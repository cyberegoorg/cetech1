const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .with_portal = b.option(
            bool,
            "with_portal",
            "Use xdg-desktop-portal instead of GTK",
        ) orelse true,
    };

    const znfde = b.addModule("root", .{
        .root_source_file = b.path("src/znfde.zig"),
    });

    var lib: *std.Build.Step.Compile = undefined;
    lib = b.addStaticLibrary(.{
        .name = "nfde",
        .target = target,
        .optimize = optimize,
    });

    const cflags = [_][]const u8{};

    lib.addIncludePath(b.path("nativefiledialog/src/include"));
    znfde.addIncludePath(b.path("nativefiledialog/src/include"));

    switch (lib.rootModuleTarget().os.tag) {
        .windows => {
            lib.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_win.cpp"), .flags = &cflags });
            lib.linkSystemLibrary("shell32");
            lib.linkSystemLibrary("ole32");
            lib.linkSystemLibrary("uuid");
        },
        .macos => {
            lib.root_module.addCMacro("NFD_MACOS_ALLOWEDCONTENTTYPES", "1");
            lib.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_cocoa.m"), .flags = &cflags });
            lib.linkFramework("AppKit");
            lib.linkFramework("UniformTypeIdentifiers");
        },
        else => {
            if (options.with_portal) {
                lib.addSystemIncludePath(b.path("includes"));
                znfde.addSystemIncludePath(b.path("includes"));
                lib.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_portal.cpp"), .flags = &cflags });
                lib.linkSystemLibrary("dbus-1");
            } else {
                lib.addCSourceFile(.{ .file = b.path("nativefiledialog/src/nfd_gtk.cpp"), .flags = &cflags });
                lib.linkSystemLibrary("atk-1.0");
                lib.linkSystemLibrary("gdk-3");
                lib.linkSystemLibrary("gtk-3");
                lib.linkSystemLibrary("glib-2.0");
                lib.linkSystemLibrary("gobject-2.0");
            }
            lib.linkLibCpp();
        },
    }

    b.installArtifact(lib);
}
