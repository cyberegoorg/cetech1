const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const cetech1_module = b.addModule(
        "cetech1",
        .{
            .root_source_file = .{ .path = "root.zig" },
        },
    );
    cetech1_module.addIncludePath(.{ .path = "includes" });
}
