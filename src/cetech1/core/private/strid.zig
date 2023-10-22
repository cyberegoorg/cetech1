const std = @import("std");

const c = @import("../c.zig");
const apidb = @import("./apidb.zig");
const strid = @import("../strid.zig");

const public = @import("../cetech1.zig");

pub var api = public.c.ct_strid_api_t{
    .strid32 = ct_strid32,
    .strid64 = ct_strid64,
};

pub fn registerToApi() !void {
    try apidb.api.setOrRemoveCApi(public.c.ct_strid_api_t, &api, true);
}

fn ct_strid32(str: [*c]const u8) callconv(.C) c.c.ct_strid32_t {
    return strid.strId32(c.fromCstr(str)).to(c.c.ct_strid32_t);
}

fn ct_strid64(str: [*c]const u8) callconv(.C) c.c.ct_strid64_t {
    return strid.strId64(c.fromCstr(str)).to(c.c.ct_strid64_t);
}
