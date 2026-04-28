const std = @import("std");
const cetech1 = @import("root.zig");

const apidb = cetech1.apidb;
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

/// Create new UUIDv7
pub inline fn newUUID7() Uuid {
    return api.newUuid7();
}

/// Create new UUID from int
pub inline fn fromInt(int: u128) Uuid {
    return api.fromInt(int);
}

/// Create new UUID from str
pub inline fn fromStr(str: []const u8) ?Uuid {
    return api.fromStr(str);
}

/// Main UUID API
pub const UuidAPI = struct {
    newUuid7: *const fn () Uuid,
    fromInt: *const fn (int: u128) Uuid,
    fromStr: *const fn (str: []const u8) ?Uuid,
};

pub var api: *const UuidAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, UuidAPI).?;
}
