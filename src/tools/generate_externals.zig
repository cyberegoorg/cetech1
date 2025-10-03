const std = @import("std");

pub const ExternalsItem = struct {
    name: []const u8,
    license: []const u8,
};
pub const ExternalsList = std.ArrayListUnmanaged(ExternalsItem);

pub const ExternalsConfig = struct {
    externals: []const ExternalsItem,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) fatal("wrong number of arguments {d}", .{args.len});

    const output_file_path = args[1];

    var output_file = std.fs.createFileAbsolute(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    var buffer: [1024]u8 = undefined;
    var writer = output_file.writer(&buffer);
    const w = &writer.interface;
    defer w.flush() catch undefined;

    try w.print("# Thanks to all ;)\n\n", .{});

    var it: u32 = 2;
    while (it < args.len) : (it += 1) {
        const config_path = args[it];

        const config_dir_path = std.fs.path.dirname(config_path).?;
        //std.log.info("{s}", .{config_dir_path});

        var config_dir = try std.fs.openDirAbsolute(config_dir_path, .{});
        defer config_dir.close();

        var config_file = try std.fs.openFileAbsolute(config_path, .{});
        defer config_file.close();
        const config_file_size = try config_file.getEndPos();

        var config_file_data = std.ArrayList(u8){};
        defer config_file_data.deinit(allocator);
        try config_file_data.resize(allocator, config_file_size);
        var config_file_data_reader = config_file.reader(&.{});
        try config_file_data_reader.interface.readSliceAll(config_file_data.items);
        try config_file_data.append(allocator, 0);

        const config = try std.zon.parse.fromSlice(
            ExternalsConfig,
            allocator,
            config_file_data.items[0..config_file_size :0],
            null,
            .{},
        );
        defer std.zon.parse.free(allocator, config);

        for (config.externals) |external| {
            // std.log.info("{s}", .{external.license});

            var f = try config_dir.openFile(external.license, .{});
            defer f.close();

            try w.print("## {s}\n\n", .{external.name});

            var reader = f.reader(&.{});
            _ = try w.sendFileAll(&reader, .unlimited);

            try w.print("\n", .{});
        }
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
