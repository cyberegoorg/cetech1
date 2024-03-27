const std = @import("std");
const builtin = @import("builtin");

pub const min_zig_version = std.SemanticVersion{ .major = 0, .minor = 12, .patch = 0, .pre = "dev.2063" };

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0, .pre = "a1" };

const bundled_modules = [_][]const u8{
    "bar",
    "foo",
    "editor_foo_tab",
    "editor",
    "editor_asset",
    "editor_asset_browser",
    "editor_explorer",
    "editor_fixtures",
    "editor_inspector",
    "editor_obj_buffer",
    "editor_tags",
    "editor_tree",
    "editor_log",
};

pub fn build(b: *std.Build) !void {
    try ensureZigVersion();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // OPTIONS
    //

    const options = .{
        .modules = b.option([]const []const u8, "with-module", "build with this modules.") orelse &bundled_modules,

        .static_modules = b.option(bool, "static-modules", "build all modules in static mode.") orelse false,

        // Tracy options
        .enable_tracy = b.option(bool, "with-tracy", "build with tracy.") orelse true,
        .tracy_on_demand = b.option(bool, "tracy-on-demand", "build tracy with TRACY_ON_DEMAND") orelse true,

        // NFD options
        .enable_nfd = b.option(bool, "with-nfd", "build with NFD (Native File Dialog).") orelse true,
        .nfd_portal = b.option(bool, "nfd-portal", "build NFD with xdg-desktop-portal instead of GTK. ( Linux, nice for steamdeck;) )") orelse true,
    };
    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    options_step.addOption(std.SemanticVersion, "version", version);
    const options_module = options_step.createModule();

    // TODO: Custom step?
    try generateStatic(b, options.modules);

    //
    // Extrnals
    //

    // UUID
    const uuid_module = b.dependency("uuid", .{}).module("Uuid");

    // ZF
    const zf_module = b.dependency("zf", .{}).module("zf");

    // ZNFDE
    const znfde = b.dependency("znfde", .{
        .with_portal = options.nfd_portal,
        .target = target,
    });

    // Mach gamemode
    const mach_gamemode_module = b.dependency(
        "mach_gamemode",
        .{ .target = target },
    ).module("mach-gamemode");

    // Tracy
    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = options.enable_tracy,
        .enable_fibers = false,
        .on_demand = options.tracy_on_demand,
        .target = target,
    });

    // ZJobs
    const zjobs = b.dependency("zjobs", .{
        .target = target,
    });

    // ZGUI
    const zgui = b.dependency("zgui", .{
        .backend = .glfw_wgpu,
        .target = target,
        .with_te = true,
    });

    // ZGLFW
    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });

    // ZPOOL
    const zpool = b.dependency("zpool", .{
        .target = target,
    });

    // ZGPU
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });

    //
    // CETech1 core
    //

    // cetech1 static lib
    // TODO: Is this needed this?
    const core_lib_static = b.addStaticLibrary(.{
        .name = "cetech1",
        .version = .{ .major = 0, .minor = 0, .patch = 0 },
        .root_source_file = .{ .path = "src/private/private.zig" },
        .target = target,
        .optimize = optimize,
    });
    core_lib_static.addIncludePath(.{ .path = "src/includes" });
    core_lib_static.addCSourceFile(.{ .file = .{ .path = "src/private/log.c" }, .flags = &.{} });
    core_lib_static.linkLibC();

    // cetech1 standalone exe
    const exe = b.addExecutable(.{
        .name = "cetech1",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.linkLibrary(core_lib_static);
    exe.linkLibC();

    // cetech1 standalone test
    const tests = b.addTest(.{
        .name = "cetech1_test",
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tests);
    tests.linkLibrary(core_lib_static);
    tests.linkLibC();

    const executables = .{ exe, tests };
    inline for (executables) |e| {
        @import("system_sdk").addLibraryPathsTo(e);
        @import("zgpu").addLibraryPathsTo(e);

        e.addIncludePath(.{ .path = "src/includes" });
        e.root_module.addImport("cetech1_options", options_module);

        e.root_module.addImport("ztracy", ztracy.module("root"));
        e.root_module.addImport("zjobs", zjobs.module("root"));
        e.root_module.addImport("zpool", zpool.module("root"));
        e.root_module.addImport("zglfw", zglfw.module("root"));
        e.root_module.addImport("zgpu", zgpu.module("root"));
        e.root_module.addImport("zgui", zgui.module("root"));
        e.root_module.addImport("zf", zf_module);
        e.root_module.addImport("Uuid", uuid_module);
        e.root_module.addImport("mach-gamemode", mach_gamemode_module);

        e.linkLibrary(ztracy.artifact("tracy"));
        e.linkLibrary(zglfw.artifact("glfw"));
        e.linkLibrary(zgpu.artifact("zdawn"));
        e.linkLibrary(zgui.artifact("imgui"));

        if (options.enable_nfd) {
            e.root_module.addImport("znfde", znfde.module("root"));
            e.linkLibrary(znfde.artifact("nfde"));
        }

        if (options.static_modules) {
            for (options.modules) |m| {
                e.linkLibrary(b.dependency(m, .{}).artifact("static"));
            }
        }
    }

    var buff: [256:0]u8 = undefined;
    for (options.modules) |m| {
        const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
        b.installArtifact(b.dependency(m, .{}).artifact(artifact_name));
    }
}

pub fn generateStatic(b: *std.Build, modules: []const []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const output_file_path = b.pathFromRoot("src/_static.zig");
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.log.err("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
        return err;
    };
    defer output_file.close();

    var w = output_file.writer();

    try w.print("// GENERATED - DO NOT EDIT\n", .{});
    try w.print("const cetech1 = @import(\"cetech1.zig\");\n\n", .{});

    for (modules) |m| {
        try w.print("extern fn ct_load_module_{s}(?*const cetech1.apidb.ct_apidb_api_t, ?*const cetech1.apidb.ct_allocator_t, u8, u8) callconv(.C) u8;\n", .{m});
    }

    try w.print("\npub const descs = [_]cetech1.modules.ct_module_desc_t{{\n", .{});

    for (modules) |m| {
        try w.print("    .{{ .name = \"{s}\", .module_fce = ct_load_module_{s} }},\n", .{ m, m });
    }

    try w.print("}};\n", .{});
}

fn ensureZigVersion() !void {
    var installed_ver = builtin.zig_version;
    installed_ver.build = null;

    if (installed_ver.order(min_zig_version) == .lt) {
        std.log.err("\n" ++
            \\---------------------------------------------------------------------------
            \\
            \\Installed Zig compiler version is too old.
            \\
            \\Min. required version: {any}
            \\Installed version: {any}
            \\
            \\Please install newer version and try again.
            \\zig/get_zig.sh <ARCH>
            \\
            \\---------------------------------------------------------------------------
            \\
        , .{ min_zig_version, installed_ver });
        return error.ZigIsTooOld;
    }
}
