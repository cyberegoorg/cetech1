const std = @import("std");
const builtin = @import("builtin");

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cetech1 = b.dependency("cetech1", .{});
    const cetech1_module = cetech1.module("cetech1");

    const editor = b.dependency("editor", .{});
    const asset_preview = b.dependency("editor_asset_preview", .{});
    const editor_tree = b.dependency("editor_tree", .{});

    const lib = b.addSharedLibrary(.{
        .name = "ct_editor_entity_asset",
        .version = version,
        .root_source_file = b.path("src/private.zig"),
        .target = target,
        .optimize = optimize,
    });

    const slib = b.addStaticLibrary(.{
        .name = "static",
        .version = version,
        .root_source_file = b.path("src/private.zig"),
        .target = target,
        .optimize = optimize,
    });

    inline for (.{ lib, slib }) |l| {
        l.root_module.addImport("cetech1", cetech1_module);
        l.root_module.addImport("editor", editor.module("editor"));
        l.root_module.addImport("asset_preview", asset_preview.module("asset_preview"));
        l.root_module.addImport("editor_tree", editor_tree.module("editor_tree"));
        l.addIncludePath(cetech1.path("includes"));
        b.installArtifact(l);
    }
}
