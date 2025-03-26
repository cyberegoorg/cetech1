const std = @import("std");

// List
pub const ArrayList = std.ArrayListUnmanaged;

// HashMap
pub const AutoArrayHashMap = std.AutoArrayHashMapUnmanaged;
pub const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;

// Sets
const ziglangSet = @import("ziglangSet");
pub const ArraySet = ziglangSet.ArraySetUnmanaged;
pub const HashSet = ziglangSet.HashSetUnmanaged;

// Queues
const queues = @import("queue.zig");
pub const MPMCBoundedQueue = queues.MPMCBoundedQueue;
pub const QueueWithLock = queues.QueueWithLock;

// StrId
const strid = @import("strid.zig");
pub const StrId32 = strid.StrId32;
pub const StrId64 = strid.StrId64;
pub const strId32 = strid.strId32;
pub const strId64 = strid.strId64;

pub const log = @import("log.zig");
pub const heap = @import("heap.zig");
pub const dag = @import("dag.zig");
pub const uuid = @import("uuid.zig");
pub const tempalloc = @import("tempalloc.zig");
pub const profiler = @import("profiler.zig");
pub const metrics = @import("metrics.zig");
pub const math = @import("math.zig");
pub const primitives = @import("primitives.zig");

pub const platform = @import("platform.zig");
pub const apidb = @import("apidb.zig");
pub const modules = @import("modules.zig");
pub const kernel = @import("kernel.zig");
pub const task = @import("task.zig");
pub const cdb = @import("cdb.zig");
pub const cdb_types = @import("cdb_types.zig");
pub const assetdb = @import("assetdb.zig");
pub const gpu = @import("gpu.zig");
pub const ecs = @import("ecs.zig");

pub const coreui = @import("coreui.zig");
pub const coreui_node_editor = @import("coreui_node_editor.zig");

pub const actions = @import("actions.zig");

test {
    // TODO: SHIT
    @setEvalBranchQuota(100000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
