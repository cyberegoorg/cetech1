const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const zm = cetech1.math;
const strid = cetech1.strid;
const ecs = cetech1.ecs;

const transform = @import("transform");
const camera = @import("camera");
const shader_system = @import("shader_system");

pub const RENDERER_KERNEL_TASK = strid.strId64("Renderer");
pub const CULLING_VOLUME_NODE_TYPE_STR = "culling_volume";
pub const CULLING_VOLUME_NODE_TYPE = strid.strId32(CULLING_VOLUME_NODE_TYPE_STR);

pub const DRAW_CALL_NODE_TYPE_STR = "draw_call";
pub const DRAW_CALL_NODE_TYPE = strid.strId32(DRAW_CALL_NODE_TYPE_STR);

pub const LSD_CUBE_NODE_TYPE_STR = "lsd_cube";
pub const LSD_CUBE_NODE_TYPE = strid.strId32(LSD_CUBE_NODE_TYPE_STR);

pub const PinTypes = struct {
    pub const GPU_GEOMETRY = strid.strId32("gpu_geometry");
    pub const GPU_INDEX_BUFFER = strid.strId32("gpu_index_buffer");
};

pub const GPUGeometryCdb = cdb.CdbTypeDecl(
    "ct_gpu_geometry",
    enum(u32) {
        handle0 = 0,
        handle1,
        handle2,
        handle3,
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

pub const GPUGeometry = struct {
    vb: [4]gpu.VertexBufferHandle = @splat(.{}),
};

pub const CullingVolume = struct {
    min: [3]f32 = .{ 0, 0, 0 },
    max: [3]f32 = .{ 0, 0, 0 },
    radius: f32 = 0,

    pub fn hasBox(self: CullingVolume) bool {
        return !std.mem.eql(f32, &self.min, &self.max);
    }

    pub fn hasSphere(self: CullingVolume) bool {
        return self.radius != 0;
    }

    pub fn hasAny(self: CullingVolume) bool {
        return self.hasBox() or self.hasSphere();
    }
};

const MatList = std.ArrayListUnmanaged(transform.WorldTransform);
const RenderableBufferList = std.ArrayListUnmanaged(u8);
const CullingVolumeList = std.ArrayListUnmanaged(CullingVolume);

pub const CullingRequest = struct {
    allocator: std.mem.Allocator,

    mtx: MatList = .{},
    renderables: RenderableBufferList = .{},
    volumes: CullingVolumeList = .{},

    no_culling_mtx: MatList = .{},
    no_culling_renderables: RenderableBufferList = .{},

    lck: std.Thread.Mutex,

    renderable_size: usize,

    pub fn init(allocator: std.mem.Allocator, renderable_size: usize) CullingRequest {
        return CullingRequest{
            .allocator = allocator,
            .lck = .{},
            .renderable_size = renderable_size,
        };
    }

    pub fn clean(self: *CullingRequest) void {
        self.mtx.clearRetainingCapacity();
        self.volumes.clearRetainingCapacity();
        self.renderables.clearRetainingCapacity();
        self.no_culling_mtx.clearRetainingCapacity();
        self.no_culling_renderables.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingRequest) void {
        self.mtx.deinit(self.allocator);
        self.volumes.deinit(self.allocator);
        self.renderables.deinit(self.allocator);
        self.no_culling_mtx.deinit(self.allocator);
        self.no_culling_renderables.deinit(self.allocator);
    }

    pub fn append(self: *CullingRequest, mtxs: []const transform.WorldTransform, volumes: []const CullingVolume, renderables_data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.appendSlice(self.allocator, mtxs);
        try self.volumes.appendSlice(self.allocator, volumes);
        try self.renderables.appendSlice(self.allocator, renderables_data);
    }

    pub fn appendNoCulling(self: *CullingRequest, mtxs: []const transform.WorldTransform, renderables_data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.no_culling_mtx.appendSlice(self.allocator, mtxs);
        try self.no_culling_renderables.appendSlice(self.allocator, renderables_data);
    }
};

pub const CullingResult = struct {
    allocator: std.mem.Allocator,

    mtx: MatList = .{},
    renderables: RenderableBufferList = .{},
    lck: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) CullingResult {
        return CullingResult{
            .allocator = allocator,
            .lck = .{},
        };
    }

    pub fn clean(self: *CullingResult) void {
        self.mtx.clearRetainingCapacity();
        self.renderables.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingResult) void {
        self.mtx.deinit(self.allocator);
        self.renderables.deinit(self.allocator);
    }

    pub fn append(self: *CullingResult, mtx: transform.WorldTransform, data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.append(self.allocator, mtx);
        try self.renderables.appendSlice(self.allocator, data);
    }

    pub fn appendMany(self: *CullingResult, mtx: []const transform.WorldTransform, data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.appendSlice(self.allocator, mtx);
        try self.renderables.appendSlice(self.allocator, data);
    }
};

pub const RendereableI = struct {
    pub const c_name = "ct_rg_component_renderer_i";
    pub const name_hash = strid.strId64(@This().c_name);

    culling: ?*const fn (allocator: std.mem.Allocator, builder: GraphBuilder, world: ecs.World, viewers: []const Viewer, rq: *CullingRequest) anyerror!void = undefined,
    render: *const fn (
        allocator: std.mem.Allocator,
        builder: GraphBuilder,
        world: ecs.World,
        viewport: Viewport,
        viewers: []const Viewer,
        systems: shader_system.SystemSet,
        mtx: []const transform.WorldTransform,
        renderables: []const u8,
    ) anyerror!void = undefined,

    size: usize,

    pub fn implement(comptime CompType: type, comptime T: type) RendereableI {
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        return RendereableI{
            .size = @sizeOf(CompType),
            .render = T.render,
            .culling = if (std.meta.hasFn(T, "culling")) T.culling else null,
        };
    }
};

pub const DefaultRenderGraphI = struct {
    pub const c_name = "ct_rg_default_i";
    pub const name_hash = strid.strId64(@This().c_name);

    create: *const fn (
        allocator: std.mem.Allocator,
        rg_api: *const RenderGraphApi,
        graph: Graph,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) DefaultRenderGraphI {
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");

        return DefaultRenderGraphI{
            .create = T.create,
        };
    }
};

// TODO: move
pub const DrawCall = struct {
    gpu_shader: ?shader_system.ShaderInstance = null,
    gpu_geometry: ?GPUGeometry = null,
    gpu_index_buffer: ?gpu.IndexBufferHandle = null,
    vertex_count: u32 = 0,
    index_count: u32 = 0,
};

pub const Viewport = struct {
    pub inline fn setSize(self: Viewport, size: [2]f32) void {
        self.vtable.setSize(self.ptr, size);
    }
    pub inline fn getTexture(self: Viewport) ?gpu.TextureHandle {
        return self.vtable.getTexture(self.ptr);
    }
    pub inline fn getFb(self: Viewport) ?gpu.FrameBufferHandle {
        return self.vtable.getFb(self.ptr);
    }
    pub inline fn getSize(self: Viewport) [2]f32 {
        return self.vtable.getSize(self.ptr);
    }

    pub inline fn setMainCamera(self: Viewport, camera_ent: ecs.EntityId) void {
        return self.vtable.setMainCamera(self.ptr, camera_ent);
    }

    pub inline fn getMainCamera(self: Viewport) ?ecs.EntityId {
        return self.vtable.getMainCamera(self.ptr);
    }

    pub inline fn renderMe(self: Viewport) void {
        return self.vtable.renderMe(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        setSize: *const fn (viewport: *anyopaque, size: [2]f32) void,
        getTexture: *const fn (viewport: *anyopaque) ?gpu.TextureHandle,
        getFb: *const fn (viewport: *anyopaque) ?gpu.FrameBufferHandle,
        getSize: *const fn (viewport: *anyopaque) [2]f32,
        getMainCamera: *const fn (viewport: *anyopaque) ?ecs.EntityId,
        setMainCamera: *const fn (viewport: *anyopaque, camera_ent: ?ecs.EntityId) void,
        renderMe: *const fn (viewport: *anyopaque) void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "setSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getTexture")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getFb")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "renderMe")) @compileError("implement me");

            return VTable{
                .setSize = &T.setSize,
                .getTexture = &T.getTexture,
                .getFb = &T.getFb,
                .getSize = &T.getSize,
                .renderMe = &T.renderMe,
                .setMainCamera = &T.setMainCamera,
                .getMainCamera = &T.getMainCamera,
            };
        }
    };
};

