const std = @import("std");
const builtin = @import("builtin");

pub const generate_ide = @import("src/tools/generate_ide.zig");

const min_zig_version = std.SemanticVersion.parse("0.15.1") catch @panic("Where is .zigversion?");
const cetech1_version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

pub fn useSystemSDK(b: *std.Build, target: std.Build.ResolvedTarget, e: *std.Build.Step.Compile) void {
    switch (target.result.os.tag) {
        .windows => {
            if (target.result.cpu.arch.isX86()) {
                if (target.result.abi.isGnu() or target.result.abi.isMusl()) {
                    if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                        e.addLibraryPath(system_sdk.path("windows/lib/x86_64-windows-gnu"));
                    }
                }
            }
        },
        .macos => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                e.addLibraryPath(system_sdk.path("macos12/usr/lib"));
                e.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
            }
        },
        .linux => {
            if (target.result.cpu.arch.isX86()) {
                if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                    e.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
                }
            } else if (target.result.cpu.arch == .aarch64) {
                if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                    e.addLibraryPath(system_sdk.path("linux/lib/aarch64-linux-gnu"));
                }
            }
        },
        else => {},
    }
}

pub fn createRunStep(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8, description: []const u8) void {
    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_exe.addArgs(args);
    }
    const run_step = b.step(name, description);
    run_step.dependOn(&run_exe.step);
}

pub fn initStep(
    b: *std.Build,
    step: *std.Build.Step,
    comptime cetech_dir: []const u8,
) void {
    _ = b;
    _ = step;
    _ = cetech_dir;
    // const init_lfs_writerside = b.addSystemCommand(&.{
    //     "git",
    //     "-C",
    //     cetech_dir,
    //     "lfs",
    //     "pull",
    //     "--include",
    //     "docs/images/**/*",
    // });
    // const init_lfs_fonts = b.addSystemCommand(&.{
    //     "git",
    //     "-C",
    //     cetech_dir,
    //     "lfs",
    //     "pull",
    //     "--include",
    //     "externals/shared/fonts/*",
    // });

    // const init_lfs_system_sdk = b.addSystemCommand(&.{
    //     "git",
    //     "-C",
    //     cetech_dir ++ "externals/shared/lib/system_sdk",
    //     "lfs",
    //     "pull",
    // });

    // step.dependOn(&init_lfs_writerside.step);
    // step.dependOn(&init_lfs_fonts.step);
    // step.dependOn(&init_lfs_system_sdk.step);

    // const init_submodules = b.addSystemCommand(&.{
    //     "git",
    //     "-C",
    //     cetech_dir,
    //     "submodule",
    //     "update",
    //     "--init",
    //     "externals/shared",
    // });
    // step.dependOn(&init_submodules.step);
    // init_lfs_system_sdk.step.dependOn(&init_submodules.step);
}

pub fn updateCectechStep(
    b: *std.Build,
    step: *std.Build.Step,
    comptime cetech_dir: []const u8,
) void {
    const sync_remote_submodules = b.addSystemCommand(&.{
        "git",
        "submodule",
        "update",
        "--init",
        "--remote",
        cetech_dir,
    });
    step.dependOn(&sync_remote_submodules.step);
}

