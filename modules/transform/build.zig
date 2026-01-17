const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "transform",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));

    _ = b.addModule(
        "transform",
        .{
            .root_source_file = b.path("src/transform.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
            },
        },
    );
}
