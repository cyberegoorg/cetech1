const std = @import("std");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) fatal("wrong number of arguments {d}", .{args.len});

    const input_file_path = args[1];
    const output_file_path = args[2];

    std.fs.cwd().copyFile(input_file_path, std.fs.cwd(), output_file_path, .{}) catch |err| {
        fatal("unable to copy file '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
