const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const render_viewport = @import("render_viewport");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const public = @import("camera_controller.zig");
const transform = @import("transform");
const camera = @import("camera");
const actions = @import("actions");

const module_name = .camera_controller;

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
var _actions: *const actions.ActionsAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const api = public.CameraControllerAPI{};

const ActivatedViewportActionSet = cetech1.strId32("camera_controller_activated_viewport");
const ViewportActionSet = cetech1.strId32("camera_controller_viewport");
const MoveAction = cetech1.strId32("move");
const LookAction = cetech1.strId32("look");
const LookActivationAction = cetech1.strId32("look_activation");

const camera_controller_c = ecs.ComponentI.implement(
    public.CameraController,
    .{
        .category = "Renderer",
    },
    struct {},
);

const camera_controller_system_i = ecs.SystemI.implement(
    .{
        .name = "camera_controller",
        // .multi_threaded = true,
        .phase = ecs.OnUpdate,
        // .simulation = true,
        .query = &.{
            .{ .id = ecs.id(transform.Transform), .inout = .InOut },
            .{ .id = ecs.id(camera.Camera), .inout = .In },
            .{ .id = ecs.id(public.CameraController), .inout = .In },
        },
    },
    struct {
        pub fn update(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            // _ = dt;

            const tr = it.field(transform.Transform, 0).?;
            const cams = it.field(camera.Camera, 1).?;
            const controllers = it.field(public.CameraController, 2).?;

            _ = cams;

            for (0..it.count()) |i| {
                var controller = &controllers[i];
                const window = _kernel.getMainWindow();

                var camera_look_activated_new = controller.camera_look_activated;
                var camera_look_activated_now = false;

                {
                    _actions.pushSet(ViewportActionSet);
                    defer _actions.popSet();
                    camera_look_activated_now = _actions.isActionDown(LookActivationAction);
                }

                if (controller.input_enabled and camera_look_activated_now) {
                    camera_look_activated_new = true;
                    if (window) |w| w.setCursorMode(.disabled);
                    _actions.pushSet(ActivatedViewportActionSet);
                }

                if (camera_look_activated_new and !camera_look_activated_now) {
                    camera_look_activated_new = false;
                    if (window) |w| w.setCursorMode(.normal);
                    _actions.popSet();
                }

                controller.camera_look_activated = camera_look_activated_new;

                if (camera_look_activated_new) {
                    const move = _actions.getActionAxis(MoveAction);
                    const look = _actions.getActionAxis(LookAction);

                    var py = zm.quatToRollPitchYaw(tr[i].rotation.q);

                    const speed = zm.f32x4s(controller.move_speed);
                    const delta_time = zm.f32x4s(dt);

                    // Look handle
                    {
                        py[0] += controller.look_speed * dt * look[1] * -1;
                        py[1] += controller.look_speed * dt * look[0];

                        py[0] = @min(py[0], 0.48 * std.math.pi);
                        py[0] = @max(py[0], -0.48 * std.math.pi);

                        py[1] = zm.modAngle(py[1]);

                        tr[i].rotation.q = zm.quatFromRollPitchYaw(py[0], py[1], 0);
                    }

                    // Move handle
                    {
                        const t = zm.mul(zm.rotationX(py[0]), zm.rotationY(py[1]));
                        var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 1.0), t));

                        const right = speed * delta_time * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 1.0), forward));
                        forward = speed * delta_time * forward;

                        var cam_pos = zm.loadArr3(.{ tr[i].position.x, tr[i].position.y, tr[i].position.z });
                        cam_pos += forward * zm.f32x4s(move[1]);
                        cam_pos += right * zm.f32x4s(move[0]);

                        tr[i].position.x = cam_pos[0];
                        tr[i].position.y = cam_pos[1];
                        tr[i].position.z = cam_pos[2];
                    }
                }
            }
        }
    },
);

var controller_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Camera controller",
    &[_]cetech1.StrId64{actions.ACTIONS_KERNEL_TASK},
    struct {
        pub fn init() !void {
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

        pub fn shutdown() !void {}
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
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _actions = apidb.getZigApi(module_name, actions.ActionsAPI).?;

    // impl api
    try apidb.setOrRemoveZigApi(module_name, public.CameraControllerAPI, &api, load);

    // impl interface
    try apidb.implInterface(module_name, cetech1.kernel.KernelTaskI, &controller_kernel_task);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &camera_controller_c, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &camera_controller_system_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_camera_controller(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
