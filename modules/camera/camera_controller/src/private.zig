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
const ZoomAction = cetech1.strId32("zoom");
const LookActivationAction = cetech1.strId32("look_activation");
const PanActivationAction = cetech1.strId32("pan_activation");

const camera_controller_c = ecs.ComponentI.implement(
    public.CameraController,
    .{
        .display_name = "Camera controller",
        .category = "Renderer",
        .with = &.{ecs.id(transform.WorldTransformComponent)},
    },
    struct {},
);

const camera_controller_system_i = ecs.SystemI.implement(
    .{
        .name = "camera_controller",
        // .multi_threaded = true,
        .phase = ecs.PostUpdate,
        // .simulation = true,
        .query = &.{
            .{ .id = ecs.id(transform.WorldTransformComponent), .inout = .InOut },
            .{ .id = ecs.id(camera.Camera), .inout = .In },
            .{ .id = ecs.id(public.CameraController), .inout = .InOut },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            // _ = dt;

            const ents = it.entities();
            const world_transforms = it.field(transform.WorldTransformComponent, 0).?;
            // const cameras = it.field(camera.Camera, 1).?;
            const controllers = it.field(public.CameraController, 2).?;

            for (ents, world_transforms, controllers) |ent, *tranform, *controller| {
                _ = ent;

                const window = _kernel.getMainWindow();

                // var camera_look_activated_new = controller.camera_look_activated;
                var camera_look_activated_now = false;

                var any_activated = false;

                {
                    _actions.pushSet(ViewportActionSet);
                    defer _actions.popSet();
                    camera_look_activated_now = _actions.isActionDown(LookActivationAction);
                    any_activated = camera_look_activated_now;
                }

                if (controller.input_enabled and any_activated) {
                    controller.camera_look_activated = true;
                    if (window) |w| w.setCursorMode(.Disabled);
                    _actions.pushSet(ActivatedViewportActionSet);
                }

                if (controller.camera_look_activated and !any_activated) {
                    controller.camera_look_activated = false;
                    if (window) |w| w.setCursorMode(.Normal);
                    _actions.popSet();
                }

                switch (controller.type) {
                    .Orbital => {
                        // Move handle
                        if (controller.camera_look_activated) {
                            const pan_active = _actions.isActionDown(PanActivationAction);
                            if (pan_active) {
                                const rotation = controller.rotation;
                                const t = math.Quatf.mul(
                                    .fromAxisAngle(.right, rotation.x),
                                    .fromAxisAngle(.up, rotation.y),
                                );

                                const pan = _actions.getActionAxis(LookAction);
                                const pan3 = math.Vec3f{ .x = -pan.x, .y = pan.y };
                                controller.focus_point.increase(t.rotateVec3(pan3));
                            } else {
                                const look = _actions.getActionAxis(LookAction);

                                var new_rotation = controller.rotation;
                                new_rotation.x -= controller.look_speed * dt * look.y;
                                new_rotation.y -= controller.look_speed * dt * look.x;
                                new_rotation.x = math.modAngle(new_rotation.x);
                                new_rotation.y = math.modAngle(new_rotation.y);
                                controller.rotation = new_rotation;
                            }

                            const zoom = _actions.getActionAxis(ZoomAction);
                            controller.zoom -= zoom.y * controller.move_speed;
                            controller.zoom = @max(1, controller.zoom);
                        } else if (controller.input_enabled) {
                            _actions.pushSet(ViewportActionSet);
                            defer _actions.popSet();

                            const zoom = _actions.getActionAxis(ZoomAction);
                            controller.zoom -= zoom.y * controller.move_speed;
                            controller.zoom = @max(1, controller.zoom);
                        }

                        const rotation = controller.rotation;
                        const t = math.Quatf.mul(
                            .fromAxisAngle(.right, rotation.x),
                            .fromAxisAngle(.up, rotation.y),
                        );
                        const focus_dir = t.rotateVec3(.forward).normalized();
                        controller.position = controller.focus_point.add(.mul(focus_dir, .splat(controller.zoom)));

                        tranform.world.position = controller.position;
                        tranform.world.rotation = math.Quatf.lookAt(
                            controller.position,
                            controller.focus_point,
                            t.getAxisY(),
                        );
                    },

                    .FreeFlight => {
                        if (controller.camera_look_activated) {
                            var new_rotation = controller.rotation;

                            // Look handle
                            {
                                const look = _actions.getActionAxis(LookAction);
                                new_rotation.x -= controller.look_speed * dt * look.y;
                                new_rotation.y += controller.look_speed * dt * look.x;

                                new_rotation.x = @min(new_rotation.x, 0.48 * std.math.pi);
                                new_rotation.x = @max(new_rotation.x, -0.48 * std.math.pi);

                                new_rotation.y = math.modAngle(new_rotation.y);

                                controller.rotation = new_rotation;
                            }

                            // Move handle
                            {
                                const move = _actions.getActionAxis(MoveAction);
                                const speed = math.Vec3f.splat(controller.move_speed * dt);

                                const t = math.Quatf.mul(
                                    .fromAxisAngle(.right, new_rotation.x),
                                    .fromAxisAngle(.up, new_rotation.y),
                                );

                                const right = speed.mul(t.getAxisX());
                                const forward = speed.mul(t.getAxisZ());

                                var cam_pos = controller.position;
                                cam_pos.increase(.mul(forward, .splat(move.y)));
                                cam_pos.increase(.mul(right, .splat(move.x)));

                                controller.position = cam_pos;
                            }
                        }
                        tranform.world = .fromPosRot(controller.position, controller.rotation);
                    },
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
            {
                try _actions.addActions(ViewportActionSet, &.{
                    .{ .name = LookActivationAction, .action = .{ .button = actions.ButtonAction{} } },
                    .{ .name = ZoomAction, .action = .{ .axis = actions.AxisAction{} } },
                });

                try _actions.addMappings(ViewportActionSet, LookActivationAction, &.{
                    .{ .gamepadAxisButton = actions.GamepadAxisButtonMapping{ .a = .right_trigger } },
                    .{ .mouseButton = actions.MouseButtonMapping{ .b = .left } },
                });

                try _actions.addMappings(ViewportActionSet, ZoomAction, &.{
                    .{ .scroll = actions.ScrollMapping{} },
                });
            }

            try _actions.createActionSet(ActivatedViewportActionSet);
            {
                try _actions.addActions(ActivatedViewportActionSet, &.{
                    .{ .name = MoveAction, .action = .{ .axis = actions.AxisAction{} } },
                    .{ .name = LookAction, .action = .{ .axis = actions.AxisAction{} } },
                    .{ .name = ZoomAction, .action = .{ .axis = actions.AxisAction{} } },

                    .{ .name = PanActivationAction, .action = .{ .button = actions.ButtonAction{} } },
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

                try _actions.addMappings(ActivatedViewportActionSet, ZoomAction, &.{
                    .{ .scroll = actions.ScrollMapping{} },

                    .{ .key = actions.KeyButtonMapping{ .k = .w, .axis_map = .{ .y = 1 } } },
                    .{ .key = actions.KeyButtonMapping{ .k = .s, .axis_map = .{ .y = -1 } } },
                });

                try _actions.addMappings(ActivatedViewportActionSet, PanActivationAction, &.{
                    .{ .key = actions.KeyButtonMapping{ .k = .left_shift } },
                });
            }
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
