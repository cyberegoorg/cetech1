const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "editor_asset",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));
    lib.root_module.addImport("editor_inspector", b.dependency("editor_inspector", .{}).module("editor_inspector"));
    lib.root_module.addImport("editor_tree", b.dependency("editor_tree", .{}).module("editor_tree"));
    lib.root_module.addImport("editor_obj_buffer", b.dependency("editor_obj_buffer", .{}).module("editor_obj_buffer"));
}
