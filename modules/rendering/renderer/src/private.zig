const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

const public = @import("renderer.zig");

const transform = @import("transform");

const camera = @import("camera");
const shader_system = @import("shader_system");
const render_graph = @import("render_graph");

const module_name = .renderer;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;

var _dd: *const gpu.GpuDDApi = undefined;
var _metrics: *const cetech1.metrics.MetricsAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;

var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;

// Global state
const G = struct {
    viewport_set: ViewportSet = undefined,
    viewport_pool: ViewportPool = undefined,

    time_system: shader_system.SystemInstance = undefined,

    current_frame: u32 = 0,
};

var _g: *G = undefined;

const FrustrumList = cetech1.ArrayList(cetech1.math.FrustrumPlanes);

const CullingSystem = struct {
    const Self = @This();

    const RequestPool = cetech1.heap.PoolWithLock(public.CullingRequest);
    const RequestMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *public.CullingRequest);

    const ResultPool = cetech1.heap.PoolWithLock(public.CullingResult);
    const ResultMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *public.CullingResult);

    allocator: std.mem.Allocator,

    crq_pool: RequestPool,
    request_map: RequestMap = .{},

    cr_pool: ResultPool,
    result_map: ResultMap = .{},

    tasks: cetech1.task.TaskIdList = .{},

    draw_culling_debug: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .crq_pool = RequestPool.init(allocator),
            .cr_pool = ResultPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.request_map.values()) |value| {
            value.deinit();
        }

        for (self.result_map.values()) |value| {
            value.deinit();
        }

        self.request_map.deinit(self.allocator);
        self.crq_pool.deinit();

        self.result_map.deinit(self.allocator);
        self.cr_pool.deinit();

        self.tasks.deinit(self.allocator);
    }

    pub fn getRequest(self: *Self, cullable_type: cetech1.StrId32, cullable_size: usize) !*public.CullingRequest {
        if (self.request_map.get(cullable_type)) |rq| {
            rq.clear();

            if (self.result_map.get(cullable_type)) |rs| {
                rs.clear();
            }

            return rq;
        }

        const rq = try self.crq_pool.create();
        rq.* = public.CullingRequest.init(self.allocator, cullable_size);
        try self.request_map.put(self.allocator, cullable_type, rq);

        const rs = try self.cr_pool.create();
        rs.* = public.CullingResult.init(self.allocator);
        try self.result_map.put(self.allocator, cullable_type, rs);

        return rq;
    }

    pub fn getResult(self: *Self, rq_type: cetech1.StrId32) *public.CullingResult {
        return self.result_map.get(rq_type).?;
    }

    pub fn doCulling(self: *Self, allocator: std.mem.Allocator, builder: render_graph.GraphBuilder, viewers: []const render_graph.Viewer) !void {
        // var zone = _profiler.ZoneN(@src(), "doCulling");
        // defer zone.End();
        var frustrums = try FrustrumList.initCapacity(allocator, viewers.len);
        defer frustrums.deinit(allocator);

        for (viewers) |v| {
            const mtx = zm.mul(zm.matFromArr(v.mtx), zm.matFromArr(v.proj));
            frustrums.appendAssumeCapacity(cetech1.math.buildFrustumPlanes(zm.matToArr(mtx)));
        }

        self.tasks.clearRetainingCapacity();

        for (self.request_map.keys(), self.request_map.values()) |k, value| {
            const result = self.getResult(k);

            const items_count = value.volumes.items.len;

            result.visibility.unsetAll();
            try result.visibility.resize(result.allocator, items_count * viewers.len, false);

            result.visibility_filtered.unsetAll();
            try result.visibility_filtered.resize(result.allocator, (items_count + value.no_cullables_data.items.len) * viewers.len, false);

            if (items_count == 0) continue;

            const ARGS = struct {
                rq: *public.CullingRequest,
                result: *public.CullingResult,
                frustrums: []const cetech1.math.FrustrumPlanes,
                builder: render_graph.GraphBuilder,
                viewers: []const render_graph.Viewer,
                draw_culling_debug: bool,
            };

            if (try cetech1.task.batchWorkloadTask(
                .{
                    .allocator = allocator,
                    .task_api = _task,
                    .profiler_api = _profiler,
                    .count = items_count,

                    // .batch_size = 128,
                    // .batch_size = 16,
                },
                ARGS{
                    .rq = value,
                    .result = result,
                    .frustrums = frustrums.items,
                    .builder = builder,
                    .viewers = viewers,
                    .draw_culling_debug = self.draw_culling_debug,
                },
                struct {
                    pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) CullingTask {
                        const rq = create_args.rq;

                        return CullingTask{
                            .count = count,
                            .visibility_offset = batch_id * args.batch_size * create_args.viewers.len,
                            .frustrums = create_args.frustrums,
                            .result = create_args.result,
                            .cullable_size = rq.cullable_size,
                            .builder = create_args.builder,
                            .draw_culling_debug = create_args.draw_culling_debug,

                            .transforms = rq.mtx.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                            .data = rq.data.items[batch_id * args.batch_size * rq.cullable_size .. ((batch_id * args.batch_size * rq.cullable_size) + count * rq.cullable_size)],
                            .volumes = rq.volumes.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                        };
                    }
                },
            )) |t| {
                try self.tasks.append(self.allocator, t);
            }
        }

        if (self.tasks.items.len != 0) {
            _task.waitMany(self.tasks.items);
        }

        // Filter results
        {
            var zone = _profiler.ZoneN(@src(), "CullingSystem - Filter results");
            defer zone.End();
            for (self.request_map.keys(), self.request_map.values()) |k, rq| {
                const result = self.getResult(k);

                for (rq.mtx.items, 0..) |mtx, culable_idx| {
                    var is_visible = false;

                    const i = result.mtx.items.len * viewers.len;
                    for (0..viewers.len) |idx| {
                        if (!result.visibility.isSet((culable_idx * viewers.len) + idx)) continue;
                        result.visibility_filtered.set(i + idx);
                        is_visible = true;
                    }

                    if (is_visible) {
                        try result.append(
                            mtx,
                            rq.data.items[culable_idx * rq.cullable_size .. (culable_idx * rq.cullable_size) + rq.cullable_size],
                        );
                    }
                }

                if (rq.no_cullables_mtx.items.len != 0) {
                    try result.appendMany(rq.no_cullables_mtx.items, rq.no_cullables_data.items);
                    result.visibility_filtered.setRangeValue(
                        .{
                            .start = result.mtx.items.len * viewers.len,
                            .end = result.visibility.bit_length,
                        },
                        true,
                    );
                }
            }
        }
    }
};

