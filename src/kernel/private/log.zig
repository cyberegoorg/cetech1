const std = @import("std");

const cetech1 = @import("cetech1");
const apidb_private = @import("apidb.zig");
const profiler_private = @import("profiler.zig");

const math = cetech1.math;
const profiler = cetech1.profiler;
const task = cetech1.task;
const apidb = cetech1.apidb;

const public = cetech1.log;

pub const api = cetech1.log.LogAPI{
    .logFn = logFn,
};

const module_name = .log;

var _io: std.Io = undefined;
pub fn init(io: std.Io) !void {
    cetech1.log.api = &api;
    _io = io;
}

pub fn registerToApi() !void {
    try apidb.setZigApi(module_name, cetech1.log.LogAPI, &api);
}

pub const zigLogFn = cetech1.log.zigLogFnGen();

const MAX_HANDLERS = 8;

pub fn logFn(level: cetech1.log.Level, scope: [:0]const u8, msg: [:0]const u8) void {
    // const thread_id = task.getWorkerId();
    //const thread_name = task.getThreadName(thread_id);
    var buffer: [public.MAX_LOG_ENTRY_SIZE]u8 = undefined;

    // {
    //     const LOG_FORMAT = "[{s}|{d}|{s}]\t{s}";
    //     const args = .{ level.asText(), thread_id, scope, msg };
    //
    //     var stderr_w = std.Io.File.stderr().writer(_io, &buffer);
    //     var stderr = &stderr_w.interface;
    //     _ = std.Io.lockStderr(_io, &buffer, null) catch undefined;
    //     defer std.Io.unlockStderr(_io);
    //
    //     defer stderr.flush() catch undefined;
    //
    //     // FIXME: COLORSSSSSSS
    //     // const color: std.process.io.tty.Color = switch (level) {
    //     //     .Info => .reset,
    //     //     .Debug => .green,
    //     //     .Warn => .yellow,
    //     //     .Err => .red,
    //     //     else => .reset,
    //     // };
    //     // const cfg = std.io.tty.detectConfig(std.fs.File.stderr());
    //     // cfg.setColor(stderr, color) catch return;
    //     nosuspend stderr.print(LOG_FORMAT ++ "\n", args) catch return;
    //     // cfg.setColor(stderr, .reset) catch return;
    // }

    if (profiler.profiler_enabled) {
        const LOG_FORMAT_TRACY = "{s}: {s}";
        const color: math.SRGBA = switch (level) {
            .Info => .fromU32(0x00_ff_ff_ff),
            .Debug => .fromU32(0x00_00_ff_00),
            .Warn => .fromU32(0x00_ff_ef_00),
            .Err => .fromU32(0x00_ff_00_00),
            else => .fromU32(0x00_ff_00_00),
        };
        if (std.fmt.bufPrintZ(&buffer, LOG_FORMAT_TRACY, .{ scope, msg })) |_| {
            profiler.msgWithColor(&buffer, color);
        } else |err| switch (err) {
            else => {},
        }
    }

    if (apidb_private.isInit()) {
        var buff: [@sizeOf(*anyopaque) * MAX_HANDLERS]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buff);
        const a = fba.allocator();

        const impls = apidb.getImpl(a, cetech1.log.LogHandlerI) catch undefined;
        for (impls) |iface| {
            iface.log(level, scope, msg) catch continue;
        }
    }
}

test "log: should log messge" {
    try init(std.testing.io);
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();
    profiler_private.init(std.testing.allocator);
    defer profiler_private.deinit();

    try registerToApi();

    const H = struct {
        var level: cetech1.log.Level = .Err;
        var scope: []const u8 = undefined;
        var log_msg: []const u8 = undefined;
        pub fn logFn(level_: cetech1.log.Level, scope_: [:0]const u8, log_msg_: [:0]const u8) !void {
            level = level_;
            scope = scope_;
            log_msg = log_msg_;
        }
    };

    var handler = cetech1.log.LogHandlerI.implement(H);
    try apidb.implInterface(.foo, cetech1.log.LogHandlerI, &handler);

    api.logFn(.Info, "test", "test msg");
    try std.testing.expectEqual(cetech1.log.Level.Info, H.level);
    try std.testing.expectEqualStrings("test", H.scope);
    try std.testing.expectEqualStrings("test msg", H.log_msg);

    api.logFn(.Debug, "test_debug", "test debug msg");
    try std.testing.expectEqual(cetech1.log.Level.Debug, H.level);
    try std.testing.expectEqualStrings("test_debug", H.scope);
    try std.testing.expectEqualStrings("test debug msg", H.log_msg);

    api.logFn(.Warn, "test_warn", "test warn msg");
    try std.testing.expectEqual(cetech1.log.Level.Warn, H.level);
    try std.testing.expectEqualStrings("test_warn", H.scope);
    try std.testing.expectEqualStrings("test warn msg", H.log_msg);
}
