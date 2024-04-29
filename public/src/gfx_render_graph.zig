const std = @import("std");

const strid = @import("strid.zig");
const gfx = @import("gfx.zig");
const ecs = @import("ecs.zig");

const GfxApi = gfx.GfxApi;
const GpuViewport = @import("gpu.zig").GpuViewport;
const GfxDDApi = @import("gfx_debug_draw.zig").GfxDDApi;

pub const CullingResult = struct {
    mtx: std.ArrayList([16]f32),
    renderables: std.ArrayList(*const anyopaque),

    lock: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) CullingResult {
        return CullingResult{
            .mtx = std.ArrayList([16]f32).init(allocator),
            .renderables = std.ArrayList(*const anyopaque).init(allocator),
        };
    }
    pub fn deinit(self: *CullingResult) void {
        self.mtx.deinit();
        self.renderables.deinit();
    }

    pub fn append(self: *CullingResult, mtx: [16]f32, renderable: *const anyopaque) !void {
        self.lock.lock();
        defer self.lock.unlock();

        try self.mtx.append(mtx);
        try self.renderables.append(renderable);
    }
};

pub const ComponentRendererI = struct {
    pub const c_name = "ct_rg_component_renderer_i";
    pub const name_hash = strid.strId64(@This().c_name);

    culling: ?*const fn (allocator: std.mem.Allocator, builder: GraphBuilder, world: ecs.World, viewers: []Viewer) anyerror!CullingResult = undefined,
    render: *const fn (builder: GraphBuilder, world: ecs.World, viewport: GpuViewport, culling: ?CullingResult) anyerror!void = undefined,

    pub fn implement(comptime T: type) ComponentRendererI {
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        return ComponentRendererI{
            .render = T.render,
            .culling = if (std.meta.hasFn(T, "culling")) T.culling else null,
        };
    }
};

pub const Pass = struct {
    setup: *const fn (pass: *Pass, builder: GraphBuilder) anyerror!void,
    render: *const fn (builder: GraphBuilder, gfx_api: *const GfxApi, viewport: GpuViewport, viewid: gfx.ViewId) anyerror!void,

    pub fn implement(comptime T: type) Pass {
        if (!std.meta.hasFn(T, "setup")) @compileError("implement me");
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        const p = Pass{
            .setup = &T.setup,
            .render = &T.render,
        };

        return p;
    }
};

pub const Module = struct {
    pub fn addPassToModule(self: Module, pass: Pass) !void {
        self.vtable.addPassToModule(self.ptr, pass);
    }
    pub fn addModuleToModule(self: Module, module: Module) !void {
        self.vtable.addModuleToModule(self.ptr, module);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPassToModule: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModuleToModule: *const fn (self: *anyopaque, module: Module) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPassToModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModuleToModule")) @compileError("implement me");

            return VTable{
                .addPassToModule = &T.addPassToModule,
                .addModuleToModule = &T.addModuleToModule,
            };
        }
    };
};

pub const Viewer = struct {
    mtx: [16]f32,
};

pub const ResourceId = strid.StrId32;
pub const ViewportColorResource = "viewport_color";

pub const TextureInfo = struct {
    has_mip: bool = true,
    num_layers: u16 = 1,
    format: gfx.TextureFormat,
    flags: gfx.TextureFlags,
    ratio: gfx.BackbufferRatio = .Equal,
    clear_color: ?u32 = null,
    clear_depth: ?f32 = null,

    pub fn eql(self: TextureInfo, other: TextureInfo) bool {
        return self.has_mip == other.has_mip and
            self.num_layers == other.num_layers and
            self.format == other.format and
            self.flags == other.flags and
            self.ratio == other.ratio and
            self.clear_color == other.clear_color and
            self.clear_depth == other.clear_depth;
    }
};

