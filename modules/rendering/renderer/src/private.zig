const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

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

    bunny_pos_vb: gpu.VertexBufferHandle = .{},
    bunny_col_vb: gpu.VertexBufferHandle = .{},
    bunny_ib: gpu.IndexBufferHandle = .{},

    time_system: shader_system.SystemInstance = undefined,
};

var _g: *G = undefined;

const CullingSystem = struct {
    const Self = @This();

    const RequestPool = cetech1.heap.PoolWithLock(public.CullingRequest);
    const RequestMap = cetech1.AutoArrayHashMap(*const anyopaque, *public.CullingRequest);

    const ResultPool = cetech1.heap.PoolWithLock(public.CullingResult);
    const ResultMap = cetech1.AutoArrayHashMap(*const anyopaque, *public.CullingResult);

    allocator: std.mem.Allocator,

    crq_pool: RequestPool,
    crq_map: RequestMap = .{},

    cr_pool: ResultPool,
    cr_map: ResultMap = .{},

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
        for (self.crq_map.values()) |value| {
            value.deinit();
        }

        for (self.cr_map.values()) |value| {
            value.deinit();
        }

        self.crq_map.deinit(self.allocator);
        self.crq_pool.deinit();

        self.cr_map.deinit(self.allocator);
        self.cr_pool.deinit();

        self.tasks.deinit(self.allocator);
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
        try self.crq_map.put(self.allocator, rq_type, rq);

        const rs = try self.cr_pool.create();
        rs.* = public.CullingResult.init(self.allocator);
        try self.cr_map.put(self.allocator, rq_type, rs);

        return rq;
    }

    pub fn getResult(self: *Self, rq_type: *const anyopaque) *public.CullingResult {
        return self.cr_map.get(rq_type).?;
    }

    pub fn doCulling(self: *Self, allocator: std.mem.Allocator, builder: public.GraphBuilder, viewers: []const public.Viewer) !void {
        // var zone = _profiler.ZoneN(@src(), "doCulling");
        // defer zone.End();

        //TODO for all viewer
        const mtx = zm.mul(zm.matFromArr(viewers[0].mtx), zm.matFromArr(viewers[0].proj));
        const frustrum_planes = cetech1.math.buildFrustumPlanes(zm.matToArr(mtx));

        self.tasks.clearRetainingCapacity();

        for (self.crq_map.keys(), self.crq_map.values()) |k, value| {
            const result = self.getResult(k);

            try result.appendMany(value.no_culling_mtx.items, value.no_culling_renderables.items);

            const items_count = value.volumes.items.len;
            if (items_count == 0) continue;

            const ARGS = struct {
                rq: *public.CullingRequest,
                result: *public.CullingResult,
                frustrum: *const cetech1.math.FrustrumPlanes,
                builder: public.GraphBuilder,
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
                    .frustrum = &frustrum_planes,
                    .builder = builder,
                    .draw_culling_debug = self.draw_culling_debug,
                },
                struct {
                    pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) CullingTask {
                        const rq = create_args.rq;

                        return CullingTask{
                            .count = count,
                            .frustrum = create_args.frustrum,
                            .result = create_args.result,
                            .renderable_size = rq.renderable_size,
                            .builder = create_args.builder,
                            .draw_culling_debug = create_args.draw_culling_debug,

                            .transforms = rq.mtx.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                            .components_data = rq.renderables.items[batch_id * args.batch_size * rq.renderable_size .. ((batch_id * args.batch_size * rq.renderable_size) + count * rq.renderable_size)],
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
    }
};

const Viewport = struct {
    name: [:0]u8,
    fb: gpu.FrameBufferHandle = .{},
    size: [2]f32 = .{ 0, 0 },
    new_size: [2]f32 = .{ 0, 0 },
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

    renderable_size: usize,
    result: *public.CullingResult,
    frustrum: *const cetech1.math.FrustrumPlanes,

    builder: public.GraphBuilder,
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
            for (self.volumes, 0..) |culling_volume, i| {
                if (culling_volume.hasSphere()) {
                    var center = [3]f32{ 0, 0, 0 };
                    const mat = self.transforms[i].mtx;
                    const origin = zm.mul(zm.loadArr4(.{ 0, 0, 0, 1 }), mat);
                    zm.storeArr3(&center, origin);

                    if (cetech1.math.frustumPlanesVsSphere(self.frustrum.*, center, culling_volume.radius)) {
                        try self.result.append(
                            self.transforms[i],
                            self.components_data[i * self.renderable_size .. (i * self.renderable_size) + self.renderable_size],
                        );

                        if (self.draw_culling_debug) {
                            var zzz = _profiler.ZoneN(@src(), "debugdraw");
                            defer zzz.End();

                            dd.pushTransform(@ptrCast(&mat));
                            defer dd.popTransform();

                            dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);

                            if (culling_volume.hasSphere()) {
                                dd.drawCircleAxis(.X, .{ 0, 0, 0 }, culling_volume.radius, 0);
                                dd.drawCircleAxis(.Y, .{ 0, 0, 0 }, culling_volume.radius, 0);
                                dd.drawCircleAxis(.Z, .{ 0, 0, 0 }, culling_volume.radius, 0);
                            }

                            if (culling_volume.hasBox()) {
                                dd.setWireframe(true);
                                dd.drawAABB(culling_volume.min, culling_volume.max);
                                dd.setWireframe(false);
                            }
                        }
                    }
                }
            }
        }
    }
};

const ModulePassList = cetech1.ArrayList(ModuleOrPass);
const PassList = cetech1.ArrayList(*public.Pass);

const PassInfoMap = cetech1.AutoArrayHashMap(*public.Pass, PassInfo);
const ResourceSet = cetech1.AutoArrayHashMap(public.ResourceId, void);
const TextureInfoMap = cetech1.AutoArrayHashMap(public.ResourceId, public.TextureInfo);
const TextureMap = cetech1.AutoArrayHashMap(public.ResourceId, gpu.TextureHandle);
const CreatedTextureMap = cetech1.AutoArrayHashMap(CreatedTextureKey, CreatedTextureInfo);
const TextureList = cetech1.ArrayList(gpu.TextureHandle);
const PassSet = cetech1.AutoArrayHashMap(*public.Pass, void);
const ResourceInfoMap = cetech1.AutoArrayHashMap(public.ResourceId, ResourceInfo);
const LayerMap = cetech1.AutoArrayHashMap(cetech1.StrId32, gpu.ViewId);

