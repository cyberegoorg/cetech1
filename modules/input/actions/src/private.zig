const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const input = cetech1.input;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const math = cetech1.math;

const public = @import("actions.zig");

const module_name = .actions;

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
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _platform: *const cetech1.host.PlatformApi = undefined;
var _input: *const cetech1.input.InputApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

var _keyboard_source: *const input.InputSourceI = undefined;
var _mouse_source: *const input.InputSourceI = undefined;
var _gamepad_source: *const input.InputSourceI = undefined;

var _last_pos: [2]f64 = .{ 0.0, 0.0 };
var _mouse_delta: [2]f64 = .{ 0.0, 0.0 };

var _last_scroll: [2]f64 = .{ 0.0, 0.0 };
var _scroll_delta: [2]f64 = .{ 0.0, 0.0 };

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

var _action_set: ActionSetMap = undefined;
var _active_set_stack: ActiveSetStack = undefined;

var actions_kernel_task = cetech1.kernel.KernelTaskI.implement(
    public.ACTIONS_KERNEL_TASK_NAME,
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            _action_set = .{};
            _active_set_stack = .{};
        }

        pub fn shutdown() !void {
            for (_action_set.values()) |*value| {
                for (value.values()) |*value2| {
                    value2.deinit(_allocator);
                }
                value.deinit(_allocator);
            }

            _action_set.deinit(_allocator);
            _active_set_stack.deinit(_allocator);
        }
    },
);

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

    for (a.mapping.items) |maping| {
        switch (maping) {
            .key => |k| {
                if (_keyboard_source.getState(0, @intFromEnum(k.k)).?.action != .release) return true;
                continue;
            },
            .gamepadButton => |gb| {
                const pressed = _gamepad_source.getState(0, @intFromEnum(gb.b)).?.action == .press;
                if (pressed) return true;
                continue;
            },
            .gamepadAxisButton => |ab| {
                const axis_x = _gamepad_source.getState(0, @intFromEnum(ab.a)).?.f;
                if (axis_x > ab.treshold) return true;
                continue;
            },
            .mouseButton => |mb| {
                const pressed = _mouse_source.getState(0, @intFromEnum(mb.b)).?.action == .press;
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

fn getActionAxis(action: cetech1.StrId32) math.Vec2f {
    if (_active_set_stack.items.len == 0) return .{};

    const set = _action_set.getPtr(_active_set_stack.getLast()).?;
    const a: Action = set.get(action) orelse return .{};

    if (a.action.action != .axis) return .{};

    const w = _kernel.getMainWindow().?; // TODO: param?

    var axis: math.Vec2f = .{};

    for (a.mapping.items) |maping| {
        switch (maping) {
            .key => |k| {
                if (_keyboard_source.getState(0, @intFromEnum(k.k)).?.action != .release) {
                    axis.increase(k.axis_map.?);
                }
                continue;
            },
            .gamepadButton => |gb| {
                if (_gamepad_source.getState(0, @intFromEnum(gb.b)).?.action == .press) {
                    axis.increase(gb.axis_map.?);
                }

                continue;
            },
            .gamepadAxis => |ga| {
                const FAKE_DEADZONE = 0.07;

                if (ga.x) |x| {
                    const axis_x = _gamepad_source.getState(0, @intFromEnum(x)).?.f;
                    if (@abs(axis_x) > FAKE_DEADZONE) {
                        axis.x += axis_x * ga.scale_x;
                    }
                }

                if (ga.y) |y| {
                    const axis_y = _gamepad_source.getState(0, @intFromEnum(y)).?.f;
                    if (@abs(axis_y) > FAKE_DEADZONE) {
                        axis.y += axis_y * -1 * ga.scale_y;
                    }
                }

                continue;
            },
            .mouse => |m| {
                if (m.delta) {
                    const pos = _mouse_delta;
                    axis.x += @floatCast(pos[0]);
                    axis.y += @floatCast(pos[1]);
                } else {
                    const pos = w.getCursorPos();
                    axis.x += @floatCast(pos[0]);
                    axis.y += @floatCast(pos[1]);
                }
            },
            .scroll => {
                const scroll = _scroll_delta;
                axis.x += @floatCast(scroll[0]);
                axis.y += @floatCast(scroll[1]);
            },
            else => |e| {
                log.err("Invalid mapping {any}", .{e});
            },
        }
    }

    return axis;
}

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "Actions",
    &[_]cetech1.StrId64{},
    0,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            checkInputs();
        }
    },
);

pub fn checkInputs() void {
    const w = _kernel.getMainWindow() orelse return;

    const mouse_pos = w.getCursorPos();

    _mouse_delta = if (_last_pos[0] == 0 and _last_pos[1] == 0) .{ 0, 0 } else .{
        mouse_pos[0] - _last_pos[0],
        _last_pos[1] - mouse_pos[1],
    };

    _last_pos = mouse_pos;

    const scroll_x = _mouse_source.getState(0, @intFromEnum(input.MouseAxis.scroll_x)).?;
    const scroll_y = _mouse_source.getState(0, @intFromEnum(input.MouseAxis.scroll_y)).?;
    _scroll_delta = .{
        _last_scroll[0] - scroll_x.f,
        _last_scroll[1] - scroll_y.f,
    };
    _last_scroll = .{ @floatCast(scroll_x.f), @floatCast(scroll_y.f) };

    // if (_scroll_delta[0] != 0 or _scroll_delta[1] != 0) {
    //     log.debug("scroll delta {any}", .{_scroll_delta});
    // }
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _platform = apidb.getZigApi(module_name, cetech1.host.PlatformApi).?;
    _input = apidb.getZigApi(module_name, cetech1.input.InputApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // impl api
    try apidb.setOrRemoveZigApi(module_name, public.ActionsAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &actions_kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _keyboard_source = _input.getSourceByType(allocator, input.KEYBOARD_TYPE).?;
    _mouse_source = _input.getSourceByType(allocator, input.MOUSE_TYPE).?;
    _gamepad_source = _input.getSourceByType(allocator, input.GAMEPAD_TYPE).?;
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_actions(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
