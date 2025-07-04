const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const shader_system = @import("shader_system");

pub const VertexActiveChannels = cetech1.StaticBitSet(32);

pub const VertexChannelsNames = struct {
    pub const Position = 0;
    pub const Color = 1;
};

pub const MAX_BUFFERS = 4;
pub const MAX_CHANNELS = 16;

pub const VertexChannel = struct {
    offset: u32 = 0,
    stride: u32 = 0,
    buffer_idx: u32 = 0,
};

pub const VertexBuffer = struct {
    active_channels: VertexActiveChannels = .initEmpty(),
    num_vertices: u32 = 0,
    num_sets: u32 = 0,
    buffers: [MAX_BUFFERS]gpu.VertexBufferHandle = @splat(.{}),
    channels: [MAX_CHANNELS]VertexChannel = @splat(.{}),
};

pub const GPUGeometry = struct {
    system: shader_system.System = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resources: ?shader_system.ResourceBufferInstance = null,
};

pub const VertexSystemApi = struct {
    createVertexSystemFromVertexBuffer: *const fn (vertex_buffer: VertexBuffer) anyerror!GPUGeometry,
};
