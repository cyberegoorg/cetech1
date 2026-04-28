const std = @import("std");
const builtin = @import("builtin");

pub const EditorType = enum {
    NVim,
    VSCode,
    IDEA,
};

const LaunchCmdProgram = union(enum) {
    runner: void,
    studio: void,
    path: []const u8,
};

pub const LaunchCmd = struct {
    name: []const u8,
    program: LaunchCmdProgram = .studio,
    args: []const []const u8,
    //cwd: []const u8,
};

pub const TaskCmd = struct {
    name: []const u8,
    type: []const u8,
    command: []const u8,
    args: []const []const u8,
};
pub const CmdList = std.ArrayListUnmanaged(LaunchCmd);
pub const TaskList = std.ArrayListUnmanaged(TaskCmd);

pub const LaunchConfig = struct {
    tasks: []const TaskCmd = &.{},
    launchers: []const LaunchCmd = &.{},
};

pub fn osBasedProgramExtension() []const u8 {
    return if (builtin.target.os.tag == .windows) ".exe" else "";
}

pub fn osBasedZigDir() []const u8 {
    return comptime builtin.target.osArchName() ++ "-" ++ @tagName(builtin.target.os.tag);
}

pub fn genLddbScriptPath(allocator: std.mem.Allocator, base_path: []const u8, is_project: bool) ![]u8 {
    return if (is_project)
        try std.fs.path.join(allocator, &.{ base_path, "externals", "cetech1", "lldb_pretty_printers.py" })
    else
        try std.fs.path.join(allocator, &.{ base_path, "lldb_pretty_printers.py" });
}

pub fn generateEditorConfigs(
    io: std.Io,
    allocator: std.mem.Allocator,
    editor_type: EditorType,
    project_dir: std.Io.Dir,
    args: ParseArgsResult,
    launch_cmds: []const LaunchCmd,
    task_cmds: []const TaskCmd,
) !void {
    switch (editor_type) {
        .NVim => try NVim.generateEditorConfigs(io, allocator, project_dir, args, launch_cmds, task_cmds),
        .IDEA => try IDEA.generateEditorConfigs(io, allocator, project_dir, args, launch_cmds, task_cmds),
        .VSCode => try VSCode.generateEditorConfigs(io, allocator, project_dir, args, launch_cmds, task_cmds),
    }
}

pub fn createLauchCmdForFixtures(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) ![]LaunchCmd {
    var cmd_list = CmdList.empty;

    var dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var iterator = dir.iterate();
    while (try iterator.next(io)) |path| {
        if (path.kind != .directory) continue;

        const basename = std.fs.path.basename(path.name);

        try cmd_list.append(allocator, .{
            .program = .studio,
            .name = try std.fmt.allocPrint(allocator, "{s} - Studio", .{basename}),
            .args = try allocator.dupe([]const u8, &.{
                "--asset-root",
                try std.fmt.allocPrint(allocator, "fixtures/{s}/", .{basename}),
            }),
        });

        try cmd_list.append(allocator, .{
            .program = .runner,
            .name = try std.fmt.allocPrint(allocator, "{s} - Runner", .{basename}),
            .args = try allocator.dupe([]const u8, &.{
                "--asset-root",
                try std.fmt.allocPrint(allocator, "fixtures/{s}/", .{basename}),
            }),
        });
    }
    return cmd_list.toOwnedSlice(allocator);
}

