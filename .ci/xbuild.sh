#!/bin/bash

set -x
set -e

ZIG_ARCH=$1
TARGET_ZIG_ARCH=$2
OPTIMIZE=$3

./zig/get_zig.sh ${ZIG_ARCH}
./lfs_pull.sh

mkdir -p build/${OPTIMIZE}

function build() {
    WITH_TRACY=$1
    zig/bin/${ZIG_ARCH}/zig build -Dtarget=${TARGET_ZIG_ARCH} -Doptimize=${OPTIMIZE} -Dwith-tracy=${WITH_TRACY} -Dwith-nfd=false --verbose
    mv zig-out build/${OPTIMIZE}/${TARGET_ZIG_ARCH}
}

build false

ls -Rhan build/
