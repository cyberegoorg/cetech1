const std = @import("std");

const builtin = @import("builtin");

const apidb = @import("apidb.zig");
const profiler_private = @import("profiler.zig");
const task_private = @import("task.zig");
const tempalloc = @import("tempalloc.zig");
const gpu_private = @import("gpu.zig");
const ecs_private = @import("ecs.zig");
const assetdb_private = @import("assetdb.zig");
const metrics_private = @import("metrics.zig");
const cdb_private = @import("cdb.zig");

const cetech1 = @import("cetech1");
const public = cetech1.renderer;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const zm = cetech1.math;
const ecs = cetech1.ecs;
const transform = cetech1.transform;

const primitives = cetech1.primitives;
const cdb = cetech1.cdb;

const _cdb = &cdb_private.api;
const _gpu = &gpu_private.api;
const _dd = &gpu_private.dd_api;
const _metrics = &metrics_private.api;
const _task = &task_private.api;
const _profiler = &profiler_private.api;

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

    pub fn doCulling(self: *Self, allocator: std.mem.Allocator, viewers: []public.Viewer) !void {
        const frustrum_planes = primitives.buildFrustumPlanes(viewers[0].mtx);

        self.tasks.clearRetainingCapacity();

        for (self.crq_map.keys(), self.crq_map.values()) |k, value| {
            const items_count = value.volumes.items.len;

            if (items_count == 0) continue;

            const result = self.getResult(k);

            const ARGS = struct {
                rq: *public.CullingRequest,
                result: *public.CullingResult,
                frustrum: *const primitives.FrustrumPlanes,
            };

            if (try cetech1.task.batchWorkloadTask(
                .{
                    .allocator = allocator,
                    .task_api = &task_private.api,
                    .profiler_api = &profiler_private.api,
                    .count = items_count,
                },
                ARGS{
                    .rq = value,
                    .result = result,
                    .frustrum = &frustrum_planes,
                },
                struct {
                    pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) CullingTask {
                        const rq = create_args.rq;

                        return CullingTask{
                            .count = count,
                            .frustrum = create_args.frustrum,
                            .result = create_args.result,
                            .rq = rq,

                            .transforms = rq.mtx.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + args.batch_size],
                            .components_data = rq.renderables.items[batch_id * args.batch_size * rq.renderable_size .. ((batch_id * args.batch_size * rq.renderable_size) + args.batch_size * rq.renderable_size)],
                            .volumes = rq.volumes.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + args.batch_size],
                        };
                    }
                },
            )) |t| {
                try self.tasks.append(t);
            }
        }

        if (self.tasks.items.len != 0) {
            _task.wait(try _task.combine(self.tasks.items));
        }
    }
};

