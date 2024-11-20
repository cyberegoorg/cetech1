const std = @import("std");
const builtin = @import("builtin");

const patches = [_][]const u8{
    "patches/zf.patch",
    "patches/zgui.patch",
    // "patches/zglfw.patch",
    // "patches/ztracy.patch",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Sync remote repository
    //
    const sync_remote_step = b.step("sync-remote", "Upgrade repositories in repo folder");
    const sync_remote_submodules = b.addSystemCommand(&.{
        "git",
        "-C",
        "repo",

        // FIXME: skip zls (we need stay on specific commit for compatibility)
        //"-c",
        //"submodule.\"repo/zls\".update=none",

        "submodule",
        "update",
        "--init",
        "--remote",
    });
    sync_remote_step.dependOn(&sync_remote_submodules.step);

    //
    // Sync local
    //
    const sync_local_step = b.step("sync-local", "Copy files from repo to lib");
    const copy_tool = b.addExecutable(.{
        .name = "copy",
        .root_source_file = b.path("src/copy.zig"),
        .target = target,
        .optimize = optimize,
    });
    const copy_run = b.addRunArtifact(copy_tool);
    sync_local_step.dependOn(&copy_run.step);

    //
    // Sync remote repository
    //
    const apply_patches_step = b.step("apply-patches", "Apply patches");

    for (patches) |patch| {
        const apply_patches = b.addSystemCommand(&.{
            "git",
            "apply",
            patch,
        });
        apply_patches_step.dependOn(&apply_patches.step);
    }
}
