const std = @import("std");
const builtin = @import("builtin");

const ztracy = @import("ztracy");
const zpool = @import("zpool");
const zglfw = @import("zglfw");
const zjobs = @import("zjobs");
const zgui = @import("zgui");
const zgpu = @import("zgpu");
const nfd = @import("nfd");

const CETECH1_MODULE_PREFIX = "ct_";
const CETECH1_MAX_MODULE_NAME = 128;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "with-tracy", "build with tracy.") orelse true;
    const tracy_on_demand = b.option(bool, "tracy-on-demand", "build tracy with TRACY_ON_DEMAND") orelse true;
    const enable_nfd = b.option(bool, "with-nfd", "build with NFD (Native File Dialog).") orelse true;
    const nfd_zenity = b.option(bool, "nfd-zenity", "build NFD with zenity. ( Linux, nice for steamdeck;) )") orelse false;

    // UUID
    const uuid_module = b.dependency("uuid", .{}).module("Uuid");

    // ZF
    const zf_module = b.dependency("zf", .{}).module("zf");

    //NFD
    const nfd_pkg = nfd.package(b, target, optimize, .{
        .options = .{ .enable_nfd = enable_nfd, .with_zenity = nfd_zenity },
    });

    // Mach gamemode
    const mach_gamemode_module = b.dependency(
        "mach_gamemode",
        .{ .target = target, .optimize = optimize },
    ).module("mach-gamemode");

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

    // ZGUI
    const zgui_pkg = zgui.package(b, target, optimize, .{
        .options = .{ .backend = .glfw_wgpu },
    });

    // Needed for glfw/wgpu rendering backend
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zpool_pkg = zpool.package(b, target, optimize, .{});
    const zgpu_pkg = zgpu.package(b, target, optimize, .{
        .deps = .{ .zpool = zpool_pkg, .zglfw = zglfw_pkg },
    });

    // cetech1 static lib
    // TODO: Is this needed this?
    const core_lib_static = b.addStaticLibrary(.{
        .name = "cetech1",
        .version = .{ .major = 0, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = "src/cetech1/core/private/private.zig" },
        .target = target,
        .optimize = optimize,
    });
    core_lib_static.addIncludePath(.{ .path = thisDir() ++ "/includes/" });
    core_lib_static.addCSourceFile(.{ .file = .{ .path = "src/cetech1/core/private/log.c" }, .flags = &.{} });
    core_lib_static.linkLibC();

    // cetech1 standalone test
    const exe_test = b.addTest(.{
        .name = "cetech1_test",
        .root_source_file = .{ .path = "src/cetech1/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_test.root_module.addImport("zf", zf_module);
    exe_test.root_module.addImport("Uuid", uuid_module);
    exe_test.root_module.addImport("mach-gamemode", mach_gamemode_module);
    exe_test.addIncludePath(.{ .path = thisDir() ++ "/includes" });

    // cetech1 standalone exe
    const exe = b.addExecutable(.{
        .name = "cetech1",
        .root_source_file = .{ .path = "src/cetech1/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zf", zf_module);
    exe.root_module.addImport("Uuid", uuid_module);
    exe.root_module.addImport("mach-gamemode", mach_gamemode_module);
    exe.addIncludePath(.{ .path = thisDir() ++ "/includes" });

    // Dependency links

    ztracy_pkg.link(exe);
    ztracy_pkg.link(exe_test);
    zjobs_pkg.link(exe);
    zjobs_pkg.link(exe_test);
    zglfw_pkg.link(exe);
    zgpu_pkg.link(exe);
    zgui_pkg.link(exe);
    zglfw_pkg.link(exe_test);
    zgpu_pkg.link(exe_test);
    zgui_pkg.link(exe_test);

    nfd_pkg.link(exe);
    nfd_pkg.link(exe_test);

    exe.linkLibrary(core_lib_static);
    exe_test.linkLibrary(core_lib_static);

    exe.linkLibC();
    exe_test.linkLibC();

    // cetech1 module
    const cetech1_module = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/core/cetech1.zig" },
    });
    cetech1_module.addIncludePath(.{ .path = "includes" });

    // cetech1 core modules

    // Foo module is Zig based module and is used as sample and test
    const module_foo = try createCetechModule(
        b,
        "foo",
        "src/cetech1/modules/examples/foo/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    _ = module_foo;

    // Bar module is C based module and is used as sample and test
    const module_bar = try createCetechModule(
        b,
        "bar",
        null,
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_bar.addCSourceFile(.{ .file = .{ .path = "src/cetech1/modules/examples/bar/module_bar.c" }, .flags = &.{} });

    // Main editor
    const module_editor_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor/editor.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });

    const module_editor = try createCetechModule(
        b,
        "editor",
        "src/cetech1/modules/editor/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    _ = module_editor;

    // Editor tree
    const module_editor_tree_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor_tree/editor_tree.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = module_editor_public },
        },
    });

    const module_editor_tree = try createCetechModule(
        b,
        "editor_tree",
        "src/cetech1/modules/editor_tree/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_tree.root_module.addImport("editor", module_editor_public);

    // Obj buffer
    const module_editor_obj_buffer_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor_obj_buffer/editor_obj_buffer.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = module_editor_public },
        },
    });
    var module_editor_obj_buffer = try createCetechModule(
        b,
        "editor_obj_buffer",
        "src/cetech1/modules/editor_obj_buffer/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_obj_buffer.root_module.addImport("editor", module_editor_public);
    module_editor_obj_buffer.root_module.addImport("editor_tree", module_editor_tree_public);

    // Editor  tags
    const module_editor_tags_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor_tags/editor_tags.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = module_editor_public },
        },
    });
    var module_editor_tags = try createCetechModule(
        b,
        "editor_tags",
        "src/cetech1/modules/editor_tags/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_tags.root_module.addImport("editor", module_editor_public);

    // Editor asset browser
    const module_editor_asset_browser_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor_asset_browser/editor_asset_browser.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
    var module_editor_asset_browser = try createCetechModule(
        b,
        "editor_asset_browser",
        "src/cetech1/modules/editor_asset_browser/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_asset_browser.root_module.addImport("editor", module_editor_public);
    module_editor_asset_browser.root_module.addImport("editor_obj_buffer", module_editor_obj_buffer_public);
    module_editor_asset_browser.root_module.addImport("editor_tree", module_editor_tree_public);
    module_editor_asset_browser.root_module.addImport("editor_tags", module_editor_tags_public);

    // Editor properties
    const module_editor_propeties_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor_properties/editor_properties.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = module_editor_public },
        },
    });
    _ = module_editor_propeties_public;
    var module_editor_inspector = try createCetechModule(
        b,
        "editor_inspector",
        "src/cetech1/modules/editor_inspector/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_inspector.root_module.addImport("editor", module_editor_public);
    module_editor_inspector.root_module.addImport("editor_asset_browser", module_editor_asset_browser_public);

    // Editor explorer
    var module_editor_explorer = try createCetechModule(
        b,
        "editor_explorer",
        "src/cetech1/modules/editor_explorer/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_explorer.root_module.addImport("editor", module_editor_public);
    module_editor_explorer.root_module.addImport("editor_tree", module_editor_tree_public);

    // Editor fixtures
    const module_editor_fixtures_public = b.createModule(.{
        .root_source_file = .{ .path = "src/cetech1/modules/editor_fixtures/editor_fixtures.zig" },
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
            .{ .name = "editor", .module = module_editor_public },
        },
    });
    _ = module_editor_fixtures_public;
    var module_editor_fixtures = try createCetechModule(
        b,
        "editor_fixtures",
        "src/cetech1/modules/editor_fixtures/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_fixtures.root_module.addImport("editor", module_editor_public);
    module_editor_fixtures.root_module.addImport("editor_asset_browser", module_editor_asset_browser_public);

    // Foo editor tab
    var module_editor_foo_tab = try createCetechModule(
        b,
        "editor_foo_tab",
        "src/cetech1/modules/examples/editor_foo_tab/private.zig",
        .{ .major = 0, .minor = 1, .patch = 0 },
        target,
        optimize,
        cetech1_module,
    );
    module_editor_foo_tab.root_module.addImport("editor", module_editor_public);

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

fn createCetechModule(
    b: *std.Build,
    name: []const u8,
    root_source_file: ?[]const u8,
    version: ?std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cetech_core_module: *std.Build.Module,
) !*std.Build.Step.Compile {
    var buffer: [CETECH1_MAX_MODULE_NAME]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const tmp_allocator = fba.allocator();

    const module_name = try std.mem.join(
        tmp_allocator,
        "",
        &[_][]const u8{ CETECH1_MODULE_PREFIX, name, getDynamicModuleExtensionForTargetOS(target.result.os.tag) },
    );

    const module = b.addSharedLibrary(.{
        .name = name,
        .version = version,
        .root_source_file = if (root_source_file) |path| .{ .path = path } else null,
        .target = target,
        .optimize = optimize,
    });

    module.root_module.addImport("cetech1", cetech_core_module);
    module.addIncludePath(.{ .path = "includes" });

    const plugin_install = b.addInstallFileWithDir(module.getEmittedBin(), .lib, module_name);
    plugin_install.step.dependOn(&module.step);
    b.getInstallStep().dependOn(&plugin_install.step);

    return module;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
