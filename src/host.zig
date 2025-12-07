const std = @import("std");
const builtin = @import("builtin");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const kernel = @import("kernel.zig");

const cetech1 = @import("cetech1");
const cetech1_options = @import("cetech1_options");
const public = cetech1.host;
const input = cetech1.input;

const module_name = .host;

const log = std.log.scoped(module_name);

// TODO: by options
const system_backend = @import("host_system.zig");
const host_backend = @import("host_glfw.zig");
const dialogs_backend = @import("host_dialogs_znfde.zig");

pub const system_api = system_backend.system_api;
pub const monitor_api = host_backend.monitor_api;
pub const window_api = host_backend.window_api;
pub const dialogs_api = dialogs_backend.dialogs_api;

pub var api = public.PlatformApi{
    .update = update,
};

var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator, headless: bool) !void {
    _allocator = allocator;
    try dialogs_backend.init();

    host_backend.init(allocator, headless) catch |err| {
        log.warn("System init error {}", .{err});
        return;
    };
}

pub fn deinit() void {
    dialogs_backend.deinit();
    host_backend.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.PlatformApi, &api);

    try system_backend.registerToApi();
    try host_backend.registerToApi();
    try dialogs_backend.registerToApi();
}

fn update(kernel_time: u64, timeout: f64) !void {
    try host_backend.update(kernel_time, timeout);
}
