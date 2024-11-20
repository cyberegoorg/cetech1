const std = @import("std");
const builtin = @import("builtin");

pub const LaunchCmd = struct {
    type: []const u8 = osBasedType(),
    request: []const u8,
    name: []const u8,
    program: []const u8,
    args: []const []const u8,
    cwd: []const u8,
};

pub const LaunchConfig = struct {
    version: []const u8 = "0.2.0",
    configurations: []const LaunchCmd,
};

pub fn osBasedProgram(comptime program: []const u8) []const u8 {
    return program ++ if (builtin.target.os.tag == .windows) ".exe" else "";
}

pub fn osBasedType() []const u8 {
    return if (builtin.target.os.tag == .windows) "cppvsdbg" else "lldb";
}

pub fn osBasedZigDir() []const u8 {
    return comptime builtin.target.osArchName() ++ "-" ++ @tagName(builtin.target.os.tag);
}

pub fn createLauchJson(allocator: std.mem.Allocator, vscode_dir: std.fs.Dir, config: LaunchConfig) !void {
    _ = allocator; // autofix

    var obj_file = try vscode_dir.createFile("launch.json", .{});
    defer obj_file.close();

    var bw = std.io.bufferedWriter(obj_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_tab });
    try ws.write(config);
}

pub fn createLauchCmdForFixtures(allocator: std.mem.Allocator, dir_path: []const u8) ![]LaunchCmd {
    var cmd_list = CmdList.init(allocator);

    var dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |path| {
        if (path.kind != .directory) continue;

        const basename = std.fs.path.basename(path.name);

        try cmd_list.append(.{
            .type = osBasedType(),
            .request = "launch",
            .name = try std.fmt.allocPrint(allocator, "CETech1 - {s}", .{basename}),
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = try allocator.dupe([]const u8, &.{
                "--asset-root",
                try std.fmt.allocPrint(allocator, "fixtures/{s}/", .{basename}),
            }),
            .cwd = "${workspaceFolder}",
        });
    }
    return cmd_list.toOwnedSlice();
}

pub fn createOrUpdateSettingsJson(allocator: std.mem.Allocator, vscode_dir: std.fs.Dir, is_project: bool) !void {
    // Read or create
    var parsed = blk: {
        var obj_file = vscode_dir.openFile("settings.json", .{ .mode = .read_only }) catch |err| {
            if (err == error.FileNotFound) {
                break :blk try std.json.parseFromSlice(std.json.Value, allocator, "{}", .{});
            }
            return err;
        };
        defer obj_file.close();
        var rb = std.io.bufferedReader(obj_file.reader());
        const reader = rb.reader();
        var json_reader = std.json.reader(allocator, reader);
        defer json_reader.deinit();

        break :blk try std.json.parseFromTokenSource(std.json.Value, allocator, &json_reader, .{});
    };
    defer parsed.deinit();

    // todo-tree.filtering.excludeGlobs
    {
        var args_array = std.json.Value{ .array = std.json.Array.init(parsed.arena.allocator()) };
        try args_array.array.append(.{ .string = "zig" });
        try args_array.array.append(.{ .string = "zig-out" });
        try args_array.array.append(.{ .string = "zig-cache" });
        try args_array.array.append(.{ .string = "externals" });
        try parsed.value.object.put("todo-tree.filtering.excludeGlobs", args_array);
    }

    // files.associations
    {
        var files_map = std.json.Value{ .object = std.json.ObjectMap.init(parsed.arena.allocator()) };
        try files_map.object.put("*.ct_*", std.json.Value{ .string = "json" });
        try files_map.object.put("vs_*.sc", std.json.Value{ .string = "glsl" });
        try files_map.object.put("fs_*.sc", std.json.Value{ .string = "glsl" });
        try files_map.object.put("cs_*.sc", std.json.Value{ .string = "glsl" });
        try files_map.object.put("bgfx_*.sh", std.json.Value{ .string = "glsl" });
        try files_map.object.put("shaderlib.sh", std.json.Value{ .string = "glsl" });

        try parsed.value.object.put("files.associations", files_map);
    }

    const base_path = try vscode_dir.realpathAlloc(allocator, "..");
    defer allocator.free(base_path);

    // Zig
    const zig_path = try std.fs.path.join(allocator, &.{ base_path, "zig", "bin", osBasedZigDir(), osBasedProgram("zig") });
    defer allocator.free(zig_path);
    try parsed.value.object.put("zig.path", .{ .string = zig_path });

    // ZLS
    const zls_path = if (is_project)
        try std.fs.path.join(allocator, &.{ base_path, "externals", "cetech1", "zig-out", "bin", osBasedProgram("zls") })
    else
        try std.fs.path.join(allocator, &.{ base_path, "zig-out", "bin", osBasedProgram("zls") });

    defer allocator.free(zls_path);
    try parsed.value.object.put("zig.zls.path", .{ .string = zls_path });

    // Write back
    var obj_file = try vscode_dir.createFile("settings.json", .{});
    defer obj_file.close();
    var bw = std.io.bufferedWriter(obj_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_tab });
    try ws.write(parsed.value);
}

const CmdList = std.ArrayList(LaunchCmd);
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allcator = gpa.allocator();

    const args = try std.process.argsAlloc(allcator);
    defer std.process.argsFree(allcator, args);

    if (args.len != 3) fatal("wrong number of arguments {d}", .{args.len});

    const vscode_path = args[1];

    const fixtures_path = args[2];

    var vscode_dir = try std.fs.openDirAbsolute(vscode_path, .{});
    defer vscode_dir.close();

    var cmd_list = CmdList.init(allcator);
    defer cmd_list.deinit();

    var tmp_arena = std.heap.ArenaAllocator.init(allcator);
    defer tmp_arena.deinit();

    const fixtures_cmds = try createLauchCmdForFixtures(tmp_arena.allocator(), fixtures_path);

    try cmd_list.appendSlice(&.{
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 no asset root",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{},
            .cwd = "${workspaceFolder}",
        },

        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 max 5 tick",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{ "--max-kernel-tick", "5", "--asset-root", "fixtures/test_asset/" },
            .cwd = "${workspaceFolder}",
        },
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 --headless",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{ "--max-kernel-tick", "5", "--asset-root", "fixtures/test_asset/", "--headless" },
            .cwd = "${workspaceFolder}",
        },
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 Tests",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1_test"),
            .args = &.{},
            .cwd = "${workspaceFolder}",
        },
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 Tests UI",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{"--test-ui"},
            .cwd = "${workspaceFolder}",
        },
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 Tests UI (headless) ",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{
                "--test-ui",
                "--headless",
                "--test-ui-junit",
                "./result.xml",
            },
            .cwd = "${workspaceFolder}",
        },
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 (Vulkan)",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{ "--asset-root", "fixtures/test_asset/", "--renderer", "vulkan" },
            .cwd = "${workspaceFolder}",
        },
    });

    try cmd_list.appendSlice(fixtures_cmds);

    try createLauchJson(allcator, vscode_dir, .{
        .configurations = cmd_list.items,
    });

    try createOrUpdateSettingsJson(allcator, vscode_dir, false);
}

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
