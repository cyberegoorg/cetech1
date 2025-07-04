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

pub const RENDERER_KERNEL_TASK = cetech1.strId64("Renderer");

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

const MatList = cetech1.ArrayList(transform.WorldTransform);
const CullableBufferList = cetech1.ByteList;
const CullingVolumeList = cetech1.ArrayList(CullingVolume);

pub const CullingRequest = struct {
    allocator: std.mem.Allocator,

    mtx: MatList = .{},
    data: CullableBufferList = .{},
    volumes: CullingVolumeList = .{},

    no_cullables_mtx: MatList = .{},
    no_cullables_data: CullableBufferList = .{},

    lck: std.Thread.Mutex,

    cullable_size: usize,

    pub fn init(allocator: std.mem.Allocator, cullable_size: usize) CullingRequest {
        return CullingRequest{
            .allocator = allocator,
            .lck = .{},
            .cullable_size = cullable_size,
        };
    }

    pub fn clear(self: *CullingRequest) void {
        self.mtx.clearRetainingCapacity();
        self.volumes.clearRetainingCapacity();
        self.data.clearRetainingCapacity();
        self.no_cullables_mtx.clearRetainingCapacity();
        self.no_cullables_data.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingRequest) void {
        self.mtx.deinit(self.allocator);
        self.volumes.deinit(self.allocator);
        self.data.deinit(self.allocator);
        self.no_cullables_mtx.deinit(self.allocator);
        self.no_cullables_data.deinit(self.allocator);
    }

    pub fn append(self: *CullingRequest, mtxs: []const transform.WorldTransform, volumes: []const CullingVolume, renderables_data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.appendSlice(self.allocator, mtxs);
        try self.volumes.appendSlice(self.allocator, volumes);
        try self.data.appendSlice(self.allocator, renderables_data);
    }

    pub fn appendNoCulling(self: *CullingRequest, mtxs: []const transform.WorldTransform, renderables_data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.no_cullables_mtx.appendSlice(self.allocator, mtxs);
        try self.no_cullables_data.appendSlice(self.allocator, renderables_data);
    }
};

pub const VisibilityBitField = cetech1.DynamicBitSet;

pub const CullingResult = struct {
    allocator: std.mem.Allocator,

    lck: std.Thread.Mutex,
    mtx: MatList = .{},
    data: CullableBufferList = .{},

    visibility: VisibilityBitField = .{},
    visibility_lck: std.Thread.Mutex,

    visibility_filtered: VisibilityBitField = .{},

    pub fn init(allocator: std.mem.Allocator) CullingResult {
        return CullingResult{
            .allocator = allocator,
            .lck = .{},
            .visibility_lck = .{},
        };
    }

    pub fn clear(self: *CullingResult) void {
        self.mtx.clearRetainingCapacity();
        self.data.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingResult) void {
        self.mtx.deinit(self.allocator);
        self.data.deinit(self.allocator);
        self.visibility.deinit(self.allocator);
        self.visibility_filtered.deinit(self.allocator);
    }

    pub fn append(self: *CullingResult, mtx: transform.WorldTransform, data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.append(self.allocator, mtx);
        try self.data.appendSlice(self.allocator, data);
    }

    pub fn appendMany(self: *CullingResult, mtx: []const transform.WorldTransform, data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.appendSlice(self.allocator, mtx);
        try self.data.appendSlice(self.allocator, data);
    }

    pub fn setVisibility(self: *CullingResult, idx: usize) void {
        self.visibility_lck.lock();
        defer self.visibility_lck.unlock();
        self.visibility.set(idx);
    }

    pub fn isVisibile(self: *const CullingResult, idx: usize) bool {
        return self.visibility_filtered.isSet(idx);
    }
};

pub const RendereableI = struct {
    pub const c_name = "ct_rg_renderables_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    culling: ?*const fn (
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewers: []const render_graph.Viewer,
        rq: *CullingRequest,
    ) anyerror!void = undefined,

    render: *const fn (
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: Viewport,
        viewers: []const render_graph.Viewer,
        systems: shader_system.SystemSet,
        result: *const CullingResult,
    ) anyerror!void = undefined,

    id: cetech1.StrId32,
    size: usize,

    pub fn implement(comptime CompType: type, comptime T: type) RendereableI {
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        return RendereableI{
            .id = cetech1.strId32(@typeName(CompType)),
            .size = @sizeOf(CompType),
            .render = T.render,
            .culling = if (std.meta.hasFn(T, "culling")) T.culling else null,
        };
    }
};

pub const ShaderableI = struct {
    pub const c_name = "ct_rg_shaderable_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    inject_graph_module: ?*const fn (
        allocator: std.mem.Allocator,
        module: render_graph.Module,
    ) anyerror!void = undefined,

    culling: ?*const fn (
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewers: []const render_graph.Viewer,
        rq: *CullingRequest,
    ) anyerror!void = undefined,

    update: *const fn (
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: Viewport,
        viewers: []const render_graph.Viewer,
        systems: shader_system.SystemSet,
        result: *const CullingResult,
    ) anyerror!void = undefined,

    id: cetech1.StrId32,
    size: usize,

    pub fn implement(comptime CompType: type, comptime T: type) ShaderableI {
        if (!std.meta.hasFn(T, "update")) @compileError("implement me");

        return ShaderableI{
            .id = cetech1.strId32(@typeName(CompType)),
            .size = @sizeOf(CompType),
            .inject_graph_module = if (std.meta.hasFn(T, "inject_graph_module")) T.culling else null,
            .culling = if (std.meta.hasFn(T, "culling")) T.culling else null,
            .update = T.update,
        };
    }
};

pub const DefaultRenderGraphI = struct {
    pub const c_name = "ct_rg_default_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    create: *const fn (
        allocator: std.mem.Allocator,
        rg_api: *const render_graph.RenderGraphApi,
        module: render_graph.Module,
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

    pub inline fn renderMe(self: Viewport, module: render_graph.Module) void {
        return self.vtable.renderMe(self.ptr, module);
    }

    pub inline fn setDebugCulling(self: Viewport, enable: bool) void {
        return self.vtable.setDebugCulling(self.ptr, enable);
    }

    pub inline fn getDebugCulling(self: Viewport) bool {
        return self.vtable.getDebugCulling(self.ptr);
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

        renderMe: *const fn (viewport: *anyopaque, module: render_graph.Module) void,

        getDebugCulling: *const fn (viewport: *anyopaque) bool,
        setDebugCulling: *const fn (viewport: *anyopaque, enable: bool) void,

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

                .getDebugCulling = &T.getDebugCulling,
                .setDebugCulling = &T.setDebugCulling,
            };
        }
    };
};

pub const ViewportColorResource = "viewport_color";

pub const RendererApi = struct {
    createViewport: *const fn (name: [:0]const u8, world: ?ecs.World, camera_ent: ecs.EntityId) anyerror!Viewport,
    destroyViewport: *const fn (viewport: Viewport) void,

    uiDebugMenuItems: *const fn (allocator: std.mem.Allocator, viewport: Viewport) void,
};
