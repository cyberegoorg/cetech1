const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const editor = b.dependency("editor", .{});
    const asset_preview = b.dependency("editor_asset_preview", .{});
    const editor_tree = b.dependency("editor_tree", .{});
    const editor_inspector = b.dependency("editor_inspector", .{});
    const editor_tabs = b.dependency("editor_tabs", .{});
    const editor_assetdb = b.dependency("editor_assetdb", .{});

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "editor_entity_asset",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", editor.module("editor"));
    lib.root_module.addImport("asset_preview", asset_preview.module("asset_preview"));
    lib.root_module.addImport("editor_tree", editor_tree.module("editor_tree"));
    lib.root_module.addImport("editor_inspector", editor_inspector.module("editor_inspector"));
    lib.root_module.addImport("editor_tabs", editor_tabs.module("editor_tabs"));
    lib.root_module.addImport("editor_assetdb", editor_assetdb.module("editor_assetdb"));
}
