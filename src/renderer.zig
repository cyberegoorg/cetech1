const std = @import("std");

const builtin = @import("builtin");

const zbgfx = @import("zbgfx");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");
const gpu_private = @import("gpu.zig");
const graph_private = @import("graphvm.zig");
const ecs_private = @import("ecs.zig");
const assetdb_private = @import("assetdb.zig");
const metrics_private = @import("metrics.zig");

const gfx_rg_private = @import("render_graph.zig");

const cetech1 = @import("cetech1");
const public = cetech1.renderer;
const gpu = cetech1.gpu;
const gfx_dd = cetech1.debug_draw;
const gfx_rg = cetech1.render_graph;
const zm = cetech1.math;
const ecs = cetech1.ecs;
const transform = cetech1.transform;
const graphvm = cetech1.graphvm;
const primitives = cetech1.primitives;

const module_name = .viewport;
const log = std.log.scoped(module_name);

var _allocator: std.mem.Allocator = undefined;

const CullingRequestPool = cetech1.mem.PoolWithLock(public.CullingRequest);
const CullingRequestMap = std.AutoArrayHashMap(*const anyopaque, *public.CullingRequest);

const CullingResultPool = cetech1.mem.PoolWithLock(public.CullingResult);
const CullingResultMap = std.AutoArrayHashMap(*const anyopaque, *public.CullingResult);

const CullingSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    crq_pool: CullingRequestPool,
    crq_map: CullingRequestMap,

    cr_pool: CullingResultPool,
    cr_map: CullingResultMap,

    tasks: cetech1.task.TaskIDList,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .crq_pool = CullingRequestPool.init(allocator),
            .crq_map = CullingRequestMap.init(allocator),

            .cr_pool = CullingResultPool.init(allocator),
            .cr_map = CullingResultMap.init(allocator),

            .tasks = cetech1.task.TaskIDList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.crq_map.values()) |value| {
            value.deinit();
        }

        for (self.cr_map.values()) |value| {
            value.deinit();
        }

        self.crq_map.deinit();
        self.crq_pool.deinit();

        self.cr_map.deinit();
        self.cr_pool.deinit();

        self.tasks.deinit();
    }

    pub fn getRequest(self: *Self, rq_type: *const anyopaque, renderable_size: usize) !*public.CullingRequest {
        if (self.crq_map.get(rq_type)) |rq| {
            rq.clean();

            if (self.cr_map.get(rq_type)) |rs| {
                rs.clean();
            }

            return rq;
        }

        const rq = try self.crq_pool.create();
        rq.* = public.CullingRequest.init(self.allocator, renderable_size);
        try self.crq_map.put(rq_type, rq);

        const rs = try self.cr_pool.create();
        rs.* = public.CullingResult.init(self.allocator);
        try self.cr_map.put(rq_type, rs);

        return rq;
    }

    pub fn getResult(self: *Self, rq_type: *const anyopaque) *public.CullingResult {
        return self.cr_map.get(rq_type).?;
    }

    pub fn doCulling(self: *Self, viewers: []gfx_rg.Viewer) !void {
        const frustrum_planes = primitives.buildFrustumPlanes(viewers[0].mtx);

        for (self.crq_map.keys(), self.crq_map.values()) |k, value| {
            self.tasks.clearRetainingCapacity();

            const result = self.getResult(k);

            const items_count = value.mtx.items.len;

            if (items_count == 0) continue;

            const batch_size: usize = 64;
            const batch_count = @max(items_count / batch_size, 1);
            const batch_rest = items_count - (batch_count * batch_size);

            for (0..batch_count) |worker| {
                var worker_items = batch_size;
                if (worker == (batch_count - 1)) worker_items += batch_rest;

                const t = value.mtx.items[worker * batch_size .. (worker * batch_size) + worker_items];
                const cd = value.renderables.items[worker * batch_size * value.renderable_size .. ((worker * batch_size * value.renderable_size) + worker_items * value.renderable_size)];
                const v = value.volumes.items[worker * batch_size .. (worker * batch_size) + worker_items];

                const task_id = try task.api.schedule(
                    cetech1.task.TaskID.none,
                    CullingTask{
                        .count = worker_items,
                        .frustrum = &frustrum_planes,
                        .result = result,
                        .transforms = t,
                        .components_data = cd,
                        .volumes = v,
                        .rq = value,
                    },
                );
                try self.tasks.append(task_id);
            }
        }

        if (self.tasks.items.len != 0) {
            task.api.wait(try task.api.combine(self.tasks.items));
        }
    }
};

