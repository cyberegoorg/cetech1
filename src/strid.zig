//! StrId{32, 64} is main hashing type for simple str->int hash.

const std = @import("std");

const Murmur2_32 = std.hash.murmur.Murmur2_32;
const Murmur2_64 = std.hash.murmur.Murmur2_64;

pub const StrId32 = extern struct {
    id: u32 = 0,
};

pub const StrId64 = extern struct {
    id: u64 = 0,

    pub inline fn to(self: *const StrId64, comptime T: type) T {
        return .{ .id = self.id };
    }

    pub inline fn from(comptime T: type, obj: T) StrId64 {
        return .{ .id = obj.id };
    }

    pub inline fn fromCArray(comptime T: type, array: [*]const T, n: usize) []StrId64 {
        var a: []StrId64 = undefined;
        a.ptr = @ptrFromInt(@intFromPtr(array));
        a.len = n;
        return a;
    }
};

/// Create StrId32 from string/data
pub inline fn strId32(str: []const u8) StrId32 {
    return .{
        .id = Murmur2_32.hash(str),
    };
}

/// Create StrId64 from string/data
pub inline fn strId64(str: []const u8) StrId64 {
    return .{
        .id = Murmur2_64.hash(str),
    };
}
