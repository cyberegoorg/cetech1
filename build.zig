const std = @import("std");
const builtin = @import("builtin");

const ztracy = @import("externals/shared/lib/zig-gamedev/libs/ztracy/build.zig");
const zjobs = @import("externals/shared/lib/zig-gamedev/libs/zjobs/build.zig");

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

    const enable_tracy = b.option(bool, "with-tracy", "build with tracy.") orelse true;
    const tracy_on_demand = b.option(bool, "tracy-on-demand", "build tracy with TRACY_ON_DEMAND") orelse true;

    const cetech_core_module = b.createModule(.{
        .source_file = .{ .path = "src/cetech1/core/cetech1.zig" },
        .dependencies = &.{},
    });

    // UUID
    const uuid_module = b.addModule("Uuid", .{ .source_file = .{ .path = "externals/shared/lib/zig-uuid/src/Uuid.zig" } });

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
    core_lib_static.addModule("Uuid", uuid_module);

    const exe_test = b.addTest(.{
        .name = "cetech1_test",
        .root_source_file = .{ .path = "src/cetech1/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_test.addIncludePath(.{ .path = "includes" });
    exe_test.linkLibrary(core_lib_static);
    exe_test.linkLibC();
    exe_test.addModule("Uuid", uuid_module);

    const exe = b.addExecutable(.{
        .name = "cetech1",
        .root_source_file = .{ .path = "src/cetech1/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .path = "includes" });
    exe.linkLibrary(core_lib_static);
    exe.addModule("cetech1", cetech_core_module);
    exe.addModule("Uuid", uuid_module);
    exe.linkLibC();

    var module_foo = try addCetechZigModule(
        b,
        "foo",
        "src/cetech1/modules/foo/private.zig",
        target,
        optimize,
        cetech_core_module,
    );
    _ = module_foo;

    var module_bar = try addCetechCModule(
        b,
        "bar",
        "src/cetech1/modules/bar/module_bar.c",
        target,
        optimize,
    );
    _ = module_bar;

    const ztracy_pkg = ztracy.package(b, target, optimize, .{
        .options = .{
            .enable_ztracy = enable_tracy,
            .enable_fibers = true,
        },
    });
    if (enable_tracy) {
        // Collect only if client is connected
        if (tracy_on_demand) ztracy_pkg.ztracy_c_cpp.defineCMacro("TRACY_ON_DEMAND", null);
    }
    ztracy_pkg.link(exe);
    ztracy_pkg.link(exe_test);

    const zjobs_pkg = zjobs.package(b, target, optimize, .{});
    zjobs_pkg.link(exe);
    zjobs_pkg.link(exe_test);

    b.installArtifact(exe_test);
    b.installArtifact(exe);
    b.installArtifact(core_lib_static);

    // const run_cmd = b.addRunArtifact(exe);
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);

    // const build_docs = b.addSystemCommand(&[_][]const u8{
    //     b.zig_exe,
    //     "test",
    //     "src/cetech1/core/cetech1.zig",
    //     "-femit-docs",
    //     "-fno-emit-bin",
    //     "-Iincludes",
    // });

    // const docs = b.step("docs", "Builds docs");

    // docs.dependOn(&build_docs.step);
}
