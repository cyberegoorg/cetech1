const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const math = cetech1.math;

const shader_system = @import("shader_system");
const vertex_system = @import("vertex_system");
const visibility_flags = @import("visibility_flags");

pub const RENDERER_KERNEL_TASK = .fromStr("Renderer nodes");
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

pub const CullingVolume = struct {
    min: math.Vec3f = .{},
    max: math.Vec3f = .{},
    radius: f32 = 0,

    pub fn hasBox(self: CullingVolume) bool {
        return !std.meta.eql(self.min, self.max);
    }

    pub fn hasSphere(self: CullingVolume) bool {
        return self.radius != 0;
    }

    pub fn hasAny(self: CullingVolume) bool {
        return self.hasBox() or self.hasSphere();
    }
};

// TODO: move
pub const SimpleMeshNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_gpu_simple_mesh_settings",
    enum(u32) {
        Type,
    },
    struct {},
);

// TODO: move
pub const SimpleMeshNodeType = enum {
    Cube,
    Bunny,
    Plane,
};

pub const DrawCallNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_draw_call_node_settings",
    enum(u32) {
        VisibilityFlags = 0,
    },
    struct {},
);

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
        Handle = 0,
    },
    struct {},
);

// TODO: move....
pub const DrawCall = struct {
    shader: ?shader_system.Shader = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resouces: ?shader_system.ResourceBufferInstance = null,

    geometry: ?vertex_system.GPUGeometry = null,
    index_buffer: ?gpu.IndexBufferHandle = null,

    vertex_count: u32 = 0,
    index_count: u32 = 0,

    visibility_mask: visibility_flags.VisibilityFlags,
    hash: u64 = 0,

    pub fn calcHash(self: *DrawCall) void {
        var h = std.hash.Wyhash.init(0);

        std.hash.autoHash(&h, self.shader);
        std.hash.autoHash(&h, self.resouces);
        std.hash.autoHash(&h, self.uniforms);
        std.hash.autoHash(&h, self.geometry);
        std.hash.autoHash(&h, self.index_buffer);
        std.hash.autoHash(&h, self.vertex_count);
        std.hash.autoHash(&h, self.index_count);
        std.hash.autoHash(&h, self.visibility_mask.mask);

        self.hash = h.final();
    }
};