const Viewport = struct {
    name: [:0]u8,
    fb: gpu.FrameBufferHandle = .{},
    size: [2]f32 = .{ 0, 0 },
    new_size: [2]f32 = .{ 0, 0 },
    dd: gpu.DDEncoder,
    rg: public.Graph,
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

const CullingTask = struct {
    count: usize,
    transforms: []const transform.WorldTransform,
    components_data: []u8,
    volumes: []const public.CullingVolume,

    rq: *public.CullingRequest,
    result: *public.CullingResult,
    frustrum: *const primitives.FrustrumPlanes,

    pub fn exec(self: *@This()) !void {
        var zone = _profiler.ZoneN(@src(), "CullingTask");
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

const ModulePassList = std.ArrayList(ModuleOrPass);
const PassList = std.ArrayList(*public.Pass);

const PassInfoMap = std.AutoArrayHashMap(*public.Pass, PassInfo);
const ResourceSet = std.AutoArrayHashMap(public.ResourceId, void);
const TextureInfoMap = std.AutoArrayHashMap(public.ResourceId, public.TextureInfo);
const TextureMap = std.AutoArrayHashMap(public.ResourceId, gpu.TextureHandle);
const CreatedTextureMap = std.AutoArrayHashMap(CreatedTextureKey, CreatedTextureInfo);
const TextureList = std.ArrayList(gpu.TextureHandle);
const PassSet = std.AutoArrayHashMap(*public.Pass, void);
const ResourceInfoMap = std.AutoArrayHashMap(public.ResourceId, ResourceInfo);
const LayerMap = std.AutoArrayHashMap(cetech1.strid.StrId32, gpu.ViewId);

const ResourceInfo = struct {
    name: []const u8,
    create: ?*public.Pass = null,
    writes: PassSet,
    reads: PassSet,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) ResourceInfo {
        return .{
            .name = name,
            .writes = PassSet.init(allocator),
            .reads = PassSet.init(allocator),
        };
    }

    pub fn deinit(self: *ResourceInfo) void {
        self.writes.deinit();
        self.reads.deinit();
    }
};

const CreatedTextureKey = struct {
    name: public.ResourceId,
    viewport: public.Viewport,
};

const CreatedTextureInfo = struct {
    handler: gpu.TextureHandle,
    info: public.TextureInfo,
    size: [2]f32,
};

const ModuleOrPass = union(enum) {
    module: *Module,
    pass: public.Pass,
};

const PassInfo = struct {
    name: []const u8 = undefined,

    write_texture: ResourceSet,
    read_texture: ResourceSet,
    create_texture: TextureInfoMap,

    viewid: gpu.ViewId = 0,
    clear_stencil: ?u8 = null,
    clear_depth: ?f32 = null,

    exported_layer: ?cetech1.strid.StrId32 = null,

    fb: ?gpu.FrameBufferHandle = null,

    pub fn init(allocator: std.mem.Allocator) PassInfo {
        return .{
            .write_texture = ResourceSet.init(allocator),
            .read_texture = ResourceSet.init(allocator),
            .create_texture = TextureInfoMap.init(allocator),
        };
    }

    pub fn deinit(self: *PassInfo) void {
        self.write_texture.deinit();
        self.create_texture.deinit();
        self.read_texture.deinit();

        if (self.fb) |fb| {
            _gpu.destroyFrameBuffer(fb);
        }
    }

    pub fn needFb(self: PassInfo) bool {
        return self.write_texture.count() != 0;
    }
};

pub fn ratioFromEnum(ratio: gpu.BackbufferRatio) f32 {
    return switch (ratio) {
        .Equal => 1,
        .Half => 1 / 2,
        .Quarter => 1 / 4,
        .Eighth => 1 / 8,
        .Sixteenth => 1 / 16,
        .Double => 2,
        else => 0,
    };
}

const ViewersList = std.ArrayList(public.Viewer);

const GraphBuilder = struct {
    allocator: std.mem.Allocator,
    rg: *Graph,

    passinfo_map: PassInfoMap,
    texture_map: TextureMap,

    passes: PassList,
    viewport: public.Viewport,
    layer_map: LayerMap,

    resource_deps: ResourceInfoMap,

    dag: dag.DAG(*public.Pass),

    viewers: ViewersList,

    pub fn init(allocator: std.mem.Allocator, rg: *Graph, viewport: public.Viewport) GraphBuilder {
        return .{
            .allocator = allocator,
            .rg = rg,
            .passinfo_map = PassInfoMap.init(allocator),
            .texture_map = TextureMap.init(allocator),
            .passes = PassList.init(allocator),
            .viewport = viewport,
            .dag = dag.DAG(*public.Pass).init(allocator),
            .resource_deps = ResourceInfoMap.init(allocator),
            .layer_map = LayerMap.init(allocator),
            .viewers = ViewersList.init(allocator),
        };
    }

    pub fn deinit(self: *GraphBuilder) void {
        for (self.passinfo_map.values()) |*info| {
            info.deinit();
        }

        for (self.resource_deps.values()) |*set| {
            set.deinit();
        }

        self.layer_map.deinit();
        self.passes.deinit();
        self.passinfo_map.deinit();
        self.texture_map.deinit();
        self.dag.deinit();
        self.resource_deps.deinit();
    }

    pub fn addPass(self: *GraphBuilder, name: []const u8, pass: *public.Pass) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.name = name;
        try self.passes.append(pass);
    }

    pub fn exportLayer(self: *GraphBuilder, pass: *public.Pass, name: []const u8) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.exported_layer = cetech1.strid.strId32(name);
    }

    pub fn getViewers(self: *GraphBuilder) []public.Viewer {
        return self.viewers.items;
    }

    pub fn clearStencil(self: *GraphBuilder, pass: *public.Pass, clear_value: u8) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.clear_stencil = clear_value;
    }

    pub fn createTexture2D(self: *GraphBuilder, pass: *public.Pass, texture: []const u8, info: public.TextureInfo) !void {
        const pass_info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strid.strId32(texture);
        try pass_info.create_texture.put(texture_id, info);

        if (info.clear_depth) |depth| {
            pass_info.clear_depth = depth;
        }

        try self.writeTexture(pass, texture);

        const deps = try self.getOrCreateResourceDeps(texture);
        deps.create = pass;
    }

    pub fn writeTexture(self: *GraphBuilder, pass: *public.Pass, texture: []const u8) !void {
        const info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strid.strId32(texture);

        try info.write_texture.put(texture_id, {});
        const deps = try self.getOrCreateResourceDeps(texture);
        try deps.writes.put(pass, {});
    }

    pub fn readTexture(self: *GraphBuilder, pass: *public.Pass, texture: []const u8) !void {
        const info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strid.strId32(texture);

        try info.read_texture.put(texture_id, {});
        const deps = try self.getOrCreateResourceDeps(texture);
        try deps.reads.put(pass, {});
    }

    pub fn getTexture(self: *GraphBuilder, texture: []const u8) ?gpu.TextureHandle {
        return self.texture_map.get(cetech1.strid.strId32(texture));
    }

    pub fn getLayer(self: *GraphBuilder, layer: []const u8) gpu.ViewId {
        return self.layer_map.get(cetech1.strid.strId32(layer)) orelse 256;
    }

    pub fn importTexture(self: *GraphBuilder, texture_name: []const u8, texture: gpu.TextureHandle) !void {
        try self.texture_map.put(cetech1.strid.strId32(texture_name), texture);
    }

    fn getOrCreateResourceDeps(self: *GraphBuilder, texture_name: []const u8) !*ResourceInfo {
        const texture_id = cetech1.strid.strId32(texture_name);

        const result = try self.resource_deps.getOrPut(texture_id);
        if (!result.found_existing) {
            result.value_ptr.* = ResourceInfo.init(self.allocator, texture_name);
        }

        return result.value_ptr;
    }

    pub fn compile(self: *GraphBuilder) !void {
        // Create DAG for pass
        for (self.passes.items) |pass| {
            const info = self.passinfo_map.getPtr(pass) orelse return error.InvalidPass;

            var depends = std.ArrayList(*public.Pass).init(self.allocator);
            defer depends.deinit();

            for (info.write_texture.keys()) |texture| {
                const texture_deps = self.resource_deps.get(texture).?;
                if (texture_deps.create) |create_pass| {
                    if (create_pass == pass) continue;

                    try depends.append(create_pass);
                }
            }

            for (info.read_texture.keys()) |texture| {
                const texture_deps = self.resource_deps.get(texture).?;

                try depends.appendSlice(texture_deps.writes.keys());

                if (texture_deps.create) |create_pass| {
                    if (create_pass == pass) continue;

                    try depends.append(create_pass);
                }
            }

            try self.dag.add(pass, depends.items);
        }

        // Build DAG => flat array
        try self.dag.build_all();

        // Prepare passes
        for (self.dag.output.keys()) |pass| {
            var info = self.passinfo_map.getPtr(pass) orelse return error.InvalidPass;

            const viewid = newViewId();
            info.viewid = viewid;
            if (info.exported_layer) |layer| {
                try self.layer_map.put(layer, viewid);
            }

            if (info.needFb()) {
                var clear_flags: gpu.ClearFlags = gpu.ClearFlags_None;
                var clear_colors: [8]u8 = .{std.math.maxInt(u8)} ** 8;

                var textures = std.ArrayList(gpu.TextureHandle).init(self.allocator);
                defer textures.deinit();

                for (info.create_texture.keys(), info.create_texture.values()) |k, v| {
                    const texture_deps = self.resource_deps.get(k).?;

                    const t = try self.rg.createTexture2D(self.viewport, texture_deps.name, v);
                    try self.texture_map.put(k, t);
                }

                for (info.write_texture.keys(), 0..) |write, idx| {
                    try textures.append(self.texture_map.get(write).?);

                    // Clear only created
                    const texture = info.create_texture.get(write) orelse continue;
                    if (texture.clear_color) |c| {
                        clear_flags |= gpu.ClearFlags_Color;
                        const c_idx = _gpu.addPaletteColor(c);
                        clear_colors[idx] = c_idx;
                    } else if (null != texture.clear_depth) {
                        clear_flags |= gpu.ClearFlags_Depth;
                    }
                }

                // stencil
                var stencil_clear_value: u8 = 0;
                if (info.clear_stencil) |clear_value| {
                    stencil_clear_value = clear_value;
                    clear_flags |= gpu.ClearFlags_Stencil;
                }

                _gpu.setViewClearMrt(
                    viewid,
                    clear_flags,
                    info.clear_depth orelse 1.0,
                    stencil_clear_value,
                    clear_colors[0],
                    clear_colors[1],
                    clear_colors[2],
                    clear_colors[3],
                    clear_colors[4],
                    clear_colors[5],
                    clear_colors[6],
                    clear_colors[7],
                );

                const fb = _gpu.createFrameBufferFromHandles(@truncate(textures.items.len), textures.items.ptr, false);
                _gpu.setFrameBufferName(fb, info.name.ptr, @intCast(info.name.len));

                info.fb = fb;

                const vp_size = self.viewport.getSize();
                _gpu.setViewName(viewid, info.name.ptr, @intCast(info.name.len));
                _gpu.setViewFrameBuffer(viewid, fb);
                _gpu.setViewRect(
                    viewid,
                    0,
                    0,
                    @intFromFloat(vp_size[0]),
                    @intFromFloat(vp_size[1]),
                );
            }
        }
    }

    pub fn execute(self: *GraphBuilder) !void {
        // Main vieewr
        const fb_size = self.viewport.getSize();
        const aspect_ratio = fb_size[0] / fb_size[1];

        // TODO: from camera
        const projMtx = zm.perspectiveFovRhGl(
            0.25 * std.math.pi,
            aspect_ratio,
            0.1,
            1000.0,
        );

        const viewMtx = self.viewport.getViewMtx();
        const VP = zm.mul(zm.matFromArr(viewMtx), projMtx);
        try self.viewers.append(.{ .mtx = zm.matToArr(VP) });

        //
        for (self.passes.items) |pass| {
            const info = self.passinfo_map.get(pass) orelse return error.InvalidPass;

            const builder = public.GraphBuilder{ .ptr = self, .vtable = &builder_vt };
            try pass.render(builder, _gpu, self.viewport, info.viewid);
        }
    }

    fn getOrCreateInfo(self: *GraphBuilder, pass: *public.Pass) !*PassInfo {
        const result = try self.passinfo_map.getOrPut(pass);

        if (!result.found_existing) {
            result.value_ptr.* = PassInfo.init(self.allocator);
        }

        return result.value_ptr;
    }
};

