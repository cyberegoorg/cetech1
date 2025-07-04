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

pub const SphereBoudingVolume = struct {
    center: [3]f32 = .{ 0, 0, 0 },
    radius: f32 = 0,
};

pub const BoxBoudingVolume = struct {
    t: transform.WorldTransform = .{},
    min: [3]f32 = .{ 0, 0, 0 },
    max: [3]f32 = .{ 0, 0, 0 },
};

pub const BoundingVolumeType = enum(u8) {
    sphere,
    box,
    _,
};

pub const MAX_VIEWERS = 32;
pub const VisibilityBitField = cetech1.StaticBitSet(MAX_VIEWERS);

pub const RendereableComponentI = struct {
    pub const c_name = "ct_renderable_component_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    init: ?*const fn (
        allocator: std.mem.Allocator,
        data: []*anyopaque,
    ) anyerror!void = undefined,

    prepare_bounding_volumes: *const fn (
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransform,
        data: []*anyopaque,
        volume_type: BoundingVolumeType,
        volumes: []u8,
    ) anyerror!void = undefined,

    render: *const fn (
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: Viewport,
        viewers: []const render_graph.Viewer,
        systems: []*shader_system.SystemInstance,
        entites_idx: []const usize,
        transforms: []transform.WorldTransform,
        render_components: []*anyopaque,
        visibility: []const VisibilityBitField,
    ) anyerror!void = undefined,

    component_id: cetech1.StrId32,

    pub fn implement(comptime CompType: type, comptime T: type) RendereableComponentI {
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        return RendereableComponentI{
            .component_id = ecs.id(CompType),
            .render = T.render,
            .prepare_bounding_volumes = T.prepare_bounding_volumes,
            .init = if (std.meta.hasFn(T, "init")) T.init else null,
        };
    }
};

pub const ShaderableComponentI = struct {
    pub const c_name = "ct_rg_shaderable_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    inject_graph_module: ?*const fn (
        allocator: std.mem.Allocator,
        module: render_graph.Module,
    ) anyerror!void = undefined,

    init: ?*const fn (
        allocator: std.mem.Allocator,
        data: []*anyopaque,
    ) anyerror!void = undefined,

    prepare_bounding_volumes: *const fn (
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransform,
        data: []*anyopaque,
        volume_type: BoundingVolumeType,
        volumes: []u8,
    ) anyerror!void = undefined,

    update: *const fn (
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: Viewport,
        viewers: []const render_graph.Viewer,
        systems: []*shader_system.SystemInstance,
        entites_idx: []const usize,
        transforms: []transform.WorldTransform,
        render_components: []*anyopaque,
        visibility: []const VisibilityBitField,
    ) anyerror!void = undefined,

    component_id: cetech1.StrId32,

    pub fn implement(comptime CompType: type, comptime T: type) ShaderableComponentI {
        if (!std.meta.hasFn(T, "update")) @compileError("implement me");

        return ShaderableComponentI{
            .id = cetech1.strId32(@typeName(CompType)),
            .size = @sizeOf(CompType),
            .init = if (std.meta.hasFn(T, "init")) T.init else null,
            .inject_graph_module = if (std.meta.hasFn(T, "inject_graph_module")) T.inject_graph_module else null,
            .prepare_bounding_volumes = T.prepare_bounding_volumes,
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
