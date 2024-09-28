const std = @import("std");
const platform = @import("platform.zig");
const strid = @import("strid.zig");
const cdb = @import("cdb.zig");
const gpu = @import("gpu.zig");

const ecs = @import("ecs.zig");
const zm = @import("root.zig").zmath;
const transform = @import("transform.zig");

const log = std.log.scoped(.renderer);

pub const CullingVolume = struct {
    radius: f32 = 0,
};

const MatList = std.ArrayList(transform.WorldTransform);
const RenderableBufferList = std.ArrayList(u8);
const CullingVolumeList = std.ArrayList(CullingVolume);

pub const CullingRequest = struct {
    mtx: MatList,
    renderables: RenderableBufferList,
    volumes: CullingVolumeList,
    lck: std.Thread.Mutex,

    renderable_size: usize,

    pub fn init(allocator: std.mem.Allocator, renderable_size: usize) CullingRequest {
        return CullingRequest{
            .mtx = MatList.init(allocator),
            .renderables = RenderableBufferList.init(allocator),
            .volumes = CullingVolumeList.init(allocator),
            .lck = .{},
            .renderable_size = renderable_size,
        };
    }

    pub fn clean(self: *CullingRequest) void {
        self.mtx.clearRetainingCapacity();
        self.volumes.clearRetainingCapacity();
        self.renderables.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingRequest) void {
        self.mtx.deinit();
        self.volumes.deinit();
        self.renderables.deinit();
    }

    pub fn append(self: *CullingRequest, mtxs: []const transform.WorldTransform, volumes: []const CullingVolume, renderables_data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.appendSlice(mtxs);
        try self.volumes.appendSlice(volumes);
        try self.renderables.appendSlice(renderables_data);
    }
};

pub const CullingResult = struct {
    mtx: MatList,
    renderables: RenderableBufferList,
    lck: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) CullingResult {
        return CullingResult{
            .mtx = MatList.init(allocator),
            .renderables = RenderableBufferList.init(allocator),
            .lck = .{},
        };
    }

    pub fn clean(self: *CullingResult) void {
        self.mtx.clearRetainingCapacity();
        self.renderables.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingResult) void {
        self.mtx.deinit();
        self.renderables.deinit();
    }

    pub fn append(self: *CullingResult, mtx: transform.WorldTransform, data: []u8) !void {
        self.lck.lock();
        defer self.lck.unlock();

        try self.mtx.append(mtx);
        try self.renderables.appendSlice(data);
    }

    pub fn appendMany(self: *CullingResult, mtxs: []const transform.WorldTransform, data: []u8) !void {
        // self.lck.lock();
        // defer self.lck.unlock();

        try self.mtx.appendSlice(mtxs);
        try self.renderables.appendSlice(data);
    }
};

pub const RendereableI = struct {
    pub const c_name = "ct_rg_component_renderer_i";
    pub const name_hash = strid.strId64(@This().c_name);

    culling: ?*const fn (allocator: std.mem.Allocator, builder: GraphBuilder, world: ecs.World, viewers: []Viewer, rq: *CullingRequest) anyerror!void = undefined,
    render: *const fn (allocator: std.mem.Allocator, builder: GraphBuilder, world: ecs.World, viewport: Viewport, culling: ?*CullingResult) anyerror!void = undefined,

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
    pub inline fn getDD(self: Viewport) gpu.DDEncoder {
        return self.vtable.getDD(self.ptr);
    }
    pub inline fn setViewMtx(self: Viewport, mtx: [16]f32) void {
        return self.vtable.setViewMtx(self.ptr, mtx);
    }
    pub inline fn getViewMtx(self: Viewport) [16]f32 {
        return self.vtable.getViewMtx(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        setSize: *const fn (viewport: *anyopaque, size: [2]f32) void,
        getTexture: *const fn (viewport: *anyopaque) ?gpu.TextureHandle,
        getFb: *const fn (viewport: *anyopaque) ?gpu.FrameBufferHandle,
        getSize: *const fn (viewport: *anyopaque) [2]f32,
        getDD: *const fn (viewport: *anyopaque) gpu.DDEncoder,
        setViewMtx: *const fn (viewport: *anyopaque, mtx: [16]f32) void,
        getViewMtx: *const fn (viewport: *anyopaque) [16]f32,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "setSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getTexture")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getFb")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getDD")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setViewMtx")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getViewMtx")) @compileError("implement me");

            return VTable{
                .setSize = &T.setSize,
                .getTexture = &T.getTexture,
                .getFb = &T.getFb,
                .getSize = &T.getSize,
                .getDD = &T.getDD,
                .setViewMtx = &T.setViewMtx,
                .getViewMtx = &T.getViewMtx,
            };
        }
    };
};

const GfxApi = gpu.GpuApi;

pub const Pass = struct {
    setup: *const fn (pass: *Pass, builder: GraphBuilder) anyerror!void,
    render: *const fn (builder: GraphBuilder, gfx_api: *const GfxApi, viewport: Viewport, viewid: gpu.ViewId) anyerror!void,

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

    pub inline fn compile(builder: GraphBuilder) !void {
        return builder.vtable.compile(builder.ptr);
    }
    pub inline fn execute(builder: GraphBuilder, viewport: Viewport) !void {
        return builder.vtable.execute(builder.ptr, viewport);
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

        getViewers: *const fn (builder: *anyopaque) []Viewer,

        compile: *const fn (builder: *anyopaque) anyerror!void,
        execute: *const fn (builder: *anyopaque, viewport: Viewport) anyerror!void,
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
    newViewId: *const fn () gpu.ViewId,

    renderAll: *const fn (ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) void,

    createViewport: *const fn (name: [:0]const u8, rg: Graph, world: ?ecs.World) anyerror!Viewport,
    destroyViewport: *const fn (viewport: Viewport) void,
};
