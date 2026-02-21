const std = @import("std");

const cetech1 = @import("cetech1");
const input = cetech1.input;
const math = cetech1.math;
const apidb = cetech1.apidb;

pub const ACTIONS_KERNEL_TASK_NAME = "ActionsInit";
pub const ACTIONS_KERNEL_TASK = cetech1.strId64(ACTIONS_KERNEL_TASK_NAME);

pub const ButtonAction = struct {};

pub const AxisAction = struct {};

pub const Action = struct {
    name: cetech1.StrId32,

    action: union(enum) {
        button: ButtonAction,
        axis: AxisAction,
    },
};

pub const KeyButtonMapping = struct {
    k: input.Key,
    axis_map: ?math.Vec2f = null,
};

pub const MouseButtonMapping = struct {
    b: input.MouseButton,
};

pub const GamepadButtonMapping = struct {
    b: input.GamepadButton,
    axis_map: ?math.Vec2f = null,
};

pub const GamepadAxisButtonMapping = struct {
    a: input.GamepadAxis,
    treshold: f32 = 0.5,
};

pub const GamepadAxisMapping = struct {
    x: ?input.GamepadAxis,
    y: ?input.GamepadAxis,

    scale_x: f32 = 1,
    scale_y: f32 = 1,
};

pub const MouseMapping = struct { delta: bool = true };
pub const ScrollMapping = struct {};

pub const ActionMapping = union(enum) {
    key: KeyButtonMapping,
    mouse: MouseMapping,
    mouseButton: MouseButtonMapping,
    scroll: ScrollMapping,
    gamepadButton: GamepadButtonMapping,
    gamepadAxis: GamepadAxisMapping,
    gamepadAxisButton: GamepadAxisButtonMapping,
};

pub fn createActionSet(name: cetech1.StrId32) anyerror!void {
    return api.createActionSet(name);
}
pub fn addActions(action_set: cetech1.StrId32, actions: []const Action) anyerror!void {
    return api.addActions(action_set, actions);
}
pub fn addMappings(action_set: cetech1.StrId32, action: cetech1.StrId32, mapping: []const ActionMapping) anyerror!void {
    return api.addMappings(action_set, action, mapping);
}
pub fn pushSet(action_set: cetech1.StrId32) void {
    return api.pushSet(action_set);
}
pub fn popSet() void {
    return api.popSet();
}
pub fn isSetActive(action_set: cetech1.StrId32) bool {
    return api.isSetActive(action_set);
}
pub fn isActionDown(action: cetech1.StrId32) bool {
    return api.isActionDown(action);
}
pub fn getActionAxis(action: cetech1.StrId32) math.Vec2f {
    return api.getActionAxis(action);
}

pub const ActionsAPI = struct {
    createActionSet: *const fn (name: cetech1.StrId32) anyerror!void,
    addActions: *const fn (action_set: cetech1.StrId32, actions: []const Action) anyerror!void,
    addMappings: *const fn (action_set: cetech1.StrId32, action: cetech1.StrId32, mapping: []const ActionMapping) anyerror!void,
    pushSet: *const fn (action_set: cetech1.StrId32) void,
    popSet: *const fn () void,
    isSetActive: *const fn (action_set: cetech1.StrId32) bool,
    isActionDown: *const fn (action: cetech1.StrId32) bool,
    getActionAxis: *const fn (action: cetech1.StrId32) math.Vec2f,
};

pub var api: *const ActionsAPI = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, ActionsAPI).?;
}
