const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allcator = gpa.allocator();

    const args = try std.process.argsAlloc(allcator);
    defer std.process.argsFree(allcator, args);

    if (args.len != 3) fatal("wrong number of arguments {d}", .{args.len});

    const output_file_path = args[1];
    const modules_args = args[2];

    var modules_it = std.mem.splitSequence(u8, modules_args, ",");
    var modules = std.ArrayList([]const u8).init(allcator);
    defer modules.deinit();
    while (modules_it.next()) |m| {
        modules.append(m) catch |err| {
            fatal("unable populate modules to memory {s}", .{@errorName(err)});
        };
    }

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    var w = output_file.writer();

    try w.print("// GENERATED - DO NOT EDIT\n", .{});
    try w.print("const cetech1 = @import(\"cetech1.zig\");\n\n", .{});

    for (modules.items) |m| {
        try w.print("extern fn ct_load_module_{s}(?*const cetech1.apidb.ct_apidb_api_t, ?*const cetech1.apidb.ct_allocator_t, u8, u8) callconv(.C) u8;\n", .{m});
    }

    try w.print("\npub const descs = [_]cetech1.modules.ct_module_desc_t{{\n", .{});

    for (modules.items) |m| {
        try w.print("    .{{ .name = \"{s}\", .module_fce = ct_load_module_{s} }},\n", .{ m, m });
    }

    try w.print("}};\n", .{});
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
