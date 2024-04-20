const std = @import("std");

pub const c = @import("c.zig").c;

pub const mem = @import("mem.zig");
pub const strid = @import("strid.zig");
pub const dag = @import("dag.zig");
pub const uuid = @import("uuid.zig");

pub const profiler = @import("profiler.zig");
pub const log = @import("log.zig");
pub const apidb = @import("apidb.zig");
pub const assetdb = @import("assetdb.zig");
pub const modules = @import("modules.zig");
pub const kernel = @import("kernel.zig");
pub const task = @import("task.zig");
pub const cdb = @import("cdb.zig");
pub const cdb_types = @import("cdb_types.zig");
pub const tempalloc = @import("tempalloc.zig");

pub const system = @import("system.zig");

pub const gpu = @import("gpu.zig");
pub const gfx = @import("gfx.zig");
pub const gfxdd = @import("gfxdd.zig");
pub const gfxrg = @import("gfxrg.zig");

pub const coreui = @import("coreui.zig");

pub const zm = @import("zmath");

test {
    // TODO: SHIT
    @setEvalBranchQuota(100000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
