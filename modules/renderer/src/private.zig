const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const primitives = cetech1.primitives;
const zm = cetech1.math;
const gpu = cetech1.gpu;
const dag = cetech1.dag;

const public = @import("renderer.zig");

const transform = @import("transform");
const graphvm = @import("graphvm");
const camera = @import("camera");
const shader_system = @import("shader_system");

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
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;

var _dd: *const gpu.GpuDDApi = undefined;
var _metrics: *const cetech1.metrics.MetricsAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;

var _shader: *const shader_system.ShaderSystemAPI = undefined;

// Global state
const G = struct {
    viewport_set: ViewportSet = undefined,
    viewport_pool: ViewportPool = undefined,
    rg_lock: std.Thread.Mutex = undefined,
    rg_set: GraphSet = undefined,
    rg_pool: GraphPool = undefined,

    cube_pos_vb: gpu.VertexBufferHandle = .{},
    cube_col_vb: gpu.VertexBufferHandle = .{},
    cube_ib: gpu.IndexBufferHandle = .{},

    time_system: shader_system.SystemInstance = undefined,
};

var _g: *G = undefined;

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

    pub fn doCulling(self: *Self, allocator: std.mem.Allocator, viewers: []const public.Viewer) !void {
        //TODO for all viewer
        const mtx = zm.mul(zm.matFromArr(viewers[0].mtx), zm.matFromArr(viewers[0].proj));
        const frustrum_planes = primitives.buildFrustumPlanes(zm.matToArr(mtx));

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
                    .task_api = _task,
                    .profiler_api = _profiler,
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

    world: ?ecs.World,
    main_camera_entity: ?ecs.EntityId = null,
    culling: CullingSystem,

    renderMe: bool,

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

        const task_allocator = try _tmpalloc.create();
        defer _tmpalloc.destroy(task_allocator);

        // TODO : Faster
        // TODO : Culling in clip space
        for (self.volumes, 0..) |culling_volume, i| {
            // TODO : Bounding box

            if (culling_volume.hasSphere()) {
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

    pub fn getLayerById(self: *GraphBuilder, layer: strid.StrId32) gpu.ViewId {
        return self.layer_map.get(layer) orelse 256;
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

            const viewid = _gpu.newViewId();
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

    pub fn execute(self: *GraphBuilder, viewers: []const public.Viewer) !void {
        //
        for (self.passes.items) |pass| {
            const info = self.passinfo_map.get(pass) orelse return error.InvalidPass;

            const builder = public.GraphBuilder{ .ptr = self, .vtable = &builder_vt };
            try pass.render(builder, _gpu, self.viewport, info.viewid, viewers);
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

const ViewportPool = cetech1.mem.PoolWithLock(Viewport);
const ViewportSet = std.AutoArrayHashMap(*Viewport, void);
const PalletColorMap = std.AutoArrayHashMap(u32, u8);

const _kernel_render_task = cetech1.kernel.KernelRenderI.implment(struct {
    pub fn render(ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) !void {
        renderAll(ctx, kernel_tick, dt, vsync);
    }
});

fn createViewport(name: [:0]const u8, rg: public.Graph, world: ?ecs.World, camera_ent: ecs.EntityId) !public.Viewport {
    const new_viewport = try _g.viewport_pool.create();

    const dupe_name = try _allocator.dupeZ(u8, name);

    var buf: [128]u8 = undefined;

    new_viewport.* = .{
        .name = dupe_name,
        .dd = _dd.encoderCreate(),
        .rg = rg,
        .world = world,
        .main_camera_entity = camera_ent,
        .renderMe = false,
        .culling = CullingSystem.init(_allocator),
        .all_renderables_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/all_renerables", .{dupe_name})),
        .rendered_counter = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/rendered", .{dupe_name})),
        .culling_collect_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_collect_duration", .{dupe_name})),
        .culling_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/culling_duration", .{dupe_name})),
        .render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/render_duration", .{dupe_name})),
        .complete_render_duration = try _metrics.getCounter(try std.fmt.bufPrint(&buf, "renderer/viewports/{s}/complete_render_duration", .{dupe_name})),
    };

    try _g.viewport_set.put(new_viewport, {});
    return public.Viewport{
        .ptr = new_viewport,
        .vtable = &viewport_vt,
    };
}

fn destroyViewport(viewport: public.Viewport) void {
    const true_viewport: *Viewport = @alignCast(@ptrCast(viewport.ptr));
    _ = _g.viewport_set.swapRemove(true_viewport);

    if (true_viewport.fb.isValid()) {
        _gpu.destroyFrameBuffer(true_viewport.fb);
    }

    true_viewport.culling.deinit();
    _allocator.free(true_viewport.name);

    _dd.encoderDestroy(true_viewport.dd);
    _g.viewport_pool.destroy(true_viewport);
}

pub const api = public.RendererApi{
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

    pub fn renderMe(viewport: *anyopaque) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.renderMe = true;
    }

    pub fn setMainCamera(viewport: *anyopaque, camera_ent: ?ecs.EntityId) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.main_camera_entity = camera_ent;
    }

    pub fn getMainCamera(viewport: *anyopaque) ?ecs.EntityId {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.main_camera_entity;
    }
});

const RenderViewportTask = struct {
    viewport: *Viewport,
    now_s: f32,
    pub fn exec(s: *@This()) !void {
        const complete_counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.complete_render_duration);
        defer complete_counter.end();

        var zone = _profiler.ZoneN(@src(), "RenderViewport");
        defer zone.End();

        const allocator = try _tmpalloc.create();
        defer _tmpalloc.destroy(allocator);

        const fb = s.viewport.fb;
        if (!fb.isValid()) return;

        const rg = s.viewport.rg;
        if (@intFromPtr(rg.ptr) == 0) return;

        const vp = public.Viewport{ .ptr = s.viewport, .vtable = &viewport_vt };

        const Renderables = struct {
            iface: *const public.RendereableI,
        };

        var viewers = ViewersList.init(allocator);
        defer viewers.deinit();

        var enabled_systems = shader_system.SystemSet.initEmpty();
        enabled_systems.set(_shader.getSystemIdx(strid.strId32("viewer_system")));
        enabled_systems.set(_shader.getSystemIdx(strid.strId32("time_system")));

        if (s.viewport.world) |world| {
            var renderables = std.ArrayList(Renderables).init(allocator);
            defer renderables.deinit();

            viewers.clearRetainingCapacity();

            // Main vieewr
            const fb_size = s.viewport.size;
            const aspect_ratio = fb_size[0] / fb_size[1];

            // TODO: shader components
            {}

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

                        const v = public.Viewer{
                            .camera = cameras[idx],
                            .mtx = zm.matToArr(zm.inverse(camera_transforms[idx].mtx)),
                            .proj = zm.matToArr(pmtx),
                            .context = strid.strId32("viewport"),
                        };

                        if (s.viewport.main_camera_entity != null and s.viewport.main_camera_entity.? == entities[idx]) {
                            try viewers.insert(0, v);
                        } else {
                            try viewers.append(v);
                        }
                    }
                }
            }

            if (viewers.items.len == 0) return;

            const builder = try rg.createBuilder(allocator, vp);
            defer rg.destroyBuilder(builder);
            {
                var z = _profiler.ZoneN(@src(), "RenderViewport - Render graph");
                defer z.End();

                const color_output = _gpu.getTexture(fb, 0);
                try builder.importTexture(public.ViewportColorResource, color_output);

                try rg.setupBuilder(builder);

                try builder.compile();
                try builder.execute(viewers.items);
            }

            // TODO: Collect renderables that is not cullable
            {}

            // Collect  renderables to culling
            {
                var z = _profiler.ZoneN(@src(), "RenderViewport - Culling collect phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.culling_collect_duration);
                defer counter.end();

                const impls = try _apidb.getImpl(allocator, public.RendereableI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    const renderable = Renderables{ .iface = iface };

                    const cr = try s.viewport.culling.getRequest(iface, iface.size);

                    if (iface.culling) |culling| {
                        var zz = _profiler.ZoneN(@src(), "RenderViewport - Culling calback");
                        defer zz.End();

                        _ = try culling(allocator, builder, world, viewers.items, cr);
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

                try s.viewport.culling.doCulling(allocator, viewers.items);
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
                        try renderable.iface.render(allocator, builder, world, vp, viewers.items, enabled_systems, result);
                    }
                }
            }
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator, time_s: f32) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "renderAllViewports");
    defer zone_ctx.End();

    var tasks = std.ArrayList(cetech1.task.TaskID).init(allocator);
    defer tasks.deinit();

    _gpu.resetViewId();

    // Submit Time system
    try _g.time_system.uniforms.?.set(strid.strId32("time"), [4]f32{ time_s, 0, 0, 0 });
    _shader.submitSystemUniforms(_g.time_system);

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

        // TODO: task wait block thread and if you have more viewport than thread they can block whole app.
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
var dt_accum: f32 = 0;
fn _renderAll(ctx: *gpu.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) !void {
    _ = kernel_tick; // autofix
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

    const allocator = try _tmpalloc.create();
    defer _tmpalloc.destroy(allocator);

    try renderAllViewports(allocator, dt_accum);

    _gpu.endAllUsedEncoders();

    // TODO: save frameid for sync (sync across frames like read back frame + 2)
    {
        var frame_zone_ctx = _profiler.ZoneN(@src(), "frame");
        defer frame_zone_ctx.End();
        _ = _gpu.frame(false);
    }

    dt_accum += dt;

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
    .getLayerById = @ptrCast(&GraphBuilder.getLayerById),
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
    const new_rg = try _g.rg_pool.create();
    new_rg.* = Graph.init(_allocator);

    {
        _g.rg_lock.lock();
        defer _g.rg_lock.unlock();
        try _g.rg_set.put(new_rg, {});
    }

    return public.Graph{ .ptr = new_rg, .vtable = &rg_vt };
}

fn createDefault(allocator: std.mem.Allocator, graph: public.Graph) !void {
    const impls = try _apidb.getImpl(allocator, public.DefaultRenderGraphI);
    defer allocator.free(impls);
    if (impls.len == 0) return;

    const iface = impls[impls.len - 1];
    return try iface.create(allocator, &graph_api, graph);
}

fn destroy(rg: public.Graph) void {
    const true_rg: *Graph = @alignCast(@ptrCast(rg.ptr));
    true_rg.deinit();

    {
        _g.rg_lock.lock();
        defer _g.rg_lock.unlock();
        _ = _g.rg_set.swapRemove(true_rg);
    }

    _g.rg_pool.destroy(true_rg);
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Renderer",
    &[_]strid.StrId64{},
    struct {
        pub fn init() !void {
            _g.viewport_set = ViewportSet.init(_allocator);
            _g.viewport_pool = ViewportPool.init(_allocator);

            _g.rg_set = GraphSet.init(_allocator);
            _g.rg_pool = GraphPool.init(_allocator);
            _g.rg_lock = std.Thread.Mutex{};

            _g.time_system = try _shader.createSystemInstance(strid.strId32("time_system"));

            _vertex_pos_layout = PosVertex.layoutInit();
            _vertex_col_layout = ColorVertex.layoutInit();
            _g.cube_pos_vb = _gpu.createVertexBuffer(
                _gpu.makeRef(&cube_positions, cube_positions.len * @sizeOf(PosVertex)),
                &_vertex_pos_layout,
                gpu.BufferFlags_None,
            );
            _g.cube_col_vb = _gpu.createVertexBuffer(
                _gpu.makeRef(&cube_cololrs, cube_cololrs.len * @sizeOf(ColorVertex)),
                &_vertex_col_layout,
                gpu.BufferFlags_None,
            );
            _g.cube_ib = _gpu.createIndexBuffer(
                _gpu.makeRef(&cube_tri_list, cube_tri_list.len * @sizeOf(u16)),
                gpu.BufferFlags_None,
            );
        }

        pub fn shutdown() !void {
            _g.viewport_set.deinit();
            _g.viewport_pool.deinit();

            _g.rg_set.deinit();
            _g.rg_pool.deinit();

            _shader.destroySystemInstance(&_g.time_system);

            _gpu.destroyIndexBuffer(_g.cube_ib);
            _gpu.destroyVertexBuffer(_g.cube_pos_vb);
            _gpu.destroyVertexBuffer(_g.cube_col_vb);
        }
    },
);

const gpu_geometry_value_type_i = graphvm.GraphValueTypeI.implement(
    public.GPUGeometry,
    .{
        .name = "GPU geometry",
        .type_hash = public.PinTypes.GPU_GEOMETRY,
        .cdb_type_hash = public.GPUGeometryCdb.type_hash, // TODO: this is not needed. value only setable from nodes out
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v: public.GPUGeometry = .{
                .vb = .{
                    .{ .idx = @truncate(public.GPUGeometryCdb.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle0)) },
                    .{ .idx = @truncate(public.GPUGeometryCdb.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle1)) },
                    .{ .idx = @truncate(public.GPUGeometryCdb.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle2)) },
                    .{ .idx = @truncate(public.GPUGeometryCdb.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle3)) },
                },
            };

            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return strid.strId64(value).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(public.GPUGeometry, value)});
        }
    },
);

