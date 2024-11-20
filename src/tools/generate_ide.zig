const std = @import("std");
const builtin = @import("builtin");

pub const EditorType = enum {
    vscode,
    fleet,
    idea,
};

pub const LaunchCmd = struct {
    name: []const u8,
    program: ?[]const u8 = null,
    args: []const []const u8,
    //cwd: []const u8,
};
pub const CmdList = std.ArrayList(LaunchCmd);

pub const LaunchConfig = struct {
    launchers: []const LaunchCmd,
};

pub fn osBasedProgramExtension() []const u8 {
    return if (builtin.target.os.tag == .windows) ".exe" else "";
}

pub fn osBasedZigDir() []const u8 {
    return comptime builtin.target.osArchName() ++ "-" ++ @tagName(builtin.target.os.tag);
}

pub fn genZlsPath(allocator: std.mem.Allocator, base_path: []const u8, is_project: bool) ![]u8 {
    return if (is_project)
        try std.fs.path.join(allocator, &.{ base_path, "externals", "cetech1", "externals", "shared", "repo", "zls", "zig-out", "bin", "zls" ++ comptime osBasedProgramExtension() })
    else
        try std.fs.path.join(allocator, &.{ base_path, "externals", "shared", "repo", "zls", "zig-out", "bin", "zls" ++ comptime osBasedProgramExtension() });
}

pub fn generateEditorConfigs(allocator: std.mem.Allocator, editor_type: EditorType, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    switch (editor_type) {
        .vscode => try generateEditorConfigsVSCode(allocator, project_dir, args, launch_cmds),
        .fleet => try generateEditorConfigsFleet(allocator, project_dir, args, launch_cmds),
        .idea => try generateEditorConfigsIdea(allocator, project_dir, args, launch_cmds),
    }
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
            .name = try std.fmt.allocPrint(allocator, "CETech1 - {s}", .{basename}),
            .args = try allocator.dupe([]const u8, &.{
                "--asset-root",
                try std.fmt.allocPrint(allocator, "fixtures/{s}/", .{basename}),
            }),
        });
    }
    return cmd_list.toOwnedSlice();
}

const ParseArgsResult = struct {
    gen_type: EditorType = .vscode,
    project_path: []const u8 = "",
    config: []const u8 = "",
    bin_path: []const u8 = "",
    fixtures_path: ?[]const u8 = null,
    is_project: bool = false,

    fn deinit(self: ParseArgsResult, allocator: std.mem.Allocator) void {
        defer if (self.fixtures_path) |path| allocator.free(path);
        defer allocator.free(self.project_path);
        defer allocator.free(self.config);
        defer allocator.free(self.bin_path);
    }
};

fn parseArgs(allocator: std.mem.Allocator) !ParseArgsResult {
    var result: ParseArgsResult = .{};
    errdefer result.deinit(allocator);

    var args_it: std.process.ArgIterator = try .initWithAllocator(allocator);
    defer args_it.deinit();

    const exe_path = args_it.next() orelse "";
    _ = exe_path;

    var arg_index: usize = 0;
    while (args_it.next()) |arg| : (arg_index += 1) {
        if (std.mem.eql(u8, arg, "--ide")) {
            const ide = args_it.next() orelse {
                std.log.err("Expected ide after --ide argument.", .{});
                std.process.exit(1);
            };

            result.gen_type = std.meta.stringToEnum(EditorType, ide).?;
        } else if (std.mem.eql(u8, arg, "--bin-path")) {
            const path = args_it.next() orelse {
                std.log.err("Expected path after bin-path argument.", .{});
                std.process.exit(1);
            };

            result.bin_path = try allocator.dupe(u8, path);
        } else if (std.mem.eql(u8, arg, "--config")) {
            const path = args_it.next() orelse {
                std.log.err("Expected path after --config argument.", .{});
                std.process.exit(1);
            };

            result.config = try allocator.dupe(u8, path);
        } else if (std.mem.eql(u8, arg, "--project-path")) {
            const path = args_it.next() orelse {
                std.log.err("Expected path after --project_path argument.", .{});
                std.process.exit(1);
            };
            result.project_path = try allocator.dupe(u8, path);
        } else if (std.mem.eql(u8, arg, "--fixtures")) {
            const path = args_it.next() orelse {
                std.log.err("Expected path after --fixtures argument.", .{});
                std.process.exit(1);
            };
            result.fixtures_path = try allocator.dupe(u8, path);
        } else if (std.mem.eql(u8, arg, "--is-project")) {
            result.is_project = true;
        } else {
            std.log.err("Unrecognized argument: '{s}'", .{arg});
            std.process.exit(1);
        }
    }

    return result;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const arguments = try parseArgs(allocator);
    defer arguments.deinit(allocator);

    var project_dir = try std.fs.openDirAbsolute(arguments.project_path, .{});
    defer project_dir.close();

    var cmd_list = CmdList.init(allocator);
    defer cmd_list.deinit();

    var config_file = try std.fs.openFileAbsolute(arguments.config, .{});
    defer config_file.close();

    var config_file_data = std.ArrayList(u8).init(allocator);
    defer config_file_data.deinit();

    const config_file_size = try config_file.getEndPos();
    try config_file.reader().readAllArrayList(&config_file_data, config_file_size);
    try config_file_data.append(0);

    const config = try std.zon.parse.fromSlice(
        LaunchConfig,
        allocator,
        config_file_data.items[0..config_file_size :0],
        null,
        .{},
    );
    defer std.zon.parse.free(allocator, config);

    for (config.launchers) |launcher| {
        // std.log.debug("{any}", .{launcher});
        try cmd_list.append(launcher);
    }

    var tmp_arena = std.heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();

    if (arguments.fixtures_path) |fixtures_path| {
        const fixtures_cmds = try createLauchCmdForFixtures(tmp_arena.allocator(), fixtures_path);
        try cmd_list.appendSlice(fixtures_cmds);
    }

    try generateEditorConfigs(allocator, arguments.gen_type, project_dir, arguments, cmd_list.items);
}

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

