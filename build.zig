const std = @import("std");
const builtin = @import("builtin");

fn get_dll_extension(tag: std.Target.Os.Tag) []const u8 {
    return switch (tag) {
        .linux, .freebsd, .openbsd => ".so",
        .windows => ".dll",
        .macos, .tvos, .watchos, .ios => ".dylib",
        else => return undefined,
    };
}

fn addCetechCModule(b: *std.Build, name: []const u8, root_source_file: []const u8, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) !*std.build.Step.Compile {
    const lib = b.addSharedLibrary(.{
        .name = name,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = root_source_file },
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(.{ .path = "includes" });
    lib.linkLibC();

    var buffer: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const tmp_allocator = fba.allocator();

    var module_name = try std.mem.join(tmp_allocator, "", &[_][]const u8{
        "ct_",
        name,
        get_dll_extension(target.getOs().tag),
    });
    const plugin_install = b.addInstallFileWithDir(lib.getOutputSource(), .lib, module_name);
    plugin_install.step.dependOn(&lib.step);
    b.getInstallStep().dependOn(&plugin_install.step);
    return lib;
}

fn addCetechZigModule(b: *std.Build, name: []const u8, root_source_file: []const u8, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, cetech_core_module: *std.Build.Module) !*std.build.Step.Compile {
    const lib = b.addSharedLibrary(.{
        .name = name,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = root_source_file },
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(.{ .path = "includes" });
    lib.addModule("cetech1", cetech_core_module);
    lib.linkLibC();

    var buffer: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const tmp_allocator = fba.allocator();

    var module_name = try std.mem.join(tmp_allocator, "", &[_][]const u8{
        "ct_",
        name,
        get_dll_extension(target.getOs().tag),
    });
    const plugin_install = b.addInstallFileWithDir(lib.getOutputSource(), .lib, module_name);
    plugin_install.step.dependOn(&lib.step);
    b.getInstallStep().dependOn(&plugin_install.step);
    return lib;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cetech_core_module = b.createModule(.{
        .source_file = .{ .path = "src/cetech1/core/cetech1.zig" },
        .dependencies = &.{},
    });

    const core_lib_static = b.addStaticLibrary(.{
        .name = "cetech1",
        .version = .{ .major = 0, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = "src/cetech1/core/private/private.zig" },
        .target = target,
        .optimize = optimize,
    });
    core_lib_static.addIncludePath(.{ .path = "includes" });
    core_lib_static.addCSourceFile(.{ .file = .{ .path = "src/cetech1/core/private/log.c" }, .flags = &.{} });
    core_lib_static.linkLibC();

    const test_exe = b.addTest(.{
        .name = "cetech1_test",
        .root_source_file = .{ .path = "src/cetech1/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_exe.addIncludePath(.{ .path = "includes" });
    test_exe.linkLibrary(core_lib_static);
    test_exe.linkLibC();

    const exe = b.addExecutable(.{
        .name = "cetech1",
        .root_source_file = .{ .path = "src/cetech1/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .path = "includes" });
    exe.linkLibrary(core_lib_static);
    exe.addModule("cetech1", cetech_core_module);
    exe.linkLibC();

    var ct_foo_module = try addCetechZigModule(
        b,
        "foo",
        "src/cetech1/modules/foo/private.zig",
        target,
        optimize,
        cetech_core_module,
    );
    _ = ct_foo_module;

    var ct_bar_module = try addCetechCModule(
        b,
        "bar",
        "src/cetech1/modules/bar/module_bar.c",
        target,
        optimize,
    );
    _ = ct_bar_module;

    b.installArtifact(test_exe);
    b.installArtifact(exe);
    b.installArtifact(core_lib_static);

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
        "src/cetech1/core/cetech1.zig",
        "-femit-docs",
        "-fno-emit-bin",
        "-Iincludes",
    });

    const docs = b.step("docs", "Builds docs");

    docs.dependOn(&build_docs.step);
}
