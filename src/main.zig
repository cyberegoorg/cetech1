const std = @import("std");
const builtin = @import("builtin");

const cetech1 = @import("cetech1");
const static_modules = @import("_static.zig");
const kernel = @import("kernel.zig");

pub const std_options = .{
    .logFn = @import("log.zig").zigLogFn,
};

const cetech1_options = @import("cetech1_options");

pub fn main() anyerror!u8 {
    const descs = if (!cetech1_options.static_modules) .{} else static_modules.descs;
    try kernel.boot(&descs, .{});
    return 0;
}
