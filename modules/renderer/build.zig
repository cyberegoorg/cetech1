const std = @import("std");
const builtin = @import("builtin");

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cetech1 = b.dependency("cetech1", .{});
    const cetech1_module = cetech1.module("cetech1");

    const lib = b.addSharedLibrary(.{
        .name = "ct_renderer",
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
        l.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
        l.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));
        l.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
        l.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));

        b.installArtifact(l);
    }

    _ = b.addModule(
        "renderer",
        .{
            .root_source_file = b.path("src/renderer.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "transform", .module = b.dependency("transform", .{}).module("transform") },
                .{ .name = "camera", .module = b.dependency("camera", .{}).module("camera") },
                .{ .name = "shader_system", .module = b.dependency("shader_system", .{}).module("shader_system") },
            },
        },
    );
}
