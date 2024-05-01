const std = @import("std");

pub const Key = enum(u32) {
    unknown = 0,
    space,
    apostrophe,
    comma,
    minus,
    period,
    slash,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    semicolon,
    equal,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    left_bracket,
    backslash,
    right_bracket,
    grave_accent,
    world_1,
    world_2,
    escape,
    enter,
    tab,
    backspace,
    insert,
    delete,
    right,
    left,
    down,
    up,
    page_up,
    page_down,
    home,
    end,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
    F21,
    F22,
    F23,
    F24,
    F25,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,
    left_shift,
    left_control,
    left_alt,
    left_super,
    right_shift,
    right_control,
    right_alt,
    right_super,
    menu,
    count,
};

pub const MouseButton = enum(u32) {
    unknown = 0,
    left,
    right,
    middle,
    four,
    five,
    six,
    seven,
    eight,
    count,
};

pub const Action = enum(u8) {
    release = 0,
    press,
    repeat,
};

pub const Mods = packed struct(u32) {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _padding: i26 = 0,
};

pub const CursorMode = enum(u32) {
    normal = 0,
    hidden,
    disabled,
    captured,
};

pub const Joystick = struct {
    pub const Id = u32;
    jid: Id,
    vtable: *const VTable,

    pub const VTable = struct {
        pub fn implement(comptime T: type) VTable {
            _ = T; // autofix
            return VTable{};
        }
    };
};

pub const Gamepad = struct {
    pub const Id = Joystick.Id;

    pub const Axis = enum(u8) {
        left_x = 0,
        left_y = 1,
        right_x = 2,
        right_y = 3,
        left_trigger = 4,
        right_trigger = 5,
        count,

        const last = Axis.count;
    };

    pub const Button = enum(u8) {
        a = 0,
        b = 1,
        x = 2,
        y = 3,
        left_bumper = 4,
        right_bumper = 5,
        back = 6,
        start = 7,
        guide = 8,
        left_thumb = 9,
        right_thumb = 10,
        dpad_up = 11,
        dpad_right = 12,
        dpad_down = 13,
        dpad_left = 14,
        count,

        const last = Button.count;

        const cross = Button.a;
        const circle = Button.b;
        const square = Button.x;
        const triangle = Button.y;
    };

    pub const State = extern struct {
        buttons: [15]Action,
        axes: [6]f32,
    };

    pub fn getState(self: Gamepad) State {
        return self.vtable.getState(self.jid);
    }

    jid: Id,
    vtable: *const VTable,

    pub const VTable = struct {
        getState: *const fn (jid: Id) State,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "getState")) @compileError("implement me");

            return VTable{
                .getState = T.getState,
            };
        }
    };
};

pub const Window = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn closed(self: Window) bool {
        return self.vtable.windowClosed(self.ptr);
    }

    pub fn getInternal(self: Window, comptime T: type) *const T {
        return @ptrCast(self.vtable.getInternalHandler(self.ptr));
    }

    pub fn getFramebufferSize(self: Window) [2]i32 {
        return self.vtable.getFramebufferSize(self.ptr);
    }

    pub fn getContentScale(self: Window) [2]f32 {
        return self.vtable.getContentScale(self.ptr);
    }

    pub fn getOsWindowHandler(self: Window) ?*anyopaque {
        return self.vtable.getOsWindowHandler(self.ptr);
    }

    pub fn getOsDisplayHandler(self: Window) ?*anyopaque {
        return self.vtable.getOsDisplayHandler(self.ptr);
    }

    pub fn getKey(self: Window, key: Key) Action {
        return self.vtable.getKey(self.ptr, key);
    }
    pub fn getMods(self: Window) Mods {
        return self.vtable.getMods(self.ptr);
    }

    pub fn getMouseButton(self: Window, button: MouseButton) Action {
        return self.vtable.getMouseButton(self.ptr, button);
    }
    pub fn getCursorPos(self: Window) [2]f64 {
        return self.vtable.getCursorPos(self.ptr);
    }
    pub fn getCursorPosDelta(self: Window, last_pos: [2]f64) [2]f64 {
        return self.vtable.getCursorPosDelta(self.ptr, last_pos);
    }
    pub fn setCursorMode(self: Window, mode: CursorMode) void {
        return self.vtable.setCursorMode(self.ptr, mode);
    }

    pub const VTable = struct {
        windowClosed: *const fn (window: *anyopaque) bool,
        getInternalHandler: *const fn (window: *anyopaque) *const anyopaque,
        getFramebufferSize: *const fn (window: *anyopaque) [2]i32,
        getContentScale: *const fn (window: *anyopaque) [2]f32,
        getOsWindowHandler: *const fn (window: *anyopaque) ?*anyopaque,
        getOsDisplayHandler: *const fn (window: *anyopaque) ?*anyopaque,
        getKey: *const fn (window: *anyopaque, key: Key) Action,
        getMods: *const fn (window: *anyopaque) Mods,
        getMouseButton: *const fn (window: *anyopaque, button: MouseButton) Action,
        getCursorPos: *const fn (window: *anyopaque) [2]f64,
        getCursorPosDelta: *const fn (window: *anyopaque, last_pos: [2]f64) [2]f64,
        setCursorMode: *const fn (window: *anyopaque, mode: CursorMode) void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "windowClosed")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getInternalHandler")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getFramebufferSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getContentScale")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getOsWindowHandler")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getOsDisplayHandler")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getKey")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getMods")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getMouseButton")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getCursorPos")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getCursorPosDelta")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setCursorMode")) @compileError("implement me");

            return VTable{
                .windowClosed = T.windowClosed,
                .getInternalHandler = T.getInternalHandler,
                .getFramebufferSize = T.getFramebufferSize,
                .getContentScale = T.getContentScale,
                .getOsWindowHandler = T.getOsWindowHandler,
                .getOsDisplayHandler = T.getOsDisplayHandler,
                .getKey = T.getKey,
                .getMods = T.getMods,
                .getMouseButton = T.getMouseButton,
                .getCursorPos = T.getCursorPos,
                .getCursorPosDelta = T.getCursorPosDelta,
                .setCursorMode = T.setCursorMode,
            };
        }
    };
};

pub const Monitor = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VideoMode = extern struct {
        width: c_int,
        height: c_int,
        red_bits: c_int,
        green_bits: c_int,
        blue_bits: c_int,
        refresh_rate: c_int,
    };

    pub fn getVideoMode(self: Monitor) !*VideoMode {
        return self.vtable.getMonitorVideoMode(self.ptr);
    }

    pub const VTable = struct {
        getMonitorVideoMode: *const fn (monitor: *anyopaque) anyerror!*VideoMode,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "getMonitorVideoMode")) @compileError("implement me");

            return VTable{
                .getMonitorVideoMode = T.getMonitorVideoMode,
            };
        }
    };
};

pub const OpenInType = enum {
    reveal,
    open_url,
    edit,
};

pub const PlatformApi = struct {
    getPrimaryMonitor: *const fn () ?Monitor,

    createWindow: *const fn (width: i32, height: i32, title: [:0]const u8, monitor: ?Monitor) anyerror!Window,
    destroyWindow: *const fn (window: Window) void,

    poolEvents: *const fn () void,
    poolEventsWithTimeout: *const fn (timeout: f64) void,

    getJoystick: *const fn (id: Joystick.Id) ?Joystick,
    getGamepad: *const fn (id: Gamepad.Id) ?Gamepad,

    openIn: *const fn (allocator: std.mem.Allocator, open_type: OpenInType, url: []const u8) anyerror!void,
};
