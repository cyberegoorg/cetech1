pub const Window = opaque {};
pub const Monitor = opaque {};

pub const SystemApi = struct {
    createWindow: *const fn (width: i32, height: i32, title: [:0]const u8, monitor: ?*Monitor) anyerror!*Window,
    destroyWindow: *const fn (window: *Window) void,
    windowClosed: *const fn (window: *Window) bool,
    poolEvents: *const fn () void,
};
