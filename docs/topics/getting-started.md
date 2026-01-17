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

## Clone

<tabs>
    <tab title="MacOS/Linux/SteamDeck/Windows">
        <code-block lang="bash" src="getting-started/clone.sh"></code-block>
    </tab>
</tabs>

## Get ZIG

Get ZIG `0.15.1`.

<tabs>
    <tab title="ZVM">
        Get <a href="https://www.zvm.app">ZVM</a>
        <code-block lang="bash">
            # zvm vmu zig mach - only for mach versions
            zvm i 0.15.1
        </code-block>
    </tab>
    <tab title="VSCode">
      Install via VSCode <a href="https://marketplace.visualstudio.com/items?itemName=ziglang.vscode-zig">plugin</a> or use ZVM. 
    </tab>
</tabs>

## VSCode

> Repository contain recommended extension.

> add `-Dno_zls` to disable zls path change (For example if you are install zls via vscode plugin).
> {style="note"}

1. Create vscode configs.
    <code-block lang="bash">
        # This generate vscode launch.json with predefined cases
        # create or update settings.json
        # and set zls path to locally builded
        zig build gen-ide -Dide=VSCode
    </code-block>
2. Install extension `ziglang.vscode-zig` (or install all recommended)

## Idea

Need [zigbrains](https://plugins.jetbrains.com/plugin/22456-zigbrains)

1. Create idea configs.
    <code-block lang="bash">
        # This generate basic files in .idea and run configuration predefined cases
        # and set zls path to locally builded
        zig build gen-ide -Dide=IDEA
    </code-block>

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

| Args                 | Value             | Default | Description                                                                 |
|----------------------|-------------------|---------|-----------------------------------------------------------------------------|
| `-Ddynamic_modules=` | `true` or `false` | `true`  | Build all modules in dynamic mode.                                          |
| `-Dstatic_modules=`  | `true` or `false` | `false` | Build all modules in static mode.                                           |
| `-Dwith_samples=`    | `true` or `false` | `true`  | Build with sample modules.                                                  |
| `-Dwith_studio=`     | `true` or `false` | `true`  | Build with studio modules.                                                  |
| `-Dwith_tracy=`      | `true` or `false` | `true`  | Build with [tracy](#tracy-profiler) support.                                |
| `-Dwith_nfd=`        | `true` or `false` | `true`  | Build with NFD (native file dialog)                                         |
| `-Dnfd_portal=`      | `true` or `false` | `true`  | Build NFD with xdg-desktop-portal instead of GTK. Linux, nice for SteamDeck |

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

| Args                     | Value                                                 | Default         | Description                                 |
|--------------------------|-------------------------------------------------------|-----------------|---------------------------------------------|
| `--asset-root`           | `str`                                                 | `null`          | Path to asset root. (project path)          |
| `--load-dynamic`         | `1` or `0`                                            | `1`             | Load dynamic modules?                       |
| `--max-kernel-tick`      | `n`                                                   | `null`          | Quit after kernel make n ticks.             |
| `--max-kernel-tick-rate` | `n`                                                   | `60`            | Kernel frame rate.                          |
| `--worker-count`         | number                                                | CPU count       | Max threads for task system.                |
| `--renderer`             | `bgfx_metal`, `bgfx_vulkan`, `bgfx_dx12`, `bgfx_noop` | Autoselect best | Render backed.                              |
| `--renderer-debug`       | `1` or `0`                                            | `0`             | Render backed debug. (shaders)              |
| `--renderer-profile`     | `1` or `0`                                            | `0`             | Render backed profile. (shaders)            |
| `--headless`             | `1` or `0`                                            | `0`             | Without creating real window.               |
| `--vsync`                | `1` or `0`                                            | `0`             | Vsync.                                      |
| `--fullscreen`           | `1` or `0`                                            | `0`             | Force full-screen mode, nice for SteamDeck. |
| `--test-ui`              | `1` or `0`                                            | `0`             | Run UI tests and quit.                      |
| `--test-ui-filter`       | `str`                                                 | `all`           | Run only ui tests that pass this filter.    |
| `--test-ui-speed`        | `fast`, `normal`,  `cinematic`                        | `fast`          | UI test speed.                              |
| `--test-ui-junit`        | `str`                                                 | `null`          | UI test JUnit result filename.              |

## ZLS

CETech provide ZLS as submodule, but you must build it.

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash">
            git submodule update --init externals/shared/repo/zls
            cd externals/shared/repo/zls
            zig build -Doptimize=ReleaseFast
        </code-block>
    </tab>
    <tab title="Windows">
        <code-block lang="bash">
            git submodule update --init externals/shared/repo/zls
            cd externals/shared/repo/zls
            zig.exe build -Doptimize=ReleaseFast
        </code-block>
    </tab>
</tabs>

## Tracy profiler

CETech1 has builtin support for tracy profiler and provide Tracy as submodule, but you must build it first.

> For more details go to [tracy](https://github.com/wolfpld/tracy) repository.

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash">
            git submodule update --init externals/shared/repo/tracy
            cd externals/shared/repo/tracy
            cmake -B profiler/build -S profiler -DCMAKE_BUILD_TYPE=Release
            cmake --build profiler/build --parallel --config Release
        </code-block>
    </tab>
    <tab title="Windows">
        <code-block lang="bash">
            git submodule update --init externals/shared/repo/tracy
            cd externals/shared/repo/tracy
            cmake -B profiler/build -S profiler -DCMAKE_BUILD_TYPE=Release
            cmake --build profiler/build --parallel --config Release
        </code-block>
    </tab>
</tabs>

<tabs>
    <tab title="MacOS">
        <code-block lang="bash">
            profiler/build/tracy-profiler -a localhost
            zig-out/bin/cetech1_studio # on separate terminal
            # Have fun
        </code-block>
    </tab>
    <tab title="Linux">
        <code-block lang="bash">
            # install tracy by your way
            profiler/build/tracy-profiler -a localhost
            zig-out/bin/cetech1_studio # on separate terminal
            # Have fun
        </code-block>
    </tab>
</tabs>
