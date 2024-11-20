const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_inspector",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));

    _ = b.addModule("editor_inspector", .{
        .root_source_file = b.path("src/editor_inspector.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = b.dependency("editor", .{}).module("editor") },
        },
    });
}
