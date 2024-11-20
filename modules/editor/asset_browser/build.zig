const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_asset_browser",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));
    lib.root_module.addImport("editor_tree", b.dependency("editor_tree", .{}).module("editor_tree"));
    lib.root_module.addImport("editor_tags", b.dependency("editor_tags", .{}).module("editor_tags"));
    lib.root_module.addImport("editor_asset", b.dependency("editor_asset", .{}).module("editor_asset"));

    _ = b.addModule("editor_asset_browser", .{
        .root_source_file = b.path("src/editor_asset_browser.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
}
