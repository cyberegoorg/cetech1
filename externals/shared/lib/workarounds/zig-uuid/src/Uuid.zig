//! Root library file that exposes the public API.

const std = @import("std");

const Uuid = @This();

/// Nil UUID with all bits set to zero.
pub const NIL = fromInt(0);

bytes: [16]u8,

pub const Error = error{
    InvalidCharacter,
    InvalidEnumTag,
};

/// Creates a UUID from a u128-bit integer.
pub fn fromInt(int: u128) Uuid {
    var uuid: Uuid = undefined;
    std.mem.writeInt(u128, uuid.bytes[0..], int, .big);
    return uuid;
}

test "fromInt" {
    try std.testing.expectEqual([1]u8{0x0} ** 16, NIL.bytes);
}

/// Creates a UUID from a 16-byte slice.
pub fn fromBytes(bytes: []const u8) Uuid {
    var uuid: Uuid = undefined;
    @memcpy(uuid.bytes[0..], bytes);
    return uuid;
}

test "fromBytes" {
    try std.testing.expectEqual([1]u8{0x0} ** 16, fromBytes(&[1]u8{0x0} ** 16).bytes);
}

/// Creates a UUID from an RFC-4122-formatted string.
pub fn fromString(str: []const u8) Error!Uuid {
    std.debug.assert(str.len == 36 and str[8] == '-' and str[13] == '-' and str[18] == '-' and str[23] == '-');

    var uuid: Uuid = undefined;
    var i: usize = 0;
    for (uuid.bytes[0..]) |*byte| {
        if (str[i] == '-') {
            i += 1;
        }
        const hi = try std.fmt.charToDigit(str[i], 16);
        const lo = try std.fmt.charToDigit(str[i + 1], 16);
        byte.* = hi << 4 | lo;
        i += 2;
    }

    return uuid;
}

test "fromString" {
    const uuid = try fromString("01234567-89ab-cdef-0123-456789abcdef");
    try std.testing.expectEqual(fromInt(0x0123456789ABCDEF0123456789ABCDEF), uuid);
}

/// Formats the UUID according to RFC-4122.
pub fn format(self: Uuid, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) (@TypeOf(writer).Error)!void {
    try std.fmt.format(writer, "{}-{}-{}-{}-{}", .{
        std.fmt.fmtSliceHexLower(self.bytes[0..4]),
        std.fmt.fmtSliceHexLower(self.bytes[4..6]),
        std.fmt.fmtSliceHexLower(self.bytes[6..8]),
        std.fmt.fmtSliceHexLower(self.bytes[8..10]),
        std.fmt.fmtSliceHexLower(self.bytes[10..16]),
    });
}

test "format" {
    const uuid = fromInt(0x0123456789ABCDEF0123456789ABCDEF);
    try std.testing.expectFmt("01234567-89ab-cdef-0123-456789abcdef", "{s}", .{uuid});
}

/// UUID variant or family.
pub const Variant = enum {
    /// Legacy Apollo Network Computing System UUIDs.
    ncs,
    /// RFC 4122/DCE 1.1 UUIDs, or "Leach–Salz" UUIDs.
    rfc4122,
    /// Backwards-compatible Microsoft COM/DCOM UUIDs.
    microsoft,
    /// Reserved for future definition UUIDs.
    future,
};

/// Returns the UUID variant.
pub fn getVariant(self: Uuid) Variant {
    const byte = self.bytes[8];
    if (byte >> 7 == 0b0) {
        return .ncs;
    } else if (byte >> 6 == 0b10) {
        return .rfc4122;
    } else if (byte >> 5 == 0b110) {
        return .microsoft;
    } else {
        return .future;
    }
}

/// Sets the UUID variant.
pub fn setVariant(uuid: *Uuid, variant: Variant) void {
    uuid.bytes[8] = switch (variant) {
        .ncs => uuid.bytes[8] & 0b01111111,
        .rfc4122 => 0b10000000 | (uuid.bytes[8] & 0b00111111),
        .microsoft => 0b11000000 | (uuid.bytes[8] & 0b00011111),
        .future => 0b11100000 | (uuid.bytes[8] & 0b0001111),
    };
}