const Module = struct {
    allocator: std.mem.Allocator,
    passes: ModulePassList,

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{
            .allocator = allocator,
            .passes = ModulePassList.init(allocator),
        };
    }

    pub fn deinit(self: *Module) void {
        for (self.passes.items) |pass_or_module| {
            switch (pass_or_module) {
                .module => |module| module.deinit(),
                .pass => continue,
            }
        }

        self.passes.deinit();
    }

    pub fn addPass(self: *Module, pass: public.Pass) !void {
        try self.passes.append(.{ .pass = pass });
    }

    pub fn addModule(self: *Module, module: public.Module) !void {
        try self.passes.append(.{ .module = @alignCast(@ptrCast(module.ptr)) });
    }

    pub fn setup(self: *Module, builder: public.GraphBuilder) !void {
        for (self.passes.items) |*pass_or_module| {
            switch (pass_or_module.*) {
                .module => |module| try module.setup(builder),
                .pass => |*pass| try pass.setup(pass, builder),
            }
        }
    }
};

const ModulePool = cetech1.mem.PoolWithLock(Module);
const BuilderPool = cetech1.mem.PoolWithLock(GraphBuilder);

const Graph = struct {
    allocator: std.mem.Allocator,
    module_pool: ModulePool,
    builder_pool: BuilderPool,
    module: Module,
    created_texture: CreatedTextureMap,

    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{
            .allocator = allocator,
            .module_pool = ModulePool.init(allocator),
            .builder_pool = BuilderPool.init(allocator),
            .module = Module.init(allocator),
            .created_texture = CreatedTextureMap.init(allocator),
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.created_texture.values()) |texture| {
            _gpu.destroyTexture(texture.handler);
        }

        self.module.deinit();
        self.module_pool.deinit();
        self.builder_pool.deinit();
        self.created_texture.deinit();
    }

    pub fn addPass(self: *Graph, pass: public.Pass) !void {
        try self.module.addPass(pass);
    }

    pub fn addModule(self: *Graph, module: public.Module) !void {
        try self.module.addModule(module);
    }

    pub fn createModule(self: *Graph) !public.Module {
        const new_module = try self.module_pool.create();
        new_module.* = Module.init(self.allocator);
        return public.Module{
            .ptr = new_module,
            .vtable = &module_vt,
        };
    }

    pub fn createBuilder(self: *Graph, allocator: std.mem.Allocator, viewport: public.Viewport) !public.GraphBuilder {
        const new_builder = try self.builder_pool.create();
        new_builder.* = GraphBuilder.init(allocator, self, viewport);
        return .{ .ptr = new_builder, .vtable = &builder_vt };
    }

    pub fn destroyBuilder(self: *Graph, builder: public.GraphBuilder) void {
        const true_builder: *GraphBuilder = @alignCast(@ptrCast(builder.ptr));
        true_builder.deinit();
        self.builder_pool.destroy(true_builder);
    }

    pub fn setupBuilder(self: *Graph, builder: public.GraphBuilder) !void {
        try self.module.setup(builder);
    }

    pub fn createTexture2D(self: *Graph, viewport: public.Viewport, texture_name: []const u8, info: public.TextureInfo) !gpu.TextureHandle {
        const texture_id = cetech1.strid.strId32(texture_name);

        const vp_size = viewport.getSize();
        const ratio = ratioFromEnum(info.ratio);
        const size = [2]f32{ vp_size[0] * ratio, vp_size[1] * ratio };
        const exist_texture = self.created_texture.get(.{ .name = texture_id, .viewport = viewport });

        if (exist_texture) |t| {
            // it's a match
            if (t.info.eql(info) and t.size[0] == vp_size[0] and t.size[1] == vp_size[1]) return t.handler;

            _gpu.destroyTexture(t.handler);
        }

        // Create new
        const t = _gpu.createTexture2D(
            @intFromFloat(size[0]),
            @intFromFloat(size[1]),
            info.has_mip,
            info.num_layers,
            info.format,
            info.flags,
            null,
        );

        if (!t.isValid()) {
            return error.InvalidTexture;
        }

        _gpu.setTextureName(t, texture_name.ptr, @intCast(texture_name.len));

        try self.created_texture.put(
            .{ .name = texture_id, .viewport = viewport },
            .{
                .handler = t,
                .info = info,
                .size = size,
            },
        );
        return t;
    }
};

