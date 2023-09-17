#!/bin/sh

set -x
set -e

mv build/x86_64-macos zig-out 

zig-out/bin/cetech1_test
zig-out/bin/cetech1 --max-kernel-tick 5
