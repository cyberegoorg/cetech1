const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const math = cetech1.math;
const apidb = cetech1.apidb;

const transform = cetech1.transform;
const camera = cetech1.camera;
const shader_system = cetech1.renderer.shader_system;
const render_graph = cetech1.renderer.graph;
const render_pipeline = cetech1.renderer.pipeline;
const visibility_flags = cetech1.renderer.visibility_flags;

pub const VIEWPORT_KERNEL_TASK = cetech1.strId64("RenderViewport");

pub const SphereBoudingVolume = struct {
    sphere: math.Spheref = .{},
    visibility_mask: visibility_flags.VisibilityFlags,
    skip_culling: bool = false,
};

pub const BoxBoudingVolume = struct {
    t: math.Transform = .{},
    min: math.Vec3f = .{},
    max: math.Vec3f = .{},
    visibility_mask: visibility_flags.VisibilityFlags,
    skip_culling: bool = false,
};

pub const BoundingVolumeType = enum(u8) {
    sphere,
    box,
    _,
};

pub const MAX_VIEWERS = 32;
pub const VisibilityBitField = cetech1.StaticBitSet(MAX_VIEWERS);

pub const RendereableComponentI = struct {
    pub const c_name = "ct_rg_renderable_component_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    init: ?*const fn (
        allocator: std.mem.Allocator,
        data: []*anyopaque,
    ) anyerror!void = undefined,

    fillBoundingVolumes: *const fn (
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransformComponent,
        data: []*anyopaque,
        volume_type: BoundingVolumeType,
        volumes: []u8,
    ) anyerror!void = undefined,

    render: *const fn (
        allocator: std.mem.Allocator,
        gpu_backend: gpu.GpuBackend,
        builder: *render_graph.GraphBuilder,
        world: *ecs.World,
        viewport: *Viewport,
        viewers: []const render_graph.Viewer,
        system_context: *const shader_system.SystemContext,
        entites_idx: []const usize,
        transforms: []transform.WorldTransformComponent,
        render_components: []*anyopaque,
        visibility: []const VisibilityBitField,
    ) anyerror!void = undefined,

    component_id: ecs.IdStrId,

    orderByCallback: ?*const fn (e1: ecs.EntityId, c1: *const anyopaque, e2: ecs.EntityId, c2: *const anyopaque) callconv(.c) i32 = null, // TODO: how without callconv?

    pub fn implement(comptime CompType: type, comptime T: type) RendereableComponentI {
        return RendereableComponentI{
            .component_id = ecs.id(CompType),
            .render = T.render,
            .fillBoundingVolumes = T.fillBoundingVolumes,
            .init = if (std.meta.hasFn(T, "init")) T.init else null,
            .orderByCallback = if (std.meta.hasFn(T, "orderByCallback")) T.orderByCallback else null,
        };
    }
};

pub const ShaderableComponentI = struct {
    pub const c_name = "ct_rg_shaderable_component_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    component_id: ecs.IdStrId,

    injectGraphModule: ?*const fn (allocator: std.mem.Allocator, manager: ?*anyopaque, module: *render_graph.Module) anyerror!void = undefined,

    init: ?*const fn (allocator: std.mem.Allocator, data: []*anyopaque) anyerror!void = undefined,

    fillBoundingVolumes: *const fn (
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransformComponent,
        data: []*anyopaque,
        volume_type: BoundingVolumeType,
        volumes: []u8,
    ) anyerror!void = undefined,

    update: *const fn (
        allocator: std.mem.Allocator,
        gpu_backend: gpu.GpuBackend,
        builder: *render_graph.GraphBuilder,
        world: *ecs.World,
        viewport: *Viewport,
        pipeline: render_pipeline.RenderPipeline,
        viewers: []const render_graph.Viewer,
        system_context: *const shader_system.SystemContext,
        entites_idx: []const usize,
        transforms: []transform.WorldTransformComponent,
        render_components: []*anyopaque,
        visibility: []const VisibilityBitField,
    ) anyerror!void = undefined,

    orderByCallback: ?*const fn (e1: ecs.EntityId, c1: *const anyopaque, e2: ecs.EntityId, c2: *const anyopaque) callconv(.c) i32 = null, // TODO: how without callconv?

    pub fn implement(comptime CompType: type, comptime T: type) ShaderableComponentI {
        return ShaderableComponentI{
            .component_id = ecs.id(CompType),
            .init = if (std.meta.hasFn(T, "init")) T.init else null,
            .injectGraphModule = if (std.meta.hasFn(T, "injectGraphModule")) T.injectGraphModule else null,
            .fillBoundingVolumes = T.fillBoundingVolumes,
            .update = T.update,
            .orderByCallback = if (std.meta.hasFn(T, "orderByCallback")) T.orderByCallback else null,
        };
    }
};