const Viewport = struct {
    name: [:0]u8,
    fb: gpu.FrameBufferHandle = .{},
    size: [2]f32 = .{ 0, 0 },
    new_size: [2]f32 = .{ 0, 0 },
    dd: gfx_dd.Encoder,
    rg: gfx_rg.RenderGraph,
    view_mtx: [16]f32,
    world: ?cetech1.ecs.World,
    culling: CullingSystem,

    // Stats
    all_renderables_counter: *f64 = undefined,
    rendered_counter: *f64 = undefined,
    culling_collect_duration: *f64 = undefined,
    culling_duration: *f64 = undefined,
    render_duration: *f64 = undefined,
    complete_render_duration: *f64 = undefined,
};

const query_onworld_i = ecs.OnWorldI.implement(struct {
    pub fn onCreate(world: ecs.World) !void {
        const q = try world.createQuery(&.{
            .{ .id = ecs.id(transform.WorldTransform), .inout = .In },
            .{ .id = ecs.id(public.RenderComponentInstance), .inout = .In },
        });
        try _world2query.put(world, q);
    }
    pub fn onDestroy(world: ecs.World) !void {
        var q = _world2query.get(world).?;
        q.destroy();
        _ = _world2query.swapRemove(world);
    }
});

const init_render_graph_system_i = ecs.SystemI.implement(
    .{
        .name = "init render component",
        .multi_threaded = false,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(public.RenderComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.RenderComponent), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *ecs.IterO) !void {
            var it = ecs_private.api.toIter(iter);

            const alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(alloc);

            const world = it.getWorld();
            const ents = it.entities();
            const render_component = it.field(public.RenderComponent, 1).?;

            const instances = try alloc.alloc(cetech1.graphvm.GraphInstance, render_component.len);
            defer alloc.free(instances);

            try graph_private.api.createInstances(alloc, assetdb_private.getDb(), render_component[0].graph, instances);
            try graph_private.api.buildInstances(alloc, instances);

            for (0..it.count()) |idx| {
                _ = world.setId(public.RenderComponentInstance, ents[idx], &public.RenderComponentInstance{ .graph_container = instances[idx] });
                try graph_private.api.setInstanceContext(instances[idx], ecs.ECS_WORLD_CONTEXT, world.ptr);
                try graph_private.api.setInstanceContext(instances[idx], ecs.ECS_ENTITY_CONTEXT, @ptrFromInt(ents[idx]));
            }

            world.deferSuspend();
            try graph_private.api.executeNode(alloc, instances, graphvm.EVENT_INIT_NODE_TYPE);
            world.deferResume();
        }
    },
);

const render_component_c = cetech1.ecs.ComponentI.implement(public.RenderComponent, struct {});