const GfxApi = gpu.GpuApi;

pub const Pass = struct {
    setup: *const fn (pass: *Pass, builder: GraphBuilder) anyerror!void,
    render: *const fn (builder: GraphBuilder, gfx_api: *const GfxApi, viewport: Viewport, viewid: gpu.ViewId, viewers: []const Viewer) anyerror!void,

    pub fn implement(comptime T: type) Pass {
        if (!std.meta.hasFn(T, "setup")) @compileError("implement me");
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        const p = Pass{
            .setup = &T.setup,
            .render = &T.render,
        };

        return p;
    }
};

pub const Module = struct {
    pub fn addPassToModule(self: Module, pass: Pass) !void {
        self.vtable.addPassToModule(self.ptr, pass);
    }
    pub fn addModuleToModule(self: Module, module: Module) !void {
        self.vtable.addModuleToModule(self.ptr, module);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPassToModule: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModuleToModule: *const fn (self: *anyopaque, module: Module) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPassToModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModuleToModule")) @compileError("implement me");

            return VTable{
                .addPassToModule = &T.addPassToModule,
                .addModuleToModule = &T.addModuleToModule,
            };
        }
    };
};

pub const Viewer = struct {
    mtx: [16]f32,
    proj: [16]f32,
    camera: camera.Camera,
    context: strid.StrId32,
};

