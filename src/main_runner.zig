const std = @import("std");
const builtin = @import("builtin");

const kernel = @import("kernel");
const modules = @import("static_modules");

pub const std_options = std.Options{
    .logFn = kernel.log.zigLogFn,
};

pub fn main(init: std.process.Init) !void {
    try kernel.kernel.bootRunner(init, &(modules.shared));
}
