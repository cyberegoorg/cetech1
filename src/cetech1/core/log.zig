//! LogAPI is logger. yep very simple =D

const std = @import("std");
const builtin = @import("builtin");

pub const LogAPI = struct {
    const Self = @This();

    pub const Level = enum {
        /// Error: something has gone wrong. This might be recoverable or might
        /// be followed by the program exiting.
        /// Warning: it is uncertain if something has gone wrong or not, but the
        err,
        /// circumstances would be worth investigating.
        warn,
        /// Info: general messages about the state of the program.
        info,
        /// Debug: messages only useful for debugging.
        debug,
    };

    log: *const fn (level: Level, scope: []const u8, log_msg: []const u8) void,

    pub inline fn info(self: *Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        self._log(.info, scope, fmt, args);
    }
    pub inline fn warn(self: *Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        self._log(.warn, scope, fmt, args);
    }
    pub inline fn err(self: *Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        self._log(.err, scope, fmt, args);
    }
    pub inline fn debug(self: *Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        if (builtin.mode != .Debug) {
            return;
        }
        self._log(.debug, scope, fmt, args);
    }

    pub inline fn _log(self: *Self, level: Level, scope: []const u8, fmt: []const u8, args: anytype) void {
        var buffer: [128]u8 = undefined;
        var log_line = std.fmt.bufPrint(&buffer, fmt, args) catch return;
        self.log(level, scope, log_line);
    }
};
