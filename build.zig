const std = @import("std");
const builtin = @import("builtin");

const min_zig_version = std.SemanticVersion.parse(@embedFile(".zigversion")) catch @panic("Where is .zigversion?");
const version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

pub fn build(b: *std.Build) !void {
    try ensureZigVersion();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // OPTIONS
    //

    const options = .{
        // Modules
        .enable_samples = b.option(bool, "with_samples", "build with sample modules.") orelse true,
        .enable_editor = b.option(bool, "with_editor", "build with editor modules.") orelse true,

        .modules = b.option([]const []const u8, "with_module", "build with this modules."),
        .static_modules = b.option(bool, "static_modules", "build all modules in static mode.") orelse false,
        .dynamic_modules = b.option(bool, "dynamic_modules", "build all modules in dynamic mode.") orelse true,

        // Tracy options
        .enable_tracy = b.option(bool, "with_tracy", "build with tracy.") orelse true,
        .tracy_on_demand = b.option(bool, "tracy_on_demand", "build tracy with TRACY_ON_DEMAND") orelse true,

        // NFD options
        .enable_nfd = b.option(bool, "with_nfd", "build with NFD (Native File Dialog).") orelse true,
        .nfd_portal = b.option(bool, "nfd_portal", "build NFD with xdg-desktop-portal instead of GTK. ( Linux, nice for steamdeck;) )") orelse true,

        .externals_optimize = b.option(std.builtin.OptimizeMode, "externals_optimize", "Optimize for externals libs") orelse .ReleaseFast,
    };

    const options_step = b.addOptions();
    options_step.addOption(std.SemanticVersion, "version", version);

    // add build args
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    //
    // Extrnals
    //

    // UUID
    const uuid = b.dependency(
        "uuid",
        .{
            .target = target,
            .optimize = options.externals_optimize,
        },
    );

    // ZF
    const zf = b.dependency(
        "zf",
        .{
            .target = target,
            .optimize = options.externals_optimize,
            .with_tui = false,
        },
    );

    // ZNFDE
    const znfde = b.dependency(
        "znfde",
        .{
            .target = target,
            .optimize = options.externals_optimize,
            .with_portal = options.nfd_portal,
        },
    );

    // Tracy
    const ztracy = b.dependency(
        "ztracy",
        .{
            .target = target,
            .optimize = options.externals_optimize,
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
            .optimize = options.externals_optimize,
        },
    );

    // ZGUI
    const zgui = b.dependency(
        "zgui",
        .{
            .target = target,
            .optimize = options.externals_optimize,
            .backend = .glfw,
            .with_te = true,
            .with_freetype = true,
        },
    );

    // ZGLFW
    const zglfw = b.dependency(
        "zglfw",
        .{
            .target = target,
            .optimize = options.externals_optimize,
        },
    );

    // ZPOOL
    const zpool = b.dependency(
        "zpool",
        .{
            .target = target,
            .optimize = options.externals_optimize,
        },
    );

    // ZFLECS
    const zflecs = b.dependency(
        "zflecs",
        .{
            .target = target,
            .optimize = options.externals_optimize,
        },
    );

    // ZBGFX
    const zbgfx = b.dependency(
        "zbgfx",
        .{
            .target = target,
            .optimize = options.externals_optimize,
            .imgui_include = zgui.path("libs").getPath(b),
        },
    );

    // ZLS
    const zls = b.dependency("zls", .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    // System sdk
    // const system_sdk = b.dependency("system_sdk", .{});

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
        .root_source_file = b.path("tools/generate_static.zig"),
        .target = target,
    });

    const generate_externals_tool = b.addExecutable(.{
        .name = "generate_externals",
        .root_source_file = b.path("tools/generate_externals.zig"),
        .target = target,
    });

    const generate_vscode_tool = b.addExecutable(.{
        .name = "generate_vscode",
        .root_source_file = b.path("tools/generate_vscode.zig"),
        .target = target,
    });

    // Modules
    var enabled_modules = std.ArrayList([]const u8).init(b.allocator);
    defer enabled_modules.deinit();

    try enabled_modules.appendSlice(&core_modules);

    if (options.enable_samples) try enabled_modules.appendSlice(&samples_modules);
    if (options.enable_editor) try enabled_modules.appendSlice(&editor_modules);

    //
    // Generated content
    //
    const generated_files = b.addUpdateSourceFiles();

    // _static.zig
    const modules_arg = try std.mem.join(b.allocator, ",", enabled_modules.items);
    defer b.allocator.free(modules_arg);

    const gen_static = b.addRunArtifact(generate_static_tool);
    const _static_output_file = gen_static.addOutputFileArg("_static.zig");
    gen_static.addArg(modules_arg);

    //generated_files.addCopyFileToSource(_static_output_file, "src/_static.zig");

    // Extrenals credits/license
    const gen_externals = b.addRunArtifact(generate_externals_tool);
    const external_credits_file = gen_externals.addOutputFileArg("externals_credit.md");
    inline for (externals) |external| {
        gen_externals.addArg(external.name);
        gen_externals.addDirectoryArg(b.path(external.file));
    }

    //
    // Init repository step
    //
    const init_step = b.step("init", "init repository");
    const init_lfs_writerside = b.addSystemCommand(&.{
        "git",
        "lfs",
        "pull",
        "--include",
        "Writerside/images/**/*",
    });
    const init_lfs_fonts = b.addSystemCommand(&.{
        "git",
        "lfs",
        "pull",
        "--include",
        "src/embed/fonts/*",
    });
    const init_lfs_system_sdk = b.addSystemCommand(&.{
        "git",
        "-C",
        "externals/shared/lib/zig-gamedev",
        "lfs",
        "pull",
        "--include",
        "libs/system-sdk/**/*",
    });
    init_step.dependOn(&init_lfs_writerside.step);
    init_step.dependOn(&init_lfs_fonts.step);
    init_step.dependOn(&init_lfs_system_sdk.step);

    //
    // Gen vscode
    //
    const vscode_step = b.step("vscode", "init/update vscode configs");
    const gen_vscode = b.addRunArtifact(generate_vscode_tool);
    gen_vscode.addDirectoryArg(b.path(".vscode/"));
    vscode_step.dependOn(&gen_vscode.step);

    //
    // ZLS
    //
    const zls_step = b.step("zls", "Build bundled ZLS");
    var zls_install = b.addInstallArtifact(zls.artifact("zls"), .{});
    zls_step.dependOn(&zls_install.step);

    //
    // CETech1 core build
    //
    const cetech1 = b.dependency(
        "cetech1",
        .{
            .target = target,
            .optimize = optimize,
            .with_tracy = options.enable_tracy,
        },
    );

    // cetech1 standalone exe
    const exe = b.addExecutable(.{
        .name = "cetech1",
        .version = version,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
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
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tests);
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

    //b.installArtifact(zbgfx.artifact("shaderc"));

    if (options.dynamic_modules) {
        var buff: [256:0]u8 = undefined;
        for (enabled_modules.items) |m| {
            const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
            const art = b.dependency(m, .{
                .target = target,
                .optimize = optimize,
            }).artifact(artifact_name);

            const step = b.addInstallArtifact(art, .{});
            b.default_step.dependOn(&step.step);
        }
    }

    // Libs, moduels etc..
    inline for (.{ exe, tests }) |e| {
        @import("system_sdk").addLibraryPathsTo(e);

        // Make exe depends on generated files.
        e.step.dependOn(&generated_files.step);

        e.root_module.addAnonymousImport("authors", .{
            .root_source_file = b.path("AUTHORS.md"),
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
            .root_source_file = b.path("externals/shared/lib/SDL_GameControllerDB/gamecontrollerdb.txt"),
        });

        e.root_module.addImport("cetech1", cetech1.module("cetech1"));

        e.root_module.addImport("cetech1_options", options_module);

        e.root_module.addImport("ztracy", ztracy.module("root"));
        e.root_module.addImport("zjobs", zjobs.module("root"));
        e.root_module.addImport("zpool", zpool.module("root"));
        e.root_module.addImport("zglfw", zglfw.module("root"));
        e.root_module.addImport("zgui", zgui.module("root"));
        e.root_module.addImport("zflecs", zflecs.module("root"));

        e.root_module.addImport("zf", zf.module("zf"));
        e.root_module.addImport("Uuid", uuid.module("Uuid"));
        e.root_module.addImport("zbgfx", zbgfx.module("zbgfx"));

        e.linkLibrary(ztracy.artifact("tracy"));
        e.linkLibrary(zglfw.artifact("glfw"));
        e.linkLibrary(zgui.artifact("imgui"));
        e.linkLibrary(zbgfx.artifact("bgfx"));
        e.linkLibrary(zflecs.artifact("flecs"));

        if (options.enable_nfd) {
            e.root_module.addImport("znfde", znfde.module("root"));
            e.linkLibrary(znfde.artifact("nfde"));
        }

        if (options.static_modules) {
            for (enabled_modules.items) |m| {
                e.linkLibrary(b.dependency(m, .{
                    .target = target,
                    .optimize = optimize,
                }).artifact("static"));
            }
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

const externals = .{
    // ZIG
    .{ .name = "zig", .file = "zig/LICENSE" },

    // zig-gamedev
    .{ .name = "zig-gamedev", .file = "externals/shared/lib/zig-gamedev/LICENSE" },
    .{ .name = "zglfw", .file = "externals/shared/lib/zig-gamedev/libs/zglfw/LICENSE" },
    .{ .name = "zpool", .file = "externals/shared/lib/zig-gamedev/libs/zpool/LICENSE" },
    .{ .name = "zjobs", .file = "externals/shared/lib/zig-gamedev/libs/zjobs/LICENSE" },
    .{ .name = "ztracy", .file = "externals/shared/lib/zig-gamedev/libs/ztracy/LICENSE" },
    .{ .name = "zgui", .file = "externals/shared/lib/zig-gamedev/libs/zgui/LICENSE" },
    .{ .name = "zflecs", .file = "externals/shared/lib/zig-gamedev/libs/zflecs/LICENSE" },

    // ImGui
    .{ .name = "imgui", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/imgui/LICENSE.txt" },
    .{ .name = "imgui_test_engine", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/imgui_test_engine/LICENSE.txt" },
    .{ .name = "implot", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/implot/LICENSE" },
    .{ .name = "imguizmo", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/imguizmo/LICENSE" },
    .{ .name = "imgui_node_editor", .file = "externals/shared/lib/zig-gamedev/libs/zgui/libs/node_editor/LICENSE" },

    // FLECS
    .{ .name = "FLECS", .file = "externals/shared/lib/zig-gamedev/libs/zflecs/libs/flecs/LICENSE" },

    // GLFW
    .{ .name = "glfw", .file = "externals/shared/lib/zig-gamedev/libs/zglfw/libs/glfw/LICENSE.md" },

    // SDL_GameControllerDB
    .{ .name = "SDL_GameControllerDB", .file = "externals/shared/lib/SDL_GameControllerDB/LICENSE" },

    // zf
    .{ .name = "zf", .file = "externals/shared/lib/zf/LICENSE" },

    // zig-uuid
    .{ .name = "zig-uuid", .file = "externals/shared/lib/zig-uuid/LICENSE" },

    // nativefiledialog-extended
    .{ .name = "nativefiledialog-extended", .file = "externals/shared/lib/znfde/nativefiledialog/LICENSE" },

    // BGFX
    .{ .name = "bgfx", .file = "externals/shared/lib/zbgfx/libs/bgfx/LICENSE" },

    // zbgfx
    .{ .name = "zbgfx", .file = "externals/shared/lib/zbgfx/LICENSE" },

    // ziglang-set
    .{ .name = "ziglang-set", .file = "externals/shared/lib/ziglang-set/LICENSE" },

    // cetech1
    .{ .name = "cetech1", .file = "LICENSE" },
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
    "editor_graph",
    "editor_metrics",
    "editor_entity_asset",
    "editor_entity",
    "editor_asset_preview",
    "editor_simulation",
};

const core_modules = [_][]const u8{
    "render_component",
    "entity_logic_component",
    "graphvm",
    "default_rg",
    "renderer",
    "transform",
    "camera",
};

const samples_modules = [_][]const u8{
    // Zig based module
    "foo",

    // Zig editor tab sample
    "editor_foo_tab",

    // Zig editor viewport tab sample
    "editor_foo_viewport_tab",
};
