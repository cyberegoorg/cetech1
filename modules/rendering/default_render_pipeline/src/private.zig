const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const light_system = @import("light_system");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const render_viewport = @import("render_viewport");
const shader_system = @import("shader_system");
const camera = @import("camera");
const transform = @import("transform");
const visibility_flags = @import("visibility_flags");

const module_name = .default_render_pipeline;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

var _dd: *const gpu.GpuDDApi = undefined;
var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _light_system: *const light_system.LightSystemApi = undefined;
var _camera: *const camera.CameraAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    rg_vt: *render_pipeline.RenderPipelineI = undefined,
};
var _g: *G = undefined;

pub const TonemapType = enum(u8) {
    aces = 0,
    uncharted,
    luma_debug,
};

const TonemapParams = struct {
    type: TonemapType = .aces,
};

//
// Bloom
//
const BloomComponent = struct {
    enabled: bool = true,
    bloom_intensity: f32 = 1.0,
};

const bloom_c = ecs.ComponentI.implement(
    BloomComponent,
    .{},
    struct {},
);

const bloom_shaderable = render_viewport.ShaderableComponentI.implement(BloomComponent, struct {
    pub fn fill_bounding_volumes(
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransform,
        data: []*anyopaque,
        volume_type: render_viewport.BoundingVolumeType,
        volumes: []u8,
    ) !void {
        var blooms = try cetech1.ArrayList(*BloomComponent).initCapacity(allocator, transforms.len);
        defer blooms.deinit(allocator);
        try blooms.resize(allocator, if (entites_idx) |eidxs| eidxs.len else transforms.len);

        if (entites_idx) |idxs| {
            for (idxs, 0..) |ent_idx, idx| {
                const gi: *BloomComponent = @ptrCast(@alignCast(data[ent_idx]));
                blooms.items[idx] = gi;
            }
        } else {
            for (data, 0..) |d, idx| {
                const gi: *BloomComponent = @ptrCast(@alignCast(d));
                blooms.items[idx] = gi;
            }
        }

        switch (volume_type) {
            .sphere => {
                var sphere_out_volumes = std.mem.bytesAsSlice(render_viewport.SphereBoudingVolume, volumes);

                for (blooms.items, 0..) |_, idx| {
                    var dc_visibility_flags = visibility_flags.VisibilityFlags.initEmpty();
                    dc_visibility_flags.set(0); // TODO:

                    sphere_out_volumes[idx] = .{
                        .skip_culling = true,
                        .visibility_mask = dc_visibility_flags,
                    };
                }
            },

            .box => {
                var box_out_volumes = std.mem.bytesAsSlice(render_viewport.BoxBoudingVolume, volumes);

                for (blooms.items, 0..) |_, idx| {
                    var dc_visibility_flags = visibility_flags.VisibilityFlags.initEmpty();
                    dc_visibility_flags.set(0); // TODO:

                    box_out_volumes[idx] = .{
                        .skip_culling = true,
                        .visibility_mask = dc_visibility_flags,
                    };
                }
            },

            else => |v| {
                log.err("Invalid bounding volume {d}", .{v});
            },
        }
    }

    pub fn update(
        allocator: std.mem.Allocator,
        gpu_backend: gpu.GpuBackend,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: render_viewport.Viewport,
        pipeline: render_pipeline.RenderPipeline,
        viewers: []const render_graph.Viewer,
        system_context: *const shader_system.SystemContext,
        entites_idx: []const usize,
        transforms: []transform.WorldTransform,
        render_components: []*anyopaque,
        visibility: []const render_viewport.VisibilityBitField,
    ) !void {
        _ = world;
        _ = viewport;
        _ = builder;
        _ = viewers;
        _ = transforms;
        _ = gpu_backend;

        _ = visibility;
        _ = system_context;

        var blooms = try cetech1.ArrayList(*BloomComponent).initCapacity(allocator, entites_idx.len);
        defer blooms.deinit(allocator);
        try blooms.resize(allocator, entites_idx.len);

        var main_module = pipeline.getMainModule();

        const bloom_component: *BloomComponent = @ptrCast(@alignCast(render_components[0]));
        if (!bloom_component.enabled) return;

        const bloom_module = try _render_graph.createModule();
        try bloom_module.addPass(.{ .name = "bloom_0_pass", .api = &bloom_0_pass });

        const downsample_shader = _shader.findShaderByName(.fromStr("downsample")).?;
        const upsample_shader = _shader.findShaderByName(.fromStr("upsample")).?;
        const step_count = 4;

        //
        // Downsample
        //
        inline for (0..step_count) |i| {
            try bloom_module.addPassWithData(
                BloomDownSampleParameters,
                std.fmt.comptimePrint("bloom_downsample_{d}", .{i + 1}),
                BloomDownSampleParameters{
                    .shader = downsample_shader,
                    .step_id = i,
                    .in_texture_name = std.fmt.comptimePrint("bloom_{d}", .{i}),
                    .out_texture_name = std.fmt.comptimePrint("bloom_{d}", .{i + 1}),
                },
                &bloom_downsample_pass_api,
            );
        }

        //
        // Upsample
        //
        inline for (0..step_count) |i| {
            try bloom_module.addPassWithData(
                BloomUpsampleParams,
                std.fmt.comptimePrint("bloom_upsample_{d}", .{i + 1}),
                BloomUpsampleParams{
                    .shader = upsample_shader,
                    .in_texture_name = std.fmt.comptimePrint("bloom_{d}", .{step_count - i}),
                    .out_texture_name = std.fmt.comptimePrint("bloom_{d}", .{step_count - i - 1}),
                    .bloom_intensity = bloom_component.bloom_intensity,
                },
                &bloom_upsample_pass_api,
            );
        }

        try main_module.addToExtensionPoint(render_pipeline.extensions.postprocess, bloom_module);
    }
});

