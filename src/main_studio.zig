const std = @import("std");
const builtin = @import("builtin");

const kernel = @import("kernel");
const kernel_options = @import("kernel_options");

pub const std_options = std.Options{
    .logFn = kernel.log.zigLogFn,
};

pub fn main(init: std.process.Init) !void {
    try kernel.kernel.bootStudio(
        init,
        &.{},
    );
}
