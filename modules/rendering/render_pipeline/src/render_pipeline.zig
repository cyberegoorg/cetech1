const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const zm = cetech1.math.zmath;

const render_graph = @import("render_graph");
const shader_system = @import("shader_system");

pub const extensions = struct {
    pub const init = cetech1.strId32("init");
    pub const render = cetech1.strId32("render");
    pub const dd = cetech1.strId32("debugdraw");
};

pub const RenderPipeline = struct {
    pub inline fn deinit(self: *RenderPipeline) void {
        self.vtable.destroy(self.ptr);
    }

    pub inline fn fillModule(self: *RenderPipeline, module: render_graph.Module) !void {
        try self.vtable.fillModule(self.ptr, module);
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

    ptr: *anyopaque,
    vtable: *const RenderPipelineI,
};

pub const RenderPipelineI = struct {
    pub const c_name = "ct_render_pipeline_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    create: *const fn (allocator: std.mem.Allocator) anyerror!*anyopaque = undefined,
    destroy: *const fn (pipeline: *anyopaque) void = undefined,

    fillModule: *const fn (pipeline: *anyopaque, module: render_graph.Module) anyerror!void = undefined,

    begin: *const fn (pipeline: *anyopaque, context: *shader_system.SystemContext, now_s: f32) anyerror!void = undefined,
    end: *const fn (pipeline: *anyopaque, context: *shader_system.SystemContext) anyerror!void = undefined,

    getGlobalSystem: *const fn (pipeline: *anyopaque, name: cetech1.StrId32) ?*anyopaque = undefined,

    pub fn implement(comptime T: type) RenderPipelineI {
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");
        if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");
        if (!std.meta.hasFn(T, "fillModule")) @compileError("implement me");
        if (!std.meta.hasFn(T, "begin")) @compileError("implement me");
        if (!std.meta.hasFn(T, "end")) @compileError("implement me");
        if (!std.meta.hasFn(T, "getGlobalSystem")) @compileError("implement me");

        return RenderPipelineI{
            .create = T.create,
            .destroy = T.destroy,
            .fillModule = T.fillModule,
            .begin = T.begin,
            .end = T.end,
            .getGlobalSystem = T.getGlobalSystem,
        };
    }
};

pub const RenderPipelineApi = struct {
    createDefault: *const fn (allocator: std.mem.Allocator) anyerror!RenderPipeline,
};
