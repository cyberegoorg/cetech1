const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len != 3) fatal("wrong number of arguments {d}", .{args.len});

    const input_file_path = args[1];
    const output_file_path = args[2];

    std.Io.Dir.cwd().copyFile(init.io, input_file_path, std.Io.Dir.cwd(), output_file_path, .{}) catch |err| {
        fatal("unable to copy file '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