const gpu_index_buffer_value_type_i = graphvm.GraphValueTypeI.implement(
    gpu.IndexBufferHandle,
    .{
        .name = "GPU index buffer",
        .type_hash = public.PinTypes.GPU_INDEX_BUFFER,
        .cdb_type_hash = public.GPUIndexBufferCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = public.GPUIndexBufferCdb.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(u32, value)});
        }
    },
);

// TODO: Move
const culling_volume_node_i = graphvm.NodeI.implement(
    .{
        .name = "Culling volume",
        .type_name = public.CULLING_VOLUME_NODE_TYPE_STR,
        .pivot = .pivot,
        .category = "Culling",
    },
    public.CullingVolume,
    struct {
        const Self = @This();

        pub fn getInputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{
                graphvm.NodePin.init("Radius", graphvm.NodePin.pinHash("radius", false), graphvm.PinTypes.F32, null),
                graphvm.NodePin.init("Min", graphvm.NodePin.pinHash("min", false), graphvm.PinTypes.VEC3F, null),
                graphvm.NodePin.init("Max", graphvm.NodePin.pinHash("max", false), graphvm.PinTypes.VEC3F, null),
            });
        }

        pub fn getOutputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{});
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
            const real_state: *public.CullingVolume = @alignCast(@ptrCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = out_pins;
            var state = args.getState(public.CullingVolume).?;
            _, const radius = in_pins.read(f32, 0) orelse .{ 0, 0 };
            _, const min = in_pins.read([3]f32, 1) orelse .{ 0, .{ 0, 0, 0 } };
            _, const max = in_pins.read([3]f32, 2) orelse .{ 0, .{ 0, 0, 0 } };

            state.radius = radius;
            state.min = min;
            state.max = max;
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Bounding});
        }
    },
);