pub const Viewport = opaque {
    pub inline fn setSize(self: *Viewport, size: math.Vec2f) void {
        api.setSize(self, size);
    }

    pub inline fn getTexture(self: *Viewport) ?gpu.TextureHandle {
        return api.getTexture(self);
    }

    pub inline fn getSize(self: *Viewport) math.Vec2f {
        return api.getSize(self);
    }

    pub inline fn setMainCamera(self: *Viewport, camera_ent: ecs.EntityId) void {
        return api.setMainCamera(self, camera_ent);
    }

    pub inline fn getMainCamera(self: *Viewport) ?ecs.EntityId {
        return api.getMainCamera(self);
    }

    pub inline fn requestRender(self: *Viewport) void {
        return api.requestRender(self);
    }

    pub inline fn setDebugCulling(self: *Viewport, enable: bool) void {
        return api.setDebugCulling(self, enable);
    }

    pub inline fn getDebugCulling(self: *Viewport) bool {
        return api.getDebugCulling(self);
    }

    pub inline fn setSelectedEntity(self: *Viewport, entity: ?ecs.EntityId) void {
        return api.setSelectedEntity(self, entity);
    }

    pub inline fn frezeMainCameraCulling(self: *Viewport, freeze: bool) void {
        return api.frezeMainCameraCulling(self, freeze);
    }
};

pub const ColorResource = "viewport_color";

pub fn createViewport(name: [:0]const u8, gpu_backend: gpu.GpuBackend, pipeline: render_pipeline.RenderPipeline, world: ?*ecs.World, output_to_backbuffer: bool) anyerror!*Viewport {
    return api.createViewport(name, gpu_backend, pipeline, world, output_to_backbuffer);
}
pub fn destroyViewport(viewport: *Viewport) void {
    return api.destroyViewport(viewport);
}
pub fn uiDebugMenuItems(allocator: std.mem.Allocator, viewport: *Viewport) anyerror!void {
    return api.uiDebugMenuItems(allocator, viewport);
}

pub const RenderViewportApi = struct {
    createViewport: *const fn (name: [:0]const u8, gpu_backend: gpu.GpuBackend, pipeline: render_pipeline.RenderPipeline, world: ?*ecs.World, output_to_backbuffer: bool) anyerror!*Viewport,
    destroyViewport: *const fn (viewport: *Viewport) void,
    uiDebugMenuItems: *const fn (allocator: std.mem.Allocator, viewport: *Viewport) anyerror!void,

    setSize: *const fn (viewport: *Viewport, size: math.Vec2f) void,
    getTexture: *const fn (viewport: *Viewport) ?gpu.TextureHandle,
    getSize: *const fn (viewport: *Viewport) math.Vec2f,
    getMainCamera: *const fn (viewport: *Viewport) ?ecs.EntityId,
    setMainCamera: *const fn (viewport: *Viewport, camera_ent: ?ecs.EntityId) void,
    frezeMainCameraCulling: *const fn (viewport: *Viewport, freeze: bool) void,
    requestRender: *const fn (viewport: *Viewport) void,
    getDebugCulling: *const fn (viewport: *Viewport) bool,
    setDebugCulling: *const fn (viewport: *Viewport, enable: bool) void,
    setSelectedEntity: *const fn (viewport: *Viewport, entity: ?ecs.EntityId) void,
};

pub var api: *const RenderViewportApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, RenderViewportApi).?;
}
