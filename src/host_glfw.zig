const std = @import("std");
const builtin = @import("builtin");

const zglfw = @import("zglfw");

const apidb = @import("apidb.zig");
const kernel = @import("kernel.zig");
const task = @import("task.zig");
const host_private = @import("host.zig");

const cetech1 = @import("cetech1");
const host = cetech1.host;
const input = cetech1.input;

const gamecontrollerdb = @embedFile("gamecontrollerdb");

const module_name = .host_glfw;

const log = std.log.scoped(module_name);

const MAX_GAMEPADS = 16;

pub const GamepadState = extern struct {
    enabled: bool = false,
    buttons: [15]input.Action = @splat(.release),
    axes: [6]f32 = @splat(0),
};

pub const Window = struct {
    window: *anyopaque,
    key_mods: input.Mods = .{},

    last_cursor_pos: [2]f64 = .{ 0, 0 },
    content_scale: [2]f32 = .{ 0, 0 },
    fb_size: [2]i32 = .{ 0, 0 },

    pub fn init(window: *anyopaque) Window {
        const w = Window{
            .window = window,
        };
        return w;
    }
};

const WindowPool = cetech1.heap.PoolWithLock(Window);
const WindowSet = cetech1.ArraySet(*Window);

pub const window_api = host.WindowApi{
    .createWindow = createWindow,
    .destroyWindow = destroyWindow,
};

pub const monitor_api = host.MonitorApi{
    .getPrimaryMonitor = getPrimaryMonitor,
};

var _allocator: std.mem.Allocator = undefined;

var _window_pool: WindowPool = undefined;
var _window_set: WindowSet = undefined;

var _keyboard_state: [@intFromEnum(input.Key.count)]input.Action = @splat(.release);
var _gamepad_state: [MAX_GAMEPADS]GamepadState = @splat(.{});
var _mouse_button_state: [@intFromEnum(input.MouseButton.count)]input.Action = @splat(.release);

pub fn init(allocator: std.mem.Allocator, headless: bool) !void {
    _allocator = allocator;

    _window_pool = WindowPool.init(allocator);
    _window_set = .init();

    _keyboard_state = @splat(.release);

    try zglfw.init();

    if (!zglfw.updateGamepadMappings(gamecontrollerdb)) {
        log.err("Failed to update gamepad mappings", .{});
    }

    zglfw.windowHint(.client_api, .no_api);

    if (headless) {
        zglfw.windowHint(.visible, false);
    }
}

pub fn deinit() void {
    zglfw.terminate();

    _window_pool.deinit();
    _window_set.deinit(_allocator);
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, host.MonitorApi, &monitor_api);
    try apidb.api.setZigApi(module_name, host.WindowApi, &window_api);

    try apidb.api.implInterface(module_name, input.InputSourceI, &keyboard_input_source);
    try apidb.api.implInterface(module_name, input.InputSourceI, &mouse_input_source);
    try apidb.api.implInterface(module_name, input.InputSourceI, &gamepad_input_source);
}