const draw_call_node_i = graphvm.NodeI.implement(
    .{
        .name = "Draw call",
        .type_name = public.DRAW_CALL_NODE_TYPE_STR,
        .pivot = .pivot,
        .category = "Renderer",
    },
    public.DrawCall,
    struct {
        const Self = @This();

        pub fn getInputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{
                graphvm.NodePin.init("GPU shader", graphvm.NodePin.pinHash("gpu_shader", false), shader_system.PinTypes.GPU_SHADER, null),
                graphvm.NodePin.init("GPU geometry", graphvm.NodePin.pinHash("gpu_geometry", false), public.PinTypes.GPU_GEOMETRY, null),
                graphvm.NodePin.init("GPU index buffer", graphvm.NodePin.pinHash("gpu_index_buffer", false), public.PinTypes.GPU_INDEX_BUFFER, null),
                graphvm.NodePin.init("Vertex count", graphvm.NodePin.pinHash("vertex_count", false), graphvm.PinTypes.U32, null),
                graphvm.NodePin.init("Index count", graphvm.NodePin.pinHash("index_count", false), graphvm.PinTypes.U32, null),
            });
        }

        pub fn getOutputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{});
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
            const real_state: *public.DrawCall = @alignCast(@ptrCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = out_pins;
            var state = args.getState(public.DrawCall).?;
            _, const gpu_shader = in_pins.read(shader_system.ShaderInstance, 0) orelse .{ 0, shader_system.ShaderInstance{} };
            _, const gpu_geometry = in_pins.read(public.GPUGeometry, 1) orelse .{ 0, public.GPUGeometry{} };
            _, const gpu_index_buffer = in_pins.read(gpu.IndexBufferHandle, 2) orelse .{ 0, gpu.IndexBufferHandle{} };
            _, const vertex_count = in_pins.read(u32, 3) orelse .{ 0, 0 };
            _, const index_count = in_pins.read(u32, 4) orelse .{ 0, 0 };

            state.gpu_shader = gpu_shader;
            state.gpu_geometry = gpu_geometry;
            state.gpu_index_buffer = gpu_index_buffer;
            state.vertex_count = vertex_count;
            state.index_count = index_count;
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Draw});
        }
    },
);

