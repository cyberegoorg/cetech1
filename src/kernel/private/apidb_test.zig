const std = @import("std");
const mem = std.mem;

const cetech1 = @import("cetech1");
const apidb = cetech1.apidb;
const apidb_private = @import("apidb.zig");

test "Can create global var" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const v1 = try apidb.setGlobalVar(u32, .TestModule, "v1", 1);

    const v1_1 = try apidb.setGlobalVar(u32, .TestModule, "v1", 10);

    try std.testing.expect(v1 == v1_1);
    try std.testing.expect(v1.* == v1_1.*);

    v1_1.* = 10;

    try std.testing.expect(10 == v1.*);
}

test "Can registr and use zig API" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const FooAPI = struct {
        pub fn bar(self: @This()) f32 {
            _ = self;
            return 3.14;
        }
    };

    var foo_api = FooAPI{};
    try apidb.setZigApi(.foo, FooAPI, &foo_api);

    var foo_api2 = apidb.getZigApi(.foo, FooAPI);
    try std.testing.expect(foo_api2 != null);

    const expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_api2.?.bar());
}

test "Unregistred api return zeroed interface" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const FooAPI = struct {
        bar: ?*const fn () f32,

        pub fn barImpl() f32 {
            return 3.14;
        }
    };

    const foo_api2 = apidb.getApi(.foo, FooAPI, cetech1.apidb.lang_zig, "foo");
    try std.testing.expect(foo_api2 != null);
    try std.testing.expect(foo_api2.?.bar == null);
}

test "Can remove api" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const FooAPI = struct {
        bar: ?*const fn () f32,

        pub fn barImpl() f32 {
            return 3.14;
        }
    };

    var foo_api = FooAPI{ .bar = &FooAPI.barImpl };
    try apidb.setZigApi(.foo, FooAPI, &foo_api);

    apidb.removeZigApi(.foo, FooAPI);

    const foo_api2 = apidb.getZigApi(.foo, FooAPI);
    try std.testing.expect(foo_api2 != null);
    try std.testing.expect(foo_api2.?.bar == null);
}

test "Can implement and use interface" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const FooInterface = struct {
        pub const c_name = "ct_foo_i";
        pub const name_hash = cetech1.strId64(@This().c_name);

        bar: *const fn () f32,
    };

    const FooInteraceImpl = struct {
        fn barImpl() f32 {
            return 3.14;
        }
    };

    var foo_impl = FooInterface{ .bar = &FooInteraceImpl.barImpl };

    try apidb.implInterface(.testing, FooInterface, &foo_impl);

    const impls = apidb.getImpl(std.testing.allocator, FooInterface) catch undefined;
    defer std.testing.allocator.free(impls);

    var foo_i_ptr: *const FooInterface = impls[0];

    try std.testing.expectEqual(@intFromPtr(&foo_impl), @intFromPtr(foo_i_ptr));

    const expect_value: f32 = 3.14;
    try std.testing.expectEqual(expect_value, foo_i_ptr.bar());
}

test "Interface should have multiple implementation" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const ct_foo_i = struct {
        pub const c_name = "ct_foo_i";
        pub const name_hash = cetech1.strId64(@This().c_name);

        bar: *const fn () i32,
    };

    const FooInteraceImpl = struct {
        fn barImpl() i32 {
            return 1;
        }
    };

    const FooInteraceImplOther = struct {
        fn barImpl() i32 {
            return 2;
        }
    };

    var foo_impl = ct_foo_i{ .bar = &FooInteraceImpl.barImpl };
    var foo_impl2 = ct_foo_i{ .bar = &FooInteraceImplOther.barImpl };

    try apidb.implInterface(.foo, ct_foo_i, &foo_impl);
    try apidb.implInterface(.foo, ct_foo_i, &foo_impl2);

    var acc: i32 = 0.0;
    const impls = apidb.getImpl(std.testing.allocator, ct_foo_i) catch undefined;
    defer std.testing.allocator.free(impls);
    for (impls) |iface| {
        acc += iface.bar();
    }

    const expect_value: i32 = 3;
    try std.testing.expectEqual(expect_value, acc);
}

test "Interface implementation can be removed" {
    try apidb_private.init(std.testing.allocator);
    defer apidb_private.deinit();

    const ct_foo_i = struct {
        pub const c_name = "ct_foo_i";
        pub const name_hash = cetech1.strId64(@This().c_name);
        bar: *const fn () i32,
    };

    const FooInteraceImpl = struct {
        fn barImpl() i32 {
            return 1;
        }
    };

    const FooInteraceImplOther = struct {
        fn barImpl() i32 {
            return 2;
        }
    };

    var foo_impl1 = ct_foo_i{ .bar = &FooInteraceImpl.barImpl };
    var foo_impl2 = ct_foo_i{ .bar = &FooInteraceImplOther.barImpl };

    try apidb.implInterface(.foo, ct_foo_i, &foo_impl1);
    try apidb.implInterface(.foo, ct_foo_i, &foo_impl2);

    apidb.removeImpl(.foo, ct_foo_i, &foo_impl2);
    {
        var acc: i32 = 0;
        const impls = apidb.getImpl(std.testing.allocator, ct_foo_i) catch undefined;
        defer std.testing.allocator.free(impls);
        for (impls) |iface| {
            acc += iface.bar();
        }

        const expect_value: i32 = 1;
        try std.testing.expectEqual(expect_value, acc);
    }

    apidb.removeImpl(.foo, ct_foo_i, &foo_impl1);
    {
        var acc: i32 = 0;
        const impls = apidb.getImpl(std.testing.allocator, ct_foo_i) catch undefined;
        defer std.testing.allocator.free(impls);
        for (impls) |iface| {
            acc += iface.bar();
        }

        const expect_value: i32 = 0;
        try std.testing.expectEqual(expect_value, acc);
    }
}