const GraphPool = cetech1.mem.PoolWithLock(Graph);
const GraphSet = std.AutoArrayHashMap(*Graph, void);
var _rg_lock: std.Thread.Mutex = undefined;
var _rg_set: GraphSet = undefined;
var _rg_pool: GraphPool = undefined;

const ViewportPool = cetech1.mem.PoolWithLock(Viewport);
const ViewportSet = std.AutoArrayHashMap(*Viewport, void);
const PalletColorMap = std.AutoArrayHashMap(u32, u8);

var _viewport_set: ViewportSet = undefined;
var _viewport_pool: ViewportPool = undefined;

const _kernel_render_task = cetech1.kernel.KernelRenderI.implment(struct {
    pub fn render(ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) !void {
        renderAll(ctx, kernel_tick, dt, vsync);
    }
});

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _viewport_set = ViewportSet.init(allocator);
    _viewport_pool = ViewportPool.init(allocator);

    _rg_set = GraphSet.init(allocator);
    _rg_pool = GraphPool.init(allocator);
    _rg_lock = std.Thread.Mutex{};

    try registerToApi();
}

pub fn deinit() void {
    _viewport_set.deinit();
    _viewport_pool.deinit();

    _rg_set.deinit();
    _rg_pool.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.RendererApi, &api);
    try apidb.api.setZigApi(module_name, public.RenderGraphApi, &graph_api);

    try apidb.api.implInterface(module_name, cetech1.kernel.KernelRenderI, &_kernel_render_task);
}

