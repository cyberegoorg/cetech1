const std = @import("std");

/// UUID types
pub const Uuid = struct {
    bytes: [16]u8 = .{0} ** 16,

    /// support for zig std fmt
    pub fn format(self: Uuid, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}-{s}-{s}-{s}-{s}", .{
            std.fmt.bytesToHex(self.bytes[0..4], .lower),
            std.fmt.bytesToHex(self.bytes[4..6], .lower),
            std.fmt.bytesToHex(self.bytes[6..8], .lower),
            std.fmt.bytesToHex(self.bytes[8..10], .lower),
            std.fmt.bytesToHex(self.bytes[10..16], .lower),
        });
    }
};

/// Main UUID API
pub const UuidAPI = struct {
    const Self = @This();

    /// Create new UUIDv7
    pub inline fn newUUID7(self: Self) Uuid {
        return self.newUUID7Fn();
    }

    /// Create new UUID from int
    pub inline fn fromInt(self: Self, int: u128) Uuid {
        return self.fromIntFn(int);
    }

    /// Create new UUID from str
    pub inline fn fromStr(self: Self, str: []const u8) ?Uuid {
        return self.fromStrFn(str);
    }

    //#region Pointers to implementation
    newUUID7Fn: *const fn () Uuid,
    fromIntFn: *const fn (int: u128) Uuid,
    fromStrFn: *const fn (str: []const u8) ?Uuid,
    //#endregion
};