//
// Keyboard
//
const KEYBOARD_ITEMS = [_]input.InputItem{
    .{ .name = "unknown", .id = 0 },
    .{ .name = "space", .id = @intFromEnum(input.Key.space) },
    .{ .name = "apostrophe", .id = @intFromEnum(input.Key.apostrophe) },
    .{ .name = "comma", .id = @intFromEnum(input.Key.comma) },
    .{ .name = "minus", .id = @intFromEnum(input.Key.minus) },
    .{ .name = "period", .id = @intFromEnum(input.Key.period) },
    .{ .name = "slash", .id = @intFromEnum(input.Key.slash) },
    .{ .name = "zero", .id = @intFromEnum(input.Key.zero) },
    .{ .name = "one", .id = @intFromEnum(input.Key.one) },
    .{ .name = "two", .id = @intFromEnum(input.Key.two) },
    .{ .name = "three", .id = @intFromEnum(input.Key.three) },
    .{ .name = "four", .id = @intFromEnum(input.Key.four) },
    .{ .name = "five", .id = @intFromEnum(input.Key.five) },
    .{ .name = "six", .id = @intFromEnum(input.Key.six) },
    .{ .name = "seven", .id = @intFromEnum(input.Key.seven) },
    .{ .name = "eight", .id = @intFromEnum(input.Key.eight) },
    .{ .name = "nine", .id = @intFromEnum(input.Key.nine) },
    .{ .name = "semicolon", .id = @intFromEnum(input.Key.semicolon) },
    .{ .name = "equal", .id = @intFromEnum(input.Key.equal) },
    .{ .name = "a", .id = @intFromEnum(input.Key.a) },
    .{ .name = "b", .id = @intFromEnum(input.Key.b) },
    .{ .name = "c", .id = @intFromEnum(input.Key.c) },
    .{ .name = "d", .id = @intFromEnum(input.Key.d) },
    .{ .name = "e", .id = @intFromEnum(input.Key.e) },
    .{ .name = "f", .id = @intFromEnum(input.Key.f) },
    .{ .name = "g", .id = @intFromEnum(input.Key.g) },
    .{ .name = "h", .id = @intFromEnum(input.Key.h) },
    .{ .name = "i", .id = @intFromEnum(input.Key.i) },
    .{ .name = "j", .id = @intFromEnum(input.Key.j) },
    .{ .name = "k", .id = @intFromEnum(input.Key.k) },
    .{ .name = "l", .id = @intFromEnum(input.Key.l) },
    .{ .name = "m", .id = @intFromEnum(input.Key.m) },
    .{ .name = "n", .id = @intFromEnum(input.Key.n) },
    .{ .name = "o", .id = @intFromEnum(input.Key.o) },
    .{ .name = "p", .id = @intFromEnum(input.Key.p) },
    .{ .name = "q", .id = @intFromEnum(input.Key.q) },
    .{ .name = "r", .id = @intFromEnum(input.Key.r) },
    .{ .name = "s", .id = @intFromEnum(input.Key.s) },
    .{ .name = "t", .id = @intFromEnum(input.Key.t) },
    .{ .name = "u", .id = @intFromEnum(input.Key.u) },
    .{ .name = "v", .id = @intFromEnum(input.Key.v) },
    .{ .name = "w", .id = @intFromEnum(input.Key.w) },
    .{ .name = "x", .id = @intFromEnum(input.Key.x) },
    .{ .name = "y", .id = @intFromEnum(input.Key.y) },
    .{ .name = "z", .id = @intFromEnum(input.Key.z) },
    .{ .name = "left_bracket", .id = @intFromEnum(input.Key.left_bracket) },
    .{ .name = "backslash", .id = @intFromEnum(input.Key.backslash) },
    .{ .name = "right_bracket", .id = @intFromEnum(input.Key.right_bracket) },
    .{ .name = "grave_accent", .id = @intFromEnum(input.Key.grave_accent) },
    .{ .name = "world_1", .id = @intFromEnum(input.Key.world_1) },
    .{ .name = "world_2", .id = @intFromEnum(input.Key.world_2) },
    .{ .name = "escape", .id = @intFromEnum(input.Key.escape) },
    .{ .name = "enter", .id = @intFromEnum(input.Key.enter) },
    .{ .name = "tab", .id = @intFromEnum(input.Key.tab) },
    .{ .name = "backspace", .id = @intFromEnum(input.Key.backspace) },
    .{ .name = "insert", .id = @intFromEnum(input.Key.insert) },
    .{ .name = "delete", .id = @intFromEnum(input.Key.delete) },
    .{ .name = "right", .id = @intFromEnum(input.Key.right) },
    .{ .name = "left", .id = @intFromEnum(input.Key.left) },
    .{ .name = "down", .id = @intFromEnum(input.Key.down) },
    .{ .name = "up", .id = @intFromEnum(input.Key.up) },
    .{ .name = "page_up", .id = @intFromEnum(input.Key.page_up) },
    .{ .name = "page_down", .id = @intFromEnum(input.Key.page_down) },
    .{ .name = "home", .id = @intFromEnum(input.Key.home) },
    .{ .name = "end", .id = @intFromEnum(input.Key.end) },
    .{ .name = "caps_lock", .id = @intFromEnum(input.Key.caps_lock) },
    .{ .name = "scroll_lock", .id = @intFromEnum(input.Key.scroll_lock) },
    .{ .name = "num_lock", .id = @intFromEnum(input.Key.num_lock) },
    .{ .name = "print_screen", .id = @intFromEnum(input.Key.print_screen) },
    .{ .name = "pause", .id = @intFromEnum(input.Key.pause) },
    .{ .name = "f1", .id = @intFromEnum(input.Key.F1) },
    .{ .name = "f2", .id = @intFromEnum(input.Key.F2) },
    .{ .name = "f3", .id = @intFromEnum(input.Key.F3) },
    .{ .name = "f4", .id = @intFromEnum(input.Key.F4) },
    .{ .name = "f5", .id = @intFromEnum(input.Key.F5) },
    .{ .name = "f6", .id = @intFromEnum(input.Key.F6) },
    .{ .name = "f7", .id = @intFromEnum(input.Key.F7) },
    .{ .name = "f8", .id = @intFromEnum(input.Key.F8) },
    .{ .name = "f9", .id = @intFromEnum(input.Key.F9) },
    .{ .name = "f10", .id = @intFromEnum(input.Key.F10) },
    .{ .name = "f11", .id = @intFromEnum(input.Key.F11) },
    .{ .name = "f12", .id = @intFromEnum(input.Key.F12) },
    .{ .name = "f13", .id = @intFromEnum(input.Key.F13) },
    .{ .name = "f14", .id = @intFromEnum(input.Key.F14) },
    .{ .name = "f15", .id = @intFromEnum(input.Key.F15) },
    .{ .name = "f16", .id = @intFromEnum(input.Key.F16) },
    .{ .name = "f17", .id = @intFromEnum(input.Key.F17) },
    .{ .name = "f18", .id = @intFromEnum(input.Key.F18) },
    .{ .name = "f19", .id = @intFromEnum(input.Key.F19) },
    .{ .name = "f20", .id = @intFromEnum(input.Key.F20) },
    .{ .name = "f21", .id = @intFromEnum(input.Key.F21) },
    .{ .name = "f22", .id = @intFromEnum(input.Key.F22) },
    .{ .name = "f23", .id = @intFromEnum(input.Key.F23) },
    .{ .name = "f24", .id = @intFromEnum(input.Key.F24) },
    .{ .name = "f25", .id = @intFromEnum(input.Key.F25) },
    .{ .name = "kp_0", .id = @intFromEnum(input.Key.kp_0) },
    .{ .name = "kp_1", .id = @intFromEnum(input.Key.kp_1) },
    .{ .name = "kp_2", .id = @intFromEnum(input.Key.kp_2) },
    .{ .name = "kp_3", .id = @intFromEnum(input.Key.kp_3) },
    .{ .name = "kp_4", .id = @intFromEnum(input.Key.kp_4) },
    .{ .name = "kp_5", .id = @intFromEnum(input.Key.kp_5) },
    .{ .name = "kp_6", .id = @intFromEnum(input.Key.kp_6) },
    .{ .name = "kp_7", .id = @intFromEnum(input.Key.kp_7) },
    .{ .name = "kp_8", .id = @intFromEnum(input.Key.kp_8) },
    .{ .name = "kp_9", .id = @intFromEnum(input.Key.kp_9) },
    .{ .name = "kp_decimal", .id = @intFromEnum(input.Key.kp_decimal) },
    .{ .name = "kp_divide", .id = @intFromEnum(input.Key.kp_divide) },
    .{ .name = "kp_multiply", .id = @intFromEnum(input.Key.kp_multiply) },
    .{ .name = "kp_subtract", .id = @intFromEnum(input.Key.kp_subtract) },
    .{ .name = "kp_add", .id = @intFromEnum(input.Key.kp_add) },
    .{ .name = "kp_enter", .id = @intFromEnum(input.Key.kp_enter) },
    .{ .name = "kp_equal", .id = @intFromEnum(input.Key.kp_equal) },
    .{ .name = "left_shift", .id = @intFromEnum(input.Key.left_shift) },
    .{ .name = "left_control", .id = @intFromEnum(input.Key.left_control) },
    .{ .name = "left_alt", .id = @intFromEnum(input.Key.left_alt) },
    .{ .name = "left_super", .id = @intFromEnum(input.Key.left_super) },
    .{ .name = "right_shift", .id = @intFromEnum(input.Key.right_shift) },
    .{ .name = "right_control", .id = @intFromEnum(input.Key.right_control) },
    .{ .name = "right_alt", .id = @intFromEnum(input.Key.right_alt) },
    .{ .name = "right_super", .id = @intFromEnum(input.Key.right_super) },
    .{ .name = "menu", .id = @intFromEnum(input.Key.menu) },
};

