//! LogAPI is logger. yep very simple =D

const std = @import("std");
const builtin = @import("builtin");
const cetech1 = @import("cetech1.zig");
const apidb = cetech1.apidb;

const LogFn = fn (comptime std.log.Level, comptime @TypeOf(.enum_literal), comptime []const u8, anytype) void;

pub const LogHandlerI = struct {
    pub const c_name = "ct_log_handler_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    log: *const fn (level: Level, scope: [:0]const u8, log_msg: [:0]const u8) anyerror!void,

    pub inline fn implement(comptime T: type) @This() {
        return @This(){
            .log = T.logFn,
        };
    }
};

pub const Level = enum {
    Invalid,

    /// Error: something has gone wrong. This might be recoverable or might
    /// be followed by the program exiting.
    /// Warning: it is uncertain if something has gone wrong or not, but the
    Err,
    /// circumstances would be worth investigating.
    Warn,
    /// Info: general messages about the state of the program.
    Info,
    /// Debug: messages only useful for debugging.
    Debug,

    pub fn asText(self: Level) []const u8 {
        return switch (self) {
            .Err => "E",
            .Warn => "W",
            .Info => "I",
            .Debug => "D",
            else => "SHIT",
        };
    }

    pub fn fromStdLevel(level: std.log.Level) Level {
        return switch (level) {
            .err => .Err,
            .warn => .Warn,
            .info => .Info,
            .debug => .Debug,
        };
    }
};

pub const MAX_LOG_ENTRY_SIZE = 128;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // TODO: For now we send full log to standard zig log.
    // And max MAX_LOG_ENTRY_SIZE to cetech log that dont print to stdout, but
    // only send to profiler and handlers.
    std.log.defaultLog(level, scope, format, args);

    // We write max MAX_LOG_ENTRY_SIZE and send it to cetech1 log.
    var msg: [MAX_LOG_ENTRY_SIZE]u8 = undefined;
    const formated_msg = blk: {
        break :blk std.fmt.bufPrintZ(&msg, format, args) catch |e| {
            switch (e) {
                error.NoSpaceLeft => {
                    msg[msg.len - 1] = 0;
                    break :blk msg[0 .. msg.len - 1 :0];
                },
            }
        };
    };

    var message: [:0]u8 = formated_msg;
    if (std.mem.endsWith(u8, formated_msg, "\n")) {
        message[message.len - 1] = 0;
        message = message[0 .. message.len - 1 :0];
    }

    api.logFn(Level.fromStdLevel(level), @tagName(scope), message);
}

// Main log API
pub const LogAPI = struct {
    logFn: *const fn (level: Level, scope: [:0]const u8, log_msg: [:0]const u8) void,
};

pub var api: *const LogAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, LogAPI).?;
}

pub fn zigLogFnGen() LogFn {
    return log;
}
