//! Kernel is entry point/runner for engine.

const std = @import("std");
const ztracy = @import("ztracy");

const strid = @import("strid.zig");
const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const gpu = @import("gpu.zig");
const platform = @import("platform.zig");

const log = std.log.scoped(.kernel);

pub const OnLoad = strid.strId64("OnLoad");
pub const PostLoad = strid.strId64("PostLoad");
pub const PreUpdate = strid.strId64("PreUpdate");
pub const OnUpdate = strid.strId64("OnUpdate");
pub const OnValidate = strid.strId64("OnValidate");
pub const PostUpdate = strid.strId64("PostUpdate");
pub const PreStore = strid.strId64("PreStore");
pub const OnStore = strid.strId64("OnStore");

// Create Kernel task interface.
// You can implement init andor shutdown that is call only on main init/shutdown
pub const KernelTaskI = struct {
    pub const c_name = "ct_kernel_task_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8,
    depends: []const strid.StrId64,
    init: *const fn () anyerror!void,
    shutdown: *const fn () anyerror!void,

    pub inline fn implement(
        name: [:0]const u8,
        depends: []const strid.StrId64,
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
    pub const name_hash = strid.strId64(@This().c_name);

    phase: strid.StrId64,
    name: [:0]const u8,
    depends: []const strid.StrId64,
    update: *const fn (kernel_tick: u64, dt: f32) anyerror!void,

    pub inline fn implment(
        phase: strid.StrId64,
        name: [:0]const u8,
        depends: []const strid.StrId64,
        comptime T: type,
    ) KernelTaskUpdateI {
        if (!std.meta.hasFn(T, "update")) @compileError("implement me");

        return KernelTaskUpdateI{
            .phase = phase,
            .name = name,
            .depends = depends,
            .update = T.update,
        };
    }
};

// TODO: TEMP SHIT
pub const KernelLoopHookI = struct {
    pub const c_name = "ct_kernel_loop_hook_i";
    pub const name_hash = strid.strId64(@This().c_name);

    begin_loop: *const fn (kernel_tick: u64, dt: f32) anyerror!void,
    end_loop: *const fn () anyerror!void,

    pub inline fn implement(
        comptime T: type,
    ) KernelLoopHookI {
        if (!std.meta.hasFn(T, "beginLoop")) @compileError("implement me");
        if (!std.meta.hasFn(T, "endLoop")) @compileError("implement me");

        return KernelLoopHookI{
            .begin_loop = T.beginLoop,
            .end_loop = T.endLoop,
        };
    }
};

// TODO: TEMP SHIT
pub const KernelRenderI = struct {
    pub const c_name = "ct_kernel_render_i";
    pub const name_hash = strid.strId64(@This().c_name);

    render: *const fn (ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) anyerror!void,

    pub inline fn implment(
        comptime T: type,
    ) KernelRenderI {
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        return KernelRenderI{
            .render = T.render,
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
    isTestigMode: *const fn () bool,

    getMainWindow: *const fn () ?platform.Window,
    getGpuCtx: *const fn () ?*gpu.GpuContext,

    getExternalsCredit: *const fn () [:0]const u8,
    getAuthors: *const fn () [:0]const u8,

    // TODO: !!!GLOBAL SHIT WARNING !!!
    getDb: *const fn () cdb.DbId,
    //
};
