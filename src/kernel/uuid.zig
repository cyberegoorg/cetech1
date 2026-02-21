const std = @import("std");

const apidb = cetech1.apidb;
const Uuid = @import("Uuid");
const cetech1 = @import("cetech1");
const public = cetech1.uuid;
const profiler = @import("profiler.zig");

const module_name = .uuid;

const api = public.UuidAPI{
    .newUuid7 = newUUID7,
    .fromInt = fromInt,
    .fromStr = fromStr,
};

pub fn init() !void {
    public.api = &api;
}

pub fn registerToApi() !void {
    try apidb.setZigApi(module_name, public.UuidAPI, &api);
}

pub fn newUUID7() public.Uuid {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    return .{ .bytes = Uuid.V7.new().bytes };
}

pub fn fromInt(int: u128) public.Uuid {
    return .{ .bytes = Uuid.fromInt(int).bytes };
}

pub fn fromStr(str: []const u8) ?public.Uuid {
    const u = Uuid.fromString(str) catch return null;
    return .{ .bytes = u.bytes };
}

test "uuid: Can create uuid7" {
    try init();
    const uuid1 = public.newUUID7();
    const uuid2 = public.newUUID7();

    try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
}

test "uuid: Can format uuid to string" {
    try init();
    const uuid1 = public.newUUID7();
    _ = uuid1;

    const uuid = public.fromInt(0x0123456789ABCDEF0123456789ABCDEF);
    try std.testing.expectFmt("01234567-89ab-cdef-0123-456789abcdef", "{f}", .{uuid});
}
