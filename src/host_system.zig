const std = @import("std");
const builtin = @import("builtin");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const kernel = @import("kernel.zig");

const cetech1 = @import("cetech1");
const cetech1_options = @import("cetech1_options");
const public = cetech1.host;
const input = cetech1.input;

const module_name = .host;

const log = std.log.scoped(module_name);

pub const system_api = public.SystemApi{
    .openIn = openIn,
};

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.SystemApi, &system_api);
}

fn openIn(allocator: std.mem.Allocator, open_type: public.OpenInType, url: []const u8) !void {
    var args = cetech1.ArrayList([]const u8){};
    defer args.deinit(allocator);

    switch (builtin.os.tag) {
        .windows => {
            // use explorer or start
            switch (open_type) {
                .Reveal => {
                    try args.append(allocator, "explorer");
                },
                else => {
                    try args.append(allocator, "start");
                },
            }

            try args.append(allocator, url);
        },
        .macos => {
            try args.append(allocator, "open");

            // Open args
            switch (open_type) {
                .Reveal => try args.append(allocator, "-R"),
                .Edit => try args.append(allocator, "-t"),
                else => {},
            }

            try args.append(allocator, url);
        },
        else => {
            try args.append(allocator, "xdg-open");

            // xdg args
            switch (open_type) {
                .Reveal => try args.append(allocator, std.fs.path.dirname(url).?),
                else => try args.append(allocator, url),
            }
        },
    }

    var child = std.process.Child.init(args.items, allocator);
    _ = try child.spawnAndWait();
}