//

const depth_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "depth",
            .{
                .format = gpu.TextureFormat.D24,
                .flags = .{
                    .rt = .rt,
                },
                .sampler_flags = .{
                    .min_filter = .point,
                    .max_filter = .point,
                    .mip_mode = .point,
                    .u = .clamp,
                    .v = .clamp,
                },

                .clear_depth = 1.0,
            },
        );
        try builder.setAttachment(pass, 0, "depth");

        try builder.setMaterialLayer(pass, "depth");
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = gpu_backend;
        _ = viewid;
        _ = pass;
    }
});

const material_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "hdr",
            .{
                .format = gpu.TextureFormat.RGBA16F,
                .flags = .{
                    .rt = .rt,
                },
                .sampler_flags = .{
                    .min_filter = .point,
                    .max_filter = .point,
                    .mip_mode = .point,
                    .u = .clamp,
                    .v = .clamp,
                },
                .clear_color = 0x336680,
                // .clear_color = 0,
            },
        );
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "hdr");
        try builder.setAttachment(pass, 1, "depth");

        try builder.setMaterialLayer(pass, "color");
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = pass;
        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            e.touch(viewid);
        }
    }
});

const dd_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.writeTexture(pass, render_viewport.ColorResource);
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, render_viewport.ColorResource);
        try builder.setAttachment(pass, 1, "depth");

        try builder.setMaterialLayer(pass, "debugdraw");
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = pass;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            const dd = _dd.encoderCreate();
            defer _dd.encoderDestroy(dd);
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, 0, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
            }
        }
    }
});

const PosVertex = struct {
    x: f32,
    y: f32,
    z: f32,

    fn init(x: f32, y: f32, z: f32) PosVertex {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    fn layoutInit(gpu_backend: gpu.GpuBackend) gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = gpu_backend.layoutBegin(&L.posColorLayout);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 3, gpu.AttribType.Float, false, false);
        gpu_backend.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};
var _vertex_pos_layout: gpu.VertexLayout = undefined;
fn screenSpaceQuad(gpu_backend: gpu.GpuBackend, e: gpu.GpuEncoder, origin_mottom_left: bool, width: f32, height: f32) void {
    if (3 == gpu_backend.getAvailTransientVertexBuffer(3, &_vertex_pos_layout)) {
        var vb: gpu.TransientVertexBuffer = undefined;
        gpu_backend.allocTransientVertexBuffer(&vb, 3, &_vertex_pos_layout);
        var vertex: [*]PosVertex = @ptrCast(@alignCast(vb.data));

        const zz: f32 = 0.0;

        const minx = -width;
        const maxx = width;
        const miny = 0.0;
        const maxy = height * 2.0;

        var minv: f32 = 0.0;
        var maxv: f32 = 2.0;

        if (origin_mottom_left) {
            const temp = minv;
            minv = maxv;
            maxv = temp;

            minv -= 1.0;
            maxv -= 1.0;
        }

        vertex[0].x = minx;
        vertex[0].y = miny;
        vertex[0].z = zz;

        vertex[1].x = maxx;
        vertex[1].y = miny;
        vertex[1].z = zz;

        vertex[2].x = maxx;
        vertex[2].y = maxy;
        vertex[2].z = zz;

        e.setTransientVertexBuffer(0, &vb, 0, 3);
    }
}

