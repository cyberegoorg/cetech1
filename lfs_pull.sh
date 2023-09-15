#/bin/bash

ZIG_ARCH=$1
git lfs pull --include "externals/shared/bin/zig/zig_${ZIG_ARCH}"
