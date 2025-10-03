const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

const public = @import("render_viewport.zig");
const culling = @import("culling.zig");

const transform = @import("transform");

const camera = @import("camera");
const shader_system = @import("shader_system");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const visibility_flags = @import("visibility_flags");

const module_name = .render_viewport;

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
var _visibility_flags: *const visibility_flags.VisibilityFlagsApi = undefined;
var _camera: *const camera.CameraAPI = undefined;

// Global state
const G = struct {
    viewport_set: ViewportSet = undefined,
    viewport_pool: ViewportPool = undefined,

    current_frame: u32 = 0,
};

var _g: *G = undefined;

const EnabledDebugDrawSet = cetech1.ArraySet(cetech1.StrId32);

const Viewport = struct {
    name: [:0]u8,

    output: gpu.TextureHandle = .{},
    size: [2]f32 = .{ 0, 0 },
    new_size: [2]f32 = .{ 0, 0 },

    world: ?ecs.World,
    main_camera_entity: ?ecs.EntityId = null,

    renderables_culling: culling.CullingSystem,
    shaderables_culling: culling.CullingSystem,

    renderMe: bool,

    render_pipeline: render_pipeline.RenderPipeline = undefined,

    graph_builder: render_graph.GraphBuilder = undefined,

    // Frame params
    frame_id: u64 = 0,

    // Stats
    all_shaderables_counter: *f64 = undefined,
    all_renderables_counter: *f64 = undefined,

    renderable_sphere_passed: *f64 = undefined,

    rendered_counter: *f64 = undefined,
    culling_collect_duration: *f64 = undefined,
    renderable_culling_duration: *f64 = undefined,
    render_duration: *f64 = undefined,

    shaderable_culling_duration: *f64 = undefined,
    shaderable_update_duration: *f64 = undefined,

    complete_render_duration: *f64 = undefined,

    viewports_count: *f64 = undefined,

    // DD
    enabled_dd_set: EnabledDebugDrawSet = undefined,

    fn init(name: [:0]const u8, world: ?ecs.World, camera_ent: ecs.EntityId) !Viewport {
        const dupe_name = try _allocator.dupeZ(u8, name);

        var buf: [128]u8 = undefined;

        return .{
            .name = dupe_name,
            .world = world,
            .main_camera_entity = camera_ent,
            .renderMe = false,
            .renderables_culling = culling.CullingSystem.init(_allocator, _profiler, _task),
            .shaderables_culling = culling.CullingSystem.init(_allocator, _profiler, _task),
            .graph_builder = try _render_graph.createBuilder(_allocator),

            .all_renderables_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_renerables", .{dupe_name})),
            .all_shaderables_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_shaderables", .{dupe_name})),
            .renderable_sphere_passed = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/renderable_sphere_passed", .{dupe_name})),
            .rendered_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/rendered", .{dupe_name})),

            .culling_collect_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_collect_duration", .{dupe_name})),
            .renderable_culling_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/renderable_culling_duration", .{dupe_name})),
            .render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/render_duration", .{dupe_name})),

            .shaderable_culling_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/shaderable_culling_duration", .{dupe_name})),
            .shaderable_update_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/shaderable_update_duration", .{dupe_name})),

            .complete_render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/complete_render_duration", .{dupe_name})),

            .viewports_count = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/viewports_count", .{dupe_name})),

            .enabled_dd_set = EnabledDebugDrawSet.init(),
        };
    }

    fn deinit(self: *Viewport) void {
        if (self.output.isValid()) {
            _gpu.destroyTexture(self.output);
        }

        self.shaderables_culling.deinit();
        self.renderables_culling.deinit();

        self.enabled_dd_set.deinit(_allocator);

        _allocator.free(self.name);

        _render_graph.destroyBuilder(self.graph_builder);
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

var viewport_visibility_flag_i = visibility_flags.VisibilityFlagI.implement(.{
    .name = "viewport",
    .uuid = cetech1.strId32("viewport").id,
    .default = true,
});

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
    const true_viewport: *Viewport = @ptrCast(@alignCast(viewport.ptr));
    _ = _g.viewport_set.swapRemove(true_viewport);
    true_viewport.deinit();
    _g.viewport_pool.destroy(true_viewport);
}

fn uiDebugMenuItems(allocator: std.mem.Allocator, viewport: public.Viewport) void {
    const true_viewport: *Viewport = @ptrCast(@alignCast(viewport.ptr));

    // if (_coreui.beginMenu(allocator, coreui.Icons.Debug ++ "  " ++ "Viewport", true, null)) {
    //     defer _coreui.endMenu();

    //
    // Components
    //
    if (_coreui.beginMenu(allocator, coreui.Icons.Debug ++ "  " ++ "Components", true, null)) {
        defer _coreui.endMenu();

        const impls = _apidb.getImpl(allocator, ecs.ComponentI) catch undefined;
        defer allocator.free(impls);

        for (impls) |iface| {
            if (iface.debugdraw) |_| {
                var icon_buff: [32:0]u8 = undefined;
                const icon = (iface.uiIcons.?(&icon_buff, allocator, .{}) catch undefined);

                var dd_enabled = true_viewport.enabled_dd_set.contains(iface.id);
                if (_coreui.menuItemPtr(
                    allocator,
                    std.fmt.allocPrintSentinel(allocator, "{s} {s}", .{ icon, iface.name }, 0) catch undefined,
                    .{ .selected = &dd_enabled },
                    null,
                )) {
                    if (dd_enabled) {
                        _ = true_viewport.enabled_dd_set.add(_allocator, iface.id) catch undefined;
                    } else {
                        _ = true_viewport.enabled_dd_set.remove(iface.id);
                    }
                }
            }
        }
    }

    //
    // Culling
    //
    if (_coreui.beginMenu(allocator, coreui.Icons.Debug ++ "  " ++ "Culling", true, null)) {
        defer _coreui.endMenu();

        var draw_culling_sphere_debug = true_viewport.renderables_culling.draw_culling_sphere_debug;
        if (_coreui.menuItemPtr(
            allocator,
            coreui.Icons.Debug ++ "  " ++ "Draw sphere",
            .{ .selected = &draw_culling_sphere_debug },
            null,
        )) {
            true_viewport.renderables_culling.draw_culling_sphere_debug = draw_culling_sphere_debug;
        }

        var draw_culling_box_debug = true_viewport.renderables_culling.draw_culling_box_debug;
        if (_coreui.menuItemPtr(
            allocator,
            coreui.Icons.Debug ++ "  " ++ "Draw box",
            .{ .selected = &draw_culling_box_debug },
            null,
        )) {
            true_viewport.renderables_culling.draw_culling_box_debug = draw_culling_box_debug;
        }
    }

    //
    // Render pipeline
    //
    if (_coreui.beginMenu(allocator, coreui.Icons.RenderPipeline ++ "  " ++ "Render pipeline", true, null)) {
        defer _coreui.endMenu();
        true_viewport.render_pipeline.uiDebugMenuItems(allocator);
    }
    // }
}

pub const api = public.RenderViewportApi{
    .createViewport = createViewport,
    .destroyViewport = destroyViewport,
    .uiDebugMenuItems = uiDebugMenuItems,
};

pub const viewport_vt = public.Viewport.VTable.implement(struct {
    pub fn setSize(viewport: *anyopaque, size: [2]f32) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.new_size[0] = @max(size[0], 1);
        true_viewport.new_size[1] = @max(size[1], 1);
    }

    pub fn getTexture(viewport: *anyopaque) ?gpu.TextureHandle {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));

        const txt = true_viewport.output;
        return if (txt.isValid()) txt else null;
    }

    pub fn getSize(viewport: *anyopaque) [2]f32 {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        return true_viewport.size;
    }

    pub fn requestRender(viewport: *anyopaque, pipeline: render_pipeline.RenderPipeline) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.renderMe = true;
        true_viewport.render_pipeline = pipeline;
    }

    pub fn setMainCamera(viewport: *anyopaque, camera_ent: ?ecs.EntityId) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.main_camera_entity = camera_ent;
    }

    pub fn getMainCamera(viewport: *anyopaque) ?ecs.EntityId {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        return true_viewport.main_camera_entity;
    }

    pub fn getDebugCulling(viewport: *anyopaque) bool {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        return true_viewport.renderables_culling.draw_culling_sphere_debug;
    }

    pub fn setDebugCulling(viewport: *anyopaque, enable: bool) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.renderables_culling.draw_culling_sphere_debug = enable;
        true_viewport.renderables_culling.draw_culling_box_debug = enable;
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

        self.viewport.frame_id %= 1;

        const allocator = try _tmpalloc.create();
        defer _tmpalloc.destroy(allocator);

        const render_module = self.viewport.render_pipeline.getMainModule();
        if (@intFromPtr(render_module.ptr) == 0) return;

        const viewport: *Viewport = self.viewport;

        const vp = public.Viewport{ .ptr = viewport, .vtable = &viewport_vt };

        var system_context = try _shader.createSystemContext();
        defer _shader.destroySystemContext(system_context);

        var culling_viewers = culling.ViewersList{};
        defer culling_viewers.deinit(allocator);

        var viewers = render_graph.ViewersList{};
        defer viewers.deinit(allocator);

        // Main viewer
        const fb_size = viewport.size;
        const aspect_ratio = fb_size[0] / fb_size[1];

        if (viewport.world) |world| {
            try viewport.render_pipeline.begin(&system_context, self.now_s);
            defer viewport.render_pipeline.end(&system_context) catch undefined;

            // Collect camera components
            {
                var q = try world.createQuery(&.{
                    .{ .id = ecs.id(transform.WorldTransform), .inout = .In },
                    .{ .id = ecs.id(camera.Camera), .inout = .In },
                });
                defer q.destroy();
                var it = try q.iter();

                while (q.next(&it)) {
                    const entities = it.entities();
                    const camera_transforms = it.field(transform.WorldTransform, 0).?;
                    const cameras = it.field(camera.Camera, 1).?;

                    for (0..camera_transforms.len) |idx| {
                        const pmtx = switch (cameras[idx].type) {
                            .perspective => _camera.perspectiveFov(
                                std.math.degreesToRadians(cameras[idx].fov),
                                aspect_ratio,
                                cameras[idx].near,
                                cameras[idx].far,
                            ),
                            .ortho => _camera.orthographic(
                                fb_size[0],
                                fb_size[1],
                                cameras[idx].near,
                                cameras[idx].far,
                            ),
                        };

                        const cv = culling.Viewer{
                            .camera = cameras[idx],
                            .mtx = zm.matToArr(zm.inverse(camera_transforms[idx].mtx)),
                            .proj = zm.matToArr(pmtx),
                            .visibility_mask = _visibility_flags.fromName(.fromStr("viewport")).?,
                        };

                        if (self.viewport.main_camera_entity != null and self.viewport.main_camera_entity.? == entities[idx]) {
                            try culling_viewers.insert(allocator, 0, cv);

                            // To struct
                            const system = _shader.findSystemByName(cetech1.strId32("viewer_system")).?;
                            const system_io = _shader.getSystemIO(system);
                            const system_uniform = (try _shader.createUniformBuffer(system_io)).?;

                            // const mtx = zm.matToArr(zm.inverse(camera_transforms[idx].mtx));

                            const pos = [4]f32{
                                camera_transforms[idx].mtx[3][0],
                                camera_transforms[idx].mtx[3][1],
                                camera_transforms[idx].mtx[3][2],
                                1,
                            };
                            // log.debug("{any}", .{pos});

                            try _shader.updateUniforms(
                                system_io,
                                system_uniform,
                                &.{.{ .name = cetech1.strId32("camera_pos"), .value = std.mem.asBytes(&pos) }},
                            );

                            const v = render_graph.Viewer{
                                .camera = cameras[idx],
                                .mtx = zm.matToArr(zm.inverse(camera_transforms[idx].mtx)),
                                .proj = zm.matToArr(pmtx),
                                .viewid = null,
                                .viewer_system = system,
                                .visibility_mask = _visibility_flags.fromName(.fromStr("viewport")).?,
                                .viewer_system_uniforms = system_uniform,
                            };
                            try viewers.insert(allocator, 0, v);
                        } else {
                            //try viewers.append(allocator, v);
                        }
                    }
                }
            }

            if (culling_viewers.items.len == 0) return;

            const graph_builder = self.viewport.graph_builder;
            try graph_builder.clear();

            var shaderables = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.ShaderableComponentI){};
            defer shaderables.deinit(allocator);
            // Inject main render graph module for shaderables and prepare culling
            {
                var z = _profiler.ZoneN(@src(), "Render viewport - Shedarables prepare");
                defer z.End();

                const impls = try _apidb.getImpl(allocator, public.ShaderableComponentI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    try shaderables.put(allocator, iface.component_id, iface);

                    if (iface.inject_graph_module) |inject_graph_module| {
                        try inject_graph_module(allocator, render_module);
                    }

                    const ci = _ecs.findComponentIById(iface.component_id).?;

                    var q = try world.createQuery(&.{
                        .{ .id = ecs.id(transform.WorldTransform), .inout = .In },
                        .{ .id = iface.component_id, .inout = .In },
                    });
                    defer q.destroy();
                    const c = q.count();

                    const rq = try viewport.shaderables_culling.getNewRequest(iface.component_id, @intCast(c.entities), ci.size);

                    var it = try q.iter();
                    var data_cnt: usize = 0;
                    while (q.next(&it)) {
                        const t = it.field(transform.WorldTransform, 0).?;
                        const rc = it.fieldRaw(ci.size, ci.aligment, 1).?;

                        // TODO: this or only copy like before? (poniter vs copy components).
                        for (0..t.len) |idx| {
                            rq.data.items[data_cnt + idx] = rc.ptr + (idx * ci.size);
                            // rq.data.items[data_cnt + idx] = std.mem.alignPointer(rc.ptr + (idx * ci.size), ci.aligment).?;
                        }

                        {
                            var zzz = _profiler.ZoneN(@src(), "Render viewport -  Shedarables init callback");
                            defer zzz.End();
                            if (iface.init) |init| {
                                try init(allocator, rq.data.items[data_cnt .. data_cnt + t.len]);
                            }
                        }

                        {
                            var zzz = _profiler.ZoneN(@src(), "Render viewport -  Shedarables fill sphere bounding box");
                            defer zzz.End();

                            rq.mtx.appendSliceAssumeCapacity(t);

                            try iface.fill_bounding_volumes(
                                allocator,
                                null,
                                t,
                                rq.data.items[data_cnt .. data_cnt + t.len],
                                .sphere,
                                std.mem.sliceAsBytes(rq.sphere_volumes.items[data_cnt .. data_cnt + t.len]),
                            );

                            data_cnt += t.len;
                        }
                    }

                    viewport.all_shaderables_counter.* += @floatFromInt(c.entities);
                }
            }

            // Culling shaderables
            {
                var z = _profiler.ZoneN(@src(), "Render viewport - Shaderables culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(viewport.shaderable_culling_duration);
                defer counter.end();

                // First culling phase
                _ = try viewport.shaderables_culling.doCullingSpheres(allocator, culling_viewers.items[0..1]);

                // Fill boxes
                for (shaderables.keys(), shaderables.values()) |renderable_id, shaderable| {
                    const rq = viewport.shaderables_culling.getRequest(renderable_id) orelse continue;
                    const result = viewport.shaderables_culling.getResult(renderable_id) orelse continue; // TODO: warning

                    try rq.box_volumes.ensureTotalCapacityPrecise(rq.allocator, result.sphere_entites_idx.items.len);
                    try rq.box_volumes.resize(rq.allocator, result.sphere_entites_idx.items.len);

                    if (result.sphere_entites_idx.items.len == 0) continue;

                    try shaderable.fill_bounding_volumes(
                        allocator,
                        result.sphere_entites_idx.items,
                        rq.mtx.items,
                        rq.data.items,
                        .box,
                        std.mem.sliceAsBytes(rq.box_volumes.items),
                    );
                }

                // Last box phase
                try viewport.shaderables_culling.doCullingBox(allocator, culling_viewers.items[0..1]);
            }

            // Update shaderable
            {
                var z = _profiler.ZoneN(@src(), "Render viewport - Shaderable update phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(viewport.shaderable_update_duration);
                defer counter.end();

                for (shaderables.keys(), shaderables.values()) |renderable_id, shaderable| {
                    var zz = _profiler.ZoneN(@src(), "Render viewport - Shaderable update callback");
                    defer zz.End();

                    const result = viewport.shaderables_culling.getResult(renderable_id) orelse continue; // TOOD: warning
                    const rq = viewport.shaderables_culling.getRequest(renderable_id) orelse continue;

                    //TODO: true_viewport.rendered_counter.* += @floatFromInt(result.mtx.len);

                    // if (result.visibleCount() > 0) {
                    try shaderable.update(
                        allocator,
                        graph_builder,
                        world,
                        vp,
                        self.viewport.render_pipeline,
                        viewers.items[0..1],
                        &system_context,
                        result.box_entites_idx.items,
                        rq.mtx.items,
                        rq.data.items,
                        std.mem.bytesAsSlice(public.VisibilityBitField, std.mem.sliceAsBytes(result.compact_visibility.items)), // TODO: maybe SHIT?
                    );
                    // }
                }
            }

            // Build and execute graph
            {
                var z = _profiler.ZoneN(@src(), "Render viewport - Build and execute render graph");
                defer z.End();

                try graph_builder.importTexture(public.ColorResource, viewport.output);

                try graph_builder.compile(allocator, render_module);
                try graph_builder.execute(allocator, fb_size, viewers.items);
            }

            // This contain all viewer for rendering (main camera + othes created from graph or components)
            const all_viewers = graph_builder.getViewers();
            viewport.viewports_count.* = @floatFromInt(all_viewers.len);

            var all_culling_viewers = try culling.ViewersList.initCapacity(allocator, all_viewers.len);
            defer all_culling_viewers.deinit(allocator);

            for (all_viewers) |v| {
                all_culling_viewers.appendAssumeCapacity(.{
                    .camera = v.camera,
                    .mtx = v.mtx,
                    .proj = v.proj,
                    .visibility_mask = v.visibility_mask,
                });
            }

            // Render renderables
            var renderables = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.RendereableComponentI){};
            defer renderables.deinit(allocator);

            {
                var zz = _profiler.ZoneN(@src(), "Render viewport - Culling renderables");
                defer zz.End();

                // Collect renderables to culling
                {
                    var z = _profiler.ZoneN(@src(), "Render viewport - Culling init phase");
                    defer z.End();

                    const counter = cetech1.metrics.MetricScopedDuration.begin(viewport.culling_collect_duration);
                    defer counter.end();

                    const impls = try _apidb.getImpl(allocator, public.RendereableComponentI);
                    defer allocator.free(impls);
                    for (impls) |renderable| {
                        try renderables.put(allocator, renderable.component_id, renderable);

                        const ci = _ecs.findComponentIById(renderable.component_id).?;

                        var q = try world.createQuery(&.{
                            .{ .id = ecs.id(transform.WorldTransform), .inout = .In },
                            .{ .id = renderable.component_id, .inout = .In },
                        });
                        defer q.destroy();
                        const c = q.count();

                        const rq = try viewport.renderables_culling.getNewRequest(renderable.component_id, @intCast(c.entities), ci.size);

                        var it = try q.iter();

                        var data_cnt: usize = 0;
                        while (q.next(&it)) {
                            const t = it.field(transform.WorldTransform, 0).?;
                            const rc = it.fieldRaw(ci.size, ci.aligment, 1).?;

                            // TODO: this or only copy like before? (poniter vs copy components).
                            for (0..t.len) |idx| {
                                rq.data.items[data_cnt + idx] = rc.ptr + (idx * ci.size);
                            }

                            if (renderable.init) |init| {
                                try init(allocator, rq.data.items[data_cnt .. data_cnt + t.len]);
                            }

                            {
                                var zzz = _profiler.ZoneN(@src(), "Render viewport - Fill sphere culling callback");
                                defer zzz.End();

                                rq.mtx.appendSliceAssumeCapacity(t);

                                try renderable.fill_bounding_volumes(
                                    allocator,
                                    null,
                                    t,
                                    rq.data.items[data_cnt .. data_cnt + t.len],
                                    .sphere,
                                    std.mem.sliceAsBytes(rq.sphere_volumes.items[data_cnt .. data_cnt + t.len]),
                                );

                                data_cnt += t.len;
                            }
                        }

                        viewport.all_renderables_counter.* += @floatFromInt(rq.mtx.items.len);
                    }
                }

                // Culling renderables
                {
                    var z = _profiler.ZoneN(@src(), "Render viewport - Culling phase");
                    defer z.End();

                    const counter = cetech1.metrics.MetricScopedDuration.begin(viewport.renderable_culling_duration);
                    defer counter.end();

                    // First culling phase
                    viewport.renderable_sphere_passed.* = @floatFromInt(try viewport.renderables_culling.doCullingSpheres(allocator, all_culling_viewers.items));

                    // Fill boxes
                    for (renderables.keys(), renderables.values()) |renderable_id, renderable| {
                        const rq = viewport.renderables_culling.getRequest(renderable_id) orelse continue;
                        const result = viewport.renderables_culling.getResult(renderable_id) orelse continue; // TODO: warning

                        try rq.box_volumes.ensureTotalCapacityPrecise(rq.allocator, result.sphere_entites_idx.items.len);
                        try rq.box_volumes.resize(rq.allocator, result.sphere_entites_idx.items.len);

                        if (result.sphere_entites_idx.items.len == 0) continue;

                        try renderable.fill_bounding_volumes(
                            allocator,
                            result.sphere_entites_idx.items,
                            rq.mtx.items,
                            rq.data.items,
                            .box,
                            std.mem.sliceAsBytes(rq.box_volumes.items),
                        );
                    }

                    // Last box phase
                    try viewport.renderables_culling.doCullingBox(allocator, all_culling_viewers.items);
                }
            }

            // Render renderables
            {
                var z = _profiler.ZoneN(@src(), "Render viewport - Render phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(viewport.render_duration);
                defer counter.end();

                for (renderables.keys(), renderables.values()) |renderable_id, renderable| {
                    var zz = _profiler.ZoneN(@src(), "Render viewport - Render callback");
                    defer zz.End();

                    const result = viewport.renderables_culling.getResult(renderable_id) orelse continue; // TODO: warning
                    const rq = viewport.renderables_culling.getRequest(renderable_id) orelse continue;

                    viewport.rendered_counter.* += @floatFromInt(result.visibleCount());

                    if (result.visibleCount() > 0) {
                        try renderable.render(
                            allocator,
                            graph_builder,
                            world,
                            vp,
                            all_viewers,
                            &system_context,
                            result.box_entites_idx.items,
                            rq.mtx.items,
                            rq.data.items,
                            std.mem.bytesAsSlice(public.VisibilityBitField, std.mem.sliceAsBytes(result.compact_visibility.items)), // TODO: maybe SHIT?
                        );
                    }
                }
            }

            // Debugdraw components
            {
                var z = _profiler.ZoneN(@src(), "Render viewport - Debugdraw pass");
                defer z.End();

                if (_gpu.getEncoder()) |e| {
                    defer _gpu.endEncoder(e);

                    const dd = _dd.encoderCreate();
                    defer _dd.encoderDestroy(dd);

                    dd.begin(graph_builder.getLayer("debugdraw"), true, e);
                    defer dd.end();

                    // Draw culling volumes
                    if (self.viewport.renderables_culling.draw_culling_sphere_debug) {
                        try self.viewport.shaderables_culling.debugdrawBoundingSpheres(dd);
                        try self.viewport.renderables_culling.debugdrawBoundingSpheres(dd);
                    }
                    if (self.viewport.renderables_culling.draw_culling_box_debug) {
                        try self.viewport.shaderables_culling.debugdrawBoundingBoxes(dd);
                        try self.viewport.renderables_culling.debugdrawBoundingBoxes(dd);
                    }

                    const impls = try _apidb.getImpl(allocator, ecs.ComponentI);
                    defer allocator.free(impls);
                    for (impls) |iface| {
                        if (iface.debugdraw) |debugdraw| {
                            if (!self.viewport.enabled_dd_set.contains(iface.id)) continue;

                            var q = try world.createQuery(&.{
                                .{ .id = iface.id, .inout = .In },
                            });
                            defer q.destroy();
                            var it = try q.iter();

                            while (q.next(&it)) {
                                const entities = it.entities();
                                const data = it.fieldRaw(iface.size, iface.aligment, 0).?;

                                try debugdraw(dd, world, entities, data, fb_size);
                            }
                        }
                    }
                }
            }

            for (all_viewers) |*value| {
                const io = _shader.getSystemIO(value.viewer_system);
                _shader.destroyUniformBuffer(io, value.viewer_system_uniforms);
            }

            _gpu.endAllUsedEncoders();
            _ = _gpu.frame(false);
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator, time_s: f32) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "RenderAllViewports");
    defer zone_ctx.End();

    var tasks = cetech1.task.TaskIdList{};
    defer tasks.deinit(allocator);

    for (_g.viewport_set.keys()) |viewport| {
        if (!viewport.renderMe) continue;
        viewport.renderMe = false;

        const recreate = viewport.new_size[0] != viewport.size[0] or viewport.new_size[1] != viewport.size[1];

        if (recreate) {
            if (viewport.output.isValid()) {
                _gpu.destroyTexture(viewport.output);
            }

            const txFlags: u64 = 0 |
                gpu.TextureFlags_Rt |
                gpu.TextureFlags_BlitDst;

            const t = _gpu.createTexture2D(
                @intFromFloat(viewport.new_size[0]),
                @intFromFloat(viewport.new_size[1]),
                false,
                1,
                gpu.TextureFormat.BGRA8,
                txFlags,
                null,
            );
            viewport.output = t;
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
    var zone_ctx = _profiler.ZoneN(@src(), "Render");
    defer zone_ctx.End();

    //
    // Render all viewports
    //
    const allocator = try _tmpalloc.create();
    defer _tmpalloc.destroy(allocator);
    try renderAllViewports(allocator, dt_accum);

    //
    // Render main viewport
    //

    // TODO: use viewport
    var flags = gpu.ResetFlags_None; // | gpu.ResetFlags_FlushAfterRender;

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

    try _coreui.draw(allocator, kernel_tick, dt);

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
    "RenderViewport",
    &[_]cetech1.StrId64{render_graph.RENDERER_GRAPH_KERNEL_TASK},
    struct {
        pub fn init() !void {
            _g.viewport_set = .{};
            _g.viewport_pool = ViewportPool.init(_allocator);
        }

        pub fn shutdown() !void {
            _g.viewport_set.deinit(_allocator);
            _g.viewport_pool.deinit();
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
    _visibility_flags = apidb.getZigApi(module_name, visibility_flags.VisibilityFlagsApi).?;
    _camera = apidb.getZigApi(module_name, camera.CameraAPI).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // register apis
    try apidb.setOrRemoveZigApi(module_name, public.RenderViewportApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &kernel_render_task, load);
    try apidb.implOrRemove(module_name, ecs.ComponentCategoryI, &renderer_ecs_category_i, load);

    try apidb.implOrRemove(module_name, visibility_flags.VisibilityFlagI, &viewport_visibility_flag_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_render_viewport(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
