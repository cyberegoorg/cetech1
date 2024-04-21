const std = @import("std");

const builtin = @import("builtin");

const zm = @import("zmath");

const zgui = @import("zgui");
const zglfw = @import("zglfw");
const zbgfx = @import("zbgfx");

const bgfx = @import("bgfx.zig");
const gpu_private = @import("gpu.zig");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");

const cetech1 = @import("cetech1");
const public = cetech1.gfx.rg;
const gfx = cetech1.gfx;
const gfx_dd = cetech1.gfx.dd;
const gpu = cetech1.gpu;

const Pass = public.Pass;

const log = std.log.scoped(.gfx_rg);

const module_name = .gfxrd;
var _allocator: std.mem.Allocator = undefined;

const ModuleOrPass = union(enum) {
    module: *Module,
    pass: Pass,
};
const ModulePassList = std.ArrayList(ModuleOrPass);
const PassList = std.ArrayList(*Pass);

const GraphBuilder = struct {
    allocator: std.mem.Allocator,
    passes: PassList,

    pub fn init(allocator: std.mem.Allocator) GraphBuilder {
        return .{
            .allocator = allocator,
            .passes = PassList.init(allocator),
        };
    }

    pub fn deinit(self: *GraphBuilder) void {
        self.passes.deinit();
    }

    pub fn addPass(self: *GraphBuilder, pass: *Pass) !void {
        try self.passes.append(pass);
    }

    pub fn render(self: *GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: gpu.GpuViewport) !void {
        for (self.passes.items) |pass| {
            try pass.render(.{ .ptr = self, .vtable = &builder_vt }, gfx_api, viewport);
        }
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

    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{
            .allocator = allocator,
            .module_pool = ModulePool.init(allocator),
            .builder_pool = BuilderPool.init(allocator),
            .module = Module.init(allocator),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.module.deinit();
        self.module_pool.deinit();
        self.builder_pool.deinit();
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

    pub fn createBuilder(self: *RenderGraph) !public.GraphBuilder {
        const new_builder = try self.builder_pool.create();
        new_builder.* = GraphBuilder.init(self.allocator);
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
};

const RenderGraphPool = cetech1.mem.PoolWithLock(RenderGraph);
const RenderGraphSet = std.AutoArrayHashMap(*RenderGraph, void);
var _rg_set: RenderGraphSet = undefined;
var _rg_pool: RenderGraphPool = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _rg_set = RenderGraphSet.init(allocator);
    _rg_pool = RenderGraphPool.init(allocator);
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
    .render = @ptrCast(&GraphBuilder.render),
};

pub const api = public.GfxRGApi{
    .create = create,
    .destroy = destroy,
};

fn create() !public.RenderGraph {
    const new_rg = try _rg_pool.create();
    new_rg.* = RenderGraph.init(_allocator);
    try _rg_set.put(new_rg, {});
    return public.RenderGraph{ .ptr = new_rg, .vtable = &rg_vt };
}

fn destroy(rg: public.RenderGraph) void {
    const true_rg: *RenderGraph = @alignCast(@ptrCast(rg.ptr));
    true_rg.deinit();
    _ = _rg_set.swapRemove(true_rg);
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
            try builder.addPass(pass);
        }

        pub fn render(builder: public.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: gpu.GpuViewport) !void {
            _ = viewport; // autofix
            _ = builder; // autofix
            try std.testing.expectEqual(&gpu_private.gfx_api, gfx_api);
        }
    });
    _ = p1; // autofix

    // var vw = gpu.GpuViewport{.ptr = rg, .vtable = };

    // const m1 = try api.createModule(rg);
    // try api.addPassToModule(m1, p1);
    // try api.addModule(rg, m1);

    // const builder = try api.createBuilder(rg);
    // defer api.destroyBuilder(rg, builder);
    // try api.setupBuilder(rg, builder);
    // try api.builderRender(builder, &gpu_private.gfx_api, &gpu_private.gfx_dd_api, &vw);
}