// ONLY FOR TESTING
const lsd_cube_node_i = graphvm.NodeI.implement(
    .{
        .name = "LSD cube",
        .type_name = public.LSD_CUBE_NODE_TYPE_STR,
        .category = "Renderer",
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{});
        }

        pub fn getOutputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{
                graphvm.NodePin.init("GPU geometry", graphvm.NodePin.pinHash("gpu_geometry", true), public.PinTypes.GPU_GEOMETRY, null),
                graphvm.NodePin.init("GPU index buffer", graphvm.NodePin.pinHash("gpu_index_buffer", true), public.PinTypes.GPU_INDEX_BUFFER, null),
            });
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool) !void {
            _ = self; // autofix
            _ = state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = in_pins; // autofix
            var g: public.GPUGeometry = .{};
            g.vb[0] = _g.cube_pos_vb;
            g.vb[1] = _g.cube_col_vb;

            try out_pins.writeTyped(public.GPUGeometry, 0, try gpu_geometry_value_type_i.calcValidityHash(&std.mem.toBytes(g)), g);
            try out_pins.writeTyped(gpu.IndexBufferHandle, 1, try gpu_index_buffer_value_type_i.calcValidityHash(&std.mem.toBytes(_g.cube_ib)), _g.cube_ib);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

// TMP SHIT
//
// Vertex layout definiton
//
const PosVertex = struct {
    x: f32,
    y: f32,
    z: f32,

    fn init(x: f32, y: f32, z: f32) PosVertex {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    fn layoutInit() gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = _gpu.layoutBegin(&L.posColorLayout, gpu.Backend.noop);
        _ = _gpu.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 3, gpu.AttribType.Float, false, false);
        //_ = _gpu.layoutAdd(&L.posColorLayout, gpu.Attrib.Color0, 4, gpu.AttribType.Uint8, true, false);
        _gpu.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};

const ColorVertex = struct {
    abgr: u32,

    fn init(abgr: u32) ColorVertex {
        return .{
            .abgr = abgr,
        };
    }

    fn layoutInit() gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = _gpu.layoutBegin(&L.posColorLayout, gpu.Backend.noop);
        //_ = _gpu.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 3, gpu.AttribType.Float, false, false);
        _ = _gpu.layoutAdd(&L.posColorLayout, gpu.Attrib.Color0, 4, gpu.AttribType.Uint8, true, false);
        _gpu.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};

const cube_positions = [_]PosVertex{
    .init(-1.0, 1.0, 1.0),
    .init(1.0, 1.0, 1.0),
    .init(-1.0, -1.0, 1.0),
    .init(1.0, -1.0, 1.0),
    .init(-1.0, 1.0, -1.0),
    .init(1.0, 1.0, -1.0),
    .init(-1.0, -1.0, -1.0),
    .init(1.0, -1.0, -1.0),
};

const cube_cololrs = [_]ColorVertex{
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffffff),
};

