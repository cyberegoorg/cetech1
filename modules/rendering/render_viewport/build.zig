const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "render_viewport",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));
    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
    lib.root_module.addImport("render_pipeline", b.dependency("render_pipeline", .{}).module("render_pipeline"));
    lib.root_module.addImport("vertex_system", b.dependency("vertex_system", .{}).module("vertex_system"));
    lib.root_module.addImport("visibility_flags", b.dependency("visibility_flags", .{}).module("visibility_flags"));

    _ = b.addModule(
        "render_viewport",
        .{
            .root_source_file = b.path("src/render_viewport.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "transform", .module = b.dependency("transform", .{}).module("transform") },
                .{ .name = "camera", .module = b.dependency("camera", .{}).module("camera") },
                .{ .name = "shader_system", .module = b.dependency("shader_system", .{}).module("shader_system") },
                .{ .name = "render_graph", .module = b.dependency("render_graph", .{}).module("render_graph") },
                .{ .name = "render_pipeline", .module = b.dependency("render_pipeline", .{}).module("render_pipeline") },
                .{ .name = "vertex_system", .module = b.dependency("vertex_system", .{}).module("vertex_system") },
                .{ .name = "visibility_flags", .module = b.dependency("visibility_flags", .{}).module("visibility_flags") },
            },
        },
    );
}
