const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const ApiHashMap = StringHashMap(*anyopaque);
const ApiHashMapPool = std.heap.MemoryPool(ApiHashMap);
const LanguagesApiHashMap = StringHashMap(*ApiHashMap);

var c = @cImport(@cInclude("cetech1/core/api_system.h"));

/// Main api register
pub const ApiRegistryAPI = struct {
    const Self = @This();
    pub const api_lang_zig = "zig";
    pub const api_lang_c = "c";

    allocator: Allocator,
    language_api_map: LanguagesApiHashMap,
    api_map_pool: ApiHashMapPool,

    pub fn init(allocator: Allocator) Self {
        return Self{ .language_api_map = LanguagesApiHashMap.init(allocator), .allocator = allocator, .api_map_pool = ApiHashMapPool.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.language_api_map.valueIterator();
        while (iter.next()) |entry| {
            entry.*.deinit();
        }
        self.api_map_pool.deinit();
        self.language_api_map.deinit();
    }

    pub fn addApiForLanguage(self: *Self, language: []const u8, api_name: []const u8, api_ptr: *anyopaque) !void {
        if (!self.language_api_map.contains(language)) {
            var api_map = try self.api_map_pool.create();
            api_map.* = ApiHashMap.init(self.allocator);
            try self.language_api_map.put(language, api_map);
        }

        var api_map = self.language_api_map.get(language);
        try api_map.?.put(api_name, api_ptr);
    }

    pub fn addApi(self: *Self, api_name: []const u8, api_ptr: *anyopaque) !void {
        return self.addApiForLanguage(api_lang_zig, api_name, api_ptr);
    }

    pub fn addCApi(self: *Self, api_name: []const u8, api_ptr: *anyopaque) !void {
        return self.addApiForLanguage(api_lang_c, api_name, api_ptr);
    }

    pub fn getApiForLanguage(self: *Self, comptime T: type, language: []const u8, api_name: []const u8) ?*T {
        var api_map = self.language_api_map.get(language);

        if (api_map == null) {
            return null;
        }

        var api_ptr = api_map.?.get(api_name);
        var ptr: *T = @ptrFromInt(@intFromPtr(api_ptr));
        //return @alignCast(ptr);
        return ptr;
    }

    pub fn getApi(self: *Self, comptime T: type, api_name: []const u8) ?*T {
        return self.getApiForLanguage(T, api_lang_zig, api_name);
    }

    pub fn getCApi(self: *Self, comptime T: type, api_name: []const u8) ?*T {
        return self.getApiForLanguage(T, api_lang_c, api_name);
    }
};

test "Can registr and use zig API" {
    const allocator = std.testing.allocator;
    var api = ApiRegistryAPI.init(allocator);
    defer api.deinit();

    const FooAPI = struct {
        pub fn bar(self: *@This()) f32 {
            _ = self;
            return 3.14;
        }
    };

    var foo_api = FooAPI{};
    try api.addApi("foo", &foo_api);

    var foo_api2 = api.getApi(FooAPI, "foo");
    try std.testing.expect(foo_api2 != null);

    var expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_api2.?.bar());
}

test "Can registr and use C API" {
    const allocator = std.testing.allocator;
    var api = ApiRegistryAPI.init(allocator);
    defer api.deinit();

    const FooAPI = struct {
        bar: *const fn () f32,

        pub fn barImpl() f32 {
            return 3.14;
        }
    };

    var foo_api = FooAPI{ .bar = &FooAPI.barImpl };
    try api.addCApi("foo", &foo_api);

    var foo_api2 = api.getCApi(FooAPI, "foo");
    try std.testing.expect(foo_api2 != null);

    var expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_api2.?.bar());
}
