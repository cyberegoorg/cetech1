const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const apidb = cetech1.apidb;

const render_graph = cetech1.renderer.graph;
const shader_system = cetech1.renderer.shader_system;

pub const extensions = struct {
    pub const init = cetech1.strId32("init");
    pub const render = cetech1.strId32("render");
    pub const postprocess = cetech1.strId32("postprocess");
    pub const dd = cetech1.strId32("debugdraw");
};

pub const RenderPipeline = struct {
    pub inline fn deinit(self: *RenderPipeline) void {
        self.vtable.destroy(self.ptr);
    }

    pub inline fn getMainModule(self: *const RenderPipeline) *render_graph.Module {
        return self.vtable.getMainModule(self.ptr);
    }

    pub fn begin(self: *RenderPipeline, context: *shader_system.SystemContext, now_s: f32) !void {
        try self.vtable.begin(self.ptr, context, now_s);
    }

    pub fn end(self: *RenderPipeline, context: *shader_system.SystemContext) !void {
        try self.vtable.end(self.ptr, context);
    }

    pub fn getGlobalSystem(self: *const RenderPipeline, T: type, name: cetech1.StrId32) ?*T {
        if (self.vtable.getGlobalSystem(self.ptr, name)) |t| {
            return @ptrCast(@alignCast(t));
        }
        return null;
    }

    pub fn uiDebugMenuItems(self: *const RenderPipeline, allocator: std.mem.Allocator) !void {
        return self.vtable.uiDebugMenuItems(self.ptr, allocator);
    }

    ptr: *anyopaque,
    vtable: *const RenderPipelineI,
};

pub const RenderPipelineI = struct {
    pub const c_name = "ct_render_pipeline_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    create: *const fn (allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: *ecs.World) anyerror!*anyopaque = undefined,
    destroy: *const fn (pipeline: *anyopaque) void = undefined,

    getMainModule: *const fn (pipeline: *anyopaque) *render_graph.Module = undefined,

    begin: *const fn (pipeline: *anyopaque, context: *shader_system.SystemContext, now_s: f32) anyerror!void = undefined,
    end: *const fn (pipeline: *anyopaque, context: *shader_system.SystemContext) anyerror!void = undefined,

    getGlobalSystem: *const fn (pipeline: *anyopaque, name: cetech1.StrId32) ?*anyopaque = undefined,
    uiDebugMenuItems: *const fn (pipeline: *anyopaque, allocator: std.mem.Allocator) anyerror!void,

    pub fn implement(comptime T: type) RenderPipelineI {
        return RenderPipelineI{
            .create = T.create,
            .destroy = T.destroy,
            .getMainModule = T.getMainModule,
            .begin = T.begin,
            .end = T.end,
            .getGlobalSystem = T.getGlobalSystem,
            .uiDebugMenuItems = T.uiDebugMenuItems,
        };
    }
};

pub fn createDefault(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: *ecs.World) anyerror!RenderPipeline {
    return api.createDefault(allocator, gpu_backend, world);
}

pub const RenderPipelineApi = struct {
    createDefault: *const fn (allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: *ecs.World) anyerror!RenderPipeline,
};

pub var api: *const RenderPipelineApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, RenderPipelineApi).?;
}
