//! Kernel is entry point/runner for engine.

const std = @import("std");
const ztracy = @import("ztracy");

const c = @import("c.zig");
const strid = @import("strid.zig");
const log = @import("log.zig");
const modules = @import("modules.zig");

pub const OnLoad = strid.strId64(c.c.CT_KERNEL_PHASE_ONLOAD);
pub const PostLoad = strid.strId64(c.c.CT_KERNEL_PHASE_POSTLOAD);
pub const PreUpdate = strid.strId64(c.c.CT_KERNEL_PHASE_PREUPDATE);
pub const OnUpdate = strid.strId64(c.c.CT_KERNEL_PHASE_ONUPDATE);
pub const OnValidate = strid.strId64(c.c.CT_KERNEL_PHASE_ONVALIDATE);
pub const PostUpdate = strid.strId64(c.c.CT_KERNEL_PHASE_POSTUPDATE);
pub const PreStore = strid.strId64(c.c.CT_KERNEL_PHASE_PRESTORE);
pub const OnStore = strid.strId64(c.c.CT_KERNEL_PHASE_ONSTORE);

// Create Kernel task interface.
// You can implement init andor shutdown that is call only on main init/shutdown
pub inline fn KernelTaskInterface(
    name: [*c]const u8,
    depends: []const strid.StrId64,
    init: ?*const fn (main_db: ?*c.c.ct_cdb_db_t) anyerror!void,
    shutdown: ?*const fn () anyerror!void,
) c.c.ct_kernel_task_i {
    const Wrap = struct {
        pub fn init_fn(main_db: ?*c.c.ct_cdb_db_t) callconv(.C) void {
            init.?(main_db) catch undefined;
        }

        pub fn shutdown_fn() callconv(.C) void {
            shutdown.?() catch undefined;
        }
    };

    return c.c.ct_kernel_task_i{
        .name = name,
        .depends = @ptrCast(depends.ptr),
        .depends_n = depends.len,
        .init = if (init != null) Wrap.init_fn else null,
        .shutdown = if (shutdown != null) Wrap.shutdown_fn else null,
    };
}

// Create Kernel update task interface.
// You must implement update that is call every kernel main loop.
pub inline fn KernelTaskUpdateInterface(
    phase: strid.StrId64,
    name: [:0]const u8,
    depends: []const strid.StrId64,
    update: *const fn (frame_allocator: std.mem.Allocator, main_db: ?*c.c.ct_cdb_db_t, u64, f32) anyerror!void,
) c.c.ct_kernel_task_update_i {
    const Wrap = struct {
        pub fn update_fn(frame_allocator: ?*c.c.ct_allocator_t, main_db: ?*c.c.ct_cdb_db_t, kernel_tick: u64, dt: f32) callconv(.C) void {
            update(modules.allocFromCApi(frame_allocator.?), main_db, kernel_tick, dt) catch undefined;
        }
    };

    return c.c.ct_kernel_task_update_i{
        .phase = phase.to(c.c.struct_ct_strid64_t),
        .name = name,
        .depends = @ptrCast(depends.ptr),
        .depends_n = depends.len,
        .update = Wrap.update_fn,
    };
}

/// Main cetech entry point.
/// Boot the cetech and start main loop.
pub extern fn cetech1_kernel_boot(static_modules: ?[*]c.c.ct_module_desc_t, static_modules_n: u32) u8;

pub const KernelApi = struct {
    quit: *const fn () void,
    setCanQuit: *const fn (can_quit: *const fn () bool) void,

    getKernelTickRate: *const fn () u32,
    setKernelTickRate: *const fn (rate: u32) void,
};