const keyboard_input_source = input.InputSourceI.implment(
    "keyboard",
    input.KEYBOARD_TYPE,
    struct {
        pub fn getItems() []const input.InputItem {
            return &KEYBOARD_ITEMS;
        }

        pub fn getControllers(allocator: std.mem.Allocator) ![]input.ControlerId {
            return allocator.dupe(input.ControlerId, &.{0}); // TODO: Multiple keyboards?
        }

        pub fn getState(controler_id: input.ControlerId, item_type: input.ItemId) ?input.ItemData {
            std.debug.assert(controler_id == 0);
            return .{ .action = _keyboard_state[item_type] };
        }
    },
);

fn keyCallback(window: *zglfw.Window, key: zglfw.Key, scancode: c_int, action: zglfw.Action, mods: zglfw.Mods) callconv(.c) void {
    _ = window;
    _ = scancode;
    _ = mods;

    const k = glfwKeyToKey(key);
    const key_idx = @intFromEnum(k);
    _keyboard_state[key_idx] = glfwActionToAction(action);
}

//
// Gamepad
//
const GAMEPAD_ITEMS = [_]input.InputItem{
    // BUTTONS
    .{ .name = "a", .id = @intFromEnum(input.GamepadButton.a) },
    .{ .name = "b", .id = @intFromEnum(input.GamepadButton.b) },
    .{ .name = "x", .id = @intFromEnum(input.GamepadButton.x) },
    .{ .name = "y", .id = @intFromEnum(input.GamepadButton.y) },
    .{ .name = "left_bumper", .id = @intFromEnum(input.GamepadButton.left_bumper) },
    .{ .name = "right_bumper", .id = @intFromEnum(input.GamepadButton.right_bumper) },
    .{ .name = "back", .id = @intFromEnum(input.GamepadButton.back) },
    .{ .name = "start", .id = @intFromEnum(input.GamepadButton.start) },
    .{ .name = "guide", .id = @intFromEnum(input.GamepadButton.guide) },
    .{ .name = "left_thumb", .id = @intFromEnum(input.GamepadButton.left_thumb) },
    .{ .name = "right_thumb", .id = @intFromEnum(input.GamepadButton.right_thumb) },
    .{ .name = "dpad_up", .id = @intFromEnum(input.GamepadButton.dpad_up) },
    .{ .name = "dpad_right", .id = @intFromEnum(input.GamepadButton.dpad_right) },
    .{ .name = "dpad_down", .id = @intFromEnum(input.GamepadButton.dpad_down) },
    .{ .name = "dpad_left", .id = @intFromEnum(input.GamepadButton.dpad_left) },

    // AXIS
    .{ .name = "left_x", .id = @intFromEnum(input.GamepadAxis.left_x) },
    .{ .name = "left_y", .id = @intFromEnum(input.GamepadAxis.left_y) },
    .{ .name = "right_x", .id = @intFromEnum(input.GamepadAxis.right_x) },
    .{ .name = "right_y", .id = @intFromEnum(input.GamepadAxis.right_y) },
    .{ .name = "left_trigger", .id = @intFromEnum(input.GamepadAxis.left_trigger) },
    .{ .name = "right_trigger", .id = @intFromEnum(input.GamepadAxis.right_trigger) },
};

