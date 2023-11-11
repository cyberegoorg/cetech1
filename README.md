# CETech 1

[![GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/test.yaml/badge.svg)](https://github.com/cyberegoorg/cetech1/actions/workflows/test.yaml)
[![codecov](https://codecov.io/gh/cyberegoorg/cetech1/graph/badge.svg?token=FCES8KRIPA)](https://codecov.io/gh/cyberegoorg/cetech1)

Yet another experimental game engine but now in [zig](https://ziglang.org).

## [Documentation](https://cyberegoorg.github.io/cetech1)

## [Getting started](https://cyberegoorg.github.io/cetech1/getting-started.html)

## Supported architectures

| Arch                | Description   |
|---------------------|---------------|
| `x86_64-macos`      | Apple Intel   |
| `aarch64-macos`     | Apple Arm     |
| `x86_64-linux`      | Linux         |
| `aarch64-linux`     | Linux ARM     |
| `x86_64-windows`    | Windows       |

## Clone

```sh
# GIT_LFS_SKIP_SMUDGE=1 disable loading all LFS objects
GIT_LFS_SKIP_SMUDGE=1 git clone --recursive https://github.com/cyberegoorg/cetech1.git

# This download zig binary from LFS. Only need for your arch where you develop
./zig/lfs_pull.sh <ARCH>

# This download lfs files that is needed
./lfs_pull.sh
```

## Build

```sh
zig/bin/<ARCH>/zig build
```

## Run

```sh
zig-out/bin/cetech1_test && zig-out/bin/cetech1 --asset-root tests/test_asset/
```

## Credits/Licenses For Fonts Included In Repository

Some fonts files are available in the `src/cetech1/core/private/fonts` folder:

- **[Roboto-Medium.ttf](https://fonts.google.com/specimen/Roboto)** - Apache License 2.0
- **[fa-solid-900.ttf](https://fontawesome.com)** - SIL OFL 1.1 License
- **[fa-regular-400.ttf](https://fontawesome.com)** - SIL OFL 1.1 License
