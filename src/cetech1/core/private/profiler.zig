const std = @import("std");
const Src = std.builtin.SourceLocation;

pub const ztracy = @import("ztracy");
pub const profiler_enabled = @import("ztracy_options").enable_ztracy;

const public = @import("../profiler.zig");

var _zone_pool: std.heap.MemoryPool(ztracy.ZoneCtx) = undefined;
var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    _allocator = allocator;
    _zone_pool = std.heap.MemoryPool(ztracy.ZoneCtx).init(allocator);
}

pub fn deinit() void {}

fn msgWithColor(text: []const u8, color: u32) void {
    ztracy.MessageC(text, color);
}

fn alloc(ptr: ?*const anyopaque, size: usize) void {
    ztracy.Alloc(ptr, size);
}

fn free(ptr: ?*const anyopaque) void {
    ztracy.Free(ptr);
}

fn allocNamed(name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void {
    ztracy.AllocN(ptr, size, name);
}

fn freeNamed(name: [*:0]const u8, ptr: ?*const anyopaque) void {
    ztracy.FreeN(ptr, name);
}

fn frameMark() void {
    ztracy.FrameMark();
}

fn plotU64(name: [*:0]const u8, val: u64) void {
    ztracy.PlotU(name, val);
}

pub var api = public.ProfilerAPI{
    .msgWithColorFn = msgWithColor,
    .allocFn = alloc,
    .freeFn = free,
    .allocNamedFn = allocNamed,
    .freeNamedFn = freeNamed,
    .frameMarkFn = frameMark,
    .plotU64Fn = plotU64,
};
