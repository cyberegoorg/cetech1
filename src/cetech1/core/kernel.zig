//! Kernel is entry point/runner for engine.

const std = @import("std");
const ztracy = @import("ztracy");

const c = @import("c.zig");
const stringid = @import("stringid.zig");

pub const OnLoad = stringid.strId64(c.c.CT_KERNEL_PHASE_ONLOAD);
pub const PostLoad = stringid.strId64(c.c.CT_KERNEL_PHASE_POSTLOAD);
pub const PreUpdate = stringid.strId64(c.c.CT_KERNEL_PHASE_PREUPDATE);
pub const OnUpdate = stringid.strId64(c.c.CT_KERNEL_PHASE_ONUPDATE);
pub const OnValidate = stringid.strId64(c.c.CT_KERNEL_PHASE_ONVALIDATE);
pub const PostUpdate = stringid.strId64(c.c.CT_KERNEL_PHASE_POSTUPDATE);
pub const PreStore = stringid.strId64(c.c.CT_KERNEL_PHASE_PRESTORE);
pub const OnStore = stringid.strId64(c.c.CT_KERNEL_PHASE_ONSTORE);

pub inline fn KernelTaskInterface(name: [*c]const u8, depends: []const stringid.StrId64, init: ?*const fn () callconv(.C) void, shutdown: ?*const fn () callconv(.C) void) c.c.ct_kernel_task_i {
    return c.c.ct_kernel_task_i{
        .name = name,
        .depends = depends.ptr,
        .depends_n = depends.len,
        .init = init,
        .shutdown = shutdown,
    };
}

pub inline fn KernelTaskUpdateInterface(phase: stringid.StrId64, name: [*c]const u8, depends: []const stringid.StrId64, update: ?*const fn (u64, f32) callconv(.C) void) c.c.ct_kernel_task_update_i {
    return c.c.ct_kernel_task_update_i{
        .phase = phase,
        .name = name,
        .depends = depends.ptr,
        .depends_n = depends.len,
        .update = update,
    };
}

pub extern fn cetech1_kernel_boot(static_modules: ?[*]c.c.ct_module_desc_t, static_modules_n: u32) u8;