pub const ResourceId = strid.StrId32;
pub const ViewportColorResource = "viewport_color";

pub const TextureInfo = struct {
    has_mip: bool = true,
    num_layers: u16 = 1,
    format: gpu.TextureFormat,
    flags: gpu.TextureFlags,
    ratio: gpu.BackbufferRatio = .Equal,
    clear_color: ?u32 = null,
    clear_depth: ?f32 = null,

    pub fn eql(self: TextureInfo, other: TextureInfo) bool {
        return self.has_mip == other.has_mip and
            self.num_layers == other.num_layers and
            self.format == other.format and
            self.flags == other.flags and
            self.ratio == other.ratio and
            self.clear_color == other.clear_color and
            self.clear_depth == other.clear_depth;
    }
};

pub const GraphBuilder = struct {
    pub inline fn addPass(builder: GraphBuilder, name: []const u8, pass: *Pass) !void {
        return builder.vtable.addPass(builder.ptr, name, pass);
    }
    pub inline fn importTexture(builder: GraphBuilder, texture_name: []const u8, texture: gpu.TextureHandle) !void {
        return builder.vtable.importTexture(builder.ptr, texture_name, texture);
    }

    pub inline fn clearStencil(builder: GraphBuilder, pass: *Pass, clear_value: u8) !void {
        return builder.vtable.clearStencil(builder.ptr, pass, clear_value);
    }

    pub inline fn createTexture2D(builder: GraphBuilder, pass: *Pass, texture: []const u8, info: TextureInfo) !void {
        return builder.vtable.createTexture2D(builder.ptr, pass, texture, info);
    }

    pub inline fn writeTexture(builder: GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return builder.vtable.writeTexture(builder.ptr, pass, texture);
    }

    pub inline fn readTexture(builder: GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return builder.vtable.readTexture(builder.ptr, pass, texture);
    }

    pub inline fn getTexture(builder: GraphBuilder, texture: []const u8) ?gpu.TextureHandle {
        return builder.vtable.getTexture(builder.ptr, texture);
    }

    pub inline fn exportLayer(builder: GraphBuilder, pass: *Pass, layer: []const u8) !void {
        return builder.vtable.exportLayer(builder.ptr, pass, layer);
    }

    pub inline fn getLayer(builder: GraphBuilder, layer: []const u8) gpu.ViewId {
        return builder.vtable.getLayer(builder.ptr, layer);
    }

    pub inline fn getLayerById(builder: GraphBuilder, layer: strid.StrId32) gpu.ViewId {
        return builder.vtable.getLayerById(builder.ptr, layer);
    }

    pub inline fn compile(builder: GraphBuilder) !void {
        return builder.vtable.compile(builder.ptr);
    }
    pub inline fn execute(builder: GraphBuilder, viewers: []const Viewer) !void {
        return builder.vtable.execute(builder.ptr, viewers);
    }

    pub inline fn getViewers(builder: GraphBuilder) []Viewer {
        return builder.vtable.getViewers(builder.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (builder: *anyopaque, name: []const u8, pass: *Pass) anyerror!void,
        importTexture: *const fn (builder: *anyopaque, texture_name: []const u8, texture: gpu.TextureHandle) anyerror!void,
        clearStencil: *const fn (builder: *anyopaque, pass: *Pass, clear_value: u8) anyerror!void,
        createTexture2D: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8, info: TextureInfo) anyerror!void,
        writeTexture: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8) anyerror!void,
        readTexture: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8) anyerror!void,
        exportLayer: *const fn (builder: *anyopaque, pass: *Pass, layer: []const u8) anyerror!void,
        getTexture: *const fn (builder: *anyopaque, texture: []const u8) ?gpu.TextureHandle,
        getLayer: *const fn (builder: *anyopaque, layer: []const u8) gpu.ViewId,
        getLayerById: *const fn (builder: *anyopaque, layer: strid.StrId32) gpu.ViewId,

        getViewers: *const fn (builder: *anyopaque) []Viewer,

        compile: *const fn (builder: *anyopaque) anyerror!void,
        execute: *const fn (builder: *anyopaque, viewers: []const Viewer) anyerror!void,
    };
};