const rc_initialized_c = ecs.ComponentI.implement(public.RenderComponentInstance, struct {
    pub fn onDestroy(components: []public.RenderComponentInstance) !void {
        for (components) |c| {
            if (c.graph_container.isValid()) {
                graph_private.api.destroyInstance(c.graph_container);
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
        var it = ecs_private.api.toIter(iter);
        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);
        const components = it.field(public.RenderComponentInstance, 0).?;
        for (components) |component| {
            // TODO: real multi call
            try graph_private.api.executeNode(alloc, &.{component.graph_container}, graphvm.EVENT_SHUTDOWN_NODE_TYPE);
        }
    }
});

pub fn toContanerSlice(from: anytype) []const graphvm.GraphInstance {
    var containers: []const graphvm.GraphInstance = undefined;
    containers.ptr = @alignCast(@ptrCast(from.ptr));
    containers.len = from.len;
    return containers;
}

const CullingTask = struct {
    frustrum: *const primitives.FrustrumPlanes,
    count: usize,
    transforms: []const transform.WorldTransform,
    components_data: []u8,
    volumes: []const public.CullingVolume,
    rq: *public.CullingRequest,
    result: *public.CullingResult,

    pub fn exec(self: *@This()) !void {
        var zone = profiler.ztracy.ZoneN(@src(), "CullingTask");
        defer zone.End();

        const task_allocator = try tempalloc.api.create();
        defer tempalloc.api.destroy(task_allocator);

        for (self.volumes, 0..) |culling_volume, i| {
            if (culling_volume.radius > 0) {
                var center = [3]f32{ 0, 0, 0 };
                const mat = self.transforms[i].mtx;
                const origin = zm.mul(zm.loadArr4(.{ 0, 0, 0, 1 }), mat);
                zm.storeArr3(&center, origin);

                if (primitives.frustumPlanesVsSphere(self.frustrum.*, center, culling_volume.radius)) {
                    try self.result.append(self.transforms[i], self.components_data[i * self.rq.renderable_size .. i * self.rq.renderable_size + self.rq.renderable_size]);
                }
            }
        }
    }
};

const remder_component_renderer_i = cetech1.renderer.ComponentRendererI.implement(public.RenderComponentInstance, struct {
    pub fn culling(allocator: std.mem.Allocator, builder: gfx_rg.GraphBuilder, world: ecs.World, viewers: []gfx_rg.Viewer, rq: *public.CullingRequest) !void {
        _ = viewers; // autofix
        _ = builder;

        var q = _world2query.get(world).?;
        var it = try q.iter();

        var renderables = std.ArrayList(public.CullingVolume).init(allocator);
        defer renderables.deinit();

        while (q.next(&it)) {
            const transforms = it.field(transform.WorldTransform, 0).?;
            const render_components = it.field(public.RenderComponentInstance, 1).?;

            const containers = toContanerSlice(render_components);
            try graph_private.api.executeNode(allocator, containers, graphvm.CULLING_VOLUME_NODE_TYPE);

            const states = try graph_private.api.getNodeState(public.CullingVolume, allocator, containers, graphvm.CULLING_VOLUME_NODE_TYPE);
            defer allocator.free(states);

            if (states.len == 0) continue;

            renderables.clearRetainingCapacity();
            try renderables.ensureTotalCapacity(states.len);
            for (states) |volume| {
                const culling_volume: *public.CullingVolume = @alignCast(@ptrCast(volume));
                renderables.appendAssumeCapacity(culling_volume.*);
            }

            try rq.append(transforms, renderables.items, std.mem.sliceAsBytes(render_components));
        }
    }

    pub fn render(allocator: std.mem.Allocator, builder: gfx_rg.GraphBuilder, world: ecs.World, viewport: public.Viewport, culling_result: ?*public.CullingResult) !void {
        _ = world;

        const layer = builder.getLayer("color");
        if (gpu_private.gfx_api.getEncoder()) |e| {
            const dd = viewport.getDD();
            {
                dd.begin(layer, true, e);
                defer dd.end();

                if (culling_result) |result| {
                    var ci: []graphvm.GraphInstance = undefined;
                    ci.ptr = @alignCast(@ptrCast(result.renderables.items.ptr));
                    ci.len = result.renderables.items.len / @sizeOf(graphvm.GraphInstance);

                    const volumes = try graph_private.api.getNodeState(public.CullingVolume, allocator, ci, graphvm.CULLING_VOLUME_NODE_TYPE);
                    defer allocator.free(volumes);

                    for (volumes, result.mtx.items) |culling_volume, mtx| {
                        const draw_bounding_volumes = true;
                        const debug_draw = draw_bounding_volumes;
                        if (debug_draw) {
                            dd.pushTransform(@ptrCast(&mtx.mtx));
                            defer dd.popTransform();

                            dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);

                            if (draw_bounding_volumes) {
                                dd.drawSphere(.{ 0, 0, 0 }, culling_volume.radius);
                            }
                        }
                    }
                }
            }
        }
    }
});

const ViewportPool = cetech1.mem.PoolWithLock(Viewport);
const ViewportSet = std.AutoArrayHashMap(*Viewport, void);
const PalletColorMap = std.AutoArrayHashMap(u32, u8);

var _viewport_set: ViewportSet = undefined;
var _viewport_pool: ViewportPool = undefined;

const World2CullingQuery = std.AutoArrayHashMap(ecs.World, ecs.Query);
var _world2query: World2CullingQuery = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _viewport_set = ViewportSet.init(allocator);
    _viewport_pool = ViewportPool.init(allocator);

    _world2query = World2CullingQuery.init(allocator);

    try registerToApi();
}

pub fn deinit() void {
    _world2query.deinit();
    _viewport_set.deinit();
    _viewport_pool.deinit();
}

