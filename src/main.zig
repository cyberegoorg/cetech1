const std = @import("std");
const builtin = @import("builtin");

const kernel = @import("kernel");
const kernel_options = @import("kernel_options");

pub const std_options = std.Options{
    .logFn = kernel.log.zigLogFn,
};

pub fn main() anyerror!u8 {
    const descs = kernel.static_module.descs;
    try kernel.kernel.boot(
        &descs,
        .{
            .ignored_modules = kernel_options.ignored_modules,
            .ignored_modules_prefix = kernel_options.ignored_modules_prefix,
        },
    );
    return 0;
}
