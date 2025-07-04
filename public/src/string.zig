const std = @import("std");

const cetech1 = @import("root.zig");

const Murmur2_32 = std.hash.murmur.Murmur2_32;
const Murmur2_64 = std.hash.murmur.Murmur2_64;

pub const StrId32List = cetech1.ArrayList(cetech1.StrId32);
pub const StrId64List = cetech1.ArrayList(cetech1.StrId64);

pub const StrId32 = extern struct {
    id: u32 = 0,

    pub fn isEmpty(a: StrId32) bool {
        return a.id == 0;
    }

    pub fn eql(a: StrId32, b: StrId32) bool {
        return a.id == b.id;
    }

    pub fn fromStr(str: []const u8) StrId32 {
        return strId32(str);
    }
};

pub const StrId64 = extern struct {
    id: u64 = 0,

    pub fn isEmpty(a: StrId64) bool {
        return a.id == 0;
    }

    pub fn eql(a: StrId64, b: StrId64) bool {
        return a.id == b.id;
    }

    pub inline fn to(self: *const StrId64, comptime T: type) T {
        return .{ .id = self.id };
    }

    pub inline fn from(comptime T: type, obj: T) StrId64 {
        return .{ .id = obj.id };
    }

    pub fn fromStr(str: []const u8) StrId64 {
        return strId64(str);
    }
};

/// Create StrId32 from string/data
pub inline fn strId32(str: []const u8) StrId32 {
    return .{
        .id = Murmur2_32.hash(str),
    };
}

/// Create StrId64 from string/data
pub inline fn strId64(str: []const u8) StrId64 {
    return .{
        .id = Murmur2_64.hash(str),
    };
}

// TODO: unshit
pub fn InternWithLock(comptime T: type) type {
    return struct {
        const Self = @This();
        const Storage = std.AutoHashMap(InternId, T);
        const has_sentinel = std.meta.sentinel(T) != null;

        pub const InternId = StrId64;

        allocator: std.mem.Allocator,
        storage: Storage,
        lck: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .storage = Storage.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.storage.valueIterator();
            while (it.next()) |v| {
                self.allocator.free(v.*);
            }
            self.storage.deinit();
        }

        pub fn intern(self: *Self, string: T) !T {
            self.lck.lock();
            defer self.lck.unlock();
            const hash = strId64(string);

            const intern_str_result = try self.storage.getOrPut(hash);
            if (intern_str_result.found_existing) return intern_str_result.value_ptr.*;

            intern_str_result.value_ptr.* = try if (has_sentinel) self.allocator.dupeZ(u8, string) else self.allocator.dupe(u8, string);

            return intern_str_result.value_ptr.*;
        }

        pub fn internToHash(self: *Self, string: T) !InternId {
            const hash = strId64(string);

            self.lck.lock();
            defer self.lck.unlock();
            const intern_str_result = try self.storage.getOrPut(hash);
            if (intern_str_result.found_existing) return hash;

            intern_str_result.value_ptr.* = try if (has_sentinel) self.allocator.dupeZ(u8, string) else self.allocator.dupe(u8, string);

            return hash;
        }

        pub fn findById(self: *Self, id: InternId) ?[:0]const u8 {
            self.lck.lock();
            defer self.lck.unlock();
            return self.storage.get(id);
        }
    };
}
