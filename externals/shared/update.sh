#/bin/bash

function download_zig_all() {
    TARBALL=`curl https://ziglang.org/download/index.json | jq -r .master[\"aarch64-macos\"].tarball`
    mkdir -p tmp/aarch64-macos/zig/
    curl -L $TARBALL | tar zxv -C tmp/aarch64-macos/zig/ --strip-components 1

    mkdir -p bin/zig
    cp -r tmp/aarch64-macos/zig/ bin/zig
    mv bin/zig/zig bin/zig/zig_aarch64-macos
}

function download_zig_bin() {
    ZIG_ARCH=$1
    TARBALL=`curl https://ziglang.org/download/index.json | jq -r .master[\"${ZIG_ARCH}\"].tarball`
    FILENAME=$(basename -- "$TARBALL")
    curl -L $TARBALL | tar zxv -C bin/zig/ --strip-components 1 "${FILENAME%.*.*}/zig"
    mv bin/zig/zig bin/zig/zig_${ZIG_ARCH}    
}

function download_zig_bin_win() {
    ZIG_ARCH=$1
    TARBALL=`curl https://ziglang.org/download/index.json | jq -r .master[\"${ZIG_ARCH}\"].tarball`
    FILENAME=$(basename -- "$TARBALL")

    mkdir -p "tmp/${ZIG_ARCH}/zig/"
    curl -o "tmp/${ZIG_ARCH}/zig/zig.zip" $TARBALL
    unzip -o "tmp/${ZIG_ARCH}/zig/zig.zip" -d "tmp/${ZIG_ARCH}/zig/"
    mv "tmp/${ZIG_ARCH}/zig/${FILENAME%.*}/zig.exe" bin/zig/zig_${ZIG_ARCH}.exe
}

download_zig_all
download_zig_bin "x86_64-macos"
download_zig_bin "x86_64-linux"
download_zig_bin "aarch64-linux"
download_zig_bin_win "x86_64-windows"
download_zig_bin_win "aarch64-windows"

rm -rf ./tmp