/// UUID version or subtype.
pub const Version = enum {
    /// Version 0 is unused.
    unused,
    /// Version 1 is the Gregorian time-based UUID from RFC4122.
    time_based_gregorian,
    /// Version 2 is the DCE Security UUID with embedded POSIX UIDs from RFC4122.
    dce_security,
    /// Version 3 is the Name-based UUID using MD5 hashing from RFC4122.
    name_based_md5,
    /// Version 4 is the UUID generated using a pseudo-randomly generated number from RFC4122.
    random,
    /// Version 5 is the Name-based UUID using SHA-1 hashing from RFC4122.
    name_based_sha1,
    /// Version 6 is the Reordered Gregorian time-based UUID from IETF "New UUID Formats" Draft.
    time_based_gregorian_reordered,
    /// Version 7 is the Unix Epoch time-based UUID specified from IETF "New UUID Formats" Draft.
    time_based_unix,
    /// Version 8 is reserved for custom UUID formats from IETF "New UUID Formats" Draft.
    custom,
};

/// Returns the UUID version.
pub fn getVersion(self: Uuid) Error!Version {
    const version_int: u4 = @truncate(self.bytes[6] >> 4);
    return try std.meta.intToEnum(Version, version_int);
}

/// Sets the UUID version.
pub fn setVersion(uuid: *Uuid, version: Version) void {
    uuid.bytes[6] = @as(u8, @intFromEnum(version)) << 4 | (uuid.bytes[6] & 0xF);
}

test "getVariant/setVariant and getVersion/setVersion" {
    var uuid = try fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(Variant.rfc4122, uuid.getVariant());
    try std.testing.expectEqual(Version.time_based_gregorian, try uuid.getVersion());

    uuid = try fromString("3d813cbb-47fb-32ba-91df-831e1593ac29");
    try std.testing.expectEqual(Variant.rfc4122, uuid.getVariant());
    try std.testing.expectEqual(Version.name_based_md5, try uuid.getVersion());

    uuid = NIL;
    uuid.setVariant(.rfc4122);
    uuid.setVersion(.random);
    try std.testing.expectEqual(Variant.rfc4122, uuid.getVariant());
    try std.testing.expectEqual(Version.random, try uuid.getVersion());
}

