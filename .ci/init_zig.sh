#!/bin/bash

set -x
set -e

ZIG_ARCH=$1
OPTIMIZE=$2

./zig/get_zig.sh ${ZIG_ARCH}

