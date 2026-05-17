const std = @import("std");
const builtin = @import("builtin");

pub const generate_ide = @import("src/tools/generate_ide.zig");
const zbgfx = @import("zbgfx");

const min_zig_version = std.SemanticVersion.parse("0.16.0") catch @panic("Where is .zigversion?");
const cetech1_version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

pub fn addCetechModule(
    b: *std.Build,
    comptime name: []const u8,
    version: std.SemanticVersion,
    root_source_file: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    target: ?std.Build.ResolvedTarget,
    optimize: ?std.builtin.OptimizeMode,
    static_modules: bool,
    studio: ?*std.Build.Step.Compile,
    runner: ?*std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = if (static_modules) .static else .dynamic,
        .name = "ct_" ++ name,
        .version = version,
        .root_module = b.createModule(
            .{
                .root_source_file = root_source_file,
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "cetech1", .module = cetech1_module },
                },
            },
        ),
        .use_llvm = true,
    });

    if (!static_modules) {
        b.installArtifact(lib);
    }

    if (static_modules) {
        if (studio) |exe| {
            exe.root_module.addImport("minimal", lib.root_module);
        }

        if (runner) |exe| {
            exe.root_module.addImport("minimal", lib.root_module);
        }
    }
    return lib;
}

pub fn installShaderc(
    b: *std.Build,
    cetech1_dep: *std.Build.Dependency,
) void {
    const zbgfx_dep = cetech1_dep.builder.dependency("zbgfx", .{});
    const shaderc_install = try zbgfx.build_step.installShaderc(b, zbgfx_dep);
    b.getInstallStep().dependOn(shaderc_install);
}