const gamepad_input_source = input.InputSourceI.implment(
    "gamepad",
    input.GAMEPAD_TYPE,
    struct {
        pub fn getItems() []const input.InputItem {
            return &GAMEPAD_ITEMS;
        }

        pub fn getControllers(allocator: std.mem.Allocator) ![]input.ControlerId {
            var controllers = try cetech1.ArrayList(input.ControlerId).initCapacity(allocator, MAX_GAMEPADS);

            for (0..MAX_GAMEPADS) |gamepad_idx| {
                if (!_gamepad_state[gamepad_idx].enabled) continue;

                controllers.appendAssumeCapacity(gamepad_idx);
            }
            return controllers.toOwnedSlice(allocator);
        }

        pub fn getState(controler_id: input.ControlerId, item_type: input.ItemId) ?input.ItemData {

            // Buttons
            if (item_type < @intFromEnum(input.GamepadAxis.left_x)) {
                return .{ .action = _gamepad_state[controler_id].buttons[item_type] };
            }

            // Axis
            const axis_idx = item_type - @intFromEnum(input.GamepadAxis.left_x);
            return .{ .f = _gamepad_state[controler_id].axes[axis_idx] };
        }
    },
);

//
// Mouse
//
const MOUSE_ITEMS = [_]input.InputItem{
    .{ .name = "unknown", .id = @intFromEnum(input.MouseButton.unknown) },
    .{ .name = "left", .id = @intFromEnum(input.MouseButton.left) },
    .{ .name = "right", .id = @intFromEnum(input.MouseButton.right) },
    .{ .name = "middle", .id = @intFromEnum(input.MouseButton.middle) },
    .{ .name = "four", .id = @intFromEnum(input.MouseButton.four) },
    .{ .name = "five", .id = @intFromEnum(input.MouseButton.five) },
    .{ .name = "six", .id = @intFromEnum(input.MouseButton.six) },
    .{ .name = "seven", .id = @intFromEnum(input.MouseButton.seven) },
    .{ .name = "eight", .id = @intFromEnum(input.MouseButton.eight) },
};

