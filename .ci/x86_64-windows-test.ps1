param (
    [string]$optimize
)

Move-Item -Path ./build/$optimize/x86_64-windows -Destination ./zig-out

zig-out/bin/cetech1_test.exe
zig-out/bin/cetech1.exe --max-kernel-tick 5
