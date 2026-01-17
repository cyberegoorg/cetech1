const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "light_component",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("cetech1", cetech1_module);
    lib.root_module.addImport("editor_inspector", b.dependency("editor_inspector", .{}).module("editor_inspector"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("editor", b.dependency("editor", .{}).module("editor"));

    _ = b.addModule(
        "light_component",
        .{
            .root_source_file = b.path("src/light_component.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
            },
        },
    );
}
