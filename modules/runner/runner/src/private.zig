const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const apidb = cetech1.apidb;

const kernel = cetech1.kernel;
const transform = @import("transform");
const camera = @import("camera");
const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");

const public = @import("runner.zig");

const module_name = .runner;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

const tempalloc = cetech1.tempalloc;
const profiler = cetech1.profiler;

const uuid = cetech1.uuid;

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
            const w = try ecs.createWorld();
            _g.world = w;

            // TODO: SHIT
            _g.camera_ent = w.newEntity(.{});
            _ = w.setComponent(transform.LocalTransformComponent, _g.camera_ent, &transform.LocalTransformComponent{ .local = .{ .position = .{ .y = 2, .z = -10 } } });
            _ = w.setComponent(camera.Camera, _g.camera_ent, &camera.Camera{});

            const gpu_backend = kernel.getGpuBackend().?;
            _g.render_pipeline = try render_pipeline.createDefault(_allocator, gpu_backend, w);

            _g.viewport = try render_viewport.createViewport("runner", gpu_backend, _g.render_pipeline, w, true);
            _g.viewport.setMainCamera(_g.camera_ent);
        }

        pub fn shutdown() !void {
            render_viewport.destroyViewport(_g.viewport);
            _g.render_pipeline.deinit();
            ecs.destroyWorld(_g.world);
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

            if (kernel.getMainWindow()) |w| {
                const fb_size = w.getFramebufferSize();
                _g.viewport.setSize(.{ .x = @floatFromInt(fb_size[0]), .y = @floatFromInt(fb_size[1]) });
                _g.viewport.requestRender();
            }
        }
    },
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try kernel.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);

    try ecs.loadAPI(module_name);
    try profiler.loadAPI(module_name);
    try uuid.loadAPI(module_name);
    try assetdb.loadAPI(module_name);

    try render_viewport.loadAPI(module_name);
    try render_pipeline.loadAPI(module_name);

    // impl interface

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &runner_kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &runner_render_task, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_runner(apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb_, allocator, load, reload);
}
