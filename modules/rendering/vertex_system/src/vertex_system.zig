const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const shader_system = @import("shader_system");

pub const VertexActiveChannels = cetech1.StaticBitSet(32);

pub const VertexChannelsNames = struct {
    pub const Position = 0;
    pub const Normal0 = 1;
    pub const Normal1 = 2;
    pub const Tangent0 = 3;
    pub const Tangent1 = 4;
    pub const SkinIndices0 = 5;
    pub const SkinIndices1 = 6;
    pub const SkinBones0 = 7;
    pub const SkinBones1 = 8;
    pub const Textcoord0 = 9;
    pub const Textcoord1 = 10;
    pub const Textcoord2 = 11;
    pub const Textcoord3 = 12;
    pub const Color0 = 13;
    pub const Color1 = 14;
};

pub const MAX_BUFFERS = 4;
pub const MAX_CHANNELS = 16;

pub const VertexChannel = struct {
    offset: u32 = 0,
    stride: u32 = 0,
    buffer: shader_system.BufferHandle = .{ .vb = .{ .idx = 0 } },
};

pub const VertexBuffer = struct {
    active_channels: VertexActiveChannels = .initEmpty(),
    num_vertices: u32 = 0,
    num_sets: u32 = 0,
    primitive_type: shader_system.PrimitiveType = .triangles,
    channels: [MAX_CHANNELS]VertexChannel = @splat(.{}),
};

pub const GPUGeometry = struct {
    primitive_type: shader_system.PrimitiveType = .triangles,
    system: shader_system.System = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resources: ?shader_system.ResourceBufferInstance = null,
};

pub const VertexSystemApi = struct {
    createVertexSystemFromVertexBuffer: *const fn (allocator: std.mem.Allocator, vertex_buffer: VertexBuffer) anyerror!GPUGeometry,
};
