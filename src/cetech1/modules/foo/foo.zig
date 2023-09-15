const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech = @import("../../cetech1.zig");
const c = @cImport({
    @cInclude("cetech1/modules/foo.h");
});

pub var api = FooAPI{};
pub const FooAPI = struct {
    const Self = @This();

    fff: f32 = 11,

    pub fn foo1(self: *Self, arg1: f32) f32 {
        return arg1 + self.fff;
    }

    pub fn foo1_c(arg1: f32) callconv(.C) f32 {
        return api.foo1(arg1);
    }
};

pub var c_api = c.ct_foo_api_t{ .foo = &FooAPI.foo1_c };

pub fn load_module(api_reg: *cetech.api_registry.ApiRegistryAPI, allocator: Allocator, load: bool, reload: bool) !void {
    _ = allocator;
    try api_reg.addApi("foo", &api);
    try api_reg.addCApi("foo", &c_api);

    if (load) {
        std.debug.print("LOAD\n", .{});
        return;
    }

    if (!load) {
        std.debug.print("UNLOAD\n", .{});
        return;
    }

    if (reload) {
        std.debug.print("RELOAD\n", .{});
        return;
    }
}