pub fn registerToApi() !void {
    _ = @alignOf(public.RenderComponentInstance);
    _ = @alignOf(public.RenderComponent);

    try apidb.api.setZigApi(module_name, public.RendererApi, &api);

    try apidb.api.implOrRemove(module_name, ecs.ComponentI, &render_component_c, true);
    try apidb.api.implOrRemove(module_name, ecs.ComponentI, &rc_initialized_c, true);

    try apidb.api.implOrRemove(module_name, ecs.SystemI, &init_render_graph_system_i, true);

    try apidb.api.implOrRemove(module_name, public.ComponentRendererI, &remder_component_renderer_i, true);
    try apidb.api.implOrRemove(module_name, ecs.OnWorldI, &query_onworld_i, true);
}

fn createViewport(name: [:0]const u8, render_graph: gfx_rg.RenderGraph, world: ?cetech1.ecs.World) !public.Viewport {
    const new_viewport = try _viewport_pool.create();

    const dupe_name = try _allocator.dupeZ(u8, name);

    var buf: [128]u8 = undefined;

    new_viewport.* = .{
        .name = dupe_name,
        .dd = gpu_private.gfx_dd_api.encoderCreate(),
        .rg = render_graph,
        .world = world,
        .view_mtx = zm.matToArr(zm.lookAtRh(
            zm.f32x4(0.0, 0.0, 0.0, 1.0),
            zm.f32x4(0.0, 0.0, 1.0, 1.0),
            zm.f32x4(0.0, 1.0, 0.0, 1.0),
        )),
        .culling = CullingSystem.init(_allocator),
        .all_renderables_counter = try metrics_private.api.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_renerables", .{dupe_name})),
        .rendered_counter = try metrics_private.api.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/rendered", .{dupe_name})),
        .culling_collect_duration = try metrics_private.api.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_collect_duration", .{dupe_name})),
        .culling_duration = try metrics_private.api.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_duration", .{dupe_name})),
        .render_duration = try metrics_private.api.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/render_duration", .{dupe_name})),
        .complete_render_duration = try metrics_private.api.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/complete_render_duration", .{dupe_name})),
    };

    try _viewport_set.put(new_viewport, {});
    return public.Viewport{
        .ptr = new_viewport,
        .vtable = &viewport_vt,
    };
}
fn destroyViewport(viewport: public.Viewport) void {
    const true_viewport: *Viewport = @alignCast(@ptrCast(viewport.ptr));
    _ = _viewport_set.swapRemove(true_viewport);

    if (true_viewport.fb.isValid()) {
        gpu_private.gfx_api.destroyFrameBuffer(true_viewport.fb);
    }

    true_viewport.culling.deinit();
    _allocator.free(true_viewport.name);

    gpu_private.gfx_dd_api.encoderDestroy(true_viewport.dd);
    _viewport_pool.destroy(true_viewport);
}

pub const api = public.RendererApi{
    .newViewId = newViewId,
    .createViewport = createViewport,
    .destroyViewport = destroyViewport,
    .renderAllViewports = renderAllViewports,
};

pub const viewport_vt = public.Viewport.VTable.implement(struct {
    pub fn setSize(viewport: *anyopaque, size: [2]f32) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.new_size[0] = @max(size[0], 1);
        true_viewport.new_size[1] = @max(size[1], 1);
    }

    pub fn getTexture(viewport: *anyopaque) ?gpu.TextureHandle {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        if (!true_viewport.fb.isValid()) return null;

        const txt = gpu_private.gfx_api.getTexture(true_viewport.fb, 0);
        return if (txt.isValid()) txt else null;
    }

    pub fn getFb(viewport: *anyopaque) ?gpu.FrameBufferHandle {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        if (!true_viewport.fb.isValid()) return null;
        return true_viewport.fb;
    }

    pub fn getSize(viewport: *anyopaque) [2]f32 {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.size;
    }

    pub fn getDD(viewport: *anyopaque) gfx_dd.Encoder {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.dd;
    }

    pub fn setViewMtx(viewport: *anyopaque, mtx: [16]f32) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.view_mtx = mtx;
    }
    pub fn getViewMtx(viewport: *anyopaque) [16]f32 {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.view_mtx;
    }
});

const AtomicViewId = std.atomic.Value(u16);
var view_id: AtomicViewId = AtomicViewId.init(1);
fn newViewId() gpu.ViewId {
    return view_id.fetchAdd(1, .monotonic);
}

fn resetViewId() void {
    view_id.store(1, .monotonic);
}

