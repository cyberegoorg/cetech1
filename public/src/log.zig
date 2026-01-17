//! LogAPI is logger. yep very simple =D

const std = @import("std");
const builtin = @import("builtin");
const cetech1 = @import("root.zig");

const LogFn = fn (comptime std.log.Level, comptime @TypeOf(.enum_literal), comptime []const u8, anytype) void;

pub const LogHandlerI = struct {
    pub const c_name = "ct_log_handler_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    log: *const fn (level: LogAPI.Level, scope: [:0]const u8, log_msg: [:0]const u8) anyerror!void,

    pub inline fn implement(comptime T: type) @This() {
        if (!std.meta.hasFn(T, "logFn")) @compileError("implement me");

        return @This(){
            .log = T.logFn,
        };
    }
};

// Main log API
pub const LogAPI = struct {
    const Self = @This();

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

    //#region Pointers to implementation
    logFn: *const fn (level: Level, scope: [:0]const u8, log_msg: [:0]const u8) void,
    //#endregion
};

pub const MAX_LOG_ENTRY_SIZE = 1024 * 6;
pub fn zigLogFnGen(comptime log_api: *const *const LogAPI) LogFn {
    return struct {
        pub fn f(
            comptime level: std.log.Level,
            comptime scope: @TypeOf(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            // const msg2: [std.fmt.count(format, args)]u8 = undefined; //TODO: WHY?
            // _ = msg2;

            var msg: [MAX_LOG_ENTRY_SIZE]u8 = undefined; // TODO: SHIIIIIIIIIIIIITTTTTTTT
            const formated_msg = std.fmt.bufPrintZ(&msg, format, args) catch |e| {
                std.debug.print("caught err writing to buffer {any}\n", .{e});
                return;
            };

            var message: [:0]u8 = formated_msg;
            if (std.mem.endsWith(u8, formated_msg, "\n")) {
                message[message.len - 1] = 0;
                message = message[0 .. message.len - 1 :0];
            }

            log_api.*.logFn(LogAPI.Level.fromStdLevel(level), @tagName(scope), message);
        }
    }.f;
}
