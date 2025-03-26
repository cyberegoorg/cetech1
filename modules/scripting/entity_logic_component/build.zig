const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "entity_logic_component",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("graphvm", b.dependency("graphvm", .{}).module("graphvm"));

    _ = b.addModule(
        "entity_logic_component",
        .{
            .root_source_file = b.path("src/entity_logic_component.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
            },
        },
    );
}
