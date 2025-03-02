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
        .name = "ct_editor_entity",
        .version = version,
        .root_source_file = b.path("src/private.zig"),
        .target = target,
        .optimize = optimize,
    });

    const slib = b.addStaticLibrary(.{
        .name = "ct_editor_entity_static",
        .version = version,
        .root_source_file = b.path("src/private.zig"),
        .target = target,
        .optimize = optimize,
    });

    inline for (.{ lib, slib }) |l| {
        l.root_module.addImport("cetech1", cetech1_module);
        l.root_module.addImport("editor", editor.module("editor"));
        l.root_module.addImport("renderer", b.dependency("renderer", .{}).module("renderer"));
        l.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
        l.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
        l.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));

        b.installArtifact(l);
    }
}
