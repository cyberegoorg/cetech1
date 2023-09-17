# CETech 1

[![GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml/badge.svg)](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml)

Yet another experimental game engine.

## Supported architectures

| Arch              | Description   |
|-------------------|---------------|
| x86_64-macos      | Apple Intel   |
| aarch64-macos     | Apple Arm     |
| x86_64-linux      | Linux         |
| aarch64-linux     | Linux ARM     |
| x86_64-windows    | Windows       |
| aarch64-windows   | Windows ARM   |

## Docs [API](https://cyberegoorg.github.io/cetech1/)/[Guide](https://cyberegoorg.github.io/cetech1/#G;)

## Clone

```sh
GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/cyberegoorg/cetech1.git 
./lfs_pull.sh <ARCH> # This download zig binary from LFS. Only need for your arch where you develop
```

## Build

```sh
externals/shared/bin/zig/zig_<ARCH> build
```

## Run

```sh
zig-out/bin/cetech1
```

Args                      | Value    | Default     | Description
--------------------------|----------|-------------|-----------------------------------
`--load-dynamic`          | 1 \| 0   | 1           | Load dynamic modules?
`--max-kernel-tick`       | n        | null        | Quit affter kernel make n ticks.

## Test

```sh
zig-out/bin/cetech1_test
```

## Build docs

```sh
externals/shared/bin/zig/zig_<ARCH> build docs
```

## Docker compose

You must fetch valid zig version for container `ARCH` via `./lfs_pull.sh <ARCH>`

```sh
docker compose run cetech1-linux 
```

## VScode

- Extension `ziglang.vscode-zig`
- Use zls provided with extension (udate features is nice)
- Set zig path to `<FULL_PATH_TO>/externals/shared/bin/zig/zig_<ARCH>`
