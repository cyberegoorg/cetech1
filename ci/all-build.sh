#!/bin/bash

set -x
set -e

ZIG_ARCH=$1

./lfs_pull.sh ${ZIG_ARCH}

rm -rf build
mkdir -p build

function build() {
    TARGET_ZIG_ARCH=$1
    externals/shared/bin/zig/zig_${ZIG_ARCH} build -Dtarget=${TARGET_ZIG_ARCH} --verbose
    mv zig-out build/${TARGET_ZIG_ARCH}
}

build x86_64-linux
build x86_64-windows
build x86_64-macos

ls -Rhal build/
