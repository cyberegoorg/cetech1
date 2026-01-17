const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const render_viewport = @import("render_viewport");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const math = cetech1.math;

const public = @import("bloom.zig");
const editor_inspector = @import("editor_inspector");
const transform = @import("transform");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const shader_system = @import("shader_system");
const visibility_flags = @import("visibility_flags");

const module_name = .bloom;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const cetech1.gpu.GpuBackendApi = undefined;

var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

//
// Bloom
//
const BloomComponentManager = struct {
    component: ?*public.BloomComponent = null,
    bloom_module: render_graph.Module,
};

const bloom_c = ecs.ComponentI.implement(
    public.BloomComponent,
    .{
        .display_name = "Bloom",
    },
    struct {
        pub fn createManager(world: ecs.World) !*anyopaque {
            _ = world;
            var bloom_module = try _render_graph.createModule();

            const manager = try _allocator.create(BloomComponentManager);
            manager.* = .{
                .bloom_module = bloom_module,
            };

            bloom_module.setEditorMenuUi(
                .implement(
                    "Bloom",
                    manager,
                    struct {
                        pub fn menui(alloc: std.mem.Allocator, data: *anyopaque) !void {
                            _ = alloc;
                            const mm: *const BloomComponentManager = @ptrCast(@alignCast(data));

                            if (mm.component) |bloom_component| {
                                if (_coreui.checkbox("enabled", .{ .v = &bloom_component.enabled })) {
                                    //_ = mm.world.setComponent(BloomComponent, inst.postprocess_ent, bloom_component);
                                }
                                if (_coreui.dragF32("intensity", .{ .v = &bloom_component.bloom_intensity, .min = 0, .max = std.math.floatMax(f32) })) {
                                    //_ = mm.world.setComponent(BloomComponent, inst.postprocess_ent, bloom_component);
                                }
                            }
                        }
                    },
                ),
            );

            try bloom_module.addPassWithData(
                "bloom_0_pass",
                BloomPass0Params,
                void,
                &.{
                    .manager = manager,
                },
                &bloom_0_pass_api,
            );

            const downsample_shader = _shader.findShaderByName(.fromStr("downsample")).?;
            const upsample_shader = _shader.findShaderByName(.fromStr("upsample")).?;
            const step_count = 4;

            //
            // Downsample
            //
            inline for (0..step_count) |i| {
                try bloom_module.addPassWithData(
                    std.fmt.comptimePrint("bloom_downsample_{d}", .{i + 1}),
                    BloomDownSampleParameters,
                    void,
                    &.{
                        .shader = downsample_shader,
                        .step_id = i,
                        .in_texture_name = std.fmt.comptimePrint("bloom_{d}", .{i}),
                        .out_texture_name = std.fmt.comptimePrint("bloom_{d}", .{i + 1}),
                        .manager = manager,
                    },
                    &bloom_downsample_pass_api,
                );
            }

            //
            // Upsample
            //
            inline for (0..step_count) |i| {
                try bloom_module.addPassWithData(
                    std.fmt.comptimePrint("bloom_upsample_{d}", .{i + 1}),
                    BloomUpsampleParams,
                    void,
                    &.{
                        .shader = upsample_shader,
                        .in_texture_name = std.fmt.comptimePrint("bloom_{d}", .{step_count - i}),
                        .out_texture_name = std.fmt.comptimePrint("bloom_{d}", .{step_count - i - 1}),
                        .manager = manager,
                    },
                    &bloom_upsample_pass_api,
                );
            }

            return manager;
        }
        pub fn destroyManager(world: ecs.World, manager: *anyopaque) void {
            _ = world;

            const m: *BloomComponentManager = @ptrCast(@alignCast(manager));

            _render_graph.destroyModule(m.bloom_module);

            _allocator.destroy(m);
        }
    },
);

