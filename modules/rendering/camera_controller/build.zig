const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "camera_controller",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    lib.root_module.addImport("cetech1", cetech1_module);
    lib.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("actions", b.dependency("actions", .{}).module("actions"));

    _ = b.addModule(
        "camera_controller",
        .{
            .root_source_file = b.path("src/camera_controller.zig"),
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1_module },
                .{ .name = "camera", .module = b.dependency("camera", .{}).module("camera") },
            },
        },
    );
}
