#!/bin/sh

set -x
set -e

build/x86_64-linux/bin/cetech1
build/x86_64-linux/bin/cetech1_test