//
// VSCode
//
pub fn osBasedTypeVScode() []const u8 {
    return if (builtin.target.os.tag == .windows) "cppvsdbg" else "lldb";
}

pub const VSCodeLaunchCmd = struct {
    type: []const u8 = osBasedTypeVScode(),
    request: []const u8 = "launch",
    name: []const u8,
    program: []const u8,
    args: []const []const u8,
    cwd: []const u8,
};

pub const VSCodeLaunchConfig = struct {
    version: []const u8 = "0.2.0",
    configurations: []const VSCodeLaunchCmd,
};

pub const VSCodeCmdList = std.ArrayList(VSCodeLaunchCmd);

pub fn generateEditorConfigsVSCode(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    try createOrUpdateSettingsJsonVSCode(allocator, project_dir, args);
    try createLaunchersVSCode(allocator, project_dir, args, launch_cmds);
}

pub fn createLaunchersVSCode(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    var cmd_list = VSCodeCmdList.init(allocator);
    defer cmd_list.deinit();

    var tmp_arena = std.heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();
    const tmp_alloc = tmp_arena.allocator();

    for (launch_cmds) |cmd| {
        try cmd_list.append(.{
            .name = cmd.name,
            .program = try std.fmt.allocPrint(tmp_alloc, "{s}{s}", .{ cmd.program orelse args.bin_path, osBasedProgramExtension() }),
            .args = cmd.args,
            .cwd = "${workspaceFolder}",
        });
    }

    var vscode_dir = try project_dir.makeOpenPath(".vscode", .{});
    defer vscode_dir.close();

    var obj_file = try vscode_dir.createFile("launch.json", .{});
    defer obj_file.close();

    var bw = std.io.bufferedWriter(obj_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_tab });
    try ws.write(VSCodeLaunchConfig{ .configurations = cmd_list.items });
}

pub fn createOrUpdateSettingsJsonVSCode(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult) !void {
    var vscode_dir = try project_dir.makeOpenPath(".vscode", .{});
    defer vscode_dir.close();

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
        try files_map.object.put("vs_*.sc", std.json.Value{ .string = "glsl" });
        try files_map.object.put("fs_*.sc", std.json.Value{ .string = "glsl" });
        try files_map.object.put("cs_*.sc", std.json.Value{ .string = "glsl" });
        try files_map.object.put("bgfx_*.sh", std.json.Value{ .string = "glsl" });
        try files_map.object.put("shaderlib.sh", std.json.Value{ .string = "glsl" });

        try parsed.value.object.put("files.associations", files_map);
    }

    const base_path = try project_dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);

    // // Zig
    // const zig_path = try std.fs.path.join(allocator, &.{ base_path, "zig", "bin", osBasedZigDir(), "zig") });
    // defer allocator.free(zig_path);
    // try parsed.value.object.put("zig.path", .{ .string = zig_path });

    // ZLS
    const zls_path = try genZlsPath(allocator, base_path, args.is_project);
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

