const std = @import("std");
const builtin = @import("builtin");

const min_zig_version = std.SemanticVersion.parse(@embedFile(".zigversion")) catch @panic("Where is .zigversion?");
const version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

const externals = .{
    // ZIG
    .{ .name = "zig", .file = "zig/LICENSE" },

    // zig-gamedev
    .{ .name = "zig-gamedev", .file = "externals/shared/lib/zig-gamedev/LICENSE" },

    // ImGui
    .{ .name = "imgui", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/imgui/LICENSE.txt" },
    .{ .name = "imgui_test_engine", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/imgui_test_engine/LICENSE.txt" },

    // GLFW
    .{ .name = "glfw", .file = "externals/shared/lib/zig-gamedev/libs/zglfw/libs/glfw/LICENSE.md" },

    // SDL_GameControllerDB
    .{ .name = "SDL_GameControllerDB", .file = "externals/shared/lib/SDL_GameControllerDB/LICENSE" },

    // zf
    .{ .name = "zf", .file = "externals/shared/lib/zf/LICENSE" },

    // zig-uuid
    .{ .name = "zig-uuid", .file = "externals/shared/lib/zig-uuid/LICENSE.md" },

    // nativefiledialog-extended
    .{ .name = "nativefiledialog-extended", .file = "externals/shared/lib/znfde/nativefiledialog/LICENSE" },

    // mach-gamemode
    .{ .name = "mach-gamemode", .file = "externals/shared/lib/mach-gamemode/LICENSE" },
};

const editor_modules = [_][]const u8{
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

const samples_modules = [_][]const u8{
    // C based module
    "bar",

    // Zig based module
    "foo",

    // Zig editor tab sample
    "editor_foo_tab",
};

pub fn build(b: *std.Build) !void {
    try ensureZigVersion();

    //
    // OPTIONS
    //

    const options = .{
        // Modules
        .enable_samples = b.option(bool, "with-samples", "build with sample modules.") orelse true,
        .enable_editor = b.option(bool, "with-editor", "build with editor modules.") orelse true,

        .modules = b.option([]const []const u8, "with-module", "build with this modules."),
        .static_modules = b.option(bool, "static-modules", "build all modules in static mode.") orelse false,
        .dynamic_modules = b.option(bool, "dynamic-modules", "build all modules in dynamic mode.") orelse true,

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

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Extrnals
    //

    // UUID
    const uuid = b.dependency(
        "uuid",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // ZF
    const zf = b.dependency(
        "zf",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // ZNFDE
    const znfde = b.dependency(
        "znfde",
        .{
            .target = target,
            .optimize = optimize,
            .with_portal = options.nfd_portal,
        },
    );

    // Mach gamemode
    const mach_gamemode = b.dependency(
        "mach_gamemode",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // Tracy
    const ztracy = b.dependency(
        "ztracy",
        .{
            .target = target,
            .optimize = optimize,
            .enable_ztracy = options.enable_tracy,
            .enable_fibers = false,
            .on_demand = options.tracy_on_demand,
        },
    );

    // ZJobs
    const zjobs = b.dependency(
        "zjobs",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // ZGUI
    const zgui = b.dependency(
        "zgui",
        .{
            .target = target,
            .optimize = optimize,
            .backend = .glfw_wgpu,
            .with_te = true,
        },
    );

    // ZGLFW
    const zglfw = b.dependency(
        "zglfw",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // ZPOOL
    const zpool = b.dependency(
        "zpool",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // ZGPU
    const zgpu = b.dependency(
        "zgpu",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    //
    // TOOLS
    //

    // const copy_tool = b.addExecutable(.{
    //     .name = "copy",
    //     .root_source_file = .{ .path = "tools/copy.zig" },
    //     .target = target,
    // });

    const generate_static_tool = b.addExecutable(.{
        .name = "generate_static",
        .root_source_file = .{ .path = "tools/generate_static.zig" },
        .target = target,
    });

    const generate_externals_tool = b.addExecutable(.{
        .name = "generate_externals",
        .root_source_file = .{ .path = "tools/generate_externals.zig" },
        .target = target,
    });

    // Modules
    var enabled_modules = std.ArrayList([]const u8).init(b.allocator);
    defer enabled_modules.deinit();
    if (options.enable_samples) try enabled_modules.appendSlice(&samples_modules);
    if (options.enable_editor) try enabled_modules.appendSlice(&editor_modules);

    //
    // Generated content
    //
    const generated_files = b.addWriteFiles();

    // _static.zig
    const modules_arg = try std.mem.join(b.allocator, ",", enabled_modules.items);
    defer b.allocator.free(modules_arg);

    const gen_static = b.addRunArtifact(generate_static_tool);
    const _static_output_file = gen_static.addOutputFileArg("_static.zig");
    gen_static.addArg(modules_arg);

    // Extrenals credits/license
    const gen_externals = b.addRunArtifact(generate_externals_tool);
    const external_credits_file = gen_externals.addOutputFileArg("externals_credit.md");
    inline for (externals) |external| {
        gen_externals.addArg(external.name);
        gen_externals.addDirectoryArg(.{ .path = external.file });
    }

    //
    // CETech1 core build
    //

    const cetech1 = b.dependency(
        "cetech1",
        .{},
    );

    // cetech1 static lib
    // TODO: Is this needed this?
    const core_lib_static = b.addStaticLibrary(.{
        .name = "cetech1_static",
        .version = version,
        .root_source_file = .{ .path = "src/private.zig" },
        .target = target,
        .optimize = optimize,
    });
    core_lib_static.addIncludePath(cetech1.path("includes"));
    core_lib_static.addCSourceFile(.{ .file = .{ .path = "src/log.c" }, .flags = &.{} });
    core_lib_static.linkLibC();

    // cetech1 standalone exe
    const exe = b.addExecutable(.{
        .name = "cetech1",
        .version = version,
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.linkLibrary(core_lib_static);
    exe.linkLibC();

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run Forest run");
    run_step.dependOn(&run_exe.step);

    // cetech1 standalone test
    const tests = b.addTest(.{
        .name = "cetech1_test",
        .version = version,
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tests);
    tests.linkLibrary(core_lib_static);
    tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(tests);
    run_unit_tests.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const run_tests_ui = b.addRunArtifact(exe);
    run_tests_ui.addArgs(&.{ "--test-ui", "--headless" });
    run_tests_ui.step.dependOn(b.getInstallStep());
    const testui_step = b.step("test-ui", "Run UI headless test");
    testui_step.dependOn(&run_tests_ui.step);

    // Libs, moduels etc..
    const executables = [_]*std.Build.Step.Compile{ exe, tests };
    inline for (executables) |e| {
        @import("system_sdk").addLibraryPathsTo(e);
        @import("zgpu").addLibraryPathsTo(e);

        // Make exe depends on generated files.
        e.step.dependOn(&generated_files.step);

        e.root_module.addAnonymousImport("authors", .{
            .root_source_file = .{ .path = "AUTHORS.md" },
        });

        e.root_module.addAnonymousImport("externals_credit", .{
            .root_source_file = external_credits_file,
        });

        e.root_module.addAnonymousImport("static_modules", .{
            .root_source_file = _static_output_file,
            .imports = &.{
                .{ .name = "cetech1", .module = cetech1.module("cetech1") },
            },
        });

        e.root_module.addAnonymousImport("gamecontrollerdb", .{
            .root_source_file = .{ .path = "externals/shared/lib/SDL_GameControllerDB/gamecontrollerdb.txt" },
        });

        e.root_module.addImport("cetech1", cetech1.module("cetech1"));
        e.addIncludePath(cetech1.path("includes"));

        e.root_module.addImport("cetech1_options", options_module);

        e.root_module.addImport("ztracy", ztracy.module("root"));
        e.root_module.addImport("zjobs", zjobs.module("root"));
        e.root_module.addImport("zpool", zpool.module("root"));
        e.root_module.addImport("zglfw", zglfw.module("root"));
        e.root_module.addImport("zgpu", zgpu.module("root"));
        e.root_module.addImport("zgui", zgui.module("root"));
        e.root_module.addImport("zf", zf.module("zf"));
        e.root_module.addImport("Uuid", uuid.module("Uuid"));
        e.root_module.addImport("mach-gamemode", mach_gamemode.module("mach-gamemode"));

        e.linkLibrary(ztracy.artifact("tracy"));
        e.linkLibrary(zglfw.artifact("glfw"));
        e.linkLibrary(zgpu.artifact("zdawn"));
        e.linkLibrary(zgui.artifact("imgui"));

        if (options.enable_nfd) {
            e.root_module.addImport("znfde", znfde.module("root"));
            e.linkLibrary(znfde.artifact("nfde"));
        }

        if (options.static_modules) {
            for (enabled_modules.items) |m| {
                e.linkLibrary(b.dependency(m, .{}).artifact("static"));
            }
        }
    }

    if (options.dynamic_modules) {
        var buff: [256:0]u8 = undefined;
        for (enabled_modules.items) |m| {
            const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
            b.installArtifact(b.dependency(m, .{}).artifact(artifact_name));
        }
    }
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
