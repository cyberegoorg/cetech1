const std = @import("std");
const builtin = @import("builtin");

const ztracy = @import("externals/shared/lib/zig-gamedev/libs/ztracy/build.zig");
const zjobs = @import("externals/shared/lib/zig-gamedev/libs/zjobs/build.zig");
const zgui = @import("externals/shared/lib/zig-gamedev/libs/zgui/build.zig");
const zglfw = @import("externals/shared/lib/zig-gamedev/libs/zglfw/build.zig");
const zgpu = @import("externals/shared/lib/zig-gamedev/libs/zgpu/build.zig");
const zpool = @import("externals/shared/lib/zig-gamedev/libs/zpool/build.zig");

const CETECH1_MODULE_PREFIX = "ct_";
const CETECH1_MAX_MODULE_NAME = 128;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "with-tracy", "build with tracy.") orelse true;
    const tracy_on_demand = b.option(bool, "tracy-on-demand", "build tracy with TRACY_ON_DEMAND") orelse true;
    const enable_nfd = b.option(bool, "with-nfd", "build with NFD (Native File Dialog).") orelse true;

    // UUID
    const uuid_module = b.addModule("Uuid", .{ .source_file = .{ .path = "externals/shared/lib/zig-uuid/src/Uuid.zig" } });

    // NFD
    const nfd_module = b.addModule("nfd", .{
        .source_file = .{
            .path = if (enable_nfd) "externals/shared/lib/nfd-zig/src/lib.zig" else "src/cetech1/core/private/nfd_dummy.zig",
        },
    });
    var lib_nfd2: ?*std.Build.Step.Compile = null;
    if (enable_nfd) {
        var lib_nfd = b.addStaticLibrary(.{
            .name = "nfd",
            .root_source_file = .{ .path = "externals/shared/lib/nfd-zig/src/lib.zig" },
            .target = target,
            .optimize = optimize,
        });
        lib_nfd2 = lib_nfd;

        lib_nfd.addModule("nfd", nfd_module);

        const cflags = [_][]const u8{"-Wall"};
        lib_nfd.addIncludePath(.{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/include" });
        lib_nfd.addCSourceFile(.{ .file = .{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/nfd_common.c" }, .flags = &cflags });
        if (lib_nfd.target.isDarwin()) {
            lib_nfd.addCSourceFile(.{ .file = .{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/nfd_cocoa.m" }, .flags = &cflags });
        } else if (lib_nfd.target.isWindows()) {
            lib_nfd.addCSourceFile(.{ .file = .{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/nfd_win.cpp" }, .flags = &cflags });
        } else {
            lib_nfd.addCSourceFile(.{ .file = .{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/nfd_gtk.c" }, .flags = &cflags });
        }

        lib_nfd.linkLibC();
        if (lib_nfd.target.isDarwin()) {
            lib_nfd.linkFramework("AppKit");
        } else if (lib_nfd.target.isWindows()) {
            lib_nfd.linkSystemLibrary("shell32");
            lib_nfd.linkSystemLibrary("ole32");
            lib_nfd.linkSystemLibrary("uuid"); // needed by MinGW
        } else {
            lib_nfd.linkSystemLibrary("atk-1.0");
            lib_nfd.linkSystemLibrary("gdk-3");
            lib_nfd.linkSystemLibrary("gtk-3");
            lib_nfd.linkSystemLibrary("glib-2.0");
            lib_nfd.linkSystemLibrary("gobject-2.0");
        }
    }
    // Tracy
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

    // ZJobs
    const zjobs_pkg = zjobs.package(b, target, optimize, .{});

    const zgui_pkg = zgui.package(b, target, optimize, .{
        .options = .{ .backend = .glfw_wgpu },
    });

    // Needed for glfw/wgpu rendering backend
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zpool_pkg = zpool.package(b, target, optimize, .{});
    const zgpu_pkg = zgpu.package(b, target, optimize, .{
        .deps = .{ .zpool = zpool_pkg.zpool, .zglfw = zglfw_pkg.zglfw },
    });

    // cetech1 module
    const cetech1_module = b.createModule(.{
        .source_file = .{ .path = "src/cetech1/core/cetech1.zig" },
        .dependencies = &.{},
    });

    // cetech1 static lib
    const core_lib_static = b.addStaticLibrary(.{
        .name = "cetech1",
        .version = .{ .major = 0, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = "src/cetech1/core/private/private.zig" },
        .target = target,
        .optimize = optimize,
    });
    core_lib_static.addIncludePath(.{ .path = "includes" });
    core_lib_static.addIncludePath(.{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/include" });
    core_lib_static.addCSourceFile(.{ .file = .{ .path = "src/cetech1/core/private/log.c" }, .flags = &.{} });
    core_lib_static.linkLibC();
    core_lib_static.addModule("Uuid", uuid_module);
    core_lib_static.addModule("nfd", nfd_module);

    // cetech1 standalone test
    const exe_test = b.addTest(.{
        .name = "cetech1_test",
        .root_source_file = .{ .path = "src/cetech1/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_test.addIncludePath(.{ .path = "includes" });
    exe_test.addIncludePath(.{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/include" });
    exe_test.linkLibrary(core_lib_static);
    exe_test.linkLibC();
    exe_test.addModule("Uuid", uuid_module);
    exe_test.addModule("nfd", nfd_module);

    // cetech1 standalone exe
    const exe = b.addExecutable(.{
        .name = "cetech1",
        .root_source_file = .{ .path = "src/cetech1/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .path = "includes" });
    exe.addIncludePath(.{ .path = "externals/shared/lib/nfd-zig/nativefiledialog/src/include" });
    exe.linkLibrary(core_lib_static);
    if (lib_nfd2) |lib| exe.linkLibrary(lib);
    exe.addModule("cetech1", cetech1_module);
    exe.addModule("Uuid", uuid_module);
    exe.addModule("nfd", nfd_module);
    exe.linkLibC();
    exe.addModule("nfd", nfd_module);

    if (lib_nfd2) |lib| {
        exe_test.linkLibrary(lib);
        exe.linkLibrary(lib);
    }

    zglfw_pkg.link(exe);
    zgpu_pkg.link(exe);
    zgui_pkg.link(exe);
    zglfw_pkg.link(exe_test);
    zgpu_pkg.link(exe_test);
    zgui_pkg.link(exe_test);

    // cetech1 core modules

    // Foo module is Zig based module and is used as sample and test
    var module_foo = try addCetechModule(
        b,
        "foo",
        "src/cetech1/modules/examples/foo/private.zig",
        target,
        optimize,
        cetech1_module,
    );
    _ = module_foo;

    // Bar module is C based module and is used as sample and test
    var module_bar = try addCetechModule(
        b,
        "bar",
        "src/cetech1/modules/examples/bar/module_bar.c",
        target,
        optimize,
        cetech1_module,
    );
    _ = module_bar;

    // Main editor
    const module_editor_public = b.createModule(.{
        .source_file = .{ .path = "src/cetech1/modules/editor/editor.zig" },
        .dependencies = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
    var module_editor = try addCetechModule(
        b,
        "editor",
        "src/cetech1/modules/editor/private.zig",
        target,
        optimize,
        cetech1_module,
    );
    _ = module_editor;

    // Editor asset browser
    var module_editor_asset_browser = try addCetechModule(
        b,
        "editor_asset_browser",
        "src/cetech1/modules/editor_asset_browser/private.zig",
        target,
        optimize,
        cetech1_module,
    );
    module_editor_asset_browser.addModule("editor", module_editor_public);

    // Editor properties
    var module_editor_propeties = try addCetechModule(
        b,
        "editor_properties",
        "src/cetech1/modules/editor_properties/private.zig",
        target,
        optimize,
        cetech1_module,
    );
    module_editor_propeties.addModule("editor", module_editor_public);

    // Editor properties
    var module_editor_explorer = try addCetechModule(
        b,
        "editor_explorer",
        "src/cetech1/modules/editor_explorer/private.zig",
        target,
        optimize,
        cetech1_module,
    );
    module_editor_explorer.addModule("editor", module_editor_public);

    // Foo editor tab
    var module_editor_foo_tab = try addCetechModule(
        b,
        "editor_foo_tab",
        "src/cetech1/modules/examples/editor_foo_tab/private.zig",
        target,
        optimize,
        cetech1_module,
    );
    module_editor_foo_tab.addModule("editor", module_editor_public);

    // Dependency links
    ztracy_pkg.link(exe);
    ztracy_pkg.link(exe_test);
    zjobs_pkg.link(exe);
    zjobs_pkg.link(exe_test);

    // Install artifacts
    b.installArtifact(exe_test);
    b.installArtifact(exe);
    b.installArtifact(core_lib_static);
}

fn getDynamicModuleExtensionForTargetOS(tag: std.Target.Os.Tag) []const u8 {
    return switch (tag) {
        .linux, .freebsd, .openbsd => ".so",
        .windows => ".dll",
        .macos, .tvos, .watchos, .ios => ".dylib",
        else => return undefined,
    };
}

fn addCetechModule(
    b: *std.Build,
    name: []const u8,
    root_source_file: []const u8,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    cetech_core_module: *std.Build.Module,
) !*std.build.Step.Compile {
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

    var buffer: [CETECH1_MAX_MODULE_NAME]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const tmp_allocator = fba.allocator();

    var module_name = try std.mem.join(
        tmp_allocator,
        "",
        &[_][]const u8{ CETECH1_MODULE_PREFIX, name, getDynamicModuleExtensionForTargetOS(target.getOs().tag) },
    );
    const plugin_install = b.addInstallFileWithDir(lib.getOutputSource(), .lib, module_name);
    plugin_install.step.dependOn(&lib.step);
    b.getInstallStep().dependOn(&plugin_install.step);
    return lib;
}
