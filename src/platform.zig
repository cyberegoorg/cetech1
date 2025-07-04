const std = @import("std");
const builtin = @import("builtin");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const kernel = @import("kernel.zig");

//const gamemode = @import("mach-gamemode");

const cetech1 = @import("cetech1");
const public = cetech1.platform;

const module_name = .platform;

const log = std.log.scoped(module_name);

// TODO: by options
const backend = @import("platform_glfw.zig");

pub const Window = struct {
    window: *anyopaque,
    key_mods: public.Mods = .{},

    pub fn init(window: *anyopaque) Window {
        const w = Window{
            .window = window,
        };
        return w;
    }
};

const WindowPool = cetech1.heap.PoolWithLock(Window);
const WindowSet = cetech1.ArraySet(*Window);

pub var api = public.PlatformApi{
    .createWindow = createWindow,
    .destroyWindow = destroyWindow,
    .poolEvents = poolEvents,
    .getPrimaryMonitor = getPrimaryMonitor,
    .poolEventsWithTimeout = poolEventsWithTimeout,
    .openIn = openIn,
    .getJoystick = getJoystick,
    .getGamepad = getGamepad,
};

var _allocator: std.mem.Allocator = undefined;
var _main_window: ?public.Window = null;
var _window_pool: WindowPool = undefined;
var _window_set: WindowSet = undefined;

const gamepaddb = @embedFile("gamecontrollerdb");

pub fn init(allocator: std.mem.Allocator, headless: bool) !void {
    _allocator = allocator;

    _window_pool = WindowPool.init(allocator);
    _window_set = .init();

    // gamemode.start();
    // if (gamemode.isActive()) {
    //    log.info("Gamemode is active", .{});
    // }

    backend.init(allocator, headless) catch |err| {
        log.warn("System init error {}", .{err});
        return;
    };
}

pub fn deinit() void {
    backend.deinit();

    _window_pool.deinit();
    _window_set.deinit(_allocator);

    //gamemode.stop();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.PlatformApi, &api);
}

fn getJoystick(id: public.Joystick.Id) ?public.Joystick {
    return backend.getJoystick(id);
}

fn getGamepad(id: public.Gamepad.Id) ?public.Gamepad {
    return backend.getGamepad(id);
}

fn createWindow(width: i32, height: i32, title: [:0]const u8, monitor: ?public.Monitor) !public.Window {
    const w = try backend.createWindow(width, height, title, monitor);

    const new_w = try _window_pool.create();
    new_w.* = Window.init(w);
    _ = try _window_set.add(_allocator, new_w);

    const window = public.Window{ .ptr = new_w, .vtable = &backend.window_vt };

    if (_main_window == null) {
        _main_window = window;
    }

    return window;
}

fn destroyWindow(window: public.Window) void {
    const true_w: *Window = @alignCast(@ptrCast(window.ptr));

    backend.destroyWindow(window);

    _ = _window_set.remove(true_w);
    _window_pool.destroy(true_w);
}

fn poolEvents() void {
    // var zone_ctx = profiler.ztracy.Zone(@src());
    // defer zone_ctx.End();
    backend.poolEvents();
}

fn poolEventsWithTimeout(timeout: f64) void {
    // var zone_ctx = profiler.ztracy.Zone(@src());
    // defer zone_ctx.End();
    backend.poolEventsWithTimeout(timeout);
}

fn getPrimaryMonitor() ?public.Monitor {
    return .{ .ptr = backend.getPrimaryMonitor() orelse return null, .vtable = &backend.monitor_vt };
}

fn openIn(allocator: std.mem.Allocator, open_type: public.OpenInType, url: []const u8) !void {
    var args = cetech1.ArrayList([]const u8){};
    defer args.deinit(allocator);

    switch (builtin.os.tag) {
        .windows => {
            // use explorer or start
            switch (open_type) {
                .reveal => {
                    try args.append(allocator, "explorer");
                },
                else => {
                    try args.append(allocator, "start");
                },
            }

            try args.append(allocator, url);
        },
        .macos => {
            try args.append(allocator, "open");

            // Open args
            switch (open_type) {
                .reveal => try args.append(allocator, "-R"),
                .edit => try args.append(allocator, "-t"),
                else => {},
            }

            try args.append(allocator, url);
        },
        else => {
            try args.append(allocator, "xdg-open");

            // xdg args
            switch (open_type) {
                .reveal => try args.append(allocator, std.fs.path.dirname(url).?),
                else => try args.append(allocator, url),
            }
        },
    }

    var child = std.process.Child.init(args.items, _allocator);
    _ = try child.spawnAndWait();
}

pub fn findWindowByInternal(window: *anyopaque) ?*Window {
    for (_window_set.unmanaged.keys()) |w| {
        if (w.window == window) return w;
    }
    return null;
}
