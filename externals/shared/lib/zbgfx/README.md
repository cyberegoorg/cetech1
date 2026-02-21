# ZBgfx

[![GitHub Actions](https://github.com/cyberegoorg/zbgfx/actions/workflows/test.yaml/badge.svg)](https://github.com/cyberegoorg/zbgfx/actions/workflows/test.yaml)

When [zig](https://codeberg.org/ziglang/zig) meets [bgfx](https://github.com/bkaradzic/bgfx).

## Features

- [x] Zig api.
- [x] Compile as standard zig library.
- [x] `shaderc` as build artifact.
- [x] Shader compile from runtime via `shaderc` as child process.
- [x] Binding for [DebugDraw API](https://github.com/bkaradzic/bgfx/tree/master/examples/common/debugdraw)
- [x] `imgui` render backend. Use build option `imgui_include` to enable. ex. for
  zgui: `.imgui_include = zgui.path("libs").getPath(b),`
- [ ] Shader compile in `build.zig` and embed as zig module.
- [ ] Zig based allocator.

> [!IMPORTANT]
>
> - This is only zig binding. For BGFX stuff goto [bgfx](https://github.com/bkaradzic/bgfx).
> - Github repository is only mirror. Development continues [here](https://codeberg.org/cyberegoorg/zbgfx)

> [!WARNING]
>
> - `shaderc` need some time to compile.

> [!NOTE]
>
> - If you build shaders/app and see something like `run shaderc (shader.bin.h) stderr`.
    This is not "true" error (build success), but only in debug build shader print some stuff to stderr and zig
    build catch it.

## License

Folders `libs`, `shaders` is copy&paste from [bgfx](https://github.com/bkaradzic/bgfx) for more sell-contained
experience and is licensed by [LICENSEE](https://github.com/bkaradzic/bgfx/blob/master/LICENSE)

Zig binding is licensed by [WTFPL](LICENSE)

## Zig version

Minimal is `0.15.1`. But you know try your version and believe.

## Bgfx version

- [BX](https://github.com/bkaradzic/bx//compare/fa641d8581f7f6f696a37abe4b80558aca161440...master)
- [BImg](https://github.com/bkaradzic/bimg/compare/b43fea9eae0e6a98118454a6d17c6cb25f5e6403...master)
- [BGFX](https://github.com/bkaradzic/bgfx/compare/ccdbacdb74428600e791bc6b1cd0c0c149c3637e...master)

## Getting started

Copy `zbgfx` to a subdirectory of your project and then add the following to your `build.zig.zon` .dependencies:

```zig
    .zbgfx = .{ .path = "path/to/zbgfx" },
```

or use `zig fetch --save ...` way.

Then in your `build.zig` add:

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{ ... });

    const zbgfx = b.dependency("zbgfx", .{});
    exe.root_module.addImport("zbgfx", zbgfx.module("zbgfx"));
    exe.linkLibrary(zbgfx.artifact("bgfx"));

    // This install shaderc to install dir
    // For shader build in build =D check examples
    // b.installArtifact(zbgfx.artifact("shaderc"));
}
```

## Usage

See examples for binding usage and [bgfx](https://github.com/bkaradzic/bgfx) for bgfx stuff.

## Build options

| Build option    | Default | Description                                          |
|-----------------|---------|------------------------------------------------------|
| `imgui_include` | `null`  | Path to ImGui includes (need for imgui bgfx backend) |
| `multithread`   | `true`  | Compile with `BGFX_CONFIG_MULTITHREADED`             |
| `with_shaderc`  | `true`  | Compile with `shaderc`                               |

## Examples

Run this for build all examples:

```sh
cd examples
zig build
```

### [00-Minimal](examples/00-minimal/)

Minimal setup with GLFW for window and input.

```sh
examples/zig-out/bin/00-minimal
```

| Key | Description  |
|-----|--------------|
| `v` | Vsync on/off |
| `d` | Debug on/off |

### [01-ZGui](examples/01-zgui/)

Minimal setup for zgui/ImGui.

```sh
examples/zig-out/bin/01-zgui
```

| Key | Description  |
|-----|--------------|
| `v` | Vsync on/off |
| `d` | Debug on/off |

### [02-Runtime shaderc](examples/02-runtime-shaderc/)

Basic usage of shader compile in runtime.
Try edit shaders in `zig-out/bin/shaders` and hit `r` to recompile.

```sh
examples/zig-out/bin/02-runtime-shaderc
```

| Key | Description                 |
|-----|-----------------------------|
| `v` | Vsync on/off                |
| `d` | Debug on/off                |
| `r` | Recompile shaders form file |

### [03-debugdraw](examples/03-debugdraw/)

DebugDraw api usage example.

```sh
examples/zig-out/bin/03-debugdraw
```

| Key | Description  |
|-----|--------------|
| `v` | Vsync on/off |
| `d` | Debug on/off |
