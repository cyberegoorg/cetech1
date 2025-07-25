const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "renderer_nodes",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));
    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));
    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
    lib.root_module.addImport("render_viewport", b.dependency("render_viewport", .{}).module("render_viewport"));

    _ = b.addModule(
        "renderer_nodes",
        .{
            .root_source_file = b.path("src/renderer_nodes.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "shader_system", .module = b.dependency("shader_system", .{}).module("shader_system") },
                .{ .name = "render_graph", .module = b.dependency("render_graph", .{}).module("render_graph") },
                .{ .name = "render_viewport", .module = b.dependency("render_viewport", .{}).module("render_viewport") },
            },
        },
    );
}
