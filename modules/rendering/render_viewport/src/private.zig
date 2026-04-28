const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const math = cetech1.math;
const ecs = cetech1.ecs;
const gpu_dd = cetech1.gpu_dd;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;
const metrics = cetech1.metrics;
const apidb = cetech1.apidb;
const tempalloc = cetech1.tempalloc;
const task = cetech1.task;
const profiler = cetech1.profiler;

const kernel = cetech1.kernel;
const culling = @import("culling.zig");
const transform = @import("transform");
const camera = @import("camera");
const shader_system = @import("shader_system");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const visibility_flags = @import("visibility_flags");
const editor = @import("editor");

const public = @import("render_viewport.zig");

const module_name = .render_viewport;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _io: std.Io = undefined;

// Global state
const G = struct {
    viewport_set: ViewportSet = undefined,
    viewport_pool: ViewportPool = undefined,

    current_frame: u32 = 0,
};

var _g: *G = undefined;

const EnabledDebugDrawSet = cetech1.ArraySet(ecs.IdStrId);
const ComponentQueryMap = cetech1.AutoArrayHashMap(ecs.IdStrId, ecs.Query);

const Viewport = struct {
    name: [:0]u8,

    output: gpu.TextureHandle = .{},
    size: math.Vec2f = .{},
    new_size: math.Vec2f = .{},

    world: ?ecs.World,
    main_camera_entity: ?ecs.EntityId = null,
    main_camera_entity_freze_mtx: ?math.Mat44f = null,

    renderables_culling: culling.CullingSystem,
    shaderables_culling: culling.CullingSystem,

    renderMe: bool,

    render_pipeline: render_pipeline.RenderPipeline = undefined,
    graph_builder: render_graph.GraphBuilder = undefined,

    selected_entity: ?ecs.EntityId = null,

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

    gpu: gpu.GpuBackend,

    output_to_backbuffer: bool,

    // Queries
    query_map: ComponentQueryMap = .{},
    collect_camera_query: ecs.Query,

    fn init(name: [:0]const u8, gpu_backend: gpu.GpuBackend, pipeline: render_pipeline.RenderPipeline, world: ?ecs.World, output_to_backbuffer: bool) !Viewport {
        const dupe_name = try _allocator.dupeZ(u8, name);

        var buf: [128]u8 = undefined;

        var self = Viewport{
            .name = dupe_name,
            .world = world,
            .renderMe = false,
            .render_pipeline = pipeline,
            .renderables_culling = culling.CullingSystem.init(_allocator),
            .shaderables_culling = culling.CullingSystem.init(_allocator),
            .graph_builder = try render_graph.createBuilder(_allocator, gpu_backend),

            .all_renderables_counter = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_renerables", .{dupe_name})),
            .all_shaderables_counter = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_shaderables", .{dupe_name})),
            .renderable_sphere_passed = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/renderable_sphere_passed", .{dupe_name})),
            .rendered_counter = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/rendered", .{dupe_name})),

            .culling_collect_duration = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_collect_duration", .{dupe_name})),
            .renderable_culling_duration = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/renderable_culling_duration", .{dupe_name})),
            .render_duration = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/render_duration", .{dupe_name})),

            .shaderable_culling_duration = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/shaderable_culling_duration", .{dupe_name})),
            .shaderable_update_duration = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/shaderable_update_duration", .{dupe_name})),

            .complete_render_duration = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/complete_render_duration", .{dupe_name})),

            .viewports_count = try metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/viewports_count", .{dupe_name})),

            .enabled_dd_set = EnabledDebugDrawSet.empty,
            .gpu = gpu_backend,
            .output_to_backbuffer = output_to_backbuffer,
            .query_map = .{},

            .collect_camera_query = try world.?.createQuery(.{
                .query = &.{
                    .{ .id = ecs.id(transform.WorldTransformComponent), .inout = .In },
                    .{ .id = ecs.id(camera.Camera), .inout = .In },
                },
            }),
        };

        //
        // Shaderables queries
        //
        {
            const impls = try apidb.getImpl(_allocator, public.ShaderableComponentI);
            defer _allocator.free(impls);
            for (impls) |shaderable| {
                const q = try world.?.createQuery(.{
                    .query = &.{
                        .{ .id = ecs.id(transform.WorldTransformComponent), .inout = .In },
                        .{ .id = shaderable.component_id, .inout = .In },
                    },
                    .order_by_component = if (shaderable.orderByCallback != null) shaderable.component_id else null,
                    .order_by_callback = shaderable.orderByCallback,
                });

                try self.query_map.put(_allocator, shaderable.component_id, q);
            }
        }
        //
        // Renderables queries
        //
        {
            const impls = try apidb.getImpl(_allocator, public.RendereableComponentI);
            defer _allocator.free(impls);
            for (impls) |renderables| {
                const q = try world.?.createQuery(.{
                    .query = &.{
                        .{ .id = ecs.id(transform.WorldTransformComponent), .inout = .In },
                        .{ .id = renderables.component_id, .inout = .In },
                    },
                    .order_by_component = if (renderables.orderByCallback != null) renderables.component_id else null,
                    .order_by_callback = renderables.orderByCallback,
                });

                try self.query_map.put(_allocator, renderables.component_id, q);
            }
        }
        return self;
    }

    fn deinit(self: *Viewport) void {
        if (self.output.isValid()) {
            self.gpu.destroyTexture(self.output);
        }

        for (self.query_map.values()) |*query| {
            query.destroy();
        }
        self.query_map.deinit(_allocator);
        self.collect_camera_query.destroy();

        self.shaderables_culling.deinit();
        self.renderables_culling.deinit();

        self.enabled_dd_set.deinit(_allocator);

        _allocator.free(self.name);

        render_graph.destroyBuilder(self.graph_builder);
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
            if (kernel.getGpuBackend()) |ctx| {
                try renderAll(ctx, kernel_tick, dt, !kernel.isHeadlessMode());
            }
        }
    },
);

