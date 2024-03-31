# Getting started

## Supported architectures

> Currently, not all architectures are tested.
> For tested platform check [GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/test.yaml).
> But you can still try to compile/run it on your arch.
> Currently develop on `aarch64-macos`, `x86_64-macos` and `SteamDeck`.
> {style="note"}

| &lt;ARCH&gt;     | Description      |
|------------------|------------------|
| `x86_64-macos`   | Apple Intel      |
| `aarch64-macos`  | Apple Arm        |
| `x86_64-linux`   | Linux, SteamDeck |
| `aarch64-linux`  | Linux ARM        |
| `x86_64-windows` | Windows          |

## Prerequisite

- [Git](https://git-scm.com/downloads)
- [Git-lfs](https://git-lfs.com)
- [curl](https://curl.se/download.html)

## Clone

<tabs>
    <tab title="MacOS/Linux/SteamDeck/Windows">
        <code-block lang="bash" src="getting-started/clone.sh"></code-block>
    </tab>
</tabs>

## Repository structure

| Folder                                                                                                | Description                                                         |
|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| [`Writerside/`](https://github.com/cyberegoorg/cetech1/tree/main/Writerside/)                         | This documentation                                                  |
| [`zig/`](https://github.com/cyberegoorg/cetech1/tree/main/zig/)                                       | Submodule for prebuilt zig                                          |
| [`externals/`](https://github.com/cyberegoorg/cetech1/tree/main/externals/)                           | 3rd-party library and tools                                         |
| [`fixtures/`](https://github.com/cyberegoorg/cetech1/tree/main/fixtures/)                             | Tests fixtures                                                      |
| [`public/`](https://github.com/cyberegoorg/cetech1/tree/main/public/)                                 | Public API for modules                                              |
| [`public/includes/`](https://github.com/cyberegoorg/cetech1/tree/main/public/includes/)               | C api headers                                                       |
| [`src/`](https://github.com/cyberegoorg/cetech1/tree/main/src/)                                       | Main source code folder                                             |
| [`modules/`](https://github.com/cyberegoorg/cetech1/tree/main/modules/)                               | There is all modules that is possible part of engine                |
| [`examples/foo`](https://github.com/cyberegoorg/cetech1/tree/main/examples/foo)                       | Simple `foo` module write in zig                                    |
| [`examples/bar`](https://github.com/cyberegoorg/cetech1/tree/main/examples/bar)                       | Simple `bar` module write in C and use api exported by `foo` module |
| [`examples/editor_foo_tab`](https://github.com/cyberegoorg/cetech1/tree/main/examples/editor_foo_tab) | Show how to crete new editor tab type                               |

## Build

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash" src="getting-started/build.sh"></code-block>
    </tab>
    <tab title="SteamDeck">
        <code-block lang="bash" src="getting-started/build_steamdeck.sh"></code-block>
    </tab>
    <tab title="Windows">
        <code-block lang="bash" src="getting-started/build_windows.sh"></code-block>
    </tab>
</tabs>

> Currently, there is a problem with one library on linux.
> If you see something like `'...libdawn.a' is neither ET_REL nor LLVM bitcode` try build again.
> {style="warning"}

| Args                 | Value             | Default | Description                                                                 |
|----------------------|-------------------|---------|-----------------------------------------------------------------------------|
| `-Ddynamic-modules=` | `true` or `false` | `true`  | Build all modules in dynamic mode.                                          |
| `-Dstatic-modules=`  | `true` or `false` | `false` | Build all modules in static mode.                                           |
| `-Dwith-samples=`    | `true` or `false` | `true`  | Build with sample modules.                                                  |
| `-Dwith-editor=`     | `true` or `false` | `true`  | Build with editor modules.                                                  |
| `-Dwith-tracy=`      | `true` or `false` | `true`  | Build with [tracy](#tracy-profiler) support.                                |
| `-Dwith-nfd=`        | `true` or `false` | `true`  | Build with NFD (native file dialog)                                         |
| `-Dnfd-portal=`      | `true` or `false` | `true`  | Build NFD with xdg-desktop-portal instead of GTK. Linux, nice for SteamDeck |

## Run

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash" src="getting-started/run.sh"></code-block>
    </tab>
    <tab title="SteamDeck">
        <code-block lang="bash" src="getting-started/run_steamdeck.sh"></code-block>
    </tab>
    <tab title="Windows">
        <code-block lang="bash" src="getting-started/run_windows.sh"></code-block>
    </tab>
</tabs>

> Bool arguments does not need value 1 for true value. ex.: `--fullscreen` is equal `--fullscreen 1`
> {style="note"}

| Args                     | Value                          | Default | Description                                 |
|--------------------------|--------------------------------|---------|---------------------------------------------|
| `--load-dynamic`         | `1` or `0`                     | `1`     | Load dynamic modules?                       |
| `--max-kernel-tick`      | `n`                            | `null`  | Quit after kernel make n ticks.             |
| `--max-kernel-tick-rate` | `n`                            | `60`    | Kernel frame rate.                          |
| `--headless`             | `1` or `0`                     | `0`     | Without creating real window.               |
| `--asset-root`           | `str`                          | `null`  | Path to asset root. (project path)          |
| `--fullscreen`           | `1` or `0`                     | `0`     | Force full-screen mode, nice for SteamDeck. |
| `--test-ui`              | `1` or `0`                     | `0`     | Run UI tests and quit.                      |
| `--test-ui-filter`       | `str`                          | `all`   | Run only ui tests that pass this filter.    |
| `--test-ui-speed`        | `fast`, `normal`,  `cinematic` | `fast`  | UI test speed.                              |
| `--test-ui-junit`        | `str`                          | `null`  | UI test JUnit result filename.              |

## Tracy profiler

CETech1 has builtin support for tracy profiler.

> For more details go to [tracy](https://github.com/wolfpld/tracy) repository.

<tabs>
    <tab title="MacOS">
        <code-block lang="bash">
            brew install tracy
            tracy -a localhost
            zig-out/bin/cetech1 # on separate terminal
            # Have fun
        </code-block>
    </tab>
    <tab title="Linux">
        <code-block lang="bash">
            # install tracy by your way
            tracy -a localhost
            zig-out/bin/cetech1 # on separate terminal
            # Have fun
        </code-block>
    </tab>
</tabs>

## ZLS

CETech provide ZLS as submodule, but you must build it.

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash">
            cd externals/shared/tools/zls
            ../../../../zig/bin/ARCH/zig build
        </code-block>
    </tab>
    <tab title="Windows">
        <code-block lang="bash">
            cd externals/shared/tools/zls
            ../../../../zig/bin/ARCH/zig.exe build
        </code-block>
    </tab>
</tabs>

## VSCode

> Repository contain recommended extension.

1. Build [ZLS](#zls)
2. Install extension `ziglang.vscode-zig` (or install all recommended)
3. Set zig path to `<FULL_PATH_TO_CETECH_REPO>/zig/bin/<ARCH>/zig`
4. Set zls path to `<FULL_PATH_TO_CETECH_REPO>/externals/shared/tools/zls/zig-out/bin/zls`