const bloom_0_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.writeBlackboardValue(.fromStr("bloom_texture"), .{ .str = "bloom_0" });

        try builder.createTexture2D(
            pass,
            "bloom_0",
            .{
                .format = gpu.TextureFormat.RGBA16F,
                .flags = .{
                    .blit_dst = true,
                    .rt = .rt,
                },

                .sampler_flags = .{
                    .u = .clamp,
                    .v = .clamp,
                },

                .clear_depth = 1.0,
                .clear_color = 0,
            },
        );
        try builder.readTexture(pass, "hdr");

        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = pass;

        const fb_size = vp_size;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            const out_tex = builder.getTexture("bloom_0").?;
            const foo_tex = builder.getTexture("hdr").?;
            e.blit(
                viewid,
                out_tex,
                0,
                0,
                0,
                0,
                foo_tex,
                0,
                0,
                0,
                0,
                @intFromFloat(fb_size[0]),
                @intFromFloat(fb_size[1]),
                0,
            );
        }
    }
});

const BloomDownSampleParameters = struct {
    shader: shader_system.Shader,
    step_id: usize,
    out_texture_name: []const u8,
    in_texture_name: []const u8,
};

const bloom_downsample_pass_api = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        const params: *const BloomDownSampleParameters = @ptrCast(@alignCast(pass.data));

        try builder.createTexture2D(
            pass,
            params.out_texture_name,
            .{
                .format = gpu.TextureFormat.RGBA16F,
                .flags = .{
                    .rt = .rt,
                },
                .clear_depth = 1.0,
                .clear_color = 0,
                .ratio = 1.0 / std.math.pow(f32, 2, @floatFromInt(params.step_id + 1)),
            },
        );
        try builder.readTexture(pass, params.in_texture_name);

        try builder.setAttachment(pass, 0, params.out_texture_name);
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        const params: *const BloomDownSampleParameters = @ptrCast(@alignCast(pass.data));

        _ = vp_size;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            var shader_constext = try _shader.createSystemContext();
            defer _shader.destroySystemContext(shader_constext);

            // TODO:
            //e.setVertexCount(3);

            const hdr_texture = builder.getTexture(params.in_texture_name).?;

            const shader = params.shader;

            const shader_io = _shader.getShaderIO(shader);

            const rb = (try _shader.createResourceBuffer(shader_io)).?;
            defer _shader.destroyResourceBuffer(shader_io, rb);

            try _shader.updateResources(
                shader_io,
                rb,
                &.{.{ .name = .fromStr("tex"), .value = .{ .texture = hdr_texture } }},
            );

            _shader.bindResource(shader_io, rb, e);

            var allocator = try _tmpalloc.create();
            defer _tmpalloc.destroy(allocator);

            const variants = try _shader.selectShaderVariant(
                allocator,
                shader,
                &.{.fromStr("viewport")},
                &shader_constext,
            );
            defer allocator.free(variants);
            const variant = variants[0];

            const projMtx = zm.matToArr(zm.orthographicOffCenterRh(0, 1, 1, 0, 0, 100));
            gpu_backend.setViewTransform(viewid, null, &projMtx);

            screenSpaceQuad(gpu_backend, e, false, 1, 1);

            e.setState(variant.state, variant.rgba);
            e.submit(viewid, variant.prg.?, 0, .{});
        }
    }
});

const BloomUpsampleParams = struct {
    shader: shader_system.Shader,
    out_texture_name: []const u8,
    in_texture_name: []const u8,

    bloom_intensity: f32 = 1.0,
};

const bloom_upsample_pass_api = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        const params: *const BloomUpsampleParams = @ptrCast(@alignCast(pass.data));

        try builder.readTexture(pass, params.in_texture_name);
        try builder.writeTexture(pass, params.out_texture_name);

        try builder.setAttachment(pass, 0, params.out_texture_name);
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        const params: *const BloomUpsampleParams = @ptrCast(@alignCast(pass.data));
        _ = vp_size;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            var shader_constext = try _shader.createSystemContext();
            defer _shader.destroySystemContext(shader_constext);

            // TODO:
            //e.setVertexCount(3);

            const hdr_texture = builder.getTexture(params.in_texture_name).?;

            const shader = params.shader;

            const shader_io = _shader.getShaderIO(shader);

            const rb = (try _shader.createResourceBuffer(shader_io)).?;
            defer _shader.destroyResourceBuffer(shader_io, rb);

            try _shader.updateResources(
                shader_io,
                rb,
                &.{.{ .name = .fromStr("tex"), .value = .{ .texture = hdr_texture } }},
            );
            _shader.bindResource(shader_io, rb, e);

            const ub = (try _shader.createUniformBuffer(shader_io)).?;
            defer _shader.destroyUniformBuffer(shader_io, ub);
            try _shader.updateUniforms(shader_io, ub, &.{
                .{
                    .name = .fromStr("intensity"),
                    .value = std.mem.asBytes(&[4]f32{
                        params.bloom_intensity,
                        0,
                        0,
                        0,
                    }),
                },
            });
            _shader.bindConstant(shader_io, ub, e);

            var allocator = try _tmpalloc.create();
            defer _tmpalloc.destroy(allocator);

            const variants = try _shader.selectShaderVariant(
                allocator,
                shader,
                &.{.fromStr("viewport")},
                &shader_constext,
            );
            defer allocator.free(variants);
            const variant = variants[0];

            const projMtx = zm.matToArr(zm.orthographicOffCenterRh(0, 1, 1, 0, 0, 100));
            gpu_backend.setViewTransform(viewid, null, &projMtx);

            screenSpaceQuad(gpu_backend, e, false, 1, 1);

            e.setState(variant.state, variant.rgba);
            e.submit(viewid, variant.prg.?, 0, .{});
        }
    }
});

