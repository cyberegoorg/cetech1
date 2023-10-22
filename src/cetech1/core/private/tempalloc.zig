const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");

pub var api = cetech1.tempalloc.TempAllocApi{
    .createTempArena = createTempArena,
    .destroyTempArena = destroyTempArena,
};

var _allocator: std.mem.Allocator = undefined;
var _tmp_pool: cetech1.mem.TmpAllocatorPool = undefined;

pub fn init(allocator: std.mem.Allocator, max_allocators: u32) !void {
    _allocator = allocator;
    _tmp_pool = try cetech1.mem.TmpAllocatorPool.init(allocator, max_allocators);
}

pub fn deinit() void {
    _tmp_pool.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(cetech1.tempalloc.TempAllocApi, &api);
}

fn createTempArena() !*std.heap.ArenaAllocator {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    return _tmp_pool.create();
}

fn destroyTempArena(arena: *std.heap.ArenaAllocator) void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    _tmp_pool.destroy(arena);
}
