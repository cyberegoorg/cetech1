const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const editor = b.dependency("editor", .{});

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "editor_simulation",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", editor.module("editor"));
    lib.root_module.addImport("renderer", b.dependency("renderer", .{}).module("renderer"));
    lib.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("editor_entity", b.dependency("editor_entity", .{}).module("editor_entity"));
}
