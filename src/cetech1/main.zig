const std = @import("std");
const builtin = @import("builtin");

const cetech1 = @import("core/cetech1.zig");
const kernel = @import("core/private/kernel.zig");

pub fn main() anyerror!u8 {
    var descs = [_]cetech1.c.ct_module_desc_t{};
    try kernel.boot(&descs, descs.len);
    return 0;
}
