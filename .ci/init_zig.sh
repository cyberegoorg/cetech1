#!/bin/bash

set -x
set -e

ZIG_ARCH=$1
OPTIMIZE=$2

./zig/lfs_pull.sh ${ZIG_ARCH}
./lfs_pull.sh
