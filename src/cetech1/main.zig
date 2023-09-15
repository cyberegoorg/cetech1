const std = @import("std");

const cetech = @import("cetech1.zig");
const foo = @import("modules/foo/foo.zig");

pub fn main() anyerror!void {
    var kernel = try cetech.Kernel.init();
    try kernel.powerOn(&[_]cetech.ModulesAPI.ModulePair{.{ .name = "foo", .module_fce = foo.load_module }});
    defer kernel.powerOff() catch undefined;

    var aa = kernel.api_reg_api.getApi(foo.FooAPI, "foo").?;
    std.debug.print("FOOO1: {}\n", .{aa.foo1(0)});
}
