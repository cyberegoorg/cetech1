const std = @import("std");
test {
    _ = std.testing.refAllDecls(@import("core/private/apidb.zig"));
    _ = std.testing.refAllDecls(@import("core/private/modules.zig"));
    _ = std.testing.refAllDecls(@import("core/private/kernel.zig"));
    _ = std.testing.refAllDecls(@import("core/cetech1.zig"));
}
