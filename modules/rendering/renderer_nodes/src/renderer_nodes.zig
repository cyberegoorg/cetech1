const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const zm = cetech1.math.zmath;

const transform = @import("transform");
const camera = @import("camera");
const shader_system = @import("shader_system");
const render_graph = @import("render_graph");

pub const RENDERER_KERNEL_TASK = cetech1.strId64("Renderer nodes");
pub const CULLING_VOLUME_NODE_TYPE_STR = "culling_volume";
pub const CULLING_VOLUME_NODE_TYPE = cetech1.strId32(CULLING_VOLUME_NODE_TYPE_STR);

pub const DRAW_CALL_NODE_TYPE_STR = "draw_call";
pub const DRAW_CALL_NODE_TYPE = cetech1.strId32(DRAW_CALL_NODE_TYPE_STR);

pub const SIMPLE_MESH_NODE_TYPE_STR = "simple_mesh";
pub const SIMPLE_MESH_NODE_TYPE = cetech1.strId32(SIMPLE_MESH_NODE_TYPE_STR);

pub const PinTypes = struct {
    pub const GPU_GEOMETRY = cetech1.strId32("gpu_geometry");
    pub const GPU_INDEX_BUFFER = cetech1.strId32("gpu_index_buffer");
};

// TODO: move
pub const SimpleMeshNodeSettings = cdb.CdbTypeDecl(
    "ct_gpu_simple_mesh_settings",
    enum(u32) {
        type,
    },
    struct {},
);

// TODO: move
pub const SimpleMeshNodeType = enum {
    cube,
    bunny,
};

pub const GPUGeometryCdb = cdb.CdbTypeDecl(
    "ct_gpu_geometry",
    enum(u32) {
        // handle0 = 0,
        // handle1,
        // handle2,
        // handle3,
    },
    struct {},
);

pub const GPUIndexBufferCdb = cdb.CdbTypeDecl(
    "ct_gpu_index_buffer",
    enum(u32) {
        handle = 0,
    },
    struct {},
);
