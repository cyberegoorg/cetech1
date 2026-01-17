const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const transform = @import("transform");
const camera = @import("camera");
const camera_controller = @import("camera_controller");
const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");
const light_component = @import("light_component");
const physics = @import("physics");

const public = @import("runner.zig");

const module_name = .runner;

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
var _gpu: *const cetech1.gpu.GpuBackendApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _uuid: *const cetech1.uuid.UuidAPI = undefined;
var _assetdb: *const cetech1.assetdb.AssetDBAPI = undefined;

var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    init: bool = false,
    viewport: render_viewport.Viewport = undefined,
    render_pipeline: render_pipeline.RenderPipeline = undefined,

    world: ecs.World = undefined,

    // TODO: SHIT
    camera_ent: ecs.EntityId = 0,
};
var _g: *G = undefined;

var runner_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Runner",
    &[_]cetech1.StrId64{ .fromStr("RenderViewport"), .fromStr("GraphVMInit") }, // TODO: =(
    struct {
        pub fn init() !void {
            const w = try _ecs.createWorld();
            _g.world = w;

            // TODO: SHIT
            _g.camera_ent = w.newEntity(.{});
            _ = w.setComponent(transform.LocalTransformComponent, _g.camera_ent, &transform.LocalTransformComponent{ .local = .{ .position = .{ .y = 2, .z = -10 } } });
            _ = w.setComponent(camera.Camera, _g.camera_ent, &camera.Camera{});

            const gpu_backend = _kernel.getGpuBackend().?;
            _g.render_pipeline = try _render_pipeline.createDefault(_allocator, gpu_backend, w);

            _g.viewport = try _render_viewport.createViewport("runner", gpu_backend, _g.render_pipeline, w, true);
            _g.viewport.setMainCamera(_g.camera_ent);
        }

        pub fn shutdown() !void {
            _render_viewport.destroyViewport(_g.viewport);
            _g.render_pipeline.deinit();
            _ecs.destroyWorld(_g.world);
        }
    },
);

var runner_render_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.PreStore,
    "Runner: render",
    &[_]cetech1.StrId64{},
    0,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            if (_kernel.getMainWindow()) |w| {
                const fb_size = w.getFramebufferSize();
                _g.viewport.setSize(.{ .x = @floatFromInt(fb_size[0]), .y = @floatFromInt(fb_size[1]) });
                _g.viewport.requestRender();
            }
        }
    },
);

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
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;
    _assetdb = apidb.getZigApi(module_name, cetech1.assetdb.AssetDBAPI).?;

    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;

    // impl interface

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &runner_kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &runner_render_task, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_runner(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
