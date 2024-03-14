const std = @import("std");

test {
    _ = std.testing.refAllDecls(@import("cetech1.zig"));
    _ = std.testing.refAllDeclsRecursive(@import("private/private.zig"));
}
