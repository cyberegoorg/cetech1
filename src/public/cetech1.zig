const std = @import("std");

pub const log = @import("log.zig");
pub const heap = @import("heap.zig");
pub const dag = @import("dag.zig");
pub const uuid = @import("uuid.zig");
pub const tempalloc = @import("tempalloc.zig");
pub const profiler = @import("profiler.zig");
pub const metrics = @import("metrics.zig");
pub const math = @import("math.zig");

pub const host = @import("host.zig");
pub const input = @import("input.zig");

pub const apidb = @import("apidb.zig");
pub const modules = @import("modules.zig");
pub const kernel = @import("kernel.zig");
pub const task = @import("task.zig");
pub const cdb = @import("cdb.zig");
pub const cdb_types = @import("cdb_types.zig");
pub const assetdb = @import("assetdb.zig");
pub const ecs = @import("ecs.zig");
pub const gpu = @import("gpu.zig");
pub const gpu_dd = @import("gpu_dd.zig");
pub const camera = @import("camera/camera.zig");
pub const camera_controller = @import("camera/camera_controller.zig");
pub const actions = @import("actions.zig");
pub const transform = @import("transform.zig");
pub const renderer = @import("renderer.zig");
pub const renderer_pipeline = @import("renderer_pipeline.zig");
pub const editor = @import("editor.zig");
pub const physics = @import("physics.zig");
pub const graphvm = @import("scripting/graphvm.zig");
pub const graphvm_script_component = @import("scripting/graphvm_script_component.zig");
pub const native_script_component = @import("scripting/native_script_component.zig");

pub const luauvm = @import("scripting/luauvm.zig");
pub const luauvm_script_component = @import("scripting/luauvm_script_component.zig");

pub const coreui = @import("coreui.zig");
pub const coreui_node_editor = @import("coreui_node_editor.zig");

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
