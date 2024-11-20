const std = @import("std");
const builtin = @import("builtin");

const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const editor = b.dependency("editor", .{});

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "editor_foo_tab",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );
    lib.root_module.addImport("editor", editor.module("editor"));
}
