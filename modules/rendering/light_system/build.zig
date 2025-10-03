const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "light_system",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("render_viewport", b.dependency("render_viewport", .{}).module("render_viewport"));
    lib.root_module.addImport("light_component", b.dependency("light_component", .{}).module("light_component"));
    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
    lib.root_module.addImport("visibility_flags", b.dependency("visibility_flags", .{}).module("visibility_flags"));
    lib.root_module.addImport("render_pipeline", b.dependency("render_pipeline", .{}).module("render_pipeline"));

    _ = b.addModule(
        "light_system",
        .{
            .root_source_file = b.path("src/light_system.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "shader_system", .module = b.dependency("shader_system", .{}).module("shader_system") },
                .{ .name = "transform", .module = b.dependency("transform", .{}).module("transform") },
                .{ .name = "render_viewport", .module = b.dependency("render_viewport", .{}).module("render_viewport") },
                .{ .name = "light_component", .module = b.dependency("light_component", .{}).module("light_component") },
            },
        },
    );
}
