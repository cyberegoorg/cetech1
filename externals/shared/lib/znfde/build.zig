const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .shared = b.option(
            bool,
            "shared",
            "Build shared library",
        ) orelse false,
        .with_portal = b.option(
            bool,
            "with_portal",
            "Use xdg-desktop-portal instead of GTK",
        ) orelse true,
    };

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("nativefiledialog/src/include/nfd.h"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("root", .{
        .root_source_file = b.path("src/znfde.zig"),
        .imports = &.{
            .{ .name = "cnfde", .module = translate_c.createModule() },
        },
        .link_libc = true,
    });

    var lib: *std.Build.Step.Compile = undefined;
    lib = b.addLibrary(.{
        .linkage = if (options.shared) .dynamic else .static,
        .name = "nfde",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = target.result.os.tag != .macos,
        }),
    });

    const cflags = [_][]const u8{};

    lib.root_module.addIncludePath(b.path("nativefiledialog/src/include"));

    switch (target.result.os.tag) {
        .windows => {
            lib.root_module.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_win.cpp"), .flags = &cflags });
            lib.root_module.linkSystemLibrary("shell32", .{ .needed = true });
            lib.root_module.linkSystemLibrary("ole32", .{ .needed = true });
            lib.root_module.linkSystemLibrary("uuid", .{ .needed = true });
        },
        .macos => {
            lib.root_module.addCMacro("NFD_MACOS_ALLOWEDCONTENTTYPES", "1");
            lib.root_module.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_cocoa.m"), .flags = &cflags });
            lib.root_module.linkFramework("AppKit", .{ .needed = true });
            lib.root_module.linkFramework("UniformTypeIdentifiers", .{ .needed = true });
            lib.root_module.linkFramework("CoreFoundation", .{ .needed = true });
            lib.root_module.linkFramework("Foundation", .{ .needed = true });
            lib.root_module.linkSystemLibrary("objc", .{});
        },
        else => {
            if (options.with_portal) {
                lib.root_module.addSystemIncludePath(b.path("includes"));
                lib.root_module.addSystemIncludePath(b.path("includes"));
                lib.root_module.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_portal.cpp"), .flags = &cflags });
                lib.root_module.linkSystemLibrary("dbus-1", .{ .needed = true });
            } else {
                lib.root_module.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_gtk.cpp"), .flags = &cflags });
                lib.root_module.linkSystemLibrary("atk-1.0", .{ .needed = true });
                lib.root_module.linkSystemLibrary("gdk-3", .{ .needed = true });
                lib.root_module.linkSystemLibrary("gtk-3", .{ .needed = true });
                lib.root_module.linkSystemLibrary("glib-2.0", .{ .needed = true });
                lib.root_module.linkSystemLibrary("gobject-2.0", .{ .needed = true });
            }
        },
    }

    b.installArtifact(lib);
}