/// UUIDv1 created from a Gregorian Epoch nanosecond timestamp and
/// pseudo-randomly generated MAC address.
pub const V1 = struct {
    /// Number of 100-nanosecond intervals from Gregorian Epoch (1582-10-15T00:00:00Z) to UNIX Epoch (1970-01-01T00:00:00Z).
    pub const NUM_INTERVALS_BEFORE_UNIX = 12_219_292_800 * (std.time.ns_per_s / 100);

    random: std.rand.Random,
    clock: *Clock,

    /// Thread-safe wrapping monotonic clock sequence ticking over 100-nanosecond intervals
    /// and being reinitialized with a pseudo-randomly generated number.
    pub const Clock = struct {
        mutex: std.Thread.Mutex = .{},
        random: std.rand.Random,
        timestamp: u60 = 0,
        sequence: u14 = 0,

        /// Initializes clock state.
        pub fn init(random: std.rand.Random) Clock {
            return .{ .random = random };
        }

        fn new(self: *Clock, timestamp: u60) u14 {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (timestamp > self.timestamp) {
                self.sequence = self.random.int(u14);
                self.timestamp = timestamp;
            }

            const sequence = self.sequence;
            self.sequence +%= 1;
            return sequence;
        }
    };

    /// Initializes UUIDv1 state.
    pub fn init(clock: *Clock, random: std.rand.Random) V1 {
        return .{ .clock = clock, .random = random };
    }

    /// Creates a new UUIDv1.
    pub fn new(self: V1) Uuid {
        const timestamp = nanoToUuidTimestamp(std.time.nanoTimestamp());
        var mac: [6]u8 = undefined;
        self.random.bytes(mac[0..]);
        mac[0] |= 1;

        var uuid: Uuid = undefined;

        const sequence = self.clock.new(timestamp);
        setTimestamp(&uuid, timestamp);
        std.mem.writeInt(u16, uuid.bytes[8..10], sequence, .big);
        @memcpy(uuid.bytes[10..], mac[0..]);

        uuid.setVariant(.rfc4122);
        uuid.setVersion(.time_based_gregorian);
        return uuid;
    }

    /// Converts a nanosecond timestamp to a UUIDv1 timestamp.
    pub fn nanoToUuidTimestamp(nanos: i128) u60 {
        const num_intervals_SINCE_UNIX = @divTrunc(nanos, 100);
        const num_intervals: u128 = @bitCast(num_intervals_SINCE_UNIX + NUM_INTERVALS_BEFORE_UNIX);
        return @truncate(num_intervals);
    }

    /// Returns the UUIDv1 timestamp.
    pub fn getTimestamp(uuid: Uuid) u60 {
        const lo = std.mem.readInt(u32, uuid.bytes[0..4], .big);
        const md = std.mem.readInt(u16, uuid.bytes[4..6], .big);
        const hi = std.mem.readInt(u16, uuid.bytes[6..8], .big) & 0xFFF;
        return @as(u60, hi) << 48 | @as(u60, md) << 32 | @as(u60, lo);
    }

    fn setTimestamp(uuid: *Uuid, timestamp: u60) void {
        const timestamp_u32: u32 = @truncate(timestamp);
        std.mem.writeInt(u32, uuid.bytes[0..4], timestamp_u32, .big);
        var timestamp_u16: u16 = @truncate(timestamp >> 32);
        std.mem.writeInt(u16, uuid.bytes[4..6], timestamp_u16, .big);
        timestamp_u16 = @truncate(timestamp >> 48);
        std.mem.writeInt(u16, uuid.bytes[6..8], timestamp_u16, .big);
    }

    test "V1" {
        var prng = std.rand.DefaultPrng.init(0);
        var clock = V1.Clock.init(prng.random());
        const v1 = V1.init(&clock, prng.random());
        const uuid1 = v1.new();
        const uuid2 = v1.new();
        try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
        try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[10..], uuid2.bytes[10..]));
    }

    /// Creates a UUIDv1 from UUIDv6.
    pub fn fromV6(uuid_v6: Uuid) Uuid {
        var uuid_v1 = uuid_v6;
        setTimestamp(&uuid_v1, V6.getTimestamp(uuid_v6));
        uuid_v1.setVersion(.time_based_gregorian);
        return uuid_v1;
    }

    test "fromV6" {
        var clock = V1.Clock.init(V6.RANDOM);
        const v6 = V6.init(&clock);
        const uuid_v6 = v6.new();
        const uuid_v1 = V1.fromV6(uuid_v6);
        try std.testing.expectEqual(uuid_v6.getVariant(), uuid_v1.getVariant());
        try std.testing.expectEqual(Version.time_based_gregorian, try uuid_v1.getVersion());
        try std.testing.expectEqualSlices(u8, uuid_v6.bytes[10..], uuid_v1.bytes[10..]);
    }
};

/// UUIDv2 created from a UUIDv1 and user's UID or GID on POSIX systems.
pub const V2 = struct {
    /// Domain represents the ID domain.
    const Domain = enum {
        person,
        group,
        org,
    };

    v1: V1,

    /// Initializes UUIDv3 state.
    pub fn init(clock: *V1.Clock, random: std.rand.Random) V2 {
        return .{ .v1 = V1.init(clock, random) };
    }

    /// Creates a new UUIDv3.
    pub fn new(self: V2, domain: Domain, id: u32) Uuid {
        var uuid = self.v1.new();
        uuid.setVariant(.rfc4122);
        uuid.setVersion(.dce_security);
        setDomain(&uuid, domain);
        setId(&uuid, id);
        return uuid;
    }

    /// Creates a new UUIDv3 for the person domain.
    pub fn nextForPerson(self: V2) Uuid {
        return self.new(Domain.person, std.os.linux.getuid());
    }

    /// Creates a new UUIDv3 for the group domain.
    pub fn nextForGroup(self: V2) Uuid {
        return self.new(Domain.group, std.os.linux.getgid());
    }

    // Returns the domain for a UUIDv2.
    pub fn getDomain(uuid: Uuid) Error!Domain {
        return try std.meta.intToEnum(Domain, uuid.bytes[6]);
    }

    // Sets the domain for a UUIDv2.
    pub fn setDomain(uuid: *Uuid, domain: Domain) void {
        uuid.bytes[6] = @intFromEnum(domain);
    }

    // Returns the id for a UUIDv2.
    pub fn getId(uuid: Uuid) u32 {
        return std.mem.readInt(u32, uuid.bytes[0..4], .big);
    }

    // Sets the id for a UUIDv2.
    pub fn setId(uuid: *Uuid, id: u32) void {
        std.mem.writeInt(u32, uuid.bytes[0..4], id, .big);
    }

    test "V2" {
        var prng = std.rand.DefaultPrng.init(0);
        var clock = V1.Clock.init(prng.random());
        const v2 = V2.init(&clock, prng.random());
        const uuid = v2.new(Domain.person, 12345678);
        try std.testing.expectEqual(Domain.person, try V2.getDomain(uuid));
        try std.testing.expectEqual(@as(u32, 12345678), V2.getId(uuid));
    }
};