pub const GraphBuilder = struct {
    pub fn addPass(builder: GraphBuilder, name: []const u8, pass: *Pass) !void {
        return builder.vtable.addPass(builder.ptr, name, pass);
    }
    pub fn importTexture(builder: GraphBuilder, texture_name: []const u8, texture: gfx.TextureHandle) !void {
        return builder.vtable.importTexture(builder.ptr, texture_name, texture);
    }

    pub fn clearStencil(builder: GraphBuilder, pass: *Pass, clear_value: u8) !void {
        return builder.vtable.clearStencil(builder.ptr, pass, clear_value);
    }

    pub fn createTexture2D(builder: GraphBuilder, pass: *Pass, texture: []const u8, info: TextureInfo) !void {
        return builder.vtable.createTexture2D(builder.ptr, pass, texture, info);
    }

    pub fn writeTexture(builder: GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return builder.vtable.writeTexture(builder.ptr, pass, texture);
    }

    pub fn readTexture(builder: GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return builder.vtable.readTexture(builder.ptr, pass, texture);
    }

    pub fn getTexture(builder: GraphBuilder, texture: []const u8) ?gfx.TextureHandle {
        return builder.vtable.getTexture(builder.ptr, texture);
    }

    pub fn exportLayer(builder: GraphBuilder, pass: *Pass, layer: []const u8) !void {
        return builder.vtable.exportLayer(builder.ptr, pass, layer);
    }

    pub fn getLayer(builder: GraphBuilder, layer: []const u8) gfx.ViewId {
        return builder.vtable.getLayer(builder.ptr, layer);
    }

    pub fn compile(builder: GraphBuilder) !void {
        return builder.vtable.compile(builder.ptr);
    }
    pub fn execute(builder: GraphBuilder, viewport: GpuViewport) !void {
        return builder.vtable.execute(builder.ptr, viewport);
    }

    pub fn getViewers(builder: GraphBuilder) []Viewer {
        return builder.vtable.getViewers(builder.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (builder: *anyopaque, name: []const u8, pass: *Pass) anyerror!void,
        importTexture: *const fn (builder: *anyopaque, texture_name: []const u8, texture: gfx.TextureHandle) anyerror!void,
        clearStencil: *const fn (builder: *anyopaque, pass: *Pass, clear_value: u8) anyerror!void,
        createTexture2D: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8, info: TextureInfo) anyerror!void,
        writeTexture: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8) anyerror!void,
        readTexture: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8) anyerror!void,
        exportLayer: *const fn (builder: *anyopaque, pass: *Pass, layer: []const u8) anyerror!void,
        getTexture: *const fn (builder: *anyopaque, texture: []const u8) ?gfx.TextureHandle,
        getLayer: *const fn (builder: *anyopaque, layer: []const u8) gfx.ViewId,

        getViewers: *const fn (builder: *anyopaque) []Viewer,

        compile: *const fn (builder: *anyopaque) anyerror!void,
        execute: *const fn (builder: *anyopaque, viewport: GpuViewport) anyerror!void,
    };
};

pub const RenderGraph = struct {
    pub fn addPass(self: RenderGraph, pass: Pass) !void {
        return self.vtable.addPass(self.ptr, pass);
    }
    pub fn addModule(self: RenderGraph, module: Module) !void {
        self.vtable.addModule(self.ptr, module);
    }
    pub fn createModule(self: RenderGraph) !Module {
        return self.vtable.createModule(self.ptr);
    }
    pub fn createBuilder(self: RenderGraph, allocator: std.mem.Allocator, viewport: GpuViewport) !GraphBuilder {
        return self.vtable.createBuilder(self.ptr, allocator, viewport);
    }
    pub fn destroyBuilder(self: RenderGraph, builder: GraphBuilder) void {
        self.vtable.destroyBuilder(self.ptr, builder);
    }
    pub fn setupBuilder(self: RenderGraph, builder: GraphBuilder) !void {
        return self.vtable.setupBuilder(self.ptr, builder);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModule: *const fn (self: *anyopaque, module: Module) anyerror!void,
        createModule: *const fn (self: *anyopaque) anyerror!Module,
        createBuilder: *const fn (self: *anyopaque, allocator: std.mem.Allocator, viewport: GpuViewport) anyerror!GraphBuilder,
        destroyBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) void,
        setupBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPass")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "createModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "createBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "destroyBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setupBuilder")) @compileError("implement me");

            return VTable{
                .addPass = &T.addPass,
                .addModule = &T.addModule,
                .createModule = &T.createModule,
                .createBuilder = &T.createBuilder,
                .destroyBuilder = &T.destroyBuilder,
                .setupBuilder = &T.setupBuilder,
            };
        }
    };
};

pub const GfxRGApi = struct {
    create: *const fn () anyerror!RenderGraph,
    destroy: *const fn (rg: RenderGraph) void,
};
