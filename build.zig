const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "cetech1",
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = "src/cetech1/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(.{ .path = "includes" });

    const exe = b.addExecutable(.{
        .name = "cetech1",
        .root_source_file = .{ .path = "src/cetech1/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .path = "includes" });

    const test_exe = b.addTest(.{
        .name = "cetech1_test",
        .root_source_file = .{ .path = "src/cetech1/cetech1.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(test_exe);
    b.installArtifact(exe);
    b.installArtifact(lib);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const build_docs = b.addSystemCommand(&[_][]const u8{
        b.zig_exe,
        "test",
        "src/cetech1/cetech1.zig",
        "-femit-docs",
        "-fno-emit-bin",
    });

    const docs = b.step("docs", "Builds docs");

    docs.dependOn(&build_docs.step);
}
