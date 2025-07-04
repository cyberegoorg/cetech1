const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

const public = @import("render_graph.zig");

const module_name = .render_graph;

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

var _gpu: *const gpu.GpuApi = undefined;

var _metrics: *const cetech1.metrics.MetricsAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;

// Global state
const G = struct {
    builder_pool: BuilderPool = undefined,
    module_pool: ModulePool = undefined,
};

var _g: *G = undefined;

const ModulePassList = cetech1.ArrayList(ModuleOrPass);
const PassList = cetech1.ArrayList(*public.Pass);

const PassInfoMap = cetech1.AutoArrayHashMap(*public.Pass, *PassInfo);
const ResourceSet = cetech1.AutoArrayHashMap(public.ResourceId, void);
const TextureInfoMap = cetech1.AutoArrayHashMap(public.ResourceId, public.TextureInfo);
const TextureMap = cetech1.AutoArrayHashMap(public.ResourceId, gpu.TextureHandle);
const CreatedTextureMap = cetech1.AutoArrayHashMap(CreatedTextureKey, CreatedTextureInfo);
const TextureList = cetech1.ArrayList(gpu.TextureHandle);
const PassSet = cetech1.AutoArrayHashMap(*public.Pass, void);
const ResourceInfoMap = cetech1.AutoArrayHashMap(public.ResourceId, *ResourceInfo);
const LayerMap = cetech1.AutoArrayHashMap(cetech1.StrId32, gpu.ViewId);

const ResourceInfoPool = cetech1.heap.VirtualPool(ResourceInfo);

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

    pub fn clear(self: *ResourceInfo) void {
        self.create = null;
        self.writes.clearRetainingCapacity();
        self.reads.clearRetainingCapacity();
    }
};

