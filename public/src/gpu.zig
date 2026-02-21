const std = @import("std");
const cetech1 = @import("root.zig");
const host = @import("host.zig");
const math = cetech1.math;

const apidb = cetech1.apidb;

// new
// TODO: generic with isValid. (like 0 as null, but bgfx use std.math.maxInt(c_ushort))
pub fn Handler() type {
    return extern struct {
        idx: c_ushort = std.math.maxInt(c_ushort),

        pub fn isValid(handler: @This()) bool {
            return handler.idx != std.math.maxInt(c_ushort);
        }
    };
}

pub const DynamicIndexBufferHandle = Handler();
pub const DynamicVertexBufferHandle = Handler();
pub const FrameBufferHandle = Handler();
pub const IndexBufferHandle = Handler();
pub const IndirectBufferHandle = Handler();
pub const OcclusionQueryHandle = Handler();
pub const ProgramHandle = Handler();
pub const ShaderHandle = Handler();
pub const TextureHandle = Handler();
pub const UniformHandle = Handler();
pub const VertexBufferHandle = Handler();
pub const VertexLayoutHandle = Handler();

pub const CubeMapSide = enum(u8) {
    /// Cubemap +x.
    PositiveX = 0,

    /// Cubemap -x.
    NegativeX,

    /// Cubemap +y.
    PositiveY,

    /// Cubemap -y.
    NegativeY,

    /// Cubemap +z.
    PositiveZ,

    /// Cubemap -z.
    NegativeZ,
};

pub const RenderFrame = enum(c_int) {
    /// Renderer context is not created yet.
    NoContext,

    /// Renderer context is created and rendering.
    Render,

    /// Renderer context wait for main thread signal timed out without rendering.
    Timeout,

    /// Renderer context is getting destroyed.
    Exiting,

    Count,
};

pub const FrameFlags = struct {
    debug_capture: bool = false,
    discard: bool = false,
};

pub const DebugFlags = struct {
    /// Enable wireframe for all
    wireframe: bool = false,

    /// Enable infinitely fast hardware test. No draw calls will be submitted to driver.
    /// It's useful when profiling to quickly assess bottleneck between CPU and
    ifh: bool = false,

    /// Enable statistics display.
    stats: bool = false,

    /// Enable debug text display.
    text: bool = false,

    /// Enable profiler. This causes per-view statistics to be collected, available through `ViewStats`..
    profiler: bool = false,
};

pub const ViewId = u16;

pub const ViewMode = enum(c_int) {
    /// Default sort order.
    Default,

    /// Sort in the same order in which submit calls were called.
    Sequential,

    /// Sort draw call depth in ascending order.
    DepthAscending,

    /// Sort draw call depth in descending order.
    DepthDescending,

    Count,
};

const ResetFlagsMsaa = enum {
    X2,
    X4,
    X8,
    X16,
};

pub const ResetFlags = struct {
    msaa: ?ResetFlagsMsaa = null,

    /// Not supported yet.
    fullscreen: bool = false,

    /// Enable V-Sync.
    vsync: bool = false,

    /// Turn on/off max anisotropy.
    maxanisotropy: bool = false,

    /// Begin screen capture.
    capture: bool = false,

    /// Flush rendering after submitting to
    flush_after_render: bool = false,

    /// This flag specifies where flip occurs. Default behaviour is that flip occurs
    /// before rendering new frame. This flag only has effect when `CONFIG_MULTITHREADED=0`.
    flip_after_render: bool = false,

    /// Enable sRGB backbuffer.
    srgb_backbuffer: bool = false,

    /// Enable HDR10 rendering.
    hdr10: bool = false,

    /// Enable HiDPI rendering.
    hidpi: bool = false,

    /// Enable depth clamp.
    depth_clamp: bool = false,

    /// Suspend rendering.
    @"suspend": bool = false,

    /// Transparent backbuffer. Availability depends on: `CAPS_TRANSPARENT_BACKBUFFER`.
    transparent_backbuffer: bool = false,
};

pub const ClearFlags = struct {
    /// Clear color.
    color: bool = false,

    /// Clear depth.
    depth: bool = false,

    /// Clear stencil.
    stencil: bool = false,

    /// Discard frame buffer attachment 0.
    discard_color0: bool = false,

    /// Discard frame buffer attachment 1.
    discard_color1: bool = false,

    /// Discard frame buffer attachment 2.
    discard_color2: bool = false,

    /// Discard frame buffer attachment 3.
    discard_color3: bool = false,

    /// Discard frame buffer attachment 4.
    discard_color4: bool = false,

    /// Discard frame buffer attachment 5.
    discard_color5: bool = false,

    /// Discard frame buffer attachment 6.
    discard_color6: bool = false,

    /// Discard frame buffer attachment 7.
    discard_color7: bool = false,

    /// Discard frame buffer depth attachment.
    discard_depth: bool = false,

    /// Discard frame buffer stencil attachment.
    discard_stencil: bool = false,
};

pub const DiscardFlags = struct {
    pub const all = DiscardFlags{
        .bindings = true,
        .index_buffer = true,
        .state = true,
        .transform = true,
        .vertex_streams = true,
    };

    /// Discard texture sampler and buffer bindings.
    bindings: bool = false,

    /// Discard index buffer.
    index_buffer: bool = false,

    /// Discard state and uniform bindings.
    state: bool = false,

    /// Discard transform.
    transform: bool = false,

    /// Discard vertex streams.
    vertex_streams: bool = false,
};

pub const Access = enum(c_int) {
    /// Read.
    Read,

    /// Write.
    Write,

    /// Read and write.
    ReadWrite,

    Count,
};

pub const Attrib = enum(c_int) {
    /// a_position
    Position,

    /// a_normal
    Normal,

    /// a_tangent
    Tangent,

    /// a_bitangent
    Bitangent,

    /// a_color0
    Color0,

    /// a_color1
    Color1,

    /// a_color2
    Color2,

    /// a_color3
    Color3,

    /// a_indices
    Indices,

    /// a_weight
    Weight,

    /// a_texcoord0
    TexCoord0,

    /// a_texcoord1
    TexCoord1,

    /// a_texcoord2
    TexCoord2,

    /// a_texcoord3
    TexCoord3,

    /// a_texcoord4
    TexCoord4,

    /// a_texcoord5
    TexCoord5,

    /// a_texcoord6
    TexCoord6,

    /// a_texcoord7
    TexCoord7,

    Count,
};

pub const AttribType = enum(c_int) {
    /// Int8
    Int8,

    /// Uint8
    Uint8,

    /// Uint10, availability depends on: `CAPS_VERTEX_ATTRIB_UINT10`.
    Uint10,

    /// Int16
    Int16,

    /// UInt16
    UInt16,

    /// Half, availability depends on: `CAPS_VERTEX_ATTRIB_HALF`.
    Half,

    /// Float
    Float,

    Count,
};

pub const UniformType = enum(c_int) {
    /// Sampler.
    Sampler,

    /// Reserved, do not use.
    End,

    /// 4 floats vector.
    Vec4,

    /// 3x3 matrix.
    Mat3,

    /// 4x4 matrix.
    Mat4,

    Count,
};

pub const BufferHandle = union(enum) {
    vb: VertexBufferHandle,
    dvb: DynamicVertexBufferHandle,

    ib: IndexBufferHandle,
    dib: DynamicIndexBufferHandle,
};

pub const BufferComputeFormat = enum {
    X8x1,
    X8x2,
    X8x4,
    X16x1,
    X16x2,
    X16x4,
    X32x1,
    X32x2,
    X32x4,
};

pub const BufferComputeType = enum {
    int,
    uint,
    float,
};

pub const BufferComputeAcces = enum {
    read,
    write,
    read_write,
};

pub const BufferFlags = struct {
    compute_format: ?BufferComputeFormat = null,
    compute_type: ?BufferComputeType = null,
    compute_access: ?BufferComputeAcces = null,
    draw_indirect: bool = false,
    allow_resize: bool = false,
    index_32: bool = false,
};

pub const PrimitiveType = enum {
    Triangles,
    TrianglesStrip,
    Lines,
    LinesStrip,
    Points,
};

pub const CullMode = enum {
    None,
    Front,
    Back,
};

pub const FrontFace = enum {
    Cw,
    Ccw,
};

pub const RasterState = struct {
    cullmode: ?CullMode = null,
    front_face: ?FrontFace = null,
};

pub const DepthComapareOp = enum {
    Never,
    Less,
    Equal,
    LessEqual,
    Greater,
    NotEqual,
    GreaterEqual,
};

pub const DepthStencilState = struct {
    depth_test_enable: ?bool = null,
    depth_write_enable: ?bool = null,
    depth_comapre_op: ?DepthComapareOp = null,
};

pub const ColorState = struct {
    pub const rgb = ColorState{ .write_r = true, .write_g = true, .write_b = true, .write_a = false };
    pub const rgba = ColorState{ .write_r = true, .write_g = true, .write_b = true, .write_a = true };
    pub const only_a = ColorState{ .write_r = false, .write_g = false, .write_b = false, .write_a = true };

    write_r: ?bool = null,
    write_g: ?bool = null,
    write_b: ?bool = null,
    write_a: ?bool = null,
};

pub const BlendEquation = enum {
    /// Blend add: src + dst.
    Add,

    /// Blend subtract: src - dst.
    Sub,

    /// Blend reverse subtract: dst - src.
    Revsub,

    /// Blend min: min(src, dst).
    Min,

    /// Blend max: max(src, dst).
    Max,
};

