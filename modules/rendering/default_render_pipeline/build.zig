const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "default_render_pipeline",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("renderer", b.dependency("renderer", .{}).module("renderer"));
    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
}