const RenderViewportTask = struct {
    viewport: *Viewport,
    pub fn exec(s: *@This()) !void {
        const complete_counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.complete_render_duration);
        defer complete_counter.end();

        var zone = profiler.ztracy.ZoneN(@src(), "RenderViewport");
        defer zone.End();

        const tmp_alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(tmp_alloc);

        const fb = s.viewport.fb;
        if (!fb.isValid()) return;

        const rg = s.viewport.rg;

        const vp = public.Viewport{ .ptr = s.viewport, .vtable = &viewport_vt };
        const builder = try rg.createBuilder(tmp_alloc, vp);
        defer rg.destroyBuilder(builder);

        {
            var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Render graph");
            defer z.End();

            const color_output = gpu_private.gfx_api.getTexture(fb, 0);
            try builder.importTexture(gfx_rg.ViewportColorResource, color_output);

            try rg.setupBuilder(builder);

            try builder.compile();
            try builder.execute(vp);
        }

        const Renderables = struct {
            iface: *const public.ComponentRendererI,
        };

        if (s.viewport.world) |world| {
            var renderables = std.ArrayList(Renderables).init(tmp_alloc);
            defer renderables.deinit();

            const viewers = builder.getViewers();

            // Collect  renderables to culling
            {
                var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Culling collect phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.culling_collect_duration);
                defer counter.end();

                const impls = try apidb.api.getImpl(tmp_alloc, cetech1.renderer.ComponentRendererI);
                defer tmp_alloc.free(impls);
                for (impls) |iface| {
                    const renderable = Renderables{ .iface = iface };

                    const cr = try s.viewport.culling.getRequest(iface, iface.size);

                    if (iface.culling) |culling| {
                        var zz = profiler.ztracy.ZoneN(@src(), "RenderViewport - Culling calback");
                        defer zz.End();

                        _ = try culling(tmp_alloc, builder, world, viewers, cr);
                    }
                    try renderables.append(renderable);

                    s.viewport.all_renderables_counter.* += @floatFromInt(cr.mtx.items.len);
                }
            }

            // Culling
            {
                var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.culling_duration);
                defer counter.end();

                try s.viewport.culling.doCulling(viewers);
            }

            // Render
            {
                var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Render phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.render_duration);
                defer counter.end();

                for (renderables.items) |renderable| {
                    var zz = profiler.ztracy.ZoneN(@src(), "RenderViewport - Render calback");
                    defer zz.End();

                    const result = s.viewport.culling.getResult(renderable.iface);

                    s.viewport.rendered_counter.* += @floatFromInt(result.mtx.items.len);

                    if (result.renderables.items.len > 0) {
                        try renderable.iface.render(tmp_alloc, builder, world, vp, result);
                    }
                }
            }
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.ztracy.ZoneN(@src(), "renderAllViewports");
    defer zone_ctx.End();

    var tasks = std.ArrayList(cetech1.task.TaskID).init(allocator);
    defer tasks.deinit();

    resetViewId();

    for (_viewport_set.keys()) |viewport| {
        const recreate = viewport.new_size[0] != viewport.size[0] or viewport.new_size[1] != viewport.size[1];

        if (recreate) {
            if (viewport.fb.isValid()) {
                gpu_private.gfx_api.destroyFrameBuffer(viewport.fb);
            }

            const txFlags: u64 = 0 |
                gpu.TextureFlags_Rt |
                gpu.TextureFlags_BlitDst |
                gpu.SamplerFlags_MinPoint |
                gpu.SamplerFlags_MagPoint |
                gpu.SamplerFlags_MipMask |
                gpu.SamplerFlags_MagPoint |
                gpu.SamplerFlags_MipPoint |
                gpu.SamplerFlags_UClamp |
                gpu.SamplerFlags_VClamp |
                gpu.SamplerFlags_MipPoint;

            const fb = gpu_private.gfx_api.createFrameBuffer(
                @intFromFloat(viewport.new_size[0]),
                @intFromFloat(viewport.new_size[1]),
                gpu.TextureFormat.BGRA8,
                txFlags,
            );
            viewport.fb = fb;
            viewport.size = viewport.new_size;
        }

        const task_id = try task.api.schedule(
            cetech1.task.TaskID.none,
            RenderViewportTask{
                .viewport = viewport,
            },
        );
        try tasks.append(task_id);
    }

    if (tasks.items.len != 0) {
        task.api.wait(try task.api.combine(tasks.items));
    }
}
