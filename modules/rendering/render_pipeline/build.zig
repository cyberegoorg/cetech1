const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "render_pipeline",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));

    _ = b.addModule(
        "render_pipeline",
        .{
            .root_source_file = b.path("src/render_pipeline.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "render_graph", .module = b.dependency("render_graph", .{}).module("render_graph") },
                .{ .name = "shader_system", .module = b.dependency("shader_system", .{}).module("shader_system") },
            },
        },
    );
}