const Viewport = struct {
    name: [:0]u8,
    fb: gpu.FrameBufferHandle = .{},
    size: [2]f32 = .{ 0, 0 },
    new_size: [2]f32 = .{ 0, 0 },

    world: ?ecs.World,
    main_camera_entity: ?ecs.EntityId = null,

    renderables_culling: CullingSystem,
    shaderables_culling: CullingSystem,

    renderMe: bool,

    render_module: render_graph.Module = undefined,
    graph_builder: render_graph.GraphBuilder = undefined,

    // Stats
    all_renderables_counter: *f64 = undefined,
    rendered_counter: *f64 = undefined,
    culling_collect_duration: *f64 = undefined,
    culling_duration: *f64 = undefined,
    render_duration: *f64 = undefined,

    shaderable_culling_duration: *f64 = undefined,
    shaderable_update_duration: *f64 = undefined,

    complete_render_duration: *f64 = undefined,

    fn init(name: [:0]const u8, world: ?ecs.World, camera_ent: ecs.EntityId) !Viewport {
        const dupe_name = try _allocator.dupeZ(u8, name);

        var buf: [128]u8 = undefined;

        return .{
            .name = dupe_name,
            .world = world,
            .main_camera_entity = camera_ent,
            .renderMe = false,
            .renderables_culling = CullingSystem.init(_allocator),
            .shaderables_culling = CullingSystem.init(_allocator),
            .graph_builder = try _render_graph.createBuilder(_allocator),

            .all_renderables_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_renerables", .{dupe_name})),
            .rendered_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/rendered", .{dupe_name})),
            .culling_collect_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_collect_duration", .{dupe_name})),
            .culling_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_duration", .{dupe_name})),
            .render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/render_duration", .{dupe_name})),

            .shaderable_culling_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/shaderable_culling_duration", .{dupe_name})),
            .shaderable_update_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/shaderable_update_duration", .{dupe_name})),

            .complete_render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/complete_render_duration", .{dupe_name})),
        };
    }

    fn deinit(self: *Viewport) void {
        if (self.fb.isValid()) {
            _gpu.destroyFrameBuffer(self.fb);
        }

        self.shaderables_culling.deinit();
        self.renderables_culling.deinit();

        _allocator.free(self.name);

        _render_graph.destroyBuilder(self.graph_builder);
    }
};

