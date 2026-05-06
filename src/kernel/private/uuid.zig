const std = @import("std");

const apidb = cetech1.apidb;
const cetech1 = @import("cetech1");
const public = cetech1.uuid;
const profiler = @import("profiler.zig");

const module_name = .uuid;

const api = public.UuidAPI{
    .newUuid7 = newUUID7,
    .fromInt = fromInt,
    .fromStr = fromStr,
};

var _io: std.Io = undefined;

pub fn init(io: std.Io) !void {
    _io = io;
    public.api = &api;
}

pub fn registerToApi() !void {
    try apidb.setZigApi(module_name, public.UuidAPI, &api);
}

pub fn newUUID7() public.Uuid {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var uuid: public.Uuid = fromInt(0);

    const millis: u64 = @bitCast(std.Io.Timestamp.now(_io, .awake).toMilliseconds());
    const millis_u48: u48 = @truncate(millis);
    std.mem.writeInt(u48, uuid.bytes[0..6], millis_u48, .big);
    _io.random(uuid.bytes[6..]);

    uuid.bytes[8] = 0b10000000 | (uuid.bytes[8] & 0b00111111);
    uuid.bytes[6] = @as(u8, 7) << 4 | (uuid.bytes[6] & 0xF);

    return uuid;
}

pub fn fromInt(int: u128) public.Uuid {
    var uuid: public.Uuid = undefined;
    std.mem.writeInt(u128, uuid.bytes[0..], int, .big);
    return uuid;
}

pub fn fromStr(str: []const u8) ?public.Uuid {
    std.debug.assert(str.len == 36 and str[8] == '-' and str[13] == '-' and str[18] == '-' and str[23] == '-');

    var uuid: public.Uuid = undefined;
    var i: usize = 0;
    for (uuid.bytes[0..]) |*byte| {
        if (str[i] == '-') {
            i += 1;
        }
        const hi = std.fmt.charToDigit(str[i], 16) catch return null;
        const lo = std.fmt.charToDigit(str[i + 1], 16) catch return null;
        byte.* = hi << 4 | lo;
        i += 2;
    }

    return uuid;
}

test "uuid: Can create uuid7" {
    try init(std.testing.io);
    const uuid1 = public.newUUID7();
    const uuid2 = public.newUUID7();

    try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
}

test "uuid: Can format uuid to string" {
    try init(std.testing.io);
    const uuid1 = public.newUUID7();
    _ = uuid1;

    const uuid = public.fromInt(0x0123456789ABCDEF0123456789ABCDEF);
    try std.testing.expectFmt("01234567-89ab-cdef-0123-456789abcdef", "{f}", .{uuid});
}
