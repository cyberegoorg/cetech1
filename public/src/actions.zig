const std = @import("std");
const builtin = @import("builtin");
const strid = @import("strid.zig");

const platform = @import("platform.zig");

pub const ButtonAction = struct {};

pub const AxisAction = struct {};

pub const Action = struct {
    name: strid.StrId32,

    action: union(enum) {
        button: ButtonAction,
        axis: AxisAction,
    },
};

pub const KeyButtonMapping = struct {
    k: platform.Key,
    axis_map: ?[]const f32 = null,
};

pub const MouseButtonMapping = struct {
    b: platform.MouseButton,
};

pub const GamepadButtonMapping = struct {
    b: platform.Gamepad.Button,
    axis_map: ?[]const f32 = null,
};

pub const GamepadAxisButtonMapping = struct {
    a: platform.Gamepad.Axis,
    treshold: f32 = 0.5,
};

pub const GamepadAxisMapping = struct {
    x: ?platform.Gamepad.Axis,
    y: ?platform.Gamepad.Axis,

    scale_x: f32 = 1,
    scale_y: f32 = 1,
};

pub const MouseMapping = struct { delta: bool = true };

pub const ActionMapping = union(enum) {
    key: KeyButtonMapping,
    mouse: MouseMapping,
    mouseButton: MouseButtonMapping,
    gamepadButton: GamepadButtonMapping,
    gamepadAxis: GamepadAxisMapping,
    gamepadAxisButton: GamepadAxisButtonMapping,
};

pub const ActionsAPI = struct {
    createActionSet: *const fn (name: strid.StrId32) anyerror!void,
    addActions: *const fn (action_set: strid.StrId32, actions: []const Action) anyerror!void,
    addMappings: *const fn (action_set: strid.StrId32, action: strid.StrId32, mapping: []const ActionMapping) anyerror!void,

    pushSet: *const fn (action_set: strid.StrId32) void,
    popSet: *const fn () void,

    isSetActive: *const fn (action_set: strid.StrId32) bool,

    isActionDown: *const fn (action: strid.StrId32) bool,
    getActionAxis: *const fn (action: strid.StrId32) [2]f32,
};
