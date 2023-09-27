#!/bin/bash

set -x
set -e

ZIG_ARCH=$1

./lfs_pull.sh ${ZIG_ARCH}

rm -rf build
mkdir -p build

function build() {
    TARGET_ZIG_ARCH=$1
    WITH_TRACY=$2
    externals/shared/bin/zig/zig_${ZIG_ARCH} build -Dtarget=${TARGET_ZIG_ARCH} -Dwith-tracy=${WITH_TRACY} --verbose
    mv zig-out build/${TARGET_ZIG_ARCH}
}

build x86_64-linux false
build x86_64-windows false
build x86_64-macos false

ls -Rhal build/
