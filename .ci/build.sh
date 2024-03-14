#!/bin/bash

set -x
set -e

ZIG_ARCH=$1
OPTIMIZE=$2

#./zig/get_zig.sh ${ZIG_ARCH}
./lfs_pull.sh

function build() {
    WITH_TRACY=$1
    WITH_NFD=$2
    zig/bin/${ZIG_ARCH}/zig build -Doptimize=${OPTIMIZE} -Dwith-tracy=${WITH_TRACY} -Dwith-nfd=${WITH_NFD}
}

build false true

ls -Rhan zig-out/
