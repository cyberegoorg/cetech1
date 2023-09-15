#!/bin/bash

set -x
set -e

ZIG_ARCH=$1

./lfs_pull.sh ${ZIG_ARCH}

function build() {
    externals/shared/bin/zig/zig_${ZIG_ARCH} build docs
}

build x86_64-linux