//
// Fleet
//
pub const FleetCodeLaunchCmd = struct {
    type: []const u8,
    name: []const u8,
    program: []const u8,
    args: []const []const u8,
    workingDir: []const u8,
};

pub const FleetCodeLaunchConfig = struct {
    configurations: []const FleetCodeLaunchCmd,
};

pub const FleetCodeCmdList = std.ArrayList(FleetCodeLaunchCmd);

pub fn generateEditorConfigsFleet(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    try createOrUpdateSettingsJsonFleet(allocator, project_dir, args);
    try createLaunchersFleet(allocator, project_dir, args, launch_cmds);
}

pub fn createLaunchersFleet(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    var cmd_list = FleetCodeCmdList.init(allocator);
    defer cmd_list.deinit();

    var tmp_arena = std.heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();
    const tmp_alloc = tmp_arena.allocator();

    for (launch_cmds) |cmd| {
        try cmd_list.append(.{
            .type = "command",
            .name = cmd.name,
            .program = try std.fmt.allocPrint(tmp_alloc, "{s}{s}", .{ cmd.program orelse args.bin_path, osBasedProgramExtension() }),
            .args = cmd.args,
            .workingDir = "$WORKSPACE_DIR$",
        });
    }

    var vscode_dir = try project_dir.makeOpenPath(".fleet", .{});
    defer vscode_dir.close();

    var obj_file = try vscode_dir.createFile("run.json", .{});
    defer obj_file.close();

    var bw = std.io.bufferedWriter(obj_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_tab });
    try ws.write(FleetCodeLaunchConfig{ .configurations = cmd_list.items });
}

pub fn createOrUpdateSettingsJsonFleet(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult) !void {
    var fleet_dir = try project_dir.makeOpenPath(".fleet", .{});
    defer fleet_dir.close();

    // Read or create
    var parsed = blk: {
        var obj_file = fleet_dir.openFile("settings.json", .{ .mode = .read_only }) catch |err| {
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

    const base_path = try project_dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);

    // plugins
    {
        var zig_plugin = std.json.Value{ .object = std.json.ObjectMap.init(parsed.arena.allocator()) };
        try zig_plugin.object.put("type", std.json.Value{ .string = "add" });
        try zig_plugin.object.put("pluginName", std.json.Value{ .string = "fleet.zig" });

        var args_array = std.json.Value{ .array = std.json.Array.init(parsed.arena.allocator()) };
        try args_array.array.append(.{ .object = zig_plugin.object });
        try parsed.value.object.put("plugins", args_array);
    }

    // ZLS
    const zls_path = try genZlsPath(allocator, base_path, args.is_project);
    defer allocator.free(zls_path);
    try parsed.value.object.put("zig.zls.path", .{ .string = zls_path });

    // Write back
    var obj_file = try fleet_dir.createFile("settings.json", .{});
    defer obj_file.close();
    var bw = std.io.bufferedWriter(obj_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_tab });
    try ws.write(parsed.value);
}

//
// Jetbrains
//

pub fn generateEditorConfigsIdea(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    try createLaunchersIdea(allocator, project_dir, args, launch_cmds);
    try createProjectIdea(allocator, project_dir, args);
}

