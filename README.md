[cetech1](https://github.com/cyberegoorg/cetech1) - CeTech 1
============================================================================

[![GitHub Actions](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml/badge.svg)](https://github.com/cyberegoorg/cetech1/actions/workflows/ci.yaml)


# Supported architectures

| Arch           	| Description 	|
|----------------	|-------------	|
| x86_64-macos   	| Apple Intel   |
| aarch64-macos  	| Apple Arm     |
| x86_64-linux   	| Linux         |
| aarch64-linux   	| Linux ARM     |
| x86_64-windows 	| Windows       |
| aarch64-windows 	| Windows ARM   |

# Docs [API](https://cyberegoorg.github.io/cetech1/)/[Guide](https://cyberegoorg.github.io/cetech1/#G;)

# Clone

```sh
$ GIT_LFS_SKIP_SMUDGE=1 git clone --recurse-submodules https://github.com/cyberegoorg/cetech1.git 
$ ./lfs_pull.sh <ARCH> # Only need for your arch not target
```

# Build

```sh
$ externals/shared/bin/zig/zig_<ARCH> build
```

# Run
```sh
$ zig-out/bin/cetech1
```

# Test 
```sh
$ zig-out/bin/cetech1_test
```

# Build docs

```sh
$ externals/shared/bin/zig/zig_<ARCH> build docs
```
