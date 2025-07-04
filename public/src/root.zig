const std = @import("std");

pub const log = @import("log.zig");
pub const heap = @import("heap.zig");
pub const dag = @import("dag.zig");
pub const uuid = @import("uuid.zig");
pub const tempalloc = @import("tempalloc.zig");
pub const profiler = @import("profiler.zig");
pub const metrics = @import("metrics.zig");
pub const math = @import("math.zig");

pub const platform = @import("platform.zig");
pub const apidb = @import("apidb.zig");
pub const modules = @import("modules.zig");
pub const kernel = @import("kernel.zig");
pub const task = @import("task.zig");
pub const cdb = @import("cdb.zig");
pub const cdb_types = @import("cdb_types.zig");
pub const assetdb = @import("assetdb.zig");
pub const ecs = @import("ecs.zig");
pub const gpu = @import("gpu.zig");

// TODO: to module (need platform based appi aka backed)
pub const coreui = @import("coreui.zig");
pub const coreui_node_editor = @import("coreui_node_editor.zig");

pub const actions = @import("actions.zig");

// BitSet
pub const StaticBitSet = std.StaticBitSet;
pub const DynamicBitSet = std.DynamicBitSetUnmanaged;

// List
pub const ArrayList = std.ArrayListUnmanaged;
pub const ByteList = ArrayList(u8);

// HashMap
pub const AutoArrayHashMap = std.AutoArrayHashMapUnmanaged;
pub const AutoHashMap = std.AutoHashMapUnmanaged;
pub const StringHashMap = std.StringHashMapUnmanaged;

// Sets
const ziglangSet = @import("ziglangSet");
pub const ArraySet = ziglangSet.ArraySetUnmanaged;
pub const HashSet = ziglangSet.HashSetUnmanaged;

// Queues
const queues = @import("queue.zig");
pub const MPMCBoundedQueue = queues.MPMCBoundedQueue;
pub const QueueWithLock = queues.QueueWithLock;

// Strings
pub const string = @import("string.zig");
pub const StrId32 = string.StrId32;
pub const StrId64 = string.StrId64;
pub const StrId32List = string.StrId32List;
pub const StrId64List = string.StrId64List;
pub const strId32 = string.strId32;
pub const strId64 = string.strId64;

test {
    // TODO: SHIT
    @setEvalBranchQuota(100000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
