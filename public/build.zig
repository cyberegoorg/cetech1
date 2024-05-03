const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {

    //
    // OPTIONS
    //

    const options = .{
        // Tracy options
        .enable_tracy = b.option(bool, "with_tracy", "build with tracy.") orelse true,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zmath = b.dependency(
        "zmath",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    const ziglangSet = b.dependency("ziglangSet", .{
        .target = target,
        .optimize = optimize,
    });

    const cetech1_module = b.addModule(
        "cetech1",
        .{
            .root_source_file = b.path("src/root.zig"),
        },
    );
    cetech1_module.addIncludePath(b.path("includes"));
    cetech1_module.addImport("zmath", zmath.module("root"));
    cetech1_module.addImport("ziglangSet", ziglangSet.module("ziglangSet"));

    cetech1_module.addImport("cetech1_options", options_module);
}