/// UUIDv3 created from an MD5-hashed concatenated input name and namespace identifier.
pub const V3 = struct {
    /// DNS namespace identifier.
    pub const DNS = fromInt(0x6BA7B8109DAD11D180B400C04FD430C8);

    md5: std.crypto.hash.Md5,

    /// Initializes UUIDv3 state.
    pub fn init(uuid: Uuid) V3 {
        var md5 = std.crypto.hash.Md5.init(.{});
        md5.update(&uuid.bytes);
        return .{ .md5 = md5 };
    }

    /// Creates a new UUIDv3.
    pub fn new(self: V3, name: []const u8) Uuid {
        var uuid: Uuid = undefined;

        var md5 = self.md5;
        md5.update(name);
        md5.final(uuid.bytes[0..]);

        uuid.setVariant(.rfc4122);
        uuid.setVersion(.name_based_md5);
        return uuid;
    }

    test "V3" {
        const v3 = V3.init(V3.DNS);
        const uuid1 = v3.new("www.example.com");
        try std.testing.expectEqual(fromInt(0x5DF418813AED351588A72F4A814CF09E), uuid1);
        const uuid2 = v3.new("www.example.com");
        try std.testing.expectEqual(uuid1, uuid2);
    }
};

/// UUIDv4 created from a pseudo-randomly generated number.
pub const V4 = struct {
    random: std.rand.Random,

    /// Initializes UUIDv4 state.
    pub fn init(random: std.rand.Random) V4 {
        return .{ .random = random };
    }

    /// Creates a new UUIDv4.
    pub fn new(self: V4) Uuid {
        var uuid: Uuid = undefined;

        self.random.bytes(uuid.bytes[0..]);

        uuid.setVariant(.rfc4122);
        uuid.setVersion(.random);
        return uuid;
    }

    test "V4" {
        var prng = std.rand.DefaultPrng.init(0);
        var v4 = V4.init(prng.random());
        const uuid1 = v4.new();
        const uuid2 = v4.new();
        try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
    }
};

/// UUIDv5 created from a SHA-1-hashed concatenated input name and namespace identifier.
pub const V5 = struct {
    sha1: std.crypto.hash.Sha1,

    /// Initializes UUIDv5 state.
    pub fn init(uuid: Uuid) V5 {
        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(uuid.bytes[0..]);
        return .{ .sha1 = sha1 };
    }

    /// Creates a new UUIDv5.
    pub fn new(self: V5, name: []const u8) Uuid {
        var uuid: Uuid = undefined;

        var sha1 = self.sha1;
        sha1.update(name);
        var buf: [20]u8 = undefined;
        sha1.final(buf[0..]);
        @memcpy(uuid.bytes[0..], buf[0..16]);

        uuid.setVariant(.rfc4122);
        uuid.setVersion(.name_based_sha1);
        return uuid;
    }

    test "V5" {
        const v5 = V5.init(V3.DNS);
        const uuid1 = v5.new("www.example.com");
        try std.testing.expectEqual(fromInt(0x2ED6657DE927568B95E12665A8AEA6A2), uuid1);
        const uuid2 = v5.new("www.example.com");
        try std.testing.expectEqual(uuid1, uuid2);
    }
};

