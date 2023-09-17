//! Cetech1 C -> ZIG api + some c related helper fce

const std = @import("std");

pub const c = @cImport({
    @cInclude("cetech1/core/core.h");
});

pub inline fn fromCstr(c_str: [*c]const u8) []const u8 {
    return c_str[0..std.mem.len(c_str)];
}
