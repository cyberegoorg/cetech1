const std = @import("std");

const zglfw = @import("zglfw");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const kernel = @import("kernel.zig");

const gamemode = @import("mach-gamemode");

const public = @import("../system.zig");

const MODULE_NAME = "system";
const log = std.log.scoped(.system);

pub var api = public.SystemApi{
    .createWindow = createWindow,
    .destroyWindow = destroyWindow,
    .windowClosed = windowClosed,
    .poolEvents = poolEvents,
    .getPrimaryMonitor = getPrimaryMonitor,
    .getMonitorVideoMode = getMonitorVideoMode,
    .poolEventsWithTimeout = poolEventsWithTimeout,
};

var _allocator: std.mem.Allocator = undefined;
var _main_window: ?*public.Window = null;

pub fn init(allocator: std.mem.Allocator, headless: bool) !void {
    _allocator = allocator;

    gamemode.start();

    if (gamemode.isActive()) {
        log.info("Gamemode is active", .{});
    }

    zglfw.init() catch |err| {
        log.warn("System init error {}", .{err});
        return;
    };

    zglfw.windowHintTyped(.client_api, .no_api);
    if (headless) {
        zglfw.windowHintTyped(.visible, false);
    }

    const success = zglfw.Gamepad.updateMappings(@embedFile("embed/gamecontrollerdb.txt"));
    if (!success) {
        @panic("failed to update gamepad mappings");
    }
}

pub fn deinit() void {
    zglfw.terminate();
    gamemode.stop();
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

fn poolEventsWithTimeout(timeout: f64) void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    zglfw.waitEventsTimeout(timeout);
}

fn getPrimaryMonitor() ?*public.Monitor {
    return @ptrCast(zglfw.Monitor.getPrimary() orelse return null);
}

fn getMonitorVideoMode(monitor: *public.Monitor) !*public.VideoMode {
    const true_monitor: *zglfw.Monitor = @ptrCast(monitor);
    const vm = try true_monitor.getVideoMode();
    return @ptrCast(vm);
}
