const std = @import("std");

const zglfw = @import("zglfw");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");

const public = @import("../system.zig");

pub var api = public.SystemApi{
    .createWindow = createWindow,
    .destroyWindow = destroyWindow,
    .windowClosed = windowClosed,
    .poolEvents = poolEvents,
};

var _allocator: std.mem.Allocator = undefined;
var _main_window: ?*public.Window = null;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    try zglfw.init();
}

pub fn deinit() void {
    zglfw.terminate();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.SystemApi, &api);
}

fn createWindow(width: i32, height: i32, title: [:0]const u8, monitor: ?*public.Monitor) !*public.Window {
    var w: *zglfw.Window = undefined;
    if (monitor) |m| {
        w = try zglfw.Window.create(width, height, title, @ptrCast(m));
    } else {
        w = try zglfw.Window.create(width, height, title, null);
    }

    if (_main_window == null) {
        _main_window = @ptrCast(w);
    }
    return @ptrCast(w);
}

fn destroyWindow(window: *public.Window) void {
    zglfw.Window.destroy(@ptrCast(window));
}

fn windowClosed(window: *public.Window) bool {
    return zglfw.Window.shouldClose(@ptrCast(window));
}

fn poolEvents() void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    zglfw.pollEvents();
}
