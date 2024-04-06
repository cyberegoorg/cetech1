const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zmath = b.dependency(
        "zmath",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    const cetech1_module = b.addModule(
        "cetech1",
        .{
            .root_source_file = .{ .path = "root.zig" },
        },
    );
    cetech1_module.addIncludePath(.{ .path = "includes" });
    cetech1_module.addImport("zmath", zmath.module("root"));
}
