const std = @import("std");

pub const log = @import("kernel/log.zig");
pub const heap = @import("kernel/heap.zig");
pub const dag = @import("kernel/dag.zig");
pub const uuid = @import("kernel/uuid.zig");
pub const tempalloc = @import("kernel/tempalloc.zig");
pub const profiler = @import("kernel/profiler.zig");
pub const metrics = @import("kernel/metrics.zig");
pub const math = @import("kernel/math.zig");

pub const host = @import("kernel/host.zig");
pub const input = @import("kernel/input.zig");

pub const apidb = @import("kernel/apidb.zig");
pub const modules = @import("kernel/modules.zig");
pub const kernel = @import("kernel/kernel.zig");
pub const task = @import("kernel/task.zig");
pub const cdb = @import("kernel/cdb.zig");
pub const cdb_types = @import("kernel/cdb_types.zig");
pub const assetdb = @import("kernel/assetdb.zig");
pub const ecs = @import("ecs/ecs.zig");
pub const gpu = @import("kernel/gpu.zig");
pub const gpu_dd = @import("kernel/gpu_dd.zig");
pub const actions = @import("actions/actions.zig");

pub const camera = @import("camera/camera.zig");
pub const camera_controller = @import("camera/camera_controller.zig");
pub const transform = @import("transform/transform.zig");
pub const renderer = @import("renderer/renderer.zig");
pub const renderer_pipeline = @import("renderer_pipeline/renderer_pipeline.zig");
pub const editor = @import("editor/editor.zig");
pub const physics = @import("physics/physics.zig");

pub const scripting = @import("scripting/scripting.zig");

pub const coreui = @import("coreui/coreui.zig");
pub const coreui_node_editor = @import("coreui/coreui_node_editor.zig");

// BitSet
pub const StaticBitSet = std.StaticBitSet;
pub const DynamicBitSet = std.DynamicBitSet;

// List
pub const ArrayList = std.ArrayList;
pub const ByteList = ArrayList(u8);

// HashMap
pub const AutoArrayHashMap = std.AutoArrayHashMapUnmanaged;
pub const AutoHashMap = std.AutoHashMapUnmanaged;
pub const StringHashMap = std.StringHashMapUnmanaged;

// Sets
const ziglangSet = @import("ziglangSet");
pub const ArraySet = ziglangSet.ArraySet;
pub const HashSet = ziglangSet.HashSet;

// Queues
const queues = @import("kernel/queue.zig");
pub const MPMCBoundedQueue = queues.MPMCBoundedQueue;
pub const QueueWithLock = queues.QueueWithLock;

// Strings
pub const string = @import("kernel/string.zig");
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
