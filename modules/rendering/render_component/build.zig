const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "render_component",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));
    lib.root_module.addImport("renderer", b.dependency("renderer", .{}).module("renderer"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("shader_system", b.dependency("shader_system", .{}).module("shader_system"));

    _ = b.addModule(
        "render_component",
        .{
            .root_source_file = b.path("src/render_component.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
            },
        },
    );
}
