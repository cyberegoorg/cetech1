const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allcator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const output_file_path = args[1];

    var shared_modules = std.ArrayListUnmanaged([]const u8).empty;
    defer shared_modules.deinit(allcator);

    var studio_modules = std.ArrayListUnmanaged([]const u8).empty;
    defer studio_modules.deinit(allcator);

    var it: u32 = 2;
    while (it < args.len) : (it += 2) {
        const arg_name = args[it];
        const arg_arg = args[it + 1];

        var modules_it = std.mem.splitSequence(u8, arg_arg, ",");

        if (std.mem.eql(u8, arg_name, "--shared")) {
            while (modules_it.next()) |m| {
                shared_modules.append(allcator, m) catch |err| {
                    fatal("unable populate modules to memory {s}", .{@errorName(err)});
                };
            }
        } else if (std.mem.eql(u8, arg_name, "--studio")) {
            while (modules_it.next()) |m| {
                studio_modules.append(allcator, m) catch |err| {
                    fatal("unable populate modules to memory {s}", .{@errorName(err)});
                };
            }
        }
    }

    var output_file = std.Io.Dir.cwd().createFile(init.io, output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close(init.io);

    var stdout_buffer: [4096]u8 = undefined;
    var bw = output_file.writer(init.io, &stdout_buffer);
    defer bw.interface.flush() catch undefined;
    var w = &bw.interface;

    try w.print("// GENERATED - DO NOT EDIT\n", .{});
    try w.print("const cetech1 = @import(\"cetech1\");\n\n", .{});
    try w.print("const std = @import(\"std\");\n\n", .{});

    // shared modules.
    try w.print("\npub const shared = [_]cetech1.modules.ModuleDesc{{\n", .{});
    for (shared_modules.items) |m| {
        if (m.len == 0) continue;
        try w.print("    .{{ .name = \"{s}\", .module_fce = .{{ .zig_fce = @import(\"{s}_private\").load_module_zig }} }},\n", .{ m, m });
    }
    try w.print("}};\n", .{});

    // studio modules.
    try w.print("\npub const studio = [_]cetech1.modules.ModuleDesc{{\n", .{});
    for (studio_modules.items) |m| {
        if (m.len == 0) continue;
        try w.print("    .{{ .name = \"{s}\", .module_fce = .{{ .zig_fce = @import(\"{s}_private\").load_module_zig }} }},\n", .{ m, m });
    }
    try w.print("}};\n", .{});
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
