const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const editor = b.dependency("editor", .{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_entity",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("editor", editor.module("editor"));
    lib.root_module.addImport("renderer", b.dependency("renderer", .{}).module("renderer"));
    lib.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));

    _ = b.addModule("editor_entity", .{
        .root_source_file = b.path("src/entity_editor.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
}