const ParseArgsResult = struct {
    gen_type: EditorType = .VSCode,
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

fn parseArgs(allocator: std.mem.Allocator, init: std.process.Init) !ParseArgsResult {
    var result: ParseArgsResult = .{};
    errdefer result.deinit(allocator);

    var args_it = try init.minimal.args.iterateAllocator(allocator);
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
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const arguments = try parseArgs(allocator, init);
    defer arguments.deinit(allocator);

    var project_dir = try std.Io.Dir.openDirAbsolute(init.io, arguments.project_path, .{});
    defer project_dir.close(init.io);

    var cmd_list = CmdList.empty;
    defer cmd_list.deinit(allocator);

    var config_file = try std.Io.Dir.openFileAbsolute(init.io, arguments.config, .{});
    defer config_file.close(init.io);
    const config_file_size = try config_file.length(init.io);

    var config_file_data = std.ArrayList(u8).empty;
    defer config_file_data.deinit(allocator);
    try config_file_data.resize(allocator, config_file_size);
    var config_file_data_reader = config_file.reader(init.io, &.{});
    try config_file_data_reader.interface.readSliceAll(config_file_data.items);
    try config_file_data.append(allocator, 0);

    const config = try std.zon.parse.fromSliceAlloc(
        LaunchConfig,
        allocator,
        config_file_data.items[0..config_file_size :0],
        null,
        .{},
    );
    defer std.zon.parse.free(allocator, config);

    for (config.launchers) |launcher| {
        // std.log.debug("{any}", .{launcher});
        try cmd_list.append(allocator, launcher);
    }

    var tmp_arena = std.heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();

    if (arguments.fixtures_path) |fixtures_path| {
        const fixtures_cmds = try createLauchCmdForFixtures(init.io, tmp_arena.allocator(), fixtures_path);
        try cmd_list.appendSlice(allocator, fixtures_cmds);
    }

    try generateEditorConfigs(init.io, allocator, arguments.gen_type, project_dir, arguments, cmd_list.items, config.tasks);
}

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

//
// NVim
//

const NVim = struct {
    pub fn generateEditorConfigs(
        io: std.Io,
        allocator: std.mem.Allocator,
        project_dir: std.Io.Dir,
        args: ParseArgsResult,
        launch_cmds: []const LaunchCmd,
        task_cmds: []const TaskCmd,
    ) !void {
        try VSCode.createOrUpdateSettingsJson(io, allocator, project_dir, args);
        try VSCode.createLaunchers(io, allocator, project_dir, args, launch_cmds, "codelldb");
        try VSCode.createTasks(io, allocator, project_dir, args, task_cmds);
    }
};

//
// VSCode
//
pub fn osBasedTypeVScode() []const u8 {
    return if (builtin.target.os.tag == .windows) "cppvsdbg" else "lldb";
}

pub const VSCodeLaunchCmd = struct {
    type: []const u8,
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

pub const VSCodeTaskCmd = struct {
    label: []const u8,
    type: []const u8,
    command: []const u8,
    args: []const []const u8,
};

pub const VSCodeTaskConfig = struct {
    version: []const u8 = "2.0.0",
    tasks: []const VSCodeTaskCmd,
};
pub const VSCodeCmdList = std.ArrayListUnmanaged(VSCodeLaunchCmd);
pub const VSCodeTaskList = std.ArrayListUnmanaged(VSCodeTaskCmd);

const VSCode = struct {
    pub fn generateEditorConfigs(
        io: std.Io,
        allocator: std.mem.Allocator,
        project_dir: std.Io.Dir,
        args: ParseArgsResult,
        launch_cmds: []const LaunchCmd,
        task_cmds: []const TaskCmd,
    ) !void {
        try VSCode.createOrUpdateSettingsJson(io, allocator, project_dir, args);
        try VSCode.createLaunchers(io, allocator, project_dir, args, launch_cmds, osBasedTypeVScode());
        try VSCode.createTasks(io, allocator, project_dir, args, task_cmds);
    }

    pub fn createLaunchers(io: std.Io, allocator: std.mem.Allocator, project_dir: std.Io.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd, cmd_type: []const u8) !void {
        var cmd_list = VSCodeCmdList.empty;
        defer cmd_list.deinit(allocator);

        var tmp_arena = std.heap.ArenaAllocator.init(allocator);
        defer tmp_arena.deinit();
        const tmp_alloc = tmp_arena.allocator();

        for (launch_cmds) |cmd| {
            const program = switch (cmd.program) {
                .path => |p| p,
                .studio => try std.fmt.allocPrint(tmp_alloc, "{s}_studio{s}", .{ args.bin_path, osBasedProgramExtension() }),
                .runner => try std.fmt.allocPrint(tmp_alloc, "{s}{s}", .{ args.bin_path, osBasedProgramExtension() }),
            };

            try cmd_list.append(allocator, .{
                .type = cmd_type,
                .name = cmd.name,
                .program = program,
                .args = cmd.args,
                .cwd = "${workspaceFolder}",
            });
        }

        var vscode_dir = try project_dir.createDirPathOpen(io, ".vscode", .{});
        defer vscode_dir.close(io);

        var obj_file = try vscode_dir.createFile(io, "launch.json", .{});
        defer obj_file.close(io);

        var buffer: [4096]u8 = undefined;

        var bw = obj_file.writer(io, &buffer);
        defer bw.interface.flush() catch undefined;

        var ws = std.json.Stringify{ .writer = &bw.interface, .options = .{ .whitespace = .indent_tab } };
        try ws.write(VSCodeLaunchConfig{ .configurations = cmd_list.items });
    }

    pub fn createTasks(io: std.Io, allocator: std.mem.Allocator, project_dir: std.Io.Dir, args: ParseArgsResult, task_cmds: []const TaskCmd) !void {
        _ = args;

        var task_list = VSCodeTaskList.empty;
        defer task_list.deinit(allocator);

        for (task_cmds) |cmd| {
            try task_list.append(allocator, .{
                .type = cmd.type,
                .label = cmd.name,
                .command = cmd.command,
                .args = cmd.args,
            });
        }

        var vscode_dir = try project_dir.createDirPathOpen(io, ".vscode", .{});
        defer vscode_dir.close(io);

        var obj_file = try vscode_dir.createFile(io, "tasks.json", .{});
        defer obj_file.close(io);

        var buffer: [4096]u8 = undefined;

        var bw = obj_file.writer(io, &buffer);
        defer bw.interface.flush() catch undefined;

        var ws = std.json.Stringify{ .writer = &bw.interface, .options = .{ .whitespace = .indent_tab } };
        try ws.write(VSCodeTaskConfig{ .tasks = task_list.items });
    }
    pub fn createOrUpdateSettingsJson(io: std.Io, allocator: std.mem.Allocator, project_dir: std.Io.Dir, args: ParseArgsResult) !void {
        var vscode_dir = try project_dir.createDirPathOpen(io, ".vscode", .{});
        defer vscode_dir.close(io);

        var buffer: [4096]u8 = undefined;

        // Read or create
        var parsed = blk: {
            var obj_file = vscode_dir.openFile(io, "settings.json", .{ .mode = .read_only }) catch |err| {
                if (err == error.FileNotFound) {
                    break :blk try std.json.parseFromSlice(std.json.Value, allocator, "{}", .{});
                }
                return err;
            };
            defer obj_file.close(io);

            var rb = obj_file.reader(io, &buffer);
            var json_reader = std.json.Reader.init(allocator, &rb.interface);
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
            try parsed.value.object.put(parsed.arena.allocator(), "todo-tree.filtering.excludeGlobs", args_array);
        }

        // files.associations
        {
            var files_map = std.json.Value{ .object = try std.json.ObjectMap.init(parsed.arena.allocator(), &.{}, &.{}) };
            try files_map.object.put(parsed.arena.allocator(), "*.sc", std.json.Value{ .string = "glsl" });
            try files_map.object.put(parsed.arena.allocator(), "bgfx_*.sh", std.json.Value{ .string = "glsl" });
            try files_map.object.put(parsed.arena.allocator(), "shaderlib.sh", std.json.Value{ .string = "glsl" });

            try parsed.value.object.put(parsed.arena.allocator(), "files.associations", files_map);
        }

        const base_path = try project_dir.realPathFileAlloc(io, ".", allocator);
        defer allocator.free(base_path);

        // // Zig
        // const zig_path = try std.fs.path.join(allocator, &.{ base_path, "zig", "bin", osBasedZigDir(), "zig") });
        // defer allocator.free(zig_path);
        // try parsed.value.object.put("zig.path", .{ .string = zig_path });

        // LLDB
        const lldb_script_path = try genLddbScriptPath(allocator, base_path, args.is_project);
        defer allocator.free(lldb_script_path);
        const cmd_script = try std.fmt.allocPrint(allocator, "command script import {s}", .{lldb_script_path});
        defer allocator.free(cmd_script);

        // lldb.launch.initCommands
        {
            var array = std.json.Value{ .array = std.json.Array.init(parsed.arena.allocator()) };
            try array.array.append(std.json.Value{ .string = cmd_script });
            try array.array.append(std.json.Value{ .string = "type category enable zig.lang" });
            try array.array.append(std.json.Value{ .string = "type category enable zig.std" });

            try parsed.value.object.put(parsed.arena.allocator(), "lldb.launch.initCommands", array);
        }

        // Write back
        var obj_file = try vscode_dir.createFile(io, "settings.json", .{});
        defer obj_file.close(io);
        var bw = obj_file.writer(io, &buffer);
        defer bw.interface.flush() catch undefined;

        // writeStream(writer, .{ .whitespace = .indent_tab });
        var ws = std.json.Stringify{ .writer = &bw.interface, .options = .{ .whitespace = .indent_tab } };
        try ws.write(parsed.value);
    }
};

//
// Jetbrains
//

const IDEA = struct {
    pub fn generateEditorConfigs(
        io: std.Io,
        allocator: std.mem.Allocator,
        project_dir: std.Io.Dir,
        args: ParseArgsResult,
        launch_cmds: []const LaunchCmd,
        task_cmds: []const TaskCmd,
    ) !void {
        _ = task_cmds;
        try IDEA.createLaunchers(io, allocator, project_dir, args, launch_cmds);
        try IDEA.createProject(io, allocator, project_dir, args);
    }

    pub fn createLaunchers(io: std.Io, allocator: std.mem.Allocator, project_dir: std.Io.Dir, args: ParseArgsResult, launch_cmds: []const LaunchCmd) !void {
        var tmp_arena = std.heap.ArenaAllocator.init(allocator);
        defer tmp_arena.deinit();
        const tmp_alloc = tmp_arena.allocator();

        var vscode_dir = try project_dir.createDirPathOpen(io, ".idea", .{});
        defer vscode_dir.close(io);

        var run_config_dir = try vscode_dir.createDirPathOpen(io, "runConfigurations", .{});
        defer run_config_dir.close(io);

        var buffer: [4096]u8 = undefined;

        for (launch_cmds) |cmd| {
            const cmd_name = try tmp_alloc.dupe(u8, cmd.name);
            _ = std.mem.replace(u8, cmd_name, " ", "_", cmd_name);
            _ = std.mem.replace(u8, cmd_name, "-", "_", cmd_name);
            _ = std.mem.replace(u8, cmd_name, "(", "_", cmd_name);
            _ = std.mem.replace(u8, cmd_name, ")", "_", cmd_name);

            //externals/cetech1/.idea/runConfigurations

            const launcher_path = try std.fmt.allocPrint(tmp_alloc, "{s}.xml", .{cmd_name});

            var obj_file = try run_config_dir.createFile(io, launcher_path, .{});
            defer obj_file.close(io);

            var bw = obj_file.writer(io, &buffer);
            defer bw.interface.flush() catch undefined;

            const program = switch (cmd.program) {
                .path => |p| p,
                .studio => try std.fmt.allocPrint(tmp_alloc, "{s}_studio{s}", .{ args.bin_path, osBasedProgramExtension() }),
                .runner => try std.fmt.allocPrint(tmp_alloc, "{s}{s}", .{ args.bin_path, osBasedProgramExtension() }),
            };

            try bw.interface.print(
                \\<component name="ProjectRunConfigurationManager">
                \\  <configuration default="false" name="{s}" type="ZIGBRAINS_BUILD" factoryName="ZIGBRAINS_BUILD">
                \\    <ZigBrainsOption name="workingDirectory" value="$PROJECT_DIR$" />
                \\    <ZigBrainsArrayOption name="buildSteps">
                \\      <ZigBrainsArrayEntry value="run" />
                \\    </ZigBrainsArrayOption>
            , .{cmd.name});

            if (cmd.args.len != 0) {
                _ = try bw.interface.write("<ZigBrainsArrayOption name=\"compilerArgs\">\n");
                _ = try bw.interface.write("  <ZigBrainsArrayEntry value=\"--\" />\n");
                for (cmd.args) |arg| {
                    try bw.interface.print("<ZigBrainsArrayEntry value=\"{s}\" />\n", .{arg});
                }
                _ = try bw.interface.write(" </ZigBrainsArrayOption>\n");

                // Debug args
                _ = try bw.interface.write("<ZigBrainsArrayOption name=\"exeArgs\">\n");
                for (cmd.args) |arg| {
                    try bw.interface.print("<ZigBrainsArrayEntry value=\"{s}\" />\n", .{arg});
                }
                _ = try bw.interface.write(" </ZigBrainsArrayOption>\n");
            }

            try bw.interface.print(
                \\    <ZigBrainsOption name="colored" value="true" />
                \\    <ZigBrainsOption name="exePath" value="{s}" />
                \\    <ZigBrainsArrayOption name="exeArgs" />
                \\    <method v="2" />
                \\  </configuration>
                \\</component>
            , .{program});
        }
    }

    pub fn createProject(io: std.Io, allocator: std.mem.Allocator, project_dir: std.Io.Dir, args: ParseArgsResult) !void {
        _ = args;
        var idea_dir = try project_dir.createDirPathOpen(io, ".idea", .{});
        defer idea_dir.close(io);

        const base_path = try project_dir.realPathFileAlloc(io, ".", allocator);
        defer allocator.free(base_path);

        var buffer: [4096]u8 = undefined;

        // cetech1.iml
        {
            var obj_file = try idea_dir.createFile(io, "cetech1.iml", .{});
            defer obj_file.close(io);
            var bw = obj_file.writer(io, &buffer);
            defer bw.interface.flush() catch undefined;

            try bw.interface.print(
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
            var obj_file = try idea_dir.createFile(io, "modules.xml", .{});
            defer obj_file.close(io);
            var bw = obj_file.writer(io, &buffer);
            defer bw.interface.flush() catch undefined;

            try bw.interface.print(
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
            var obj_file = try idea_dir.createFile(io, ".gitignore", .{});
            defer obj_file.close(io);
            var bw = obj_file.writer(io, &buffer);
            defer bw.interface.flush() catch undefined;

            try bw.interface.print(
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
};