pub const BlendFunction = enum {
    // 0, 0, 0, 0
    Zero,

    // 1, 1, 1, 1
    One,

    // Rs, Gs, Bs, As
    Src_color,

    // 1-Rs, 1-Gs, 1-Bs, 1-As
    Inv_src_color,

    // As, As, As, As
    Src_alpha,

    // 1-As, 1-As, 1-As, 1-As
    Inv_src_alpha,

    // Ad, Ad, Ad, Ad
    Dst_alpha,

    // 1-Ad, 1-Ad, 1-Ad ,1-Ad
    Inv_dst_alpha,

    // Rd, Gd, Bd, Ad
    Dst_color,

    // 1-Rd, 1-Gd, 1-Bd, 1-Ad
    Inv_dst_color,

    // f, f, f, 1; f = min(As, 1-Ad)
    Src_alpha_sat,
};

pub const BlendState = struct {
    color_equation: ?BlendEquation = null,
    source_color_factor: ?BlendFunction = null,
    destination_color_factor: ?BlendFunction = null,
    alpha_equation: ?BlendEquation = null,
    source_alpha_factor: ?BlendFunction = null,
    destination_alpha_factor: ?BlendFunction = null,
};

pub const SamplerCompare = enum {
    Less,
    Lequal,
    Equal,
    Gequal,
    Greater,
    Notequal,
    Never,
    Always,
};

pub const SamplerMinFilter = enum {
    Point,
    Linear,
};

pub const SamplerMaxFilter = enum {
    Point,
    Linear,
};

pub const SamplerMipPoint = enum {
    Point,
    Linear,
};

pub const SamplerAdressMode = enum {
    Wrap,
    Clamp,
    Border,
};

pub const SamplerFlags = struct {
    min_filter: ?SamplerMinFilter = null,
    max_filter: ?SamplerMaxFilter = null,
    mip_mode: ?SamplerMipPoint = null,
    u: ?SamplerAdressMode = null,
    v: ?SamplerAdressMode = null,
    w: ?SamplerAdressMode = null,
};

pub const RenderState = struct {
    raster_state: RasterState = .{},
    depth_stencil_state: DepthStencilState = .{},
    color_state: ColorState = .{},
    blend_state: BlendState = .{},
    primitive_type: PrimitiveType = .Triangles,
};

pub const RenderTargetTextureFlags = enum {
    NoRT,
    RT,
    MssaaX2,
    MssaaX4,
    MssaaX8,
    MssaaX16,
};

pub const TextureFormat = enum(c_int) {
    /// DXT1 R5G6B5A1
    BC1,

    /// DXT3 R5G6B5A4
    BC2,

    /// DXT5 R5G6B5A8
    BC3,

    /// LATC1/ATI1 R8
    BC4,

    /// LATC2/ATI2 RG8
    BC5,

    /// BC6H RGB16F
    BC6H,

    /// BC7 RGB 4-7 bits per color channel, 0-8 bits alpha
    BC7,

    /// ETC1 RGB8
    ETC1,

    /// ETC2 RGB8
    ETC2,

    /// ETC2 RGBA8
    ETC2A,

    /// ETC2 RGB8A1
    ETC2A1,

    /// EAC R11 UNORM
    EACR11,

    /// EAC R11 SNORM
    EACR11S,

    /// EAC RG11 UNORM
    EACRG11,

    /// EAC RG11 SNORM
    EACRG11S,

    /// PVRTC1 RGB 2BPP
    PTC12,

    /// PVRTC1 RGB 4BPP
    PTC14,

    /// PVRTC1 RGBA 2BPP
    PTC12A,

    /// PVRTC1 RGBA 4BPP
    PTC14A,

    /// PVRTC2 RGBA 2BPP
    PTC22,

    /// PVRTC2 RGBA 4BPP
    PTC24,

    /// ATC RGB 4BPP
    ATC,

    /// ATCE RGBA 8 BPP explicit alpha
    ATCE,

    /// ATCI RGBA 8 BPP interpolated alpha
    ATCI,

    /// ASTC 4x4 8.0 BPP
    ASTC4x4,

    /// ASTC 5x4 6.40 BPP
    ASTC5x4,

    /// ASTC 5x5 5.12 BPP
    ASTC5x5,

    /// ASTC 6x5 4.27 BPP
    ASTC6x5,

    /// ASTC 6x6 3.56 BPP
    ASTC6x6,

    /// ASTC 8x5 3.20 BPP
    ASTC8x5,

    /// ASTC 8x6 2.67 BPP
    ASTC8x6,

    /// ASTC 8x8 2.00 BPP
    ASTC8x8,

    /// ASTC 10x5 2.56 BPP
    ASTC10x5,

    /// ASTC 10x6 2.13 BPP
    ASTC10x6,

    /// ASTC 10x8 1.60 BPP
    ASTC10x8,

    /// ASTC 10x10 1.28 BPP
    ASTC10x10,

    /// ASTC 12x10 1.07 BPP
    ASTC12x10,

    /// ASTC 12x12 0.89 BPP
    ASTC12x12,

    /// Compressed formats above.
    Unknown,
    R1,
    A8,
    R8,
    R8I,
    R8U,
    R8S,
    R16,
    R16I,
    R16U,
    R16F,
    R16S,
    R32I,
    R32U,
    R32F,
    RG8,
    RG8I,
    RG8U,
    RG8S,
    RG16,
    RG16I,
    RG16U,
    RG16F,
    RG16S,
    RG32I,
    RG32U,
    RG32F,
    RGB8,
    RGB8I,
    RGB8U,
    RGB8S,
    RGB9E5F,
    BGRA8,
    RGBA8,
    RGBA8I,
    RGBA8U,
    RGBA8S,
    RGBA16,
    RGBA16I,
    RGBA16U,
    RGBA16F,
    RGBA16S,
    RGBA32I,
    RGBA32U,
    RGBA32F,
    B5G6R5,
    R5G6B5,
    BGRA4,
    RGBA4,
    BGR5A1,
    RGB5A1,
    RGB10A2,
    RG11B10F,

    /// Depth formats below.
    UnknownDepth,
    D16,
    D24,
    D24S8,
    D32,
    D16F,
    D24F,
    D32F,
    D0S8,

    Count,
};

pub const UniformFreq = enum(c_int) {
    /// Changing per draw call.
    Draw,

    /// Changing per view.
    View,

    /// Changing per frame.
    Frame,

    Count,
};

pub const ShadingRate = enum(c_int) {
    /// 1x1
    Rate1x1,

    /// 1x2
    Rate1x2,

    /// 2x1
    Rate2x1,

    /// 2x2
    Rate2x2,

    /// 2x4
    Rate2x4,

    /// 4x2
    Rate4x2,

    /// 4x4
    Rate4x4,

    Count,
};

pub const TextureFlags = struct {
    /// Texture will be used for MSAA sampling.
    msaa_sample: bool = false,

    /// Texture will be used for compute write.
    compute_write: bool = false,

    /// Sample texture as sRGB.
    srgb: bool = false,

    /// Texture will be used as blit destination.
    blit_dst: bool = false,

    /// Texture will be used for read back from
    read_back: bool = false,

    rt: RenderTargetTextureFlags = .NoRT,

    /// Render target will be used for writing
    rt_write_only: bool = false,
};

//

