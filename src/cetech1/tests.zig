const std = @import("std");
test {
    _ = std.testing.refAllDecls(@import("core/cetech1.zig"));

    _ = std.testing.refAllDecls(@import("core/private/modules.zig"));
    _ = std.testing.refAllDecls(@import("core/private/kernel.zig"));
    _ = std.testing.refAllDecls(@import("core/private/cdb.zig"));
    _ = std.testing.refAllDecls(@import("core/private/uuid.zig"));

    _ = std.testing.refAllDecls(@import("core/private/apidb_test.zig"));
    _ = std.testing.refAllDecls(@import("core/private/cdb_test.zig"));
    _ = std.testing.refAllDecls(@import("core/private/assetdb_test.zig"));
}
