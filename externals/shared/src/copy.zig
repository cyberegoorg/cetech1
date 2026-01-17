const std = @import("std");

const RepositorySyncConfig = struct {
    repo_folder: []const u8,
    entries: []const []const u8,
};

const REPO_DIR = "repo";
const LIB_DIR = "lib";

// TODO: From file
const sync_list = [_]RepositorySyncConfig{
    .{
        .repo_folder = "SDL_GameControllerDB",
        .entries = &.{
            "gamecontrollerdb.txt",
            "LICENSE",
            "README.md",
        },
    },

    // .{
    //     .repo_folder = "system_sdk",
    //     .entries = &.{
    //         "linux",
    //         "macos12",
    //         "windows",
    //         ".gitattributes",
    //         ".gitignore",
    //         "build.zig",
    //         "build.zig.zon",
    //         "LICENSE",
    //         "README.md",
    //     },
    // },

    .{
        .repo_folder = "zbgfx",
        .entries = &.{
            "includes",
            "libs",
            "shaders",
            "src",
            "tools",
            ".gitattributes",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
            "AUTHORS.md",
        },
    },

    .{
        .repo_folder = "zf",
        .entries = &.{
            "src",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
            "CHANGELOG.md",
        },
    },

    .{
        .repo_folder = "zflecs",
        .entries = &.{
            "src",
            "libs",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "zglfw",
        .entries = &.{
            "src",
            "libs",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "zgui",
        .entries = &.{
            "src",
            "libs",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "zig-uuid",
        .entries = &.{
            "src",
            ".gitattributes",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "ziglang-set",
        .entries = &.{
            "src",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "zmath",
        .entries = &.{
            "src",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "znfde",
        .entries = &.{
            "includes",
            "nativefiledialog",
            "src",
            "build.zig",
            "build.zig.zon",
            "README.md",
        },
    },

    .{
        .repo_folder = "ztracy",
        .entries = &.{
            "libs",
            "src",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },

    .{
        .repo_folder = "zphysics",
        .entries = &.{
            "libs",
            "src",
            ".gitignore",
            "build.zig",
            "build.zig.zon",
            "LICENSE",
            "README.md",
        },
    },
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.fs.cwd().deleteTree(LIB_DIR);
    try std.fs.cwd().makeDir(LIB_DIR);

    var repo_dir = try std.fs.cwd().openDir(REPO_DIR, .{});
    defer repo_dir.close();

    var lib_dir = try std.fs.cwd().openDir(LIB_DIR, .{});
    defer lib_dir.close();

    for (sync_list) |config| {
        var src_dir = try repo_dir.openDir(config.repo_folder, .{});
        defer src_dir.close();

        try lib_dir.makeDir(config.repo_folder);
        var dest_dir = try lib_dir.openDir(config.repo_folder, .{});
        defer dest_dir.close();

        for (config.entries) |entry| {
            const stat = src_dir.statFile(entry) catch |e| {
                switch (e) {
                    error.FileNotFound => {
                        std.log.err("File {s} not found", .{entry});
                        continue;
                    },
                    else => return e,
                }
            };

            if (stat.kind == .file) {
                try src_dir.copyFile(entry, dest_dir, entry, .{});
            } else if (stat.kind == .directory) {
                // TODO: zig based dir copy
                const from_path = try std.fs.path.join(arena, &.{ REPO_DIR, config.repo_folder, entry });
                const to_path = try std.fs.path.join(arena, &.{ LIB_DIR, config.repo_folder, entry });

                _ = try std.process.Child.run(.{
                    .allocator = arena,
                    .argv = &.{
                        "cp",
                        "-r",
                        from_path,
                        to_path,
                    },
                });
            }
        }
    }

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
