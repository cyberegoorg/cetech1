const std = @import("std");
const builtin = @import("builtin");

pub fn addCetechModule(
    b: *std.Build,
    comptime name: []const u8,
    version: std.SemanticVersion,
    target: ?std.Build.ResolvedTarget,
    optimize: ?std.builtin.OptimizeMode,
) struct { *std.Build.Step.Compile, *std.Build.Module } {
    const cetech1 = b.dependency("cetech1", .{});
    const cetech1_module = cetech1.module("cetech1");

    const link_mode = b.option(std.builtin.LinkMode, "link_mode", "link mode for module") orelse .dynamic;
    const lib = b.addLibrary(.{
        .linkage = link_mode,
        .name = "ct_" ++ name,
        .version = version,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/private.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });
    lib.root_module.addImport("cetech1", cetech1_module);
    b.installArtifact(lib);
    return .{ lib, cetech1_module };
}

pub fn build(b: *std.Build) !void {

    //
    // OPTIONS
    //

    const options = .{
        // Tracy options
        .enable_tracy = b.option(bool, "with_tracy", "build with tracy.") orelse true,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zmath = b.dependency(
        "zmath",
        .{
            .target = target,
            //.optimize = optimize, // TODO: why?
        },
    );

    const ziglangSet = b.dependency("ziglangSet", .{
        .target = target,
        .optimize = optimize,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/faicons.h"),
        .target = target,
        .optimize = optimize,
    });

    const cetech1_module = b.addModule(
        "cetech1",
        .{
            .root_source_file = b.path("src/root.zig"),
        },
    );
    cetech1_module.addImport("icons_c", translate_c.createModule());
    cetech1_module.addImport("zmath", zmath.module("root"));
    cetech1_module.addImport("ziglangSet", ziglangSet.module("ziglangSet"));

    cetech1_module.addImport("cetech1_options", options_module);
}

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
        // .macos => {
        //     if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
        //         e.addLibraryPath(system_sdk.path("macos12/usr/lib"));
        //         e.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
        //     }
        // },
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
