//! Kernel is entry point/runner for engine.

const std = @import("std");
const ztracy = @import("ztracy");

const c = @import("private/c.zig").c;
const strid = @import("strid.zig");
const log = @import("log.zig");
const cdb = @import("cdb.zig");
const modules = @import("modules.zig");

pub const OnLoad = strid.strId64(c.CT_KERNEL_PHASE_ONLOAD);
pub const PostLoad = strid.strId64(c.CT_KERNEL_PHASE_POSTLOAD);
pub const PreUpdate = strid.strId64(c.CT_KERNEL_PHASE_PREUPDATE);
pub const OnUpdate = strid.strId64(c.CT_KERNEL_PHASE_ONUPDATE);
pub const OnValidate = strid.strId64(c.CT_KERNEL_PHASE_ONVALIDATE);
pub const PostUpdate = strid.strId64(c.CT_KERNEL_PHASE_POSTUPDATE);
pub const PreStore = strid.strId64(c.CT_KERNEL_PHASE_PRESTORE);
pub const OnStore = strid.strId64(c.CT_KERNEL_PHASE_ONSTORE);

// Create Kernel task interface.
// You can implement init andor shutdown that is call only on main init/shutdown
pub const KernelTaskI = extern struct {
    pub const c_name = "ct_kernel_task_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [*:0]const u8,
    depends: [*]const strid.StrId64,
    depends_n: u64,
    init: ?*const fn (main_db: *cdb.Db) callconv(.C) void,
    shutdown: ?*const fn () callconv(.C) void,

    pub inline fn implement(
        name: [*c]const u8,
        depends: []const strid.StrId64,
        comptime T: type,
    ) KernelTaskI {
        if (!std.meta.hasFn(T, "init")) @compileError("implement me");
        if (!std.meta.hasFn(T, "shutdown")) @compileError("implement me");

        return KernelTaskI{
            .name = name,
            .depends = depends.ptr,
            .depends_n = depends.len,

            .init = struct {
                pub fn f(main_db: *cdb.Db) callconv(.C) void {
                    T.init(main_db) catch undefined;
                }
            }.f,

            .shutdown = struct {
                pub fn f() callconv(.C) void {
                    T.shutdown() catch undefined;
                }
            }.f,
        };
    }
};

// Create Kernel update task interface.
// You must implement update that is call every kernel main loop.
pub const KernelTaskUpdateI = extern struct {
    pub const c_name = "ct_kernel_task_update_i";
    pub const name_hash = strid.strId64(@This().c_name);

    phase: strid.StrId64,
    name: [*:0]const u8,
    depends: [*]const strid.StrId64,
    depends_n: u64,
    update: *const fn (frame_allocator: *const std.mem.Allocator, main_db: *cdb.Db, kernel_tick: u64, dt: f32) callconv(.C) void,

    pub inline fn implment(
        phase: strid.StrId64,
        name: [:0]const u8,
        depends: []const strid.StrId64,
        update: *const fn (frame_allocator: std.mem.Allocator, main_db: *cdb.Db, kernel_tick: u64, dt: f32) anyerror!void,
    ) KernelTaskUpdateI {
        return KernelTaskUpdateI{
            .phase = phase,
            .name = name,
            .depends = depends.ptr,
            .depends_n = depends.len,
            .update = struct {
                pub fn f(frame_allocator: *const std.mem.Allocator, main_db: *cdb.Db, kernel_tick: u64, dt: f32) callconv(.C) void {
                    update(frame_allocator.*, main_db, kernel_tick, dt) catch undefined;
                }
            }.f,
        };
    }
};

/// Main cetech entry point.
/// Boot the cetech and start main loop.
pub extern fn cetech1_kernel_boot(static_modules: ?[*]c.c.ct_module_desc_t, static_modules_n: u32) u8;

pub const KernelApi = struct {
    quit: *const fn () void,
    setCanQuit: *const fn (can_quit: *const fn () bool) void,

    getKernelTickRate: *const fn () u32,
    setKernelTickRate: *const fn (rate: u32) void,

    restart: *const fn (asset_root: ?[]const u8) void,
};