const CreatedTextureKey = struct {
    name: public.ResourceId,
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

const PassInfoPool = cetech1.heap.VirtualPool(PassInfo);
const PassInfo = struct {
    name: []const u8 = undefined,

    create_texture: TextureInfoMap = .{},
    write_texture: ResourceSet = .{},
    read_texture: ResourceSet = .{},

    viewid: gpu.ViewId = 0,
    clear_stencil: ?u8 = null,
    clear_depth: ?f32 = null,

    exported_layer: ?cetech1.StrId32 = null,

    fb: ?gpu.FrameBufferHandle = null,

    pub fn deinit(self: *PassInfo, allocator: std.mem.Allocator) void {
        self.create_texture.deinit(allocator);
        self.write_texture.deinit(allocator);
        self.read_texture.deinit(allocator);

        if (self.fb) |fb| {
            _gpu.destroyFrameBuffer(fb);
        }
    }

    pub fn clear(self: *PassInfo) void {
        self.create_texture.clearRetainingCapacity();
        self.write_texture.clearRetainingCapacity();
        self.read_texture.clearRetainingCapacity();

        if (self.fb) |fb| {
            _gpu.destroyFrameBuffer(fb);
        }

        self.viewid = 0;
        self.clear_stencil = null;
        self.clear_depth = null;
        self.exported_layer = null;
        self.fb = null;
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

pub const MAX_PASSES_IN_BUILDER = 256;
pub const MAX_RESOURCE_INFO_IN_BUILDER = 256;

const GraphBuilder = struct {
    allocator: std.mem.Allocator,

    passinfo_pool: PassInfoPool,
    resourceinfo_pool: ResourceInfoPool,

    passinfo_map: PassInfoMap = .{},
    texture_map: TextureMap = .{},

    passes: PassList = .{},
    layer_map: LayerMap = .{},

    resource_deps: ResourceInfoMap = .{},

    dag: dag.DAG(*public.Pass),

    viewers: public.ViewersList = .{},

    created_texture: CreatedTextureMap = .{},

    pub fn init(allocator: std.mem.Allocator) !GraphBuilder {
        return .{
            .allocator = allocator,
            .dag = dag.DAG(*public.Pass).init(allocator),
            .passinfo_pool = try PassInfoPool.init(allocator, MAX_PASSES_IN_BUILDER),
            .resourceinfo_pool = try ResourceInfoPool.init(allocator, MAX_RESOURCE_INFO_IN_BUILDER),
        };
    }

    pub fn deinit(self: *GraphBuilder) void {
        for (self.passinfo_map.values()) |info| {
            info.deinit(self.allocator);
        }

        for (self.resource_deps.values()) |set| {
            set.deinit(self.allocator);
        }

        for (self.created_texture.values()) |texture| {
            _gpu.destroyTexture(texture.handler);
        }
        self.created_texture.deinit(_allocator);

        self.layer_map.deinit(self.allocator);
        self.passes.deinit(self.allocator);
        self.passinfo_map.deinit(self.allocator);
        self.texture_map.deinit(self.allocator);
        self.resource_deps.deinit(self.allocator);
        self.viewers.deinit(self.allocator);

        self.passinfo_pool.deinit();
        self.resourceinfo_pool.deinit();

        self.dag.deinit();
    }

    pub fn clear(self: *GraphBuilder) !void {
        var z = _profiler.ZoneN(@src(), "RenderGraph - Clear");
        defer z.End();

        for (self.passinfo_map.values()) |info| {
            try self.passinfo_pool.destroy(info);
        }

        for (self.resource_deps.values()) |set| {
            try self.resourceinfo_pool.destroy(set);
        }

        self.layer_map.clearRetainingCapacity();
        self.passes.clearRetainingCapacity();
        self.passinfo_map.clearRetainingCapacity();
        self.texture_map.clearRetainingCapacity();
        self.resource_deps.clearRetainingCapacity();
        self.viewers.clearRetainingCapacity();

        try self.dag.reset();
    }

    pub fn addPass(self: *GraphBuilder, name: []const u8, pass: *public.Pass, layer: ?[]const u8) !void {
        const pass_info = try self.getOrCreateInfo(pass);

        pass_info.name = name;

        if (layer) |l| pass_info.exported_layer = cetech1.strId32(l);

        try self.passes.append(self.allocator, pass);
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
            var new = false;
            var p = self.resourceinfo_pool.create(&new);
            if (new) {
                p.* = ResourceInfo.init(texture_name);
            } else {
                p.clear();
            }

            result.value_ptr.* = p;
        }

        return result.value_ptr.*;
    }

    pub fn compile(self: *GraphBuilder, allocator: std.mem.Allocator) !void {
        var z = _profiler.ZoneN(@src(), "RenderGraph - Compile");
        defer z.End();

        var depends = cetech1.ArrayList(*public.Pass){};
        defer depends.deinit(allocator);

        // Create DAG for pass
        for (self.passes.items) |pass| {
            depends.clearRetainingCapacity();

            const info = self.passinfo_map.get(pass) orelse return error.InvalidPass;

            for (info.write_texture.keys()) |texture| {
                const texture_deps = self.resource_deps.get(texture).?;
                if (texture_deps.create) |create_pass| {
                    if (create_pass == pass) continue;

                    try depends.append(allocator, create_pass);
                }
            }

            for (info.read_texture.keys()) |texture| {
                const texture_deps = self.resource_deps.get(texture).?;

                try depends.appendSlice(allocator, texture_deps.writes.keys());

                if (texture_deps.create) |create_pass| {
                    if (create_pass == pass) continue;

                    try depends.append(allocator, create_pass);
                }
            }

            try self.dag.add(pass, depends.items);
        }

        // Build DAG => flat array
        try self.dag.build_all();
    }

    pub fn execute(self: *GraphBuilder, allocator: std.mem.Allocator, vp_size: [2]f32, world: ecs.World, viewers: []const public.Viewer) !void {
        var z = _profiler.ZoneN(@src(), "RenderGraph - Execute");
        defer z.End();

        try self.viewers.appendSlice(self.allocator, viewers);

        var textures = cetech1.ArrayList(gpu.TextureHandle){};
        defer textures.deinit(allocator);

        // Prepare passes
        for (self.dag.output.keys()) |pass| {
            textures.clearRetainingCapacity();

            var info = self.passinfo_map.get(pass) orelse return error.InvalidPass;

            const viewid = _gpu.newViewId();
            info.viewid = viewid;
            if (info.exported_layer) |layer| {
                try self.layer_map.put(self.allocator, layer, viewid);
            }

            if (info.needFb()) {
                var clear_flags: gpu.ClearFlags = gpu.ClearFlags_None;
                var clear_colors: [8]u8 = .{std.math.maxInt(u8)} ** 8;

                for (info.create_texture.keys(), info.create_texture.values()) |k, v| {
                    const texture_deps = self.resource_deps.get(k).?;

                    const t = try self.getOrCreateTexture2D(vp_size, texture_deps.name, v);
                    try self.texture_map.put(self.allocator, k, t);
                }

                for (info.write_texture.keys(), 0..) |write, idx| {
                    try textures.append(allocator, self.texture_map.get(write).?);

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

        for (self.passes.items) |pass| {
            const info = self.passinfo_map.get(pass) orelse return error.InvalidPass;

            const builder = public.GraphBuilder{ .ptr = self, .vtable = &builder_vt };
            try pass.execute(builder, _gpu, world, vp_size, info.viewid, self.viewers.items);
        }
    }

    fn getOrCreateInfo(self: *GraphBuilder, pass: *public.Pass) !*PassInfo {
        const result = try self.passinfo_map.getOrPut(self.allocator, pass);

        if (!result.found_existing) {
            var new = false;
            var p = self.passinfo_pool.create(&new);
            if (new) {
                p.* = .{};
            } else {
                p.clear();
            }

            result.value_ptr.* = p;
        }

        return result.value_ptr.*;
    }

    pub fn getOrCreateTexture2D(self: *GraphBuilder, vp_size: [2]f32, texture_name: []const u8, info: public.TextureInfo) !gpu.TextureHandle {
        const texture_id = cetech1.strId32(texture_name);

        const ratio = ratioFromEnum(info.ratio);
        const size = [2]f32{ vp_size[0] * ratio, vp_size[1] * ratio };

        const exist_texture = self.created_texture.get(.{ .name = texture_id });

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
            try self.created_texture.put(
                _allocator,
                .{ .name = texture_id },
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

    pub fn setupBuilder(self: *Module, builder: public.GraphBuilder) !void {
        var z = _profiler.ZoneN(@src(), "RenderGraph - Module setup builder");
        defer z.End();

        for (self.passes.items) |*pass_or_module| {
            switch (pass_or_module.*) {
                .module => |module| try module.setupBuilder(builder),
                .pass => |*pass| try pass.setup(pass, builder),
            }
        }
    }

    pub fn cleanup(self: *Module) !void {
        self.passes.clearRetainingCapacity();
    }
};

const ModulePool = cetech1.heap.PoolWithLock(Module);
const BuilderPool = cetech1.heap.PoolWithLock(GraphBuilder);

pub fn createModule() !public.Module {
    const new_module = try _g.module_pool.create();
    new_module.* = Module.init(_allocator);
    return public.Module{
        .ptr = new_module,
        .vtable = &module_vt,
    };
}

pub fn destroyModule(module: public.Module) void {
    var real_module: *Module = @alignCast(@ptrCast(module.ptr));
    real_module.deinit();
    _g.module_pool.destroy(real_module);
}

pub fn createBuilder(allocator: std.mem.Allocator) !public.GraphBuilder {
    const new_builder = try _g.builder_pool.create();
    new_builder.* = try GraphBuilder.init(allocator);
    return .{ .ptr = new_builder, .vtable = &builder_vt };
}

pub fn destroyBuilder(builder: public.GraphBuilder) void {
    const true_builder: *GraphBuilder = @alignCast(@ptrCast(builder.ptr));
    true_builder.deinit();
    _g.builder_pool.destroy(true_builder);
}

const PalletColorMap = cetech1.AutoArrayHashMap(u32, u8);

pub const module_vt = public.Module.VTable{
    .addPass = @ptrCast(&Module.addPass),
    .addModule = @ptrCast(&Module.addModule),
    .setupBuilder = @ptrCast(&Module.setupBuilder),
    .cleanup = @ptrCast(&Module.cleanup),
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

    .getViewers = @ptrCast(&GraphBuilder.getViewers),

    .execute = @ptrCast(&GraphBuilder.execute),
    .compile = @ptrCast(&GraphBuilder.compile),
    .clear = @ptrCast(&GraphBuilder.clear),
};

pub const graph_api = public.RenderGraphApi{
    .createDefault = createDefault,

    .createBuilder = @ptrCast(&createBuilder),
    .destroyBuilder = @ptrCast(&destroyBuilder),
    .createModule = createModule,
    .destroyModule = destroyModule,
};

fn createDefault(allocator: std.mem.Allocator, module: public.Module) !void {
    const impls = try _apidb.getImpl(allocator, public.DefaultRenderGraphI);
    defer allocator.free(impls);
    if (impls.len == 0) return;

    const iface = impls[impls.len - 1];
    try iface.create(allocator, &graph_api, module);
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Renderer graph",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            _g.builder_pool = BuilderPool.init(_allocator);
            _g.module_pool = ModulePool.init(_allocator);
        }

        pub fn shutdown() !void {
            _g.builder_pool.deinit();
            _g.module_pool.deinit();
        }
    },
);

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

    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;

    _metrics = apidb.getZigApi(module_name, cetech1.metrics.MetricsAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // register apis
    try apidb.setOrRemoveZigApi(module_name, public.RenderGraphApi, &graph_api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_render_graph(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
