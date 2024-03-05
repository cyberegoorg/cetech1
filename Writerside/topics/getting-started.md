# Getting started

## Supported architectures

> Currently, not all architectures are tested.
> For tested platform check [GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/test.yaml).
> But you can still try to compile/run it on your arch.
> Currently develop on `aarch64-macos`, `x86_64-macos` and `SteamDeck`.
> {style="note"}

| \<ARCH\>         | Description      |
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

| Args                 | Value         | Default | Description                                      |
|----------------------|---------------|---------|--------------------------------------------------|
| `-Dwith-tracy=`      | true \| false | true    | Build with [tracy](#tracy-profiler) support?     |
| `-Dtracy-on-demand=` | true \| false | true    | Collect data only if exist client.               |
| `-Dwith-nfd=`        | true \| false | true    | Build with NFD (native file dialog)              |
| `-Dnfd-zenity=`      | true \| false | false   | Build NFD with zenity. Linux, nice for SteamDeck |

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

| Args                     | Value  | Default | Description                                |
|--------------------------|--------|---------|--------------------------------------------|
| `--load-dynamic`         | 1 \| 0 | 1       | Load dynamic modules?                      |
| `--max-kernel-tick`      | n      | null    | Quit after kernel make n ticks.            |
| `--max-kernel-tick-rate` | n      | 60      | Kernel frame rate.                         |
| `--headless`             | 1 \| 0 | 0       | Without creating real window.              |
| `--asset-root`           | str    | null    | Path to asset root (project path)          |
| `--fullscreen`           | 1 \| 0 | 0       | Force full-screen mode, nice for SteamDeck |

## Tracy profiler

CeTech1 has builtin support for tracy profiler.

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

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash">
            cd externals/shared/tools/zls
            ../../../../zig/bin/ARCH/zig build
        </code-block>
    </tab>
</tabs>

## VSCode

> Repository contain recommended extension.

1. Build [ZLS](#zls)
2. Install extension `ziglang.vscode-zig`
3. Set zig path to `<FULL_PATH_TO_CETECH_REPO>/zig/bin/<ARCH>/zig`
4. Set zls path to `<FULL_PATH_TO_CETECH_REPO>/externals/shared/tools/zls/zig-out/bin/zls`

## Docker compose

You must fetch valid zig version for container `ARCH` via `./bin/zig/lfs_pull.sh <ARCH>`

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash">docker compose run --service-ports cetech1-linux</code-block>
    </tab>
</tabs>
