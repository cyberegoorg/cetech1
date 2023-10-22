const std = @import("std");
const mem = std.mem;

const cetech1 = @import("../cetech1.zig");

const apidb = @import("apidb.zig");

test "Can create global var" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    var v1 = try apidb.api.globalVar(u32, "TestModule", "v1", 1);

    var v1_1 = try apidb.api.globalVar(u32, "TestModule", "v1", 10);

    try std.testing.expect(v1 == v1_1);
    try std.testing.expect(v1.* == v1_1.*);

    v1_1.* = 10;

    try std.testing.expect(10 == v1.*);
}

test "Can registr and use zig API" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const FooAPI = struct {
        pub fn bar(self: *@This()) f32 {
            _ = self;
            return 3.14;
        }
    };

    var foo_api = FooAPI{};
    try apidb.api.setZigApi(FooAPI, &foo_api);

    var foo_api2 = apidb.api.getZigApi(FooAPI);
    try std.testing.expect(foo_api2 != null);

    var expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_api2.?.bar());
}

test "Can registr and use C API" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const FooAPI = struct {
        bar: *const fn () callconv(.C) f32,

        pub fn barImpl() callconv(.C) f32 {
            return 3.14;
        }
    };

    var foo_api = FooAPI{ .bar = &FooAPI.barImpl };
    try apidb.api.setApi(FooAPI, cetech1.apidb.ApiDbAPI.lang_c, "foo", &foo_api);

    var foo_api2 = apidb.api.getApi(FooAPI, cetech1.apidb.ApiDbAPI.lang_c, "foo");
    try std.testing.expect(foo_api2 != null);

    var expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_api2.?.bar());
}

test "Unregistred api return zeroed interface" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const FooAPI = struct {
        bar: ?*const fn () callconv(.C) f32,

        pub fn barImpl() callconv(.C) f32 {
            return 3.14;
        }
    };

    var foo_api2 = apidb.api.getApi(FooAPI, cetech1.apidb.ApiDbAPI.lang_c, "foo");
    try std.testing.expect(foo_api2 != null);
    try std.testing.expect(foo_api2.?.bar == null);
}

test "Can remove api" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const FooAPI = struct {
        bar: ?*const fn () callconv(.C) f32,

        pub fn barImpl() callconv(.C) f32 {
            return 3.14;
        }
    };

    var foo_api = FooAPI{ .bar = &FooAPI.barImpl };
    try apidb.api.setZigApi(FooAPI, &foo_api);

    apidb.api.removeZigApi(FooAPI);

    var foo_api2 = apidb.api.getZigApi(FooAPI);
    try std.testing.expect(foo_api2 != null);
    try std.testing.expect(foo_api2.?.bar == null);
}

test "Can implement and use interface" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const FooInterace = struct {
        bar: *const fn () callconv(.C) f32,
    };

    const FooInteraceImpl = struct {
        fn barImpl() callconv(.C) f32 {
            return 3.14;
        }
    };

    var foo_impl = FooInterace{ .bar = &FooInteraceImpl.barImpl };

    try apidb.api.implInterfaceFn("foo_i", &foo_impl);
    var foo_i_ptr: *FooInterace = @alignCast(@ptrCast(apidb.api.getFirstImplFn("foo_i").?.interface));

    try std.testing.expectEqual(@intFromPtr(&foo_impl), @intFromPtr(foo_i_ptr));

    var expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_i_ptr.bar());
}

test "Interface should have multiple implementation" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const ct_foo_i = struct {
        bar: *const fn () callconv(.C) i32,
    };

    const FooInteraceImpl = struct {
        fn barImpl() callconv(.C) i32 {
            return 1;
        }
    };

    const FooInteraceImplOther = struct {
        fn barImpl() callconv(.C) i32 {
            return 2;
        }
    };

    var foo_impl = ct_foo_i{ .bar = &FooInteraceImpl.barImpl };
    var foo_impl2 = ct_foo_i{ .bar = &FooInteraceImplOther.barImpl };

    try apidb.api.implInterface(ct_foo_i, &foo_impl);
    try apidb.api.implInterface(ct_foo_i, &foo_impl2);

    var acc: i32 = 0.0;
    var it = apidb.api.getFirstImpl(ct_foo_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(ct_foo_i, node);
        acc += iface.bar();
    }

    var expect_value: i32 = 3;
    try std.testing.expectEqual(expect_value, acc);
}

test "Interface implementation can be removed" {
    try apidb.init(std.testing.allocator);
    defer apidb.deinit();

    const ct_foo_i = struct {
        bar: *const fn () callconv(.C) i32,
    };

    const FooInteraceImpl = struct {
        fn barImpl() callconv(.C) i32 {
            return 1;
        }
    };

    const FooInteraceImplOther = struct {
        fn barImpl() callconv(.C) i32 {
            return 2;
        }
    };

    var foo_impl1 = ct_foo_i{ .bar = &FooInteraceImpl.barImpl };
    var foo_impl2 = ct_foo_i{ .bar = &FooInteraceImplOther.barImpl };

    try apidb.api.implInterface(ct_foo_i, &foo_impl1);
    try apidb.api.implInterface(ct_foo_i, &foo_impl2);

    apidb.api.removeImpl(ct_foo_i, &foo_impl2);
    {
        var acc: i32 = 0;
        var it = apidb.api.getFirstImpl(ct_foo_i);
        while (it) |node| : (it = node.next) {
            var iface = cetech1.apidb.ApiDbAPI.toInterface(ct_foo_i, node);
            acc += iface.bar();
        }

        var expect_value: i32 = 1;
        try std.testing.expectEqual(expect_value, acc);
    }

    apidb.api.removeImpl(ct_foo_i, &foo_impl1);
    {
        var acc: i32 = 0;
        var it = apidb.api.getFirstImpl(ct_foo_i);
        while (it) |node| : (it = node.next) {
            var iface = cetech1.apidb.ApiDbAPI.toInterface(ct_foo_i, node);
            acc += iface.bar();
        }

        var expect_value: i32 = 0;
        try std.testing.expectEqual(expect_value, acc);
    }
}
