const std = @import("std");

const cetech1 = @import("cetech1");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");

pub var api = cetech1.tempalloc.TempAllocApi{
    .create = create,
    .destroy = destroy,
};
const module_name = .tempalloc;

var _allocator: std.mem.Allocator = undefined;
var _tmp_pool: cetech1.heap.TmpAllocatorPool = undefined;

pub fn init(allocator: std.mem.Allocator, max_allocators: u32) !void {
    _allocator = allocator;
    _tmp_pool = try cetech1.heap.TmpAllocatorPool.init(allocator, max_allocators);
}

pub fn deinit() void {
    _tmp_pool.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, cetech1.tempalloc.TempAllocApi, &api);
}

fn create() !std.mem.Allocator {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    return _tmp_pool.create();
}

fn destroy(allocator: std.mem.Allocator) void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    _tmp_pool.destroy(allocator);
}
