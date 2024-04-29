const std = @import("std");

pub const log = @import("log.zig");
pub const mem = @import("mem.zig");
pub const strid = @import("strid.zig");
pub const dag = @import("dag.zig");
pub const uuid = @import("uuid.zig");
pub const tempalloc = @import("tempalloc.zig");
pub const profiler = @import("profiler.zig");
pub const zmath = @import("zmath");

pub const platform = @import("platform.zig");
pub const apidb = @import("apidb.zig");
pub const modules = @import("modules.zig");
pub const kernel = @import("kernel.zig");
pub const task = @import("task.zig");
pub const cdb = @import("cdb.zig");
pub const cdb_types = @import("cdb_types.zig");

pub const assetdb = @import("assetdb.zig");
pub const gpu = @import("gpu.zig");
pub const gfx = @import("gfx.zig");
pub const coreui = @import("coreui.zig");

pub const ecs = @import("ecs.zig");
pub const primitives = @import("primitives.zig");

test {
    // TODO: SHIT
    @setEvalBranchQuota(100000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
