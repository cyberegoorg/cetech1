const std = @import("std");
const builtin = @import("builtin");

pub const generate_ide = @import("src/tools/generate_ide.zig");
const zbgfx = @import("zbgfx");

const cetech1_version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

pub const Cetech1ModuleOut = struct {
    public_module: ?*std.Build.Module = null,
    private_module: ?*std.Build.Module = null,
};

pub fn addCetechModule(
    b: *std.Build,
    name: []const u8,
    version: std.SemanticVersion,
    root_source_file: ?std.Build.LazyPath,
    public_root_source_file: ?std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_modules: ?*std.Build.Module,
) !Cetech1ModuleOut {
    var out = Cetech1ModuleOut{};

    if (root_source_file) |root_source| {
        const private_module = b.createModule(
            .{
                .root_source_file = root_source,
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "cetech1", .module = cetech1_module },
                },
            },
        );

        out.private_module = private_module;

        if (static_modules) |sm| {
            const import_name = try std.fmt.allocPrint(b.allocator, "{s}_private", .{name});
            defer b.allocator.free(import_name);
            sm.addImport(import_name, private_module);
        } else {
            const lib_name = try std.fmt.allocPrint(b.allocator, "ct_{s}", .{name});
            defer b.allocator.free(lib_name);

            const lib = b.addLibrary(.{
                .linkage = .dynamic,
                .name = lib_name,
                .version = version,
                .root_module = private_module,
                .use_llvm = true,
            });
            b.installArtifact(lib);
        }
    }

    if (public_root_source_file) |root_source| {
        const public_module = b.createModule(
            .{
                .root_source_file = root_source,
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "cetech1", .module = cetech1_module },
                },
            },
        );

        out.public_module = public_module;
    }
    return out;
}

pub fn addStaticModule(
    b: *std.Build,
    target: ?std.Build.ResolvedTarget,
    optimize: ?std.builtin.OptimizeMode,
    root_source_file: ?std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    shared_modules: []const []const u8,
    studio_modules: []const []const u8,
) !*std.Build.Module {
    const generate_static_tool = b.addExecutable(.{
        .name = "generate_static",
        .root_module = b.createModule(.{
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        }),
    });
    const gen_static = b.addRunArtifact(generate_static_tool);
    const static_output_file = gen_static.addOutputFileArg("_static.zig");
    const shared_m = try std.mem.join(b.allocator, ",", shared_modules);
    defer b.allocator.free(shared_m);
    gen_static.addArg("--shared");
    gen_static.addArg(shared_m);

    const studio_m = try std.mem.join(b.allocator, ",", studio_modules);
    defer b.allocator.free(studio_m);
    gen_static.addArg("--studio");
    gen_static.addArg(studio_m);

    return b.addModule("static_module", .{
        .root_source_file = static_output_file,
        .imports = &.{
            .{ .name = "cetech1", .module = cetech1_module },
        },
    });
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
    bin_name: []const u8,
    run_name: []const u8,
    run_description: []const u8,
    runner_main: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    cetech1_kernel: *std.Build.Module,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_module: *std.Build.Module,
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
    exe.root_module.addImport("static_modules", static_module);

    b.installArtifact(exe);
    useSystemSDK(cetech1_b, target, exe.root_module);
    createRunStep(b, exe, run_name, run_description);

    const options_step = b.addOptions();
    const options_module = options_step.createModule();
    exe.root_module.addImport("kernel_options", options_module);
    return exe;
}

pub fn createStudioExe(
    b: *std.Build,
    cetech1_b: *std.Build,
    base_bin_name: []const u8,
    root_source: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    cetech1_kernel: *std.Build.Module,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_module: *std.Build.Module,
) !*std.Build.Step.Compile {
    const bin_name = try std.fmt.allocPrint(b.allocator, "{s}_studio", .{base_bin_name});
    defer b.allocator.free(bin_name);

    return try createKernelExe(
        b,
        cetech1_b,
        bin_name,
        "run-studio",
        "Run studio",
        root_source,
        cetech1_module,
        cetech1_kernel,
        versionn,
        target,
        optimize,
        static_module,
    );
}