pub const Graph = struct {
    pub inline fn addPass(self: Graph, pass: Pass) !void {
        return self.vtable.addPass(self.ptr, pass);
    }
    pub inline fn addModule(self: Graph, module: Module) !void {
        self.vtable.addModule(self.ptr, module);
    }
    pub inline fn createModule(self: Graph) !Module {
        return self.vtable.createModule(self.ptr);
    }
    pub inline fn createBuilder(self: Graph, allocator: std.mem.Allocator, viewport: Viewport) !GraphBuilder {
        return self.vtable.createBuilder(self.ptr, allocator, viewport);
    }
    pub inline fn destroyBuilder(self: Graph, builder: GraphBuilder) void {
        self.vtable.destroyBuilder(self.ptr, builder);
    }
    pub inline fn setupBuilder(self: Graph, builder: GraphBuilder) !void {
        return self.vtable.setupBuilder(self.ptr, builder);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModule: *const fn (self: *anyopaque, module: Module) anyerror!void,
        createModule: *const fn (self: *anyopaque) anyerror!Module,
        createBuilder: *const fn (self: *anyopaque, allocator: std.mem.Allocator, viewport: Viewport) anyerror!GraphBuilder,
        destroyBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) void,
        setupBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPass")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "createModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "createBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "destroyBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setupBuilder")) @compileError("implement me");

            return VTable{
                .addPass = &T.addPass,
                .addModule = &T.addModule,
                .createModule = &T.createModule,
                .createBuilder = &T.createBuilder,
                .destroyBuilder = &T.destroyBuilder,
                .setupBuilder = &T.setupBuilder,
            };
        }
    };
};

pub const RenderGraphApi = struct {
    create: *const fn () anyerror!Graph,
    createDefault: *const fn (allocator: std.mem.Allocator, graph: Graph) anyerror!void,
    destroy: *const fn (rg: Graph) void,
};

pub const RendererApi = struct {
    createViewport: *const fn (name: [:0]const u8, rg: Graph, world: ?ecs.World, camera_ent: ecs.EntityId) anyerror!Viewport,
    destroyViewport: *const fn (viewport: Viewport) void,
};
