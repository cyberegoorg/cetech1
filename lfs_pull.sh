#/bin/bash

set -x
set -e

#export GIT_TRACE=1

cd "$(dirname "$0")"
git lfs pull --include "Writerside/images/**/*"
git lfs pull --include "src/private/embed/fonts/*"

# LFS for zig-gamedev
cd externals/shared/lib/zig-gamedev
git lfs pull --include "libs/system-sdk/**/*"

cd "$(dirname "$0")"
