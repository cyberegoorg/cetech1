#!/bin/bash

set -x
set -e

ZIG_ARCH=$1
TARGET_ZIG_ARCH=$2
OPTIMIZE=$3

./bin/zig/lfs_pull.sh ${ZIG_ARCH}

mkdir -p build/${OPTIMIZE}

function build() {
    WITH_TRACY=$1
    bin/zig/zig_${ZIG_ARCH} build -Dtarget=${TARGET_ZIG_ARCH} -Doptimize=${OPTIMIZE} -Dwith-tracy=${WITH_TRACY} --verbose
    mv zig-out build/${OPTIMIZE}/${TARGET_ZIG_ARCH}
}

build false

ls -Rhal build/
