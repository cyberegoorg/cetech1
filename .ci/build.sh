#!/bin/bash

set -x
set -e

ZIG_ARCH=$1
OPTIMIZE=$2

zig/bin/${ZIG_ARCH}/zig build init

function build() {
    WITH_TRACY=$1
    WITH_NFD=$2
    zig/bin/${ZIG_ARCH}/zig build -Doptimize=${OPTIMIZE} -Dwith_tracy=${WITH_TRACY} -Dwith_nfd=${WITH_NFD}
}

build false true

ls -Rhan zig-out/
