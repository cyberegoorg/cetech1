const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const render_viewport = @import("render_viewport");
const render_graph = @import("render_graph");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const graphvm = @import("graphvm");
const transform = @import("transform");
const shader_system = @import("shader_system");
const renderer_nodes = @import("renderer_nodes");

const public = @import("render_component.zig");

const module_name = .render_component;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _graphvm: *const graphvm.GraphVMApi = undefined;
var _gpu: *const gpu.GpuApi = undefined;
var _dd: *const gpu.GpuDDApi = undefined;
var _shader_system: *const shader_system.ShaderSystemAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const init_render_graph_system_i = ecs.SystemI.implement(
    .{
        .name = "renderer.init_render_component",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(public.RenderComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.RenderComponent), .inout = .In },
        },
    },
    struct {
        pub fn update(world: ecs.World, it: *ecs.Iter) !void {
            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            const ents = it.entities();
            const render_component = it.field(public.RenderComponent, 1).?;

            const instances = try alloc.alloc(graphvm.GraphInstance, render_component.len);
            defer alloc.free(instances);

            // TODO: SHIT
            if (render_component[0].graph.isEmpty()) return;

            try _graphvm.createInstances(alloc, render_component[0].graph, instances);
            try _graphvm.buildInstances(alloc, instances);

            for (0..it.count()) |idx| {
                _ = world.setId(public.RenderComponentInstance, ents[idx], &public.RenderComponentInstance{ .graph_container = instances[idx] });
                try _graphvm.setInstanceContext(instances[idx], ecs.ECS_WORLD_CONTEXT, world.ptr);
                try _graphvm.setInstanceContext(instances[idx], ecs.ECS_ENTITY_CONTEXT, @ptrFromInt(ents[idx]));
            }

            // world.deferSuspend();
            try _graphvm.executeNode(alloc, instances, graphvm.EVENT_INIT_NODE_TYPE, .{ .use_tasks = false });
            // world.deferResume();
        }
    },
);

const render_component_c = ecs.ComponentI.implement(
    public.RenderComponent,
    .{
        .cdb_type_hash = public.RenderComponentCdb.type_hash,
        .category = "Renderer",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.CoreIcons.FA_CUBE});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const component = std.mem.bytesAsValue(public.RenderComponent, data);
            component.* = public.RenderComponent{
                .graph = public.RenderComponentCdb.readSubObj(_cdb, r, .graph) orelse .{},
            };
        }
    },
);

const rc_initialized_c = ecs.ComponentI.implement(
    public.RenderComponentInstance,
    .{},
    struct {
        pub fn onDestroy(components: []public.RenderComponentInstance) !void {
            for (components) |c| {
                if (c.graph_container.isValid()) {
                    _graphvm.destroyInstance(c.graph_container);
                }
            }
        }

        pub fn onMove(dsts: []public.RenderComponentInstance, srcs: []public.RenderComponentInstance) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.graph_container = .{};
            }
        }

        pub fn onRemove(iter: *ecs.IterO) !void {
            var it = _ecs.toIter(iter);
            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);
            const components = it.field(public.RenderComponentInstance, 0).?;

            try _graphvm.executeNode(alloc, toInstanceSlice(components), graphvm.EVENT_SHUTDOWN_NODE_TYPE, .{ .use_tasks = false });
        }
    },
);

