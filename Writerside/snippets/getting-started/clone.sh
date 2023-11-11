# GIT_LFS_SKIP_SMUDGE=1 disable loading all LFS objects
GIT_LFS_SKIP_SMUDGE=1 git clone --recursive https://github.com/cyberegoorg/cetech1.git

# This download zig binary from LFS. Only need for your arch where you develop
./zig/lfs_pull.sh <ARCH>

# This download lfs files that is needed
./lfs_pull.sh