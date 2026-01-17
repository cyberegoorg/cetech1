const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "physics_jolt",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    const zphysics = b.dependency("zphysics", .{
        .use_double_precision = false,
        .enable_debug_renderer = true,
        .enable_cross_platform_determinism = true,
    });
    lib.linkLibrary(zphysics.artifact("joltc"));

    lib.root_module.addImport("cetech1", cetech1_module);
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("physics", b.dependency("physics", .{}).module("physics"));
    lib.root_module.addImport("zphysics", zphysics.module("root"));
}