const mouse_input_source = input.InputSourceI.implment(
    "mouse",
    input.MOUSE_TYPE,
    struct {
        pub fn getItems() []const input.InputItem {
            return &MOUSE_ITEMS;
        }

        pub fn getControllers(allocator: std.mem.Allocator) ![]input.ControlerId {
            return allocator.dupe(input.ControlerId, &.{0}); // TODO:
        }

        pub fn getState(controler_id: input.ControlerId, item_type: input.ItemId) ?input.ItemData {
            std.debug.assert(controler_id == 0);
            return .{ .action = _mouse_button_state[item_type] };
        }
    },
);

fn cursorPosCallback(window: *zglfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    var w = findWindowByInternal(window).?;
    w.last_cursor_pos = .{ xpos, ypos };
}

fn mouseButtonCallback(
    window: *zglfw.Window,
    button: zglfw.MouseButton,
    action: zglfw.Action,
    mods: zglfw.Mods,
) callconv(.c) void {
    _ = window;
    _ = mods;

    const b = gltfMouseButtonToMouseButton(button);
    const a = glfwActionToAction(action);

    _mouse_button_state[@intFromEnum(b)] = a;
    //var w = findWindowByInternal(window).?;
}

//
// Window
//
pub const window_vt = host.Window.VTable.implement(struct {
    pub fn setCursorMode(window: *anyopaque, mode: host.CursorMode) void {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);

        // TODO: this is HOTFIX
        const Task = struct {
            mode: host.CursorMode,
            glfw_w: *zglfw.Window,

            pub fn exec(s: *@This()) !void {
                try s.glfw_w.setInputMode(.cursor, cursorModeTOGlfw(s.mode));
            }
        };
        const task_id = task.api.schedule(
            cetech1.task.TaskID.none,
            Task{
                .mode = mode,
                .glfw_w = glfw_w,
            },
            .{ .affinity = 0 },
        ) catch undefined;
        _ = task_id;
        //task.api.wait(task_id);
    }

    pub fn getOsWindowHandler(window: *anyopaque) ?*anyopaque {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);

        return switch (builtin.target.os.tag) {
            // TODO: wayland
            .linux => @ptrFromInt(zglfw.getX11Window(glfw_w)),
            .windows => zglfw.getWin32Window(glfw_w),
            else => |v| if (v.isDarwin())
                zglfw.getCocoaWindow(glfw_w)
            else
                null,
        };
    }

    pub fn getOsDisplayHandler(window: *anyopaque) ?*anyopaque {
        _ = window; // autofix

        return switch (builtin.target.os.tag) {
            .linux => zglfw.getX11Display(),
            else => null,
        };
    }

    pub fn shouldClose(window: *anyopaque) bool {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return zglfw.Window.shouldClose(glfw_w);
    }

    pub fn setShouldClose(window: *anyopaque, should_quit: bool) void {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        zglfw.setWindowShouldClose(glfw_w, should_quit);
    }

    pub fn getCursorPos(window: *anyopaque) [2]f64 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        return true_w.last_cursor_pos;
    }

    pub fn getFramebufferSize(window: *anyopaque) [2]i32 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        return true_w.fb_size;
    }

    pub fn getContentScale(window: *anyopaque) [2]f32 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        return true_w.content_scale;
    }

    pub fn getInternalHandler(window: *anyopaque) *const anyopaque {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfw_w;
    }
});

