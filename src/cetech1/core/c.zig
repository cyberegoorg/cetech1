//!  some c related helper fce

const std = @import("std");

pub inline fn fromCstr(c_str: [*c]const u8) []const u8 {
    return std.mem.sliceTo(c_str, 0);
}

pub inline fn fromCstrZ(c_str: [*c]const u8) [:0]const u8 {
    return c_str[0..std.mem.len(c_str) :0];
}