pub fn createLaunchersIdea(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
    var tmp_arena = std.heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();
    const tmp_alloc = tmp_arena.allocator();

    var vscode_dir = try project_dir.makeOpenPath(".idea", .{});
    defer vscode_dir.close();

    var run_config_dir = try vscode_dir.makeOpenPath("runConfigurations", .{});
    defer run_config_dir.close();

    for (launch_cmds) |cmd| {
        const cmd_name = try tmp_alloc.dupe(u8, cmd.name);
        _ = std.mem.replace(u8, cmd_name, " ", "_", cmd_name);
        _ = std.mem.replace(u8, cmd_name, "-", "_", cmd_name);
        _ = std.mem.replace(u8, cmd_name, "(", "_", cmd_name);
        _ = std.mem.replace(u8, cmd_name, ")", "_", cmd_name);

        //externals/cetech1/.idea/runConfigurations

        const launcher_path = try std.fmt.allocPrint(tmp_alloc, "{s}.xml", .{cmd_name});

        var obj_file = try run_config_dir.createFile(launcher_path, .{});
        defer obj_file.close();
        var bw = std.io.bufferedWriter(obj_file.writer());
        defer bw.flush() catch undefined;

        const program = try std.fmt.allocPrint(tmp_alloc, "{s}{s}", .{ cmd.program orelse args.bin_path, osBasedProgramExtension() });

        try std.fmt.format(bw.writer(),
            \\<component name="ProjectRunConfigurationManager">
            \\  <configuration default="false" name="{s}" type="ZIGBRAINS_BUILD" factoryName="ZIGBRAINS_BUILD">
            \\    <ZigBrainsOption name="workingDirectory" value="$PROJECT_DIR$" />
            \\    <ZigBrainsArrayOption name="buildSteps">
            \\      <ZigBrainsArrayEntry value="run" />
            \\    </ZigBrainsArrayOption>
        , .{cmd.name});

        if (cmd.args.len != 0) {
            _ = try bw.write("<ZigBrainsArrayOption name=\"compilerArgs\">\n");
            _ = try bw.write("  <ZigBrainsArrayEntry value=\"--\" />\n");
            for (cmd.args) |arg| {
                try std.fmt.format(bw.writer(), "<ZigBrainsArrayEntry value=\"{s}\" />\n", .{arg});
            }
            _ = try bw.write(" </ZigBrainsArrayOption>\n");

            // Debug args
            _ = try bw.write("<ZigBrainsArrayOption name=\"exeArgs\">\n");
            for (cmd.args) |arg| {
                try std.fmt.format(bw.writer(), "<ZigBrainsArrayEntry value=\"{s}\" />\n", .{arg});
            }
            _ = try bw.write(" </ZigBrainsArrayOption>\n");
        }

        try std.fmt.format(bw.writer(),
            \\    <ZigBrainsOption name="colored" value="true" />
            \\    <ZigBrainsOption name="exePath" value="{s}" />
            \\    <ZigBrainsArrayOption name="exeArgs" />
            \\    <method v="2" />
            \\  </configuration>
            \\</component>
        , .{program});
    }
}

pub fn createProjectIdea(allocator: std.mem.Allocator, project_dir: std.fs.Dir, args: ParseArgsResult) !void {
    var fleet_dir = try project_dir.makeOpenPath(".idea", .{});
    defer fleet_dir.close();

    const base_path = try project_dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);

    // zigbrains.xml
    {
        const zls_path = try genZlsPath(allocator, base_path, args.is_project);
        defer allocator.free(zls_path);

        var obj_file = try fleet_dir.createFile("zigbrains.xml", .{});
        defer obj_file.close();
        var bw = std.io.bufferedWriter(obj_file.writer());
        defer bw.flush() catch undefined;

        try std.fmt.format(bw.writer(),
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<project version="4">
            \\  <component name="ZLSSettings">
            \\    <option name="zlsPath" value="{s}" />
            \\  </component>
            \\</project>
        , .{zls_path});
    }

    // cetech1.iml
    {
        var obj_file = try fleet_dir.createFile("cetech1.iml", .{});
        defer obj_file.close();
        var bw = std.io.bufferedWriter(obj_file.writer());
        defer bw.flush() catch undefined;

        try std.fmt.format(bw.writer(),
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<module type="EMPTY_MODULE" version="4">
            \\  <component name="NewModuleRootManager">
            \\    <content url="file://$MODULE_DIR$" />
            \\    <orderEntry type="inheritedJdk" />
            \\    <orderEntry type="sourceFolder" forTests="false" />
            \\  </component>
            \\</module>
        , .{});
    }

    // modules.xml
    {
        var obj_file = try fleet_dir.createFile("modules.xml", .{});
        defer obj_file.close();
        var bw = std.io.bufferedWriter(obj_file.writer());
        defer bw.flush() catch undefined;

        try std.fmt.format(bw.writer(),
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<project version="4">
            \\  <component name="ProjectModuleManager">
            \\    <modules>
            \\      <module fileurl="file://$PROJECT_DIR$/.idea/cetech1.iml" filepath="$PROJECT_DIR$/.idea/cetech1.iml" />
            \\    </modules>
            \\  </component>
            \\</project>
        , .{});
    }

    // .gitignore
    {
        var obj_file = try fleet_dir.createFile(".gitignore", .{});
        defer obj_file.close();
        var bw = std.io.bufferedWriter(obj_file.writer());
        defer bw.flush() catch undefined;

        try std.fmt.format(bw.writer(),
            \\# Default ignored files
            \\/shelf/
            \\/tools/
            \\/workspace.xml
            \\/zigbrains.xml
            \\/customTargets.xml
            \\/editor.xml
            \\/vcs.xml
            \\/runConfigurations
        , .{});
    }
}
