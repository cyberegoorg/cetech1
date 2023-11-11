#!/bin/sh

set -x
set -e


OPTIMIZE=$1

mv build/${OPTIMIZE}/x86_64-linux zig-out 
chmod -R 777 zig-out/
ls -Rhan zig-out/

zig-out/bin/cetech1_test 
#zig-out/bin/cetech1 --headless --max-kernel-tick 5
