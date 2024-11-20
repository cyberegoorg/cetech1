const std = @import("std");
const builtin = @import("builtin");

const kernel = @import("kernel");
const cetech1_options = kernel.cetech1_options;

pub const std_options = std.Options{
    .logFn = kernel.log.zigLogFn,
};

pub fn main() anyerror!u8 {
    const descs = if (!cetech1_options.static_modules) .{} else kernel.static_module.descs;
    try kernel.kernel.boot(&descs, .{});
    return 0;
}
