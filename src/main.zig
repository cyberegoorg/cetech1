const std = @import("std");
const builtin = @import("builtin");

const cetech1 = @import("cetech1");
const static_modules = @import("static_modules");
const kernel = @import("kernel.zig");

pub const std_options = struct {
    pub const logFn = @import("log.zig").zigLogFn;
};

const cetech1_options = @import("cetech1_options");

pub fn main() anyerror!u8 {
    var descs = if (!cetech1_options.static_modules) [_]cetech1.modules.ct_module_desc_t{} else static_modules.descs;
    try kernel.boot(&descs, descs.len, .{});
    return 0;
}
