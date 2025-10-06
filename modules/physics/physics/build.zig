const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "physics",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("cetech1", cetech1_module);
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));

    _ = b.addModule(
        "physics",
        .{
            .root_source_file = b.path("src/physics.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
            },
        },
    );
}