const ResourceInfo = struct {
    name: []const u8,
    create: ?*public.Pass = null,
    writes: PassSet = .{},
    reads: PassSet = .{},

    pub fn init(name: []const u8) ResourceInfo {
        return .{
            .name = name,
        };
    }

    pub fn deinit(self: *ResourceInfo, allocator: std.mem.Allocator) void {
        self.writes.deinit(allocator);
        self.reads.deinit(allocator);
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

    write_texture: ResourceSet = .{},
    read_texture: ResourceSet = .{},
    create_texture: TextureInfoMap = .{},

    viewid: gpu.ViewId = 0,
    clear_stencil: ?u8 = null,
    clear_depth: ?f32 = null,

    exported_layer: ?cetech1.StrId32 = null,

    fb: ?gpu.FrameBufferHandle = null,

    pub fn deinit(self: *PassInfo, allocator: std.mem.Allocator) void {
        self.write_texture.deinit(allocator);
        self.create_texture.deinit(allocator);
        self.read_texture.deinit(allocator);

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

const ViewersList = cetech1.ArrayList(public.Viewer);

const GraphBuilder = struct {
    allocator: std.mem.Allocator,
    rg: *Graph,

    passinfo_map: PassInfoMap = .{},
    texture_map: TextureMap = .{},

    passes: PassList = .{},
    viewport: public.Viewport,
    layer_map: LayerMap = .{},

    resource_deps: ResourceInfoMap = .{},

    dag: dag.DAG(*public.Pass),

    viewers: ViewersList = .{},

    pub fn init(allocator: std.mem.Allocator, rg: *Graph, viewport: public.Viewport) GraphBuilder {
        return .{
            .allocator = allocator,
            .rg = rg,
            .viewport = viewport,
            .dag = dag.DAG(*public.Pass).init(allocator),
        };
    }

    pub fn deinit(self: *GraphBuilder) void {
        for (self.passinfo_map.values()) |*info| {
            info.deinit(self.allocator);
        }

        for (self.resource_deps.values()) |*set| {
            set.deinit(self.allocator);
        }

        self.layer_map.deinit(self.allocator);
        self.passes.deinit(self.allocator);
        self.passinfo_map.deinit(self.allocator);
        self.texture_map.deinit(self.allocator);
        self.dag.deinit();
        self.resource_deps.deinit(self.allocator);
    }

    pub fn addPass(self: *GraphBuilder, name: []const u8, pass: *public.Pass) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.name = name;
        try self.passes.append(self.allocator, pass);
    }

    pub fn exportLayer(self: *GraphBuilder, pass: *public.Pass, name: []const u8) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.exported_layer = cetech1.strId32(name);
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

        const texture_id = cetech1.strId32(texture);
        try pass_info.create_texture.put(self.allocator, texture_id, info);

        if (info.clear_depth) |depth| {
            pass_info.clear_depth = depth;
        }

        try self.writeTexture(pass, texture);

        const deps = try self.getOrCreateResourceDeps(texture);
        deps.create = pass;
    }

    pub fn writeTexture(self: *GraphBuilder, pass: *public.Pass, texture: []const u8) !void {
        const info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strId32(texture);

        try info.write_texture.put(self.allocator, texture_id, {});
        const deps = try self.getOrCreateResourceDeps(texture);
        try deps.writes.put(self.allocator, pass, {});
    }

    pub fn readTexture(self: *GraphBuilder, pass: *public.Pass, texture: []const u8) !void {
        const info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strId32(texture);

        try info.read_texture.put(self.allocator, texture_id, {});
        const deps = try self.getOrCreateResourceDeps(texture);
        try deps.reads.put(self.allocator, pass, {});
    }

    pub fn getTexture(self: *GraphBuilder, texture: []const u8) ?gpu.TextureHandle {
        return self.texture_map.get(cetech1.strId32(texture));
    }

    pub fn getLayer(self: *GraphBuilder, layer: []const u8) gpu.ViewId {
        return self.layer_map.get(cetech1.strId32(layer)) orelse 256;
    }

    pub fn getLayerById(self: *GraphBuilder, layer: cetech1.StrId32) gpu.ViewId {
        return self.layer_map.get(layer) orelse 256;
    }

    pub fn importTexture(self: *GraphBuilder, texture_name: []const u8, texture: gpu.TextureHandle) !void {
        try self.texture_map.put(self.allocator, cetech1.strId32(texture_name), texture);
    }

    fn getOrCreateResourceDeps(self: *GraphBuilder, texture_name: []const u8) !*ResourceInfo {
        const texture_id = cetech1.strId32(texture_name);

        const result = try self.resource_deps.getOrPut(self.allocator, texture_id);
        if (!result.found_existing) {
            result.value_ptr.* = ResourceInfo.init(texture_name);
        }

        return result.value_ptr;
    }

    pub fn compile(self: *GraphBuilder) !void {
        // Create DAG for pass
        for (self.passes.items) |pass| {
            const info = self.passinfo_map.getPtr(pass) orelse return error.InvalidPass;

            var depends = cetech1.ArrayList(*public.Pass){};
            defer depends.deinit(self.allocator);

            for (info.write_texture.keys()) |texture| {
                const texture_deps = self.resource_deps.get(texture).?;
                if (texture_deps.create) |create_pass| {
                    if (create_pass == pass) continue;

                    try depends.append(self.allocator, create_pass);
                }
            }

            for (info.read_texture.keys()) |texture| {
                const texture_deps = self.resource_deps.get(texture).?;

                try depends.appendSlice(self.allocator, texture_deps.writes.keys());

                if (texture_deps.create) |create_pass| {
                    if (create_pass == pass) continue;

                    try depends.append(self.allocator, create_pass);
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
                try self.layer_map.put(self.allocator, layer, viewid);
            }

            if (info.needFb()) {
                var clear_flags: gpu.ClearFlags = gpu.ClearFlags_None;
                var clear_colors: [8]u8 = .{std.math.maxInt(u8)} ** 8;

                var textures = cetech1.ArrayList(gpu.TextureHandle){};
                defer textures.deinit(self.allocator);

                for (info.create_texture.keys(), info.create_texture.values()) |k, v| {
                    const texture_deps = self.resource_deps.get(k).?;

                    const t = try self.rg.createTexture2D(self.viewport, texture_deps.name, v);
                    try self.texture_map.put(self.allocator, k, t);
                }

                for (info.write_texture.keys(), 0..) |write, idx| {
                    try textures.append(self.allocator, self.texture_map.get(write).?);

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
        const result = try self.passinfo_map.getOrPut(self.allocator, pass);

        if (!result.found_existing) {
            result.value_ptr.* = .{};
        }

        return result.value_ptr;
    }
};

const Module = struct {
    allocator: std.mem.Allocator,
    passes: ModulePassList = .{},

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        for (self.passes.items) |pass_or_module| {
            switch (pass_or_module) {
                .module => |module| module.deinit(),
                .pass => continue,
            }
        }

        self.passes.deinit(self.allocator);
    }

    pub fn addPass(self: *Module, pass: public.Pass) !void {
        try self.passes.append(self.allocator, .{ .pass = pass });
    }

    pub fn addModule(self: *Module, module: public.Module) !void {
        try self.passes.append(self.allocator, .{ .module = @alignCast(@ptrCast(module.ptr)) });
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

const ModulePool = cetech1.heap.PoolWithLock(Module);
const BuilderPool = cetech1.heap.PoolWithLock(GraphBuilder);

const Graph = struct {
    allocator: std.mem.Allocator,
    module_pool: ModulePool,
    builder_pool: BuilderPool,
    module: Module,

    created_texture: CreatedTextureMap = .{},
    created_texture_lck: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{
            .allocator = allocator,
            .module_pool = ModulePool.init(allocator),
            .builder_pool = BuilderPool.init(allocator),
            .module = Module.init(allocator),
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.created_texture.values()) |texture| {
            _gpu.destroyTexture(texture.handler);
        }

        self.module.deinit();
        self.module_pool.deinit();
        self.builder_pool.deinit();
        self.created_texture.deinit(self.allocator);
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
        const texture_id = cetech1.strId32(texture_name);

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
        {
            self.created_texture_lck.lock();
            defer self.created_texture_lck.unlock();
            try self.created_texture.put(
                self.allocator,
                .{ .name = texture_id, .viewport = viewport },
                .{
                    .handler = t,
                    .info = info,
                    .size = size,
                },
            );
        }
        return t;
    }
};

const GraphPool = cetech1.heap.PoolWithLock(Graph);
const GraphSet = cetech1.AutoArrayHashMap(*Graph, void);

const ViewportPool = cetech1.heap.PoolWithLock(Viewport);
const ViewportSet = cetech1.AutoArrayHashMap(*Viewport, void);
const PalletColorMap = cetech1.AutoArrayHashMap(u32, u8);

var kernel_render_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "RenderFrame",
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

fn createViewport(name: [:0]const u8, rg: public.Graph, world: ?ecs.World, camera_ent: ecs.EntityId) !public.Viewport {
    const new_viewport = try _g.viewport_pool.create();

    const dupe_name = try _allocator.dupeZ(u8, name);

    var buf: [128]u8 = undefined;

    new_viewport.* = .{
        .name = dupe_name,
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

    try _g.viewport_set.put(_allocator, new_viewport, {});
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

    pub fn getDebugCulling(viewport: *anyopaque) bool {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        return true_viewport.culling.draw_culling_debug;
    }
    pub fn setDebugCulling(viewport: *anyopaque, enable: bool) void {
        const true_viewport: *Viewport = @alignCast(@ptrCast(viewport));
        true_viewport.culling.draw_culling_debug = enable;
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

        var viewers = ViewersList{};
        defer viewers.deinit(allocator);

        var enabled_systems = shader_system.SystemSet.initEmpty();
        enabled_systems.set(_shader.getSystemIdx(cetech1.strId32("viewer_system")));
        enabled_systems.set(_shader.getSystemIdx(cetech1.strId32("time_system")));

        if (s.viewport.world) |world| {
            var renderables = cetech1.ArrayList(Renderables){};
            defer renderables.deinit(allocator);

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
                            .context = cetech1.strId32("viewport"),
                        };

                        if (s.viewport.main_camera_entity != null and s.viewport.main_camera_entity.? == entities[idx]) {
                            try viewers.insert(allocator, 0, v);
                        } else {
                            try viewers.append(allocator, v);
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
                    try renderables.append(allocator, renderable);

                    const cr = try s.viewport.culling.getRequest(iface, iface.size);

                    if (iface.culling) |culling| {
                        var zz = _profiler.ZoneN(@src(), "RenderViewport - Culling calback");
                        defer zz.End();

                        _ = try culling(allocator, builder, world, viewers.items, cr);
                    }

                    s.viewport.all_renderables_counter.* += @floatFromInt(cr.mtx.items.len);
                }
            }

            // Culling
            {
                var z = _profiler.ZoneN(@src(), "RenderViewport - Culling phase");
                defer z.End();

                const counter = cetech1.metrics.MetricScopedDuration.begin(s.viewport.culling_duration);
                defer counter.end();

                try s.viewport.culling.doCulling(allocator, builder, viewers.items);
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
                        try renderable.iface.render(
                            allocator,
                            builder,
                            world,
                            vp,
                            viewers.items,
                            enabled_systems,
                            result.mtx.items,
                            result.renderables.items,
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

        if (false) {
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
        try _g.rg_set.put(_allocator, new_rg, {});
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
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            _g.viewport_set = .{};
            _g.viewport_pool = ViewportPool.init(_allocator);

            _g.rg_set = .{};
            _g.rg_pool = GraphPool.init(_allocator);
            _g.rg_lock = std.Thread.Mutex{};

            _g.time_system = try _shader.createSystemInstance(cetech1.strId32("time_system"));

            _vertex_pos_layout = PosVertex.layoutInit();
            _vertex_col_layout = ColorVertex.layoutInit();

            // Cube
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

            // Bunny
            _g.bunny_pos_vb = _gpu.createVertexBuffer(
                _gpu.makeRef(&bunny_position, bunny_position.len * @sizeOf(PosVertex)),
                &_vertex_pos_layout,
                gpu.BufferFlags_None,
            );
            _g.bunny_col_vb = _gpu.createVertexBuffer(
                _gpu.makeRef(&bunny_colors, bunny_colors.len * @sizeOf(ColorVertex)),
                &_vertex_col_layout,
                gpu.BufferFlags_None,
            );
            _g.bunny_ib = _gpu.createIndexBuffer(
                _gpu.makeRef(&bunny_tri_list, bunny_tri_list.len * @sizeOf(u16)),
                gpu.BufferFlags_None,
            );
        }

        pub fn shutdown() !void {
            _g.viewport_set.deinit(_allocator);
            _g.viewport_pool.deinit();

            _g.rg_set.deinit(_allocator);
            _g.rg_pool.deinit();

            _shader.destroySystemInstance(&_g.time_system);

            _gpu.destroyIndexBuffer(_g.cube_ib);
            _gpu.destroyVertexBuffer(_g.cube_pos_vb);
            _gpu.destroyVertexBuffer(_g.cube_col_vb);

            _gpu.destroyVertexBuffer(_g.bunny_pos_vb);
            _gpu.destroyVertexBuffer(_g.bunny_ib);
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
            return cetech1.strId64(value).id;
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

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Radius", graphvm.NodePin.pinHash("radius", false), graphvm.PinTypes.F32, null),
                    graphvm.NodePin.init("Min", graphvm.NodePin.pinHash("min", false), graphvm.PinTypes.VEC3F, null),
                    graphvm.NodePin.init("Max", graphvm.NodePin.pinHash("max", false), graphvm.PinTypes.VEC3F, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{}),
            };
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

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("GPU shader", graphvm.NodePin.pinHash("gpu_shader", false), shader_system.PinTypes.GPU_SHADER, null),
                    graphvm.NodePin.init("GPU geometry", graphvm.NodePin.pinHash("gpu_geometry", false), public.PinTypes.GPU_GEOMETRY, null),
                    graphvm.NodePin.init("GPU index buffer", graphvm.NodePin.pinHash("gpu_index_buffer", false), public.PinTypes.GPU_INDEX_BUFFER, null),
                    graphvm.NodePin.init("Vertex count", graphvm.NodePin.pinHash("vertex_count", false), graphvm.PinTypes.U32, null),
                    graphvm.NodePin.init("Index count", graphvm.NodePin.pinHash("index_count", false), graphvm.PinTypes.U32, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{}),
            };
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

// TODO: Move
const simple_mesh_node_i = graphvm.NodeI.implement(
    .{
        .name = "Simple mesh",
        .type_name = public.SIMPLE_MESH_NODE_TYPE_STR,
        .category = "Renderer",
        .settings_type = public.SimpleMeshNodeSettings.type_hash,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("GPU geometry", graphvm.NodePin.pinHash("gpu_geometry", true), public.PinTypes.GPU_GEOMETRY, null),
                    graphvm.NodePin.init("GPU index buffer", graphvm.NodePin.pinHash("gpu_index_buffer", true), public.PinTypes.GPU_INDEX_BUFFER, null),
                    graphvm.NodePin.init("Vertex count", graphvm.NodePin.pinHash("vertex_count", true), graphvm.PinTypes.U32, null),
                    graphvm.NodePin.init("Index count", graphvm.NodePin.pinHash("index_count", true), graphvm.PinTypes.U32, null),
                }),
            };
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
            _ = in_pins; // autofix

            const settings_r = public.SimpleMeshNodeSettings.read(_cdb, args.settings.?).?;

            const type_str = public.SimpleMeshNodeSettings.readStr(_cdb, settings_r, .type) orelse "cube";
            const type_enum = std.meta.stringToEnum(public.SimpleMeshNodeType, type_str).?;

            var g: public.GPUGeometry = .{};

            switch (type_enum) {
                .cube => {
                    g.vb[0] = _g.cube_pos_vb;
                    g.vb[1] = _g.cube_col_vb;
                    try out_pins.writeTyped(public.GPUGeometry, 0, try gpu_geometry_value_type_i.calcValidityHash(&std.mem.toBytes(g)), g);
                    try out_pins.writeTyped(gpu.IndexBufferHandle, 1, try gpu_index_buffer_value_type_i.calcValidityHash(&std.mem.toBytes(_g.cube_ib)), _g.cube_ib);
                    try out_pins.writeTyped(u32, 2, 8, 8);
                    try out_pins.writeTyped(u32, 3, 36, 36);
                },

                .bunny => {
                    g.vb[0] = _g.bunny_pos_vb;
                    g.vb[1] = _g.bunny_col_vb;
                    try out_pins.writeTyped(public.GPUGeometry, 0, try gpu_geometry_value_type_i.calcValidityHash(&std.mem.toBytes(g)), g);
                    try out_pins.writeTyped(gpu.IndexBufferHandle, 1, try gpu_index_buffer_value_type_i.calcValidityHash(&std.mem.toBytes(_g.bunny_ib)), _g.bunny_ib);
                    try out_pins.writeTyped(u32, 2, bunny_position.len, bunny_position.len);
                    try out_pins.writeTyped(u32, 3, bunny_tri_list.len, bunny_tri_list.len);
                },
            }
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

//
// CUBE
//
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

//
// Bunny
//
const bunny_scale = 0.02;
const bunny_position = [_]PosVertex{
    .{ .x = 25.0883 * bunny_scale, .y = -44.2788 * bunny_scale, .z = 31.0055 * bunny_scale },
    .{ .x = 0.945623 * bunny_scale, .y = 53.5504 * bunny_scale, .z = -24.6146 * bunny_scale },
    .{ .x = -0.94455 * bunny_scale, .y = -14.3443 * bunny_scale, .z = -16.8223 * bunny_scale },
    .{ .x = -20.1103 * bunny_scale, .y = -48.6664 * bunny_scale, .z = 12.6763 * bunny_scale },
    .{ .x = -1.60652 * bunny_scale, .y = -26.3165 * bunny_scale, .z = -24.5424 * bunny_scale },
    .{ .x = -30.6284 * bunny_scale, .y = -53.6299 * bunny_scale, .z = 14.7666 * bunny_scale },
    .{ .x = 1.69145 * bunny_scale, .y = -43.8075 * bunny_scale, .z = -15.2065 * bunny_scale },
    .{ .x = -20.5139 * bunny_scale, .y = 21.0521 * bunny_scale, .z = -5.40868 * bunny_scale },
    .{ .x = -13.9518 * bunny_scale, .y = 53.6299 * bunny_scale, .z = -39.1193 * bunny_scale },
    .{ .x = -21.7912 * bunny_scale, .y = 48.7801 * bunny_scale, .z = -42.0995 * bunny_scale },
    .{ .x = -26.8408 * bunny_scale, .y = 23.6537 * bunny_scale, .z = -17.7324 * bunny_scale },
    .{ .x = -23.1196 * bunny_scale, .y = 33.9692 * bunny_scale, .z = 4.91483 * bunny_scale },
    .{ .x = -12.3236 * bunny_scale, .y = -41.6303 * bunny_scale, .z = 31.8324 * bunny_scale },
    .{ .x = 27.6427 * bunny_scale, .y = -5.05034 * bunny_scale, .z = -11.3201 * bunny_scale },
    .{ .x = 32.2565 * bunny_scale, .y = 1.30521 * bunny_scale, .z = 30.2671 * bunny_scale },
    .{ .x = 47.2723 * bunny_scale, .y = -27.0974 * bunny_scale, .z = 11.1774 * bunny_scale },
    .{ .x = 33.598 * bunny_scale, .y = 10.5888 * bunny_scale, .z = 7.95916 * bunny_scale },
    .{ .x = -13.2898 * bunny_scale, .y = 12.6234 * bunny_scale, .z = 5.55953 * bunny_scale },
    .{ .x = -32.7364 * bunny_scale, .y = 19.0648 * bunny_scale, .z = -10.5736 * bunny_scale },
    .{ .x = -32.7536 * bunny_scale, .y = 31.4158 * bunny_scale, .z = -1.40712 * bunny_scale },
    .{ .x = -25.3672 * bunny_scale, .y = 30.2874 * bunny_scale, .z = -12.4682 * bunny_scale },
    .{ .x = 32.921 * bunny_scale, .y = -36.8408 * bunny_scale, .z = -12.0254 * bunny_scale },
    .{ .x = -37.7251 * bunny_scale, .y = -33.8989 * bunny_scale, .z = 0.378443 * bunny_scale },
    .{ .x = -35.6341 * bunny_scale, .y = -0.246891 * bunny_scale, .z = -9.25165 * bunny_scale },
    .{ .x = -16.7041 * bunny_scale, .y = -50.0254 * bunny_scale, .z = -15.6177 * bunny_scale },
    .{ .x = 24.6604 * bunny_scale, .y = -53.5319 * bunny_scale, .z = -11.1059 * bunny_scale },
    .{ .x = -7.77574 * bunny_scale, .y = -53.5719 * bunny_scale, .z = -16.6655 * bunny_scale },
    .{ .x = 20.6241 * bunny_scale, .y = 13.3489 * bunny_scale, .z = 0.376349 * bunny_scale },
    .{ .x = -44.2889 * bunny_scale, .y = 29.5222 * bunny_scale, .z = 18.7918 * bunny_scale },
    .{ .x = 18.5805 * bunny_scale, .y = 16.3651 * bunny_scale, .z = 12.6351 * bunny_scale },
    .{ .x = -23.7853 * bunny_scale, .y = 31.7598 * bunny_scale, .z = -6.54093 * bunny_scale },
    .{ .x = 24.7518 * bunny_scale, .y = -53.5075 * bunny_scale, .z = 2.14984 * bunny_scale },
    .{ .x = -45.7912 * bunny_scale, .y = -17.6301 * bunny_scale, .z = 21.1198 * bunny_scale },
    .{ .x = 51.8403 * bunny_scale, .y = -33.1847 * bunny_scale, .z = 24.3337 * bunny_scale },
    .{ .x = -47.5343 * bunny_scale, .y = -4.32792 * bunny_scale, .z = 4.06232 * bunny_scale },
    .{ .x = -50.6832 * bunny_scale, .y = -12.442 * bunny_scale, .z = 11.0994 * bunny_scale },
    .{ .x = -49.5132 * bunny_scale, .y = 19.2782 * bunny_scale, .z = 3.17559 * bunny_scale },
    .{ .x = -39.4881 * bunny_scale, .y = 29.0208 * bunny_scale, .z = -6.70431 * bunny_scale },
    .{ .x = -52.7286 * bunny_scale, .y = 1.23232 * bunny_scale, .z = 9.74872 * bunny_scale },
    .{ .x = 26.505 * bunny_scale, .y = -16.1297 * bunny_scale, .z = -17.0487 * bunny_scale },
    .{ .x = -25.367 * bunny_scale, .y = 20.0473 * bunny_scale, .z = -8.44282 * bunny_scale },
    .{ .x = -24.5797 * bunny_scale, .y = -10.3143 * bunny_scale, .z = -18.3154 * bunny_scale },
    .{ .x = -28.6707 * bunny_scale, .y = 6.12074 * bunny_scale, .z = 27.8025 * bunny_scale },
    .{ .x = -16.9868 * bunny_scale, .y = 22.6819 * bunny_scale, .z = 1.37408 * bunny_scale },
    .{ .x = -37.2678 * bunny_scale, .y = 23.9443 * bunny_scale, .z = -9.4945 * bunny_scale },
    .{ .x = -24.8562 * bunny_scale, .y = 21.3763 * bunny_scale, .z = 18.8847 * bunny_scale },
    .{ .x = -47.1879 * bunny_scale, .y = 3.8542 * bunny_scale, .z = -4.74621 * bunny_scale },
    .{ .x = 38.0706 * bunny_scale, .y = -7.33673 * bunny_scale, .z = -7.6099 * bunny_scale },
    .{ .x = -34.8833 * bunny_scale, .y = -3.57074 * bunny_scale, .z = 26.4838 * bunny_scale },
    .{ .x = 12.3797 * bunny_scale, .y = 5.46782 * bunny_scale, .z = 32.9762 * bunny_scale },
    .{ .x = -31.5974 * bunny_scale, .y = -22.956 * bunny_scale, .z = 30.5827 * bunny_scale },
    .{ .x = -6.80953 * bunny_scale, .y = 48.055 * bunny_scale, .z = -18.5116 * bunny_scale },
    .{ .x = 6.3474 * bunny_scale, .y = -15.1622 * bunny_scale, .z = -24.4726 * bunny_scale },
    .{ .x = -25.5733 * bunny_scale, .y = 25.2452 * bunny_scale, .z = -34.4736 * bunny_scale },
    .{ .x = -23.8955 * bunny_scale, .y = 31.8323 * bunny_scale, .z = -40.8696 * bunny_scale },
    .{ .x = -11.8622 * bunny_scale, .y = 38.2304 * bunny_scale, .z = -43.3125 * bunny_scale },
    .{ .x = -20.4918 * bunny_scale, .y = 41.2409 * bunny_scale, .z = -3.11271 * bunny_scale },
    .{ .x = 24.9806 * bunny_scale, .y = -8.53455 * bunny_scale, .z = 37.2862 * bunny_scale },
    .{ .x = -52.8935 * bunny_scale, .y = 5.3376 * bunny_scale, .z = 28.246 * bunny_scale },
    .{ .x = 34.106 * bunny_scale, .y = -41.7941 * bunny_scale, .z = 30.962 * bunny_scale },
    .{ .x = -1.26914 * bunny_scale, .y = 35.6664 * bunny_scale, .z = -18.7177 * bunny_scale },
    .{ .x = -0.13048 * bunny_scale, .y = 44.7288 * bunny_scale, .z = -28.7163 * bunny_scale },
    .{ .x = 2.47929 * bunny_scale, .y = 0.678165 * bunny_scale, .z = -14.6892 * bunny_scale },
    .{ .x = -31.8649 * bunny_scale, .y = -14.2299 * bunny_scale, .z = 32.2998 * bunny_scale },
    .{ .x = -19.774 * bunny_scale, .y = 30.8258 * bunny_scale, .z = 5.77293 * bunny_scale },
    .{ .x = 49.8059 * bunny_scale, .y = -37.125 * bunny_scale, .z = 4.97284 * bunny_scale },
    .{ .x = -28.0581 * bunny_scale, .y = -26.439 * bunny_scale, .z = -14.8316 * bunny_scale },
    .{ .x = -9.12066 * bunny_scale, .y = -27.3987 * bunny_scale, .z = -12.8592 * bunny_scale },
    .{ .x = -13.8752 * bunny_scale, .y = -29.9821 * bunny_scale, .z = 32.5962 * bunny_scale },
    .{ .x = -6.6222 * bunny_scale, .y = -10.9884 * bunny_scale, .z = 33.5007 * bunny_scale },
    .{ .x = -21.2664 * bunny_scale, .y = -53.6089 * bunny_scale, .z = -3.49195 * bunny_scale },
    .{ .x = -0.628672 * bunny_scale, .y = 52.8093 * bunny_scale, .z = -9.88088 * bunny_scale },
    .{ .x = 8.02417 * bunny_scale, .y = 51.8956 * bunny_scale, .z = -21.5834 * bunny_scale },
    .{ .x = -44.6547 * bunny_scale, .y = 11.9973 * bunny_scale, .z = 34.7897 * bunny_scale },
    .{ .x = -7.55466 * bunny_scale, .y = 37.9035 * bunny_scale, .z = -0.574101 * bunny_scale },
    .{ .x = 52.8252 * bunny_scale, .y = -27.1986 * bunny_scale, .z = 11.6429 * bunny_scale },
    .{ .x = -0.934591 * bunny_scale, .y = 9.81861 * bunny_scale, .z = 0.512566 * bunny_scale },
    .{ .x = -3.01043 * bunny_scale, .y = 5.70605 * bunny_scale, .z = 22.0954 * bunny_scale },
    .{ .x = -34.6337 * bunny_scale, .y = 44.5964 * bunny_scale, .z = -31.1713 * bunny_scale },
    .{ .x = -26.9017 * bunny_scale, .y = 35.1991 * bunny_scale, .z = -32.4307 * bunny_scale },
    .{ .x = 15.9884 * bunny_scale, .y = -8.92223 * bunny_scale, .z = -14.7411 * bunny_scale },
    .{ .x = -22.8337 * bunny_scale, .y = -43.458 * bunny_scale, .z = 26.7274 * bunny_scale },
    .{ .x = -31.9864 * bunny_scale, .y = -47.0243 * bunny_scale, .z = 9.36972 * bunny_scale },
    .{ .x = -36.9436 * bunny_scale, .y = 24.1866 * bunny_scale, .z = 29.2521 * bunny_scale },
    .{ .x = -26.5411 * bunny_scale, .y = 29.6549 * bunny_scale, .z = 21.2867 * bunny_scale },
    .{ .x = 33.7644 * bunny_scale, .y = -24.1886 * bunny_scale, .z = -13.8513 * bunny_scale },
    .{ .x = -2.44749 * bunny_scale, .y = -17.0148 * bunny_scale, .z = 41.6617 * bunny_scale },
    .{ .x = -38.364 * bunny_scale, .y = -13.9823 * bunny_scale, .z = -12.5705 * bunny_scale },
    .{ .x = -10.2972 * bunny_scale, .y = -51.6584 * bunny_scale, .z = 38.935 * bunny_scale },
    .{ .x = 1.28109 * bunny_scale, .y = -43.4943 * bunny_scale, .z = 36.6288 * bunny_scale },
    .{ .x = -19.7784 * bunny_scale, .y = -44.0413 * bunny_scale, .z = -4.23994 * bunny_scale },
    .{ .x = 37.0944 * bunny_scale, .y = -53.5479 * bunny_scale, .z = 27.6467 * bunny_scale },
    .{ .x = 24.9642 * bunny_scale, .y = -37.1722 * bunny_scale, .z = 35.7038 * bunny_scale },
    .{ .x = 37.5851 * bunny_scale, .y = 5.64874 * bunny_scale, .z = 21.6702 * bunny_scale },
    .{ .x = -17.4738 * bunny_scale, .y = -53.5734 * bunny_scale, .z = 30.0664 * bunny_scale },
    .{ .x = -8.93088 * bunny_scale, .y = 45.3429 * bunny_scale, .z = -34.4441 * bunny_scale },
    .{ .x = -17.7111 * bunny_scale, .y = -6.5723 * bunny_scale, .z = 29.5162 * bunny_scale },
    .{ .x = 44.0059 * bunny_scale, .y = -17.4408 * bunny_scale, .z = -5.08686 * bunny_scale },
    .{ .x = -46.2534 * bunny_scale, .y = -22.6115 * bunny_scale, .z = 0.702059 * bunny_scale },
    .{ .x = 43.9321 * bunny_scale, .y = -33.8575 * bunny_scale, .z = 4.31819 * bunny_scale },
    .{ .x = 41.6762 * bunny_scale, .y = -7.37115 * bunny_scale, .z = 27.6798 * bunny_scale },
    .{ .x = 8.20276 * bunny_scale, .y = -42.0948 * bunny_scale, .z = -18.0893 * bunny_scale },
    .{ .x = 26.2678 * bunny_scale, .y = -44.6777 * bunny_scale, .z = -10.6835 * bunny_scale },
    .{ .x = 17.709 * bunny_scale, .y = 13.1542 * bunny_scale, .z = 25.1769 * bunny_scale },
    .{ .x = -35.9897 * bunny_scale, .y = 3.92007 * bunny_scale, .z = 35.8198 * bunny_scale },
    .{ .x = -23.9323 * bunny_scale, .y = -37.3142 * bunny_scale, .z = -2.39396 * bunny_scale },
    .{ .x = 5.19169 * bunny_scale, .y = 46.8851 * bunny_scale, .z = -28.7587 * bunny_scale },
    .{ .x = -37.3072 * bunny_scale, .y = -35.0484 * bunny_scale, .z = 16.9719 * bunny_scale },
    .{ .x = 45.0639 * bunny_scale, .y = -28.5255 * bunny_scale, .z = 22.3465 * bunny_scale },
    .{ .x = -34.4175 * bunny_scale, .y = 35.5861 * bunny_scale, .z = -21.7562 * bunny_scale },
    .{ .x = 9.32684 * bunny_scale, .y = -12.6655 * bunny_scale, .z = 42.189 * bunny_scale },
    .{ .x = 1.00938 * bunny_scale, .y = -31.7694 * bunny_scale, .z = 43.1914 * bunny_scale },
    .{ .x = -45.4666 * bunny_scale, .y = -3.71104 * bunny_scale, .z = 19.2248 * bunny_scale },
    .{ .x = -28.7999 * bunny_scale, .y = -50.8481 * bunny_scale, .z = 31.5232 * bunny_scale },
    .{ .x = 35.2212 * bunny_scale, .y = -45.9047 * bunny_scale, .z = 0.199736 * bunny_scale },
    .{ .x = 40.3 * bunny_scale, .y = -53.5889 * bunny_scale, .z = 7.47622 * bunny_scale },
    .{ .x = 29.0515 * bunny_scale, .y = 5.1074 * bunny_scale, .z = -10.002 * bunny_scale },
    .{ .x = 13.4336 * bunny_scale, .y = 4.84341 * bunny_scale, .z = -9.72327 * bunny_scale },
    .{ .x = 11.0617 * bunny_scale, .y = -26.245 * bunny_scale, .z = -24.9471 * bunny_scale },
    .{ .x = -35.6056 * bunny_scale, .y = -51.2531 * bunny_scale, .z = 0.436527 * bunny_scale },
    .{ .x = -10.6863 * bunny_scale, .y = 34.7374 * bunny_scale, .z = -36.7452 * bunny_scale },
    .{ .x = -51.7652 * bunny_scale, .y = 27.4957 * bunny_scale, .z = 7.79363 * bunny_scale },
    .{ .x = -50.1898 * bunny_scale, .y = 18.379 * bunny_scale, .z = 26.3763 * bunny_scale },
    .{ .x = -49.6836 * bunny_scale, .y = -1.32722 * bunny_scale, .z = 26.2828 * bunny_scale },
    .{ .x = 19.0363 * bunny_scale, .y = -16.9114 * bunny_scale, .z = 41.8511 * bunny_scale },
    .{ .x = 32.7141 * bunny_scale, .y = -21.501 * bunny_scale, .z = 36.0025 * bunny_scale },
    .{ .x = 12.5418 * bunny_scale, .y = -28.4244 * bunny_scale, .z = 43.3125 * bunny_scale },
    .{ .x = -19.5634 * bunny_scale, .y = 42.6328 * bunny_scale, .z = -27.0687 * bunny_scale },
    .{ .x = -16.1942 * bunny_scale, .y = 6.55011 * bunny_scale, .z = 19.4066 * bunny_scale },
    .{ .x = 46.9886 * bunny_scale, .y = -18.8482 * bunny_scale, .z = 22.1332 * bunny_scale },
    .{ .x = 45.9697 * bunny_scale, .y = -3.76781 * bunny_scale, .z = 4.10111 * bunny_scale },
    .{ .x = -28.2912 * bunny_scale, .y = 51.3277 * bunny_scale, .z = -35.1815 * bunny_scale },
    .{ .x = -40.2796 * bunny_scale, .y = -27.7518 * bunny_scale, .z = 22.8684 * bunny_scale },
    .{ .x = -22.7984 * bunny_scale, .y = -38.9977 * bunny_scale, .z = 22.158 * bunny_scale },
    .{ .x = 54.0614 * bunny_scale, .y = -35.6096 * bunny_scale, .z = 12.694 * bunny_scale },
    .{ .x = 44.2064 * bunny_scale, .y = -53.6029 * bunny_scale, .z = 18.8679 * bunny_scale },
    .{ .x = 19.789 * bunny_scale, .y = -29.517 * bunny_scale, .z = -19.6094 * bunny_scale },
    .{ .x = -34.3769 * bunny_scale, .y = 34.8566 * bunny_scale, .z = 9.92517 * bunny_scale },
    .{ .x = -23.7518 * bunny_scale, .y = -45.0319 * bunny_scale, .z = 8.71282 * bunny_scale },
    .{ .x = -12.7978 * bunny_scale, .y = 3.55087 * bunny_scale, .z = -13.7108 * bunny_scale },
    .{ .x = -54.0614 * bunny_scale, .y = 8.83831 * bunny_scale, .z = 8.91353 * bunny_scale },
    .{ .x = 16.2986 * bunny_scale, .y = -53.5717 * bunny_scale, .z = 34.065 * bunny_scale },
    .{ .x = -36.6243 * bunny_scale, .y = -53.5079 * bunny_scale, .z = 24.6495 * bunny_scale },
    .{ .x = 16.5794 * bunny_scale, .y = -48.5747 * bunny_scale, .z = 35.5681 * bunny_scale },
    .{ .x = -32.3263 * bunny_scale, .y = 41.4526 * bunny_scale, .z = -18.7388 * bunny_scale },
    .{ .x = -18.8488 * bunny_scale, .y = 9.62627 * bunny_scale, .z = -8.81052 * bunny_scale },
    .{ .x = 5.35849 * bunny_scale, .y = 36.3616 * bunny_scale, .z = -12.9346 * bunny_scale },
    .{ .x = 6.19167 * bunny_scale, .y = 34.497 * bunny_scale, .z = -17.965 * bunny_scale },
};

const bunny_colors = [_]ColorVertex{
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff0000ff),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ff00),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xff00ffff),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff0000),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffff00ff),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffff00),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xffffffff),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff000000),
    .init(0xff0000ff),
};
const bunny_tri_list = [_]u16{
    80,  2,   52,
    0,   143, 92,
    51,  1,   71,
    96,  128, 77,
    67,  2,   41,
    85,  39,  52,
    58,  123, 38,
    99,  21,  114,
    55,  9,   54,
    136, 102, 21,
    3,   133, 81,
    101, 136, 4,
    5,   82,  3,
    6,   90,  24,
    7,   40,  145,
    33,  75,  134,
    55,  8,   9,
    10,  40,  20,
    46,  140, 38,
    74,  64,  11,
    89,  88,  12,
    147, 60,  7,
    47,  116, 13,
    59,  129, 108,
    147, 72,  106,
    33,  108, 75,
    100, 57,  14,
    129, 130, 15,
    32,  35,  112,
    16,  29,  27,
    107, 98,  132,
    130, 116, 47,
    17,  43,  7,
    54,  44,  53,
    46,  34,  23,
    87,  41,  23,
    40,  10,  18,
    8,   131, 9,
    11,  19,  56,
    11,  137, 19,
    19,  20,  30,
    28,  121, 137,
    122, 140, 36,
    15,  130, 97,
    28,  84,  83,
    114, 21,  102,
    87,  98,  22,
    41,  145, 23,
    133, 68,  12,
    90,  70,  24,
    31,  25,  26,
    98,  34,  35,
    16,  27,  116,
    28,  83,  122,
    29,  103, 77,
    40,  30,  20,
    14,  49,  103,
    31,  26,  142,
    78,  9,   131,
    80,  62,  2,
    6,   67,  105,
    32,  48,  63,
    60,  30,  7,
    33,  135, 91,
    116, 130, 16,
    47,  13,  39,
    70,  119, 5,
    24,  26,  6,
    102, 25,  31,
    103, 49,  77,
    16,  130, 93,
    125, 126, 124,
    111, 86,  110,
    4,   52,  2,
    87,  34,  98,
    4,   6,   101,
    29,  76,  27,
    112, 35,  34,
    6,   4,   67,
    72,  1,   106,
    26,  24,  70,
    36,  37,  121,
    81,  113, 142,
    44,  109, 37,
    122, 58,  38,
    96,  48,  128,
    71,  11,  56,
    73,  122, 83,
    52,  39,  80,
    40,  18,  145,
    82,  5,   119,
    10,  20,  120,
    139, 145, 41,
    3,   142, 5,
    76,  117, 27,
    95,  120, 20,
    104, 45,  42,
    128, 43,  17,
    44,  37,  36,
    128, 45,  64,
    143, 111, 126,
    34,  46,  38,
    97,  130, 47,
    142, 91,  115,
    114, 31,  115,
    125, 100, 129,
    48,  96,  63,
    62,  41,  2,
    69,  77,  49,
    133, 50,  68,
    60,  51,  30,
    4,   118, 52,
    53,  55,  54,
    95,  8,   55,
    121, 37,  19,
    65,  75,  99,
    51,  56,  30,
    14,  57,  110,
    58,  122, 73,
    59,  92,  125,
    42,  45,  128,
    49,  14,  110,
    60,  147, 61,
    76,  62,  117,
    69,  49,  86,
    26,  5,   142,
    46,  44,  36,
    63,  50,  132,
    128, 64,  43,
    75,  108, 15,
    134, 75,  65,
    68,  69,  86,
    62,  76,  145,
    142, 141, 91,
    67,  66,  105,
    69,  68,  96,
    119, 70,  90,
    33,  91,  108,
    136, 118, 4,
    56,  51,  71,
    1,   72,  71,
    23,  18,  44,
    104, 123, 73,
    106, 1,   61,
    86,  111, 68,
    83,  45,  104,
    30,  56,  19,
    15,  97,  99,
    71,  74,  11,
    15,  99,  75,
    25,  102, 6,
    12,  94,  81,
    135, 33,  134,
    138, 133, 3,
    76,  29,  77,
    94,  88,  141,
    115, 31,  142,
    36,  121, 122,
    4,   2,   67,
    9,   78,  79,
    137, 121, 19,
    69,  96,  77,
    13,  62,  80,
    8,   127, 131,
    143, 141, 89,
    133, 12,  81,
    82,  119, 138,
    45,  83,  84,
    21,  85,  136,
    126, 110, 124,
    86,  49,  110,
    13,  116, 117,
    22,  66,  87,
    141, 88,  89,
    64,  45,  84,
    79,  78,  109,
    26,  70,  5,
    14,  93,  100,
    68,  50,  63,
    90,  105, 138,
    141, 0,   91,
    105, 90,  6,
    0,   92,  59,
    17,  145, 76,
    29,  93,  103,
    113, 81,  94,
    39,  85,  47,
    132, 35,  32,
    128, 48,  42,
    93,  29,  16,
    145, 18,  23,
    108, 129, 15,
    32,  112, 48,
    66,  41,  87,
    120, 95,  55,
    96,  68,  63,
    85,  99,  97,
    18,  53,  44,
    22,  98,  107,
    98,  35,  132,
    95,  127, 8,
    137, 64,  84,
    18,  10,  53,
    21,  99,  85,
    54,  79,  44,
    100, 93,  130,
    142, 3,   81,
    102, 101, 6,
    93,  14,  103,
    42,  48,  104,
    87,  23,  34,
    66,  22,  105,
    106, 61,  147,
    72,  74,  71,
    109, 144, 37,
    115, 65,  99,
    107, 132, 133,
    94,  12,  88,
    108, 91,  59,
    43,  64,  74,
    109, 78,  144,
    43,  147, 7,
    91,  135, 115,
    111, 110, 126,
    38,  112, 34,
    142, 113, 94,
    54,  9,   79,
    120, 53,  10,
    138, 3,   82,
    114, 102, 31,
    134, 65,  115,
    105, 22,  107,
    125, 129, 59,
    37,  144, 19,
    17,  76,  77,
    89,  12,  111,
    41,  66,  67,
    13,  117, 62,
    116, 27,  117,
    136, 52,  118,
    51,  60,  61,
    138, 119, 90,
    53,  120, 55,
    68,  111, 12,
    122, 121, 28,
    123, 58,  73,
    110, 57,  124,
    47,  85,  97,
    44,  79,  109,
    126, 125, 92,
    43,  74,  146,
    20,  19,  127,
    128, 17,  77,
    72,  146, 74,
    115, 99,  114,
    140, 122, 38,
    133, 105, 107,
    129, 100, 130,
    131, 144, 78,
    95,  20,  127,
    123, 48,  112,
    102, 136, 101,
    89,  111, 143,
    28,  137, 84,
    133, 132, 50,
    125, 57,  100,
    38,  123, 112,
    124, 57,  125,
    135, 134, 115,
    23,  44,  46,
    136, 85,  52,
    41,  62,  139,
    137, 11,  64,
    104, 48,  123,
    133, 138, 105,
    145, 139, 62,
    25,  6,   26,
    7,   30,  40,
    46,  36,  140,
    141, 143, 0,
    132, 32,  63,
    83,  104, 73,
    19,  144, 127,
    142, 94,  141,
    39,  13,  80,
    92,  143, 126,
    127, 144, 131,
    51,  61,  1,
    91,  0,   59,
    17,  7,   145,
    43,  146, 147,
    146, 72,  147,
};

var _vertex_pos_layout: gpu.VertexLayout = undefined;
var _vertex_col_layout: gpu.VertexLayout = undefined;

//
const renderer_ecs_category_i = ecs.ComponentCategoryI.implement(.{ .name = "Renderer", .order = 20 });

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

        // ConstNodeSettings
        {
            const type_idx = try _cdb.addType(
                db,
                public.SimpleMeshNodeSettings.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.SimpleMeshNodeSettings.propIdx(.type),
                        .name = "type",
                        .type = .STR,
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

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // register apis
    try apidb.setOrRemoveZigApi(module_name, public.RendererApi, &api, load);
    try apidb.setOrRemoveZigApi(module_name, public.RenderGraphApi, &graph_api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &kernel_render_task, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &culling_volume_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &draw_call_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &simple_mesh_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_geometry_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_index_buffer_value_type_i, load);

    try apidb.implOrRemove(module_name, ecs.ComponentCategoryI, &renderer_ecs_category_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_renderer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
