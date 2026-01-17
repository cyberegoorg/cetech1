const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

const render_viewport = @import("render_viewport");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const public = @import("tonemap.zig");
const editor_inspector = @import("editor_inspector");
const transform = @import("transform");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const shader_system = @import("shader_system");
const visibility_flags = @import("visibility_flags");

const module_name = .tonemap;

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
var _dd: *const cetech1.gpu.GpuDDApi = undefined;

var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const TonemapComponentManager = struct {
    component: ?*public.TonemapComponent = null,
    tonemap_module: render_graph.Module,
};

const tonemap_c = ecs.ComponentI.implement(
    public.TonemapComponent,
    .{
        .display_name = "Tonemap",
    },
    struct {
        pub fn createManager(world: ecs.World) !*anyopaque {
            _ = world;
            var tonemap_module = try _render_graph.createModule();

            const manager = try _allocator.create(TonemapComponentManager);
            manager.* = .{
                .tonemap_module = tonemap_module,
            };

            tonemap_module.setEditorMenuUi(
                .implement(
                    "Tonemap",
                    manager,
                    struct {
                        pub fn menui(alloc: std.mem.Allocator, data: *anyopaque) !void {
                            _ = alloc;
                            const mm: *const TonemapComponentManager = @ptrCast(@alignCast(data));

                            if (mm.component) |tonemap_component| {
                                if (_coreui.comboFromEnum("", &tonemap_component.type)) {}
                            }
                        }
                    },
                ),
            );

            try tonemap_module.addPassWithData(
                "tonemap",
                TonemapParams,
                void,
                &.{
                    .manager = manager,
                },
                &tonemap_pass_api,
            );

            try tonemap_module.addPass(.{ .name = "dd_pass", .api = &dd_pass });

            return manager;
        }
        pub fn destroyManager(world: ecs.World, manager: *anyopaque) void {
            _ = world;

            const m: *TonemapComponentManager = @ptrCast(@alignCast(manager));

            _render_graph.destroyModule(m.tonemap_module);

            _allocator.destroy(m);
        }
    },
);

const dd_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.writeTexture(pass, render_viewport.ColorResource);
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, render_viewport.ColorResource);
        try builder.setAttachment(pass, 1, "depth");

        try builder.setMaterialLayer(pass, "debugdraw");
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
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

                dd.drawGridAxis(.Y, .{}, 128, 1);
                dd.drawAxis(.{}, 1.0, .Count, 0);
            }
        }
    }
});

const tonemap_shaderable = render_viewport.ShaderableComponentI.implement(public.TonemapComponent, struct {
    pub fn injectGraphModule(allocator: std.mem.Allocator, manager: ?*anyopaque, module: render_graph.Module) !void {
        _ = allocator;

        const m: *TonemapComponentManager = @ptrCast(@alignCast(manager));

        try module.addToExtensionPoint(render_pipeline.extensions.postprocess, m.tonemap_module);
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

        var manager = world.getComponentManager(public.TonemapComponent, TonemapComponentManager).?;
        const tonemap_component: *public.TonemapComponent = @ptrCast(@alignCast(render_components[0]));
        manager.component = tonemap_component;
    }
});

const TonemapParams = struct {
    manager: *TonemapComponentManager,
};

const tonemap_pass_api = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.readTexture(pass, "hdr");

        if (builder.readBlackboardValue(.fromStr("bloom_texture"))) |name| {
            try builder.readTexture(pass, name.str);
        }

        try builder.writeTexture(pass, render_viewport.ColorResource);

        try builder.setAttachment(pass, 0, render_viewport.ColorResource);

        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
        const params: TonemapParams = std.mem.bytesToValue(TonemapParams, pass.const_data.?);

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
            if (bloom_texture_name) |name| {
                const bloom_texture = builder.getTexture(name.str).?;
                try _shader.updateResources(
                    shader_io,
                    rb,
                    &.{
                        .{ .name = .fromStr("bloom"), .value = .{ .texture = bloom_texture } },
                    },
                );
            }

            const tonemap_type = if (params.manager.component) |c| c.type else .aces;

            try _shader.updateUniforms(
                shader_io,
                ub,
                &.{.{ .name = .fromStr("params"), .value = std.mem.asBytes(
                    &[4]f32{
                        @bitCast(@as(u32, @intFromEnum(tonemap_type))),
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
    "Tonemap",
    &[_]cetech1.StrId64{ .fromStr("ShaderSystem"), .fromStr("InstanceSystem") },
    struct {
        pub fn init() !void {
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
    _dd = apidb.getZigApi(module_name, cetech1.gpu.GpuDDApi).?;
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

    try apidb.implOrRemove(module_name, cetech1.ecs.ComponentI, &tonemap_c, load);
    try apidb.implOrRemove(module_name, render_viewport.ShaderableComponentI, &tonemap_shaderable, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_tonemap(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
