//! StrId{32, 64} is main hashing type for simple str->int hash.

const std = @import("std");

const Murmur2_32 = std.hash.murmur.Murmur2_32;
const Murmur2_64 = std.hash.murmur.Murmur2_64;

pub const StrId32 = extern struct {
    id: u32 = 0,

    pub fn isEmpty(a: StrId32) bool {
        return a.id == 0;
    }

    pub fn eql(a: StrId32, b: StrId32) bool {
        return a.id == b.id;
    }
};

pub const StrId64 = extern struct {
    id: u64 = 0,

    pub fn isEmpty(a: StrId64) bool {
        return a.id == 0;
    }

    pub fn eql(a: StrId64, b: StrId64) bool {
        return a.id == b.id;
    }

    pub inline fn to(self: *const StrId64, comptime T: type) T {
        return .{ .id = self.id };
    }

    pub inline fn from(comptime T: type, obj: T) StrId64 {
        return .{ .id = obj.id };
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
