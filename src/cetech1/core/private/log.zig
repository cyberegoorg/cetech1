const std = @import("std");

const public = @import("../cetech1.zig");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");

pub var api = public.log.LogAPI{
    .logFn = log,
};

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.log.LogAPI, &api);

    _ct_log_set_log_api(&api_c);
    try apidb.api.setOrRemoveCApi(public.c.ct_log_api_t, &api_c, true);
}

pub fn log(level: public.log.LogAPI.Level, scope: []const u8, msg: []const u8) void {
    if (profiler.profiler_enabled) {
        const LOG_FORMAT_TRACY = "{s}: {s}";
        var color: u32 = switch (level) {
            .info => 0x00_ff_ff_ff,
            .debug => 0x00_00_ff_00,
            .warn => 0x00_ff_ef_00,
            .err => 0x00_ff_00_00,
        };
        var buffer: [256:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&buffer, LOG_FORMAT_TRACY, .{ scope, msg }) catch undefined;
        profiler.api.msgWithColor(&buffer, color);
    }

    const thread_id = std.Thread.getCurrentId();
    //const thread_name = task.getThreadName(thread_id);

    const LOG_FORMAT = "\t[{d}] {s}:\t{s}";
    const args = .{ thread_id, scope, msg };
    switch (level) {
        .info => std.log.info(LOG_FORMAT, args),
        .debug => std.log.debug(LOG_FORMAT, args),
        .warn => std.log.warn(LOG_FORMAT, args),
        .err => std.log.err(LOG_FORMAT, args),
    }

    var it = apidb.api.getFirstImpl(public.log.LogHandlerI);
    while (it) |node| : (it = node.next) {
        var iface = public.apidb.ApiDbAPI.toInterface(public.log.LogHandlerI, node);
        iface.log(level, scope, msg);
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
