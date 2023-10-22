# Getting started

## Supported architectures

> Currently, not all architectures are tested.
> For tested platform check [GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml).
> But you can still try to compile/run it on your arch.
> Currently develop on `aarch64-macos` and `x86_64-macos`.
> {style="note"}

| \<ARCH\>         | Description |
|------------------|-------------|
| `x86_64-macos`   | Apple Intel |
| `aarch64-macos`  | Apple Arm   |
| `x86_64-linux`   | Linux       |
| `aarch64-linux`  | Linux ARM   |
| `x86_64-windows` | Windows     |

## Clone

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash" src="getting-started/clone.sh"></code-block>
    </tab>
</tabs>

## Build

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash" src="getting-started/build.sh"></code-block>
    </tab>
</tabs>

| Args                 | Value         | Default | Description                                  |
|----------------------|---------------|---------|----------------------------------------------|
| `-Dwith-tracy=`      | true \| false | true    | Build with [tracy](#tracy-profiler) support? |
| `-Dtracy-on-demand=` | true \| false | true    | Collect data only if exist client.           |
| `-Dwith-nfd=`        | true \| false | true    | Build with NFD (native file dialog)          |

## Run

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash" src="getting-started/run.sh"></code-block>
    </tab>
</tabs>

| Args                     | Value  | Default | Description                       |
|--------------------------|--------|---------|-----------------------------------|
| `--load-dynamic`         | 1 \| 0 | 1       | Load dynamic modules?             |
| `--max-kernel-tick`      | n      | null    | Quit after kernel make n ticks.   |
| `--max-kernel-tick-rate` | n      | 60      | Kernel frame rate.                |
| `--headless`             | 1 \| 0 | 0       | Without creating real window.     |
| `--asset-root`           | str    | null    | Path to asset root (project path) |

## Tracy profiler

CeTech1 has builtin support for tracy profiler.

> For more details go to [tracy](https://github.com/wolfpld/tracy) repository.

### Macos

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

## Docker compose

You must fetch valid zig version for container `ARCH` via `./bin/zig/lfs_pull.sh <ARCH>`

<tabs>
    <tab title="MacOS/Linux">
        <code-block lang="bash">docker compose run --service-ports cetech1-linux</code-block>
    </tab>
</tabs>

## VSCode

> Repository contain recommended extension.
> {style="note"}

1. Install extension `ziglang.vscode-zig`
2. Use zls provided with extension.
3. Set zig path to `<FULL_PATH_TO>bin/zig/zig_<ARCH>`