fn createViewport(name: [:0]const u8, rg: public.Graph, world: ?ecs.World) !public.Viewport {
    const new_viewport = try _viewport_pool.create();

    const dupe_name = try _allocator.dupeZ(u8, name);

    var buf: [128]u8 = undefined;

    new_viewport.* = .{
        .name = dupe_name,
        .dd = _dd.encoderCreate(),
        .rg = rg,
        .world = world,
        .view_mtx = zm.matToArr(zm.lookAtRh(
            zm.f32x4(0.0, 0.0, 0.0, 1.0),
            zm.f32x4(0.0, 0.0, 1.0, 1.0),
            zm.f32x4(0.0, 1.0, 0.0, 1.0),
        )),
        .culling = CullingSystem.init(_allocator),
        .all_renderables_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_renerables", .{dupe_name})),
        .rendered_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/rendered", .{dupe_name})),
        .culling_collect_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_collect_duration", .{dupe_name})),
        .culling_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_duration", .{dupe_name})),
        .render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/render_duration", .{dupe_name})),
        .complete_render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/complete_render_duration", .{dupe_name})),
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
        _gpu.destroyFrameBuffer(true_viewport.fb);
    }

    true_viewport.culling.deinit();
    _allocator.free(true_viewport.name);

    _dd.encoderDestroy(true_viewport.dd);
    _viewport_pool.destroy(true_viewport);
}

