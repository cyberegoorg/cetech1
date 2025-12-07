const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;
const actions = cetech1.actions;

const transform = @import("transform");
const camera = @import("camera");
const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");
const physics = @import("physics");
const light_component = @import("light_component");

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
var _actions: *const cetech1.actions.ActionsAPI = undefined;

var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;

const seed: u64 = 1111;
var prng = std.Random.DefaultPrng.init(seed);

// Global state that can surive hot-reload
const G = struct {
    init: bool = false,
    viewport: render_viewport.Viewport = undefined,
    render_pipeline: render_pipeline.RenderPipeline = undefined,

    world: ecs.World = undefined,

    // TODO: SHIT
    camera_ent: ecs.EntityId = 0,
    camera_look_activated: bool = false,
    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, -12 },
    }),

    simulatate_ui: bool = false,

    flecs_port: ?u16 = null,
};
var _g: *G = undefined;

// TODO: SHIT
const ActivatedViewportActionSet = cetech1.strId32("runner_activated_viewport");
const ViewportActionSet = cetech1.strId32("runner_viewport");
const MoveAction = cetech1.strId32("move");
const LookAction = cetech1.strId32("look");
const LookActivationAction = cetech1.strId32("look_activation");

var runner_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Runner",
    &[_]cetech1.StrId64{ .fromStr("RenderViewport"), .fromStr("GraphVMInit") }, // TODO: =(
    struct {
        pub fn init() !void {
            const w = try _ecs.createWorld();
            _g.world = w;

            _g.simulatate_ui = 1 == _kernel.getIntArgs("--simulate-ui") orelse 0;
            const simulate_pause = 1 == _kernel.getIntArgs("--simulate-pause") orelse 0;

            if (simulate_pause) w.setSimulate(false);

            _g.camera_ent = w.newEntity(null);
            _ = w.setId(transform.Position, _g.camera_ent, &transform.Position{ .x = 0, .y = 2, .z = -10 });
            _ = w.setId(transform.Rotation, _g.camera_ent, &transform.Rotation{});
            _ = w.setId(camera.Camera, _g.camera_ent, &camera.Camera{});

            const gpu_backend = _kernel.getGpuBackend().?;
            _g.viewport = try _render_viewport.createViewport("runner", gpu_backend, w, _g.camera_ent, true);
            _g.render_pipeline = try _render_pipeline.createDefault(_allocator, gpu_backend, w);

            try _actions.createActionSet(ViewportActionSet);
            try _actions.addActions(ViewportActionSet, &.{
                .{ .name = LookActivationAction, .action = .{ .button = actions.ButtonAction{} } },
            });

            try _actions.addMappings(ViewportActionSet, LookActivationAction, &.{
                .{ .gamepadAxisButton = actions.GamepadAxisButtonMapping{ .a = .right_trigger } },
                .{ .mouseButton = actions.MouseButtonMapping{ .b = .left } },
            });

            try _actions.createActionSet(ActivatedViewportActionSet);
            try _actions.addActions(ActivatedViewportActionSet, &.{
                .{ .name = MoveAction, .action = .{ .axis = actions.AxisAction{} } },
                .{ .name = LookAction, .action = .{ .axis = actions.AxisAction{} } },
            });
            try _actions.addMappings(ActivatedViewportActionSet, MoveAction, &.{
                // WSAD
                .{ .key = actions.KeyButtonMapping{ .k = .w, .axis_map = &.{ 0, 1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .s, .axis_map = &.{ 0, -1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .a, .axis_map = &.{ -1, 0 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .d, .axis_map = &.{ 1, 0 } } },

                // Arrow
                .{ .key = actions.KeyButtonMapping{ .k = .up, .axis_map = &.{ 0, 1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .down, .axis_map = &.{ 0, -1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .left, .axis_map = &.{ -1, 0 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .right, .axis_map = &.{ 1, 0 } } },

                // Dpad
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_up, .axis_map = &.{ 0, 1 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_down, .axis_map = &.{ 0, -1 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_left, .axis_map = &.{ -1, 0 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_right, .axis_map = &.{ 1, 0 } } },

                // Clasic gamepad move
                .{ .gamepadAxis = actions.GamepadAxisMapping{ .x = .left_x, .y = .left_y } },
            });
            try _actions.addMappings(ActivatedViewportActionSet, LookAction, &.{
                .{ .mouse = actions.MouseMapping{ .delta = true } },

                .{ .gamepadAxis = actions.GamepadAxisMapping{
                    .x = .right_x,
                    .y = .right_y,
                    .scale_x = 10,
                    .scale_y = 10,
                } },
            });
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

            // TODO: SHIT
            if (!_g.init) {
                _g.init = true;

                const w = _g.world;

                if (_kernel.getStrArgs("--simulate")) |uuid_str| {
                    const uuid = _uuid.fromStr(uuid_str).?;

                    const simulate_explode_num = _kernel.getIntArgs("--simulate-explode");

                    const allocator = try _tmpalloc.create();
                    defer _tmpalloc.destroy(allocator);

                    const obj = _assetdb.getObjId(uuid).?;

                    const entities = try _ecs.spawnManyFromCDB(allocator, w, obj, simulate_explode_num orelse 1);
                    defer allocator.free(entities);

                    const rnd = prng.random();

                    if (simulate_explode_num != null) {
                        // Spawn light
                        const light_ent = w.newEntity(null);
                        _ = w.setId(transform.Position, light_ent, &transform.Position{ .y = 20 });
                        _ = w.setId(light_component.Light, light_ent, &light_component.Light{ .radius = 100, .power = 10000 });

                        // Set random velocity.
                        for (entities) |ent| {
                            _ = w.setId(physics.Velocity, ent, &physics.Velocity{
                                .x = (rnd.float(f32) * 2 - 1) * 0.1,
                                .y = (rnd.float(f32) * 2 - 1) * 0.1,
                                .z = (rnd.float(f32) * 2 - 1) * 0.1,
                            });
                        }
                    }
                }
            }

            if (_kernel.getMainWindow()) |w| {
                const fb_size = w.getFramebufferSize();
                _g.viewport.setSize(.{ @floatFromInt(fb_size[0]), @floatFromInt(fb_size[1]) });

                if (_g.camera_ent != 0) {
                    const hovered = true;
                    var camera_look_activated = false;
                    {
                        _actions.pushSet(ViewportActionSet);
                        defer _actions.popSet();
                        camera_look_activated = _actions.isActionDown(LookActivationAction);
                    }

                    if (hovered and camera_look_activated) {
                        _g.camera_look_activated = true;
                        _kernel.getMainWindow().?.setCursorMode(.disabled);
                        _actions.pushSet(ActivatedViewportActionSet);
                    }

                    if (_g.camera_look_activated and !camera_look_activated) {
                        _g.camera_look_activated = false;
                        _kernel.getMainWindow().?.setCursorMode(.normal);
                        _actions.popSet();
                    }

                    if (_g.camera_look_activated) {
                        const move = _actions.getActionAxis(MoveAction);
                        const look = _actions.getActionAxis(LookAction);

                        _g.camera.update(move, look, dt);
                    }

                    _ = _g.world.setId(transform.Position, _g.camera_ent, &transform.Position{
                        .x = _g.camera.position[0],
                        .y = _g.camera.position[1],
                        .z = _g.camera.position[2],
                    });

                    _ = _g.world.setId(transform.Rotation, _g.camera_ent, &transform.Rotation{
                        .q = zm.matToQuat(zm.mul(zm.rotationX(_g.camera.pitch), zm.rotationY(_g.camera.yaw))),
                    });
                }

                _g.viewport.requestRender(_g.render_pipeline);
            }
        }
    },
);

var runner_ui_i = coreui.CoreUII.implement(struct {
    pub fn ui(allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        if (!_g.simulatate_ui) return;

        _coreui.beginMainMenuBar();
        defer _coreui.endMainMenuBar();

        _g.world.debuguiMenuItems(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            _render_viewport.uiDebugMenuItems(allocator, _g.viewport);
            _g.flecs_port = _g.world.uiRemoteDebugMenuItems(allocator, _g.flecs_port);
        }
    }
});

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
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;
    _assetdb = apidb.getZigApi(module_name, cetech1.assetdb.AssetDBAPI).?;
    _actions = apidb.getZigApi(module_name, cetech1.actions.ActionsAPI).?;

    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &runner_kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &runner_render_task, load);
    try apidb.implOrRemove(module_name, coreui.CoreUII, &runner_ui_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_runner(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
