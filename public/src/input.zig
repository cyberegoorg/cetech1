const std = @import("std");

const strid = @import("string.zig");

pub const KEYBOARD_TYPE = strid.strId32("keyboard");
pub const MOUSE_TYPE = strid.strId32("mouse");
pub const GAMEPAD_TYPE = strid.strId32("gamepad");

pub const Action = enum(u8) {
    release = 0,
    press,
    repeat,
};

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

pub const MouseAxis = enum(u32) {
    scroll_x = 9,
    scroll_y = 10,
    count,
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

pub const GamepadButton = enum(u8) {
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

    const cross = GamepadButton.a;
    const circle = GamepadButton.b;
    const square = GamepadButton.x;
    const triangle = GamepadButton.y;
};

pub const GamepadAxis = enum(u8) {
    left_x = 15,
    left_y = 16,
    right_x = 17,
    right_y = 18,
    left_trigger = 19,
    right_trigger = 20,
    count,
};

pub const ControlerId = u64;
pub const ItemId = u64;

pub const InputItem = struct {
    id: ItemId,
    name: []const u8,
};

pub const ItemData = union(enum) {
    action: Action,
    f: f32,
};

pub const InputSourceI = struct {
    pub const c_name = "ct_input_source_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8,
    input_type: strid.StrId32,

    getItems: *const fn () []const InputItem,
    getControllers: *const fn (allocator: std.mem.Allocator) anyerror![]ControlerId,

    getState: *const fn (controler_id: ControlerId, item_type: ItemId) ?ItemData,

    pub inline fn implment(name: [:0]const u8, input_type: strid.StrId32, comptime T: type) InputSourceI {
        if (!std.meta.hasFn(T, "getItems")) @compileError("implement me");
        if (!std.meta.hasFn(T, "getControllers")) @compileError("implement me");
        if (!std.meta.hasFn(T, "getState")) @compileError("implement me");

        return InputSourceI{
            .name = name,
            .input_type = input_type,

            .getItems = T.getItems,
            .getControllers = T.getControllers,

            .getState = T.getState,
        };
    }
};

pub const InputApi = struct {
    getSourceByType: *const fn (allocator: std.mem.Allocator, input_type: strid.StrId32) ?*const InputSourceI,
};
