const std = @import("std");
const builtin = @import("builtin");

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cetech1 = b.dependency("cetech1", .{});
    const cetech1_module = cetech1.module("cetech1");

    const editor = b.dependency("editor", .{});

    const lib = b.addSharedLibrary(.{
        .name = "ct_editor_asset_preview",
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

    _ = b.addModule("asset_preview", .{
        .root_source_file = b.path("src/asset_preview.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });

    inline for (.{ lib, slib }) |l| {
        l.root_module.addImport("cetech1", cetech1_module);
        l.root_module.addImport("editor", editor.module("editor"));

        b.installArtifact(l);
    }
}
