const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allcator = gpa.allocator();

    const args = try std.process.argsAlloc(allcator);
    defer std.process.argsFree(allcator, args);

    if (args.len < 4) fatal("wrong number of arguments {d}", .{args.len});

    const output_file_path = args[1];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    // var bw = std.io.bufferedWriter(output_file.writer());
    // defer bw.flush() catch undefined;

    const w = output_file.writer();

    try w.print("# Thanks to all ;)\n\n", .{});

    var it: u32 = 2;
    while (it < args.len) : (it += 2) {
        const external_name = args[it];
        const path = args[it + 1];

        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();

        try w.print("## {s}\n\n", .{external_name});

        try output_file.writeFileAll(f, .{});

        try w.print("\n", .{});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
