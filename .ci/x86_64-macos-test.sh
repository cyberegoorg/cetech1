#!/bin/sh

set -x
set -e


OPTIMIZE=$1

mv build/${OPTIMIZE}/x86_64-macos zig-out 

zig-out/bin/cetech1_test
zig-out/bin/cetech1 --headless --max-kernel-tick 5