const RenderComponentTask = struct {
    transforms: []const transform.WorldTransform,
    entities_idx: []const usize,
    draw_calls: []const ?*render_viewport.DrawCall,
    viewers: []const render_graph.Viewer,
    shader_context: *const shader_system.ShaderContext,
    builder: render_graph.GraphBuilder,
    visibility: []const render_viewport.VisibilityBitField,

    pub fn exec(self: *@This()) !void {
        var zone = _profiler.ZoneN(@src(), "RenderComponentTask");
        defer zone.End();

        const allocator = try _tmpalloc.create();
        defer _tmpalloc.destroy(allocator);

        if (_gpu.getEncoder()) |e| {
            defer _gpu.endEncoder(e);

            self.shader_context.submit(e);

            for (self.draw_calls, self.entities_idx, 0..) |draw_call, ent_idx, renderable_idx| {
                if (draw_call) |dc| {
                    const mtx = self.transforms[ent_idx];

                    var zzz = _profiler.ZoneN(@src(), "RenderComponentTask - draw call");
                    defer zzz.End();

                    if (dc.gpu_shader) |gpu_shader| {
                        _ = e.setTransform(&zm.matToArr(mtx.mtx), 1);

                        if (dc.gpu_geometry) |gpu_geometry| {
                            for (gpu_geometry.vb, 0..) |vb, idx| {
                                if (vb.isValid()) {
                                    e.setVertexBuffer(@truncate(idx), vb, 0, dc.vertex_count);
                                }
                            }
                        }

                        if (draw_call.?.gpu_index_buffer) |gpu_index_buffer| {
                            e.setIndexBuffer(gpu_index_buffer, 0, dc.index_count);
                        }

                        for (self.viewers, 0..) |viewer, viewer_idx| {
                            if (!self.visibility[renderable_idx].isSet(viewer_idx)) continue;

                            const variants = try _shader_system.selectShaderVariant(
                                allocator,
                                gpu_shader,
                                viewer.context,
                                self.shader_context,
                            );
                            defer allocator.free(variants);

                            for (variants) |variant| {
                                if (variant.prg) |prg| {
                                    _shader_system.submitShaderUniforms(e, variant, gpu_shader);

                                    const layer = if (variant.layer) |l| self.builder.getLayerById(l) else continue; // TODO: SHIT
                                    e.setState(variant.state, variant.rgba);
                                    e.submit(layer, prg, 0, 0);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
};

pub fn toInstanceSlice(from: anytype) []const graphvm.GraphInstance {
    var containers: []const graphvm.GraphInstance = undefined;
    containers.ptr = @alignCast(@ptrCast(from.ptr));
    containers.len = from.len;
    return containers;
}

const render_component_renderer_i = render_viewport.RendereableComponentI.implement(public.RenderComponentInstance, struct {
    pub fn init(
        allocator: std.mem.Allocator,
        data: []*anyopaque,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "RenderComponent - Init calback");
        defer zz.End();

        var containers = try cetech1.ArrayList(graphvm.GraphInstance).initCapacity(allocator, data.len);
        defer containers.deinit(allocator);
        try containers.resize(allocator, data.len);

        for (data, 0..) |d, idx| {
            const gi: *graphvm.GraphInstance = @alignCast(@ptrCast(d));
            containers.items[idx] = gi.*;
        }

        try _graphvm.executeNode(
            allocator,
            containers.items,
            renderer_nodes.CULLING_VOLUME_NODE_TYPE,
            .{},
        );
    }

    pub fn fill_bounding_volumes(
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransform,
        data: []*anyopaque,
        volume_type: render_viewport.BoundingVolumeType,
        volumes: []u8,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "RenderComponent - Culling calback");
        defer zz.End();

        var containers = try cetech1.ArrayList(graphvm.GraphInstance).initCapacity(allocator, transforms.len);
        defer containers.deinit(allocator);
        try containers.resize(allocator, if (entites_idx) |eidxs| eidxs.len else transforms.len);

        if (entites_idx) |idxs| {
            for (idxs, 0..) |ent_idx, idx| {
                const gi: *graphvm.GraphInstance = @alignCast(@ptrCast(data[ent_idx]));
                containers.items[idx] = gi.*;
            }
        } else {
            for (data, 0..) |d, idx| {
                const gi: *graphvm.GraphInstance = @alignCast(@ptrCast(d));
                containers.items[idx] = gi.*;
            }
        }

        const states = try _graphvm.getNodeState(
            render_viewport.CullingVolume,
            allocator,
            containers.items,
            renderer_nodes.CULLING_VOLUME_NODE_TYPE,
        );
        defer allocator.free(states);

        switch (volume_type) {
            .sphere => {
                var sphere_out_volumes = std.mem.bytesAsSlice(render_viewport.SphereBoudingVolume, volumes);

                for (states, 0..) |volume, idx| {
                    if (volume) |v| {
                        const mat = if (entites_idx) |idxs| transforms[idxs[idx]].mtx else transforms[idx].mtx;

                        const origin = zm.util.getTranslationVec(mat);
                        var center = [3]f32{ 0, 0, 0 };
                        zm.storeArr3(&center, origin);

                        sphere_out_volumes[idx] = .{
                            .center = center,
                            .radius = v.radius,
                        };
                    } else {
                        sphere_out_volumes[idx] = .{};
                    }
                }
            },
            .box => {
                var box_out_volumes = std.mem.bytesAsSlice(render_viewport.BoxBoudingVolume, volumes);

                for (states, 0..) |volume, idx| {
                    if (volume) |v| {
                        const t = if (entites_idx) |idxs| transforms[idxs[idx]] else transforms[idx];

                        box_out_volumes[idx] = .{
                            .t = t,
                            .min = v.min,
                            .max = v.max,
                        };
                    } else {
                        box_out_volumes[idx] = .{};
                    }
                }
            },
            else => |v| {
                log.err("Invalid bounding volume {d}", .{v});
            },
        }
    }

    pub fn render(
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: render_viewport.Viewport,
        viewers: []const render_graph.Viewer,
        shader_context: *const shader_system.ShaderContext,
        entites_idx: []const usize,
        transforms: []transform.WorldTransform,
        render_components: []*anyopaque,
        visibility: []const render_viewport.VisibilityBitField,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "RenderComponent - Render calback");
        defer zz.End();
        _ = world;

        var containers = try cetech1.ArrayList(graphvm.GraphInstance).initCapacity(allocator, entites_idx.len);
        defer containers.deinit(allocator);
        try containers.resize(allocator, entites_idx.len);

        for (entites_idx, 0..) |ent_idx, idx| {
            const gi: *graphvm.GraphInstance = @alignCast(@ptrCast(render_components[ent_idx]));
            containers.items[idx] = gi.*;
        }

        const draw_calls = try _graphvm.executeNodeAndGetState(
            render_viewport.DrawCall,
            allocator,
            containers.items,
            renderer_nodes.DRAW_CALL_NODE_TYPE,
            .{},
        );
        defer allocator.free(draw_calls);

        const ARGS = struct {
            viewport: render_viewport.Viewport,
            viewers: []const render_graph.Viewer,
            shader_context: *const shader_system.ShaderContext,
            builder: render_graph.GraphBuilder,

            entities_idx: []const usize,
            transforms: []transform.WorldTransform,
            draw_calls: []const ?*render_viewport.DrawCall,
            visibility: []const render_viewport.VisibilityBitField,
        };
        if (try cetech1.task.batchWorkloadTask(
            .{
                .allocator = allocator,
                .task_api = _task,
                .profiler_api = _profiler,
                .count = entites_idx.len,
            },

            ARGS{
                .viewport = viewport,
                .viewers = viewers,
                .shader_context = shader_context,
                .builder = builder,

                .entities_idx = entites_idx,
                .transforms = transforms,
                .draw_calls = draw_calls,
                .visibility = visibility,
            },

            struct {
                pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) RenderComponentTask {
                    return RenderComponentTask{
                        .viewers = create_args.viewers,
                        .shader_context = create_args.shader_context,
                        .builder = create_args.builder,

                        .entities_idx = create_args.entities_idx[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                        .transforms = create_args.transforms,

                        .visibility = create_args.visibility[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                        .draw_calls = create_args.draw_calls[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                    };
                }
            },
        )) |t| {
            _task.wait(t);
        }
    }
});

// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // RenderComponentCdb
        {
            const type_idx = try _cdb.addType(
                db,
                public.RenderComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.RenderComponentCdb.propIdx(.graph),
                        .name = "graph",
                        .type = cdb.PropType.SUBOBJECT,
                        .type_hash = graphvm.GraphType.type_hash,
                    },
                },
            );
            _ = type_idx; // autofix
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _graphvm = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _shader_system = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, ecs.ComponentI, &render_component_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &rc_initialized_c, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_render_graph_system_i, load);

    try apidb.implOrRemove(module_name, render_viewport.RendereableComponentI, &render_component_renderer_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_render_component(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
