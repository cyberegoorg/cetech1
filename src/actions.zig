const std = @import("std");

const cetech1 = @import("cetech1");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const platform = @import("platform.zig");
const kernel = @import("kernel.zig");

const public = cetech1.actions;
const zm = cetech1.math.zmath;

pub var api = public.ActionsAPI{
    .createActionSet = createActionSet,
    .addActions = addActions,
    .addMappings = addMappings,
    .pushSet = pushSet,
    .popSet = popSet,
    .isSetActive = isSetActive,
    .isActionDown = isActionDown,
    .getActionAxis = getActionAxis,
};

const module_name = .actions;
const log = std.log.scoped(module_name);

const ActionsSet = cetech1.AutoArrayHashMap(cetech1.StrId32, Action);
const ActionSetMap = cetech1.AutoArrayHashMap(cetech1.StrId32, ActionsSet);

const MappingList = cetech1.ArrayList(public.ActionMapping);
const ActiveSetStack = cetech1.StrId32List;

const Action = struct {
    action: public.Action,
    mapping: MappingList = .{},

    pub fn init(action: public.Action) !Action {
        return .{
            .action = action,
        };
    }

    pub fn deinit(
        self: *Action,
        allocator: std.mem.Allocator,
    ) void {
        self.mapping.deinit(allocator);
    }
};

var _allocator: std.mem.Allocator = undefined;
var _action_set: ActionSetMap = undefined;
var _active_set_stack: ActiveSetStack = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    _action_set = .{};
    _active_set_stack = .{};
}

pub fn deinit() void {
    for (_action_set.values()) |*value| {
        for (value.values()) |*value2| {
            value2.deinit(_allocator);
        }
        value.deinit(_allocator);
    }

    _action_set.deinit(_allocator);
    _active_set_stack.deinit(_allocator);
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.ActionsAPI, &api);
}

pub fn createActionSet(name: cetech1.StrId32) !void {
    const result = try _action_set.getOrPut(_allocator, name);
    if (!result.found_existing) {
        result.value_ptr.* = .{};
    }
}
pub fn addActions(action_set: cetech1.StrId32, actions: []const public.Action) !void {
    var set = _action_set.getPtr(action_set) orelse return error.ActionSetNotFound;

    for (actions) |action| {
        const result = try set.getOrPut(_allocator, action.name);
        if (!result.found_existing) {
            result.value_ptr.* = try .init(action);
        }
    }
}
pub fn addMappings(action_set: cetech1.StrId32, action: cetech1.StrId32, mapping: []const public.ActionMapping) !void {
    var set = _action_set.getPtr(action_set) orelse return error.ActionSetNotFound;
    var a = set.getPtr(action) orelse return error.ActionNotFound;
    try a.mapping.appendSlice(_allocator, mapping);
}

fn pushSet(action_set: cetech1.StrId32) void {
    _active_set_stack.append(_allocator, action_set) catch undefined;
}

fn popSet() void {
    _ = _active_set_stack.pop();
}

fn isSetActive(action_set: cetech1.StrId32) bool {
    return _active_set_stack.getLast().eql(action_set);
}

fn isActionDown(action: cetech1.StrId32) bool {
    if (_active_set_stack.items.len == 0) return false;

    const set = _action_set.getPtr(_active_set_stack.getLast()) orelse return false;
    const a: Action = set.get(action) orelse return false;

    if (a.action.action != .button) return false;

    const w = kernel.api.getMainWindow() orelse return false;

    for (a.mapping.items) |maping| {
        switch (maping) {
            .key => |k| {
                if (w.getKey(k.k) == .press) return true;
                continue;
            },
            .gamepadButton => |gb| {
                const gamepad = platform.api.getGamepad(0) orelse continue;
                const state = gamepad.getState();
                const pressed = state.buttons[@intFromEnum(gb.b)] == .press;
                if (pressed) return true;
                continue;
            },
            .gamepadAxisButton => |ab| {
                const gamepad = platform.api.getGamepad(0) orelse continue;
                const state = gamepad.getState();
                const axis_x = state.axes[@intFromEnum(ab.a)];
                if (axis_x > ab.treshold) return true;

                continue;
            },
            .mouseButton => |mb| {
                const pressed = w.getMouseButton(mb.b) == .press;
                if (pressed) return true;
                continue;
            },
            else => |e| {
                log.err("Invalid mapping {any}", .{e});
            },
        }
    }

    return false;
}

var last_pos: [2]f64 = .{ 0.0, 0.0 };
var mouse_delta: [2]f64 = .{ 0.0, 0.0 };

pub fn checkInputs() void {
    const w = kernel.api.getMainWindow() orelse return;

    const mouse_pos = w.getCursorPos();

    mouse_delta = if (last_pos[0] == 0 and last_pos[1] == 0) .{ 0, 0 } else .{
        mouse_pos[0] - last_pos[0],
        last_pos[1] - mouse_pos[1],
    };

    last_pos = mouse_pos;
}

fn getActionAxis(action: cetech1.StrId32) [2]f32 {
    if (_active_set_stack.items.len == 0) return .{ 0, 0 };

    const set = _action_set.getPtr(_active_set_stack.getLast()).?;
    const a: Action = set.get(action) orelse return .{ 0, 0 };

    if (a.action.action != .axis) return .{ 0, 0 };

    const w = kernel.api.getMainWindow().?;

    var axis: [2]f32 = .{ 0, 0 };

    for (a.mapping.items) |maping| {
        switch (maping) {
            .key => |k| {
                if (w.getKey(k.k) == .press) {
                    axis[0] += k.axis_map.?[0];
                    axis[1] += k.axis_map.?[1];
                }
                continue;
            },
            .gamepadButton => |gb| {
                const gamepad = platform.api.getGamepad(0) orelse continue;
                const state = gamepad.getState();

                if (state.buttons[@intFromEnum(gb.b)] == .press) {
                    axis[0] += gb.axis_map.?[0];
                    axis[1] += gb.axis_map.?[1];
                }

                continue;
            },
            .gamepadAxis => |ga| {
                const gamepad = platform.api.getGamepad(0) orelse continue;
                const state = gamepad.getState();
                const FAKE_DEADZONE = 0.07;

                if (ga.x) |x| {
                    const axis_x = state.axes[@intFromEnum(x)];
                    if (@abs(axis_x) > FAKE_DEADZONE) {
                        axis[0] += axis_x * ga.scale_x;
                    }
                }

                if (ga.y) |y| {
                    const axis_y = state.axes[@intFromEnum(y)];
                    if (@abs(axis_y) > FAKE_DEADZONE) {
                        axis[1] += axis_y * -1 * ga.scale_y;
                    }
                }

                continue;
            },
            .mouse => |m| {
                if (m.delta) {
                    const pos = mouse_delta;
                    axis[0] += @floatCast(pos[0]);
                    axis[1] += @floatCast(pos[1]);
                } else {
                    const pos = w.getCursorPos();
                    axis[0] += @floatCast(pos[0]);
                    axis[1] += @floatCast(pos[1]);
                }
            },
            else => |e| {
                log.err("Invalid mapping {any}", .{e});
            },
        }
    }

    // if (axis[0] != 0 or axis[1] != 0) {
    //     const av = zm.loadArr2(axis);
    //     const av_norm = zm.normalize2(av);
    //     axis = zm.vecToArr2(av_norm);
    // }

    return axis;
}
