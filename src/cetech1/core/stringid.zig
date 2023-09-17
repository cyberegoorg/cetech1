//! StrId{32, 64} is main hashing type for simple str->int hash.

const std = @import("std");

const c = @import("c.zig");

const Murmur2_32 = std.hash.murmur.Murmur2_32;
const Murmur2_64 = std.hash.murmur.Murmur2_64;

pub const StrId32 = c.c.ct_strid32_t;
pub const StrId64 = c.c.ct_strid64_t;

pub inline fn strId32(str: []const u8) StrId32 {
    return .{
        .id = Murmur2_32.hash(str),
    };
}

pub inline fn strId64(str: []const u8) StrId64 {
    return .{
        .id = Murmur2_64.hash(str),
    };
}
