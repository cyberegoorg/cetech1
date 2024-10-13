const std = @import("std");
const platform = @import("platform.zig");
const strid = @import("strid.zig");
const cdb = @import("cdb.zig");

const ecs = @import("ecs.zig");

const log = std.log.scoped(.gpu);

pub const GpuContext = opaque {};

pub const Backend = enum(c_int) {
    /// No rendering.
    noop,

    /// AGC
    agc,

    /// Direct3D 11.0
    dx11,

    /// Direct3D 12.0
    dx12,

    /// GNM
    gnm,

    /// Metal
    metal,

    /// NVN
    nvn,

    /// OpenGL ES 2.0+
    opengl_es,

    /// OpenGL 2.1+
    opengl,

    /// Vulkan
    vulkan,

    /// Auto select best
    auto,

    pub fn fromString(str: []const u8) Backend {
        return std.meta.stringToEnum(Backend, str) orelse .auto;
    }
};

pub const GpuApi = struct {
    createContext: *const fn (window: ?platform.Window, backend: ?Backend, vsync: bool, headles: bool) anyerror!*GpuContext,
    destroyContext: *const fn (ctx: *GpuContext) void,
    getWindow: *const fn (ctx: *GpuContext) ?platform.Window,

    getResolution: *const fn () Resolution,

    addPaletteColor: *const fn (color: u32) u8,
    endAllUsedEncoders: *const fn () void,

    newViewId: *const fn () ViewId,
    resetViewId: *const fn () void,

    getBackendType: *const fn () Backend,

    compileShader: *const fn (
        allocator: std.mem.Allocator,
        varying: []const u8,
        shader: []const u8,
        options: ShadercOptions,
    ) anyerror![]u8,

    createDefaultOptionsForRenderer: *const fn (renderer: Backend) ShadercOptions,

    vertexPack: *const fn (_input: [4]f32, _inputNormalized: bool, _attr: Attrib, _layout: [*c]const VertexLayout, _data: ?*anyopaque, _index: u32) void,
    vertexUnpack: *const fn (_output: [4]f32, _attr: Attrib, _layout: [*c]const VertexLayout, _data: ?*const anyopaque, _index: u32) void,
    vertexConvert: *const fn (_dstLayout: [*c]const VertexLayout, _dstData: ?*anyopaque, _srcLayout: [*c]const VertexLayout, _srcData: ?*const anyopaque, _num: u32) void,
    weldVertices: *const fn (_output: ?*anyopaque, _layout: [*c]const VertexLayout, _data: ?*const anyopaque, _num: u32, _index32: bool, _epsilon: f32) u32,
    topologyConvert: *const fn (_conversion: TopologyConvert, _dst: ?*anyopaque, _dstSize: u32, _indices: ?*const anyopaque, _numIndices: u32, _index32: bool) u32,
    topologySortTriList: *const fn (_sort: TopologySort, _dst: ?*anyopaque, _dstSize: u32, _dir: [3]f32, _pos: [3]f32, _vertices: ?*const anyopaque, _stride: u32, _indices: ?*const anyopaque, _numIndices: u32, _index32: bool) void,
    reset: *const fn (_width: u32, _height: u32, _flags: u32, _format: TextureFormat) void,
    frame: *const fn (_capture: bool) u32,
    alloc: *const fn (_size: u32) [*c]const Memory,
    copy: *const fn (_data: ?*const anyopaque, _size: u32) [*c]const Memory,
    makeRef: *const fn (_data: ?*const anyopaque, _size: u32) [*c]const Memory,
    makeRefRelease: *const fn (_data: ?*const anyopaque, _size: u32, _releaseFn: ?*anyopaque, _userData: ?*anyopaque) [*c]const Memory,
    setDebug: *const fn (_debug: u32) void,
    dbgTextClear: *const fn (_attr: u8, _small: bool) void,
    dbgTextImage: *const fn (_x: u16, _y: u16, _width: u16, _height: u16, _data: ?*const anyopaque, _pitch: u16) void,
    createIndexBuffer: *const fn (_mem: [*c]const Memory, _flags: u16) IndexBufferHandle,
    setIndexBufferName: *const fn (_handle: IndexBufferHandle, _name: [*c]const u8, _len: i32) void,
    destroyIndexBuffer: *const fn (_handle: IndexBufferHandle) void,
    createVertexLayout: *const fn (_layout: [*c]const VertexLayout) VertexLayoutHandle,
    destroyVertexLayout: *const fn (_layoutHandle: VertexLayoutHandle) void,
    createVertexBuffer: *const fn (_mem: [*c]const Memory, _layout: [*c]const VertexLayout, _flags: u16) VertexBufferHandle,
    setVertexBufferName: *const fn (_handle: VertexBufferHandle, _name: [*c]const u8, _len: i32) void,
    destroyVertexBuffer: *const fn (_handle: VertexBufferHandle) void,
    createDynamicIndexBuffer: *const fn (_num: u32, _flags: u16) DynamicIndexBufferHandle,
    createDynamicIndexBufferMem: *const fn (_mem: [*c]const Memory, _flags: u16) DynamicIndexBufferHandle,
    updateDynamicIndexBuffer: *const fn (_handle: DynamicIndexBufferHandle, _startIndex: u32, _mem: [*c]const Memory) void,
    destroyDynamicIndexBuffer: *const fn (_handle: DynamicIndexBufferHandle) void,
    createDynamicVertexBuffer: *const fn (_num: u32, _layout: [*c]const VertexLayout, _flags: u16) DynamicVertexBufferHandle,
    createDynamicVertexBufferMem: *const fn (_mem: [*c]const Memory, _layout: [*c]const VertexLayout, _flags: u16) DynamicVertexBufferHandle,
    updateDynamicVertexBuffer: *const fn (_handle: DynamicVertexBufferHandle, _startVertex: u32, _mem: [*c]const Memory) void,
    destroyDynamicVertexBuffer: *const fn (_handle: DynamicVertexBufferHandle) void,
    getAvailTransientIndexBuffer: *const fn (_num: u32, _index32: bool) u32,
    getAvailTransientVertexBuffer: *const fn (_num: u32, _layout: [*c]const VertexLayout) u32,
    getAvailInstanceDataBuffer: *const fn (_num: u32, _stride: u16) u32,
    allocTransientIndexBuffer: *const fn (_tib: [*c]TransientIndexBuffer, _num: u32, _index32: bool) void,
    allocTransientVertexBuffer: *const fn (_tvb: [*c]TransientVertexBuffer, _num: u32, _layout: [*c]const VertexLayout) void,
    allocTransientBuffers: *const fn (_tvb: [*c]TransientVertexBuffer, _layout: [*c]const VertexLayout, _numVertices: u32, _tib: [*c]TransientIndexBuffer, _numIndices: u32, _index32: bool) bool,
    allocInstanceDataBuffer: *const fn (_idb: [*c]InstanceDataBuffer, _num: u32, _stride: u16) void,
    createIndirectBuffer: *const fn (_num: u32) IndirectBufferHandle,
    destroyIndirectBuffer: *const fn (_handle: IndirectBufferHandle) void,
    createShader: *const fn (_mem: [*c]const Memory) ShaderHandle,
    getShaderUniforms: *const fn (_handle: ShaderHandle, _uniforms: [*c]UniformHandle, _max: u16) u16,
    setShaderName: *const fn (_handle: ShaderHandle, _name: [*c]const u8, _len: i32) void,
    destroyShader: *const fn (_handle: ShaderHandle) void,
    createProgram: *const fn (_vsh: ShaderHandle, _fsh: ShaderHandle, _destroyShaders: bool) ProgramHandle,
    createComputeProgram: *const fn (_csh: ShaderHandle, _destroyShaders: bool) ProgramHandle,
    destroyProgram: *const fn (_handle: ProgramHandle) void,
    isTextureValid: *const fn (_depth: u16, _cubeMap: bool, _numLayers: u16, _format: TextureFormat, _flags: u64) bool,
    isFrameBufferValid: *const fn (_num: u8, _attachment: [*c]const Attachment) bool,
    calcTextureSize: *const fn (_info: [*c]TextureInfo, _width: u16, _height: u16, _depth: u16, _cubeMap: bool, _hasMips: bool, _numLayers: u16, _format: TextureFormat) void,
    createTexture: *const fn (_mem: [*c]const Memory, _flags: u64, _skip: u8, _info: [*c]TextureInfo) TextureHandle,
    createTexture2D: *const fn (_width: u16, _height: u16, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: u64, _mem: [*c]const Memory) TextureHandle,
    createTexture2DScaled: *const fn (_ratio: BackbufferRatio, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: u64) TextureHandle,
    createTexture3D: *const fn (_width: u16, _height: u16, _depth: u16, _hasMips: bool, _format: TextureFormat, _flags: u64, _mem: [*c]const Memory) TextureHandle,
    createTextureCube: *const fn (_size: u16, _hasMips: bool, _numLayers: u16, _format: TextureFormat, _flags: u64, _mem: [*c]const Memory) TextureHandle,
    updateTexture2D: *const fn (_handle: TextureHandle, _layer: u16, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: [*c]const Memory, _pitch: u16) void,
    updateTexture3D: *const fn (_handle: TextureHandle, _mip: u8, _x: u16, _y: u16, _z: u16, _width: u16, _height: u16, _depth: u16, _mem: [*c]const Memory) void,
    updateTextureCube: *const fn (_handle: TextureHandle, _layer: u16, _side: u8, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: [*c]const Memory, _pitch: u16) void,
    readTexture: *const fn (_handle: TextureHandle, _data: ?*anyopaque, _mip: u8) u32,
    setTextureName: *const fn (_handle: TextureHandle, _name: [*c]const u8, _len: i32) void,
    getDirectAccessPtr: *const fn (_handle: TextureHandle) ?*anyopaque,
    destroyTexture: *const fn (_handle: TextureHandle) void,
    createFrameBuffer: *const fn (_width: u16, _height: u16, _format: TextureFormat, _textureFlags: u64) FrameBufferHandle,
    createFrameBufferScaled: *const fn (_ratio: BackbufferRatio, _format: TextureFormat, _textureFlags: u64) FrameBufferHandle,
    createFrameBufferFromHandles: *const fn (_num: u8, _handles: [*c]const TextureHandle, _destroyTexture: bool) FrameBufferHandle,
    createFrameBufferFromAttachment: *const fn (_num: u8, _attachment: [*c]const Attachment, _destroyTexture: bool) FrameBufferHandle,
    createFrameBufferFromNwh: *const fn (_nwh: ?*anyopaque, _width: u16, _height: u16, _format: TextureFormat, _depthFormat: TextureFormat) FrameBufferHandle,
    setFrameBufferName: *const fn (_handle: FrameBufferHandle, _name: [*c]const u8, _len: i32) void,
    getTexture: *const fn (_handle: FrameBufferHandle, _attachment: u8) TextureHandle,
    destroyFrameBuffer: *const fn (_handle: FrameBufferHandle) void,
    createUniform: *const fn (_name: [*c]const u8, _type: UniformType, _num: u16) UniformHandle,
    getUniformInfo: *const fn (_handle: UniformHandle, _info: [*c]UniformInfo) void,
    destroyUniform: *const fn (_handle: UniformHandle) void,
    createOcclusionQuery: *const fn () OcclusionQueryHandle,
    getResult: *const fn (_handle: OcclusionQueryHandle, _result: [*c]i32) OcclusionQueryResult,
    destroyOcclusionQuery: *const fn (_handle: OcclusionQueryHandle) void,
    setPaletteColor: *const fn (_index: u8, _rgba: [4]f32) void,
    setPaletteColorRgba8: *const fn (_index: u8, _rgba: u32) void,
    setViewName: *const fn (_id: ViewId, _name: [*c]const u8, _len: i32) void,
    setViewRect: *const fn (_id: ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void,
    setViewRectRatio: *const fn (_id: ViewId, _x: u16, _y: u16, _ratio: BackbufferRatio) void,
    setViewScissor: *const fn (_id: ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void,
    setViewClear: *const fn (_id: ViewId, _flags: u16, _rgba: u32, _depth: f32, _stencil: u8) void,
    setViewClearMrt: *const fn (_id: ViewId, _flags: u16, _depth: f32, _stencil: u8, _c0: u8, _c1: u8, _c2: u8, _c3: u8, _c4: u8, _c5: u8, _c6: u8, _c7: u8) void,
    setViewMode: *const fn (_id: ViewId, _mode: ViewMode) void,
    setViewFrameBuffer: *const fn (_id: ViewId, _handle: FrameBufferHandle) void,
    setViewTransform: *const fn (_id: ViewId, _view: ?*const anyopaque, _proj: ?*const anyopaque) void,
    setViewOrder: *const fn (_id: ViewId, _num: u16, _order: [*c]const ViewId) void,
    resetView: *const fn (_id: ViewId) void,
    getEncoder: *const fn () ?Encoder,
    requestScreenShot: *const fn (_handle: FrameBufferHandle, _filePath: [*c]const u8) void,
    renderFrame: *const fn (_msecs: i32) RenderFrame,
    overrideInternalTexturePtr: *const fn (_handle: TextureHandle, _ptr: usize) usize,
    overrideInternalTexture: *const fn (_handle: TextureHandle, _width: u16, _height: u16, _numMips: u8, _format: TextureFormat, _flags: u64) usize,
    setMarker: *const fn (_name: [*c]const u8, _len: i32) void,
    setState: *const fn (_state: u64, _rgba: u32) void,
    setCondition: *const fn (_handle: OcclusionQueryHandle, _visible: bool) void,
    setStencil: *const fn (_fstencil: u32, _bstencil: u32) void,
    setScissor: *const fn (_x: u16, _y: u16, _width: u16, _height: u16) u16,
    setScissorCached: *const fn (_cache: u16) void,
    setTransform: *const fn (_mtx: ?*const anyopaque, _num: u16) u32,
    setTransformCached: *const fn (_cache: u32, _num: u16) void,
    allocTransform: *const fn (_transform: [*c]Transform, _num: u16) u32,
    setUniform: *const fn (_handle: UniformHandle, _value: ?*const anyopaque, _num: u16) void,
    setIndexBuffer: *const fn (_handle: IndexBufferHandle, _firstIndex: u32, _numIndices: u32) void,
    setDynamicIndexBuffer: *const fn (_handle: DynamicIndexBufferHandle, _firstIndex: u32, _numIndices: u32) void,
    setTransientIndexBuffer: *const fn (_tib: [*c]const TransientIndexBuffer, _firstIndex: u32, _numIndices: u32) void,
    setVertexBuffer: *const fn (_stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32) void,
    setVertexBufferWithLayout: *const fn (_stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
    setDynamicVertexBuffer: *const fn (_stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32) void,
    setDynamicVertexBufferWithLayout: *const fn (_stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
    setTransientVertexBuffer: *const fn (_stream: u8, _tvb: [*c]const TransientVertexBuffer, _startVertex: u32, _numVertices: u32) void,
    setTransientVertexBufferWithLayout: *const fn (_stream: u8, _tvb: [*c]const TransientVertexBuffer, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
    setVertexCount: *const fn (_numVertices: u32) void,
    setInstanceDataBuffer: *const fn (_idb: [*c]const InstanceDataBuffer, _start: u32, _num: u32) void,
    setInstanceDataFromVertexBuffer: *const fn (_handle: VertexBufferHandle, _startVertex: u32, _num: u32) void,
    setInstanceDataFromDynamicVertexBuffer: *const fn (_handle: DynamicVertexBufferHandle, _startVertex: u32, _num: u32) void,
    setInstanceCount: *const fn (_numInstances: u32) void,
    setTexture: *const fn (_stage: u8, _sampler: UniformHandle, _handle: TextureHandle, _flags: u32) void,
    touch: *const fn (_id: ViewId) void,
    submit: *const fn (_id: ViewId, _program: ProgramHandle, _depth: u32, _flags: u8) void,
    submitOcclusionQuery: *const fn (_id: ViewId, _program: ProgramHandle, _occlusionQuery: OcclusionQueryHandle, _depth: u32, _flags: u8) void,
    submitIndirect: *const fn (_id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _depth: u32, _flags: u8) void,
    submitIndirectCount: *const fn (_id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _numHandle: IndexBufferHandle, _numIndex: u32, _numMax: u32, _depth: u32, _flags: u8) void,
    setComputeIndexBuffer: *const fn (_stage: u8, _handle: IndexBufferHandle, _access: Access) void,
    setComputeVertexBuffer: *const fn (_stage: u8, _handle: VertexBufferHandle, _access: Access) void,
    setComputeDynamicIndexBuffer: *const fn (_stage: u8, _handle: DynamicIndexBufferHandle, _access: Access) void,
    setComputeDynamicVertexBuffer: *const fn (_stage: u8, _handle: DynamicVertexBufferHandle, _access: Access) void,
    setComputeIndirectBuffer: *const fn (_stage: u8, _handle: IndirectBufferHandle, _access: Access) void,
    setImage: *const fn (_stage: u8, _handle: TextureHandle, _mip: u8, _access: Access, _format: TextureFormat) void,
    dispatch: *const fn (_id: ViewId, _program: ProgramHandle, _numX: u32, _numY: u32, _numZ: u32, _flags: u8) void,
    dispatchIndirect: *const fn (_id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _flags: u8) void,
    discard: *const fn (_flags: u8) void,
    blit: *const fn (_id: ViewId, _dst: TextureHandle, _dstMip: u8, _dstX: u16, _dstY: u16, _dstZ: u16, _src: TextureHandle, _srcMip: u8, _srcX: u16, _srcY: u16, _srcZ: u16, _width: u16, _height: u16, _depth: u16) void,

    // Attr
    layoutBegin: *const fn (self: *VertexLayout, _rendererType: Backend) *VertexLayout,
    layoutAdd: *const fn (self: *VertexLayout, _attrib: Attrib, _num: u8, _type: AttribType, _normalized: bool, _asInt: bool) *VertexLayout,
    layoutDecode: *const fn (self: *const VertexLayout, _attrib: Attrib, _num: [*c]u8, _type: [*c]AttribType, _normalized: [*c]bool, _asInt: [*c]bool) void,
    layoutHas: *const fn (self: *const VertexLayout, _attrib: Attrib) bool,
    layoutSkip: *const fn (self: *VertexLayout, _num: u8) *VertexLayout,
    layoutEnd: *const fn (self: *VertexLayout) void,
};

pub const Encoder = struct {
    pub inline fn setMarker(self: Encoder, _name: [*c]const u8, _len: i32) void {
        return self.vtable.encoderSetMarker(self.ptr, _name, _len);
    }
    pub inline fn setState(self: Encoder, _state: u64, _rgba: u32) void {
        return self.vtable.encoderSetState(self.ptr, _state, _rgba);
    }
    pub inline fn setCondition(self: Encoder, _handle: OcclusionQueryHandle, _visible: bool) void {
        return self.vtable.encoderSetCondition(self.ptr, _handle, _visible);
    }
    pub inline fn setStencil(self: Encoder, _fstencil: u32, _bstencil: u32) void {
        return self.vtable.encoderSetStencil(self.ptr, _fstencil, _bstencil);
    }
    pub inline fn setScissor(self: Encoder, _x: u16, _y: u16, _width: u16, _height: u16) u16 {
        return self.vtable.encoderSetScissor(self.ptr, _x, _y, _width, _height);
    }
    pub inline fn setScissorCached(self: Encoder, _cache: u16) void {
        return self.vtable.encoderSetScissorCached(self.ptr, _cache);
    }
    pub inline fn setTransform(self: Encoder, _mtx: ?*const anyopaque, _num: u16) u32 {
        return self.vtable.encoderSetTransform(self.ptr, _mtx, _num);
    }
    pub inline fn setTransformCached(self: Encoder, _cache: u32, _num: u16) void {
        return self.vtable.encoderSetTransformCached(self.ptr, _cache, _num);
    }
    pub inline fn allocTransform(self: Encoder, _transform: [*c]Transform, _num: u16) u32 {
        return self.vtable.encoderAllocTransform(self.ptr, _transform, _num);
    }
    pub inline fn setUniform(self: Encoder, _handle: UniformHandle, _value: ?*const anyopaque, _num: u16) void {
        return self.vtable.encoderSetUniform(self.ptr, _handle, _value, _num);
    }
    pub inline fn setIndexBuffer(self: Encoder, _handle: IndexBufferHandle, _firstIndex: u32, _numIndices: u32) void {
        return self.vtable.encoderSetIndexBuffer(self.ptr, _handle, _firstIndex, _numIndices);
    }
    pub inline fn setDynamicIndexBuffer(self: Encoder, _handle: DynamicIndexBufferHandle, _firstIndex: u32, _numIndices: u32) void {
        return self.vtable.encoderSetDynamicIndexBuffer(self.ptr, _handle, _firstIndex, _numIndices);
    }
    pub inline fn setTransientIndexBuffer(self: Encoder, _tib: [*c]const TransientIndexBuffer, _firstIndex: u32, _numIndices: u32) void {
        return self.vtable.encoderSetTransientIndexBuffer(self.ptr, _tib, _firstIndex, _numIndices);
    }
    pub inline fn setVertexBuffer(self: Encoder, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32) void {
        return self.vtable.encoderSetVertexBuffer(self.ptr, _stream, _handle, _startVertex, _numVertices);
    }
    pub inline fn setVertexBufferWithLayout(self: Encoder, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void {
        return self.vtable.encoderSetVertexBufferWithLayout(self.ptr, _stream, _handle, _startVertex, _numVertices, _layoutHandle);
    }
    pub inline fn setDynamicVertexBuffer(self: Encoder, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32) void {
        return self.vtable.encoderSetDynamicVertexBuffer(self.ptr, _stream, _handle, _startVertex, _numVertices);
    }
    pub inline fn setDynamicVertexBufferWithLayout(self: Encoder, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void {
        return self.vtable.encoderSetDynamicVertexBufferWithLayout(self.ptr, _stream, _handle, _startVertex, _numVertices, _layoutHandle);
    }
    pub inline fn setTransientVertexBuffer(self: Encoder, _stream: u8, _tvb: [*c]const TransientVertexBuffer, _startVertex: u32, _numVertices: u32) void {
        return self.vtable.encoderSetTransientVertexBuffer(self.ptr, _stream, _tvb, _startVertex, _numVertices);
    }
    pub inline fn setTransientVertexBufferWithLayout(self: Encoder, _stream: u8, _tvb: [*c]const TransientVertexBuffer, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void {
        return self.vtable.encoderSetTransientVertexBufferWithLayout(self.ptr, _stream, _tvb, _startVertex, _numVertices, _layoutHandle);
    }
    pub inline fn setVertexCount(self: Encoder, _numVertices: u32) void {
        return self.vtable.encoderSetVertexCount(self.ptr, _numVertices);
    }
    pub inline fn setInstanceDataBuffer(self: Encoder, _idb: [*c]const InstanceDataBuffer, _start: u32, _num: u32) void {
        return self.vtable.encoderSetInstanceDataBuffer(self.ptr, _idb, _start, _num);
    }
    pub inline fn setInstanceDataFromVertexBuffer(self: Encoder, _handle: VertexBufferHandle, _startVertex: u32, _num: u32) void {
        return self.vtable.encoderSetInstanceDataFromVertexBuffer(self.ptr, _handle, _startVertex, _num);
    }
    pub inline fn setInstanceDataFromDynamicVertexBuffer(self: Encoder, _handle: DynamicVertexBufferHandle, _startVertex: u32, _num: u32) void {
        return self.vtable.encoderSetInstanceDataFromDynamicVertexBuffer(self.ptr, _handle, _startVertex, _num);
    }
    pub inline fn setInstanceCount(self: Encoder, _numInstances: u32) void {
        return self.vtable.encoderSetInstanceCount(self.ptr, _numInstances);
    }
    pub inline fn setTexture(self: Encoder, _stage: u8, _sampler: UniformHandle, _handle: TextureHandle, _flags: u32) void {
        return self.vtable.encoderSetTexture(self.ptr, _stage, _sampler, _handle, _flags);
    }
    pub inline fn touch(self: Encoder, _id: ViewId) void {
        return self.vtable.encoderTouch(self.ptr, _id);
    }
    pub inline fn submit(self: Encoder, _id: ViewId, _program: ProgramHandle, _depth: u32, _flags: u8) void {
        return self.vtable.encoderSubmit(self.ptr, _id, _program, _depth, _flags);
    }
    pub inline fn submitOcclusionQuery(self: Encoder, _id: ViewId, _program: ProgramHandle, _occlusionQuery: OcclusionQueryHandle, _depth: u32, _flags: u8) void {
        return self.vtable.encoderSubmitOcclusionQuery(self.ptr, _id, _program, _occlusionQuery, _depth, _flags);
    }
    pub inline fn submitIndirect(self: Encoder, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _depth: u32, _flags: u8) void {
        return self.vtable.encoderSubmitIndirect(self.ptr, _id, _program, _indirectHandle, _start, _num, _depth, _flags);
    }
    pub inline fn submitIndirectCount(self: Encoder, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _numHandle: IndexBufferHandle, _numIndex: u32, _numMax: u32, _depth: u32, _flags: u8) void {
        return self.vtable.encoderSubmitIndirectCount(self.ptr, _id, _program, _indirectHandle, _start, _numHandle, _numIndex, _numMax, _depth, _flags);
    }
    pub inline fn setComputeIndexBuffer(self: Encoder, _stage: u8, _handle: IndexBufferHandle, _access: Access) void {
        return self.vtable.encoderSetComputeIndexBuffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeVertexBuffer(self: Encoder, _stage: u8, _handle: VertexBufferHandle, _access: Access) void {
        return self.vtable.encoderSetComputeVertexBuffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeDynamicIndexBuffer(self: Encoder, _stage: u8, _handle: DynamicIndexBufferHandle, _access: Access) void {
        return self.vtable.encoderSetComputeDynamicIndexBuffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeDynamicVertexBuffer(self: Encoder, _stage: u8, _handle: DynamicVertexBufferHandle, _access: Access) void {
        return self.vtable.encoderSetComputeDynamicVertexBuffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setComputeIndirectBuffer(self: Encoder, _stage: u8, _handle: IndirectBufferHandle, _access: Access) void {
        return self.vtable.encoderSetComputeIndirectBuffer(self.ptr, _stage, _handle, _access);
    }
    pub inline fn setImage(self: Encoder, _stage: u8, _handle: TextureHandle, _mip: u8, _access: Access, _format: TextureFormat) void {
        return self.vtable.encoderSetImage(self.ptr, _stage, _handle, _mip, _access, _format);
    }
    pub inline fn dispatch(self: Encoder, _id: ViewId, _program: ProgramHandle, _numX: u32, _numY: u32, _numZ: u32, _flags: u8) void {
        return self.vtable.encoderDispatch(self.ptr, _id, _program, _numX, _numY, _numZ, _flags);
    }
    pub inline fn dispatchIndirect(self: Encoder, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _flags: u8) void {
        return self.vtable.encoderDispatchIndirect(self.ptr, _id, _program, _indirectHandle, _start, _num, _flags);
    }
    pub inline fn discard(self: Encoder, _flags: u8) void {
        return self.vtable.encoderDiscard(self.ptr, _flags);
    }
    pub inline fn blit(self: Encoder, _id: ViewId, _dst: TextureHandle, _dstMip: u8, _dstX: u16, _dstY: u16, _dstZ: u16, _src: TextureHandle, _srcMip: u8, _srcX: u16, _srcY: u16, _srcZ: u16, _width: u16, _height: u16, _depth: u16) void {
        return self.vtable.encoderBlit(self.ptr, _id, _dst, _dstMip, _dstX, _dstY, _dstZ, _src, _srcMip, _srcX, _srcY, _srcZ, _width, _height, _depth);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // Encoder
        encoderSetMarker: *const fn (self: *anyopaque, _name: [*c]const u8, _len: i32) void,
        encoderSetState: *const fn (self: *anyopaque, _state: u64, _rgba: u32) void,
        encoderSetCondition: *const fn (self: *anyopaque, _handle: OcclusionQueryHandle, _visible: bool) void,
        encoderSetStencil: *const fn (self: *anyopaque, _fstencil: u32, _bstencil: u32) void,
        encoderSetScissor: *const fn (self: *anyopaque, _x: u16, _y: u16, _width: u16, _height: u16) u16,
        encoderSetScissorCached: *const fn (self: *anyopaque, _cache: u16) void,
        encoderSetTransform: *const fn (self: *anyopaque, _mtx: ?*const anyopaque, _num: u16) u32,
        encoderSetTransformCached: *const fn (self: *anyopaque, _cache: u32, _num: u16) void,
        encoderAllocTransform: *const fn (self: *anyopaque, _transform: [*c]Transform, _num: u16) u32,
        encoderSetUniform: *const fn (self: *anyopaque, _handle: UniformHandle, _value: ?*const anyopaque, _num: u16) void,
        encoderSetIndexBuffer: *const fn (self: *anyopaque, _handle: IndexBufferHandle, _firstIndex: u32, _numIndices: u32) void,
        encoderSetDynamicIndexBuffer: *const fn (self: *anyopaque, _handle: DynamicIndexBufferHandle, _firstIndex: u32, _numIndices: u32) void,
        encoderSetTransientIndexBuffer: *const fn (self: *anyopaque, _tib: [*c]const TransientIndexBuffer, _firstIndex: u32, _numIndices: u32) void,
        encoderSetVertexBuffer: *const fn (self: *anyopaque, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32) void,
        encoderSetVertexBufferWithLayout: *const fn (self: *anyopaque, _stream: u8, _handle: VertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
        encoderSetDynamicVertexBuffer: *const fn (self: *anyopaque, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32) void,
        encoderSetDynamicVertexBufferWithLayout: *const fn (self: *anyopaque, _stream: u8, _handle: DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
        encoderSetTransientVertexBuffer: *const fn (self: *anyopaque, _stream: u8, _tvb: [*c]const TransientVertexBuffer, _startVertex: u32, _numVertices: u32) void,
        encoderSetTransientVertexBufferWithLayout: *const fn (self: *anyopaque, _stream: u8, _tvb: [*c]const TransientVertexBuffer, _startVertex: u32, _numVertices: u32, _layoutHandle: VertexLayoutHandle) void,
        encoderSetVertexCount: *const fn (self: *anyopaque, _numVertices: u32) void,
        encoderSetInstanceDataBuffer: *const fn (self: *anyopaque, _idb: [*c]const InstanceDataBuffer, _start: u32, _num: u32) void,
        encoderSetInstanceDataFromVertexBuffer: *const fn (self: *anyopaque, _handle: VertexBufferHandle, _startVertex: u32, _num: u32) void,
        encoderSetInstanceDataFromDynamicVertexBuffer: *const fn (self: *anyopaque, _handle: DynamicVertexBufferHandle, _startVertex: u32, _num: u32) void,
        encoderSetInstanceCount: *const fn (self: *anyopaque, _numInstances: u32) void,
        encoderSetTexture: *const fn (self: *anyopaque, _stage: u8, _sampler: UniformHandle, _handle: TextureHandle, _flags: u32) void,
        encoderTouch: *const fn (self: *anyopaque, _id: ViewId) void,
        encoderSubmit: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _depth: u32, _flags: u8) void,
        encoderSubmitOcclusionQuery: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _occlusionQuery: OcclusionQueryHandle, _depth: u32, _flags: u8) void,
        encoderSubmitIndirect: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _depth: u32, _flags: u8) void,
        encoderSubmitIndirectCount: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _numHandle: IndexBufferHandle, _numIndex: u32, _numMax: u32, _depth: u32, _flags: u8) void,
        encoderSetComputeIndexBuffer: *const fn (self: *anyopaque, _stage: u8, _handle: IndexBufferHandle, _access: Access) void,
        encoderSetComputeVertexBuffer: *const fn (self: *anyopaque, _stage: u8, _handle: VertexBufferHandle, _access: Access) void,
        encoderSetComputeDynamicIndexBuffer: *const fn (self: *anyopaque, _stage: u8, _handle: DynamicIndexBufferHandle, _access: Access) void,
        encoderSetComputeDynamicVertexBuffer: *const fn (self: *anyopaque, _stage: u8, _handle: DynamicVertexBufferHandle, _access: Access) void,
        encoderSetComputeIndirectBuffer: *const fn (self: *anyopaque, _stage: u8, _handle: IndirectBufferHandle, _access: Access) void,
        encoderSetImage: *const fn (self: *anyopaque, _stage: u8, _handle: TextureHandle, _mip: u8, _access: Access, _format: TextureFormat) void,
        encoderDispatch: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _numX: u32, _numY: u32, _numZ: u32, _flags: u8) void,
        encoderDispatchIndirect: *const fn (self: *anyopaque, _id: ViewId, _program: ProgramHandle, _indirectHandle: IndirectBufferHandle, _start: u32, _num: u32, _flags: u8) void,
        encoderDiscard: *const fn (self: *anyopaque, _flags: u8) void,
        encoderBlit: *const fn (self: *anyopaque, _id: ViewId, _dst: TextureHandle, _dstMip: u8, _dstX: u16, _dstY: u16, _dstZ: u16, _src: TextureHandle, _srcMip: u8, _srcX: u16, _srcY: u16, _srcZ: u16, _width: u16, _height: u16, _depth: u16) void,
    };
};

pub const DDAxis = enum(c_int) {
    X,
    Y,
    Z,
    Count,
};

pub const DDVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const DDSpriteHandle = extern struct {
    idx: u16,

    fn isValid(sprite: DDSpriteHandle) bool {
        return sprite.idx != std.math.maxInt(u16);
    }
};

pub const DDGeometryHandle = extern struct {
    idx: u16,

    fn isValid(geometry: DDGeometryHandle) bool {
        return geometry.idx != std.math.maxInt(u16);
    }
};

pub const DDEncoder = struct {
    //
    pub inline fn begin(dde: DDEncoder, _viewId: u16, _depthTestLess: bool, _encoder: Encoder) void {
        dde.vtable.encoderBegin(dde.ptr, _viewId, _depthTestLess, _encoder.ptr);
    }

    //
    pub inline fn end(dde: DDEncoder) void {
        dde.vtable.encoderEnd(dde.ptr);
    }

    //
    pub inline fn push(dde: DDEncoder) void {
        dde.vtable.encoderPush(dde.ptr);
    }

    //
    pub inline fn pop(dde: DDEncoder) void {
        dde.vtable.encoderPop(dde.ptr);
    }

    //
    pub inline fn setDepthTestLess(dde: DDEncoder, _depthTestLess: bool) void {
        dde.vtable.encoderSetDepthTestLess(dde.ptr, _depthTestLess);
    }

    //
    pub inline fn setState(dde: DDEncoder, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void {
        dde.vtable.encoderSetState(dde.ptr, _depthTest, _depthWrite, _clockwise);
    }

    //
    pub inline fn setColor(dde: DDEncoder, _abgr: u32) void {
        dde.vtable.encoderSetColor(dde.ptr, _abgr);
    }

    //
    pub inline fn setLod(dde: DDEncoder, _lod: u8) void {
        dde.vtable.encoderSetLod(dde.ptr, _lod);
    }

    //
    pub inline fn setWireframe(dde: DDEncoder, _wireframe: bool) void {
        dde.vtable.encoderSetWireframe(dde.ptr, _wireframe);
    }

    //
    pub inline fn setStipple(dde: DDEncoder, _stipple: bool, _scale: f32, _offset: f32) void {
        dde.vtable.encoderSetStipple(dde.ptr, _stipple, _scale, _offset);
    }

    //
    pub inline fn setSpin(dde: DDEncoder, _spin: f32) void {
        dde.vtable.encoderSetSpin(dde, _spin);
    }

    //
    pub inline fn setTransform(dde: DDEncoder, _mtx: ?*const anyopaque) void {
        dde.vtable.encoderSetTransform(dde.ptr, _mtx);
    }

    //
    pub inline fn setTranslate(dde: DDEncoder, _xyz: [3]f32) void {
        dde.vtable.encoderSetTranslate(dde.ptr, _xyz[0], _xyz[1], _xyz[2]);
    }

    //
    pub inline fn pushTransform(dde: DDEncoder, _mtx: *const anyopaque) void {
        dde.vtable.encoderPushTransform(dde.ptr, _mtx);
    }

    //
    pub inline fn popTransform(dde: DDEncoder) void {
        dde.vtable.encoderPopTransform(dde.ptr);
    }

    //
    pub inline fn moveTo(dde: DDEncoder, _xyz: [3]f32) void {
        dde.vtable.encoderMoveTo(dde.ptr, _xyz[0], _xyz[1], _xyz[2]);
    }

    //
    pub inline fn lineTo(dde: DDEncoder, _xyz: [3]f32) void {
        dde.vtable.encoderLineTo(dde.ptr, _xyz[0], _xyz[1], _xyz[2]);
    }

    //
    pub inline fn close(dde: DDEncoder) void {
        dde.vtable.encoderClose(dde.ptr);
    }

    ///
    pub inline fn drawAABB(dde: DDEncoder, min: [3]f32, max: [3]f32) void {
        dde.vtable.encoderDrawAABB(dde.ptr, min, max);
    }

    ///
    pub inline fn drawCylinder(dde: DDEncoder, pos: [3]f32, _end: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawCylinder(dde.ptr, pos, _end, radius);
    }

    ///
    pub inline fn drawCapsule(dde: DDEncoder, pos: [3]f32, _end: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawCapsule(dde.ptr, pos, _end, radius);
    }

    ///
    pub inline fn drawDisk(dde: DDEncoder, center: [3]f32, normal: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawDisk(dde.ptr, center, normal, radius);
    }

    ///
    pub inline fn drawObb(dde: DDEncoder, _obb: [3]f32) void {
        dde.vtable.encoderDrawObb(dde.ptr, _obb);
    }

    ///
    pub inline fn drawSphere(dde: DDEncoder, center: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawSphere(dde.ptr, center, radius);
    }

    ///
    pub inline fn drawTriangle(dde: DDEncoder, v0: [3]f32, v1: [3]f32, v2: [3]f32) void {
        dde.vtable.encoderDrawTriangle(dde.ptr, &v0, &v1, &v2);
    }

    ///
    pub inline fn drawCone(dde: DDEncoder, pos: [3]f32, _end: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawCone(dde.ptr, pos, _end, radius);
    }

    //
    pub inline fn drawGeometry(dde: DDEncoder, _handle: DDGeometryHandle) void {
        dde.vtable.encoderDrawGeometry(dde.ptr, _handle);
    }

    ///
    pub inline fn drawLineList(dde: DDEncoder, _numVertices: u32, _vertices: []const DDVertex, _numIndices: u32, _indices: ?[*]const u16) void {
        dde.vtable.encoderDrawLineList(dde.ptr, _numVertices, _vertices.ptr, _numIndices, _indices);
    }

    ///
    pub inline fn drawTriList(dde: DDEncoder, _numVertices: u32, _vertices: []const DDVertex, _numIndices: u32, _indices: ?[*]const u16) void {
        dde.vtable.encoderDrawTriList(dde.ptr, _numVertices, _vertices.ptr, _numIndices, _indices.?);
    }

    ///
    pub inline fn drawFrustum(dde: DDEncoder, _viewProj: [16]f32) void {
        dde.vtable.encoderDrawFrustum(dde.ptr, &_viewProj);
    }

    ///
    pub inline fn drawArc(dde: DDEncoder, _axis: DDAxis, _xyz: [3]f32, _radius: f32, _degrees: f32) void {
        dde.vtable.encoderDrawArc(dde.ptr, _axis, _xyz[0], _xyz[1], _xyz[2], _radius, _degrees);
    }

    ///
    pub inline fn drawCircle(dde: DDEncoder, _normal: [3]f32, _center: [3]f32, _radius: f32, _weight: f32) void {
        dde.vtable.encoderDrawCircle(dde.ptr, _normal, _center, _radius, _weight);
    }

    ///
    pub inline fn drawCircleAxis(dde: DDEncoder, _axis: DDAxis, _xyz: [3]f32, _radius: f32, _weight: f32) void {
        dde.vtable.encoderDrawCircleAxis(dde.ptr, _axis, _xyz, _radius, _weight);
    }

    ///
    pub inline fn drawQuad(dde: DDEncoder, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        dde.vtable.encoderDrawQuad(dde.ptr, _normal, _center, _size);
    }

    ///
    pub inline fn drawQuadSprite(dde: DDEncoder, _handle: DDSpriteHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        dde.vtable.encoderDrawQuadSprite(dde.ptr, _handle, _normal, _center, _size);
    }

    ///
    pub inline fn drawQuadTexture(dde: DDEncoder, _handle: TextureHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        dde.vtable.encoderDrawQuadTexture(dde.ptr, _handle, _normal, _center, _size);
    }

    ///
    pub inline fn drawAxis(dde: DDEncoder, _xyz: [3]f32, _len: f32, _highlight: DDAxis, _thickness: f32) void {
        dde.vtable.encoderDrawAxis(dde.ptr, _xyz, _len, _highlight, _thickness);
    }

    ///
    pub inline fn drawGrid(dde: DDEncoder, _normal: [3]f32, _center: [3]f32, _size: u32, _step: f32) void {
        dde.vtable.encoderDrawGrid(dde.ptr, _normal, _center, _size, _step);
    }

    ///
    pub inline fn drawGridAxis(dde: DDEncoder, _axis: DDAxis, _center: [3]f32, _size: u32, _step: f32) void {
        dde.vtable.encoderDrawGridAxis(dde.ptr, _axis, _center, _size, _step);
    }

    ///
    pub inline fn drawOrb(dde: DDEncoder, _xyz: [3]f32, _radius: f32, _highlight: DDAxis) void {
        dde.vtable.encoderDrawOrb(dde.ptr, _xyz, _radius, _highlight);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        encoderBegin: *const fn (dde: *anyopaque, _viewId: u16, _depthTestLess: bool, _encoder: *anyopaque) void,
        encoderEnd: *const fn (dde: *anyopaque) void,
        encoderPush: *const fn (dde: *anyopaque) void,
        encoderPop: *const fn (dde: *anyopaque) void,
        encoderSetDepthTestLess: *const fn (dde: *anyopaque, _depthTestLess: bool) void,
        encoderSetState: *const fn (dde: *anyopaque, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void,
        encoderSetColor: *const fn (dde: *anyopaque, _abgr: u32) void,
        encoderSetLod: *const fn (dde: *anyopaque, _lod: u8) void,
        encoderSetWireframe: *const fn (dde: *anyopaque, _wireframe: bool) void,
        encoderSetStipple: *const fn (dde: *anyopaque, _stipple: bool, _scale: f32, _offset: f32) void,
        encoderSetSpin: *const fn (dde: *anyopaque, _spin: f32) void,
        encoderSetTransform: *const fn (dde: *anyopaque, _mtx: ?*const anyopaque) void,
        encoderSetTranslate: *const fn (dde: *anyopaque, _xyz: [3]f32) void,
        encoderPushTransform: *const fn (dde: *anyopaque, _mtx: *const anyopaque) void,
        encoderPopTransform: *const fn (dde: *anyopaque) void,
        encoderMoveTo: *const fn (dde: *anyopaque, _xyz: [3]f32) void,
        encoderLineTo: *const fn (dde: *anyopaque, _xyz: [3]f32) void,
        encoderClose: *const fn (dde: *anyopaque) void,
        encoderDrawAABB: *const fn (dde: *anyopaque, min: [3]f32, max: [3]f32) void,
        encoderDrawCylinder: *const fn (dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void,
        encoderDrawCapsule: *const fn (dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void,
        encoderDrawDisk: *const fn (dde: *anyopaque, center: [3]f32, normal: [3]f32, radius: f32) void,
        encoderDrawObb: *const fn (dde: *anyopaque, _obb: [3]f32) void,
        encoderDrawSphere: *const fn (dde: *anyopaque, center: [3]f32, radius: f32) void,
        encoderDrawTriangle: *const fn (dde: *anyopaque, v0: [3]f32, v1: [3]f32, v2: [3]f32) void,
        encoderDrawCone: *const fn (dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void,
        encoderDrawGeometry: *const fn (dde: *anyopaque, _handle: DDGeometryHandle) void,
        encoderDrawLineList: *const fn (dde: *anyopaque, _numVertices: u32, _vertices: []const DDVertex, _numIndices: u32, _indices: ?[*]const u16) void,
        encoderDrawTriList: *const fn (dde: *anyopaque, _numVertices: u32, _vertices: []const DDVertex, _numIndices: u32, _indices: ?[*]const u16) void,
        encoderDrawFrustum: *const fn (dde: *anyopaque, _viewProj: []const f32) void,
        encoderDrawArc: *const fn (dde: *anyopaque, _axis: DDAxis, _xyz: [3]f32, _radius: f32, _degrees: f32) void,
        encoderDrawCircle: *const fn (dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _radius: f32, _weight: f32) void,
        encoderDrawCircleAxis: *const fn (dde: *anyopaque, _axis: DDAxis, _xyz: [3]f32, _radius: f32, _weight: f32) void,
        encoderDrawQuad: *const fn (dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _size: f32) void,
        encoderDrawQuadSprite: *const fn (dde: *anyopaque, _handle: DDSpriteHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void,
        encoderDrawQuadTexture: *const fn (dde: *anyopaque, _handle: TextureHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void,
        encoderDrawAxis: *const fn (dde: *anyopaque, _xyz: [3]f32, _len: f32, _highlight: DDAxis, _thickness: f32) void,
        encoderDrawGrid: *const fn (dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _size: u32, _step: f32) void,
        encoderDrawGridAxis: *const fn (dde: *anyopaque, _axis: DDAxis, _center: [3]f32, _size: u32, _step: f32) void,
        encoderDrawOrb: *const fn (dde: *anyopaque, _xyz: [3]f32, _radius: f32, _highlight: DDAxis) void,
    };
};

pub const GpuDDApi = struct {
    createSprite: *const fn (width: u16, height: u16, _data: []const u8) DDSpriteHandle,
    destroySprite: *const fn (handle: DDSpriteHandle) void,
    createGeometry: *const fn (numVertices: u32, vertices: []const DDVertex, numIndices: u32, indices: ?[*]const u8, index32: bool) DDGeometryHandle,
    destroyGeometry: *const fn (handle: DDGeometryHandle) void,

    encoderCreate: *const fn () DDEncoder,
    encoderDestroy: *const fn (encoder: DDEncoder) void,
};

pub const ViewId = u16;

pub const StateFlags = u64;
/// Enable R write.
pub const StateFlags_WriteR: StateFlags = 0x0000000000000001;

/// Enable G write.
pub const StateFlags_WriteG: StateFlags = 0x0000000000000002;

/// Enable B write.
pub const StateFlags_WriteB: StateFlags = 0x0000000000000004;

/// Enable alpha write.
pub const StateFlags_WriteA: StateFlags = 0x0000000000000008;

/// Enable depth write.
pub const StateFlags_WriteZ: StateFlags = 0x0000004000000000;

/// Enable RGB write.
pub const StateFlags_WriteRgb: StateFlags = 0x0000000000000007;

/// Write all channels mask.
pub const StateFlags_WriteMask: StateFlags = 0x000000400000000f;

/// Enable depth test, less.
pub const StateFlags_DepthTestLess: StateFlags = 0x0000000000000010;

/// Enable depth test, less or equal.
pub const StateFlags_DepthTestLequal: StateFlags = 0x0000000000000020;

/// Enable depth test, equal.
pub const StateFlags_DepthTestEqual: StateFlags = 0x0000000000000030;

/// Enable depth test, greater or equal.
pub const StateFlags_DepthTestGequal: StateFlags = 0x0000000000000040;

/// Enable depth test, greater.
pub const StateFlags_DepthTestGreater: StateFlags = 0x0000000000000050;

/// Enable depth test, not equal.
pub const StateFlags_DepthTestNotequal: StateFlags = 0x0000000000000060;

/// Enable depth test, never.
pub const StateFlags_DepthTestNever: StateFlags = 0x0000000000000070;

/// Enable depth test, always.
pub const StateFlags_DepthTestAlways: StateFlags = 0x0000000000000080;
pub const StateFlags_DepthTestShift: StateFlags = 4;
pub const StateFlags_DepthTestMask: StateFlags = 0x00000000000000f0;

/// 0, 0, 0, 0
pub const StateFlags_BlendZero: StateFlags = 0x0000000000001000;

/// 1, 1, 1, 1
pub const StateFlags_BlendOne: StateFlags = 0x0000000000002000;

/// Rs, Gs, Bs, As
pub const StateFlags_BlendSrcColor: StateFlags = 0x0000000000003000;

/// 1-Rs, 1-Gs, 1-Bs, 1-As
pub const StateFlags_BlendInvSrcColor: StateFlags = 0x0000000000004000;

/// As, As, As, As
pub const StateFlags_BlendSrcAlpha: StateFlags = 0x0000000000005000;

/// 1-As, 1-As, 1-As, 1-As
pub const StateFlags_BlendInvSrcAlpha: StateFlags = 0x0000000000006000;

/// Ad, Ad, Ad, Ad
pub const StateFlags_BlendDstAlpha: StateFlags = 0x0000000000007000;

/// 1-Ad, 1-Ad, 1-Ad ,1-Ad
pub const StateFlags_BlendInvDstAlpha: StateFlags = 0x0000000000008000;

/// Rd, Gd, Bd, Ad
pub const StateFlags_BlendDstColor: StateFlags = 0x0000000000009000;

/// 1-Rd, 1-Gd, 1-Bd, 1-Ad
pub const StateFlags_BlendInvDstColor: StateFlags = 0x000000000000a000;

/// f, f, f, 1; f = min(As, 1-Ad)
pub const StateFlags_BlendSrcAlphaSat: StateFlags = 0x000000000000b000;

/// Blend factor
pub const StateFlags_BlendFactor: StateFlags = 0x000000000000c000;

/// 1-Blend factor
pub const StateFlags_BlendInvFactor: StateFlags = 0x000000000000d000;
pub const StateFlags_BlendShift: StateFlags = 12;
pub const StateFlags_BlendMask: StateFlags = 0x000000000ffff000;

/// Blend add: src + dst.
pub const StateFlags_BlendEquationAdd: StateFlags = 0x0000000000000000;

/// Blend subtract: src - dst.
pub const StateFlags_BlendEquationSub: StateFlags = 0x0000000010000000;

/// Blend reverse subtract: dst - src.
pub const StateFlags_BlendEquationRevsub: StateFlags = 0x0000000020000000;

/// Blend min: min(src, dst).
pub const StateFlags_BlendEquationMin: StateFlags = 0x0000000030000000;

/// Blend max: max(src, dst).
pub const StateFlags_BlendEquationMax: StateFlags = 0x0000000040000000;
pub const StateFlags_BlendEquationShift: StateFlags = 28;
pub const StateFlags_BlendEquationMask: StateFlags = 0x00000003f0000000;

/// Cull clockwise triangles.
pub const StateFlags_CullCw: StateFlags = 0x0000001000000000;

/// Cull counter-clockwise triangles.
pub const StateFlags_CullCcw: StateFlags = 0x0000002000000000;
pub const StateFlags_CullShift: StateFlags = 36;
pub const StateFlags_CullMask: StateFlags = 0x0000003000000000;
pub const StateFlags_AlphaRefShift: StateFlags = 40;
pub const StateFlags_AlphaRefMask: StateFlags = 0x0000ff0000000000;

/// Tristrip.
pub const StateFlags_PtTristrip: StateFlags = 0x0001000000000000;

/// Lines.
pub const StateFlags_PtLines: StateFlags = 0x0002000000000000;

/// Line strip.
pub const StateFlags_PtLinestrip: StateFlags = 0x0003000000000000;

/// Points.
pub const StateFlags_PtPoints: StateFlags = 0x0004000000000000;
pub const StateFlags_PtShift: StateFlags = 48;
pub const StateFlags_PtMask: StateFlags = 0x0007000000000000;
pub const StateFlags_PointSizeShift: StateFlags = 52;
pub const StateFlags_PointSizeMask: StateFlags = 0x00f0000000000000;

/// Enable MSAA rasterization.
pub const StateFlags_Msaa: StateFlags = 0x0100000000000000;

/// Enable line AA rasterization.
pub const StateFlags_Lineaa: StateFlags = 0x0200000000000000;

/// Enable conservative rasterization.
pub const StateFlags_ConservativeRaster: StateFlags = 0x0400000000000000;

/// No state.
pub const StateFlags_None: StateFlags = 0x0000000000000000;

/// Front counter-clockwise (default is clockwise).
pub const StateFlags_FrontCcw: StateFlags = 0x0000008000000000;

/// Enable blend independent.
pub const StateFlags_BlendIndependent: StateFlags = 0x0000000400000000;

/// Enable alpha to coverage.
pub const StateFlags_BlendAlphaToCoverage: StateFlags = 0x0000000800000000;

/// Default state is write to RGB, alpha, and depth with depth test less enabled, with clockwise
/// culling and MSAA (when writing into MSAA frame buffer, otherwise this flag is ignored).
pub const StateFlags_Default: StateFlags = 0x010000500000001f;
pub const StateFlags_Mask: StateFlags = 0xffffffffffffffff;
pub const StateFlags_ReservedShift: StateFlags = 61;
pub const StateFlags_ReservedMask: StateFlags = 0xe000000000000000;

pub const StencilFlags = u32;
pub const StencilFlags_FuncRefShift: StencilFlags = 0;
pub const StencilFlags_FuncRefMask: StencilFlags = 0x000000ff;
pub const StencilFlags_FuncRmaskShift: StencilFlags = 8;
pub const StencilFlags_FuncRmaskMask: StencilFlags = 0x0000ff00;
pub const StencilFlags_None: StencilFlags = 0x00000000;
pub const StencilFlags_Mask: StencilFlags = 0xffffffff;
pub const StencilFlags_Default: StencilFlags = 0x00000000;

/// Enable stencil test, less.
pub const StencilFlags_TestLess: StencilFlags = 0x00010000;

/// Enable stencil test, less or equal.
pub const StencilFlags_TestLequal: StencilFlags = 0x00020000;

/// Enable stencil test, equal.
pub const StencilFlags_TestEqual: StencilFlags = 0x00030000;

/// Enable stencil test, greater or equal.
pub const StencilFlags_TestGequal: StencilFlags = 0x00040000;

/// Enable stencil test, greater.
pub const StencilFlags_TestGreater: StencilFlags = 0x00050000;

/// Enable stencil test, not equal.
pub const StencilFlags_TestNotequal: StencilFlags = 0x00060000;

/// Enable stencil test, never.
pub const StencilFlags_TestNever: StencilFlags = 0x00070000;

/// Enable stencil test, always.
pub const StencilFlags_TestAlways: StencilFlags = 0x00080000;
pub const StencilFlags_TestShift: StencilFlags = 16;
pub const StencilFlags_TestMask: StencilFlags = 0x000f0000;

/// Zero.
pub const StencilFlags_OpFailSZero: StencilFlags = 0x00000000;

/// Keep.
pub const StencilFlags_OpFailSKeep: StencilFlags = 0x00100000;

/// Replace.
pub const StencilFlags_OpFailSReplace: StencilFlags = 0x00200000;

/// Increment and wrap.
pub const StencilFlags_OpFailSIncr: StencilFlags = 0x00300000;

/// Increment and clamp.
pub const StencilFlags_OpFailSIncrsat: StencilFlags = 0x00400000;

/// Decrement and wrap.
pub const StencilFlags_OpFailSDecr: StencilFlags = 0x00500000;

/// Decrement and clamp.
pub const StencilFlags_OpFailSDecrsat: StencilFlags = 0x00600000;

/// Invert.
pub const StencilFlags_OpFailSInvert: StencilFlags = 0x00700000;
pub const StencilFlags_OpFailSShift: StencilFlags = 20;
pub const StencilFlags_OpFailSMask: StencilFlags = 0x00f00000;

/// Zero.
pub const StencilFlags_OpFailZZero: StencilFlags = 0x00000000;

/// Keep.
pub const StencilFlags_OpFailZKeep: StencilFlags = 0x01000000;

/// Replace.
pub const StencilFlags_OpFailZReplace: StencilFlags = 0x02000000;

/// Increment and wrap.
pub const StencilFlags_OpFailZIncr: StencilFlags = 0x03000000;

/// Increment and clamp.
pub const StencilFlags_OpFailZIncrsat: StencilFlags = 0x04000000;

/// Decrement and wrap.
pub const StencilFlags_OpFailZDecr: StencilFlags = 0x05000000;

/// Decrement and clamp.
pub const StencilFlags_OpFailZDecrsat: StencilFlags = 0x06000000;

/// Invert.
pub const StencilFlags_OpFailZInvert: StencilFlags = 0x07000000;
pub const StencilFlags_OpFailZShift: StencilFlags = 24;
pub const StencilFlags_OpFailZMask: StencilFlags = 0x0f000000;

/// Zero.
pub const StencilFlags_OpPassZZero: StencilFlags = 0x00000000;

/// Keep.
pub const StencilFlags_OpPassZKeep: StencilFlags = 0x10000000;

/// Replace.
pub const StencilFlags_OpPassZReplace: StencilFlags = 0x20000000;

/// Increment and wrap.
pub const StencilFlags_OpPassZIncr: StencilFlags = 0x30000000;

/// Increment and clamp.
pub const StencilFlags_OpPassZIncrsat: StencilFlags = 0x40000000;

/// Decrement and wrap.
pub const StencilFlags_OpPassZDecr: StencilFlags = 0x50000000;

/// Decrement and clamp.
pub const StencilFlags_OpPassZDecrsat: StencilFlags = 0x60000000;

/// Invert.
pub const StencilFlags_OpPassZInvert: StencilFlags = 0x70000000;
pub const StencilFlags_OpPassZShift: StencilFlags = 28;
pub const StencilFlags_OpPassZMask: StencilFlags = 0xf0000000;

pub const ClearFlags = u16;
/// No clear flags.
pub const ClearFlags_None: ClearFlags = 0x0000;

/// Clear color.
pub const ClearFlags_Color: ClearFlags = 0x0001;

/// Clear depth.
pub const ClearFlags_Depth: ClearFlags = 0x0002;

/// Clear stencil.
pub const ClearFlags_Stencil: ClearFlags = 0x0004;

/// Discard frame buffer attachment 0.
pub const ClearFlags_DiscardColor0: ClearFlags = 0x0008;

/// Discard frame buffer attachment 1.
pub const ClearFlags_DiscardColor1: ClearFlags = 0x0010;

/// Discard frame buffer attachment 2.
pub const ClearFlags_DiscardColor2: ClearFlags = 0x0020;

/// Discard frame buffer attachment 3.
pub const ClearFlags_DiscardColor3: ClearFlags = 0x0040;

/// Discard frame buffer attachment 4.
pub const ClearFlags_DiscardColor4: ClearFlags = 0x0080;

/// Discard frame buffer attachment 5.
pub const ClearFlags_DiscardColor5: ClearFlags = 0x0100;

/// Discard frame buffer attachment 6.
pub const ClearFlags_DiscardColor6: ClearFlags = 0x0200;

/// Discard frame buffer attachment 7.
pub const ClearFlags_DiscardColor7: ClearFlags = 0x0400;

/// Discard frame buffer depth attachment.
pub const ClearFlags_DiscardDepth: ClearFlags = 0x0800;

/// Discard frame buffer stencil attachment.
pub const ClearFlags_DiscardStencil: ClearFlags = 0x1000;
pub const ClearFlags_DiscardColorMask: ClearFlags = 0x07f8;
pub const ClearFlags_DiscardMask: ClearFlags = 0x1ff8;

pub const DiscardFlags = u32;
/// Preserve everything.
pub const DiscardFlags_None: DiscardFlags = 0x00000000;

/// Discard texture sampler and buffer bindings.
pub const DiscardFlags_Bindings: DiscardFlags = 0x00000001;

/// Discard index buffer.
pub const DiscardFlags_IndexBuffer: DiscardFlags = 0x00000002;

/// Discard instance data.
pub const DiscardFlags_InstanceData: DiscardFlags = 0x00000004;

/// Discard state and uniform bindings.
pub const DiscardFlags_State: DiscardFlags = 0x00000008;

/// Discard transform.
pub const DiscardFlags_Transform: DiscardFlags = 0x00000010;

/// Discard vertex streams.
pub const DiscardFlags_VertexStreams: DiscardFlags = 0x00000020;

/// Discard all states.
pub const DiscardFlags_All: DiscardFlags = 0x000000ff;

pub const DebugFlags = u32;
/// No debug.
pub const DebugFlags_None: DebugFlags = 0x00000000;

/// Enable wireframe for all primitives.
pub const DebugFlags_Wireframe: DebugFlags = 0x00000001;

/// Enable infinitely fast hardware test. No draw calls will be submitted to driver.
/// It's useful when profiling to quickly assess bottleneck between CPU and
pub const DebugFlags_Ifh: DebugFlags = 0x00000002;

/// Enable statistics display.
pub const DebugFlags_Stats: DebugFlags = 0x00000004;

/// Enable debug text display.
pub const DebugFlags_Text: DebugFlags = 0x00000008;

/// Enable profiler. This causes per-view statistics to be collected, available through `bgfx::Stats::ViewStats`. This is unrelated to the profiler functions in `bgfx::CallbackI`.
pub const DebugFlags_Profiler: DebugFlags = 0x00000010;

pub const BufferFlags = u16;
/// 1 8-bit value
pub const BufferFlags_ComputeFormat8x1: BufferFlags = 0x0001;

/// 2 8-bit values
pub const BufferFlags_ComputeFormat8x2: BufferFlags = 0x0002;

/// 4 8-bit values
pub const BufferFlags_ComputeFormat8x4: BufferFlags = 0x0003;

/// 1 16-bit value
pub const BufferFlags_ComputeFormat16x1: BufferFlags = 0x0004;

/// 2 16-bit values
pub const BufferFlags_ComputeFormat16x2: BufferFlags = 0x0005;

/// 4 16-bit values
pub const BufferFlags_ComputeFormat16x4: BufferFlags = 0x0006;

/// 1 32-bit value
pub const BufferFlags_ComputeFormat32x1: BufferFlags = 0x0007;

/// 2 32-bit values
pub const BufferFlags_ComputeFormat32x2: BufferFlags = 0x0008;

/// 4 32-bit values
pub const BufferFlags_ComputeFormat32x4: BufferFlags = 0x0009;
pub const BufferFlags_ComputeFormatShift: BufferFlags = 0;
pub const BufferFlags_ComputeFormatMask: BufferFlags = 0x000f;

/// Type `int`.
pub const BufferFlags_ComputeTypeInt: BufferFlags = 0x0010;

/// Type `uint`.
pub const BufferFlags_ComputeTypeUint: BufferFlags = 0x0020;

/// Type `float`.
pub const BufferFlags_ComputeTypeFloat: BufferFlags = 0x0030;
pub const BufferFlags_ComputeTypeShift: BufferFlags = 4;
pub const BufferFlags_ComputeTypeMask: BufferFlags = 0x0030;
pub const BufferFlags_None: BufferFlags = 0x0000;

/// Buffer will be read by shader.
pub const BufferFlags_ComputeRead: BufferFlags = 0x0100;

/// Buffer will be used for writing.
pub const BufferFlags_ComputeWrite: BufferFlags = 0x0200;

/// Buffer will be used for storing draw indirect commands.
pub const BufferFlags_DrawIndirect: BufferFlags = 0x0400;

/// Allow dynamic index/vertex buffer resize during update.
pub const BufferFlags_AllowResize: BufferFlags = 0x0800;

/// Index buffer contains 32-bit indices.
pub const BufferFlags_Index32: BufferFlags = 0x1000;
pub const BufferFlags_ComputeReadWrite: BufferFlags = 0x0300;

pub const TextureFlags = u64;
pub const TextureFlags_None: TextureFlags = 0x0000000000000000;

/// Texture will be used for MSAA sampling.
pub const TextureFlags_MsaaSample: TextureFlags = 0x0000000800000000;

/// Render target no MSAA.
pub const TextureFlags_Rt: TextureFlags = 0x0000001000000000;

/// Texture will be used for compute write.
pub const TextureFlags_ComputeWrite: TextureFlags = 0x0000100000000000;

/// Sample texture as sRGB.
pub const TextureFlags_Srgb: TextureFlags = 0x0000200000000000;

/// Texture will be used as blit destination.
pub const TextureFlags_BlitDst: TextureFlags = 0x0000400000000000;

/// Texture will be used for read back from
pub const TextureFlags_ReadBack: TextureFlags = 0x0000800000000000;

/// Render target MSAAx2 mode.
pub const TextureFlags_RtMsaaX2: TextureFlags = 0x0000002000000000;

/// Render target MSAAx4 mode.
pub const TextureFlags_RtMsaaX4: TextureFlags = 0x0000003000000000;

/// Render target MSAAx8 mode.
pub const TextureFlags_RtMsaaX8: TextureFlags = 0x0000004000000000;

/// Render target MSAAx16 mode.
pub const TextureFlags_RtMsaaX16: TextureFlags = 0x0000005000000000;
pub const TextureFlags_RtMsaaShift: TextureFlags = 36;
pub const TextureFlags_RtMsaaMask: TextureFlags = 0x0000007000000000;

/// Render target will be used for writing
pub const TextureFlags_RtWriteOnly: TextureFlags = 0x0000008000000000;
pub const TextureFlags_RtShift: TextureFlags = 36;
pub const TextureFlags_RtMask: TextureFlags = 0x000000f000000000;

pub const SamplerFlags = u32;
/// Wrap U mode: Mirror
pub const SamplerFlags_UMirror: SamplerFlags = 0x00000001;

/// Wrap U mode: Clamp
pub const SamplerFlags_UClamp: SamplerFlags = 0x00000002;

/// Wrap U mode: Border
pub const SamplerFlags_UBorder: SamplerFlags = 0x00000003;
pub const SamplerFlags_UShift: SamplerFlags = 0;
pub const SamplerFlags_UMask: SamplerFlags = 0x00000003;

/// Wrap V mode: Mirror
pub const SamplerFlags_VMirror: SamplerFlags = 0x00000004;

/// Wrap V mode: Clamp
pub const SamplerFlags_VClamp: SamplerFlags = 0x00000008;

/// Wrap V mode: Border
pub const SamplerFlags_VBorder: SamplerFlags = 0x0000000c;
pub const SamplerFlags_VShift: SamplerFlags = 2;
pub const SamplerFlags_VMask: SamplerFlags = 0x0000000c;

/// Wrap W mode: Mirror
pub const SamplerFlags_WMirror: SamplerFlags = 0x00000010;

/// Wrap W mode: Clamp
pub const SamplerFlags_WClamp: SamplerFlags = 0x00000020;

/// Wrap W mode: Border
pub const SamplerFlags_WBorder: SamplerFlags = 0x00000030;
pub const SamplerFlags_WShift: SamplerFlags = 4;
pub const SamplerFlags_WMask: SamplerFlags = 0x00000030;

/// Min sampling mode: Point
pub const SamplerFlags_MinPoint: SamplerFlags = 0x00000040;

/// Min sampling mode: Anisotropic
pub const SamplerFlags_MinAnisotropic: SamplerFlags = 0x00000080;
pub const SamplerFlags_MinShift: SamplerFlags = 6;
pub const SamplerFlags_MinMask: SamplerFlags = 0x000000c0;

/// Mag sampling mode: Point
pub const SamplerFlags_MagPoint: SamplerFlags = 0x00000100;

/// Mag sampling mode: Anisotropic
pub const SamplerFlags_MagAnisotropic: SamplerFlags = 0x00000200;
pub const SamplerFlags_MagShift: SamplerFlags = 8;
pub const SamplerFlags_MagMask: SamplerFlags = 0x00000300;

/// Mip sampling mode: Point
pub const SamplerFlags_MipPoint: SamplerFlags = 0x00000400;
pub const SamplerFlags_MipShift: SamplerFlags = 10;
pub const SamplerFlags_MipMask: SamplerFlags = 0x00000400;

/// Compare when sampling depth texture: less.
pub const SamplerFlags_CompareLess: SamplerFlags = 0x00010000;

/// Compare when sampling depth texture: less or equal.
pub const SamplerFlags_CompareLequal: SamplerFlags = 0x00020000;

/// Compare when sampling depth texture: equal.
pub const SamplerFlags_CompareEqual: SamplerFlags = 0x00030000;

/// Compare when sampling depth texture: greater or equal.
pub const SamplerFlags_CompareGequal: SamplerFlags = 0x00040000;

/// Compare when sampling depth texture: greater.
pub const SamplerFlags_CompareGreater: SamplerFlags = 0x00050000;

/// Compare when sampling depth texture: not equal.
pub const SamplerFlags_CompareNotequal: SamplerFlags = 0x00060000;

/// Compare when sampling depth texture: never.
pub const SamplerFlags_CompareNever: SamplerFlags = 0x00070000;

/// Compare when sampling depth texture: always.
pub const SamplerFlags_CompareAlways: SamplerFlags = 0x00080000;
pub const SamplerFlags_CompareShift: SamplerFlags = 16;
pub const SamplerFlags_CompareMask: SamplerFlags = 0x000f0000;
pub const SamplerFlags_BorderColorShift: SamplerFlags = 24;
pub const SamplerFlags_BorderColorMask: SamplerFlags = 0x0f000000;
pub const SamplerFlags_ReservedShift: SamplerFlags = 28;
pub const SamplerFlags_ReservedMask: SamplerFlags = 0xf0000000;
pub const SamplerFlags_None: SamplerFlags = 0x00000000;

/// Sample stencil instead of depth.
pub const SamplerFlags_SampleStencil: SamplerFlags = 0x00100000;
pub const SamplerFlags_Point: SamplerFlags = 0x00000540;
pub const SamplerFlags_UvwMirror: SamplerFlags = 0x00000015;
pub const SamplerFlags_UvwClamp: SamplerFlags = 0x0000002a;
pub const SamplerFlags_UvwBorder: SamplerFlags = 0x0000003f;
pub const SamplerFlags_BitsMask: SamplerFlags = 0x000f07ff;

pub const ResetFlags = u32;
/// Enable 2x MSAA.
pub const ResetFlags_MsaaX2: ResetFlags = 0x00000010;

/// Enable 4x MSAA.
pub const ResetFlags_MsaaX4: ResetFlags = 0x00000020;

/// Enable 8x MSAA.
pub const ResetFlags_MsaaX8: ResetFlags = 0x00000030;

/// Enable 16x MSAA.
pub const ResetFlags_MsaaX16: ResetFlags = 0x00000040;
pub const ResetFlags_MsaaShift: ResetFlags = 4;
pub const ResetFlags_MsaaMask: ResetFlags = 0x00000070;

/// No reset flags.
pub const ResetFlags_None: ResetFlags = 0x00000000;

/// Not supported yet.
pub const ResetFlags_Fullscreen: ResetFlags = 0x00000001;

/// Enable V-Sync.
pub const ResetFlags_Vsync: ResetFlags = 0x00000080;

/// Turn on/off max anisotropy.
pub const ResetFlags_Maxanisotropy: ResetFlags = 0x00000100;

/// Begin screen capture.
pub const ResetFlags_Capture: ResetFlags = 0x00000200;

/// Flush rendering after submitting to
pub const ResetFlags_FlushAfterRender: ResetFlags = 0x00002000;

/// This flag specifies where flip occurs. Default behaviour is that flip occurs
/// before rendering new frame. This flag only has effect when `BGFX_CONFIG_MULTITHREADED=0`.
pub const ResetFlags_FlipAfterRender: ResetFlags = 0x00004000;

/// Enable sRGB backbuffer.
pub const ResetFlags_SrgbBackbuffer: ResetFlags = 0x00008000;

/// Enable HDR10 rendering.
pub const ResetFlags_Hdr10: ResetFlags = 0x00010000;

/// Enable HiDPI rendering.
pub const ResetFlags_Hidpi: ResetFlags = 0x00020000;

/// Enable depth clamp.
pub const ResetFlags_DepthClamp: ResetFlags = 0x00040000;

/// Suspend rendering.
pub const ResetFlags_Suspend: ResetFlags = 0x00080000;

/// Transparent backbuffer. Availability depends on: `BGFX_CAPS_TRANSPARENT_BACKBUFFER`.
pub const ResetFlags_TransparentBackbuffer: ResetFlags = 0x00100000;
pub const ResetFlags_FullscreenShift: ResetFlags = 0;
pub const ResetFlags_FullscreenMask: ResetFlags = 0x00000001;
pub const ResetFlags_ReservedShift: ResetFlags = 31;
pub const ResetFlags_ReservedMask: ResetFlags = 0x80000000;

pub const CapsFlags = u64;
/// Alpha to coverage is supported.
pub const CapsFlags_AlphaToCoverage: CapsFlags = 0x0000000000000001;

/// Blend independent is supported.
pub const CapsFlags_BlendIndependent: CapsFlags = 0x0000000000000002;

/// Compute shaders are supported.
pub const CapsFlags_Compute: CapsFlags = 0x0000000000000004;

/// Conservative rasterization is supported.
pub const CapsFlags_ConservativeRaster: CapsFlags = 0x0000000000000008;

/// Draw indirect is supported.
pub const CapsFlags_DrawIndirect: CapsFlags = 0x0000000000000010;

/// Fragment depth is available in fragment shader.
pub const CapsFlags_FragmentDepth: CapsFlags = 0x0000000000000020;

/// Fragment ordering is available in fragment shader.
pub const CapsFlags_FragmentOrdering: CapsFlags = 0x0000000000000040;

/// Graphics debugger is present.
pub const CapsFlags_GraphicsDebugger: CapsFlags = 0x0000000000000080;

/// HDR10 rendering is supported.
pub const CapsFlags_Hdr10: CapsFlags = 0x0000000000000100;

/// HiDPI rendering is supported.
pub const CapsFlags_Hidpi: CapsFlags = 0x0000000000000200;

/// Image Read/Write is supported.
pub const CapsFlags_ImageRw: CapsFlags = 0x0000000000000400;

/// 32-bit indices are supported.
pub const CapsFlags_Index32: CapsFlags = 0x0000000000000800;

/// Instancing is supported.
pub const CapsFlags_Instancing: CapsFlags = 0x0000000000001000;

/// Occlusion query is supported.
pub const CapsFlags_OcclusionQuery: CapsFlags = 0x0000000000002000;

/// Renderer is on separate thread.
pub const CapsFlags_RendererMultithreaded: CapsFlags = 0x0000000000004000;

/// Multiple windows are supported.
pub const CapsFlags_SwapChain: CapsFlags = 0x0000000000008000;

/// 2D texture array is supported.
pub const CapsFlags_Texture2DArray: CapsFlags = 0x0000000000010000;

/// 3D textures are supported.
pub const CapsFlags_Texture3D: CapsFlags = 0x0000000000020000;

/// Texture blit is supported.
pub const CapsFlags_TextureBlit: CapsFlags = 0x0000000000040000;

/// Transparent back buffer supported.
pub const CapsFlags_TransparentBackbuffer: CapsFlags = 0x0000000000080000;
pub const CapsFlags_TextureCompareReserved: CapsFlags = 0x0000000000100000;

/// Texture compare less equal mode is supported.
pub const CapsFlags_TextureCompareLequal: CapsFlags = 0x0000000000200000;

/// Cubemap texture array is supported.
pub const CapsFlags_TextureCubeArray: CapsFlags = 0x0000000000400000;

/// CPU direct access to GPU texture memory.
pub const CapsFlags_TextureDirectAccess: CapsFlags = 0x0000000000800000;

/// Read-back texture is supported.
pub const CapsFlags_TextureReadBack: CapsFlags = 0x0000000001000000;

/// Vertex attribute half-float is supported.
pub const CapsFlags_VertexAttribHalf: CapsFlags = 0x0000000002000000;

/// Vertex attribute 10_10_10_2 is supported.
pub const CapsFlags_VertexAttribUint10: CapsFlags = 0x0000000004000000;

/// Rendering with VertexID only is supported.
pub const CapsFlags_VertexId: CapsFlags = 0x0000000008000000;

/// PrimitiveID is available in fragment shader.
pub const CapsFlags_PrimitiveId: CapsFlags = 0x0000000010000000;

/// Viewport layer is available in vertex shader.
pub const CapsFlags_ViewportLayerArray: CapsFlags = 0x0000000020000000;

/// Draw indirect with indirect count is supported.
pub const CapsFlags_DrawIndirectCount: CapsFlags = 0x0000000040000000;

/// All texture compare modes are supported.
pub const CapsFlags_TextureCompareAll: CapsFlags = 0x0000000000300000;

pub const CapsFormatFlags = u32;
/// Texture format is not supported.
pub const CapsFormatFlags_TextureNone: CapsFormatFlags = 0x00000000;

/// Texture format is supported.
pub const CapsFormatFlags_Texture2D: CapsFormatFlags = 0x00000001;

/// Texture as sRGB format is supported.
pub const CapsFormatFlags_Texture2DSrgb: CapsFormatFlags = 0x00000002;

/// Texture format is emulated.
pub const CapsFormatFlags_Texture2DEmulated: CapsFormatFlags = 0x00000004;

/// Texture format is supported.
pub const CapsFormatFlags_Texture3D: CapsFormatFlags = 0x00000008;

/// Texture as sRGB format is supported.
pub const CapsFormatFlags_Texture3DSrgb: CapsFormatFlags = 0x00000010;

/// Texture format is emulated.
pub const CapsFormatFlags_Texture3DEmulated: CapsFormatFlags = 0x00000020;

/// Texture format is supported.
pub const CapsFormatFlags_TextureCube: CapsFormatFlags = 0x00000040;

/// Texture as sRGB format is supported.
pub const CapsFormatFlags_TextureCubeSrgb: CapsFormatFlags = 0x00000080;

/// Texture format is emulated.
pub const CapsFormatFlags_TextureCubeEmulated: CapsFormatFlags = 0x00000100;

/// Texture format can be used from vertex shader.
pub const CapsFormatFlags_TextureVertex: CapsFormatFlags = 0x00000200;

/// Texture format can be used as image and read from.
pub const CapsFormatFlags_TextureImageRead: CapsFormatFlags = 0x00000400;

/// Texture format can be used as image and written to.
pub const CapsFormatFlags_TextureImageWrite: CapsFormatFlags = 0x00000800;

/// Texture format can be used as frame buffer.
pub const CapsFormatFlags_TextureFramebuffer: CapsFormatFlags = 0x00001000;

/// Texture format can be used as MSAA frame buffer.
pub const CapsFormatFlags_TextureFramebufferMsaa: CapsFormatFlags = 0x00002000;

/// Texture can be sampled as MSAA.
pub const CapsFormatFlags_TextureMsaa: CapsFormatFlags = 0x00004000;

/// Texture format supports auto-generated mips.
pub const CapsFormatFlags_TextureMipAutogen: CapsFormatFlags = 0x00008000;

pub const ResolveFlags = u32;
/// No resolve flags.
pub const ResolveFlags_None: ResolveFlags = 0x00000000;

/// Auto-generate mip maps on resolve.
pub const ResolveFlags_AutoGenMips: ResolveFlags = 0x00000001;

pub const PciIdFlags = u16;
/// Autoselect adapter.
pub const PciIdFlags_None: PciIdFlags = 0x0000;

/// Software rasterizer.
pub const PciIdFlags_SoftwareRasterizer: PciIdFlags = 0x0001;

/// AMD adapter.
pub const PciIdFlags_Amd: PciIdFlags = 0x1002;

/// Apple adapter.
pub const PciIdFlags_Apple: PciIdFlags = 0x106b;

/// Intel adapter.
pub const PciIdFlags_Intel: PciIdFlags = 0x8086;

/// nVidia adapter.
pub const PciIdFlags_Nvidia: PciIdFlags = 0x10de;

/// Microsoft adapter.
pub const PciIdFlags_Microsoft: PciIdFlags = 0x1414;

/// ARM adapter.
pub const PciIdFlags_Arm: PciIdFlags = 0x13b5;

pub const CubeMapFlags = u32;
/// Cubemap +x.
pub const CubeMapFlags_PositiveX: CubeMapFlags = 0x00000000;

/// Cubemap -x.
pub const CubeMapFlags_NegativeX: CubeMapFlags = 0x00000001;

/// Cubemap +y.
pub const CubeMapFlags_PositiveY: CubeMapFlags = 0x00000002;

/// Cubemap -y.
pub const CubeMapFlags_NegativeY: CubeMapFlags = 0x00000003;

/// Cubemap +z.
pub const CubeMapFlags_PositiveZ: CubeMapFlags = 0x00000004;

/// Cubemap -z.
pub const CubeMapFlags_NegativeZ: CubeMapFlags = 0x00000005;

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

pub const InstanceDataBuffer = extern struct {
    data: [*c]u8,
    size: u32,
    offset: u32,
    num: u32,
    stride: u16,
    handle: VertexBufferHandle,
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
    format: TextureFormat,
    width: u32,
    height: u32,
    reset: u32,
    numBackBuffers: u8,
    maxFrameLatency: u8,
    debugTextScale: u8,
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
    /// Uint8
    Uint8,

    /// Uint10, availability depends on: `BGFX_CAPS_VERTEX_ATTRIB_UINT10`.
    Uint10,

    /// Int16
    Int16,

    /// Half, availability depends on: `BGFX_CAPS_VERTEX_ATTRIB_HALF`.
    Half,

    /// Float
    Float,

    Count,
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

pub const ShaderType = enum {
    vertex,
    fragment,
    compute,
};

pub const Optimize = enum(u32) {
    o1 = 1,
    o2 = 2,
    o3 = 3,
};

pub const Platform = enum {
    android,
    asm_js,
    ios,
    linux,
    orbis,
    osx,
    windows,
};

pub const Profile = enum {
    es_100,
    es_300,
    es_310,
    es_320,

    s_4_0,
    s_5_0,

    metal,
    metal10_10,
    metal11_10,
    metal12_10,
    metal20_11,
    metal21_11,
    metal22_11,
    metal23_14,
    metal24_14,
    metal30_14,
    metal31_14,

    pssl,

    spirv,
    spirv10_10,
    spirv13_11,
    spirv14_11,
    spirv15_12,
    spirv16_13,

    glsl_120,
    glsl_130,
    glsl_140,
    glsl_150,
    glsl_330,
    glsl_400,
    glsl_410,
    glsl_420,
    glsl_430,
    glsl_440,
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

    optimizationLevel: Optimize = .o3,
};

// TODO: to original
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