const tonemap_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.readTexture(pass, "hdr");

        if (builder.readBlackboardValue(.fromStr("bloom_texture"))) |bloom| {
            try builder.readTexture(pass, bloom.str);
        }

        try builder.writeTexture(pass, render_viewport.ColorResource);

        try builder.setAttachment(pass, 0, render_viewport.ColorResource);

        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        const params: *const TonemapParams = @ptrCast(@alignCast(pass.data));

        _ = vp_size;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            var shader_constext = try _shader.createSystemContext();
            defer _shader.destroySystemContext(shader_constext);

            // TODO:
            //e.setVertexCount(3);

            const hdr_texture = builder.getTexture("hdr").?;

            const shader = _shader.findShaderByName(.fromStr("tonemaping")).?;

            const shader_io = _shader.getShaderIO(shader);

            const ub = (try _shader.createUniformBuffer(shader_io)).?;
            defer _shader.destroyUniformBuffer(shader_io, ub);

            const rb = (try _shader.createResourceBuffer(shader_io)).?;
            defer _shader.destroyResourceBuffer(shader_io, rb);

            try _shader.updateResources(
                shader_io,
                rb,
                &.{
                    .{ .name = .fromStr("hdr"), .value = .{ .texture = hdr_texture } },
                },
            );
            const bloom_texture_name = builder.readBlackboardValue(.fromStr("bloom_texture"));
            if (bloom_texture_name) |bloom| {
                const bloom_texture = builder.getTexture(bloom.str).?;
                try _shader.updateResources(
                    shader_io,
                    rb,
                    &.{
                        .{ .name = .fromStr("bloom"), .value = .{ .texture = bloom_texture } },
                    },
                );
            }

            try _shader.updateUniforms(
                shader_io,
                ub,
                &.{.{ .name = .fromStr("params"), .value = std.mem.asBytes(
                    &[4]f32{
                        @bitCast(@as(u32, @intFromEnum(params.type))),
                        @bitCast(@as(u32, @intFromBool(bloom_texture_name != null))),
                        0,
                        0,
                    },
                ) }},
            );

            _shader.bindConstant(shader_io, ub, e);
            _shader.bindResource(shader_io, rb, e);

            var allocator = try _tmpalloc.create();
            defer _tmpalloc.destroy(allocator);

            const variants = try _shader.selectShaderVariant(
                allocator,
                shader,
                &.{.fromStr("viewport")},
                &shader_constext,
            );
            defer allocator.free(variants);
            const variant = variants[0];

            const projMtx = zm.matToArr(zm.orthographicOffCenterRh(0, 1, 1, 0, 0, 100));
            gpu_backend.setViewTransform(viewid, null, &projMtx);

            screenSpaceQuad(gpu_backend, e, false, 1, 1);

            e.setState(variant.state, variant.rgba);
            e.submit(viewid, variant.prg.?, 0, .{});
        }
    }
});

const DefaultPipelineInst = struct {
    allocator: std.mem.Allocator,

    gpu: gpu.GpuBackend,

    time_system: shader_system.System = undefined,
    time_system_uniforms: shader_system.UniformBufferInstance = undefined,

    light_system: light_system.LightSystem = undefined,

    main_module: render_graph.Module = undefined,

    //
    tonemap_params: TonemapParams = .{},

    //
    world: ecs.World = undefined,
    postprocess_ent: ecs.EntityId = 0,
};