pub fn createRunnerExe(
    b: *std.Build,
    cetech1_b: *std.Build,
    base_bin_name: []const u8,
    root_source: std.Build.LazyPath,
    cetech1_module: *std.Build.Module,
    cetech1_kernel: *std.Build.Module,
    versionn: std.SemanticVersion,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static_module: *std.Build.Module,
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
        static_module,
    );
}

const ModuleDesc = struct {
    name: []const u8,
    private_root_file: std.Build.LazyPath,
    private_add_import: ?[]const std.Build.Module.Import = null,
    private_link_lib: ?[]const *std.Build.Step.Compile = null,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // OPTIONS
    //
    const options = .{
        .app_name = b.option([]const u8, "app_name", "App name") orelse "CETech1",
        .bin_name = b.option([]const u8, "bin_name", "App bin name") orelse "cetech1",

        .externals_optimize = b.option(std.builtin.OptimizeMode, "externals_optimize", "Optimize for externals libs") orelse .ReleaseFast,
        .externals_shared = b.option(bool, "externals_shared", "Build externals as shared") orelse (optimize == .Debug),

        // Modules
        .enable_studio = b.option(bool, "with_studio", "Build with studio.") orelse true,
        .enable_runner = b.option(bool, "with_runner", "Build with runner.") orelse false,
        .enable_samples = b.option(bool, "with_samples", "Build with sample modules.") orelse true,
        .enable_test = b.option(bool, "with_test", "Build tests.") orelse false,

        .modules = b.option([]const []const u8, "with_module", "build with this modules."),

        .add_shared_modules = b.option([]const []const u8, "add_shared_modules", "Add these static modules."),
        .add_studio_modules = b.option([]const []const u8, "add_studio_modules", "Add these static modules."),

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
    // Shared modules
    //
    const all_shared_modules = [_]ModuleDesc{
        .{ .name = "actions", .private_root_file = b.path("src/actions/private/actions.zig") },
        .{ .name = "transform", .private_root_file = b.path("src/transform/private/transform.zig") },
        .{ .name = "graphvm", .private_root_file = b.path("src/scripting/private/graphvm/graphvm.zig") },
        .{ .name = "graphvm_script_component", .private_root_file = b.path("src/scripting/private/graphvm/graphvm_script_component.zig") },
        .{ .name = "native_script_component", .private_root_file = b.path("src/scripting/private/native_script_component.zig") },
        .{
            .name = "luauvm",
            .private_root_file = b.path("src/scripting/private/luauvm/luauvm.zig"),
            .private_add_import = &.{
                .{ .name = "zlua", .module = zlua.module("zlua") },
            },
        },
        .{ .name = "luauvm_script_component", .private_root_file = b.path("src/scripting/private/luauvm/luauvm_script_component.zig") },
        .{ .name = "camera", .private_root_file = b.path("src/camera/private/camera.zig") },
        .{ .name = "camera_controller", .private_root_file = b.path("src/camera/private/camera_controller.zig") },
        .{ .name = "visibility_flags", .private_root_file = b.path("src/renderer/private/visibility_flags.zig") },
        .{ .name = "render_graph", .private_root_file = b.path("src/renderer/private/render_graph.zig") },
        .{ .name = "render_pipeline", .private_root_file = b.path("src/renderer/private/render_pipeline.zig") },
        .{ .name = "render_viewport", .private_root_file = b.path("src/renderer/private/render_viewport.zig") },
        .{ .name = "shader_system", .private_root_file = b.path("src/renderer/private/shader_system.zig") },
        .{ .name = "renderer_nodes", .private_root_file = b.path("src/renderer/private/renderer_nodes.zig") },
        .{ .name = "physics", .private_root_file = b.path("src/physics/private/physics.zig") },
        .{
            .name = "physics_jolt",
            .private_root_file = b.path("src/physics/private/physics_jolt.zig"),
            .private_add_import = &.{
                .{ .name = "zphysics", .module = zphysics.module("root") },
            },
            .private_link_lib = &.{
                zphysics.artifact("joltc"),
            },
        },
        .{ .name = "bloom", .private_root_file = b.path("src/renderer_pipeline/private/bloom.zig") },
        .{ .name = "default_render_pipeline", .private_root_file = b.path("src/renderer_pipeline/private/default_render_pipeline.zig") },
        .{ .name = "instance_system", .private_root_file = b.path("src/renderer_pipeline/private/instance_system.zig") },
        .{ .name = "light_component", .private_root_file = b.path("src/renderer_pipeline/private/light_component.zig") },
        .{ .name = "light_system", .private_root_file = b.path("src/renderer_pipeline/private/light_system.zig") },
        .{ .name = "render_component", .private_root_file = b.path("src/renderer_pipeline/private/render_component.zig") },
        .{ .name = "tonemap", .private_root_file = b.path("src/renderer_pipeline/private/tonemap.zig") },
        .{ .name = "vertex_system", .private_root_file = b.path("src/renderer_pipeline/private/vertex_system.zig") },
        .{
            .name = "gpu_bgfx",
            .private_root_file = b.path("src/gpu_bgfx/private/gpu_bgfx.zig"),
            .private_add_import = &.{
                .{ .name = "zbgfx", .module = zbgfx_dep.module("zbgfx") },
            },
            .private_link_lib = &.{
                zbgfx_dep.artifact("bgfx"),
            },
        },
    };

    //
    // Studio modules
    //
    const all_studio_modules = [_]ModuleDesc{
        .{ .name = "editor", .private_root_file = b.path("src/editor/private/editor.zig") },
        .{ .name = "editor_asset_browser", .private_root_file = b.path("src/editor/private/asset_browser.zig") },
        .{ .name = "editor_asset_preview", .private_root_file = b.path("src/editor/private/asset_preview.zig") },
        .{ .name = "editor_assetdb", .private_root_file = b.path("src/editor/private/assetdb.zig") },
        .{ .name = "editor_entity_asset", .private_root_file = b.path("src/editor/private/entity_asset.zig") },
        .{ .name = "editor_entity_editor", .private_root_file = b.path("src/editor/private/entity_editor.zig") },
        .{ .name = "editor_explorer", .private_root_file = b.path("src/editor/private/explorer.zig") },
        .{ .name = "editor_fixtures", .private_root_file = b.path("src/editor/private/fixtures.zig") },
        .{ .name = "editor_gizmo", .private_root_file = b.path("src/editor/private/gizmo.zig") },
        .{ .name = "editor_graph", .private_root_file = b.path("src/editor/private/graph.zig") },
        .{ .name = "editor_input", .private_root_file = b.path("src/editor/private/input.zig") },
        .{ .name = "editor_inspector", .private_root_file = b.path("src/editor/private/inspector.zig") },
        .{ .name = "editor_log", .private_root_file = b.path("src/editor/private/log.zig") },
        .{ .name = "editor_metrics", .private_root_file = b.path("src/editor/private/metrics.zig") },
        .{ .name = "editor_obj_buffer", .private_root_file = b.path("src/editor/private/obj_buffer.zig") },
        .{ .name = "editor_renderer", .private_root_file = b.path("src/editor/private/renderer.zig") },
        .{ .name = "editor_simulator", .private_root_file = b.path("src/editor/private/simulator.zig") },
        .{ .name = "editor_tabs", .private_root_file = b.path("src/editor/private/tabs.zig") },
        .{ .name = "editor_tree", .private_root_file = b.path("src/editor/private/tree.zig") },
    };

    //
    // TOOLS
    //

    // const copy_tool = b.addExecutable(.{
    //     .name = "copy",
    //     .root_source_file = .{ .path = "src/tools/copy.zig" },
    //     .target = target,
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

    //
    // Generated content
    //
    const generated_files = b.addUpdateSourceFiles();

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
            .target = target,
            .optimize = optimize,
        },
    );
    cetech1_module.addImport("lucide_icons", lucide_c.createModule());
    cetech1_module.addImport("zmath", zmath.module("root"));
    cetech1_module.addImport("ziglangSet", ziglangSet.module("ziglangSet"));
    cetech1_module.addImport("cetech1_options", options_module);

    if (options.with_shaderc) {
        const shaderc_install = try zbgfx.build_step.installShaderc(b, zbgfx_dep);
        b.getInstallStep().dependOn(shaderc_install);
    }

    const imports = [_]std.Build.Module.Import{
        .{ .name = "cetech1", .module = cetech1_module },
        .{ .name = "cetech1_options", .module = options_module },

        // Deps
        .{ .name = "ztracy", .module = ztracy.module("root") },
        .{ .name = "zglfw", .module = zglfw.module("root") },
        .{ .name = "zgui", .module = zgui.module("root") },
        .{ .name = "zflecs", .module = zflecs.module("root") },
        .{ .name = "zf", .module = zf.module("zf") },

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
    // Static modules
    //
    var static_shared_modules = std.ArrayList([]const u8).empty;
    defer static_shared_modules.deinit(b.allocator);
    for (all_shared_modules) |module| {
        try static_shared_modules.append(b.allocator, module.name);
    }
    if (options.add_shared_modules) |modules| {
        try static_shared_modules.appendSlice(b.allocator, modules);
    }

    var static_studio_modules = std.ArrayList([]const u8).empty;
    defer static_studio_modules.deinit(b.allocator);
    for (all_studio_modules) |module| {
        try static_studio_modules.append(b.allocator, module.name);
    }
    if (options.add_studio_modules) |modules| {
        try static_studio_modules.appendSlice(b.allocator, modules);
    }

    const static_module = try addStaticModule(
        b,
        target,
        optimize,
        b.path("src/tools/generate_static.zig"),
        cetech1_module,
        static_shared_modules.items,
        static_studio_modules.items,
    );

    //
    // CETech1 editor standalone exe
    //
    if (options.enable_studio) {
        const studio_exe = try createStudioExe(
            b,
            b,
            options.bin_name,
            b.path("src/main_studio.zig"),
            cetech1_module,
            kernel_module,
            cetech1_version,
            target,
            optimize,
            static_module,
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
            options.bin_name,
            b.path("src/main_runner.zig"),
            cetech1_module,
            kernel_module,
            cetech1_version,
            target,
            optimize,
            static_module,
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
    // Basic static modules
    //
    for (all_studio_modules) |value| {
        _ = try addCetechModule(
            b,
            value.name,
            .{ .major = 0, .minor = 1, .patch = 0 },
            value.private_root_file,
            null,
            cetech1_module,
            target,
            optimize,
            static_module,
        );
    }
    for (all_shared_modules) |value| {
        const out = try addCetechModule(
            b,
            value.name,
            .{ .major = 0, .minor = 1, .patch = 0 },
            value.private_root_file,
            null,
            cetech1_module,
            target,
            optimize,
            static_module,
        );

        if (value.private_add_import) |add_imports| {
            for (add_imports) |import| {
                out.private_module.?.addImport(import.name, import.module);
            }
        }

        if (value.private_link_lib) |libs| {
            for (libs) |l| {
                out.private_module.?.linkLibrary(l);
            }
        }
    }

    //
    // Samples
    //
    if (options.enable_samples) {
        _ = try addCetechModule(
            b,
            "editor_foo_tab",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/editor_foo_tab/private.zig"),
            null,
            cetech1_module,
            target,
            optimize,
            null,
        );

        _ = try addCetechModule(
            b,
            "editor_foo_viewport_tab",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/editor_foo_viewport_tab/private.zig"),
            null,
            cetech1_module,
            target,
            optimize,
            null,
        );

        _ = try addCetechModule(
            b,
            "example_foo",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/foo/private.zig"),
            null,
            cetech1_module,
            target,
            optimize,
            null,
        );

        _ = try addCetechModule(
            b,
            "example_native_script",
            .{ .major = 0, .minor = 1, .patch = 0 },
            b.path("src/examples/native_script/private.zig"),
            null,
            cetech1_module,
            target,
            optimize,
            null,
        );
    }
}