const CullingTask = struct {
    count: usize,
    visibility_offset: usize,

    transforms: []const transform.WorldTransform,
    volumes: []const public.CullingVolume,
    data: []u8,

    cullable_size: usize,
    result: *public.CullingResult,
    frustrums: []const cetech1.math.FrustrumPlanes,

    builder: render_graph.GraphBuilder,
    draw_culling_debug: bool,

    pub fn exec(self: *@This()) !void {
        var zone = _profiler.ZoneN(@src(), "CullingTask");
        defer zone.End();

        if (_gpu.getEncoder()) |e| {
            defer _gpu.endEncoder(e);

            const dd = _dd.encoderCreate();
            defer _dd.encoderDestroy(dd);

            // TODO: Special layer for debug?
            dd.begin(self.builder.getLayer("color"), true, e);
            defer dd.end();

            // TODO : Faster (Culling in clip space? simd?)
            // TODO : Bounding box
            for (self.volumes, 0..) |volume, i| {
                if (volume.hasSphere()) {
                    var center = [3]f32{ 0, 0, 0 };
                    const mat = self.transforms[i].mtx;
                    const origin = zm.mul(zm.loadArr4(.{ 0, 0, 0, 1 }), mat);
                    zm.storeArr3(&center, origin);

                    for (self.frustrums, 0..) |frustrum, frustrum_idx| {
                        if (cetech1.math.frustumPlanesVsSphere(frustrum, center, volume.radius)) {
                            self.result.setVisibility(self.visibility_offset + (i * self.frustrums.len) + frustrum_idx);

                            if (self.draw_culling_debug and frustrum_idx == 0) {
                                var zzz = _profiler.ZoneN(@src(), "debugdraw");
                                defer zzz.End();

                                dd.pushTransform(@ptrCast(&mat));
                                defer dd.popTransform();

                                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);

                                if (volume.hasSphere()) {
                                    dd.drawCircleAxis(.X, .{ 0, 0, 0 }, volume.radius, 0);
                                    dd.drawCircleAxis(.Y, .{ 0, 0, 0 }, volume.radius, 0);
                                    dd.drawCircleAxis(.Z, .{ 0, 0, 0 }, volume.radius, 0);
                                }

                                if (volume.hasBox()) {
                                    dd.setWireframe(true);
                                    dd.drawAABB(volume.min, volume.max);
                                    dd.setWireframe(false);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
};

const ViewportPool = cetech1.heap.PoolWithLock(Viewport);
const ViewportSet = cetech1.AutoArrayHashMap(*Viewport, void);
const PalletColorMap = cetech1.AutoArrayHashMap(u32, u8);

var kernel_render_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "Render all viewports",
    &[_]cetech1.StrId64{},
    1,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            if (_kernel.getGpuCtx()) |ctx| {
                try renderAll(ctx, kernel_tick, dt, !_kernel.isHeadlessMode());
            }
        }
    },
);

fn createViewport(name: [:0]const u8, world: ?ecs.World, camera_ent: ecs.EntityId) !public.Viewport {
    const new_viewport = try _g.viewport_pool.create();
    new_viewport.* = try .init(name, world, camera_ent);

    try _g.viewport_set.put(_allocator, new_viewport, {});
    return public.Viewport{
        .ptr = new_viewport,
        .vtable = &viewport_vt,
    };
}

fn destroyViewport(viewport: public.Viewport) void {
    const true_viewport: *Viewport = @alignCast(@ptrCast(viewport.ptr));
    _ = _g.viewport_set.swapRemove(true_viewport);
    true_viewport.deinit();
    _g.viewport_pool.destroy(true_viewport);
}

fn uiDebugMenuItems(allocator: std.mem.Allocator, viewport: public.Viewport) void {
    var remote_active = viewport.getDebugCulling();

    if (_coreui.beginMenu(allocator, coreui.Icons.Debug ++ "  " ++ "Viewport", true, null)) {
        defer _coreui.endMenu();

        if (_coreui.menuItemPtr(
            allocator,
            coreui.Icons.Debug ++ "  " ++ "Draw culling volume",
            .{ .selected = &remote_active },
            null,
        )) {
            viewport.setDebugCulling(remote_active);
        }
    }
}

pub const api = public.RendererApi{
    .createViewport = createViewport,
    .destroyViewport = destroyViewport,
    .uiDebugMenuItems = uiDebugMenuItems,
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

        const txt = _gpu.getTexture(true_viewport.fb, 0);
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

    pub fn renderMe(viewport: *anyopaque, module: render_graph.Module) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.renderMe = true;
        true_viewport.render_module = module;
    }

    pub fn setMainCamera(viewport: *anyopaque, camera_ent: ?ecs.EntityId) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.main_camera_entity = camera_ent;
    }

    pub fn getMainCamera(viewport: *anyopaque) ?ecs.EntityId {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.main_camera_entity;
    }

    pub fn getDebugCulling(viewport: *anyopaque) bool {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.renderables_culling.draw_culling_debug;
    }
    pub fn setDebugCulling(viewport: *anyopaque, enable: bool) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.renderables_culling.draw_culling_debug = enable;
    }
});

