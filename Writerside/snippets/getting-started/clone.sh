# GIT_LFS_SKIP_SMUDGE=1 disable loading all LFS objects
GIT_LFS_SKIP_SMUDGE=1 git clone  https://github.com/cyberegoorg/cetech1.git

# This fetch submodules from `externals`
git submodule update --init

# This download lfs files that is needed for build and other stuff
zig build init