const render_pipeline_i = render_pipeline.RenderPipelineI.implement(struct {
    pub fn create(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: ecs.World) !*anyopaque {
        const inst = try allocator.create(DefaultPipelineInst);

        const time_system = _shader.findSystemByName(.fromStr("time_system")).?;
        const time_system_io = _shader.getSystemIO(time_system);

        const pp_ent = world.newEntity("postprocess");
        _ = world.setId(transform.Position, pp_ent, &transform.Position{});
        _ = world.setId(BloomComponent, pp_ent, &BloomComponent{});

        inst.* = .{
            .allocator = allocator,
            .world = world,
            .time_system = time_system,
            .time_system_uniforms = (try _shader.createUniformBuffer(time_system_io)).?,

            .light_system = try _light_system.createLightSystem(gpu_backend),
            .main_module = try _render_graph.createModule(),

            .postprocess_ent = pp_ent,
            .gpu = gpu_backend,
        };
        return inst;
    }

    pub fn destroy(pipeline: *anyopaque) void {
        var inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        const time_system_io = _shader.getSystemIO(inst.time_system);
        _shader.destroyUniformBuffer(time_system_io, inst.time_system_uniforms);

        _light_system.destroyLightSystem(inst.light_system, inst.gpu);
        _render_graph.destroyModule(inst.main_module);

        inst.world.destroyEntities(&.{inst.postprocess_ent});

        inst.allocator.destroy(inst);
    }

    pub fn fillModule(pipeline: *anyopaque, module: render_graph.Module) !void {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        try module.addExtensionPoint(render_pipeline.extensions.init);
        try module.addExtensionPoint(render_pipeline.extensions.render);
        try module.addExtensionPoint(render_pipeline.extensions.postprocess);
        try module.addExtensionPoint(render_pipeline.extensions.dd);

        // Geometry passes
        {
            const render_module = try _render_graph.createModule();
            try render_module.addPass(.{ .name = "depth_pass", .api = &depth_pass });
            try render_module.addPass(.{ .name = "material_pass", .api = &material_pass });
            try module.addToExtensionPoint(render_pipeline.extensions.render, render_module);
        }

        //
        // Tonemap hdr output
        //
        {
            const tonemap_module = try _render_graph.createModule();
            try tonemap_module.addPass(.{ .name = "bloom_0_pass", .api = &bloom_0_pass });

            try tonemap_module.addPassWithData(TonemapParams, "tonemap", inst.tonemap_params, &tonemap_pass);

            // DD draw after tonemap
            // TODO: move out to dd module
            try tonemap_module.addPass(.{ .name = "dd_pass", .api = &dd_pass });

            try module.addToExtensionPoint(render_pipeline.extensions.postprocess, tonemap_module);
        }
    }

    pub fn getMainModule(pipeline: *anyopaque) render_graph.Module {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));
        return inst.main_module;
    }

    pub fn begin(pipeline: *anyopaque, context: *shader_system.SystemContext, now_s: f32) !void {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        try inst.main_module.cleanup();
        try @This().fillModule(pipeline, inst.main_module);

        // Time system
        try context.addSystem(inst.time_system, inst.time_system_uniforms, null);
        const system_io = _shader.getSystemIO(inst.time_system);

        try _shader.updateUniforms(
            system_io,
            inst.time_system_uniforms,
            &.{.{ .name = .fromStr("time"), .value = std.mem.asBytes(&[4]f32{ now_s, 0, 0, 0 }) }},
        );

        // Light system
        try context.addSystem(inst.light_system.system, inst.light_system.uniforms, inst.light_system.resources);
    }

    pub fn end(pipeline: *anyopaque, context: *shader_system.SystemContext) !void {
        _ = pipeline;
        _ = context;
    }

    pub fn uiDebugMenuItems(pipeline: *anyopaque, allocator: std.mem.Allocator) void {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        //
        // Bloom
        //
        if (inst.world.getMutComponent(BloomComponent, inst.postprocess_ent)) |bloom_component| {
            if (_coreui.beginMenu(allocator, coreui.Icons.RenderPipeline ++ "  " ++ "Bloom", true, null)) {
                defer _coreui.endMenu();

                if (_coreui.checkbox("enabled", .{ .v = &bloom_component.enabled })) {
                    _ = inst.world.setId(BloomComponent, inst.postprocess_ent, bloom_component);
                }
                if (_coreui.dragF32("intensity", .{ .v = &bloom_component.bloom_intensity, .min = 0, .max = std.math.floatMax(f32) })) {
                    _ = inst.world.setId(BloomComponent, inst.postprocess_ent, bloom_component);
                }
            }
        }

        //
        // Tonemap
        //
        const enum_str = "aces\x00uncharted\x00luma_debug\x00";
        if (_coreui.beginMenu(allocator, coreui.Icons.RenderPipeline ++ "  " ++ "Tonemaping", true, null)) {
            defer _coreui.endMenu();

            var cur_idx: i32 = @intCast(@intFromEnum(inst.tonemap_params.type));
            if (_coreui.combo("", .{
                .current_item = &cur_idx,
                .items_separated_by_zeros = enum_str,
            })) {
                inst.tonemap_params.type = @enumFromInt(cur_idx);
            }
        }
    }

    pub fn getGlobalSystem(pipeline: *anyopaque, name: cetech1.StrId32) ?*anyopaque {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        if (name.eql(.fromStr("light_system"))) {
            return &inst.light_system;
        }

        return null;
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "DefaultRenderPipeline",
    &[_]cetech1.StrId64{ .fromStr("ShaderSystem"), .fromStr("InstanceSystem") },
    struct {
        pub fn init() !void {
            _vertex_pos_layout = PosVertex.layoutInit(_kernel.getGpuBackend().?);

            // Time system
            try _shader.addSystemDefiniton("time_system", .{
                .imports = &.{
                    .{ .name = "time", .type = .vec4 },
                },
            });

            //
            // Lit shader node
            //
            try _shader.addShaderDefiniton("node_pbr_lit", .{
                .color_state = .rgb,
                .raster_state = .{
                    .cullmode = .back,
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = true,
                    .depth_comapre_op = .equal,
                },

                .graph_node = .{
                    .name = "node_pbr_lit",
                    .display_name = "PBR Lit",
                    .category = "PBR",

                    .inputs = &.{
                        // Vertexs
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = shader_system.TranspileStages.Vertex },

                        // Surface
                        .{ .name = "albedo", .display_name = "Albedo", .type = .vec4, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "emissive", .display_name = "Emissive", .type = .vec3, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "roughness", .display_name = "Roughness", .type = .float, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "metallic", .display_name = "Metallic", .type = .float, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "occlusion", .display_name = "Occlusion", .type = .float, .stage = shader_system.TranspileStages.Fragment },
                    },
                },

                .vertex_block = .{
                    .imports = &.{
                        // .position,
                        // .color0,
                    },
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                        .{ .name = "world_position", .type = .vec3 },
                        .{ .name = "normal", .type = .vec3 },
                    },
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph, vertex_ctx);
                    \\  ct_graph_eval(graph, input);
                    \\  
                    \\  mat4 model = load_model_transform(input, input.instance_id);
                    \\
                    \\  #if CT_PIN_CONNECTED(position)
                    \\      //output.position = graph.position;
                    \\      output.position = mul(model, load_vertex_position(vertex_ctx, input.vertex_id, 0));
                    \\  #else
                    \\      output.position = mul(model, load_vertex_position(vertex_ctx, input.vertex_id, 0));
                    \\  #endif
                    \\
                    \\  output.world_position = output.position;
                    \\
                    \\  const mat3 normal_matrix = cofactor(model);
                    \\  output.normal = normalize(load_vertex_normal0(vertex_ctx, input.vertex_id, 0) * normal_matrix);
                    \\
                    \\  output.position = mul(u_viewProj, output.position);
                    \\  output.color0 = load_vertex_color0(vertex_ctx, input.vertex_id, 0);
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\
                    \\  ct_graph_eval(graph, input);
                    \\
                    \\  const vec3 wp = input.world_position;
                    \\  const vec3 V = normalize(load_camera_pos() - wp);
                    \\  const vec3 N = input.normal;
                    \\
                    \\  ct_pbr_material mat;
                    \\  #if CT_PIN_CONNECTED(albedo)
                    \\      mat.albedo = graph.albedo;
                    \\  #else
                    \\      mat.albedo = vec4(1, 0, 0, 1);
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(emissive)
                    \\      mat.emissive = graph.emissive;
                    \\  #else
                    \\      mat.emissive = vec3(0, 0, 0);
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(roughness)
                    \\      mat.roughness = graph.roughness;
                    \\  #else
                    \\      mat.roughness = 0.0;
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(metallic)
                    \\      mat.metallic = graph.metallic;
                    \\  #else
                    \\      mat.metallic = 0.0;
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(occlusion)
                    \\      mat.occlusion = graph.occlusion;
                    \\  #else
                    \\      mat.occlusion = 1.0;
                    \\  #endif
                    \\  const vec3 out_rad = pbr_calc_out_radiance(V, N, wp, mat);
                    \\
                    \\  output.color0 = vec4(out_rad, 1.0);
                    \\
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system", "light_system" } },
                            },
                        },
                        .{
                            .name = "depth",
                            .variations = &.{
                                .{
                                    // TODO: Remove light system, need fragment (null fragmen?)?
                                    .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system", "light_system" },
                                    .depth_stencil_state = .{
                                        .depth_write_enable = true,
                                        .depth_test_enable = true,
                                        .depth_comapre_op = .less,
                                    },
                                },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .layer = "color", .config = "default" },
                                .{ .layer = "depth", .config = "depth" },
                            },
                        },
                    },
                },
            });

            //
            // Unlit shader node
            //
            try _shader.addShaderDefiniton("node_unlit", .{
                .color_state = .rgb,
                .raster_state = .{
                    .cullmode = .back,
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = true,
                    .depth_comapre_op = .equal,
                },

                .graph_node = .{
                    .name = "node_unlit",
                    .display_name = "Unlit",
                    .category = "PBR",

                    .inputs = &.{
                        // Vertexs
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = shader_system.TranspileStages.Vertex },

                        // Surface
                        .{ .name = "color", .display_name = "Color", .type = .vec4, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "emissive", .display_name = "Emissive", .type = .vec3, .stage = shader_system.TranspileStages.Fragment },
                    },
                },

                .vertex_block = .{
                    .imports = &.{
                        // .position,
                        // .color0,
                    },
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                        .{ .name = "world_position", .type = .vec3 },
                        .{ .name = "normal", .type = .vec3 },
                    },
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph, vertex_ctx);
                    \\  ct_graph_eval(graph, input);
                    \\  
                    \\  mat4 model = load_model_transform(input, input.instance_id);
                    \\
                    \\  #if CT_PIN_CONNECTED(position)
                    \\      //output.position = graph.position;
                    \\      output.position = mul(model, load_vertex_position(vertex_ctx, input.vertex_id, 0));
                    \\  #else
                    \\      output.position = mul(model, load_vertex_position(vertex_ctx, input.vertex_id, 0));
                    \\  #endif
                    \\
                    \\  output.world_position = output.position;
                    \\
                    \\  const mat3 normal_matrix = cofactor(model);
                    \\  output.normal = normalize(load_vertex_normal0(vertex_ctx, input.vertex_id, 0) * normal_matrix);
                    \\
                    \\  output.position = mul(u_viewProj, output.position);
                    \\  output.color0 = load_vertex_color0(vertex_ctx, input.vertex_id, 0);
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\
                    \\  ct_graph_eval(graph, input);
                    \\  
                    \\  vec4 color = vec4_splat(0);
                    \\  #if CT_PIN_CONNECTED(color)
                    \\      color = graph.color;
                    \\  #endif
                    \\
                    \\  vec3 emissive = vec3_splat(0);
                    \\  #if CT_PIN_CONNECTED(emissive)
                    \\      emissive = graph.emissive;
                    \\  #endif
                    \\  
                    \\  output.color0 = color + vec4(emissive, 1);
                    \\
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system" } },
                            },
                        },
                        .{
                            .name = "depth",
                            .variations = &.{
                                .{
                                    .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system" },
                                    .depth_stencil_state = .{
                                        .depth_write_enable = true,
                                        .depth_test_enable = true,
                                        .depth_comapre_op = .less,
                                    },
                                },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .layer = "color", .config = "default" },
                                .{ .layer = "depth", .config = "depth" },
                            },
                        },
                    },
                },
            });

            // "tonemaping"
            try _shader.addShaderDefiniton("tonemaping", .{
                .color_state = .rgba,

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = false,
                },
                .imports = &.{
                    .{ .name = "hdr", .type = .sampler2d },
                    .{ .name = "bloom", .type = .sampler2d },
                    .{ .name = "params", .type = .vec4 },
                },
                .vertex_block = .{
                    .imports = &.{
                        .position,
                    },
                    .import_semantic = &.{.vertex_id},
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                    },
                    .code =
                    \\  output.position = mul(u_modelViewProj, vec4(a_position, 1.0));
                    ,
                },
                .fragment_block = .{
                    .common_block = @embedFile("shaders/fs_tonemap_common_block.glsl"),
                    .code = @embedFile("shaders/fs_tonemap_block.glsl"),
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{} },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .config = "default" },
                            },
                        },
                    },
                },
            });

            // "downsample"
            try _shader.addShaderDefiniton("downsample", .{
                .color_state = .rgba,

                .samplers = &.{
                    .{
                        .name = "default",
                        .defs = .{
                            .min_filter = .linear,
                            .max_filter = .linear,
                            .u = .clamp,
                            .v = .clamp,
                        },
                    },
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = false,
                },
                .imports = &.{
                    .{ .name = "tex", .type = .sampler2d, .sampler = "default" },
                },
                .vertex_block = .{
                    .imports = &.{
                        .position,
                    },
                    .import_semantic = &.{.vertex_id},
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                    },
                    .code =
                    \\  output.position = mul(u_modelViewProj, vec4(a_position, 1.0));
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  vec2 halfpixel = 0.5 * vec2(u_viewTexel.x, u_viewTexel.y);
                    \\  vec2 oneepixel = 1.0 * vec2(u_viewTexel.x, u_viewTexel.y);
                    \\
                    \\  vec2 uv = gl_FragCoord.xy * u_viewTexel.xy;
                    \\
                    \\  vec4 sum = vec4_splat(0.0);
                    \\
                    \\  sum += (4.0/32.0) * texture2D(get_tex_sampler(), uv).rgba;
                    \\
                    \\  sum += (4.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(-halfpixel.x, -halfpixel.y) );
                    \\  sum += (4.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(+halfpixel.x, +halfpixel.y) );
                    \\  sum += (4.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(+halfpixel.x, -halfpixel.y) );
                    \\  sum += (4.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(-halfpixel.x, +halfpixel.y) );
                    \\
                    \\  sum += (2.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(+oneepixel.x, 0.0) );
                    \\  sum += (2.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(-oneepixel.x, 0.0) );
                    \\  sum += (2.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(0.0, +oneepixel.y) );
                    \\  sum += (2.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(0.0, -oneepixel.y) );
                    \\
                    \\  sum += (1.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(+oneepixel.x, +oneepixel.y) );
                    \\  sum += (1.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(-oneepixel.x, +oneepixel.y) );
                    \\  sum += (1.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(+oneepixel.x, -oneepixel.y) );
                    \\  sum += (1.0/32.0) * texture2D(get_tex_sampler(), uv + vec2(-oneepixel.x, -oneepixel.y) );
                    \\
                    \\  output.color0.xyzw = sum;
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{} },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .config = "default" },
                            },
                        },
                    },
                },
            });

            // "upsample"
            try _shader.addShaderDefiniton("upsample", .{
                .color_state = .rgba,
                .blend_state = .{
                    .source_color_factor = .One,
                    .destination_color_factor = .One,
                    .source_alpha_factor = .One,
                    .destination_alpha_factor = .One,
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = false,
                },

                .samplers = &.{
                    .{
                        .name = "default",
                        .defs = .{
                            .min_filter = .linear,
                            .max_filter = .linear,
                            .u = .clamp,
                            .v = .clamp,
                        },
                    },
                },

                .imports = &.{
                    .{ .name = "tex", .type = .sampler2d, .sampler = "default" },
                    .{ .name = "intensity", .type = .vec4 },
                },
                .vertex_block = .{
                    .imports = &.{
                        .position,
                    },
                    .import_semantic = &.{.vertex_id},
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                    },
                    .code =
                    \\  output.position = mul(u_modelViewProj, vec4(a_position, 1.0));
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  vec2 halfpixel = u_viewTexel.xy;
                    \\  vec2 uv = gl_FragCoord.xy * u_viewTexel.xy;
                    \\
                    \\  vec4 sum = vec4_splat(0.0);
                    \\
                    \\  sum += (2.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2(-halfpixel.x,  0.0) );
                    \\  sum += (2.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2( 0.0,          halfpixel.y) );
                    \\  sum += (2.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2( halfpixel.x,  0.0) );
                    \\  sum += (2.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2( 0.0,         -halfpixel.y) );
                    \\
                    \\  sum += (1.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2(-halfpixel.x, -halfpixel.y) );
                    \\  sum += (1.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2(-halfpixel.x,  halfpixel.y) );
                    \\  sum += (1.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2( halfpixel.x, -halfpixel.y) );
                    \\  sum += (1.0 / 16.0) * texture2D(get_tex_sampler(), uv + vec2( halfpixel.x,  halfpixel.y) );
                    \\
                    \\  sum += (4.0 / 16.0) * texture2D(get_tex_sampler(), uv);
                    \\
                    \\  output.color0.xyzw = load_intensity().x * sum;
                    \\
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{} },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .config = "default" },
                            },
                        },
                    },
                },
            });
        }

        pub fn shutdown() !void {}
    },
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _apidb = apidb;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _light_system = apidb.getZigApi(module_name, light_system.LightSystemApi).?;
    _camera = apidb.getZigApi(module_name, camera.CameraAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.ecs.ComponentI, &bloom_c, load);
    try apidb.implOrRemove(module_name, render_viewport.ShaderableComponentI, &bloom_shaderable, load);

    _g.rg_vt = try apidb.setGlobalVarValue(render_pipeline.RenderPipelineI, module_name, "rg_vt", render_pipeline_i);
    try apidb.implOrRemove(module_name, render_pipeline.RenderPipelineI, _g.rg_vt, load);

    // impl interface

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_default_render_pipeline(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
