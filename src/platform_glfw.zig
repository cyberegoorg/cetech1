const std = @import("std");
const builtin = @import("builtin");

const zglfw = @import("zglfw");

const apidb = @import("apidb.zig");
const kernel = @import("kernel.zig");

const cetech1 = @import("cetech1");
const public = cetech1.platform;

const module_name = .platform_glfw;

const log = std.log.scoped(module_name);

const gamepaddb = @embedFile("gamecontrollerdb");
const findWindowByInternal = @import("platform.zig").findWindowByInternal;
const Window = @import("platform.zig").Window;

var _allocator: std.mem.Allocator = undefined;
pub fn init(allocator: std.mem.Allocator, headless: bool) !void {
    _allocator = allocator;

    try zglfw.init();

    zglfw.windowHint(.client_api, .no_api);

    if (headless) {
        zglfw.windowHint(.visible, false);
    }

    //zglfw.windowHint(.scale_to_monitor, true);

    if (!zglfw.Gamepad.updateMappings(gamepaddb)) {
        log.err("Failed to update gamepad mappings", .{});
    }
}

pub fn deinit() void {
    zglfw.terminate();
}

pub const window_vt = public.Window.VTable.implement(struct {
    pub fn setCursorMode(window: *anyopaque, mode: public.CursorMode) void {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        glfw_w.setInputMode(.cursor, cursorModeTOGlfw(mode)) catch undefined;
    }

    pub fn getKey(window: *anyopaque, key: public.Key) public.Action {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfwActionToAction(glfw_w.getKey(keyToglfwKey(key)));
    }

    pub fn getMods(window: *anyopaque) public.Mods {
        const true_w: *Window = @ptrCast(@alignCast(window));
        return true_w.key_mods;
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

    pub fn getMouseButton(window: *anyopaque, button: public.MouseButton) public.Action {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfwActionToAction(glfw_w.getMouseButton(mouseButtonToGlfwMouseButton(button)));
    }

    pub fn getCursorPos(window: *anyopaque) [2]f64 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfw_w.getCursorPos();
    }

    pub fn getCursorPosDelta(window: *anyopaque, last_pos: [2]f64) [2]f64 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        const pos = glfw_w.getCursorPos();
        return .{ pos[0] - last_pos[0], last_pos[1] - pos[1] };
    }

    pub fn getFramebufferSize(window: *anyopaque) [2]i32 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfw_w.getFramebufferSize();
    }

    pub fn getContentScale(window: *anyopaque) [2]f32 {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfw_w.getContentScale();
    }

    pub fn getInternalHandler(window: *anyopaque) *const anyopaque {
        const true_w: *Window = @ptrCast(@alignCast(window));
        const glfw_w: *zglfw.Window = @ptrCast(true_w.window);
        return glfw_w;
    }
});

const joystick_vt = public.Joystick.VTable.implement(struct {});
const gamepad_vt = public.Gamepad.VTable.implement(struct {
    pub fn getState(id: public.Gamepad.Id) public.Gamepad.State {
        var s = zglfw.Gamepad.getState(@enumFromInt(id));
        return @as(*public.Gamepad.State, @ptrCast(&s)).*;
    }
});

pub const monitor_vt = public.Monitor.VTable.implement(struct {
    pub fn getMonitorVideoMode(monitor: *anyopaque) !*public.Monitor.VideoMode {
        const true_monitor: *zglfw.Monitor = @ptrCast(monitor);
        const vm = try true_monitor.getVideoMode();
        return @ptrCast(vm);
    }
});

pub fn getJoystick(id: public.Joystick.Id) ?public.Joystick {
    if (!zglfw.Joystick.isPresent(@enumFromInt(id))) return null;

    return .{ .jid = id, .vtable = &joystick_vt };
}

pub fn getGamepad(id: public.Gamepad.Id) ?public.Gamepad {
    if (!zglfw.Joystick.isPresent(@enumFromInt(id))) return null;

    return .{ .jid = id, .vtable = &gamepad_vt };
}

pub fn createWindow(width: i32, height: i32, title: [:0]const u8, monitor: ?public.Monitor) !*anyopaque {
    var w: *zglfw.Window = undefined;
    if (monitor) |m| {
        w = try zglfw.Window.create(width, height, title, @ptrCast(m.ptr));
    } else {
        w = try zglfw.Window.create(width, height, title, null);
    }

    return w;
}

pub fn destroyWindow(window: public.Window) void {
    const true_w: *Window = @ptrCast(@alignCast(window.ptr));
    zglfw.Window.destroy(@ptrCast(true_w.window));
}

pub fn poolEvents() void {
    zglfw.pollEvents();
}

pub fn poolEventsWithTimeout(timeout: f64) void {
    zglfw.waitEventsTimeout(timeout);
}

pub fn getPrimaryMonitor() ?*anyopaque {
    return @ptrCast(zglfw.Monitor.getPrimary() orelse return null);
}

fn mouseButtonCallback(window: *zglfw.Window, button: zglfw.MouseButton, action: zglfw.Action, mods: zglfw.Mods) callconv(.c) void {
    _ = button; // autofix
    _ = action; // autofix
    const true_w = findWindowByInternal(window) orelse return;
    true_w.key_mods = .{
        .shift = mods.shift,
        .control = mods.control,
        .alt = mods.alt,
        .super = mods.super,
        .caps_lock = mods.caps_lock,
        .num_lock = mods.num_lock,
    };
}

fn keyCallback(window: *zglfw.Window, key: zglfw.Key, scancode: i32, action: zglfw.Action, mods: zglfw.Mods) callconv(.c) void {
    _ = key; // autofix
    _ = action; // autofix
    const true_w = findWindowByInternal(window) orelse return;

    true_w.key_mods = .{
        .shift = mods.shift,
        .control = mods.control,
        .alt = mods.alt,
        .super = mods.super,
        .caps_lock = mods.caps_lock,
        .num_lock = mods.num_lock,
    };

    _ = scancode;
}

fn glfwActionToAction(action: zglfw.Action) public.Action {
    return switch (action) {
        .release => .release,
        .press => .press,
        .repeat => .repeat,
    };
}

fn cursorModeTOGlfw(button: public.CursorMode) zglfw.Cursor.Mode {
    return switch (button) {
        .normal => .normal,
        .hidden => .hidden,
        .disabled => .disabled,
        .captured => .captured,
    };
}

fn mouseButtonToGlfwMouseButton(button: public.MouseButton) zglfw.MouseButton {
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

fn keyToglfwKey(key: public.Key) zglfw.Key {
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
