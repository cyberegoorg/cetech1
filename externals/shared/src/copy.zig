const std = @import("std");

const RepositorySyncConfig = struct {
    repo_folder: []const u8,
    entries: []const []const u8,
};

const SyncConfig = struct {
    repository: []const RepositorySyncConfig,
};

const REPO_DIR = "repo";
const LIB_DIR = "lib";

const sync_list: SyncConfig = @import("sync.zon");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    var repo_dir = try std.Io.Dir.cwd().openDir(init.io, REPO_DIR, .{});
    defer repo_dir.close(init.io);

    var lib_dir = try std.Io.Dir.cwd().openDir(init.io, LIB_DIR, .{});
    defer lib_dir.close(init.io);

    for (sync_list.repository) |config| {
        var src_dir = try repo_dir.openDir(init.io, config.repo_folder, .{});
        defer src_dir.close(init.io);

        try lib_dir.deleteTree(init.io, config.repo_folder);

        try lib_dir.createDir(init.io, config.repo_folder, .default_dir);
        var dest_dir = try lib_dir.openDir(init.io, config.repo_folder, .{});
        defer dest_dir.close(init.io);

        for (config.entries) |entry| {
            const stat = src_dir.statFile(init.io, entry, .{}) catch |e| {
                switch (e) {
                    error.FileNotFound => {
                        std.log.err("File {s} not found", .{entry});
                        continue;
                    },
                    else => return e,
                }
            };

            if (stat.kind == .file) {
                try src_dir.copyFile(entry, dest_dir, entry, init.io, .{});
            } else if (stat.kind == .directory) {
                // TODO: zig based dir copy
                const from_path = try std.fs.path.join(arena, &.{ REPO_DIR, config.repo_folder, entry });
                const to_path = try std.fs.path.join(arena, &.{ LIB_DIR, config.repo_folder, entry });

                _ = try std.process.run(arena, init.io, .{
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

    return std.process.cleanExit(init.io);
}
