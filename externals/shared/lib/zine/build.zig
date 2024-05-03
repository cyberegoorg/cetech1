const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .imgui_include = b.option([]const u8, "imgui_include", "Path to imgui"),
    };

    _ = b.addModule("zine", .{
        .root_source_file = b.path("src/zine.zig"),
    });

    var lib: *std.Build.Step.Compile = undefined;
    lib = b.addStaticLibrary(.{
        .name = "zine",
        .target = target,
        .optimize = optimize,
    });

    const cflags = [_][]const u8{};

    // TODO: need for zls
    if (options.imgui_include) |imgui_include| {
        lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ imgui_include, "imgui" }) });
    }

    lib.addCSourceFile(.{ .file = b.path("src/zine.cpp"), .flags = &cflags });
    lib.addCSourceFile(.{ .file = b.path("libs/crude_json.cpp"), .flags = &cflags });
    lib.addCSourceFile(.{ .file = b.path("libs/imgui_canvas.cpp"), .flags = &cflags });
    lib.addCSourceFile(.{ .file = b.path("libs/imgui_node_editor_api.cpp"), .flags = &cflags });
    lib.addCSourceFile(.{ .file = b.path("libs/imgui_node_editor.cpp"), .flags = &cflags });

    lib.linkLibCpp();

    b.installArtifact(lib);
}
