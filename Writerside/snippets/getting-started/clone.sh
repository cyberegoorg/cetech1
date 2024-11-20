# GIT_LFS_SKIP_SMUDGE=1 disable loading all LFS objects
GIT_LFS_SKIP_SMUDGE=1 git clone  https://github.com/cyberegoorg/cetech1.git

# This fetch basic externals deps
git submodule update --init externals/shared

# This download zig binary from our website. Only need for your arch where you develop
./zig/get_zig.sh <ARCH>

# This download lfs files that is needed for build
zig/bin/<ARCH>/zig build init
