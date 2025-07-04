const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "render_graph",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));
    lib.root_module.addImport("visibility_flags", b.dependency("visibility_flags", .{}).module("visibility_flags"));

    _ = b.addModule(
        "render_graph",
        .{
            .root_source_file = b.path("src/render_graph.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "camera", .module = b.dependency("camera", .{}).module("camera") },
                .{ .name = "shader_system", .module = b.dependency("shader_system", .{}).module("shader_system") },
                .{ .name = "visibility_flags", .module = b.dependency("visibility_flags", .{}).module("visibility_flags") },
            },
        },
    );
}