const bloom_shaderable = render_viewport.ShaderableComponentI.implement(public.BloomComponent, struct {
    pub fn injectGraphModule(allocator: std.mem.Allocator, manager: ?*anyopaque, module: render_graph.Module) !void {
        _ = allocator;

        const m: *BloomComponentManager = @ptrCast(@alignCast(manager));

        try module.addToExtensionPoint(render_pipeline.extensions.postprocess, m.bloom_module);
    }

    pub fn fillBoundingVolumes(
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransformComponent,
        data: []*anyopaque,
        volume_type: render_viewport.BoundingVolumeType,
        volumes: []u8,
    ) !void {
        _ = allocator;
        _ = entites_idx;
        _ = transforms;

        switch (volume_type) {
            .sphere => {
                var sphere_out_volumes = std.mem.bytesAsSlice(render_viewport.SphereBoudingVolume, volumes);

                for (data, 0..) |_, idx| {
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

                for (data, 0..) |_, idx| {
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
        transforms: []transform.WorldTransformComponent,
        render_components: []*anyopaque,
        visibility: []const render_viewport.VisibilityBitField,
    ) !void {
        // _ = world;
        _ = viewport;
        _ = builder;
        _ = viewers;
        _ = transforms;
        _ = gpu_backend;
        _ = allocator;
        _ = pipeline;
        _ = visibility;
        _ = system_context;
        _ = entites_idx;

        var manager = world.getComponentManager(public.BloomComponent, BloomComponentManager).?;
        const bloom_component: *public.BloomComponent = @ptrCast(@alignCast(render_components[0]));
        manager.component = bloom_component;
    }
});

const BloomPass0Params = struct {
    manager: *BloomComponentManager,
};

const bloom_0_pass_api = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        const params: BloomPass0Params = std.mem.bytesToValue(BloomPass0Params, pass.const_data.?);

        if (params.manager.component == null or !params.manager.component.?.enabled) {
            return;
        }

        try builder.writeBlackboardValue(.fromStr("bloom_texture"), .{ .str = "bloom_0" });

        try builder.createTexture2D(
            pass,
            "bloom_0",
            .{
                .format = gpu.TextureFormat.RGBA16F,
                .flags = .{
                    .blit_dst = true,
                    .rt = .RT,
                },

                .sampler_flags = .{
                    .u = .Clamp,
                    .v = .Clamp,
                },

                .clear_depth = 1.0,
                .clear_color = .{},
            },
        );
        try builder.readTexture(pass, "hdr");

        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
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
                @intFromFloat(fb_size.x),
                @intFromFloat(fb_size.y),
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
    manager: *BloomComponentManager,
};

const bloom_downsample_pass_api = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        const params: BloomDownSampleParameters = std.mem.bytesToValue(BloomDownSampleParameters, pass.const_data.?);

        if (params.manager.component == null or !params.manager.component.?.enabled) {
            return;
        }

        try builder.createTexture2D(
            pass,
            params.out_texture_name,
            .{
                .format = gpu.TextureFormat.RGBA16F,
                .flags = .{
                    .rt = .RT,
                },
                .clear_depth = 1.0,
                .clear_color = .{},
                .ratio = 1.0 / std.math.pow(f32, 2, @floatFromInt(params.step_id + 1)),
            },
        );
        try builder.readTexture(pass, params.in_texture_name);

        try builder.setAttachment(pass, 0, params.out_texture_name);
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
        const params: BloomDownSampleParameters = std.mem.bytesToValue(BloomDownSampleParameters, pass.const_data.?);

        _ = vp_size;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            var shader_constext = try _shader.createSystemContext();
            defer _shader.destroySystemContext(shader_constext);

            // TODO:
            //e.setVertexCount(3);

            const hdr_texture = builder.getTexture(params.in_texture_name) orelse return;

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

            const projMtx = math.Mat44f.orthographicOffCenterRh(0, 1, 1, 0, 0, 100, gpu_backend.isHomogenousDepth()).toArray();
            gpu_backend.setViewTransform(viewid, null, &projMtx);

            _render_graph.screenSpaceQuad(gpu_backend, e, false, 1, 1);

            e.setState(variant.state, variant.rgba);
            e.submit(viewid, variant.prg.?, 0, .all);
        }
    }
});

const BloomUpsampleParams = struct {
    shader: shader_system.Shader,
    out_texture_name: []const u8,
    in_texture_name: []const u8,

    manager: *BloomComponentManager,
};

const bloom_upsample_pass_api = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        const params: BloomUpsampleParams = std.mem.bytesToValue(BloomUpsampleParams, pass.const_data.?);

        if (params.manager.component == null or !params.manager.component.?.enabled) {
            return;
        }

        // log.debug("{s}", .{params.out_texture_name});

        try builder.readTexture(pass, params.in_texture_name);
        try builder.writeTexture(pass, params.out_texture_name);

        try builder.setAttachment(pass, 0, params.out_texture_name);

        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
        const params: BloomUpsampleParams = std.mem.bytesToValue(BloomUpsampleParams, pass.const_data.?);
        _ = vp_size;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);

            var shader_constext = try _shader.createSystemContext();
            defer _shader.destroySystemContext(shader_constext);

            // TODO: WHYYYY NOOOOTTTTT WOOOORRRRKKKKIIIINNNGGG
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
                        params.manager.component.?.bloom_intensity,
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

            const projMtx = math.Mat44f.orthographicOffCenterRh(
                0,
                1,
                1,
                0,
                0,
                100,
                gpu_backend.isHomogenousDepth(),
            ).toArray();
            gpu_backend.setViewTransform(viewid, null, &projMtx);

            _render_graph.screenSpaceQuad(gpu_backend, e, false, 1, 1);

            e.setState(variant.state, variant.rgba);
            e.submit(viewid, variant.prg.?, 0, .all);
        }
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Bloom",
    &[_]cetech1.StrId64{ .fromStr("ShaderSystem"), .fromStr("InstanceSystem") },
    struct {
        pub fn init() !void {

            // "downsample"
            try _shader.addShaderDefiniton("downsample", .{
                .color_state = .rgba,

                .samplers = &.{
                    .{
                        .name = "default",
                        .defs = .{
                            .min_filter = .Linear,
                            .max_filter = .Linear,
                            .u = .Clamp,
                            .v = .Clamp,
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
                            .min_filter = .Linear,
                            .max_filter = .Linear,
                            .u = .Clamp,
                            .v = .Clamp,
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

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _gpu = apidb.getZigApi(module_name, cetech1.gpu.GpuBackendApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    try apidb.implOrRemove(module_name, cetech1.ecs.ComponentI, &bloom_c, load);
    try apidb.implOrRemove(module_name, render_viewport.ShaderableComponentI, &bloom_shaderable, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_bloom(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