/// UUIDv6 created from a Gregorian Epoch nanosecond timestamp and
/// cryptographically-secure pseudo-randomly generated number.
pub const V6 = struct {
    /// Cryptographically-secure pseudo-random number generator.
    pub const RANDOM = std.crypto.random;

    clock: *V1.Clock,

    /// Initializes UUIDv6 state.
    pub fn init(clock: *V1.Clock) V6 {
        return .{ .clock = clock };
    }

    /// Creates a new UUIDv6.
    pub fn new(self: V6) Uuid {
        var uuid: Uuid = NIL;

        const timestamp = nanoToUuidTimestamp(std.time.nanoTimestamp());
        const sequence = self.clock.new(timestamp);
        setTimestamp(&uuid, timestamp);
        std.mem.writeInt(u16, uuid.bytes[8..10], sequence, .big);
        RANDOM.bytes(uuid.bytes[10..]);

        uuid.setVariant(.rfc4122);
        uuid.setVersion(.time_based_gregorian_reordered);
        return uuid;
    }

    /// Converts a nanosecond timestamp to a UUIDv6 timestamp.
    pub const nanoToUuidTimestamp = V1.nanoToUuidTimestamp;

    /// Returns the UUIDv6 timestamp.
    pub fn getTimestamp(uuid: Uuid) u60 {
        const hi = std.mem.readInt(u48, uuid.bytes[0..6], .big);
        const lo = std.mem.readInt(u16, uuid.bytes[6..8], .big) & 0xFFF;
        return @as(u60, hi) << 12 | @as(u60, lo);
    }

    fn setTimestamp(uuid: *Uuid, timestamp: u60) void {
        const timestamp_u48: u48 = @truncate(timestamp >> 12);
        std.mem.writeInt(u48, uuid.bytes[0..6], timestamp_u48, .big);
        const timestamp_u16: u16 = @truncate(timestamp & 0xFFF);
        std.mem.writeInt(u16, uuid.bytes[6..8], timestamp_u16, .big);
    }

    test "V6" {
        var clock = V1.Clock.init(V6.RANDOM);
        const v6 = V6.init(&clock);
        const uuid1 = v6.new();
        const uuid2 = v6.new();
        try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
    }

    /// Creates a UUIDv6 from a UUIDv1.
    pub fn fromV1(uuid_v1: Uuid) Uuid {
        var uuid_v6 = uuid_v1;
        setTimestamp(&uuid_v6, V1.getTimestamp(uuid_v1));
        uuid_v6.setVersion(.time_based_gregorian_reordered);
        return uuid_v6;
    }

    test "fromV1" {
        var prng = std.rand.DefaultPrng.init(0);
        var clock = V1.Clock.init(prng.random());
        const v1 = V1.init(&clock, prng.random());
        const uuid_v1 = v1.new();
        const uuid_v6 = fromV1(uuid_v1);
        try std.testing.expectEqual(uuid_v1.getVariant(), uuid_v6.getVariant());
        try std.testing.expectEqual(Version.time_based_gregorian_reordered, try uuid_v6.getVersion());
    }
};

/// UUIDv7 created from a UNIX Epoch millisecond timestamp and
/// cryptographically-secure pseudo-randomly generated number.
pub const V7 = struct {
    /// Cryptographically-secure pseudo-random number generator.
    pub const RANDOM = std.crypto.random;

    /// Creates a new UUIDv7.
    pub fn new() Uuid {
        var uuid: Uuid = NIL;

        const millis: u64 = @bitCast(std.time.milliTimestamp());
        const millis_u48: u48 = @truncate(millis);
        std.mem.writeInt(u48, uuid.bytes[0..6], millis_u48, .big);
        RANDOM.bytes(uuid.bytes[6..]);

        uuid.setVariant(.rfc4122);
        uuid.setVersion(.time_based_unix);
        return uuid;
    }

    test "V7" {
        const uuid1 = V7.new();
        const uuid2 = V7.new();
        try std.testing.expect(!std.mem.eql(u8, uuid1.bytes[0..], uuid2.bytes[0..]));
    }
};

test {
    std.testing.refAllDecls(Uuid);
}
