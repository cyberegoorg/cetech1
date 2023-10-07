const std = @import("std");

const apidb = @import("apidb.zig");
const Uuid = @import("Uuid");
const public = @import("../uuid.zig");
const profiler = @import("profiler.zig");

pub var api = public.UuidAPI{
    .newUUID7Fn = newUUID7,
};

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.UuidAPI, &api);
}

pub fn newUUID7() public.Uuid {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    return .{ .bytes = Uuid.V7.new().bytes };
}

test "uuid: Can create uuid7" {
    const uuid1 = api.newUUID7();
    const uuid2 = api.newUUID7();

    try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
}