pub const GpuBackend = struct {
    pub fn getWindow(self: GpuBackend) ?host.Window {
        return self.api.getWindow(self.inst);
    }
    pub fn getResolution(self: GpuBackend) Resolution {
        return self.api.getResolution(self.inst);
    }
    pub fn addPaletteColor(self: GpuBackend, color: math.SRGBA) u8 {
        return self.api.addPaletteColor(self.inst, color);
    }
    pub fn endAllUsedEncoders(self: GpuBackend) void {
        return self.api.endAllUsedEncoders(self.inst);
    }
    pub fn isNoop(self: GpuBackend) bool {
        return self.api.isNoop(self.inst);
    }
    pub fn compileShader(self: GpuBackend, allocator: std.mem.Allocator, varying: []const u8, shader: []const u8, options: ShadercOptions) anyerror![]u8 {
        return self.api.compileShader(self.inst, allocator, varying, shader, options);
    }
    pub fn createDefaultShadercOptions(self: GpuBackend) ShadercOptions {
        return self.api.createDefaultShadercOptions(self.inst);
    }
    pub fn isHomogenousDepth(self: GpuBackend) bool {
        return self.api.isHomogenousDepth(self.inst);
    }
    pub fn isOriginBottomLeft(self: GpuBackend) bool {
        return self.api.isOriginBottomLeft(self.inst);
    }
    pub fn getNullVb(self: GpuBackend) VertexBufferHandle {
        return self.api.getNullVb(self.inst);
    }
    pub fn getFloatBufferLayout(self: GpuBackend) *const VertexLayout {
        return self.api.getFloatBufferLayout(self.inst);
    }
    pub fn reset(self: GpuBackend, _width: u32, _height: u32, _flags: ResetFlags, _format: TextureFormat) void {
        return self.api.reset(self.inst, _width, _height, _flags, _format);
    }
    pub fn frame(self: GpuBackend, _flags: FrameFlags) u32 {
        return self.api.frame(self.inst, _flags);
    }
    pub fn alloc(self: GpuBackend, _size: u32) *const Memory {
        return self.api.alloc(self.inst, _size);
    }
    pub fn copy(self: GpuBackend, _data: ?*const anyopaque, _size: u32) *const Memory {
        return self.api.copy(self.inst, _data, _size);
    }
    pub fn makeRef(self: GpuBackend, _data: ?*const anyopaque, _size: u32) *const Memory {
        return self.api.makeRef(self.inst, _data, _size);
    }
    pub fn makeRefRelease(self: GpuBackend, _data: ?*const anyopaque, _size: u32, _releaseFn: ?*anyopaque, _userData: ?*anyopaque) *const Memory {
        return self.api.makeRefRelease(self.inst, _data, _size, _releaseFn, _userData);
    }
    pub fn setDebug(self: GpuBackend, _debug: DebugFlags) void {
        return self.api.setDebug(self.inst, _debug);
    }
    pub fn dbgTextClear(self: GpuBackend, _attr: u8, _small: bool) void {
        return self.api.dbgTextClear(self.inst, _attr, _small);
    }
    pub fn dbgTextImage(self: GpuBackend, _x: u16, _y: u16, _width: u16, _height: u16, _data: ?*const anyopaque, _pitch: u16) void {
        return self.api.dbgTextImage(self.inst, _x, _y, _width, _height, _data, _pitch);
    }
    pub fn getEncoder(self: GpuBackend) ?GpuEncoder {
        return self.api.getEncoder(self.inst);
    }
    pub fn endEncoder(self: GpuBackend, encoder: GpuEncoder) void {
        return self.api.endEncoder(self.inst, encoder);
    }
    pub fn requestScreenShot(self: GpuBackend, _handle: FrameBufferHandle, _filePath: [*c]const u8) void {
        return self.api.requestScreenShot(self.inst, _handle, _filePath);
    }
    pub fn renderFrame(self: GpuBackend, _msecs: i32) RenderFrame {
        return self.api.renderFrame(self.inst, _msecs);
    }
    pub fn createIndexBuffer(self: GpuBackend, _mem: ?*const Memory, _flags: BufferFlags) IndexBufferHandle {
        return self.api.createIndexBuffer(self.inst, _mem, _flags);
    }
    pub fn setIndexBufferName(self: GpuBackend, _handle: IndexBufferHandle, _name: []const u8) void {
        return self.api.setIndexBufferName(self.inst, _handle, _name);
    }
    pub fn destroyIndexBuffer(self: GpuBackend, _handle: IndexBufferHandle) void {
        return self.api.destroyIndexBuffer(self.inst, _handle);
    }
    pub fn createVertexLayout(self: GpuBackend, _layout: *const VertexLayout) VertexLayoutHandle {
        return self.api.createVertexLayout(self.inst, _layout);
    }
    pub fn destroyVertexLayout(self: GpuBackend, _layoutHandle: VertexLayoutHandle) void {
        return self.api.destroyVertexLayout(self.inst, _layoutHandle);
    }
    pub fn createVertexBuffer(self: GpuBackend, _mem: ?*const Memory, _layout: *const VertexLayout, _flags: BufferFlags) VertexBufferHandle {
        return self.api.createVertexBuffer(self.inst, _mem, _layout, _flags);
    }
    pub fn setVertexBufferName(self: GpuBackend, _handle: VertexBufferHandle, _name: *const u8, _len: i32) void {
        return self.api.setVertexBufferName(self.inst, _handle, _name, _len);
    }
    pub fn destroyVertexBuffer(self: GpuBackend, _handle: VertexBufferHandle) void {
        return self.api.destroyVertexBuffer(self.inst, _handle);
    }
    pub fn createDynamicIndexBuffer(self: GpuBackend, _num: u32, _flags: u16) DynamicIndexBufferHandle {
        return self.api.createDynamicIndexBuffer(self.inst, _num, _flags);
    }
    pub fn createDynamicIndexBufferMem(self: GpuBackend, _mem: ?*const Memory, _flags: u16) DynamicIndexBufferHandle {
        return self.api.createDynamicIndexBufferMem(self.inst, _mem, _flags);
    }
    pub fn updateDynamicIndexBuffer(self: GpuBackend, _handle: DynamicIndexBufferHandle, _startIndex: u32, _mem: ?*const Memory) void {
        return self.api.updateDynamicIndexBuffer(self.inst, _handle, _startIndex, _mem);
    }
    pub fn destroyDynamicIndexBuffer(self: GpuBackend, _handle: DynamicIndexBufferHandle) void {
        return self.api.destroyDynamicIndexBuffer(self.inst, _handle);
    }
    pub fn createDynamicVertexBuffer(self: GpuBackend, _num: u32, _layout: *const VertexLayout, _flags: BufferFlags) DynamicVertexBufferHandle {
        return self.api.createDynamicVertexBuffer(self.inst, _num, _layout, _flags);
    }
    pub fn createDynamicVertexBufferMem(self: GpuBackend, _mem: ?*const Memory, _layout: *const VertexLayout, _flags: u16) DynamicVertexBufferHandle {
        return self.api.createDynamicVertexBufferMem(self.inst, _mem, _layout, _flags);
    }
    pub fn updateDynamicVertexBuffer(self: GpuBackend, _handle: DynamicVertexBufferHandle, _startVertex: u32, _mem: ?*const Memory) void {
        return self.api.updateDynamicVertexBuffer(self.inst, _handle, _startVertex, _mem);
    }
    pub fn destroyDynamicVertexBuffer(self: GpuBackend, _handle: DynamicVertexBufferHandle) void {
        return self.api.destroyDynamicVertexBuffer(self.inst, _handle);
    }
    pub fn getAvailTransientIndexBuffer(self: GpuBackend, _num: u32, _index32: bool) u32 {
        return self.api.getAvailTransientIndexBuffer(self.inst, _num, _index32);
    }
    pub fn getAvailTransientVertexBuffer(self: GpuBackend, _num: u32, _layout: *const VertexLayout) u32 {
        return self.api.getAvailTransientVertexBuffer(self.inst, _num, _layout);
    }
    pub fn allocTransientIndexBuffer(self: GpuBackend, _tib: [*c]TransientIndexBuffer, _num: u32, _index32: bool) void {
        return self.api.allocTransientIndexBuffer(self.inst, _tib, _num, _index32);
    }
    pub fn allocTransientVertexBuffer(self: GpuBackend, _tvb: [*c]TransientVertexBuffer, _num: u32, _layout: *const VertexLayout) void {
        return self.api.allocTransientVertexBuffer(self.inst, _tvb, _num, _layout);
    }
    pub fn allocTransientBuffers(self: GpuBackend, _tvb: [*c]TransientVertexBuffer, _layout: *const VertexLayout, _numVertices: u32, _tib: [*c]TransientIndexBuffer, _numIndices: u32, _index32: bool) bool {
        return self.api.allocTransientBuffers(self.inst, _tvb, _layout, _numVertices, _tib, _numIndices, _index32);
    }
    pub fn createIndirectBuffer(self: GpuBackend, _num: u32) IndirectBufferHandle {
        return self.api.createIndirectBuffer(self.inst, _num);
    }
    pub fn destroyIndirectBuffer(self: GpuBackend, _handle: IndirectBufferHandle) void {
        return self.api.destroyIndirectBuffer(self.inst, _handle);
    }
    pub fn createShader(self: GpuBackend, _mem: ?*const Memory) ShaderHandle {
        return self.api.createShader(self.inst, _mem);
    }
    pub fn getShaderUniforms(self: GpuBackend, _handle: ShaderHandle, _uniforms: [*c]UniformHandle, _max: u16) u16 {
        return self.api.getShaderUniforms(self.inst, _handle, _uniforms, _max);
    }
    pub fn setShaderName(self: GpuBackend, _handle: ShaderHandle, _name: []const u8) void {
        return self.api.setShaderName(self.inst, _handle, _name);
    }
    pub fn destroyShader(self: GpuBackend, _handle: ShaderHandle) void {
        return self.api.destroyShader(self.inst, _handle);
    }
    pub fn createProgram(self: GpuBackend, _vsh: ShaderHandle, _fsh: ShaderHandle, _destroyShaders: bool) ProgramHandle {
        return self.api.createProgram(self.inst, _vsh, _fsh, _destroyShaders);
    }
    pub fn createComputeProgram(self: GpuBackend, _csh: ShaderHandle, _destroyShaders: bool) ProgramHandle {
        return self.api.createComputeProgram(self.inst, _csh, _destroyShaders);
    }
    pub fn destroyProgram(self: GpuBackend, _handle: ProgramHandle) void {
        return self.api.destroyProgram(self.inst, _handle);
    }
    pub fn isTextureValid(self: GpuBackend, _depth: u16, _cubeMap: bool, _numLayers: u16, _format: TextureFormat, _flags: u64) bool {
        return self.api.isTextureValid(self.inst, _depth, _cubeMap, _numLayers, _format, _flags);
    }
    pub fn isFrameBufferValid(self: GpuBackend, _num: u8, _attachment: *const Attachment) bool {
        return self.api.isFrameBufferValid(self.inst, _num, _attachment);
    }
    pub fn calcTextureSize(self: GpuBackend, _info: [*c]TextureInfo, _width: u16, _height: u16, _depth: u16, _cubeMap: bool, _hasMips: bool, _numLayers: u16, _format: TextureFormat) void {
        return self.api.calcTextureSize(self.inst, _info, _width, _height, _depth, _cubeMap, _hasMips, _numLayers, _format);
    }
    pub fn createTexture(self: GpuBackend, _mem: ?*const Memory, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _skip: u8, _info: ?*TextureInfo) TextureHandle {
        return self.api.createTexture(self.inst, _mem, _flags, _sampler_flags, _skip, _info);
    }
    pub fn createTexture2D(self: GpuBackend, _width: u16, _height: u16, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _mem: ?*const Memory, _external: u64) TextureHandle {
        return self.api.createTexture2D(self.inst, _width, _height, _hasMips, _numLayers, _format, _flags, _sampler_flags, _mem, _external);
    }
    pub fn createTexture3D(self: GpuBackend, _width: u16, _height: u16, _depth: u16, _hasMips: bool, _format: TextureFormat, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _mem: ?*const Memory) TextureHandle {
        return self.api.createTexture3D(self.inst, _width, _height, _depth, _hasMips, _format, _flags, _sampler_flags, _mem);
    }
    pub fn createTextureCube(self: GpuBackend, _size: u16, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _mem: ?*const Memory, _external: u64) TextureHandle {
        return self.api.createTextureCube(self.inst, _size, _hasMips, _numLayers, _format, _flags, _sampler_flags, _mem, _external);
    }
    pub fn updateTexture2D(self: GpuBackend, _handle: TextureHandle, _layer: u16, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: ?*const Memory, _pitch: u16) void {
        return self.api.updateTexture2D(self.inst, _handle, _layer, _mip, _x, _y, _width, _height, _mem, _pitch);
    }
    pub fn updateTexture3D(self: GpuBackend, _handle: TextureHandle, _mip: u8, _x: u16, _y: u16, _z: u16, _width: u16, _height: u16, _depth: u16, _mem: ?*const Memory) void {
        return self.api.updateTexture3D(self.inst, _handle, _mip, _x, _y, _z, _width, _height, _depth, _mem);
    }
    pub fn updateTextureCube(self: GpuBackend, _handle: TextureHandle, _layer: u16, _side: CubeMapSide, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: ?*const Memory, _pitch: u16) void {
        return self.api.updateTextureCube(self.inst, _handle, _layer, _side, _mip, _x, _y, _width, _height, _mem, _pitch);
    }
    pub fn readTexture(self: GpuBackend, _handle: TextureHandle, _data: ?*anyopaque, _mip: u8) u32 {
        return self.api.readTexture(self.inst, _handle, _data, _mip);
    }
    pub fn setTextureName(self: GpuBackend, _handle: TextureHandle, _name: []const u8) void {
        return self.api.setTextureName(self.inst, _handle, _name);
    }
    pub fn getDirectAccessPtr(self: GpuBackend, _handle: TextureHandle) ?*anyopaque {
        return self.api.getDirectAccessPtr(self.inst, _handle);
    }
    pub fn destroyTexture(self: GpuBackend, _handle: TextureHandle) void {
        return self.api.destroyTexture(self.inst, _handle);
    }
    pub fn createFrameBuffer(self: GpuBackend, _width: u16, _height: u16, _format: TextureFormat, _textureFlags: u64) FrameBufferHandle {
        return self.api.createFrameBuffer(self.inst, _width, _height, _format, _textureFlags);
    }
    pub fn createFrameBufferScaled(self: GpuBackend, _ratio: BackbufferRatio, _format: TextureFormat, _textureFlags: u64) FrameBufferHandle {
        return self.api.createFrameBufferScaled(self.inst, _ratio, _format, _textureFlags);
    }
    pub fn createFrameBufferFromHandles(self: GpuBackend, _handles: []const TextureHandle, _destroyTexture: bool) FrameBufferHandle {
        return self.api.createFrameBufferFromHandles(self.inst, _handles, _destroyTexture);
    }
    pub fn createFrameBufferFromAttachment(self: GpuBackend, _attachment: []const Attachment, _destroyTexture: bool) FrameBufferHandle {
        return self.api.createFrameBufferFromAttachment(self.inst, _attachment, _destroyTexture);
    }
    pub fn createFrameBufferFromNwh(self: GpuBackend, _nwh: ?*anyopaque, _width: u16, _height: u16, _format: TextureFormat, _depthFormat: TextureFormat) FrameBufferHandle {
        return self.api.createFrameBufferFromNwh(self.inst, _nwh, _width, _height, _format, _depthFormat);
    }
    pub fn setFrameBufferName(self: GpuBackend, _handle: FrameBufferHandle, _name: []const u8) void {
        return self.api.setFrameBufferName(self.inst, _handle, _name);
    }
    pub fn getTexture(self: GpuBackend, _handle: FrameBufferHandle, _attachment: u8) TextureHandle {
        return self.api.getTexture(self.inst, _handle, _attachment);
    }
    pub fn destroyFrameBuffer(self: GpuBackend, _handle: FrameBufferHandle) void {
        return self.api.destroyFrameBuffer(self.inst, _handle);
    }
    pub fn createUniform(self: GpuBackend, _name: [:0]const u8, _type: UniformType, _num: u16) UniformHandle {
        return self.api.createUniform(self.inst, _name, _type, _num);
    }
    pub fn getUniformInfo(self: GpuBackend, _handle: UniformHandle, _info: [*c]UniformInfo) void {
        return self.api.getUniformInfo(self.inst, _handle, _info);
    }
    pub fn destroyUniform(self: GpuBackend, _handle: UniformHandle) void {
        return self.api.destroyUniform(self.inst, _handle);
    }
    pub fn createOcclusionQuery(self: GpuBackend) OcclusionQueryHandle {
        return self.api.createOcclusionQuery(self.inst);
    }
    pub fn getResult(self: GpuBackend, _handle: OcclusionQueryHandle, _result: [*c]i32) OcclusionQueryResult {
        return self.api.getResult(_handle, _result);
    }
    pub fn destroyOcclusionQuery(self: GpuBackend, _handle: OcclusionQueryHandle) void {
        return self.api.destroyOcclusionQuery(self.inst, _handle);
    }
    pub fn setViewName(self: GpuBackend, _id: ViewId, _name: []const u8) void {
        return self.api.setViewName(self.inst, _id, _name);
    }
    pub fn setViewRect(self: GpuBackend, _id: ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void {
        return self.api.setViewRect(self.inst, _id, _x, _y, _width, _height);
    }
    pub fn setViewRectRatio(self: GpuBackend, _id: ViewId, _x: u16, _y: u16, _ratio: BackbufferRatio) void {
        return self.api.setViewRectRatio(self.inst, _id, _x, _y, _ratio);
    }
    pub fn setViewScissor(self: GpuBackend, _id: ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void {
        return self.api.setViewScissor(self.inst, _id, _x, _y, _width, _height);
    }
    pub fn setViewClear(self: GpuBackend, _id: ViewId, _flags: ClearFlags, _rgba: u32, _depth: f32, _stencil: u8) void {
        return self.api.setViewClear(self.inst, _id, _flags, _rgba, _depth, _stencil);
    }
    pub fn setViewClearMrt(self: GpuBackend, _id: ViewId, _flags: ClearFlags, _depth: f32, _stencil: u8, _c0: u8, _c1: u8, _c2: u8, _c3: u8, _c4: u8, _c5: u8, _c6: u8, _c7: u8) void {
        return self.api.setViewClearMrt(self.inst, _id, _flags, _depth, _stencil, _c0, _c1, _c2, _c3, _c4, _c5, _c6, _c7);
    }
    pub fn setViewMode(self: GpuBackend, _id: ViewId, _mode: ViewMode) void {
        return self.api.setViewMode(self.inst, _id, _mode);
    }
    pub fn setViewFrameBuffer(self: GpuBackend, _id: ViewId, _handle: FrameBufferHandle) void {
        return self.api.setViewFrameBuffer(self.inst, _id, _handle);
    }
    pub fn setViewTransform(self: GpuBackend, _id: ViewId, _view: ?*const anyopaque, _proj: ?*const anyopaque) void {
        return self.api.setViewTransform(self.inst, _id, _view, _proj);
    }
    pub fn setViewOrder(self: GpuBackend, _id: ViewId, _num: u16, _order: *const ViewId) void {
        return self.api.setViewOrder(self.inst, _id, _num, _order);
    }
    pub fn resetView(self: GpuBackend, _id: ViewId) void {
        return self.api.resetView(self.inst, _id);
    }

    pub fn layoutBegin(sself: GpuBackend, self: *VertexLayout) *VertexLayout {
        return sself.api.layoutBegin(self);
    }
    pub fn layoutAdd(sself: GpuBackend, self: *VertexLayout, _attrib: Attrib, _num: u8, _type: AttribType, _normalized: bool, _asInt: bool) *VertexLayout {
        return sself.api.layoutAdd(self, _attrib, _num, _type, _normalized, _asInt);
    }
    pub fn layoutDecode(sself: GpuBackend, self: *const VertexLayout, _attrib: Attrib, _num: [*c]u8, _type: [*c]AttribType, _normalized: [*c]bool, _asInt: [*c]bool) void {
        return sself.api.layoutDecode(self, _attrib, _num, _type, _normalized, _asInt);
    }
    pub fn layoutHas(sself: GpuBackend, self: *const VertexLayout, _attrib: Attrib) bool {
        return sself.api.layoutHas(self, _attrib);
    }
    pub fn layoutSkip(sself: GpuBackend, self: *VertexLayout, _num: u8) *VertexLayout {
        return sself.api.layoutSkip(self, _num);
    }
    pub fn layoutEnd(sself: GpuBackend, self: *VertexLayout) void {
        return sself.api.layoutEnd(self);
    }

    pub fn getCoreUIProgram(self: GpuBackend) ProgramHandle {
        return self.api.getCoreUIProgram(self.inst);
    }

    pub fn getCoreUIImageProgram(self: GpuBackend) ProgramHandle {
        return self.api.getCoreUIImageProgram(self.inst);
    }

    pub fn getCoreShader(self: GpuBackend) []const u8 {
        return self.api.getCoreShader(self.inst);
    }

    inst: *anyopaque,
    api: *const GpuBackendApi,
};

pub const GpuBackendI = struct {
    const Self = @This();
    pub const c_name = "ct_gpu_backend_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: []const u8,

    isDefault: *const fn (backend: []const u8, headles: bool) bool,

    createBackend: *const fn (
        window: ?host.Window,
        backend: []const u8,
        vsync: bool,
        headles: bool,
        debug: bool,
        profile: bool,
    ) anyerror!GpuBackend,
};

pub const GpuBackendApi = struct {
    pub fn implement(comptime T: type) GpuBackendApi {
        return GpuBackendApi{
            .destroyBackend = T.destroyBackend,
            .isNoop = T.isNoop,
            .getWindow = T.getWindow,
            .getResolution = T.getResolution,
            .addPaletteColor = T.addPaletteColor,
            .endAllUsedEncoders = T.endAllUsedEncoders,
            .compileShader = T.compileShader,
            .createDefaultShadercOptions = T.createDefaultOptionsForRenderer,
            .isHomogenousDepth = T.isHomogenousDepth,
            .isOriginBottomLeft = T.isOriginBottomLeft,
            .getNullVb = T.getNullVb,
            .getFloatBufferLayout = T.getFloatBufferLayout,
            .reset = T.reset,
            .frame = T.frame,
            .alloc = T.alloc,
            .copy = T.copy,
            .makeRef = T.makeRef,
            .makeRefRelease = T.makeRefRelease,
            .setDebug = T.setDebug,
            .dbgTextClear = T.dbgTextClear,
            .dbgTextImage = T.dbgTextImage,
            .getEncoder = T.getEncoder,
            .endEncoder = T.endEncoder,
            .requestScreenShot = T.requestScreenShot,
            .renderFrame = T.renderFrame,
            .createIndexBuffer = T.createIndexBuffer,
            .setIndexBufferName = T.setIndexBufferName,
            .destroyIndexBuffer = T.destroyIndexBuffer,
            .createVertexLayout = T.createVertexLayout,
            .destroyVertexLayout = T.destroyVertexLayout,
            .createVertexBuffer = T.createVertexBuffer,
            .setVertexBufferName = T.setVertexBufferName,
            .destroyVertexBuffer = T.destroyVertexBuffer,
            .createDynamicIndexBuffer = T.createDynamicIndexBuffer,
            .createDynamicIndexBufferMem = T.createDynamicIndexBufferMem,
            .updateDynamicIndexBuffer = T.updateDynamicIndexBuffer,
            .destroyDynamicIndexBuffer = T.destroyDynamicIndexBuffer,
            .createDynamicVertexBuffer = T.createDynamicVertexBuffer,
            .createDynamicVertexBufferMem = T.createDynamicVertexBufferMem,
            .updateDynamicVertexBuffer = T.updateDynamicVertexBuffer,
            .destroyDynamicVertexBuffer = T.destroyDynamicVertexBuffer,
            .getAvailTransientIndexBuffer = T.getAvailTransientIndexBuffer,
            .getAvailTransientVertexBuffer = T.getAvailTransientVertexBuffer,
            .allocTransientIndexBuffer = T.allocTransientIndexBuffer,
            .allocTransientVertexBuffer = T.allocTransientVertexBuffer,
            .allocTransientBuffers = T.allocTransientBuffers,
            .createIndirectBuffer = T.createIndirectBuffer,
            .destroyIndirectBuffer = T.destroyIndirectBuffer,
            .createShader = T.createShader,
            .getShaderUniforms = T.getShaderUniforms,
            .setShaderName = T.setShaderName,
            .destroyShader = T.destroyShader,
            .createProgram = T.createProgram,
            .createComputeProgram = T.createComputeProgram,
            .destroyProgram = T.destroyProgram,
            .isTextureValid = T.isTextureValid,
            .isFrameBufferValid = T.isFrameBufferValid,
            .calcTextureSize = T.calcTextureSize,
            .createTexture = T.createTexture,
            .createTexture2D = T.createTexture2D,
            .createTexture3D = T.createTexture3D,
            .createTextureCube = T.createTextureCube,
            .updateTexture2D = T.updateTexture2D,
            .updateTexture3D = T.updateTexture3D,
            .updateTextureCube = T.updateTextureCube,
            .readTexture = T.readTexture,
            .setTextureName = T.setTextureName,
            .getDirectAccessPtr = T.getDirectAccessPtr,
            .destroyTexture = T.destroyTexture,
            .createFrameBuffer = T.createFrameBuffer,
            .createFrameBufferScaled = T.createFrameBufferScaled,
            .createFrameBufferFromHandles = T.createFrameBufferFromHandles,
            .createFrameBufferFromAttachment = T.createFrameBufferFromAttachment,
            .createFrameBufferFromNwh = T.createFrameBufferFromNwh,
            .setFrameBufferName = T.setFrameBufferName,
            .getTexture = T.getTexture,
            .destroyFrameBuffer = T.destroyFrameBuffer,
            .createUniform = T.createUniform,
            .getUniformInfo = T.getUniformInfo,
            .destroyUniform = T.destroyUniform,
            .createOcclusionQuery = T.createOcclusionQuery,
            .getResult = T.getResult,
            .destroyOcclusionQuery = T.destroyOcclusionQuery,
            .setViewName = T.setViewName,
            .setViewRect = T.setViewRect,
            .setViewRectRatio = T.setViewRectRatio,
            .setViewScissor = T.setViewScissor,
            .setViewClear = T.setViewClear,
            .setViewClearMrt = T.setViewClearMrt,
            .setViewMode = T.setViewMode,
            .setViewFrameBuffer = T.setViewFrameBuffer,
            .setViewTransform = T.setViewTransform,
            .setViewOrder = T.setViewOrder,
            .resetView = T.resetView,
            .layoutBegin = T.layoutBegin,
            .layoutAdd = T.layoutAdd,
            .layoutDecode = T.layoutDecode,
            .layoutSkip = T.layoutSkip,
            .layoutEnd = T.layoutEnd,

            .getCoreUIProgram = T.getCoreUIProgram,
            .getCoreShader = T.getCoreShader,
        };
    }

    destroyBackend: *const fn (self: *anyopaque) void,
    isNoop: *const fn (self: *anyopaque) bool,
    getWindow: *const fn (self: *anyopaque) ?host.Window,
    getResolution: *const fn (self: *anyopaque) Resolution,
    addPaletteColor: *const fn (self: *anyopaque, color: math.SRGBA) u8,
    endAllUsedEncoders: *const fn (self: *anyopaque) void,
    compileShader: *const fn (self: *anyopaque, allocator: std.mem.Allocator, varying: []const u8, shader: []const u8, options: ShadercOptions) anyerror![]u8,
    createDefaultShadercOptions: *const fn (self: *anyopaque) ShadercOptions,
    isHomogenousDepth: *const fn (self: *anyopaque) bool,
    isOriginBottomLeft: *const fn (self: *anyopaque) bool,
    getNullVb: *const fn (self: *anyopaque) VertexBufferHandle,
    getFloatBufferLayout: *const fn (self: *anyopaque) *const VertexLayout,
    reset: *const fn (self: *anyopaque, _width: u32, _height: u32, _flags: ResetFlags, _format: TextureFormat) void,
    frame: *const fn (self: *anyopaque, _flags: FrameFlags) u32,
    alloc: *const fn (self: *anyopaque, _size: u32) *const Memory,
    copy: *const fn (self: *anyopaque, _data: ?*const anyopaque, _size: u32) *const Memory,
    makeRef: *const fn (self: *anyopaque, _data: ?*const anyopaque, _size: u32) *const Memory,
    makeRefRelease: *const fn (self: *anyopaque, _data: ?*const anyopaque, _size: u32, _releaseFn: ?*anyopaque, _userData: ?*anyopaque) *const Memory,
    setDebug: *const fn (self: *anyopaque, _debug: DebugFlags) void,
    dbgTextClear: *const fn (self: *anyopaque, _attr: u8, _small: bool) void,
    dbgTextImage: *const fn (self: *anyopaque, _x: u16, _y: u16, _width: u16, _height: u16, _data: ?*const anyopaque, _pitch: u16) void,
    getEncoder: *const fn (self: *anyopaque) ?GpuEncoder,
    endEncoder: *const fn (self: *anyopaque, encoder: GpuEncoder) void,
    requestScreenShot: *const fn (self: *anyopaque, _handle: FrameBufferHandle, _filePath: [*c]const u8) void,
    renderFrame: *const fn (self: *anyopaque, _msecs: i32) RenderFrame,
    createIndexBuffer: *const fn (self: *anyopaque, _mem: ?*const Memory, _flags: BufferFlags) IndexBufferHandle,
    setIndexBufferName: *const fn (self: *anyopaque, _handle: IndexBufferHandle, _name: []const u8) void,
    destroyIndexBuffer: *const fn (self: *anyopaque, _handle: IndexBufferHandle) void,
    createVertexLayout: *const fn (self: *anyopaque, _layout: *const VertexLayout) VertexLayoutHandle,
    destroyVertexLayout: *const fn (self: *anyopaque, _layoutHandle: VertexLayoutHandle) void,
    createVertexBuffer: *const fn (self: *anyopaque, _mem: ?*const Memory, _layout: *const VertexLayout, _flags: BufferFlags) VertexBufferHandle,
    setVertexBufferName: *const fn (self: *anyopaque, _handle: VertexBufferHandle, _name: []const u8) void,
    destroyVertexBuffer: *const fn (self: *anyopaque, _handle: VertexBufferHandle) void,
    createDynamicIndexBuffer: *const fn (self: *anyopaque, _num: u32, _flags: u16) DynamicIndexBufferHandle,
    createDynamicIndexBufferMem: *const fn (self: *anyopaque, _mem: ?*const Memory, _flags: u16) DynamicIndexBufferHandle,
    updateDynamicIndexBuffer: *const fn (self: *anyopaque, _handle: DynamicIndexBufferHandle, _startIndex: u32, _mem: ?*const Memory) void,
    destroyDynamicIndexBuffer: *const fn (self: *anyopaque, _handle: DynamicIndexBufferHandle) void,
    createDynamicVertexBuffer: *const fn (self: *anyopaque, _num: u32, _layout: *const VertexLayout, _flags: BufferFlags) DynamicVertexBufferHandle,
    createDynamicVertexBufferMem: *const fn (self: *anyopaque, _mem: ?*const Memory, _layout: *const VertexLayout, _flags: u16) DynamicVertexBufferHandle,
    updateDynamicVertexBuffer: *const fn (self: *anyopaque, _handle: DynamicVertexBufferHandle, _startVertex: u32, _mem: ?*const Memory) void,
    destroyDynamicVertexBuffer: *const fn (self: *anyopaque, _handle: DynamicVertexBufferHandle) void,
    getAvailTransientIndexBuffer: *const fn (self: *anyopaque, _num: u32, _index32: bool) u32,
    getAvailTransientVertexBuffer: *const fn (self: *anyopaque, _num: u32, _layout: *const VertexLayout) u32,
    allocTransientIndexBuffer: *const fn (self: *anyopaque, _tib: [*c]TransientIndexBuffer, _num: u32, _index32: bool) void,
    allocTransientVertexBuffer: *const fn (self: *anyopaque, _tvb: [*c]TransientVertexBuffer, _num: u32, _layout: *const VertexLayout) void,
    allocTransientBuffers: *const fn (self: *anyopaque, _tvb: [*c]TransientVertexBuffer, _layout: *const VertexLayout, _numVertices: u32, _tib: [*c]TransientIndexBuffer, _numIndices: u32, _index32: bool) bool,
    createIndirectBuffer: *const fn (self: *anyopaque, _num: u32) IndirectBufferHandle,
    destroyIndirectBuffer: *const fn (self: *anyopaque, _handle: IndirectBufferHandle) void,
    createShader: *const fn (self: *anyopaque, _mem: ?*const Memory) ShaderHandle,
    getShaderUniforms: *const fn (self: *anyopaque, _handle: ShaderHandle, _uniforms: [*c]UniformHandle, _max: u16) u16,
    setShaderName: *const fn (self: *anyopaque, _handle: ShaderHandle, _name: []const u8) void,
    destroyShader: *const fn (self: *anyopaque, _handle: ShaderHandle) void,
    createProgram: *const fn (self: *anyopaque, _vsh: ShaderHandle, _fsh: ShaderHandle, _destroyShaders: bool) ProgramHandle,
    createComputeProgram: *const fn (self: *anyopaque, _csh: ShaderHandle, _destroyShaders: bool) ProgramHandle,
    destroyProgram: *const fn (self: *anyopaque, _handle: ProgramHandle) void,
    isTextureValid: *const fn (self: *anyopaque, _depth: u16, _cubeMap: bool, _numLayers: u16, _format: TextureFormat, _flags: u64) bool,
    isFrameBufferValid: *const fn (self: *anyopaque, _num: u8, _attachment: *const Attachment) bool,
    calcTextureSize: *const fn (self: *anyopaque, _info: [*c]TextureInfo, _width: u16, _height: u16, _depth: u16, _cubeMap: bool, _hasMips: bool, _numLayers: u16, _format: TextureFormat) void,
    createTexture: *const fn (self: *anyopaque, _mem: ?*const Memory, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _skip: u8, _info: ?*TextureInfo) TextureHandle,
    createTexture2D: *const fn (self: *anyopaque, _width: u16, _height: u16, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _mem: ?*const Memory, _external: u64) TextureHandle,
    createTexture3D: *const fn (self: *anyopaque, _width: u16, _height: u16, _depth: u16, _hasMips: bool, _format: TextureFormat, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _mem: ?*const Memory, _external: u64) TextureHandle,
    createTextureCube: *const fn (self: *anyopaque, _size: u16, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: TextureFlags, _sampler_flags: ?SamplerFlags, _mem: ?*const Memory, _external: u64) TextureHandle,
    updateTexture2D: *const fn (self: *anyopaque, _handle: TextureHandle, _layer: u16, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: ?*const Memory, _pitch: u16) void,
    updateTexture3D: *const fn (self: *anyopaque, _handle: TextureHandle, _mip: u8, _x: u16, _y: u16, _z: u16, _width: u16, _height: u16, _depth: u16, _mem: ?*const Memory) void,
    updateTextureCube: *const fn (self: *anyopaque, _handle: TextureHandle, _layer: u16, _side: CubeMapSide, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: ?*const Memory, _pitch: u16) void,
    readTexture: *const fn (self: *anyopaque, _handle: TextureHandle, _data: ?*anyopaque, _mip: u8) u32,
    setTextureName: *const fn (self: *anyopaque, _handle: TextureHandle, _name: []const u8) void,
    getDirectAccessPtr: *const fn (self: *anyopaque, _handle: TextureHandle) ?*anyopaque,
    destroyTexture: *const fn (self: *anyopaque, _handle: TextureHandle) void,
    createFrameBuffer: *const fn (self: *anyopaque, _width: u16, _height: u16, _format: TextureFormat, _textureFlags: u64) FrameBufferHandle,
    createFrameBufferScaled: *const fn (self: *anyopaque, _ratio: BackbufferRatio, _format: TextureFormat, _textureFlags: u64) FrameBufferHandle,
    createFrameBufferFromHandles: *const fn (self: *anyopaque, _handles: []const TextureHandle, _destroyTexture: bool) FrameBufferHandle,
    createFrameBufferFromAttachment: *const fn (self: *anyopaque, _attachment: []const Attachment, _destroyTexture: bool) FrameBufferHandle,
    createFrameBufferFromNwh: *const fn (self: *anyopaque, _nwh: ?*anyopaque, _width: u16, _height: u16, _format: TextureFormat, _depthFormat: TextureFormat) FrameBufferHandle,
    setFrameBufferName: *const fn (self: *anyopaque, _handle: FrameBufferHandle, _name: []const u8) void,
    getTexture: *const fn (self: *anyopaque, _handle: FrameBufferHandle, _attachment: u8) TextureHandle,
    destroyFrameBuffer: *const fn (self: *anyopaque, _handle: FrameBufferHandle) void,
    createUniform: *const fn (self: *anyopaque, _name: [:0]const u8, _type: UniformType, _num: u16) UniformHandle,
    getUniformInfo: *const fn (self: *anyopaque, _handle: UniformHandle, _info: [*c]UniformInfo) void,
    destroyUniform: *const fn (self: *anyopaque, _handle: UniformHandle) void,
    createOcclusionQuery: *const fn (self: *anyopaque) OcclusionQueryHandle,
    getResult: *const fn (self: *anyopaque, _handle: OcclusionQueryHandle, _result: [*c]i32) OcclusionQueryResult,
    destroyOcclusionQuery: *const fn (self: *anyopaque, _handle: OcclusionQueryHandle) void,
    setViewName: *const fn (self: *anyopaque, _id: ViewId, _name: []const u8) void,
    setViewRect: *const fn (self: *anyopaque, _id: ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void,
    setViewRectRatio: *const fn (self: *anyopaque, _id: ViewId, _x: u16, _y: u16, _ratio: BackbufferRatio) void,
    setViewScissor: *const fn (self: *anyopaque, _id: ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void,
    setViewClear: *const fn (self: *anyopaque, _id: ViewId, _flags: ClearFlags, _rgba: u32, _depth: f32, _stencil: u8) void,
    setViewClearMrt: *const fn (self: *anyopaque, _id: ViewId, _flags: ClearFlags, _depth: f32, _stencil: u8, _c0: u8, _c1: u8, _c2: u8, _c3: u8, _c4: u8, _c5: u8, _c6: u8, _c7: u8) void,
    setViewMode: *const fn (self: *anyopaque, _id: ViewId, _mode: ViewMode) void,
    setViewFrameBuffer: *const fn (self: *anyopaque, _id: ViewId, _handle: FrameBufferHandle) void,
    setViewTransform: *const fn (self: *anyopaque, _id: ViewId, _view: ?*const anyopaque, _proj: ?*const anyopaque) void,
    setViewOrder: *const fn (self: *anyopaque, _id: ViewId, _num: u16, _order: *const ViewId) void,
    resetView: *const fn (self: *anyopaque, _id: ViewId) void,

    layoutBegin: *const fn (vl: *VertexLayout) *VertexLayout,
    layoutAdd: *const fn (vl: *VertexLayout, _attrib: Attrib, _num: u8, _type: AttribType, _normalized: bool, _asInt: bool) *VertexLayout,
    layoutDecode: *const fn (vl: *const VertexLayout, _attrib: Attrib, _num: [*c]u8, _type: [*c]AttribType, _normalized: [*c]bool, _asInt: [*c]bool) void,
    layoutSkip: *const fn (vl: *VertexLayout, _num: u8) *VertexLayout,
    layoutEnd: *const fn (vl: *VertexLayout) void,

    // Not nice solution
    getCoreUIProgram: *const fn (self: *anyopaque) ProgramHandle,
    getCoreShader: *const fn (self: *anyopaque) []const u8,
};

pub const GpuEncoder = struct {
    pub inline fn setMarker(self: GpuEncoder, _name: []const u8) void {
        return self.vtable.set_marker(self.ptr, _name);
    }
    pub inline fn setState(self: GpuEncoder, state: RenderState, _rgba: u32) void {
        return self.vtable.set_state(self.ptr, state, _rgba);
    }
    pub inline fn setCondition(self: GpuEncoder, _handle: OcclusionQueryHandle, _visible: bool) void {
        return self.vtable.set_condition(self.ptr, _handle, _visible);
    }
    pub inline fn setStencil(self: GpuEncoder, _fstencil: u32, _bstencil: u32) void {
        return self.vtable.set_stencil(self.ptr, _fstencil, _bstencil);
    }
    pub inline fn setScissor(self: GpuEncoder, _x: u16, _y: u16, _width: u16, _height: u16) u16 {
        return self.vtable.set_scissor(self.ptr, _x, _y, _width, _height);
    }
    pub inline fn setScissorCached(self: GpuEncoder, _cache: u16) void {
        return self.vtable.set_scissor_cached(self.ptr, _cache);
    }
    pub inline fn setTransform(self: GpuEncoder, _mtx: ?*const anyopaque, _num: u16) u32 {
        return self.vtable.set_transform(self.ptr, _mtx, _num);
    }
    pub inline fn setTransformCached(self: GpuEncoder, _cache: u32, _num: u16) void {
        return self.vtable.set_transform_cached(self.ptr, _cache, _num);
    }
    pub inline fn allocTransform(self: GpuEncoder, _transform: [*c]Transform, _num: u16) u32 {
        return self.vtable.alloc_transform(self.ptr, _transform, _num);
    }
    pub inline fn setUniform(self: GpuEncoder, _handle: UniformHandle, _value: ?*const anyopaque, _num: u16) void {
        return self.vtable.set_uniform(self.ptr, _handle, _value, _num);
    }
    pub inline fn setIndexBuffer(self: GpuEncoder, _handle: IndexBufferHandle, _firstIndex: u32, _numIndices: u32) void {
        return self.vtable.set_index_buffer(self.ptr, _handle, _firstIndex, _numIndices);
    }
    pub inline fn setDynamicIndexBuffer(self: GpuEncoder, _handle: DynamicIndexBufferHandle, _firstIndex: u32, _numIndices: u32) void {
        return self.vtable.set_dynamic_index_buffer(self.ptr, _handle, _firstIndex, _numIndices);
    }
    pub inline fn setTransientIndexBuffer(self: GpuEncoder, _tib: *const TransientIndexBuffer, _firstIndex: u32, _numIndices: u32) void {
        return self.vtable.set_transient_index_buffer(self.ptr, _tib, _firstIndex, _numIndices);
    }
    pub inline fn setVertexBuffer(self: GpuEncoder, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32) void {
        return self.vtable.set_vertex_buffer(self.ptr, _stream, _handle, _startVertex, _numVertices);
    }
    pub inline fn setVertexBufferWithLayout(self: GpuEncoder, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void {
        return self.vtable.set_vertex_buffer_with_layout(self.ptr, _stream, _handle, _startVertex, _numVertices, _layoutHandle);
    }
    pub inline fn setDynamicVertexBuffer(self: GpuEncoder, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32) void {
        return self.vtable.set_dynamic_vertex_buffer(self.ptr, _stream, _handle, _startVertex, _numVertices);
    }
    pub inline fn setDynamicVertexBufferWithLayout(self: GpuEncoder, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void {
        return self.vtable.set_dynamic_vertex_buffer_with_layout(self.ptr, _stream, _handle, _startVertex, _numVertices, _layoutHandle);
    }
    pub inline fn setTransientVertexBuffer(self: GpuEncoder, _stream: u8, _tvb: *const TransientVertexBuffer, _startVertex: u32, _numVertices: u32) void {
        return self.vtable.set_transient_vertex_buffer(self.ptr, _stream, _tvb, _startVertex, _numVertices);
    }
    pub inline fn setTransientVertexBufferWithLayout(self: GpuEncoder, _stream: u8, _tvb: *const TransientVertexBuffer, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void {
        return self.vtable.set_transient_vertex_buffer_with_layout(self.ptr, _stream, _tvb, _startVertex, _numVertices, _layoutHandle);
    }
    pub inline fn setVertexCount(self: GpuEncoder, _numVertices: u32) void {
        return self.vtable.set_vertex_count(self.ptr, _numVertices);
    }
    pub inline fn setInstanceCount(self: GpuEncoder, _numInstances: u32) void {
        return self.vtable.set_instance_count(self.ptr, _numInstances);
    }
    pub inline fn setTexture(self: GpuEncoder, _stage: u8, _sampler: UniformHandle, _handle: TextureHandle, _flags: ?SamplerFlags) void {
        return self.vtable.set_texture(self.ptr, _stage, _sampler, _handle, _flags);
    }
    pub inline fn touch(self: GpuEncoder, _id: ViewId) void {
        return self.vtable.touch(self.ptr, _id);
    }
    pub inline fn submit(self: GpuEncoder, _id: ViewId, _program: ProgramHandle, _depth: u32, _flags: DiscardFlags) void {
        return self.vtable.submit(self.ptr, _id, _program, _depth, _flags);
    }
    pub inline fn submitOcclusionQuery(self: GpuEncoder, _id: ViewId, _program: ProgramHandle, _occlusionQuery: OcclusionQueryHandle, _depth: u32, _flags: u8) void {
        return self.vtable.submit_occlusion_query(self.ptr, _id, _program, _occlusionQuery, _depth, _flags);
    }
    pub inline fn submitIndirect(self: GpuEncoder, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _depth: u32, _flags: u8) void {
        return self.vtable.submit_indirect(self.ptr, _id, _program, _indirectHandle, _start, _num, _depth, _flags);
    }
    pub inline fn submitIndirectCount(self: GpuEncoder, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _numHandle: IndexBufferHandle, _numIndex: u32, _numMax: u32, _depth: u32, _flags: u8) void {
        return self.vtable.submit_indirect_count(self.ptr, _id, _program, _indirectHandle, _start, _numHandle, _numIndex, _numMax, _depth, _flags);
    }
    pub inline fn setComputeIndexBuffer(self: GpuEncoder, _stage: u8, _handle: IndexBufferHandle, _access: Access) void {
        return self.vtable.set_compute_index_buffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeVertexBuffer(self: GpuEncoder, _stage: u8, _handle: VertexBufferHandle, _access: Access) void {
        return self.vtable.set_compute_vertex_buffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeDynamicIndexBuffer(self: GpuEncoder, _stage: u8, _handle: DynamicIndexBufferHandle, _access: Access) void {
        return self.vtable.set_compute_dynamic_index_buffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeDynamicVertexBuffer(self: GpuEncoder, _stage: u8, _handle: DynamicVertexBufferHandle, _access: Access) void {
        return self.vtable.set_compute_dynamic_vertex_buffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeIndirectBuffer(self: GpuEncoder, _stage: u8, _handle: IndirectBufferHandle, _access: Access) void {
        return self.vtable.set_compute_indirect_buffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setImage(self: GpuEncoder, _stage: u8, _handle: TextureHandle, _mip: u8, _access: Access, _format: TextureFormat) void {
        return self.vtable.set_image(self.ptr, _stage, _handle, _mip, _access, _format);
    }
    pub inline fn dispatch(self: GpuEncoder, _id: ViewId, _program: ProgramHandle, _numX: u32, _numY: u32, _numZ: u32, _flags: u8) void {
        return self.vtable.dispatch(self.ptr, _id, _program, _numX, _numY, _numZ, _flags);
    }
    pub inline fn dispatchIndirect(self: GpuEncoder, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _flags: u8) void {
        return self.vtable.dispatch_indirect(self.ptr, _id, _program, _indirectHandle, _start, _num, _flags);
    }
    pub inline fn discard(self: GpuEncoder, _flags: DiscardFlags) void {
        return self.vtable.discard(self.ptr, _flags);
    }
    pub inline fn blit(self: GpuEncoder, _id: ViewId, _dst: TextureHandle, _dstMip: u8, _dstX: u16, _dstY: u16, _dstZ: u16, _src: TextureHandle, _srcMip: u8, _srcX: u16, _srcY: u16, _srcZ: u16, _width: u16, _height: u16, _depth: u16) void {
        return self.vtable.blit(self.ptr, _id, _dst, _dstMip, _dstX, _dstY, _dstZ, _src, _srcMip, _srcX, _srcY, _srcZ, _width, _height, _depth);
    }

    pub fn implement(comptime T: type) VTable {
        return VTable{
            .set_marker = T.setMarker,
            .set_state = T.setState,
            .set_condition = T.setCondition,
            .set_stencil = T.setStencil,
            .set_scissor = T.setScissor,
            .set_scissor_cached = T.setScissorCached,
            .set_transform = T.setTransform,
            .set_transform_cached = T.setTransformCached,
            .alloc_transform = T.allocTransform,
            .set_uniform = T.setUniform,
            .set_index_buffer = T.setIndexBuffer,
            .set_dynamic_index_buffer = T.setDynamicIndexBuffer,
            .set_transient_index_buffer = T.setTransientIndexBuffer,
            .set_vertex_buffer = T.setVertexBuffer,
            .set_vertex_buffer_with_layout = T.setVertexBufferWithLayout,
            .set_dynamic_vertex_buffer = T.setDynamicVertexBuffer,
            .set_dynamic_vertex_buffer_with_layout = T.setDynamicVertexBufferWithLayout,
            .set_transient_vertex_buffer = T.setTransientVertexBuffer,
            .set_transient_vertex_buffer_with_layout = T.setTransientVertexBufferWithLayout,
            .set_vertex_count = T.setVertexCount,
            .set_instance_count = T.setInstanceCount,
            .set_texture = T.setTexture,
            .touch = T.touch,
            .submit = T.submit,
            .submit_occlusion_query = T.submitOcclusionQuery,
            .submit_indirect = T.submitIndirect,
            .submit_indirect_count = T.submitIndirectCount,
            .set_compute_index_buffer = T.setComputeIndexBuffer,
            .set_compute_vertex_buffer = T.setComputeVertexBuffer,
            .set_compute_dynamic_index_buffer = T.setComputeDynamicIndexBuffer,
            .set_compute_dynamic_vertex_buffer = T.setComputeDynamicVertexBuffer,
            .set_compute_indirect_buffer = T.setComputeIndirectBuffer,
            .set_image = T.setImage,
            .dispatch = T.dispatch,
            .dispatch_indirect = T.dispatchIndirect,
            .discard = T.discard,
            .blit = T.blit,
        };
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        set_marker: *const fn (self: *anyopaque, _name: []const u8) void,
        set_state: *const fn (self: *anyopaque, state: RenderState, _rgba: u32) void,
        set_condition: *const fn (self: *anyopaque, _handle: OcclusionQueryHandle, _visible: bool) void,
        set_stencil: *const fn (self: *anyopaque, _fstencil: u32, _bstencil: u32) void,
        set_scissor: *const fn (self: *anyopaque, _x: u16, _y: u16, _width: u16, _height: u16) u16,
        set_scissor_cached: *const fn (self: *anyopaque, _cache: u16) void,
        set_transform: *const fn (self: *anyopaque, _mtx: ?*const anyopaque, _num: u16) u32,
        set_transform_cached: *const fn (self: *anyopaque, _cache: u32, _num: u16) void,
        alloc_transform: *const fn (self: *anyopaque, _transform: [*c]Transform, _num: u16) u32,
        set_uniform: *const fn (self: *anyopaque, _handle: UniformHandle, _value: ?*const anyopaque, _num: u16) void,
        set_index_buffer: *const fn (self: *anyopaque, _handle: IndexBufferHandle, _firstIndex: u32, _numIndices: u32) void,
        set_dynamic_index_buffer: *const fn (self: *anyopaque, _handle: DynamicIndexBufferHandle, _firstIndex: u32, _numIndices: u32) void,
        set_transient_index_buffer: *const fn (self: *anyopaque, _tib: *const TransientIndexBuffer, _firstIndex: u32, _numIndices: u32) void,
        set_vertex_buffer: *const fn (self: *anyopaque, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32) void,
        set_vertex_buffer_with_layout: *const fn (self: *anyopaque, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
        set_dynamic_vertex_buffer: *const fn (self: *anyopaque, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32) void,
        set_dynamic_vertex_buffer_with_layout: *const fn (self: *anyopaque, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
        set_transient_vertex_buffer: *const fn (self: *anyopaque, _stream: u8, _tvb: *const TransientVertexBuffer, _startVertex: u32, _numVertices: u32) void,
        set_transient_vertex_buffer_with_layout: *const fn (self: *anyopaque, _stream: u8, _tvb: *const TransientVertexBuffer, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
        set_vertex_count: *const fn (self: *anyopaque, _numVertices: u32) void,
        set_instance_count: *const fn (self: *anyopaque, _numInstances: u32) void,
        set_texture: *const fn (self: *anyopaque, _stage: u8, _sampler: UniformHandle, _handle: TextureHandle, _flags: ?SamplerFlags) void,
        touch: *const fn (self: *anyopaque, _id: ViewId) void,
        submit: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _depth: u32, _flags: DiscardFlags) void,
        submit_occlusion_query: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _occlusionQuery: OcclusionQueryHandle, _depth: u32, _flags: u8) void,
        submit_indirect: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _depth: u32, _flags: u8) void,
        submit_indirect_count: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _numHandle: IndexBufferHandle, _numIndex: u32, _numMax: u32, _depth: u32, _flags: u8) void,
        set_compute_index_buffer: *const fn (self: *anyopaque, _stage: u8, _handle: IndexBufferHandle, _access: Access) void,
        set_compute_vertex_buffer: *const fn (self: *anyopaque, _stage: u8, _handle: VertexBufferHandle, _access: Access) void,
        set_compute_dynamic_index_buffer: *const fn (self: *anyopaque, _stage: u8, _handle: DynamicIndexBufferHandle, _access: Access) void,
        set_compute_dynamic_vertex_buffer: *const fn (self: *anyopaque, _stage: u8, _handle: DynamicVertexBufferHandle, _access: Access) void,
        set_compute_indirect_buffer: *const fn (self: *anyopaque, _stage: u8, _handle: IndirectBufferHandle, _access: Access) void,
        set_image: *const fn (self: *anyopaque, _stage: u8, _handle: TextureHandle, _mip: u8, _access: Access, _format: TextureFormat) void,
        dispatch: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _numX: u32, _numY: u32, _numZ: u32, _flags: u8) void,
        dispatch_indirect: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _flags: u8) void,
        discard: *const fn (self: *anyopaque, _flags: DiscardFlags) void,
        blit: *const fn (self: *anyopaque, _id: ViewId, _dst: TextureHandle, _dstMip: u8, _dstX: u16, _dstY: u16, _dstZ: u16, _src: TextureHandle, _srcMip: u8, _srcX: u16, _srcY: u16, _srcZ: u16, _width: u16, _height: u16, _depth: u16) void,
    };
};

pub const Memory = extern struct {
    data: [*c]u8,
    size: u32,
};

pub const TransientIndexBuffer = extern struct {
    data: [*c]u8,
    size: u32,
    startIndex: u32,
    handle: IndexBufferHandle,
    isIndex16: bool,
};

pub const TransientVertexBuffer = extern struct {
    data: [*c]u8,
    size: u32,
    startVertex: u32,
    stride: u16,
    handle: VertexBufferHandle,
    layoutHandle: VertexLayoutHandle,
};

pub const TextureInfo = extern struct {
    format: TextureFormat,
    storageSize: u32,
    width: u16,
    height: u16,
    depth: u16,
    numLayers: u16,
    numMips: u8,
    bitsPerPixel: u8,
    cubeMap: bool,
};

pub const UniformInfo = extern struct {
    name: [256]u8,
    type: UniformType,
    num: u16,
};

pub const Attachment = extern struct {
    access: Access,
    handle: TextureHandle,
    mip: u16,
    layer: u16,
    numLayers: u16,
    resolve: u8,
};

pub const Transform = extern struct {
    data: [*c]f32,
    num: u16,
};

pub const VertexLayout = extern struct {
    hash: u32,
    stride: u16,
    offset: [18]u16,
    attributes: [18]u16,
};

pub const Resolution = extern struct {
    formatColor: TextureFormat,
    formatDepthStencil: TextureFormat,
    width: u32,
    height: u32,
    reset: u32,
    numBackBuffers: u8,
    maxFrameLatency: u8,
    debugTextScale: u8,
};

pub const BackbufferRatio = enum(c_int) {
    /// Equal to backbuffer.
    Equal,

    /// One half size of backbuffer.
    Half,

    /// One quarter size of backbuffer.
    Quarter,

    /// One eighth size of backbuffer.
    Eighth,

    /// One sixteenth size of backbuffer.
    Sixteenth,

    /// Double size of backbuffer.
    Double,

    Count,
};

pub const OcclusionQueryResult = enum(c_int) {
    /// Query failed test.
    Invisible,

    /// Query passed test.
    Visible,

    /// Query result is not available yet.
    NoResult,

    Count,
};

pub const Topology = enum(c_int) {
    /// Triangle list.
    TriList,

    /// Triangle strip.
    TriStrip,

    /// Line list.
    LineList,

    /// Line strip.
    LineStrip,

    /// Point list.
    PointList,

    Count,
};

pub const TopologyConvert = enum(c_int) {
    /// Flip winding order of triangle list.
    TriListFlipWinding,

    /// Flip winding order of triangle strip.
    TriStripFlipWinding,

    /// Convert triangle list to line list.
    TriListToLineList,

    /// Convert triangle strip to triangle list.
    TriStripToTriList,

    /// Convert line strip to line list.
    LineStripToLineList,

    Count,
};

pub const TopologySort = enum(c_int) {
    DirectionFrontToBackMin,
    DirectionFrontToBackAvg,
    DirectionFrontToBackMax,
    DirectionBackToFrontMin,
    DirectionBackToFrontAvg,
    DirectionBackToFrontMax,
    DistanceFrontToBackMin,
    DistanceFrontToBackAvg,
    DistanceFrontToBackMax,
    DistanceBackToFrontMin,
    DistanceBackToFrontAvg,
    DistanceBackToFrontMax,
    Count,
};

pub const ShaderType = enum {
    Vertex,
    Fragment,
    Compute,
};

pub const Optimize = enum(u32) {
    O1 = 1,
    O2 = 2,
    O3 = 3,
};

pub const Platform = enum {
    Android,
    AsmJs,
    Ios,
    Linux,
    Orbis,
    Osx,
    Windows,
};

pub const Profile = enum {
    Es100,
    Es300,
    Es310,
    Es320,

    S40,
    S50,

    S60,
    S61,
    S62,
    S63,
    S64,
    S65,
    S66,
    S67,
    S68,
    S69,

    Metal,
    Metal1010,
    Metal1110,
    Metal1210,
    Metal2011,
    Metal2111,
    Metal2211,
    Metal2314,
    Metal2414,
    Metal3014,
    Metal3114,

    Pssl,

    Spirv,
    Spirv1010,
    Spirv1311,
    Spirv1411,
    Spirv1512,
    Spirv1613,

    Glsl120,
    Glsl130,
    Glsl140,
    Glsl150,
    Glsl330,
    Glsl400,
    Glsl410,
    Glsl420,
    Glsl430,
    Glsl440,
};

pub const ShadercOptions = struct {
    shaderType: ShaderType,

    platform: Platform,
    profile: Profile,

    inputFilePath: ?[]const u8 = null,
    outputFilePath: ?[]const u8 = null,
    varyingFilePath: ?[]const u8 = null,

    includeDirs: ?[]const []const u8 = null,
    defines: ?[]const []const u8 = null,

    optimizationLevel: Optimize = .O3,
    keepcomments: bool = false,
};

pub fn createBackend(
    window: ?host.Window,
    backend: ?[]const u8,
    vsync: bool,
    headles: bool,
    debug: bool,
    profile: bool,
) anyerror!?GpuBackend {
    return api.createBackend(window, backend, vsync, headles, debug, profile);
}

pub fn destroyBackend(backend: GpuBackend) void {
    return api.destroyBackend(backend);
}

pub const GpuApi = struct {
    createBackend: *const fn (
        window: ?host.Window,
        backend: ?[]const u8,
        vsync: bool,
        headles: bool,
        debug: bool,
        profile: bool,
    ) anyerror!?GpuBackend,
    destroyBackend: *const fn (backend: GpuBackend) void,
};

pub var api: *const GpuApi = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, GpuApi).?;
}
