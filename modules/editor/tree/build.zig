const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_tree",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));
    lib.root_module.addImport("editor_inspector", b.dependency("editor_inspector", .{}).module("editor_inspector"));
    lib.root_module.addImport("editor_tabs", b.dependency("editor_tabs", .{}).module("editor_tabs"));

    _ = b.addModule("editor_tree", .{
        .root_source_file = b.path("src/editor_tree.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = b.dependency("editor", .{}).module("editor") },
            .{ .name = "editor_tabs", .module = b.dependency("editor_tabs", .{}).module("editor_tabs") },
        },
    });
}
