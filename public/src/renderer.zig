const std = @import("std");
const platform = @import("platform.zig");
const strid = @import("strid.zig");
const cdb = @import("cdb.zig");
const gpu = @import("gpu.zig");
const gfx_rg = @import("render_graph.zig");
const gfx_dd = @import("debug_draw.zig");
const ecs = @import("ecs.zig");
const graphvm = @import("graphvm.zig");
const zm = @import("root.zig").zmath;
const transform = @import("transform.zig");

const log = std.log.scoped(.renderer);

pub const RenderComponent = struct {
    graph: cdb.ObjId = .{},
};

pub const RenderComponentCdb = cdb.CdbTypeDecl(
    "ct_render_component",
    enum(u32) {
        graph = 0,
    },
    struct {},
);

pub const RenderComponentInstance = struct {
    graph_container: graphvm.GraphInstance = .{},
};

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

pub const ComponentRendererI = struct {
    pub const c_name = "ct_rg_component_renderer_i";
    pub const name_hash = strid.strId64(@This().c_name);

    culling: ?*const fn (allocator: std.mem.Allocator, builder: gfx_rg.GraphBuilder, world: ecs.World, viewers: []gfx_rg.Viewer, rq: *CullingRequest) anyerror!void = undefined,
    render: *const fn (allocator: std.mem.Allocator, builder: gfx_rg.GraphBuilder, world: ecs.World, viewport: Viewport, culling: ?*CullingResult) anyerror!void = undefined,

    size: usize,

    pub fn implement(comptime CompType: type, comptime T: type) ComponentRendererI {
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        return ComponentRendererI{
            .size = @sizeOf(CompType),
            .render = T.render,
            .culling = if (std.meta.hasFn(T, "culling")) T.culling else null,
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
    pub inline fn getDD(self: Viewport) gfx_dd.Encoder {
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
        getDD: *const fn (viewport: *anyopaque) gfx_dd.Encoder,
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

pub const RendererApi = struct {
    newViewId: *const fn () gpu.ViewId,

    renderAllViewports: *const fn (allocator: std.mem.Allocator) anyerror!void,
    createViewport: *const fn (name: [:0]const u8, rg: gfx_rg.RenderGraph, world: ?ecs.World) anyerror!Viewport,
    destroyViewport: *const fn (viewport: Viewport) void,
};
