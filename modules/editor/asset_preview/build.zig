const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const editor = b.dependency("editor", .{});

    const lib, const cetech1_module = cetech1_build.addCetechModule(
        b,
        "editor_asset_preview",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    _ = b.addModule("asset_preview", .{
        .root_source_file = b.path("src/asset_preview.zig"),
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });

    lib.root_module.addImport("editor", editor.module("editor"));
    lib.root_module.addImport("render_viewport", b.dependency("render_viewport", .{}).module("render_viewport"));
    lib.root_module.addImport("camera", b.dependency("camera", .{}).module("camera"));
    lib.root_module.addImport("camera_controller", b.dependency("camera_controller", .{}).module("camera_controller"));
    lib.root_module.addImport("transform", b.dependency("transform", .{}).module("transform"));
    lib.root_module.addImport("render_graph", b.dependency("render_graph", .{}).module("render_graph"));
    lib.root_module.addImport("render_pipeline", b.dependency("render_pipeline", .{}).module("render_pipeline"));
    lib.root_module.addImport("light_component", b.dependency("light_component", .{}).module("light_component"));
}