pub const monitor_vt = host.Monitor.VTable.implement(struct {
    pub fn getMonitorVideoMode(monitor: *anyopaque) !*host.Monitor.VideoMode {
        const true_monitor: *zglfw.Monitor = @ptrCast(monitor);
        const vm = try true_monitor.getVideoMode();
        return @ptrCast(vm);
    }
});

pub fn createWindow(width: i32, height: i32, title: [:0]const u8, monitor: ?host.Monitor) !host.Window {
    var w: *zglfw.Window = undefined;

    const m: ?*zglfw.Monitor = if (monitor) |m| @ptrCast(m.ptr) else null;
    w = try zglfw.Window.create(width, height, title, m);

    const new_w = try _window_pool.create();
    new_w.* = Window.init(w);
    _ = try _window_set.add(_allocator, new_w);

    const fb_size = w.getFramebufferSize();
    framebufferSizeCallback(w, fb_size[0], fb_size[1]);

    const content_scale = w.getContentScale();
    contentScaleCallback(w, content_scale[0], content_scale[1]);

    // TODO: call prev callbacks
    std.debug.assert(zglfw.setKeyCallback(w, keyCallback) == null);
    std.debug.assert(zglfw.setCursorPosCallback(w, cursorPosCallback) == null);
    std.debug.assert(zglfw.setMouseButtonCallback(w, mouseButtonCallback) == null);
    std.debug.assert(zglfw.setFramebufferSizeCallback(w, framebufferSizeCallback) == null);
    std.debug.assert(zglfw.setWindowContentScaleCallback(w, contentScaleCallback) == null);

    return .{ .ptr = new_w, .vtable = &window_vt };
}

pub fn destroyWindow(window: host.Window) void {
    const true_w: *Window = @ptrCast(@alignCast(window.ptr));

    _ = _window_set.remove(true_w);
    _window_pool.destroy(true_w);

    zglfw.Window.destroy(@ptrCast(true_w.window));
}

pub fn findWindowByInternal(window: *anyopaque) ?*Window {
    for (_window_set.unmanaged.keys()) |w| {
        if (w.window == window) return w;
    }
    return null;
}

fn framebufferSizeCallback(window: *zglfw.Window, width: c_int, height: c_int) callconv(.c) void {
    var w = findWindowByInternal(window).?;
    w.fb_size = .{ @intCast(width), @intCast(height) };
}

fn contentScaleCallback(window: *zglfw.Window, x: f32, y: f32) callconv(.c) void {
    var w = findWindowByInternal(window).?;
    w.content_scale = .{ x, y };
}

//
//
//
pub fn update(kernel_tick: u64, timeout: f64) !void {
    _ = kernel_tick;
    zglfw.waitEventsTimeout(timeout);

    for (0..MAX_GAMEPADS) |gamepad_idx| {
        const joystick: zglfw.Joystick = @enumFromInt(gamepad_idx);

        const enabled = zglfw.joystickPresent(joystick) and zglfw.joystickIsGamepad(joystick);
        _gamepad_state[gamepad_idx].enabled = enabled;

        if (!enabled) continue;

        const gamepad: zglfw.Gamepad = joystick.asGamepad() orelse continue;

        const new_state = try gamepad.getState();

        @memcpy(&_gamepad_state[gamepad_idx].buttons, @as([]const input.Action, @ptrCast(&new_state.buttons)));
        @memcpy(&_gamepad_state[gamepad_idx].axes, &new_state.axes);
    }
}

//
// Monitor
//
pub fn getPrimaryMonitor() ?host.Monitor {
    return .{
        .ptr = @ptrCast(zglfw.Monitor.getPrimary() orelse return null),
        .vtable = &monitor_vt,
    };
}

//
//
//
fn glfwActionToAction(action: zglfw.Action) input.Action {
    return switch (action) {
        .release => .release,
        .press => .press,
        .repeat => .repeat,
    };
}

