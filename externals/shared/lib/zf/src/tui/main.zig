const std = @import("std");
const builtin = @import("builtin");

const vaxis = @import("vaxis");

const input = @import("input.zig");
const opts = @import("opts.zig");
const ui = @import("ui.zig");

const ArrayList = std.ArrayList;
const Haystack = input.Haystack;
const Color = ui.Color;

pub const std_options: std.Options = .{
    .log_level = if (builtin.is_test) .debug else .err,
};

const eql = std.mem.eql;

pub const panic = vaxis.panic_handler;

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var stdout_file: std.Io.File = .stdout();
    var stderr_file: std.Io.File = .stderr();

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    var stdout_writer = stdout_file.writer(io, &stdout_buf);
    var stderr_writer = stderr_file.writer(io, &stderr_buf);

    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(allocator);
    var config = opts.parse(allocator, args, stderr);

    // read all lines or exit on out of memory
    const buf = blk: {
        var stdin_file: std.Io.File = .stdin();
        var stdin_buf: [1024]u8 = undefined;
        var stdin_reader = stdin_file.reader(io, &stdin_buf);
        const stdin = &stdin_reader.interface;

        const buf = try stdin.allocRemaining(allocator, .unlimited);

        break :blk std.mem.trim(u8, buf, "\n");
    };

    // escape specific delimiters
    const delimiter = blk: {
        if (eql(u8, config.delimiter, "\\n")) {
            break :blk '\n';
        } else if (eql(u8, config.delimiter, "\\0")) {
            break :blk 0;
        } else {
            break :blk config.delimiter[0];
        }
    };

    const haystacks = try input.collectHaystacks(allocator, buf, delimiter);
    if (haystacks.len == 0) std.process.exit(1);

    defer stdout.flush() catch unreachable;
    if (config.filter) |query| {
        // Use the heap here rather than an array on the stack. Testing showed that this is actually
        // faster, likely due to locality with other heap-alloced data used in the algorithm.
        const needles_buf = try allocator.alloc([]const u8, 16);
        const needles = ui.splitQuery(needles_buf, query);
        const case_sensitive = ui.hasUpper(query);
        const filtered_buf = try allocator.alloc(Haystack, haystacks.len);
        const filtered = input.rankAndSort(filtered_buf, haystacks, needles, config.keep_order, config.plain, case_sensitive);
        if (filtered.len == 0) std.process.exit(1);
        for (filtered) |h| {
            try stdout.print("{s}\n", .{h.str});
        }
    } else {
        config.prompt = init.environ_map.get("ZF_PROMPT") orelse "> ";
        config.vi_mode = if (init.environ_map.get("ZF_VI_MODE")) |value| blk: {
            break :blk value.len > 0;
        } else false;

        {
            const no_color = if (init.environ_map.get("NO_COLOR")) |value| blk: {
                break :blk value.len > 0;
            } else false;

            const highlight_color: Color = if (init.environ_map.get("ZF_HIGHLIGHT")) |value| blk: {
                break :blk std.meta.stringToEnum(Color, value) orelse .cyan;
            } else .cyan;

            config.highlight = if (no_color) null else highlight_color;
        }

        var tui_buf: [1024]u8 = undefined;
        var state = try ui.State.init(io, allocator, init.environ_map, &tui_buf, config);
        const selected = try state.run(io, haystacks);

        if (selected) |selected_lines| {
            for (selected_lines) |str| {
                try stdout.print("{s}\n", .{str});
            }
        } else std.process.exit(1);
    }
}

test {
    _ = @import("array_toggle_set.zig");
    _ = @import("EditBuffer.zig");
    _ = @import("input.zig");
    _ = @import("opts.zig");
    _ = @import("ui.zig");
    _ = @import("Previewer.zig");
}
