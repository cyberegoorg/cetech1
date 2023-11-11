const std = @import("std");

pub const Options = struct {
    enable_nfd: bool = true,
    with_zenity: bool = false,
};

pub const Package = struct {
    options: Options,
    nfd: *std.Build.Module,
    nfd_lib: *std.Build.Step.Compile,

    pub fn link(pkg: Package, exe: *std.Build.Step.Compile) void {
        exe.root_module.addImport("nfd", pkg.nfd);
        if (pkg.options.enable_nfd) {
            exe.linkLibrary(pkg.nfd_lib);
            exe.addIncludePath(.{ .path = thisDir() ++ "/nativefiledialog/src/include" });
        }
    }
};

pub fn package(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    args: struct {
        options: Options = .{},
    },
) Package {
    const nfd = b.addModule("nfd", .{
        .root_source_file = .{ .path = if (args.options.enable_nfd) thisDir() ++ "/src/nfd.zig" else thisDir() ++ "/src/nfd_dummy.zig" },
    });

    var lib: *std.Build.Step.Compile = undefined;

    if (args.options.enable_nfd) {
        lib = b.addStaticLibrary(.{
            .name = "nfd",
            .target = target,
            .optimize = optimize,
        });

        const cflags = [_][]const u8{};

        lib.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/nativefiledialog/src/nfd_common.c" }, .flags = &cflags });

        lib.addIncludePath(.{ .path = thisDir() ++ "/nativefiledialog/src/include" });
        nfd.addIncludePath(.{ .path = thisDir() ++ "/nativefiledialog/src/include" });

        switch (lib.rootModuleTarget().os.tag) {
            .windows => {
                lib.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/nativefiledialog/src/nfd_win.cpp" }, .flags = &cflags });
                lib.linkSystemLibrary("shell32");
                lib.linkSystemLibrary("ole32");
                lib.linkSystemLibrary("uuid");
            },
            .macos => {
                lib.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/nativefiledialog/src/nfd_cocoa.m" }, .flags = &cflags });
                lib.linkFramework("AppKit");
            },
            else => {
                if (args.options.with_zenity) {
                    lib.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/nativefiledialog/src/nfd_zenity.c" }, .flags = &cflags });
                } else {
                    lib.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/nativefiledialog/src/nfd_gtk.c" }, .flags = &cflags });
                    lib.linkSystemLibrary("atk-1.0");
                    lib.linkSystemLibrary("gdk-3");
                    lib.linkSystemLibrary("gtk-3");
                    lib.linkSystemLibrary("glib-2.0");
                    lib.linkSystemLibrary("gobject-2.0");
                }
            },
        }

        lib.linkLibC();
    }
    return .{
        .options = args.options,
        .nfd = nfd,
        .nfd_lib = lib,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Run nfd tests");
    test_step.dependOn(runTests(b, optimize, target));

    _ = package(b, target, optimize, .{});
}

pub fn runTests(
    b: *std.Build,
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
) *std.Build.Step {
    const tests = b.addTest(.{
        .name = "nfd-tests",
        .root_source_file = .{ .path = thisDir() ++ "/src/nfd.zig" },
        .target = target,
        .optimize = optimize,
    });

    const pkg = package(b, target, optimize, .{});
    pkg.link(tests);

    return &b.addRunArtifact(tests).step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
