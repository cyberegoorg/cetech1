const std = @import("std");
const builtin = @import("builtin");
const cetech1_build = @import("cetech1");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ZBGFX
    const zbgfx = b.dependency(
        "zbgfx",
        .{
            .target = target,
            .optimize = .ReleaseFast, // TODO:
            //.optimize = .Debug, // TODO:
        },
    );

    const lib, _ = cetech1_build.addCetechModule(
        b,
        "gpu_bgfx",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
    );

    switch (target.result.os.tag) {
        .windows => {
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("user32");
            lib.linkSystemLibrary("shell32");
        },
        else => {},
    }
    lib.linkLibC();
    lib.linkLibrary(zbgfx.artifact("bgfx"));
    lib.root_module.addImport("zbgfx", zbgfx.module("zbgfx"));
}
