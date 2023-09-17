const std = @import("std");

const public = @import("../cetech1.zig");
const apidb = @import("apidb.zig");

pub var api = public.LogAPI{
    .log = log,
};

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.LogAPI, &api);

    _ct_log_set_log_api(&api_c);
    try apidb.api.setOrRemoveCApi(public.c.ct_log_api_t, &api_c, true, false);
}

pub fn log(level: public.LogAPI.Level, scope: []const u8, msg: []const u8) void {
    const LOG_FORMAT = "\t{s}: {s}";
    switch (level) {
        .info => std.log.info(LOG_FORMAT, .{ scope, msg }),
        .debug => std.log.debug(LOG_FORMAT, .{ scope, msg }),
        .warn => std.log.warn(LOG_FORMAT, .{ scope, msg }),
        .err => std.log.err(LOG_FORMAT, .{ scope, msg }),
    }
}

extern fn _ct_log_set_log_api(_logapi: *public.c.ct_log_api_t) callconv(.C) void;
extern fn _ct_log_va(_logapi: *public.c.ct_log_api_t, log_level: public.c.ct_log_level_e, scope: [*c]const u8, msg: [*c]const u8, va: std.builtin.VaList) callconv(.C) void;
extern fn ct_log_warn(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;
extern fn ct_log_info(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;
extern fn ct_log_err(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;
extern fn ct_log_debug(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;

var api_c = blk: {
    var c_api = struct {
        pub fn c_log(level: public.c.ct_log_level_e, scope: [*c]const u8, log_msg: [*c]const u8) callconv(.C) void {
            log(@enumFromInt(level), scope[0..std.mem.len(scope)], log_msg[0..std.mem.len(log_msg)]);
        }
    };
    break :blk public.c.ct_log_api_t{
        .log = c_api.c_log,
        .info = ct_log_info,
        .debug = ct_log_debug,
        .warn = ct_log_warn,
        .err = ct_log_err,
    };
};
