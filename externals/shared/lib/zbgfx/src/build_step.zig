const std = @import("std");

pub fn installShaderCPrecompiledDependencies(b: *std.Build, target: std.Build.ResolvedTarget, step: *std.Build.Step, zbgfx_dep: *std.Build.Dependency) !void {
    if (target.result.os.tag.isDarwin()) return;

    if (target.result.os.tag == .windows) {
        const install_d3d4linux = b.addInstallBinFile(zbgfx_dep.path("libs/bgfx/tools/bin/windows/d3d4linux.exe"), "d3d4linux.exe");
        const install_d3dcompiler_47 = b.addInstallBinFile(zbgfx_dep.path("libs/bgfx/tools/bin/windows/d3dcompiler_47.dll"), "d3dcompiler_47.dll");
        const install_dxcompiler = b.addInstallBinFile(zbgfx_dep.path("libs/bgfx/tools/bin/windows/dxcompiler.dll"), "dxcompiler.dll");
        const install_dxil = b.addInstallBinFile(zbgfx_dep.path("libs/bgfx/tools/bin/windows/dxil.dll"), "dxil.dll");
        step.dependOn(&install_d3d4linux.step);
        step.dependOn(&install_d3dcompiler_47.step);
        step.dependOn(&install_dxcompiler.step);
        step.dependOn(&install_dxil.step);
    } else {
        const install_libdxcompiler = b.addInstallBinFile(zbgfx_dep.path("libs/bgfx/tools/bin/linux/libdxcompiler.so"), "libdxcompiler.so");
        const install_libdxil = b.addInstallBinFile(zbgfx_dep.path("libs/bgfx/tools/bin/linux/libdxil.so"), "libdxil.so");
        step.dependOn(&install_libdxcompiler.step);
        step.dependOn(&install_libdxil.step);
    }
}
