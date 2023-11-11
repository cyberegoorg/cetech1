#!/bin/bash

set -x
set -e

ZIG_ARCH=$1

./zig/lfs_pull.sh ${ZIG_ARCH}

function build() {
    zig/${ZIG_ARCH}/zig build docs
}

build x86_64-linux
