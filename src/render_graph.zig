// TODO: SHIT

const std = @import("std");

const builtin = @import("builtin");

const bgfx = @import("bgfx.zig");
const gpu_private = @import("gpu.zig");
const renderer_private = @import("renderer.zig");
const _gfx_api = gpu_private.gfx_api;
const _renderer_api = renderer_private.api;

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");

const cetech1 = @import("cetech1");
const public = cetech1.render_graph;
const gfx = cetech1.gpu;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const zm = cetech1.math;

const Viewport = cetech1.renderer.Viewport;

const Pass = public.Pass;

const module_name = .render_graph;
const log = std.log.scoped(module_name);

var _allocator: std.mem.Allocator = undefined;

const ModulePassList = std.ArrayList(ModuleOrPass);
const PassList = std.ArrayList(*Pass);

const PassInfoMap = std.AutoArrayHashMap(*public.Pass, PassInfo);
const ResourceSet = std.AutoArrayHashMap(public.ResourceId, void);
const TextureInfoMap = std.AutoArrayHashMap(public.ResourceId, public.TextureInfo);
const TextureMap = std.AutoArrayHashMap(public.ResourceId, gfx.TextureHandle);
const CreatedTextureMap = std.AutoArrayHashMap(CreatedTextureKey, CreatedTextureInfo);
const TextureList = std.ArrayList(gfx.TextureHandle);
const PassSet = std.AutoArrayHashMap(*public.Pass, void);
const ResourceInfoMap = std.AutoArrayHashMap(public.ResourceId, ResourceInfo);
const LayerMap = std.AutoArrayHashMap(cetech1.strid.StrId32, gfx.ViewId);

const ResourceInfo = struct {
    name: []const u8,
    create: ?*Pass = null,
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
    viewport: Viewport,
};

const CreatedTextureInfo = struct {
    handler: gfx.TextureHandle,
    info: public.TextureInfo,
    size: [2]f32,
};

const ModuleOrPass = union(enum) {
    module: *Module,
    pass: Pass,
};

const PassInfo = struct {
    name: []const u8 = undefined,

    write_texture: ResourceSet,
    read_texture: ResourceSet,
    create_texture: TextureInfoMap,

    viewid: gfx.ViewId = 0,
    clear_stencil: ?u8 = null,
    clear_depth: ?f32 = null,

    exported_layer: ?cetech1.strid.StrId32 = null,

    fb: ?gfx.FrameBufferHandle = null,

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
            _gfx_api.destroyFrameBuffer(fb);
        }
    }

    pub fn needFb(self: PassInfo) bool {
        return self.write_texture.count() != 0;
    }
};