var viewport_visibility_flag_i = visibility_flags.VisibilityFlagI.implement(.{
    .name = "viewport",
    .uuid = cetech1.strId32("viewport").id,
    .default = true,
});

fn createViewport(name: [:0]const u8, gpu_backend: gpu.GpuBackend, pipeline: render_pipeline.RenderPipeline, world: ?ecs.World, output_to_backbuffer: bool) !public.Viewport {
    const new_viewport = try _g.viewport_pool.create(_io);
    new_viewport.* = try .init(name, gpu_backend, pipeline, world, output_to_backbuffer);

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    const impls = try apidb.getImpl(allocator, public.ShaderableComponentI);
    defer allocator.free(impls);
    for (impls) |iface| {
        if (iface.injectGraphModule) |injectGraphModule| {
            const manager = world.?.getComponentManagerRaw(iface.component_id);
            try injectGraphModule(allocator, manager, pipeline.getMainModule());
        }
    }

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
    _g.viewport_pool.destroy(_io, true_viewport);
}

fn uiDebugMenuItems(allocator: std.mem.Allocator, viewport: public.Viewport) !void {
    const true_viewport: *Viewport = @ptrCast(@alignCast(viewport.ptr));

    //
    // Components
    //
    if (coreui.beginMenu(allocator, coreui.Icons.Component ++ "  " ++ "Components", true, null)) {
        defer coreui.endMenu();

        const impls = apidb.getImpl(allocator, ecs.ComponentI) catch undefined;
        defer allocator.free(impls);

        const db = kernel.getDb();

        for (impls) |iface| {
            const aspect = if (!iface.cdb_type_hash.isEmpty()) cdb.getAspect(
                editor.EditorComponentAspect,
                db,
                cdb.getTypeIdx(db, iface.cdb_type_hash).?,
            ) else null;

            if (iface.debugdraw) |_| {
                var icon_buff: [32:0]u8 = undefined;
                const icon = blk: {
                    if (aspect) |a| {
                        if (a.uiIcons) |uiIcons| break :blk (uiIcons(&icon_buff, allocator, .{}) catch undefined);
                    }
                    break :blk "";
                };

                var dd_enabled = true_viewport.enabled_dd_set.contains(iface.id);
                if (coreui.menuItemPtr(
                    allocator,
                    std.fmt.allocPrintSentinel(allocator, "{s} {s}", .{ icon, iface.display_name }, 0) catch undefined,
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
    coreui.separatorText(coreui.Icons.Culling ++ " " ++ "Culling");
    {
        // if (coreui.beginMenu(allocator, coreui.Icons.Debug ++ "  " ++ "Culling", true, null)) {
        //     defer coreui.endMenu();

        var freeze_camera = true_viewport.main_camera_entity_freze_mtx != null;
        if (coreui.menuItemPtr(
            allocator,
            coreui.Icons.FreezeCamera ++ "  " ++ "Freeze camera",
            .{ .selected = &freeze_camera },
            null,
        )) {
            viewport.frezeMainCameraCulling(freeze_camera);
        }

        var draw_culling_sphere_debug = true_viewport.renderables_culling.draw_culling_sphere_debug;
        if (coreui.menuItemPtr(
            allocator,
            coreui.Icons.BoundingSphere ++ "  " ++ "Draw sphere",
            .{ .selected = &draw_culling_sphere_debug },
            null,
        )) {
            true_viewport.renderables_culling.draw_culling_sphere_debug = draw_culling_sphere_debug;
        }

        var draw_culling_box_debug = true_viewport.renderables_culling.draw_culling_box_debug;
        if (coreui.menuItemPtr(
            allocator,
            coreui.Icons.BoundingBox ++ "  " ++ "Draw box",
            .{ .selected = &draw_culling_box_debug },
            null,
        )) {
            true_viewport.renderables_culling.draw_culling_box_debug = draw_culling_box_debug;
        }
    }

    //
    // Render pipeline
    //
    coreui.separatorText(coreui.Icons.RenderPipeline ++ "  " ++ "Render pipeline");
    {
        try true_viewport.render_pipeline.uiDebugMenuItems(allocator);
    }
}

pub const api = public.RenderViewportApi{
    .createViewport = createViewport,
    .destroyViewport = destroyViewport,
    .uiDebugMenuItems = uiDebugMenuItems,
};

pub const viewport_vt = public.Viewport.VTable.implement(struct {
    pub fn setSize(viewport: *anyopaque, size: math.Vec2f) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.new_size.x = @max(size.x, 1);
        true_viewport.new_size.y = @max(size.y, 1);
    }

    pub fn getTexture(viewport: *anyopaque) ?gpu.TextureHandle {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));

        const txt = true_viewport.output;
        return if (txt.isValid()) txt else null;
    }

    pub fn getSize(viewport: *anyopaque) math.Vec2f {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        return true_viewport.size;
    }

    pub fn requestRender(viewport: *anyopaque) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.renderMe = true;
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

    pub fn setSelectedEntity(viewport: *anyopaque, entity: ?ecs.EntityId) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        true_viewport.selected_entity = entity;
    }

    pub fn frezeMainCameraCulling(viewport: *anyopaque, freeze: bool) void {
        const true_viewport: *Viewport = @ptrCast(@alignCast(viewport));
        if (freeze) {
            if (true_viewport.main_camera_entity) |camera_ent| {
                const world_transform = true_viewport.world.?.getComponent(transform.WorldTransformComponent, camera_ent).?;
                const ccamera = true_viewport.world.?.getComponent(camera.Camera, camera_ent).?;
                const proj = camera.projectionMatrixFromCamera(
                    ccamera.*,
                    true_viewport.size.x,
                    true_viewport.size.y,
                    true_viewport.gpu.isHomogenousDepth(),
                );

                true_viewport.main_camera_entity_freze_mtx = world_transform.world.inverse().toMat().mul(proj);
            }
        } else {
            true_viewport.main_camera_entity_freze_mtx = null;
        }
    }
});

const RenderViewportTask = struct {
    viewport: *Viewport,
    gpu: gpu.GpuBackend,
    now_s: f32,
    pub fn exec(self: *@This()) !void {
        const complete_counter = cetech1.metrics.MetricScopedDuration.begin(_io, self.viewport.complete_render_duration);
        defer complete_counter.end(_io);

        var zone = profiler.ZoneN(@src(), "RenderViewport");
        defer zone.End();

        self.viewport.frame_id %= 1;

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        const render_module = self.viewport.render_pipeline.getMainModule();
        if (@intFromPtr(render_module.ptr) == 0) return;

        const viewport: *Viewport = self.viewport;

        const vp = public.Viewport{ .ptr = viewport, .vtable = &viewport_vt };

        // Main viewer
        const fb_size = viewport.size;

        if (viewport.world) |world| {
            var system_context = try shader_system.createSystemContext();
            defer shader_system.destroySystemContext(system_context);

            var culling_viewers = culling.ViewersList.empty;
            defer culling_viewers.deinit(allocator);

            var viewers = render_graph.ViewersList.empty;
            defer viewers.deinit(allocator);

            try viewport.render_pipeline.begin(&system_context, self.now_s);
            defer viewport.render_pipeline.end(&system_context) catch undefined;

            // Collect camera components
            {
                var q = viewport.collect_camera_query;
                var it = try q.iter();

                while (q.next(&it)) {
                    const entities = it.entities();
                    const camera_transforms = it.field(transform.WorldTransformComponent, 0).?;
                    const cameras = it.field(camera.Camera, 1).?;

                    for (0..camera_transforms.len) |idx| {
                        const pmtx = camera.projectionMatrixFromCamera(
                            cameras[idx],
                            fb_size.x,
                            fb_size.y,
                            self.gpu.isHomogenousDepth(),
                        );

                        const cv = culling.Viewer{
                            .frustum = .fromMat44(camera_transforms[idx].world.inverse().toMat().mul(pmtx)),
                            .visibility_mask = visibility_flags.fromName(.fromStr("viewport")).?,
                        };

                        if (self.viewport.main_camera_entity != null and self.viewport.main_camera_entity.? == entities[idx]) {
                            try culling_viewers.insert(allocator, 0, cv);

                            // To struct
                            const system = shader_system.findSystemByName(.fromStr("viewer_system")).?;
                            const system_io = shader_system.getSystemIO(system);
                            const system_uniform = (try shader_system.createUniformBuffer(system_io)).?;

                            const pos = [4]f32{
                                camera_transforms[idx].world.position.x,
                                camera_transforms[idx].world.position.y,
                                camera_transforms[idx].world.position.z,
                                1,
                            };
                            // log.debug("{any}", .{pos});

                            try shader_system.updateUniforms(
                                system_io,
                                system_uniform,
                                &.{.{ .name = .fromStr("camera_pos"), .value = std.mem.asBytes(&pos) }},
                            );

                            const v = render_graph.Viewer{
                                .camera = cameras[idx],
                                .mtx = camera_transforms[idx].world.inverse().toMat(),
                                .proj = pmtx,
                                .viewid = null,
                                .viewer_system = system,
                                .visibility_mask = visibility_flags.fromName(.fromStr("viewport")).?,
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

            if (viewport.main_camera_entity_freze_mtx) |mtx| {
                culling_viewers.items[0].frustum = .fromMat44(mtx);
            }

            const graph_builder = self.viewport.graph_builder;
            try graph_builder.clear();

            var shaderables = cetech1.AutoArrayHashMap(ecs.IdStrId, *const public.ShaderableComponentI).empty;
            defer shaderables.deinit(allocator);
            // Inject main render graph module for shaderables and prepare culling
            {
                var z = profiler.ZoneN(@src(), "Render viewport - Shedarables prepare");
                defer z.End();

                const impls = try apidb.getImpl(allocator, public.ShaderableComponentI);
                defer allocator.free(impls);
                for (impls) |shaderable| {
                    try shaderables.put(allocator, shaderable.component_id, shaderable);

                    const ci = ecs.findComponentIById(shaderable.component_id).?;

                    var q = viewport.query_map.get(shaderable.component_id).?;
                    const c = q.count();

                    const rq = try viewport.shaderables_culling.getNewRequest(
                        _io,
                        shaderable.component_id,
                        @intCast(c.entities),
                        ci.size,
                    );

                    var it = try q.iter();
                    var data_cnt: usize = 0;
                    while (q.next(&it)) {
                        const transforms = it.field(transform.WorldTransformComponent, 0).?;
                        const components = it.fieldRaw(ci.size, ci.aligment, 1).?;

                        // TODO: this or only copy like before? (poniter vs copy components).
                        for (0..transforms.len) |idx| {
                            rq.data.items[data_cnt + idx] = components.ptr + (idx * ci.size);
                            // rq.data.items[data_cnt + idx] = std.mem.alignPointer(rc.ptr + (idx * ci.size), ci.aligment).?;
                        }

                        data_cnt += transforms.len;
                        rq.mtx.appendSliceAssumeCapacity(transforms);
                    }

                    {
                        var zzz = profiler.ZoneN(@src(), "Render viewport -  Shedarables init callback");
                        defer zzz.End();
                        if (shaderable.init) |init| {
                            try init(allocator, rq.data.items);
                        }
                    }

                    {
                        var zzz = profiler.ZoneN(@src(), "Render viewport -  Shedarables fill sphere bounding box");
                        defer zzz.End();

                        try shaderable.fillBoundingVolumes(
                            allocator,
                            null,
                            rq.mtx.items,
                            rq.data.items,
                            .sphere,
                            std.mem.sliceAsBytes(rq.sphere_volumes.items),
                        );
                    }

                    viewport.all_shaderables_counter.* += @floatFromInt(c.entities);
                }
            }

            // Culling shaderables
            {
                var z = profiler.ZoneN(@src(), "Render viewport - Shaderables culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(_io, viewport.shaderable_culling_duration);
                defer counter.end(_io);

                // First culling phase
                _ = try viewport.shaderables_culling.doCullingSpheres(
                    allocator,
                    culling_viewers.items[0..1],
                );

                // Fill boxes
                for (shaderables.keys(), shaderables.values()) |renderable_id, shaderable| {
                    const rq = viewport.shaderables_culling.getRequest(renderable_id) orelse continue;
                    const result = viewport.shaderables_culling.getResult(renderable_id) orelse continue; // TODO: warning

                    try rq.box_volumes.ensureTotalCapacityPrecise(rq.allocator, result.sphere_entites_idx.items.len);
                    try rq.box_volumes.resize(rq.allocator, result.sphere_entites_idx.items.len);

                    if (result.sphere_entites_idx.items.len == 0) continue;

                    try shaderable.fillBoundingVolumes(
                        allocator,
                        result.sphere_entites_idx.items,
                        rq.mtx.items,
                        rq.data.items,
                        .box,
                        std.mem.sliceAsBytes(rq.box_volumes.items),
                    );
                }

                // Last box phase
                try viewport.shaderables_culling.doCullingBox(
                    allocator,
                    culling_viewers.items[0..1],
                );
            }

            // Update shaderable
            {
                var z = profiler.ZoneN(@src(), "Render viewport - Shaderable update phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(_io, viewport.shaderable_update_duration);
                defer counter.end(_io);

                for (shaderables.keys(), shaderables.values()) |renderable_id, shaderable| {
                    var zz = profiler.ZoneN(@src(), "Render viewport - Shaderable update callback");
                    defer zz.End();

                    const result = viewport.shaderables_culling.getResult(renderable_id) orelse continue; // TOOD: warning
                    const rq = viewport.shaderables_culling.getRequest(renderable_id) orelse continue;

                    //TODO: true_viewport.rendered_counter.* += @floatFromInt(result.mtx.len);

                    // if (result.visibleCount() > 0) {
                    try shaderable.update(
                        allocator,
                        self.gpu,
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
                var z = profiler.ZoneN(@src(), "Render viewport - Build and execute render graph");
                defer z.End();

                try graph_builder.importTexture(public.ColorResource, viewport.output);
                try graph_builder.compile(allocator, render_module);
                try graph_builder.execute(allocator, fb_size, viewers.items, null);
            }

            // This contain all viewer for rendering (main camera + othes created from graph or components)
            const all_viewers = graph_builder.getViewers();
            viewport.viewports_count.* = @floatFromInt(all_viewers.len);

            var all_culling_viewers = try culling.ViewersList.initCapacity(allocator, all_viewers.len);
            defer all_culling_viewers.deinit(allocator);

            for (all_viewers) |*v| {
                all_culling_viewers.appendAssumeCapacity(.{
                    .frustum = .fromMat44(v.mtx.mul(v.proj)),
                    .visibility_mask = v.visibility_mask,
                });
            }

            if (viewport.main_camera_entity_freze_mtx) |mtx| {
                all_culling_viewers.items[0].frustum = .fromMat44(mtx);
            }

            // Render renderables
            var renderables = cetech1.AutoArrayHashMap(ecs.IdStrId, *const public.RendereableComponentI).empty;
            defer renderables.deinit(allocator);

            {
                var zz = profiler.ZoneN(@src(), "Render viewport - Culling renderables");
                defer zz.End();

                // Collect renderables to culling
                {
                    var z = profiler.ZoneN(@src(), "Render viewport - Culling init phase");
                    defer z.End();

                    const counter = cetech1.metrics.MetricScopedDuration.begin(_io, viewport.culling_collect_duration);
                    defer counter.end(_io);

                    const impls = try apidb.getImpl(allocator, public.RendereableComponentI);
                    defer allocator.free(impls);
                    for (impls) |renderable| {
                        try renderables.put(allocator, renderable.component_id, renderable);

                        const ci = ecs.findComponentIById(renderable.component_id).?;

                        var q = viewport.query_map.get(renderable.component_id).?;
                        const c = q.count();

                        const rq = try viewport.renderables_culling.getNewRequest(
                            _io,
                            renderable.component_id,
                            @intCast(c.entities),
                            ci.size,
                        );

                        var it = try q.iter();

                        var data_cnt: usize = 0;
                        while (q.next(&it)) {
                            const t = it.field(transform.WorldTransformComponent, 0).?;
                            const rc = it.fieldRaw(ci.size, ci.aligment, 1).?;

                            // TODO: this or only copy like before? (poniter vs copy components).
                            for (0..t.len) |idx| {
                                rq.data.items[data_cnt + idx] = rc.ptr + (idx * ci.size);
                            }

                            rq.mtx.appendSliceAssumeCapacity(t);
                            data_cnt += t.len;
                        }
                        viewport.all_renderables_counter.* += @floatFromInt(rq.mtx.items.len);

                        //if (data_cnt == 0) continue;

                        if (renderable.init) |init| {
                            try init(allocator, rq.data.items);
                        }

                        {
                            var zzz = profiler.ZoneN(@src(), "Render viewport - Fill sphere culling callback");
                            defer zzz.End();

                            try renderable.fillBoundingVolumes(
                                allocator,
                                null,
                                rq.mtx.items,
                                rq.data.items,
                                .sphere,
                                std.mem.sliceAsBytes(rq.sphere_volumes.items),
                            );
                        }
                    }
                }

                // Culling renderables
                {
                    var z = profiler.ZoneN(@src(), "Render viewport - Culling phase");
                    defer z.End();

                    const counter = cetech1.metrics.MetricScopedDuration.begin(_io, viewport.renderable_culling_duration);
                    defer counter.end(_io);

                    // First culling phase
                    const passed_spheres = try viewport.renderables_culling.doCullingSpheres(
                        allocator,
                        all_culling_viewers.items,
                    );
                    viewport.renderable_sphere_passed.* = @floatFromInt(passed_spheres);

                    // Fill boxes
                    for (renderables.keys(), renderables.values()) |renderable_id, renderable| {
                        const rq = viewport.renderables_culling.getRequest(renderable_id) orelse continue;
                        const result = viewport.renderables_culling.getResult(renderable_id) orelse continue; // TODO: warning

                        try rq.box_volumes.ensureTotalCapacityPrecise(rq.allocator, result.sphere_entites_idx.items.len);
                        try rq.box_volumes.resize(rq.allocator, result.sphere_entites_idx.items.len);

                        if (result.sphere_entites_idx.items.len == 0) continue;

                        try renderable.fillBoundingVolumes(
                            allocator,
                            result.sphere_entites_idx.items,
                            rq.mtx.items,
                            rq.data.items,
                            .box,
                            std.mem.sliceAsBytes(rq.box_volumes.items),
                        );
                    }

                    // Last box phase
                    try viewport.renderables_culling.doCullingBox(
                        allocator,
                        all_culling_viewers.items,
                    );
                }
            }

            // Render renderables
            {
                var z = profiler.ZoneN(@src(), "Render viewport - Render phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(_io, viewport.render_duration);
                defer counter.end(_io);

                for (renderables.keys(), renderables.values()) |renderable_id, renderable| {
                    var zz = profiler.ZoneN(@src(), "Render viewport - Render callback");
                    defer zz.End();

                    const result = viewport.renderables_culling.getResult(renderable_id) orelse continue; // TODO: warning
                    const rq = viewport.renderables_culling.getRequest(renderable_id) orelse continue;

                    viewport.rendered_counter.* += @floatFromInt(result.visibleCount());

                    if (result.visibleCount() > 0) {
                        try renderable.render(
                            allocator,
                            self.gpu,
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
                var z = profiler.ZoneN(@src(), "Render viewport - Debugdraw pass");
                defer z.End();

                if (self.gpu.getEncoder()) |e| {
                    defer self.gpu.endEncoder(e);

                    const dd = gpu_dd.encoderCreate();
                    defer gpu_dd.encoderDestroy(dd);

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

                    const impls = try apidb.getImpl(allocator, ecs.ComponentI);
                    defer allocator.free(impls);
                    for (impls) |iface| {
                        if (iface.debugdraw) |debugdraw| {
                            if (self.viewport.enabled_dd_set.contains(iface.id)) {
                                var q = try world.createQuery(.{
                                    .query = &.{
                                        .{ .id = iface.id, .inout = .In },
                                    },
                                });
                                defer q.destroy();
                                var it = try q.iter();

                                while (q.next(&it)) {
                                    const entities = it.entities();
                                    const data = it.fieldRaw(iface.size, iface.aligment, 0).?;

                                    try debugdraw(self.gpu, dd, world, entities, data, fb_size);
                                }
                            } else if (viewport.selected_entity) |selected_entity| {
                                if (viewport.world.?.getComponentRaw(iface.id, selected_entity)) |data| {
                                    var d: []const u8 = undefined;
                                    d.ptr = @ptrCast(data);
                                    d.len = iface.size;

                                    try debugdraw(self.gpu, dd, world, &.{selected_entity}, d, fb_size);
                                }
                            }
                        }
                    }

                    if (viewport.main_camera_entity_freze_mtx) |mtx| {
                        dd.drawFrustum(mtx);
                    }
                }
            }

            for (all_viewers) |*value| {
                const io = shader_system.getSystemIO(value.viewer_system);
                shader_system.destroyUniformBuffer(io, value.viewer_system_uniforms);
            }

            self.gpu.endAllUsedEncoders();
            _ = self.gpu.frame(.{});
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, time_s: f32) !void {
    var zone_ctx = profiler.ZoneN(@src(), "RenderAllViewports");
    defer zone_ctx.End();

    var tasks = cetech1.task.TaskIdList.empty;
    defer tasks.deinit(allocator);

    for (_g.viewport_set.keys()) |viewport| {
        if (!viewport.renderMe) continue;
        viewport.renderMe = false;

        const recreate = viewport.new_size.x != viewport.size.x or viewport.new_size.y != viewport.size.y;

        if (recreate) {
            if (viewport.output.isValid()) {
                gpu_backend.destroyTexture(viewport.output);
            }

            const t = gpu_backend.createTexture2D(
                @intFromFloat(viewport.new_size.x),
                @intFromFloat(viewport.new_size.y),
                false,
                1,
                gpu.TextureFormat.BGRA8,
                .{
                    .blit_dst = true,
                    .rt = .RT,
                },
                null,
                null,
                0,
            );
            viewport.output = t;
            viewport.size = viewport.new_size;
        }

        var t = RenderViewportTask{ .viewport = viewport, .gpu = gpu_backend, .now_s = time_s };
        if (true) {
            try t.exec();
        } else {
            const task_id = try task.schedule(cetech1.task.TaskID.none, t, .{});
            try tasks.append(allocator, task_id);
        }
    }

    if (tasks.items.len != 0) {
        task.waitMany(tasks.items);
    }
}

var old_fb_size = [2]i32{ -1, -1 };
var old_flags = gpu.ResetFlags{};
var dt_accum: f32 = 0;
fn renderAll(gpu_backend: gpu.GpuBackend, kernel_tick: u64, dt: f32, vsync: bool) !void {
    var zone_ctx = profiler.ZoneN(@src(), "Render");
    defer zone_ctx.End();

    // _ = kernel_tick;

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    //
    // Render main viewport
    //

    var size = [2]i32{ 0, 0 };
    if (gpu_backend.getWindow()) |w| {
        size = w.getFramebufferSize();
    }

    var flags = gpu.ResetFlags{};
    flags.vsync = vsync;

    if (!std.meta.eql(old_flags, flags) or old_fb_size[0] != size[0] or old_fb_size[1] != size[1]) {
        gpu_backend.reset(
            @intCast(size[0]),
            @intCast(size[1]),
            flags,
            gpu_backend.getResolution().formatColor,
        );
        old_fb_size = size;
        old_flags = flags;
    }

    //
    // Render all viewports
    //
    try renderAllViewports(allocator, gpu_backend, dt_accum);

    gpu_backend.dbgTextClear(0, false);

    const present_viewid = 0;
    const coreui_viewid = 255;

    // TODO: SHIT
    if (true) {
        const encoder = gpu_backend.getEncoder().?;
        defer gpu_backend.endEncoder(encoder);

        for (_g.viewport_set.keys()) |viewport| {
            if (!viewport.output_to_backbuffer) continue;

            gpu_backend.resetView(present_viewid);
            gpu_backend.setViewClear(present_viewid, .{ .color = true }, 0, 1.0, 0);
            gpu_backend.setViewRectRatio(present_viewid, 0, 0, .Equal);

            const tobb_shader = shader_system.findShaderByName(.fromStr("tobb")).?;
            const shader_io = shader_system.getShaderIO(tobb_shader);

            var shader_constext = try shader_system.createSystemContext();
            defer shader_system.destroySystemContext(shader_constext);

            const rb = (try shader_system.createResourceBuffer(shader_io)).?;
            defer shader_system.destroyResourceBuffer(shader_io, rb);

            try shader_system.updateResources(
                shader_io,
                rb,
                &.{.{ .name = .fromStr("tex"), .value = .{ .texture = viewport.output } }},
            );
            shader_system.bindResource(shader_io, rb, encoder);

            const variants = try shader_system.selectShaderVariant(
                allocator,
                tobb_shader,
                &.{.fromStr("viewport")},
                &shader_constext,
            );
            defer allocator.free(variants);
            const variant = variants[0];

            const projMtx = math.Mat44f.orthographicOffCenterRh(
                0,
                1,
                1,
                0,
                0,
                100,
                gpu_backend.isHomogenousDepth(),
            ).toArray();
            gpu_backend.setViewTransform(present_viewid, null, &projMtx);

            render_graph.screenSpaceQuad(gpu_backend, encoder, 1, 1);

            encoder.setState(variant.state, variant.rgba);
            encoder.submit(present_viewid, variant.prg.?, 0, .all);
            break;
        }
    }

    // TODO: remove or move
    gpu_backend.resetView(coreui_viewid);
    try coreui.draw(allocator, gpu_backend, coreui_viewid, kernel_tick, dt);
    //

    gpu_backend.endAllUsedEncoders();

    {
        var frame_zone_ctx = profiler.ZoneN(@src(), "frame");
        defer frame_zone_ctx.End();
        _g.current_frame = gpu_backend.frame(.{});
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

            try shader_system.addShaderDefiniton("tobb", .{
                .color_state = .rgba,

                .samplers = &.{
                    .{
                        .name = "default",
                        .defs = .{
                            .min_filter = .Linear,
                            .max_filter = .Linear,
                            .u = .Clamp,
                            .v = .Clamp,
                        },
                    },
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = false,
                },
                .imports = &.{
                    .{ .name = "tex", .type = .sampler2d, .sampler = "default" },
                },
                .vertex_block = .{
                    .imports = &.{ .position, .texcoord0 },
                    .import_semantic = &.{.vertex_id},
                    .code =
                    \\  outputs.position = mul(u_modelViewProj, vec4(a_position, 1.0));
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  vec2 uv = gl_FragCoord.xy * u_viewTexel.xy;
                    \\  outputs.color0.xyzw = texture2D(get_tex_sampler(), uv).rgba;
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{} },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .config = "default" },
                            },
                        },
                    },
                },
            });
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
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _io = io;
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);
    try kernel.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try ecs.loadAPI(module_name);
    try gpu_dd.loadAPI(module_name);
    try metrics.loadAPI(module_name);
    try task.loadAPI(module_name);
    try profiler.loadAPI(module_name);
    try coreui.loadAPI(module_name);

    try shader_system.loadAPI(module_name);
    try render_graph.loadAPI(module_name);
    try visibility_flags.loadAPI(module_name);
    try camera.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

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
pub export fn ct_load_module_render_viewport(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
