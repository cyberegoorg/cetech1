const std = @import("std");
const builtin = @import("builtin");

const LaunchConfig = struct {
    version: []const u8 = "0.2.0",
    configurations: []const LaunchCmd = &.{
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{ "--asset-root", "fixtures/test_asset/" },
            .cwd = "${workspaceFolder}",
        },
        .{
            .type = osBasedType(),
            .request = "launch",
            .name = "CETech1 - graph",
            .program = osBasedProgram("${workspaceFolder}/zig-out/bin/cetech1"),
            .args = &.{ "--asset-root", "fixtures/test_graph/" },
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
    },
};

const LaunchCmd = struct {
    type: []const u8,
    request: []const u8,
    name: []const u8,
    program: []const u8,
    args: []const []const u8,
    cwd: []const u8,
};

fn osBasedProgram(comptime program: []const u8) []const u8 {
    return program ++ if (builtin.target.os.tag == .windows) ".exe" else "";
}

fn osBasedType() []const u8 {
    return if (builtin.target.os.tag == .windows) "cppvsdbg" else "lldb";
}

fn osBasedZigDir() []const u8 {
    return comptime builtin.target.osArchName() ++ "-" ++ @tagName(builtin.target.os.tag);
}

fn launchCmdToValue(allocator: std.mem.Allocator, cmd: LaunchCmd) !std.json.Value {
    var obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };

    try obj.object.put("type", std.json.Value{ .string = cmd.type });
    try obj.object.put("request", std.json.Value{ .string = cmd.request });
    try obj.object.put("name", std.json.Value{ .string = cmd.name });
    try obj.object.put("program", std.json.Value{ .string = cmd.program });

    var args_array = std.json.Value{ .array = std.json.Array.init(allocator) };
    for (cmd.args) |arg| {
        try args_array.array.append(.{ .string = arg });
    }
    try obj.object.put("args", args_array);

    try obj.object.put("cwd", std.json.Value{ .string = cmd.cwd });

    return obj;
}

fn createLauchJson(allocator: std.mem.Allocator, vscode_dir: std.fs.Dir) !void {
    _ = allocator; // autofix

    var obj_file = try vscode_dir.createFile("launch.json", .{});
    defer obj_file.close();

    var bw = std.io.bufferedWriter(obj_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_tab });
    try ws.write(LaunchConfig{});
}

fn createOrUpdateSettingsJson(allocator: std.mem.Allocator, vscode_dir: std.fs.Dir) !void {
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
        try parsed.value.object.put("files.associations", files_map);
    }

    const base_path = try vscode_dir.realpathAlloc(allocator, "..");
    defer allocator.free(base_path);

    // Zig
    const zig_path = try std.fs.path.join(allocator, &.{ base_path, "zig", "bin", osBasedZigDir(), osBasedProgram("zig") });
    defer allocator.free(zig_path);
    try parsed.value.object.put("zig.path", .{ .string = zig_path });

    // ZLS
    const zls_path = try std.fs.path.join(allocator, &.{ base_path, "zig-out", "bin", osBasedProgram("zls") });
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allcator = gpa.allocator();

    const args = try std.process.argsAlloc(allcator);
    defer std.process.argsFree(allcator, args);

    if (args.len != 2) fatal("wrong number of arguments {d}", .{args.len});

    const vscode_path = args[1];

    var vscode_dir = try std.fs.openDirAbsolute(vscode_path, .{});
    defer vscode_dir.close();

    try createLauchJson(allcator, vscode_dir);
    try createOrUpdateSettingsJson(allcator, vscode_dir);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
