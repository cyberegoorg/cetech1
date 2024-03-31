//!  some c related helper fce

pub const c = @cImport({
    @cInclude("cetech1/core/core.h");
});

const std = @import("std");

pub inline fn fromCstr(c_str: [*c]const u8) []const u8 {
    return std.mem.span(c_str);
    //return std.mem.sliceTo(c_str, 0);
}

pub inline fn fromCstrZ(c_str: [*c]const u8) [:0]const u8 {
    return std.mem.span(c_str);
    //return c_str[0..std.mem.len(c_str) :0];
}
