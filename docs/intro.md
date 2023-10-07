# CETech 1

[![GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml/badge.svg)](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml)

Yet another experimental game engine.

## Supported architectures

| Arch                | Description   |
|---------------------|---------------|
| `x86_64-macos`      | Apple Intel   |
| `aarch64-macos`     | Apple Arm     |
| `x86_64-linux`      | Linux         |
| `aarch64-linux`     | Linux ARM     |
| `x86_64-windows`    | Windows       |
| `aarch64-windows`   | Windows ARM   |

## Clone

```sh
# GIT_LFS_SKIP_SMUDGE=1 disable loading all LFS objects
GIT_LFS_SKIP_SMUDGE=1 git clone --recursive https://github.com/cyberegoorg/cetech1.git

# This download zig binary from LFS. Only need for your arch where you develop
./bin/zig/lfs_pull.sh <ARCH>
```

## Build

```sh
bin/zig/zig_<ARCH> build
```

Args                      | Value           | Default     | Description
--------------------------|-----------------|-------------|-----------------------------------
`-dwith-tracy=`           | true \| false   | true        | Build with [tracy](#tracy-profiler) support?
`-dtracy-on-demand=`      | true \| false   | true        | Collect data only if exist client.

## Run

```sh
zig-out/bin/cetech1_test && zig-out/bin/cetech1
```

Args                      | Value    | Default     | Description
--------------------------|----------|-------------|-----------------------------------
`--load-dynamic`          | 1 \| 0   | 1           | Load dynamic modules?
`--max-kernel-tick`       | n        | null        | Quit affter kernel make n ticks.

## Tracy profiler

For more details go to [tracy](https://github.com/wolfpld/tracy) repository.

### Macos

```sh
brew install tracy
tracy -a localhost 
zig-out/bin/cetech1 # on separate terminal
# Have fun
```

## Docker compose

You must fetch valid zig version for container `ARCH` via `./bin/zig/lfs_pull.sh <ARCH>`

```sh
docker compose run --service-ports cetech1-linux 
```

## VScode

- Extension `ziglang.vscode-zig`
- Use zls provided with extension (udate features is nice)
- Set zig path to `<FULL_PATH_TO>bin/zig/zig_<ARCH>`
