param (
    [string]$optimize
)

function CheckLastExitCode {
    if (!$?) {
        exit 1
    }
    return 0
}


Move-Item -Path ./build/$optimize/x86_64-windows -Destination ./zig-out

zig-out/bin/cetech1_test.exe
CheckLastExitCode

zig-out/bin/cetech1.exe --headless --max-kernel-tick 5
CheckLastExitCode
