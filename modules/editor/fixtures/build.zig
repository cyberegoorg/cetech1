const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_fixtures",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));
    lib.root_module.addImport("editor_asset_browser", b.dependency("editor_asset_browser", .{}).module("editor_asset_browser"));

    _ = b.addModule("editor_fixtures", .{
        .root_source_file = b.path("src/editor_fixtures.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
}
