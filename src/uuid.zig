const std = @import("std");

/// UUID types
pub const Uuid = struct {
    bytes: [16]u8 = .{0} ** 16,

    /// support for zig std fmt
    pub fn format(self: Uuid, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) (@TypeOf(writer).Error)!void {
        try std.fmt.format(writer, "{}-{}-{}-{}-{}", .{
            std.fmt.fmtSliceHexLower(self.bytes[0..4]),
            std.fmt.fmtSliceHexLower(self.bytes[4..6]),
            std.fmt.fmtSliceHexLower(self.bytes[6..8]),
            std.fmt.fmtSliceHexLower(self.bytes[8..10]),
            std.fmt.fmtSliceHexLower(self.bytes[10..16]),
        });
    }
};

/// Main UUID API
pub const UuidAPI = struct {
    const Self = @This();

    /// Create new UUIDv7
    pub fn newUUID7(self: Self) Uuid {
        return self.newUUID7Fn();
    }

    /// Create new UUID from int
    pub fn fromInt(self: Self, int: u128) Uuid {
        return self.fromIntFn(int);
    }

    /// Create new UUID from str
    pub fn fromStr(self: Self, str: []const u8) ?Uuid {
        return self.fromStrFn(str);
    }

    //#region Pointers to implementation
    newUUID7Fn: *const fn () Uuid,
    fromIntFn: *const fn (int: u128) Uuid,
    fromStrFn: *const fn (str: []const u8) ?Uuid,
    //#endregion
};
