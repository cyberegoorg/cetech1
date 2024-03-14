const std = @import("std");
const builtin = @import("builtin");

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cetech1 = b.dependency("cetech1", .{});
    const cetech1_module = cetech1.module("cetech1");

    const lib = b.addSharedLibrary(.{
        .name = "ct_bar",
        .version = version,
        .target = target,
        .optimize = optimize,
    });

    const slib = b.addSharedLibrary(.{
        .name = "static",
        .version = version,
        .target = target,
        .optimize = optimize,
    });

    inline for (.{ lib, slib }) |l| {
        l.addCSourceFile(.{ .file = .{ .path = "module_bar.c" }, .flags = &.{} });
        l.addIncludePath(cetech1.path("includes"));
        l.root_module.addImport("cetech1", cetech1_module);
        b.installArtifact(l);
    }
}
