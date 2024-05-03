const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root_source_file = b.path("src/Uuid.zig");

    // Module
    _ = b.addModule("Uuid", .{ .root_source_file = root_source_file });

    // Library
    const lib_step = b.step("lib", "Install library");

    const lib = b.addStaticLibrary(.{
        .name = "uuid",
        .target = target,
        .optimize = optimize,
        .root_source_file = root_source_file,
        .version = .{ .major = 1, .minor = 2, .patch = 3 },
    });

    const lib_install = b.addInstallArtifact(lib, .{});
    lib_step.dependOn(&lib_install.step);
    b.default_step.dependOn(lib_step);

    // Documentation
    const docs_step = b.step("doc", "Emit documentation");

    const docs_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "doc",
        .source_dir = lib.getEmittedDocs(),
    });

    docs_step.dependOn(&docs_install.step);
    b.default_step.dependOn(docs_step);

    // Benchmark suite
    const benchs_step = b.step("bench", "Run benchmark suite");

    const benchs = b.addExecutable(.{
        .target = target,
        .name = "uuid_benchs",
        .optimize = .ReleaseFast,
        .root_source_file = b.path("src/bench.zig"),
    });

    const benchs_run = b.addRunArtifact(benchs);
    if (b.args) |args| {
        benchs_run.addArgs(args);
    }
    benchs_step.dependOn(&benchs_run.step);
    b.default_step.dependOn(benchs_step);

    // Test suite
    const tests_step = b.step("test", "Run test suite");

    const tests = b.addTest(.{
        .root_source_file = root_source_file,
    });

    const tests_run = b.addRunArtifact(tests);
    tests_step.dependOn(&tests_run.step);
    b.default_step.dependOn(tests_step);

    // Code coverage
    const cov_step = b.step("cov", "Generate code coverage");

    const cov_run = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    cov_run.addArtifactArg(tests);

    cov_step.dependOn(&cov_run.step);
    b.default_step.dependOn(cov_step);

    // Formatting checks
    const fmt_step = b.step("fmt", "Run formatting checks");

    const fmt = b.addFmt(.{
        .paths = &.{ "src/", "build.zig" },
        .check = true,
    });

    fmt_step.dependOn(&fmt.step);
    b.default_step.dependOn(fmt_step);
}
