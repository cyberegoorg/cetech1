const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const render_viewport = @import("render_viewport");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const math = cetech1.math;

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
var _transform: *const transform.TransformApi = undefined;

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
            .{ .id = ecs.id(transform.LocalTransformComponent), .inout = .InOut },
            .{ .id = ecs.id(camera.Camera), .inout = .In },
            .{ .id = ecs.id(public.CameraController), .inout = .InOut },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            // _ = world;
            // _ = dt;

            const ents = it.entities();
            const local_tranforms = it.field(transform.LocalTransformComponent, 0).?;
            // const cameras = it.field(camera.Camera, 1).?;
            const controllers = it.field(public.CameraController, 2).?;

            for (ents, local_tranforms, controllers) |ent, *local_tranform, *controller| {
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
                    var py = local_tranform.local.rotation.toRollPitchYaw();

                    switch (controller.type) {
                        .free_flight => {
                            // Look handle
                            {
                                py.x += controller.look_speed * dt * look.y * -1;
                                py.y += controller.look_speed * dt * look.x;

                                py.x = @min(py.x, 0.48 * std.math.pi);
                                py.x = @max(py.x, -0.48 * std.math.pi);

                                py.y = math.modAngle(py.y);

                                local_tranform.local.rotation = .fromRollPitchYaw(py.x, py.y, 0);
                            }

                            // Move handle
                            {
                                const speed = math.Vec3f.splat(controller.move_speed * dt);

                                const t = math.Quatf.mul(
                                    .fromAxisAngle(.right, py.x),
                                    .fromAxisAngle(.up, py.y),
                                );

                                const right = speed.mul(t.getAxisX());
                                const forward = speed.mul(t.getAxisZ());

                                var cam_pos = local_tranform.local.position;
                                cam_pos.increase(.mul(forward, .splat(move.y)));
                                cam_pos.increase(.mul(right, .splat(move.x)));

                                local_tranform.local.position = cam_pos;
                            }

                            _transform.transform(world, ent);
                            // world.modified(ent, transform.LocalTransformComponent);
                        },
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
                .{ .key = actions.KeyButtonMapping{ .k = .w, .axis_map = .{ .y = 1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .s, .axis_map = .{ .y = -1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .a, .axis_map = .{ .x = -1, .y = 0 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .d, .axis_map = .{ .x = 1, .y = 0 } } },

                // Arrow
                .{ .key = actions.KeyButtonMapping{ .k = .up, .axis_map = .{ .y = 1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .down, .axis_map = .{ .y = -1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .left, .axis_map = .{ .x = -1, .y = 0 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .right, .axis_map = .{ .x = 1, .y = 0 } } },

                // Dpad
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_up, .axis_map = .{ .y = 1 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_down, .axis_map = .{ .y = -1 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_left, .axis_map = .{ .x = -1, .y = 0 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_right, .axis_map = .{ .x = 1, .y = 0 } } },

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
    _transform = apidb.getZigApi(module_name, transform.TransformApi).?;

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
