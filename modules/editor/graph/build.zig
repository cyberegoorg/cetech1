const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const editor = b.dependency("editor", .{});
    const editor_inspector = b.dependency("editor_inspector", .{});

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "editor_graph",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", editor.module("editor"));
    lib.root_module.addImport("editor_inspector", editor_inspector.module("editor_inspector"));
    lib.root_module.addImport("editor_obj_buffer", b.dependency("editor_obj_buffer", .{}).module("editor_obj_buffer"));
    lib.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));
}
