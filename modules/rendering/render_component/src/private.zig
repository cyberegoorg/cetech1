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
const renderer = @import("renderer");
const visibility_flags = @import("visibility_flags");
const instance_system = @import("instance_system");

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

var _dd: *const gpu.GpuDDApi = undefined;
var _shader_system: *const shader_system.ShaderSystemAPI = undefined;
var _visibility_flags: *const visibility_flags.VisibilityFlagsApi = undefined;
var _instance_system: *const instance_system.InstanceSystemApi = undefined;

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
        pub fn update(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

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

const UpdateHashesTask = struct {
    draw_calls: []const ?*renderer_nodes.DrawCall,
    visibility: []const render_viewport.VisibilityBitField,
    hashes: []u64,

    pub fn exec(self: *@This()) !void {
        var zzz = _profiler.ZoneN(@src(), "RenderComponentTask - Update hashes");
        defer zzz.End();
        for (self.draw_calls, 0..) |dc, idx| {
            var h = std.hash.Fnv1a_64.init();
            std.hash.autoHash(&h, dc.?.hash);
            std.hash.autoHash(&h, self.visibility[idx].mask);
            const final_hash = h.final();

            self.hashes[idx] = final_hash;
        }
    }
};

pub fn toInstanceSlice(from: anytype) []const graphvm.GraphInstance {
    var containers: []const graphvm.GraphInstance = undefined;
    containers.ptr = @ptrCast(@alignCast(from.ptr));
    containers.len = from.len;
    return containers;
}

const SortDrawCallsContext = struct {
    drawcalls: []?*renderer_nodes.DrawCall,
    ent_idx: []usize,
    visibility: []const render_viewport.VisibilityBitField,
    hash: []u64,

    pub fn lessThan(ctx: *SortDrawCallsContext, lhs: usize, rhs: usize) bool {
        return ctx.hash[lhs] < ctx.hash[rhs];
    }

    pub fn swap(ctx: *SortDrawCallsContext, lhs: usize, rhs: usize) void {
        std.mem.swap(usize, &ctx.ent_idx[lhs], &ctx.ent_idx[rhs]);
        std.mem.swap(u64, &ctx.hash[lhs], &ctx.hash[rhs]);
        std.mem.swap(?*renderer_nodes.DrawCall, &ctx.drawcalls[lhs], &ctx.drawcalls[rhs]);
    }
};

fn lessThanDrawCall(ctx: *SortDrawCallsContext, lhs: usize, rhs: usize) bool {
    return ctx.drawcalls[lhs].?.hash < ctx.drawcalls[rhs].?.hash;
}

const DrawCallCusterDef = struct {
    first_idx: usize,
    calls: []const ?*renderer_nodes.DrawCall,
};

fn clusterByDrawCall(allocator: std.mem.Allocator, sorted_instances: []?*renderer_nodes.DrawCall, hash: []u64, max_cluster: usize) ![]DrawCallCusterDef {
    var zone2_ctx = _profiler.ZoneN(@src(), "clusterByDrawCall");
    defer zone2_ctx.End();

    var clusters = try cetech1.ArrayList(DrawCallCusterDef).initCapacity(allocator, max_cluster);
    defer clusters.deinit(allocator);

    var cluster_begin_idx: usize = 0;
    var current_obj = hash[0];
    for (0..sorted_instances.len) |idx| {
        if (hash[idx] == current_obj) continue;

        clusters.appendAssumeCapacity(.{
            .first_idx = cluster_begin_idx,
            .calls = sorted_instances[cluster_begin_idx..idx],
        });
        current_obj = hash[idx];
        cluster_begin_idx = idx; //-1;
    }

    // Add rest
    clusters.appendAssumeCapacity(.{
        .first_idx = cluster_begin_idx,
        .calls = sorted_instances[cluster_begin_idx..sorted_instances.len],
    });

    return clusters.toOwnedSlice(allocator);
}

fn submitDrawcall(
    allocator: std.mem.Allocator,
    e: gpu.GpuEncoder,
    dc: *const renderer_nodes.DrawCall,
    builder: render_graph.GraphBuilder,
    system_context: *shader_system.SystemContext,
    first_idx: usize,
    viewers: []const render_graph.Viewer,
    visibility: []const render_viewport.VisibilityBitField,
) !void {
    const shader_io = _shader_system.getShaderIO(dc.shader.?);

    if (dc.uniforms) |u| _shader_system.bindConstant(shader_io, u, e);
    if (dc.resouces) |r| _shader_system.bindResource(shader_io, r, e);

    var contexts = try cetech1.StrId32List.initCapacity(allocator, visibility_flags.MAX_FLAGS);
    defer contexts.deinit(allocator);

    var viewer_it = visibility[first_idx].iterator(.{ .kind = .set });
    while (viewer_it.next()) |viewer_idx| {
        const viewer = &viewers[viewer_idx];

        try system_context.addSystem(viewer.viewer_system, viewer.viewer_system_uniforms, null);

        contexts.clearRetainingCapacity();
        var visibility_flags_it = (dc.visibility_mask.intersectWith(viewer.visibility_mask)).iterator(.{ .kind = .set });
        while (visibility_flags_it.next()) |flags_idx| {
            var flag = visibility_flags.VisibilityFlags.initEmpty();
            flag.set(flags_idx);
            contexts.appendAssumeCapacity(_visibility_flags.toName(flag).?);
        }

        const variants = try _shader_system.selectShaderVariant(
            allocator,
            dc.shader.?,
            contexts.items,
            system_context,
        );
        defer allocator.free(variants);

        system_context.bind(shader_io, e);
        for (variants) |variant| {
            if (variant.prg) |prg| {
                const viewid = if (variant.layer) |l| builder.getLayerById(l) else viewer.viewid.?; // TODO: SHIT

                var s = variant.state;
                s.primitive_type = dc.geometry.?.primitive_type;

                e.setState(variant.state, variant.rgba);
                e.submit(viewid, prg, 0, .{});
            }
        }
    }
}

const render_component_renderer_i = render_viewport.RendereableComponentI.implement(public.RenderComponentInstance, struct {
    pub fn init(
        allocator: std.mem.Allocator,
        data: []*anyopaque,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "RenderComponent - Init callback");
        defer zz.End();

        var containers = try cetech1.ArrayList(graphvm.GraphInstance).initCapacity(allocator, data.len);
        defer containers.deinit(allocator);
        try containers.resize(allocator, data.len);

        for (data, 0..) |d, idx| {
            const gi: *graphvm.GraphInstance = @ptrCast(@alignCast(d));
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
        var zz = _profiler.ZoneN(@src(), "RenderComponent - Culling callback");
        defer zz.End();

        var containers = try cetech1.ArrayList(graphvm.GraphInstance).initCapacity(allocator, transforms.len);
        defer containers.deinit(allocator);
        try containers.resize(allocator, if (entites_idx) |eidxs| eidxs.len else transforms.len);

        if (entites_idx) |idxs| {
            for (idxs, 0..) |ent_idx, idx| {
                const gi: *graphvm.GraphInstance = @ptrCast(@alignCast(data[ent_idx]));
                containers.items[idx] = gi.*;
            }
        } else {
            for (data, 0..) |d, idx| {
                const gi: *graphvm.GraphInstance = @ptrCast(@alignCast(d));
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

        const draw_calls = try _graphvm.getNodeState(
            renderer_nodes.DrawCall,
            allocator,
            containers.items,
            renderer_nodes.DRAW_CALL_NODE_TYPE,
        );
        defer allocator.free(draw_calls);

        switch (volume_type) {
            .sphere => {
                var sphere_out_volumes = std.mem.bytesAsSlice(render_viewport.SphereBoudingVolume, volumes);

                for (states, draw_calls, 0..) |volume, draw_call, idx| {
                    const dc_visibility_flags = if (draw_call) |dc| dc.visibility_mask else visibility_flags.VisibilityFlags.initEmpty();

                    if (volume) |v| {
                        if (v.hasSphere()) {
                            const tidx = if (entites_idx) |idxs| idxs[idx] else idx;
                            const mat = transforms[tidx].mtx;

                            const origin = zm.util.getTranslationVec(mat);
                            var center = [3]f32{ 0, 0, 0 };
                            zm.storeArr3(&center, origin);

                            sphere_out_volumes[idx] = .{
                                .center = center,
                                .radius = v.radius,
                                .visibility_mask = dc_visibility_flags,
                            };
                        } else {
                            sphere_out_volumes[idx] = .{ .visibility_mask = dc_visibility_flags, .skip_culling = true };
                        }
                    } else {
                        sphere_out_volumes[idx] = .{ .visibility_mask = dc_visibility_flags, .skip_culling = true };
                    }
                }
            },
            .box => {
                var box_out_volumes = std.mem.bytesAsSlice(render_viewport.BoxBoudingVolume, volumes);

                for (states, draw_calls, 0..) |volume, draw_call, idx| {
                    const dc_visibility_flags = if (draw_call) |dc| dc.visibility_mask else visibility_flags.VisibilityFlags.initEmpty();

                    if (volume) |v| {
                        const tidx = if (entites_idx) |idxs| idxs[idx] else idx;
                        const t = transforms[tidx];
                        if (v.hasBox()) {
                            box_out_volumes[idx] = .{
                                .t = t,
                                .min = v.min,
                                .max = v.max,
                                .visibility_mask = dc_visibility_flags,
                            };
                        } else {
                            box_out_volumes[idx] = .{ .visibility_mask = dc_visibility_flags, .skip_culling = true };
                        }
                    } else {
                        box_out_volumes[idx] = .{ .visibility_mask = dc_visibility_flags, .skip_culling = true };
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
        gpu_backend: gpu.GpuBackend,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: render_viewport.Viewport,
        viewers: []const render_graph.Viewer,
        system_context: *const shader_system.SystemContext,
        entites_idx: []const usize,
        transforms: []transform.WorldTransform,
        render_components: []*anyopaque,
        visibility: []const render_viewport.VisibilityBitField,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "RenderComponent - Render callback");
        defer zz.End();
        _ = world;
        _ = viewport;

        var containers = try cetech1.ArrayList(graphvm.GraphInstance).initCapacity(allocator, entites_idx.len);
        defer containers.deinit(allocator);
        try containers.resize(allocator, entites_idx.len);

        for (entites_idx, 0..) |ent_idx, idx| {
            const gi: *graphvm.GraphInstance = @ptrCast(@alignCast(render_components[ent_idx]));
            containers.items[idx] = gi.*;
        }

        const draw_calls = try _graphvm.executeNodeAndGetState(
            renderer_nodes.DrawCall,
            allocator,
            containers.items,
            renderer_nodes.DRAW_CALL_NODE_TYPE,
            .{},
        );
        defer allocator.free(draw_calls);

        // TODO: SHITy auto instances by drawcall hash
        // TODO: What about multiple cameras?

        const dup_ent_idx = try allocator.dupe(usize, entites_idx);
        defer allocator.free(dup_ent_idx);

        const hashes = try allocator.alloc(u64, draw_calls.len);
        defer allocator.free(hashes);

        {
            var zzz = _profiler.ZoneN(@src(), "RenderComponentTask - Update hashes");
            defer zzz.End();
            const update_hash_wih_task = true;
            if (update_hash_wih_task) {
                const ARGS = struct {
                    hashes: []u64,
                    draw_calls: []const ?*renderer_nodes.DrawCall,
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
                        .hashes = hashes,
                        .draw_calls = draw_calls,
                        .visibility = visibility,
                    },

                    struct {
                        pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) UpdateHashesTask {
                            return UpdateHashesTask{
                                .visibility = create_args.visibility[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                                .draw_calls = create_args.draw_calls[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                                .hashes = create_args.hashes[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                            };
                        }
                    },
                )) |t| {
                    _task.wait(t);
                }
            } else {
                for (draw_calls, 0..) |dc, idx| {
                    var h = std.hash.Fnv1a_64.init();
                    std.hash.autoHash(&h, dc.?.hash);
                    std.hash.autoHash(&h, visibility[idx].mask);
                    const final_hash = h.final();

                    hashes[idx] = final_hash;
                }
            }
        }

        {
            var zzz = _profiler.ZoneN(@src(), "RenderComponentTask - Sort drawcalls");
            defer zzz.End();

            var sort_ctx = SortDrawCallsContext{
                .drawcalls = draw_calls,
                .ent_idx = dup_ent_idx,
                .visibility = visibility,
                .hash = hashes,
            };
            std.sort.insertionContext(0, draw_calls.len, &sort_ctx);
        }

        const clusters = try clusterByDrawCall(allocator, draw_calls, hashes, 256);
        defer allocator.free(clusters);

        var contexts = try cetech1.StrId32List.initCapacity(allocator, visibility_flags.MAX_FLAGS);
        defer contexts.deinit(allocator);

        for (clusters) |cluster| {
            if (gpu_backend.getEncoder()) |e| {
                defer gpu_backend.endEncoder(e);

                var zzz = _profiler.ZoneN(@src(), "RenderComponentTask - Draw cluster");
                defer zzz.End();
                const draw_call_count: u32 = @truncate(cluster.calls.len);

                // Select first call for drawcall struct
                if (cluster.calls[0]) |dc| {
                    var mtxs = try allocator.alloc(transform.WorldTransform, draw_call_count);
                    defer allocator.free(mtxs);
                    for (0..draw_call_count) |idx| {
                        mtxs[idx] = transforms[dup_ent_idx[cluster.first_idx + idx]];
                    }
                    const inst_system = try _instance_system.createInstanceSystem(mtxs);
                    defer _instance_system.destroyInstanceSystem(inst_system);

                    var shader_context = try _shader_system.cloneSystemContext(system_context.*);
                    defer _shader_system.destroySystemContext(shader_context);

                    try shader_context.addSystem(inst_system.system, inst_system.uniforms, inst_system.resources);

                    if (dc.geometry) |gpu_geometry| {
                        try shader_context.addSystem(gpu_geometry.system, gpu_geometry.uniforms, gpu_geometry.resources);
                    }

                    // TODO: Set empty VB.. need this?
                    e.setVertexBuffer(0, gpu_backend.getNullVb(), 0, 0);
                    // e.setVertexCount(dc.vertex_count);

                    if (dc.index_buffer) |gpu_index_buffer| {
                        e.setIndexBuffer(gpu_index_buffer, 0, dc.index_count);
                    }

                    e.setInstanceCount(draw_call_count);

                    try submitDrawcall(
                        allocator,
                        e,
                        dc,
                        builder,
                        &shader_context,
                        cluster.first_idx,
                        viewers,
                        visibility,
                    );

                    //e.discard(.all);
                } else {
                    log.err("null draw call", .{});
                }
            }
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

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _shader_system = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _visibility_flags = apidb.getZigApi(module_name, visibility_flags.VisibilityFlagsApi).?;
    _instance_system = apidb.getZigApi(module_name, instance_system.InstanceSystemApi).?;

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
pub export fn ct_load_module_render_component(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
