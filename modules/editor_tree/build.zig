const std = @import("std");
const builtin = @import("builtin");

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cetech1 = b.dependency("cetech1", .{});
    const cetech1_module = cetech1.module("cetech1");

    const lib = b.addSharedLibrary(.{
        .name = "ct_editor_tree",
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
        l.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));
        l.root_module.addImport("editor_inspector", b.dependency("editor_inspector", .{}).module("editor_inspector"));

        l.addIncludePath(b.path("includes"));
        b.installArtifact(l);
    }

    _ = b.addModule("editor_tree", .{
        .root_source_file = b.path("src/editor_tree.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = b.dependency("editor", .{}).module("editor") },
        },
    });
}
