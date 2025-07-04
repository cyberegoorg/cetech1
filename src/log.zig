const std = @import("std");

const cetech1 = @import("cetech1");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");

pub const api = cetech1.log.LogAPI{
    .logFn = logFn,
};

const module_name = .log;

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, cetech1.log.LogAPI, &api);
}

pub const zigLogFn = cetech1.log.zigLogFnGen(&&api);

const MAX_HANDLERS = 8;

pub fn logFn(level: cetech1.log.LogAPI.Level, scope: [:0]const u8, msg: [:0]const u8) void {
    const thread_id = task.api.getWorkerId();
    //const thread_name = task.getThreadName(thread_id);

    {
        const LOG_FORMAT = "[{s}|{d}|{s}]\t{s}";
        const args = .{ level.asText(), thread_id, scope, msg };

        const stderr = std.io.getStdErr().writer();
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();

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
        if (std.fmt.bufPrintZ(&buffer, LOG_FORMAT_TRACY, .{ scope, msg })) |_| {
            profiler.api.msgWithColor(&buffer, color);
        } else |err| switch (err) {
            else => {},
        }
    }

    if (apidb.isInit()) {
        var buff: [@sizeOf(*anyopaque) * MAX_HANDLERS]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buff);
        const a = fba.allocator();

        const impls = apidb.api.getImpl(a, cetech1.log.LogHandlerI) catch undefined;
        for (impls) |iface| {
            iface.log(level, scope, msg) catch continue;
        }
    }
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
