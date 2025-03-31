const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_renderer",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));
    lib.root_module.addImport("editor_inspector", b.dependency("editor_inspector", .{}).module("editor_inspector"));
    lib.root_module.addImport("renderer", b.dependency("renderer", .{}).module("renderer"));

    _ = b.addModule("editor_fixtures", .{
        .root_source_file = b.path("src/editor_renderer.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
}