pub fn createKernelExe(
    b: *std.Build,
    comptime bin_name: []const u8,
    runner_main: std.Build.LazyPath,
    cetech1_kernel: *std.Build.Module,
    cetech1_kernel_lib: *std.Build.Step.Compile,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = bin_name,
        .version = versionn,
        .root_module = b.createModule(.{
            .root_source_file = runner_main,
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });
    exe.linkLibC();
    exe.root_module.addImport("kernel", cetech1_kernel);
    exe.linkLibrary(cetech1_kernel_lib);
    b.installArtifact(exe);
    useSystemSDK(b, target, exe);
    createRunStep(b, exe, "run", "Run Forest run");

    return exe;
}

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

        .with_freetype = b.option(bool, "with_freetype", "build coreui with freetype support") orelse false,

        .externals_optimize = b.option(std.builtin.OptimizeMode, "externals_optimize", "Optimize for externals libs") orelse .ReleaseFast,

        .enable_shaderc = b.option(bool, "with_shaderc", "build with shaderc support") orelse true,

        .app_name = b.option([]const u8, "app_name", "App name") orelse "CETech1",
        .ide = b.option(generate_ide.EditorType, "ide", "IDE for gen-ide command") orelse .vscode,
    };

    const external_credits = b.option([]std.Build.LazyPath, "external_credits", "Path to additional .external_credits.json .");
    const authors = b.option(std.Build.LazyPath, "authors", "Path to AUTHORS.");

    const options_step = b.addOptions();
    options_step.addOption(std.SemanticVersion, "version", cetech1_version);

    // add build args
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    //
    // Extrnals
    //
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

    // ZGUI
    const zgui = b.dependency(
        "zgui",
        .{
            .target = target,
            .optimize = options.externals_optimize,
            .backend = .glfw,
            .with_implot = true,
            .with_gizmo = true,
            .with_node_editor = true,
            .with_te = true,
            .with_freetype = options.with_freetype,
            // .disable_obsolete = false
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_static.zig"),
            .target = b.graph.host,
        }),
    });

    const generate_externals_tool = b.addExecutable(.{
        .name = "generate_externals",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_externals.zig"),
            .target = b.graph.host,
        }),
    });

    const generate_ide_tool = b.addExecutable(.{
        .name = "generate_ide",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_ide.zig"),
            .target = b.graph.host,
        }),
    });
    b.installArtifact(generate_ide_tool);

    // Modules
    const ModulesSet = std.StringArrayHashMapUnmanaged(void);
    var module_set = ModulesSet{};
    defer module_set.deinit(b.allocator);
    for (all_modules) |module| {
        try module_set.put(b.allocator, module, {});
    }

    var enabled_modules = std.ArrayListUnmanaged([]const u8){};
    defer enabled_modules.deinit(b.allocator);

    if (options.modules) |modules| {
        try enabled_modules.appendSlice(b.allocator, modules);
    } else {
        try enabled_modules.appendSlice(b.allocator, &core_modules);

        if (options.enable_samples) try enabled_modules.appendSlice(b.allocator, &samples_modules);
        if (options.enable_editor) try enabled_modules.appendSlice(b.allocator, &editor_modules);
    }

    // Static modules.
    var static_modules = ModulesSet{};
    defer static_modules.deinit(b.allocator);

    // TODO: Problem with debugdraw in dll on windows.
    if (target.result.os.tag == .windows) {
        try static_modules.put(b.allocator, "gpu_bgfx", {});
    }

    // Dynamic modules.
    var dynamic_modules = ModulesSet{};
    defer dynamic_modules.deinit(b.allocator);

    if (options.static_modules) {
        for (enabled_modules.items) |m| {
            try static_modules.put(b.allocator, m, {});
        }
    } else if (options.dynamic_modules) {
        for (enabled_modules.items) |m| {
            if (static_modules.contains(m)) continue;

            try dynamic_modules.put(b.allocator, m, {});
        }
    }

    //
    // Generated content
    //
    const generated_files = b.addUpdateSourceFiles();

    // _static.zig
    const gen_static = b.addRunArtifact(generate_static_tool);
    const _static_output_file = gen_static.addOutputFileArg("_static.zig");

    if (static_modules.count() != 0) {
        const modules_arg = try std.mem.join(b.allocator, ",", static_modules.keys());
        defer b.allocator.free(modules_arg);
        gen_static.addArg(modules_arg);
    } else {
        gen_static.addArg("");
    }

    // Extrenals credits/license
    const gen_externals = b.addRunArtifact(generate_externals_tool);
    const external_credits_file = gen_externals.addOutputFileArg("externals_credit.md");
    gen_externals.addFileArg(b.path(".external_credits.zon"));
    if (external_credits) |credits| {
        for (credits) |ec| {
            gen_externals.addFileArg(ec);
        }
    }

    //
    // Init repository step
    //
    const init_step = b.step("init", "init repository");
    initStep(b, init_step, "./");

    //
    // Gen IDE config
    //
    const gen_ide_step = b.step("gen-ide", "init/update IDE configs");
    {
        const gen_ide = b.addRunArtifact(generate_ide_tool);

        gen_ide.addArgs(&.{ "--ide", @tagName(options.ide) });

        gen_ide.addArg("--bin-path");
        gen_ide.addDirectoryArg(b.path("zig-out/bin/cetech1"));

        gen_ide.addArg("--project-path");
        gen_ide.addDirectoryArg(b.path(""));

        gen_ide.addArg("--fixtures");
        gen_ide.addDirectoryArg(b.path("fixtures/"));

        gen_ide.addArg("--config");
        gen_ide.addDirectoryArg(b.path(".generate_ide.zon"));

        gen_ide_step.dependOn(&gen_ide.step);
    }

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

    const static_module_module = b.addModule("static_module", .{
        .root_source_file = _static_output_file,
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1.module("cetech1") },
        },
    });

    if (options.enable_shaderc) {
        b.installArtifact(zbgfx.artifact("shaderc"));
    }

    //
    // Dynamic modules
    //
    var buff: [256:0]u8 = undefined;
    for (dynamic_modules.keys()) |m| {
        const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
        const art = b.lazyDependency(m, .{
            .target = target,
            .optimize = optimize,
            .link_mode = .dynamic,
        }).?.artifact(artifact_name);

        const step = b.addInstallArtifact(art, .{});
        b.default_step.dependOn(&step.step);
    }

    const imports = [_]std.Build.Module.Import{
        .{ .name = "cetech1", .module = cetech1.module("cetech1") },

        .{ .name = "cetech1_options", .module = options_module },
        .{ .name = "static_module", .module = static_module_module },

        // Deps
        .{ .name = "ztracy", .module = ztracy.module("root") },
        .{ .name = "zglfw", .module = zglfw.module("root") },
        .{ .name = "zgui", .module = zgui.module("root") },
        .{ .name = "zflecs", .module = zflecs.module("root") },
        .{ .name = "zf", .module = zf.module("zf") },
        .{ .name = "Uuid", .module = uuid.module("Uuid") },
        .{ .name = "znfde", .module = znfde.module("root") },

        // Generated stuff
        .{
            .name = "externals_credit",
            .module = b.createModule(.{ .root_source_file = external_credits_file }),
        },
        .{
            .name = "authors",
            .module = b.createModule(.{ .root_source_file = authors orelse b.path("AUTHORS.md") }),
        },
        .{
            .name = "gamecontrollerdb",
            .module = b.createModule(.{ .root_source_file = b.path("externals/shared/lib/SDL_GameControllerDB/gamecontrollerdb.txt") }),
        },
        .{
            .name = "fa-solid-900",
            .module = b.createModule(.{ .root_source_file = b.path("externals/shared/fonts/fa-solid-900.ttf") }),
        },
        .{
            .name = "Roboto-Medium",
            .module = b.createModule(.{ .root_source_file = b.path("externals/shared/fonts/Roboto-Medium.ttf") }),
        },
    };

    //
    // CETech1 kernel lib
    //
    const kernel_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cetech1_kernel",
        .version = cetech1_version,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/private.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    useSystemSDK(b, target, kernel_lib);
    b.installArtifact(kernel_lib);
    kernel_lib.linkLibC();
    kernel_lib.linkLibrary(ztracy.artifact("tracy"));
    kernel_lib.linkLibrary(zglfw.artifact("glfw"));
    kernel_lib.linkLibrary(zgui.artifact("imgui"));
    kernel_lib.linkLibrary(zflecs.artifact("flecs"));

    if (options.enable_nfd) {
        kernel_lib.root_module.addImport("znfde", znfde.module("root"));
        kernel_lib.linkLibrary(znfde.artifact("nfde"));
    }

    const kernel_module = b.addModule("kernel", .{
        .root_source_file = b.path("src/private.zig"),
        .imports = &imports,
    });

    //
    // CETech1 kernel standalone exe
    //
    const exe = createKernelExe(
        b,
        "cetech1",
        b.path("src/main.zig"),
        kernel_module,
        kernel_lib,
        cetech1_version,
        target,
        optimize,
    );
    try linkStaticModules(b, exe, target, optimize, static_modules.keys());
    // Make exe depends on generated files.
    exe.step.dependOn(&generated_files.step);

    //
    // CETech1 kernel standalone tests
    //
    const tests = b.addTest(.{
        .name = "cetech1_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &imports,
        }),
        .use_llvm = true,
    });
    useSystemSDK(b, target, tests);
    b.installArtifact(tests);
    tests.linkLibC();
    tests.linkLibrary(kernel_lib);
    tests.step.dependOn(&generated_files.step);
    try linkStaticModules(b, tests, target, optimize, static_modules.keys());

    const run_unit_tests = b.addRunArtifact(tests);
    run_unit_tests.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const run_tests_ui = b.addRunArtifact(exe);
    run_tests_ui.addArgs(&.{ "--test-ui", "--headless" });
    run_tests_ui.step.dependOn(b.getInstallStep());
    const testui_step = b.step("test-ui", "Run UI headless test");
    testui_step.dependOn(&run_tests_ui.step);
}

fn linkStaticModules(
    b: *std.Build,
    e: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_modules: []const []const u8,
) !void {
    var buff: [256:0]u8 = undefined;

    for (static_modules) |m| {
        const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
        e.linkLibrary(b.lazyDependency(m, .{
            .target = target,
            .optimize = optimize,
            .link_mode = .static,
        }).?.artifact(artifact_name));
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

pub const editor_modules = [_][]const u8{
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
    "editor_renderer",
};

pub const core_modules = [_][]const u8{
    "gpu_bgfx",
    "graphvm",
    "render_viewport",
    "render_graph",
    "renderer_nodes",
    "render_pipeline",
    "default_render_pipeline",
    "shader_system",
    "render_component",
    "entity_logic_component",
    "transform",
    "camera",
    "vertex_system",
    "instance_system",
    "visibility_flags",
    "light_component",
    "light_system",
    "physics",
};

pub const samples_modules = [_][]const u8{
    // Zig based module
    "foo",

    // Zig editor tab sample
    "editor_foo_tab",

    // Zig editor viewport tab sample
    "editor_foo_viewport_tab",
};

pub const all_modules = editor_modules ++ core_modules ++ samples_modules;
