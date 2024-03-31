const std = @import("std");

const c = @import("c.zig").c;
const apidb = @import("./apidb.zig");

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const public = cetech1;

const module_name = .strid;

pub var api = c.ct_strid_api_t{
    .strid32 = ct_strid32,
    .strid64 = ct_strid64,
};

pub fn registerToApi() !void {
    try apidb.api.setOrRemoveCApi(module_name, c.ct_strid_api_t, &api, true);
}

fn ct_strid32(str: [*c]const u8) callconv(.C) c.ct_strid32_t {
    return .{ .id = strid.strId32(public.fromCstr(str)).id };
}

fn ct_strid64(str: [*c]const u8) callconv(.C) c.ct_strid64_t {
    return .{ .id = strid.strId64(public.fromCstr(str)).id };
}

test "strid: should use ct_strid32" {
    try std.testing.expectEqual(strid.strId32("foo").id, ct_strid32("foo").id);
}

test "strid: should use ct_strid64" {
    try std.testing.expectEqual(strid.strId64("foo").id, ct_strid64("foo").id);
}

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_strid32_t) == @sizeOf(public.strid.StrId32));
    std.debug.assert(@sizeOf(c.ct_strid64_t) == @sizeOf(public.strid.StrId64));
}