pub fn useSystemSDK(b: *std.Build, target: std.Build.ResolvedTarget, e: *std.Build.Module) void {
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
    cetech1_b: *std.Build,
    comptime bin_name: []const u8,
    comptime run_name: []const u8,
    comptime run_description: []const u8,
    runner_main: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    cetech1_kernel: *std.Build.Module,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_modules: bool,
) !*std.Build.Step.Compile {
    const use_lld = !target.result.os.tag.isDarwin();

    const exe = b.addExecutable(.{
        .name = bin_name,
        .version = versionn,
        .root_module = b.createModule(.{
            .root_source_file = runner_main,
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
        .use_lld = use_lld,
    });
    exe.root_module.link_libc = true;
    exe.root_module.addImport("kernel", cetech1_kernel);
    exe.root_module.addImport("cetech1", cetech1_module);
    b.installArtifact(exe);
    useSystemSDK(cetech1_b, target, exe.root_module);
    createRunStep(b, exe, run_name, run_description);

    const options_step = b.addOptions();
    options_step.addOption(bool, "static_modules", static_modules);
    const options_module = options_step.createModule();
    exe.root_module.addImport("kernel_options", options_module);
    return exe;
}

pub fn createStudioExe(
    b: *std.Build,
    cetech1_b: *std.Build,
    comptime base_bin_name: []const u8,
    root_source: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    cetech1_kernel: *std.Build.Module,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_modules: bool,
) !*std.Build.Step.Compile {
    return try createKernelExe(
        b,
        cetech1_b,
        base_bin_name ++ "_studio",
        "run-studio",
        "Run studio",
        root_source,
        cetech1_module,
        cetech1_kernel,
        versionn,
        target,
        optimize,
        static_modules,
    );
}

pub fn createRunnerExe(
    b: *std.Build,
    cetech1_b: *std.Build,
    comptime base_bin_name: []const u8,
    root_source: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    cetech1_kernel: *std.Build.Module,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_modules: bool,
) !*std.Build.Step.Compile {
    return try createKernelExe(
        b,
        cetech1_b,
        base_bin_name,
        "run",
        "Run Forest Run!",
        root_source,
        cetech1_module,
        cetech1_kernel,
        versionn,
        target,
        optimize,
        static_modules,
    );
}

pub fn build(b: *std.Build) !void {
    try ensureZigVersion();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // OPTIONS
    //
    const options = .{
        .app_name = b.option([]const u8, "app_name", "App name") orelse "CETech1",

        .externals_optimize = b.option(std.builtin.OptimizeMode, "externals_optimize", "Optimize for externals libs") orelse .ReleaseFast,
        .externals_shared = b.option(bool, "externals_shared", "Build externals as shared") orelse (optimize == .Debug),

        // Modules
        .enable_studio = b.option(bool, "with_studio", "Build with studio.") orelse true,
        .enable_runner = b.option(bool, "with_runner", "Build with runner.") orelse false,
        .enable_samples = b.option(bool, "with_samples", "Build with sample modules.") orelse true,
        .enable_test = b.option(bool, "with_test", "Build tests.") orelse false,

        .modules = b.option([]const []const u8, "with_module", "build with this modules."),

        // Tracy options
        .with_tracy = b.option(bool, "with_tracy", "build with tracy.") orelse true,
        .tracy_on_demand = b.option(bool, "tracy_on_demand", "build tracy with TRACY_ON_DEMAND") orelse true,

        // NFD options
        .with_nfd = b.option(bool, "with_nfd", "build with NFD (Native File Dialog).") orelse true,
        .nfd_portal = b.option(bool, "nfd_portal", "build NFD with xdg-desktop-portal instead of GTK. ( Linux, nice for steamdeck;) )") orelse true,

        // ZGUI
        .with_freetype = b.option(bool, "with_freetype", "build coreui with freetype support") orelse true,

        // BGFX
        .with_shaderc = b.option(bool, "with_shaderc", "build with shaderc support") orelse true,
    };

    const external_credits = b.option([]std.Build.LazyPath, "external_credits", "Path to additional .externals.zon .");
    const authors = b.option(std.Build.LazyPath, "authors", "Path to AUTHORS.");

    const options_step = b.addOptions();
    options_step.addOption(std.SemanticVersion, "version", cetech1_version);

    // add build args
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    const use_lld = !target.result.os.tag.isDarwin();

    //
    // Extrnals
    //

    // ZF
    const zf = b.dependency("zf", .{
        .target = target,
        .optimize = options.externals_optimize,
        .with_tui = false,
    });

    // ZNFDE
    const znfde = b.dependency("znfde", .{
        .target = target,
        .optimize = options.externals_optimize,
        .with_portal = options.nfd_portal,
        .shared = options.externals_shared,
    });

    // Tracy
    const ztracy = b.dependency("ztracy", .{
        .target = target,
        .optimize = options.externals_optimize,
        .enable_ztracy = options.with_tracy,
        .enable_fibers = false,
        .on_demand = options.tracy_on_demand,
        // .shared = options.externals_shared,
    });

    // ZGUI
    const zgui = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize, //options.externals_optimize,
        .backend = .glfw, // TODO: move to module
        .with_implot = true,
        .with_gizmo = true,
        .with_node_editor = true,
        .with_te = true,
        .with_freetype = options.with_freetype,
        .shared = options.externals_shared,
    });

    // ZGLFW
    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = options.externals_optimize,
        // .shared = options.externals_shared,
    });

    // ZFLECS
    const zflecs = b.dependency("zflecs", .{
        .target = target,
        .optimize = options.externals_optimize,
        .keep_assert = optimize == .Debug,
        .soft_assert = optimize == .Debug,
        .shared = options.externals_shared,
    });

    // ZBGFX
    const zbgfx_dep = b.dependency("zbgfx", .{
        .target = target,
        .optimize = options.externals_optimize,
        .shared = options.externals_shared,
    });

    // Jolt
    const zphysics = b.dependency("zphysics", .{
        .target = target,
        .optimize = options.externals_optimize,
        .use_double_precision = false,
        .enable_debug_renderer = true,
        .enable_cross_platform_determinism = true,
        .shared = options.externals_shared,
    });

    // Luau
    const zlua = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
        .lang = .luau,
    });

    // Ziglang set
    const ziglangSet = b.dependency("ziglangSet", .{
        .target = target,
        .optimize = optimize,
    });

    // ZMath
    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    // TODO: remove?
    const lucide_c = b.addTranslateC(.{
        .root_source_file = b.path("src/coreui/private/IconsLucide.h"),
        .target = target,
        .optimize = optimize,
    });

    //
    // TOOLS
    //

    // const copy_tool = b.addExecutable(.{
    //     .name = "copy",
    //     .root_source_file = .{ .path = "src/tools/copy.zig" },
    //     .target = target,
    // });

    // const generate_static_tool = b.addExecutable(.{
    //     .name = "generate_static",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("src/tools/generate_static.zig"),
    //         .target = b.graph.host,
    //     }),
    // });

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

    // Modules
    const ModulesSet = std.StringArrayHashMapUnmanaged(void);

    var internal_modules = std.ArrayListUnmanaged([]const u8).empty;
    defer internal_modules.deinit(b.allocator);

    var module_set = ModulesSet{};
    defer module_set.deinit(b.allocator);
    for (all_modules) |module| {
        try module_set.put(b.allocator, module, {});
    }

    var enabled_modules = std.ArrayListUnmanaged([]const u8).empty;
    defer enabled_modules.deinit(b.allocator);

    if (options.modules) |modules| {
        try enabled_modules.appendSlice(b.allocator, modules);
    } else {
        try enabled_modules.appendSlice(b.allocator, &core_modules);

        if (options.enable_samples) try enabled_modules.appendSlice(b.allocator, &samples_modules);
        if (options.enable_studio) try enabled_modules.appendSlice(b.allocator, &studio_modules);
        if (options.enable_runner) try enabled_modules.appendSlice(b.allocator, &runner_modules);
    }

    // Static modules.
    // var static_modules = ModulesSet{};
    // defer static_modules.deinit(b.allocator);

    // Dynamic modules.
    // var dynamic_modules = ModulesSet{};
    // defer dynamic_modules.deinit(b.allocator);

    // if (options.static_modules) {
    //     for (enabled_modules.items) |m| {
    //         try static_modules.put(b.allocator, m, {});
    //     }
    // } else if (options.dynamic_modules) {
    //     for (enabled_modules.items) |m| {
    //         if (static_modules.contains(m)) continue;
    //
    //         try dynamic_modules.put(b.allocator, m, {});
    //     }
    // }

    //
    // Generated content
    //
    const generated_files = b.addUpdateSourceFiles();

    // _static.zig
    // const gen_static = b.addRunArtifact(generate_static_tool);
    // const _static_output_file = gen_static.addOutputFileArg("_static.zig");
    // if (static_modules.count() != 0) {
    //     const modules_arg = try std.mem.join(b.allocator, ",", static_modules.keys());
    //     defer b.allocator.free(modules_arg);
    //     gen_static.addArg(modules_arg);
    // } else {
    //     gen_static.addArg("");
    // }

    // Extrenals credits/license
    const gen_externals = b.addRunArtifact(generate_externals_tool);
    const external_credits_file = gen_externals.addOutputFileArg("externals_credit.md");
    gen_externals.addFileArg(b.path(".externals.zon"));
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
        const ide = b.option(generate_ide.EditorType, "ide", "IDE for gen-ide command") orelse .VSCode;

        const gen_ide = b.addRunArtifact(generate_ide_tool);

        gen_ide.addArgs(&.{ "--ide", @tagName(ide) });

        gen_ide.addArg("--bin-path");
        gen_ide.addDirectoryArg(b.path("zig-out/bin/cetech1"));

        gen_ide.addArg("--project-path");
        gen_ide.addDirectoryArg(b.path(""));

        gen_ide.addArg("--fixtures");
        gen_ide.addDirectoryArg(b.path("fixtures/"));

        gen_ide.addArg("--config");
        gen_ide.addDirectoryArg(b.path(".ide.zon"));

        gen_ide_step.dependOn(&gen_ide.step);
    }

    //
    // CETech1 core build
    //
    const cetech1_module = b.addModule(
        "cetech1",
        .{
            .root_source_file = b.path("src/cetech1.zig"),
        },
    );
    cetech1_module.addImport("lucide_icons", lucide_c.createModule());
    cetech1_module.addImport("zmath", zmath.module("root"));
    cetech1_module.addImport("ziglangSet", ziglangSet.module("ziglangSet"));
    cetech1_module.addImport("cetech1_options", options_module);

    // const static_module_module = b.addModule("static_module", .{
    //     .root_source_file = _static_output_file,
    //     .imports = &.{
    //         .{ .name = "cetech1", .module = cetech1_module },
    //     },
    // });

    if (options.with_shaderc) {
        const shaderc_install = try zbgfx.build_step.installShaderc(b, zbgfx_dep);
        b.getInstallStep().dependOn(shaderc_install);
    }

    //
    // Dynamic modules
    //
    // var buff: [256:0]u8 = undefined;
    // for (dynamic_modules.keys()) |m| {
    //     const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
    //
    //     if (!module_set.contains(m)) continue;
    //
    //     const art = b.lazyDependency(m, .{
    //         .target = target,
    //         .optimize = optimize,
    //         .link_mode = .dynamic,
    //     }).?.artifact(artifact_name);
    //
    //     const step = b.addInstallArtifact(art, .{});
    //     b.default_step.dependOn(&step.step);
    // }
    const imports = [_]std.Build.Module.Import{
        .{ .name = "cetech1", .module = cetech1_module },

        .{ .name = "cetech1_options", .module = options_module },
        // .{ .name = "static_module", .module = static_module_module },

        // Deps
        .{ .name = "ztracy", .module = ztracy.module("root") },
        .{ .name = "zglfw", .module = zglfw.module("root") },
        .{ .name = "zgui", .module = zgui.module("root") },
        .{ .name = "zflecs", .module = zflecs.module("root") },
        .{ .name = "zphysics", .module = zphysics.module("root") },
        .{ .name = "zf", .module = zf.module("zf") },
        .{ .name = "zlua", .module = zlua.module("zlua") },
        .{ .name = "zbgfx", .module = zbgfx_dep.module("zbgfx") },

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
            .name = "font-main",
            .module = b.createModule(.{ .root_source_file = b.path("externals/shared/fonts/roboto/Roboto-Medium.ttf") }),
        },
        .{
            .name = "font-icons",
            .module = b.createModule(.{ .root_source_file = b.path("externals/shared/fonts/lucide/lucide.ttf") }),
        },
    };

    //
    // CETech1 kernel lib
    //

    const kernel_module = b.addModule("kernel", .{
        .root_source_file = b.path("src/private.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &imports,
        .link_libc = true,
    });
    useSystemSDK(b, target, kernel_module);
    kernel_module.linkLibrary(ztracy.artifact("tracy"));
    kernel_module.linkLibrary(zglfw.artifact("glfw"));
    kernel_module.linkLibrary(zgui.artifact("imgui"));
    kernel_module.linkLibrary(zflecs.artifact("flecs"));
    kernel_module.linkLibrary(zphysics.artifact("joltc"));
    kernel_module.linkLibrary(zbgfx_dep.artifact("bgfx"));

    if (options.with_nfd) {
        kernel_module.addImport("znfde", znfde.module("root"));
        kernel_module.linkLibrary(znfde.artifact("nfde"));
    }

    switch (target.result.os.tag) {
        .windows => {
            kernel_module.linkSystemLibrary("gdi32", .{ .needed = true });
            kernel_module.linkSystemLibrary("user32", .{ .needed = true });
            kernel_module.linkSystemLibrary("shell32", .{ .needed = true });
        },
        else => {},
    }

    //
    // CETech1 editor standalone exe
    //
    if (options.enable_studio) {
        const studio_exe = try createStudioExe(
            b,
            b,
            "cetech1",
            b.path("src/main_studio.zig"),
            cetech1_module,
            kernel_module,
            cetech1_version,
            target,
            optimize,
            false,
        );
        studio_exe.step.dependOn(&generated_files.step);

        const run_tests_ui = b.addRunArtifact(studio_exe);
        run_tests_ui.addArgs(&.{ "--test-ui", "--headless" });
        run_tests_ui.step.dependOn(b.getInstallStep());
        const testui_step = b.step("test-ui", "Run UI headless test");
        testui_step.dependOn(&run_tests_ui.step);
    }

    //
    // CETech1 runner standalone exe
    //
    if (options.enable_runner) {
        const runner_exe = try createRunnerExe(
            b,
            b,
            "cetech1",
            b.path("src/main_runner.zig"),
            cetech1_module,
            kernel_module,
            cetech1_version,
            target,
            optimize,
            false,
        );
        runner_exe.step.dependOn(&generated_files.step);
    }

    //
    // CETech1 kernel standalone tests
    //
    const tests = b.addTest(.{
        .name = "cetech1_test",
        .root_module = kernel_module,
        .use_llvm = true,
        .use_lld = use_lld,
    });
    useSystemSDK(b, target, tests.root_module);
    tests.step.dependOn(&generated_files.step);

    const run_unit_tests = b.addRunArtifact(tests);
    // run_unit_tests.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    if (options.enable_test) {
        b.installArtifact(tests);
    }

    //
    // Lua definition exporter
    //
    const def_exe = b.addExecutable(.{
        .name = "define-zig-types",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel/scripting/luauvm/luaapi.zig"),
            .target = target,
            .imports = &imports,
        }),
    });
    var run_def_exe = b.addRunArtifact(def_exe);
    run_def_exe.addFileArg(b.path("definitions.lua"));
    const define_step = b.step("define", "Generate definitions.lua file");
    define_step.dependOn(&run_def_exe.step);

    //
    // Samples
    //
    if (options.enable_samples) {
        _ = addCetechModule(
            b,
            "editor_foo_tab",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/editor_foo_tab/private.zig"),
            cetech1_module,
            target,
            optimize,
            false,
            null,
            null,
        );

        _ = addCetechModule(
            b,
            "editor_foo_viewport_tab",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/editor_foo_viewport_tab/private.zig"),
            cetech1_module,
            target,
            optimize,
            false,
            null,
            null,
        );

        _ = addCetechModule(
            b,
            "example_foo",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/foo/private.zig"),
            cetech1_module,
            target,
            optimize,
            false,
            null,
            null,
        );

        _ = addCetechModule(
            b,
            "example_native_script",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/native_script/private.zig"),
            cetech1_module,
            target,
            optimize,
            false,
            null,
            null,
        );
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

pub const studio_modules = [_][]const u8{};

pub const runner_modules = [_][]const u8{};

pub const core_modules = [_][]const u8{};

pub const samples_modules = [_][]const u8{};

pub const all_modules = core_modules ++ studio_modules ++ runner_modules ++ samples_modules;
