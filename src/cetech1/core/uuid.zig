pub const Uuid = struct {
    bytes: [16]u8 = .{0} ** 16,
};

pub const UuidAPI = struct {
    const Self = @This();

    pub fn newUUID7(self: *Self) Uuid {
        return self.newUUID7Fn.?();
    }

    newUUID7Fn: ?*const fn () Uuid,
};