const cube_tri_list = [_]u16{
    0, 1, 2, // 0
    1, 3, 2,
    4, 6, 5, // 2
    5, 6, 7,
    0, 2, 4, // 4
    4, 2, 6,
    1, 5, 3, // 6
    5, 7, 3,
    0, 4, 1, // 8
    4, 5, 1,
    2, 3, 6, // 10
    6, 3, 7,
};

var _vertex_pos_layout: gpu.VertexLayout = undefined;
var _vertex_col_layout: gpu.VertexLayout = undefined;
//

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // GPUGeometryCdb
        {
            const type_idx = try _cdb.addType(
                db,
                public.GPUGeometryCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.GPUGeometryCdb.propIdx(.handle0),
                        .name = "handle0",
                        .type = cdb.PropType.U32,
                    },
                    .{
                        .prop_idx = public.GPUGeometryCdb.propIdx(.handle1),
                        .name = "handle1",
                        .type = cdb.PropType.U32,
                    },
                    .{
                        .prop_idx = public.GPUGeometryCdb.propIdx(.handle2),
                        .name = "handle2",
                        .type = cdb.PropType.U32,
                    },
                    .{
                        .prop_idx = public.GPUGeometryCdb.propIdx(.handle3),
                        .name = "handle3",
                        .type = cdb.PropType.U32,
                    },
                },
            );
            _ = type_idx; // autofix
        }

        // GPUIndexBufferCdb
        {
            const type_idx = try _cdb.addType(
                db,
                public.GPUIndexBufferCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.GPUIndexBufferCdb.propIdx(.handle),
                        .name = "handle",
                        .type = cdb.PropType.U32,
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
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _metrics = apidb.getZigApi(module_name, cetech1.metrics.MetricsAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;

    // create global variable that can survive reload
    _g = try _apidb.globalVar(G, module_name, "_g", .{});

    // register apis
    try apidb.setOrRemoveZigApi(module_name, public.RendererApi, &api, load);
    try apidb.setOrRemoveZigApi(module_name, public.RenderGraphApi, &graph_api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelRenderI, &_kernel_render_task, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &culling_volume_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &draw_call_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &lsd_cube_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_geometry_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_index_buffer_value_type_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_renderer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}