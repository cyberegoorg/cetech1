const std = @import("std");

const cetech1 = @import("cetech1");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");

const c = @import("c.zig").c;

pub var api = cetech1.log.LogAPI{
    .logFn = logFn,
};

const module_name = .log;

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, cetech1.log.LogAPI, &api);

    _ct_log_set_log_api(&api_c);
    try apidb.api.setOrRemoveCApi(module_name, c.ct_log_api_t, &api_c, true);
}

pub fn logFn(level: cetech1.log.LogAPI.Level, scope: [:0]const u8, msg: [:0]const u8) void {
    if (profiler.profiler_enabled) {
        const LOG_FORMAT_TRACY = "{s}: {s}";
        const color: u32 = switch (level) {
            .info => 0x00_ff_ff_ff,
            .debug => 0x00_00_ff_00,
            .warn => 0x00_ff_ef_00,
            .err => 0x00_ff_00_00,
            else => 0x00_ff_00_00,
        };
        var buffer: [256:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&buffer, LOG_FORMAT_TRACY, .{ scope, msg }) catch undefined;
        profiler.api.msgWithColor(&buffer, color);
    }

    const thread_id = std.Thread.getCurrentId();
    //const thread_name = task.getThreadName(thread_id);

    const LOG_FORMAT = "[{s}|{d}|{s}]\t{s}";
    const args = .{ level.asText(), thread_id, scope, msg };

    {
        const stderr = std.io.getStdErr().writer();
        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();

        const color: std.io.tty.Color = switch (level) {
            .info => .reset,
            .debug => .green,
            .warn => .yellow,
            .err => .red,
            else => .reset,
        };

        const cfg = std.io.tty.detectConfig(std.io.getStdErr());
        cfg.setColor(stderr, color) catch return;
        nosuspend stderr.print(LOG_FORMAT ++ "\n", args) catch return;
        cfg.setColor(stderr, .reset) catch return;
    }

    var it = apidb.api.getFirstImpl(cetech1.log.LogHandlerI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(cetech1.log.LogHandlerI, node);
        iface.log(@intFromEnum(level), scope.ptr, msg.ptr);
    }
}

extern fn _ct_log_set_log_api(_logapi: *const c.ct_log_api_t) callconv(.C) void;
extern fn _ct_log_va(_logapi: *cetech1.c.ct_log_api_t, log_level: cetech1.c.ct_log_level_e, scope: [*c]const u8, msg: [*c]const u8, va: std.builtin.VaList) callconv(.C) void;
extern fn ct_log_warn(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;
extern fn ct_log_info(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;
extern fn ct_log_err(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;
extern fn ct_log_debug(scope: [*c]const u8, msg: [*c]const u8, ...) callconv(.C) void;

const api_c = c.ct_log_api_t{
    .log = struct {
        pub fn f(level: c.ct_log_level_e, scope: [*c]const u8, log_msg: [*c]const u8) callconv(.C) void {
            logFn(@enumFromInt(level), std.mem.span(scope), std.mem.span(log_msg));
        }
    }.f,
    .info = ct_log_info,
    .debug = ct_log_debug,
    .warn = ct_log_warn,
    .err = ct_log_err,
};

pub fn zigLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    //var msg: [std.fmt.count(format, args)]u8 = undefined; //TODO: WHY?
    var msg: [cetech1.log.MAX_LOG_ENTRY_SIZE]u8 = undefined; // TODO: SHIIIIIIIIIIIIITTTTTTTT
    const formated_msg = std.fmt.bufPrintZ(&msg, format, args) catch |e| {
        std.debug.print("caught err writing to buffer {any}", .{e});
        return;
    };

    var message: [:0]u8 = formated_msg;
    if (std.mem.endsWith(u8, formated_msg, "\n")) {
        message[message.len - 1] = 0;
        message = message[0 .. message.len - 1 :0];
    }

    logFn(cetech1.log.LogAPI.Level.fromStdLevel(level), @tagName(scope), message);
}

test "log: should log messge" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();
    try registerToApi();

    const H = struct {
        var level: cetech1.log.LogAPI.Level = .err;
        var scope: []const u8 = undefined;
        var log_msg: []const u8 = undefined;
        pub fn logFn(level_: cetech1.log.LogAPI.Level, scope_: [:0]const u8, log_msg_: [:0]const u8) !void {
            level = level_;
            scope = scope_;
            log_msg = log_msg_;
        }
    };

    var handler = cetech1.log.LogHandlerI.implement(H);
    try apidb.api.implInterface(.foo, cetech1.log.LogHandlerI, &handler);

    api.logFn(.info, "test", "test msg");
    try std.testing.expectEqual(cetech1.log.LogAPI.Level.info, H.level);
    try std.testing.expectEqualStrings("test", H.scope);
    try std.testing.expectEqualStrings("test msg", H.log_msg);

    api.logFn(.debug, "test_debug", "test debug msg");
    try std.testing.expectEqual(cetech1.log.LogAPI.Level.debug, H.level);
    try std.testing.expectEqualStrings("test_debug", H.scope);
    try std.testing.expectEqualStrings("test debug msg", H.log_msg);

    api.logFn(.warn, "test_warn", "test warn msg");
    try std.testing.expectEqual(cetech1.log.LogAPI.Level.warn, H.level);
    try std.testing.expectEqualStrings("test_warn", H.scope);
    try std.testing.expectEqualStrings("test warn msg", H.log_msg);
}

test "log: should log messge via c api" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();
    try registerToApi();

    const H = struct {
        var level: cetech1.log.LogAPI.Level = .invalid;
        var scope: [:0]const u8 = undefined;
        var log_msg: [:0]const u8 = undefined;
        pub fn logFn(level_: cetech1.log.LogAPI.Level, scope_: [:0]const u8, log_msg_: [:0]const u8) !void {
            level = level_;
            scope = try std.testing.allocator.dupeZ(u8, scope_);
            log_msg = try std.testing.allocator.dupeZ(u8, log_msg_);
        }
    };

    errdefer {
        defer std.testing.allocator.free(H.scope);
        defer std.testing.allocator.free(H.log_msg);
    }

    var handler = cetech1.log.LogHandlerI.implement(H);
    try apidb.api.implInterface(.foo, cetech1.log.LogHandlerI, &handler);

    api_c.info.?.*("test_info", "test info msg");
    try std.testing.expectEqual(cetech1.log.LogAPI.Level.info, H.level);
    try std.testing.expectEqualStrings("test_info", H.scope);
    try std.testing.expectEqualStrings("test info msg", H.log_msg);
    std.testing.allocator.free(H.scope);
    std.testing.allocator.free(H.log_msg);

    api_c.debug.?.*("test_debug", "test debug msg");
    try std.testing.expectEqual(cetech1.log.LogAPI.Level.debug, H.level);
    try std.testing.expectEqualStrings("test_debug", H.scope);
    try std.testing.expectEqualStrings("test debug msg", H.log_msg);
    std.testing.allocator.free(H.scope);
    std.testing.allocator.free(H.log_msg);

    api_c.warn.?.*("test_warn", "test warn msg");
    try std.testing.expectEqual(cetech1.log.LogAPI.Level.warn, H.level);
    try std.testing.expectEqualStrings("test_warn", H.scope);
    try std.testing.expectEqualStrings("test warn msg", H.log_msg);
    std.testing.allocator.free(H.scope);
    std.testing.allocator.free(H.log_msg);
}