const RenderViewportTask = struct {
    viewport: *Viewport,
    now_s: f32,
    pub fn exec(self: *@This()) !void {
        const complete_counter = cetech1.metrics.MetricScopedDuration.begin(self.viewport.complete_render_duration);
        defer complete_counter.end();

        var zone = _profiler.ZoneN(@src(), "RenderViewport");
        defer zone.End();

        const allocator = try _tmpalloc.create();
        defer _tmpalloc.destroy(allocator);

        const fb = self.viewport.fb;
        if (!fb.isValid()) return;

        const render_module = self.viewport.render_module;
        if (@intFromPtr(render_module.ptr) == 0) return;

        const vp = public.Viewport{ .ptr = self.viewport, .vtable = &viewport_vt };

        var viewers = render_graph.ViewersList{};
        defer viewers.deinit(allocator);

        // Main viewer
        const fb_size = self.viewport.size;
        const aspect_ratio = fb_size[0] / fb_size[1];

        const true_viewport: *Viewport = self.viewport;

        if (self.viewport.world) |world| {
            viewers.clearRetainingCapacity();

            // Collect camera components
            {
                var q = try world.createQuery(&.{
                    .{ .id = ecs.id(transform.WorldTransform), .inout = .In },
                    .{ .id = ecs.id(camera.Camera), .inout = .In },
                });
                var it = try q.iter();
                defer q.destroy();

                while (q.next(&it)) {
                    const entities = it.entities();
                    const camera_transforms = it.field(transform.WorldTransform, 0).?;
                    const cameras = it.field(camera.Camera, 1).?;
                    for (0..camera_transforms.len) |idx| {
                        const pmtx = switch (cameras[idx].type) {
                            .perspective => zm.perspectiveFovRh(
                                std.math.degreesToRadians(cameras[idx].fov),
                                aspect_ratio,
                                cameras[idx].near,
                                cameras[idx].far,
                            ),
                            .ortho => zm.orthographicRh(
                                fb_size[0],
                                fb_size[1],
                                cameras[idx].near,
                                cameras[idx].far,
                            ),
                        };

                        const v = render_graph.Viewer{
                            .camera = cameras[idx],
                            .mtx = zm.matToArr(zm.inverse(camera_transforms[idx].mtx)),
                            .proj = zm.matToArr(pmtx),
                            .context = cetech1.strId32("viewport"),
                        };

                        if (self.viewport.main_camera_entity != null and self.viewport.main_camera_entity.? == entities[idx]) {
                            try viewers.insert(allocator, 0, v);
                        } else {
                            try viewers.append(allocator, v);
                        }
                    }
                }
            }

            if (viewers.items.len == 0) return;

            const graph_builder = self.viewport.graph_builder;
            try graph_builder.reset();

            var shaderables = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.ShaderableI){};
            defer shaderables.deinit(allocator);

            // Inject main render graph module for shaderables and prepare culling
            {
                var z = _profiler.ZoneN(@src(), "Renderer - Shedarables inject render graph module");
                defer z.End();

                const impls = try _apidb.getImpl(allocator, public.ShaderableI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    try shaderables.put(allocator, iface.id, iface);

                    const cr = try true_viewport.shaderables_culling.getRequest(iface.id, iface.size);

                    if (iface.culling) |culling| {
                        var zz = _profiler.ZoneN(@src(), "Renderer - Shedarables culling calback");
                        defer zz.End();

                        _ = try culling(allocator, graph_builder, world, viewers.items, cr);
                    }

                    true_viewport.all_renderables_counter.* += @floatFromInt(cr.mtx.items.len);
                }
            }

            // Culling shaderables
            {
                var z = _profiler.ZoneN(@src(), "Renderer - Shaderables culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(true_viewport.shaderable_culling_duration);
                defer counter.end();

                try true_viewport.shaderables_culling.doCulling(allocator, graph_builder, viewers.items[0..1]);
            }

            // Update shaderable
            {
                var z = _profiler.ZoneN(@src(), "Renderer - Shaderable update phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(true_viewport.shaderable_update_duration);
                defer counter.end();

                var enabled_systems = shader_system.SystemSet.initEmpty();
                enabled_systems.set(_shader.getSystemIdx(cetech1.strId32("viewer_system")));
                enabled_systems.set(_shader.getSystemIdx(cetech1.strId32("time_system")));

                for (shaderables.keys(), shaderables.values()) |renderable_id, renderable| {
                    var zz = _profiler.ZoneN(@src(), "Renderer - Shaderable update calback");
                    defer zz.End();

                    const result = true_viewport.shaderables_culling.getResult(renderable_id);

                    true_viewport.rendered_counter.* += @floatFromInt(result.mtx.items.len);

                    if (result.data.items.len > 0) {
                        try renderable.update(
                            allocator,
                            graph_builder,
                            world,
                            vp,
                            viewers.items[0..1],
                            enabled_systems,
                            result,
                        );
                    }
                }
            }

            // Build and execute graph
            {
                const color_output = _gpu.getTexture(fb, 0);
                try graph_builder.importTexture(public.ViewportColorResource, color_output);

                try render_module.setupBuilder(graph_builder);

                try graph_builder.compile();
                try graph_builder.execute(fb_size, world, viewers.items);
            }

            // Render renderables

            var renderables = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.RendereableI){};
            defer renderables.deinit(allocator);

            // Collect renderables to culling
            {
                var z = _profiler.ZoneN(@src(), "Renderer - Culling collect phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(true_viewport.culling_collect_duration);
                defer counter.end();

                const impls = try _apidb.getImpl(allocator, public.RendereableI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    try renderables.put(allocator, iface.id, iface);

                    const cr = try true_viewport.renderables_culling.getRequest(iface.id, iface.size);

                    if (iface.culling) |culling| {
                        var zz = _profiler.ZoneN(@src(), "Renderer - Culling calback");
                        defer zz.End();

                        _ = try culling(allocator, graph_builder, world, viewers.items, cr);
                    }

                    true_viewport.all_renderables_counter.* += @floatFromInt(cr.mtx.items.len);
                }
            }

            const all_viewers = graph_builder.getViewers();
            // Culling renderables
            {
                var z = _profiler.ZoneN(@src(), "Renderer - Culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(true_viewport.culling_duration);
                defer counter.end();

                try true_viewport.renderables_culling.doCulling(allocator, graph_builder, all_viewers);
            }

            // Render renderables
            {
                var z = _profiler.ZoneN(@src(), "Renderer - Render phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(true_viewport.render_duration);
                defer counter.end();

                var enabled_systems = shader_system.SystemSet.initEmpty();
                enabled_systems.set(_shader.getSystemIdx(cetech1.strId32("viewer_system")));
                enabled_systems.set(_shader.getSystemIdx(cetech1.strId32("time_system")));

                for (renderables.keys(), renderables.values()) |renderable_id, renderable| {
                    var zz = _profiler.ZoneN(@src(), "Renderer - Render calback");
                    defer zz.End();

                    const result = true_viewport.renderables_culling.getResult(renderable_id);

                    true_viewport.rendered_counter.* += @floatFromInt(result.mtx.items.len);

                    if (result.data.items.len > 0) {
                        try renderable.render(
                            allocator,
                            graph_builder,
                            world,
                            vp,
                            all_viewers,
                            enabled_systems,
                            result,
                        );
                    }
                }
            }
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator, time_s: f32) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "renderAllViewports");
    defer zone_ctx.End();

    var tasks = cetech1.task.TaskIdList{};
    defer tasks.deinit(allocator);

    _gpu.resetViewId();

    // Submit Time system
    // TODO: move
    {
        const enc = _gpu.getEncoder().?;
        defer _gpu.endEncoder(enc);

        try _g.time_system.uniforms.?.set(cetech1.strId32("time"), [4]f32{ time_s, 0, 0, 0 });
        _shader.submitSystemUniforms(enc, _g.time_system);
    }

    for (_g.viewport_set.keys()) |viewport| {
        if (!viewport.renderMe) continue;
        viewport.renderMe = false;

        const recreate = viewport.new_size[0] != viewport.size[0] or viewport.new_size[1] != viewport.size[1];

        if (recreate) {
            if (viewport.fb.isValid()) {
                _gpu.destroyFrameBuffer(viewport.fb);
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

            const fb = _gpu.createFrameBuffer(
                @intFromFloat(viewport.new_size[0]),
                @intFromFloat(viewport.new_size[1]),
                gpu.TextureFormat.BGRA8,
                txFlags,
            );
            viewport.fb = fb;
            viewport.size = viewport.new_size;
        }

        if (true) {
            var render_task = RenderViewportTask{ .viewport = viewport, .now_s = time_s };
            try render_task.exec();
        } else {
            const task_id = try _task.schedule(
                cetech1.task.TaskID.none,
                RenderViewportTask{
                    .viewport = viewport,
                    .now_s = time_s,
                },
                .{},
            );
            try tasks.append(allocator, task_id);
        }
    }

    if (tasks.items.len != 0) {
        _task.waitMany(tasks.items);
    }
}

var old_fb_size = [2]i32{ -1, -1 };
var old_flags = gpu.ResetFlags_None;
var dt_accum: f32 = 0;
fn renderAll(ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) !void {
    _ = kernel_tick; // autofix
    var zone_ctx = _profiler.ZoneN(@src(), "Render");
    defer zone_ctx.End();

    // Render viewports
    const allocator = try _tmpalloc.create();
    defer _tmpalloc.destroy(allocator);
    try renderAllViewports(allocator, dt_accum);

    // Render main viewport
    // TODO: use viewport
    var flags = gpu.ResetFlags_None; //| gpu.ResetFlags_FlipAfterRender;

    var size = [2]i32{ 0, 0 };
    if (_gpu.getWindow(ctx)) |w| {
        size = w.getFramebufferSize();
    }

    if (vsync) {
        flags |= gpu.ResetFlags_Vsync;
    }

    if (old_flags != flags or old_fb_size[0] != size[0] or old_fb_size[1] != size[1]) {
        _gpu.reset(
            @intCast(size[0]),
            @intCast(size[1]),
            flags,
            _gpu.getResolution().format,
        );
        old_fb_size = size;
        old_flags = flags;
    }

    _gpu.setViewClear(0, gpu.ClearFlags_Color | gpu.ClearFlags_Depth, 0x303030ff, 1.0, 0);
    _gpu.setViewRectRatio(0, 0, 0, .Equal);

    {
        const encoder = _gpu.getEncoder().?;
        defer _gpu.endEncoder(encoder);
        encoder.touch(0);
    }
    _gpu.dbgTextClear(0, false);

    _gpu.endAllUsedEncoders();

    // TODO: save frameid for sync (sync across frames like read back frame + 2)
    {
        var frame_zone_ctx = _profiler.ZoneN(@src(), "frame");
        defer frame_zone_ctx.End();
        _g.current_frame = _gpu.frame(false);
    }

    dt_accum += dt;

    // TODO
    // profiler.ztracy.FrameImage( , width: u16, height: u16, offset: u8, flip: c_int);
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Renderer",
    &[_]cetech1.StrId64{render_graph.RENDERER_GRAPH_KERNEL_TASK},
    struct {
        pub fn init() !void {
            _g.viewport_set = .{};
            _g.viewport_pool = ViewportPool.init(_allocator);

            _g.time_system = try _shader.createSystemInstance(cetech1.strId32("time_system"));
        }

        pub fn shutdown() !void {
            _g.viewport_set.deinit(_allocator);
            _g.viewport_pool.deinit();

            _shader.destroySystemInstance(&_g.time_system);
        }
    },
);

//
const renderer_ecs_category_i = ecs.ComponentCategoryI.implement(.{ .name = "Renderer", .order = 20 });

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _metrics = apidb.getZigApi(module_name, cetech1.metrics.MetricsAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;

    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // register apis
    try apidb.setOrRemoveZigApi(module_name, public.RendererApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &kernel_render_task, load);
    try apidb.implOrRemove(module_name, ecs.ComponentCategoryI, &renderer_ecs_category_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_renderer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
