const std = @import("std");

const builtin = @import("builtin");

const zbgfx = @import("zbgfx");

// TODO: fix some invalid type in original bgfx generator
//const bgfx = zbgfx.bgfx;
const bgfx = @import("bgfx.zig");

const gpu_bgfx = @import("gpu_bgfx.zig");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");

const cetech1 = @import("cetech1");
const public = cetech1.gpu;

const zm = cetech1.math.zmath;

const log = std.log.scoped(.gpu);
const module_name = .gpu;

var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    try gpu_bgfx.init(allocator);
}

pub fn deinit() void {
    gpu_bgfx.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.GpuApi, &api);

    try gpu_bgfx.registerToApi();
}

pub const api = public.GpuApi{
    .createBackend = createContext,
    .destroyBackend = destroyContext,
};

fn createContext(
    window: ?cetech1.platform.Window,
    backend: ?[]const u8,
    vsync: bool,
    headles: bool,
    debug: bool,
    profile: bool,
) !?public.GpuBackend {
    const impls = try apidb.api.getImpl(_allocator, public.GpuBackendI);
    defer _allocator.free(impls);

    if (backend) |b| {
        for (impls) |iface| {
            if (!std.ascii.eqlIgnoreCase(b, iface.name)) continue;
            return try iface.createBackend(window, b, vsync, headles, debug, profile);
        }
        log.err("Unknow gpu backend: {s}", .{b});
    } else {
        for (impls) |iface| {
            if (!iface.isDefault(iface.name, headles)) continue;
            return try iface.createBackend(window, iface.name, vsync, headles, debug, profile);
        }
        log.err("No default gpu backend", .{});
    }

    log.err("No valid backend for this platform", .{});
    return null;
}

fn destroyContext(ctx: public.GpuBackend) void {
    ctx.api.destroyBackend(ctx.inst);
}
