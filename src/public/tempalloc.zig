const std = @import("std");
const cetech1 = @import("cetech1.zig");

const apidb = cetech1.apidb;
pub fn create() !std.mem.Allocator {
    return api.create();
}

pub fn destroy(allocator: std.mem.Allocator) void {
    return api.destroy(allocator);
}

pub const TempAllocApi = struct {
    create: *const fn () anyerror!std.mem.Allocator,
    destroy: *const fn (allocator: std.mem.Allocator) void,
};

pub var api: *const TempAllocApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, TempAllocApi).?;
}
