const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allcator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len != 3) fatal("wrong number of arguments {d}", .{args.len});

    const output_file_path = args[1];
    const modules_args = args[2];

    var modules_it = std.mem.splitSequence(u8, modules_args, ",");
    var modules = std.ArrayListUnmanaged([]const u8).empty;
    defer modules.deinit(allcator);

    while (modules_it.next()) |m| {
        modules.append(allcator, m) catch |err| {
            fatal("unable populate modules to memory {s}", .{@errorName(err)});
        };
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

    for (modules.items) |m| {
        if (m.len == 0) continue;
        try w.print("extern fn ct_load_module_{s}(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool;\n", .{m});
    }

    try w.print("\npub const descs = [_]cetech1.modules.ModuleDesc{{\n", .{});

    for (modules.items) |m| {
        if (m.len == 0) continue;
        try w.print("    .{{ .name = \"{s}\", .module_fce = .{{ .c_fce = ct_load_module_{s} }} }},\n", .{ m, m });
    }

    try w.print("}};\n", .{});
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