pub const api = public.RendererApi{
    .newViewId = newViewId,
    .createViewport = createViewport,
    .destroyViewport = destroyViewport,

    .renderAll = renderAll,
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

    pub fn getDD(viewport: *anyopaque) gpu.DDEncoder {
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

        var zone = _profiler.ZoneN(@src(), "RenderViewport");
        defer zone.End();

        const allocator = try tempalloc.api.create();
        defer tempalloc.api.destroy(allocator);

        const fb = s.viewport.fb;
        if (!fb.isValid()) return;

        const rg = s.viewport.rg;
        if (@intFromPtr(rg.ptr) == 0) return;

        const vp = public.Viewport{ .ptr = s.viewport, .vtable = &viewport_vt };
        const builder = try rg.createBuilder(allocator, vp);
        defer rg.destroyBuilder(builder);
        {
            var z = _profiler.ZoneN(@src(), "RenderViewport - Render graph");
            defer z.End();

            const color_output = _gpu.getTexture(fb, 0);
            try builder.importTexture(public.ViewportColorResource, color_output);

            try rg.setupBuilder(builder);

            try builder.compile();
            try builder.execute(vp);
        }

        const Renderables = struct {
            iface: *const public.RendereableI,
        };

        if (s.viewport.world) |world| {
            var renderables = std.ArrayList(Renderables).init(allocator);
            defer renderables.deinit();

            const viewers = builder.getViewers();

            // Collect  renderables to culling
            {
                var z = _profiler.ZoneN(@src(), "RenderViewport - Culling collect phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.culling_collect_duration);
                defer counter.end();

                const impls = try apidb.api.getImpl(allocator, cetech1.renderer.RendereableI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    const renderable = Renderables{ .iface = iface };

                    const cr = try s.viewport.culling.getRequest(iface, iface.size);

                    if (iface.culling) |culling| {
                        var zz = _profiler.ZoneN(@src(), "RenderViewport - Culling calback");
                        defer zz.End();

                        _ = try culling(allocator, builder, world, viewers, cr);
                    }
                    try renderables.append(renderable);

                    s.viewport.all_renderables_counter.* += @floatFromInt(cr.mtx.items.len);
                }
            }

            // Culling
            {
                var z = _profiler.ZoneN(@src(), "RenderViewport - Culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.culling_duration);
                defer counter.end();

                try s.viewport.culling.doCulling(allocator, viewers);
            }

            // Render
            {
                var z = _profiler.ZoneN(@src(), "RenderViewport - Render phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.render_duration);
                defer counter.end();

                for (renderables.items) |renderable| {
                    var zz = _profiler.ZoneN(@src(), "RenderViewport - Render calback");
                    defer zz.End();

                    const result = s.viewport.culling.getResult(renderable.iface);

                    s.viewport.rendered_counter.* += @floatFromInt(result.mtx.items.len);

                    if (result.renderables.items.len > 0) {
                        try renderable.iface.render(allocator, builder, world, vp, result);
                    }
                }
            }
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "renderAllViewports");
    defer zone_ctx.End();

    var tasks = std.ArrayList(cetech1.task.TaskID).init(allocator);
    defer tasks.deinit();

    resetViewId();

    for (_viewport_set.keys()) |viewport| {
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

        // TODO: task wait block thread and if you have more viewport than thread they can block whole app.
        if (true) {
            var render_task = RenderViewportTask{ .viewport = viewport };
            try render_task.exec();
        } else {
            const task_id = try _task.schedule(
                cetech1.task.TaskID.none,
                RenderViewportTask{
                    .viewport = viewport,
                },
            );
            try tasks.append(task_id);
        }
    }

    if (tasks.items.len != 0) {
        _task.wait(try _task.combine(tasks.items));
    }
}

fn renderAll(ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) void {
    _renderAll(@alignCast(@ptrCast(ctx)), kernel_tick, dt, vsync) catch undefined;
}

var old_fb_size = [2]i32{ -1, -1 };
var old_flags = gpu.ResetFlags_None;
fn _renderAll(ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) !void {
    _ = kernel_tick;
    _ = dt;
    var zone_ctx = _profiler.ZoneN(@src(), "Render");
    defer zone_ctx.End();

    var flags = gpu.ResetFlags_None;

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

    const encoder = _gpu.getEncoder().?;
    encoder.touch(0);

    _gpu.dbgTextClear(0, false);

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try renderAllViewports(allocator);

    gpu_private.endAllUsedEncoders();

    // TODO: save frameid for sync (sync across frames like read back frame + 2)
    {
        var frame_zone_ctx = _profiler.ZoneN(@src(), "frame");
        defer frame_zone_ctx.End();
        _ = _gpu.frame(false);
    }
    // TODO
    // profiler.ztracy.FrameImage( , width: u16, height: u16, offset: u8, flip: c_int);
}

pub const rg_vt = public.Graph.VTable{
    .addPass = @ptrCast(&Graph.addPass),
    .addModule = @ptrCast(&Graph.addModule),
    .createModule = @ptrCast(&Graph.createModule),
    .createBuilder = @ptrCast(&Graph.createBuilder),
    .destroyBuilder = @ptrCast(&Graph.destroyBuilder),
    .setupBuilder = @ptrCast(&Graph.setupBuilder),
};

pub const module_vt = public.Module.VTable{
    .addPassToModule = @ptrCast(&Module.addPass),
    .addModuleToModule = @ptrCast(&Module.addModule),
};

pub const builder_vt = public.GraphBuilder.VTable{
    .addPass = @ptrCast(&GraphBuilder.addPass),
    .clearStencil = @ptrCast(&GraphBuilder.clearStencil),
    .createTexture2D = @ptrCast(&GraphBuilder.createTexture2D),
    .getTexture = @ptrCast(&GraphBuilder.getTexture),
    .writeTexture = @ptrCast(&GraphBuilder.writeTexture),
    .readTexture = @ptrCast(&GraphBuilder.readTexture),
    .importTexture = @ptrCast(&GraphBuilder.importTexture),
    .getLayer = @ptrCast(&GraphBuilder.getLayer),
    .exportLayer = @ptrCast(&GraphBuilder.exportLayer),

    .getViewers = @ptrCast(&GraphBuilder.getViewers),

    .execute = @ptrCast(&GraphBuilder.execute),
    .compile = @ptrCast(&GraphBuilder.compile),
};

pub const graph_api = public.RenderGraphApi{
    .create = create,
    .createDefault = createDefault,
    .destroy = destroy,
};

fn create() !public.Graph {
    const new_rg = try _rg_pool.create();
    new_rg.* = Graph.init(_allocator);

    {
        _rg_lock.lock();
        defer _rg_lock.unlock();
        try _rg_set.put(new_rg, {});
    }

    return public.Graph{ .ptr = new_rg, .vtable = &rg_vt };
}

fn createDefault(allocator: std.mem.Allocator, graph: public.Graph) !void {
    const impls = try apidb.api.getImpl(allocator, public.DefaultRenderGraphI);
    defer allocator.free(impls);
    if (impls.len == 0) return;

    const iface = impls[impls.len - 1];
    return try iface.create(allocator, &graph_api, graph);
}

fn destroy(rg: public.Graph) void {
    const true_rg: *Graph = @alignCast(@ptrCast(rg.ptr));
    true_rg.deinit();

    {
        _rg_lock.lock();
        defer _rg_lock.unlock();
        _ = _rg_set.swapRemove(true_rg);
    }

    _rg_pool.destroy(true_rg);
}