fn cursorModeTOGlfw(button: host.CursorMode) zglfw.Cursor.Mode {
    return switch (button) {
        .normal => .normal,
        .hidden => .hidden,
        .disabled => .disabled,
        .captured => .captured,
    };
}

fn mouseButtonToGlfwMouseButton(button: input.MouseButton) zglfw.MouseButton {
    return switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        else => undefined,
    };
}

fn gltfMouseButtonToMouseButton(button: zglfw.MouseButton) input.MouseButton {
    return switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
    };
}

fn keyToglfwKey(key: input.Key) zglfw.Key {
    return switch (key) {
        .unknown => .unknown,
        .space => .space,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .minus => .minus,
        .period => .period,
        .slash => .slash,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
        .semicolon => .semicolon,
        .equal => .equal,
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .left_bracket => .left_bracket,
        .backslash => .backslash,
        .right_bracket => .right_bracket,
        .grave_accent => .grave_accent,
        .world_1 => .world_1,
        .world_2 => .world_2,
        .escape => .escape,
        .enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .insert => .insert,
        .delete => .delete,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .page_up => .page_up,
        .page_down => .page_down,
        .home => .home,
        .end => .end,
        .caps_lock => .caps_lock,
        .scroll_lock => .scroll_lock,
        .num_lock => .num_lock,
        .print_screen => .print_screen,
        .pause => .pause,
        .F1 => .F1,
        .F2 => .F2,
        .F3 => .F3,
        .F4 => .F4,
        .F5 => .F5,
        .F6 => .F6,
        .F7 => .F7,
        .F8 => .F8,
        .F9 => .F9,
        .F10 => .F10,
        .F11 => .F11,
        .F12 => .F12,
        .F13 => .F13,
        .F14 => .F14,
        .F15 => .F15,
        .F16 => .F16,
        .F17 => .F17,
        .F18 => .F18,
        .F19 => .F19,
        .F20 => .F20,
        .F21 => .F21,
        .F22 => .F22,
        .F23 => .F23,
        .F24 => .F24,
        .F25 => .F25,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
        .kp_equal => .kp_equal,
        .left_shift => .left_shift,
        .left_control => .left_control,
        .left_alt => .left_alt,
        .left_super => .left_super,
        .right_shift => .right_shift,
        .right_control => .right_control,
        .right_alt => .right_alt,
        .right_super => .right_super,
        .menu => .menu,
        else => undefined,
    };
}

fn glfwKeyToKey(key: zglfw.Key) input.Key {
    return switch (key) {
        .unknown => .unknown,
        .space => .space,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .minus => .minus,
        .period => .period,
        .slash => .slash,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
        .semicolon => .semicolon,
        .equal => .equal,
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .left_bracket => .left_bracket,
        .backslash => .backslash,
        .right_bracket => .right_bracket,
        .grave_accent => .grave_accent,
        .world_1 => .world_1,
        .world_2 => .world_2,
        .escape => .escape,
        .enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .insert => .insert,
        .delete => .delete,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .page_up => .page_up,
        .page_down => .page_down,
        .home => .home,
        .end => .end,
        .caps_lock => .caps_lock,
        .scroll_lock => .scroll_lock,
        .num_lock => .num_lock,
        .print_screen => .print_screen,
        .pause => .pause,
        .F1 => .F1,
        .F2 => .F2,
        .F3 => .F3,
        .F4 => .F4,
        .F5 => .F5,
        .F6 => .F6,
        .F7 => .F7,
        .F8 => .F8,
        .F9 => .F9,
        .F10 => .F10,
        .F11 => .F11,
        .F12 => .F12,
        .F13 => .F13,
        .F14 => .F14,
        .F15 => .F15,
        .F16 => .F16,
        .F17 => .F17,
        .F18 => .F18,
        .F19 => .F19,
        .F20 => .F20,
        .F21 => .F21,
        .F22 => .F22,
        .F23 => .F23,
        .F24 => .F24,
        .F25 => .F25,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
        .kp_equal => .kp_equal,
        .left_shift => .left_shift,
        .left_control => .left_control,
        .left_alt => .left_alt,
        .left_super => .left_super,
        .right_shift => .right_shift,
        .right_control => .right_control,
        .right_alt => .right_alt,
        .right_super => .right_super,
        .menu => .menu,
    };
}
