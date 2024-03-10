//! LogAPI is logger. yep very simple =D

const std = @import("std");
const builtin = @import("builtin");
const strid = @import("strid.zig");

const MAX_LOG_ENTRY_SIZE = 256;

pub const LogHandlerI = struct {
    pub const c_name = "ct_log_handler_i";
    pub const name_hash = strid.strId64(@This().c_name);

    log: *const fn (level: LogAPI.Level, scope: []const u8, log_msg: []const u8) void,
};

// Main log API
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

    // Info logging
    pub inline fn info(self: Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        self._log(.info, scope, fmt, args);
    }

    // Warning logging
    pub inline fn warn(self: Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        self._log(.warn, scope, fmt, args);
    }

    // Error logging
    pub inline fn err(self: Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        self._log(.err, scope, fmt, args);
    }

    // Debug logging
    // Not present in non debug builds.
    pub inline fn debug(self: Self, scope: []const u8, fmt: []const u8, args: anytype) void {
        if (builtin.mode != .Debug) {
            return;
        }
        self._log(.debug, scope, fmt, args);
    }

    pub inline fn _log(self: Self, level: Level, scope: []const u8, fmt: []const u8, args: anytype) void {
        var buffer: [MAX_LOG_ENTRY_SIZE]u8 = undefined;
        const log_line = std.fmt.bufPrint(&buffer, fmt, args) catch return;
        self.logFn(level, scope, log_line);
    }

    //#region Pointers to implementation
    logFn: *const fn (level: Level, scope: []const u8, log_msg: []const u8) void,
    //#endregion
};
