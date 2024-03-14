#!/bin/bash

set -x
set -e

ZIG_ARCH=$1

./zig/get_zig.sh ${ZIG_ARCH}

function build() {
    zig/${ZIG_ARCH}/zig build docs
}

build x86_64-linux
