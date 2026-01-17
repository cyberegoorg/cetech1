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

    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
    lib.root_module.addImport("render_pipeline", b.dependency("render_pipeline", .{}).module("render_pipeline"));
    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));
    lib.root_module.addImport("light_system", b.dependency("light_system", .{}).module("light_system"));
    lib.root_module.addImport("bloom", b.dependency("bloom", .{}).module("bloom"));
    lib.root_module.addImport("tonemap", b.dependency("tonemap", .{}).module("tonemap"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
}
