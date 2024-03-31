const std = @import("std");

pub const Window = opaque {};
pub const Monitor = opaque {};

pub const VideoMode = extern struct {
    width: c_int,
    height: c_int,
    red_bits: c_int,
    green_bits: c_int,
    blue_bits: c_int,
    refresh_rate: c_int,
};

pub const OpenInType = enum {
    reveal,
    open_url,
    edit,
};

pub const SystemApi = struct {
    createWindow: *const fn (width: i32, height: i32, title: [:0]const u8, monitor: ?*Monitor) anyerror!*Window,
    destroyWindow: *const fn (window: *Window) void,
    windowClosed: *const fn (window: *Window) bool,
    getPrimaryMonitor: *const fn () ?*Monitor,
    getMonitorVideoMode: *const fn (monitor: *Monitor) anyerror!*VideoMode,
    poolEvents: *const fn () void,
    poolEventsWithTimeout: *const fn (timeout: f64) void,

    openIn: *const fn (allocator: std.mem.Allocator, open_type: OpenInType, url: []const u8) anyerror!void,
};
