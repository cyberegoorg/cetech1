const std = @import("std");

test {
    _ = std.testing.refAllDecls(@import("cetech1"));
    _ = std.testing.refAllDeclsRecursive(@import("private.zig"));
}
