const std = @import("std");

pub const TempAllocApi = struct {
    create: *const fn () anyerror!std.mem.Allocator,
    destroy: *const fn (allocator: std.mem.Allocator) void,
};
