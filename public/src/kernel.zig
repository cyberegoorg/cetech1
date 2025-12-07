//! Kernel is entry point/runner for engine.

const std = @import("std");

const cetech1 = @import("root.zig");
const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const gpu = @import("gpu.zig");
const host = @import("host.zig");

const log = std.log.scoped(.kernel);

pub const OnLoad = cetech1.strId64("OnLoad");
pub const PostLoad = cetech1.strId64("PostLoad");
pub const PreUpdate = cetech1.strId64("PreUpdate");
pub const OnUpdate = cetech1.strId64("OnUpdate");
pub const OnValidate = cetech1.strId64("OnValidate");
pub const PostUpdate = cetech1.strId64("PostUpdate");
pub const PreStore = cetech1.strId64("PreStore");
pub const OnStore = cetech1.strId64("OnStore");

// Create Kernel task interface.
// You can implement init andor shutdown that is call only on main init/shutdown
pub const KernelTaskI = struct {
    pub const c_name = "ct_kernel_task_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8,
    depends: []const cetech1.StrId64,
    init: *const fn () anyerror!void,
    shutdown: *const fn () anyerror!void,

    pub inline fn implement(
        name: [:0]const u8,
        depends: []const cetech1.StrId64,
        comptime T: type,
    ) KernelTaskI {
        if (!std.meta.hasFn(T, "init")) @compileError("implement me");
        if (!std.meta.hasFn(T, "shutdown")) @compileError("implement me");

        return KernelTaskI{
            .name = name,
            .depends = depends,
            .init = T.init,
            .shutdown = T.shutdown,
        };
    }
};

// Create Kernel update task interface.
// You must implement update that is call every kernel main loop.
pub const KernelTaskUpdateI = struct {
    pub const c_name = "ct_kernel_task_update_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    phase: cetech1.StrId64,
    name: [:0]const u8,
    depends: []const cetech1.StrId64,
    affinity: ?u32 = null,
    update: *const fn (kernel_tick: u64, dt: f32) anyerror!void,

    pub inline fn implment(
        phase: cetech1.StrId64,
        name: [:0]const u8,
        depends: []const cetech1.StrId64,
        affinity: ?u32,
        comptime T: type,
    ) KernelTaskUpdateI {
        if (!std.meta.hasFn(T, "update")) @compileError("implement me");

        return KernelTaskUpdateI{
            .phase = phase,
            .name = name,
            .depends = depends,
            .affinity = affinity,
            .update = T.update,
        };
    }
};

pub const TestResult = struct {
    count_tested: i32,
    count_success: i32,
};

pub const KernelTestingI = struct {
    pub const c_name = "ct_kernel_testing_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    isRunning: *const fn () anyerror!bool,
    printResult: *const fn () void,
    getResult: *const fn () TestResult,

    pub inline fn implment(comptime T: type) KernelTestingI {
        if (!std.meta.hasFn(T, "isRunning")) @compileError("implement me");
        if (!std.meta.hasFn(T, "printResult")) @compileError("implement me");
        if (!std.meta.hasFn(T, "getResult")) @compileError("implement me");

        return KernelTestingI{
            .isRunning = T.isRunning,
            .printResult = T.printResult,
            .getResult = T.getResult,
        };
    }
};

pub const KernelApi = struct {
    quit: *const fn () void,
    setCanQuit: *const fn (can_quit: *const fn () bool) void,
    getKernelTickRate: *const fn () u32,
    setKernelTickRate: *const fn (rate: u32) void,
    openAssetRoot: *const fn (asset_root: ?[]const u8) void,
    restart: *const fn () void,
    isHeadlessMode: *const fn () bool,
    isTestigMode: *const fn () bool,

    getExternalsCredit: *const fn () [:0]const u8,
    getAuthors: *const fn () [:0]const u8,

    getStrArgs: *const fn (arg_name: []const u8) ?[]const u8,
    getIntArgs: *const fn (arg_name: []const u8) ?u32,

    // TODO: !!!GLOBAL SHIT WARNING !!!
    getDb: *const fn () cdb.DbId,
    getMainWindow: *const fn () ?host.Window,
    getGpuBackend: *const fn () ?gpu.GpuBackend,

    //
};
