#/bin/bash

set -x
set -e

cd "$(dirname "$0")"

# LFS for zig-gamedev
cd externals/shared/lib/zig-gamedev
git lfs pull --include "libs/system-sdk/**/*"

cd "$(dirname "$0")"