pub fn ratioFromEnum(ratio: gfx.BackbufferRatio) f32 {
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
    rg: *RenderGraph,

    passinfo_map: PassInfoMap,
    texture_map: TextureMap,

    passes: PassList,
    viewport: Viewport,
    layer_map: LayerMap,

    resource_deps: ResourceInfoMap,

    dag: dag.DAG(*Pass),

    viewers: ViewersList,

    pub fn init(allocator: std.mem.Allocator, rg: *RenderGraph, viewport: Viewport) GraphBuilder {
        return .{
            .allocator = allocator,
            .rg = rg,
            .passinfo_map = PassInfoMap.init(allocator),
            .texture_map = TextureMap.init(allocator),
            .passes = PassList.init(allocator),
            .viewport = viewport,
            .dag = dag.DAG(*Pass).init(allocator),
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

    pub fn addPass(self: *GraphBuilder, name: []const u8, pass: *Pass) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.name = name;
        try self.passes.append(pass);
    }

    pub fn exportLayer(self: *GraphBuilder, pass: *Pass, name: []const u8) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.exported_layer = cetech1.strid.strId32(name);
    }

    pub fn getViewers(self: *GraphBuilder) []public.Viewer {
        return self.viewers.items;
    }

    pub fn clearStencil(self: *GraphBuilder, pass: *Pass, clear_value: u8) !void {
        const pass_info = try self.getOrCreateInfo(pass);
        pass_info.clear_stencil = clear_value;
    }

    pub fn createTexture2D(self: *GraphBuilder, pass: *Pass, texture: []const u8, info: public.TextureInfo) !void {
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

    pub fn writeTexture(self: *GraphBuilder, pass: *Pass, texture: []const u8) !void {
        const info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strid.strId32(texture);

        try info.write_texture.put(texture_id, {});
        const deps = try self.getOrCreateResourceDeps(texture);
        try deps.writes.put(pass, {});
    }

    pub fn readTexture(self: *GraphBuilder, pass: *Pass, texture: []const u8) !void {
        const info = try self.getOrCreateInfo(pass);

        const texture_id = cetech1.strid.strId32(texture);

        try info.read_texture.put(texture_id, {});
        const deps = try self.getOrCreateResourceDeps(texture);
        try deps.reads.put(pass, {});
    }

    pub fn getTexture(self: *GraphBuilder, texture: []const u8) ?gfx.TextureHandle {
        return self.texture_map.get(cetech1.strid.strId32(texture));
    }

    pub fn getLayer(self: *GraphBuilder, layer: []const u8) gfx.ViewId {
        return self.layer_map.get(cetech1.strid.strId32(layer)) orelse 256;
    }

    pub fn importTexture(self: *GraphBuilder, texture_name: []const u8, texture: gfx.TextureHandle) !void {
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

            var depends = std.ArrayList(*Pass).init(self.allocator);
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

            const viewid = _renderer_api.newViewId();
            info.viewid = viewid;
            if (info.exported_layer) |layer| {
                try self.layer_map.put(layer, viewid);
            }

            if (info.needFb()) {
                var clear_flags: gfx.ClearFlags = gfx.ClearFlags_None;
                var clear_colors: [8]u8 = .{std.math.maxInt(u8)} ** 8;

                var textures = std.ArrayList(gfx.TextureHandle).init(self.allocator);
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
                        clear_flags |= gfx.ClearFlags_Color;
                        const c_idx = _gfx_api.addPaletteColor(c);
                        clear_colors[idx] = c_idx;
                    } else if (null != texture.clear_depth) {
                        clear_flags |= gfx.ClearFlags_Depth;
                    }
                }

                // stencil
                var stencil_clear_value: u8 = 0;
                if (info.clear_stencil) |clear_value| {
                    stencil_clear_value = clear_value;
                    clear_flags |= gfx.ClearFlags_Stencil;
                }

                _gfx_api.setViewClearMrt(
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

                const fb = _gfx_api.createFrameBufferFromHandles(@truncate(textures.items.len), textures.items.ptr, false);
                _gfx_api.setFrameBufferName(fb, info.name.ptr, @intCast(info.name.len));

                info.fb = fb;

                const vp_size = self.viewport.getSize();
                _gfx_api.setViewName(viewid, info.name.ptr, @intCast(info.name.len));
                _gfx_api.setViewFrameBuffer(viewid, fb);
                _gfx_api.setViewRect(
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
            try pass.render(builder, &gpu_private.gfx_api, self.viewport, info.viewid);
        }
    }

    fn getOrCreateInfo(self: *GraphBuilder, pass: *Pass) !*PassInfo {
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

    pub fn addPass(self: *Module, pass: Pass) !void {
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

const RenderGraph = struct {
    allocator: std.mem.Allocator,
    module_pool: ModulePool,
    builder_pool: BuilderPool,
    module: Module,
    created_texture: CreatedTextureMap,

    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{
            .allocator = allocator,
            .module_pool = ModulePool.init(allocator),
            .builder_pool = BuilderPool.init(allocator),
            .module = Module.init(allocator),
            .created_texture = CreatedTextureMap.init(allocator),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        for (self.created_texture.values()) |texture| {
            _gfx_api.destroyTexture(texture.handler);
        }

        self.module.deinit();
        self.module_pool.deinit();
        self.builder_pool.deinit();
        self.created_texture.deinit();
    }

    pub fn addPass(self: *RenderGraph, pass: public.Pass) !void {
        try self.module.addPass(pass);
    }

    pub fn addModule(self: *RenderGraph, module: public.Module) !void {
        try self.module.addModule(module);
    }

    pub fn createModule(self: *RenderGraph) !public.Module {
        const new_module = try self.module_pool.create();
        new_module.* = Module.init(self.allocator);
        return public.Module{
            .ptr = new_module,
            .vtable = &module_vt,
        };
    }

    pub fn createBuilder(self: *RenderGraph, allocator: std.mem.Allocator, viewport: Viewport) !public.GraphBuilder {
        const new_builder = try self.builder_pool.create();
        new_builder.* = GraphBuilder.init(allocator, self, viewport);
        return .{ .ptr = new_builder, .vtable = &builder_vt };
    }

    pub fn destroyBuilder(self: *RenderGraph, builder: public.GraphBuilder) void {
        const true_builder: *GraphBuilder = @alignCast(@ptrCast(builder.ptr));
        true_builder.deinit();
        self.builder_pool.destroy(true_builder);
    }

    pub fn setupBuilder(self: *RenderGraph, builder: public.GraphBuilder) !void {
        try self.module.setup(builder);
    }

    pub fn createTexture2D(self: *RenderGraph, viewport: Viewport, texture_name: []const u8, info: public.TextureInfo) !gfx.TextureHandle {
        const texture_id = cetech1.strid.strId32(texture_name);

        const vp_size = viewport.getSize();
        const ratio = ratioFromEnum(info.ratio);
        const size = [2]f32{ vp_size[0] * ratio, vp_size[1] * ratio };
        const exist_texture = self.created_texture.get(.{ .name = texture_id, .viewport = viewport });

        if (exist_texture) |t| {
            // it's a match
            if (t.info.eql(info) and t.size[0] == vp_size[0] and t.size[1] == vp_size[1]) return t.handler;

            _gfx_api.destroyTexture(t.handler);
        }

        // Create new
        const t = _gfx_api.createTexture2D(
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

        _gfx_api.setTextureName(t, texture_name.ptr, @intCast(texture_name.len));

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

const RenderGraphPool = cetech1.mem.PoolWithLock(RenderGraph);
const RenderGraphSet = std.AutoArrayHashMap(*RenderGraph, void);
var _rg_lock: std.Thread.Mutex = undefined;
var _rg_set: RenderGraphSet = undefined;
var _rg_pool: RenderGraphPool = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _rg_set = RenderGraphSet.init(allocator);
    _rg_pool = RenderGraphPool.init(allocator);
    _rg_lock = std.Thread.Mutex{};
}

pub fn deinit() void {
    _rg_set.deinit();
    _rg_pool.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.GfxRGApi, &api);
}

pub const rg_vt = public.RenderGraph.VTable{
    .addPass = @ptrCast(&RenderGraph.addPass),
    .addModule = @ptrCast(&RenderGraph.addModule),
    .createModule = @ptrCast(&RenderGraph.createModule),
    .createBuilder = @ptrCast(&RenderGraph.createBuilder),
    .destroyBuilder = @ptrCast(&RenderGraph.destroyBuilder),
    .setupBuilder = @ptrCast(&RenderGraph.setupBuilder),
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

pub const api = public.GfxRGApi{
    .create = create,
    .destroy = destroy,
};

fn create() !public.RenderGraph {
    const new_rg = try _rg_pool.create();
    new_rg.* = RenderGraph.init(_allocator);

    {
        _rg_lock.lock();
        defer _rg_lock.unlock();
        try _rg_set.put(new_rg, {});
    }

    return public.RenderGraph{ .ptr = new_rg, .vtable = &rg_vt };
}

fn destroy(rg: public.RenderGraph) void {
    const true_rg: *RenderGraph = @alignCast(@ptrCast(rg.ptr));
    true_rg.deinit();

    {
        _rg_lock.lock();
        defer _rg_lock.unlock();
        _ = _rg_set.swapRemove(true_rg);
    }

    _rg_pool.destroy(true_rg);
}

test "gfxrd: Basic usage" {
    const allocator = std.testing.allocator;

    try init(allocator);
    defer deinit();

    const rg = try api.create();
    defer api.destroy(rg);

    const p1 = Pass.implement(struct {
        pub fn setup(pass: *Pass, builder: public.GraphBuilder) !void {
            try builder.addPass("none", pass);
        }

        pub fn render(builder: public.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: Viewport, viewid: gfx.ViewId) !void {
            _ = viewid;
            _ = viewport;
            _ = builder;
            try std.testing.expectEqual(&gpu_private.gfx_api, gfx_api);
        }
    });
    _ = p1;

    // var vw = gpu.Viewport{.ptr = rg, .vtable = };

    // const m1 = try api.createModule(rg);
    // try api.addPassToModule(m1, p1);
    // try api.addModule(rg, m1);

    // const builder = try api.createBuilder(rg);
    // defer api.destroyBuilder(rg, builder);
    // try api.setupBuilder(rg, builder);
    // try api.builderRender(builder, &gpu_private.gfx_api, &gpu_private.gfx_dd_api, &vw);
}
