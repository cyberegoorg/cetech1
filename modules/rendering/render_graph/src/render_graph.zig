const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const zm = cetech1.math.zmath;

const camera = @import("camera");

const GpuApi = gpu.GpuApi;

pub const RENDERER_GRAPH_KERNEL_TASK = cetech1.strId64("Renderer graph");

pub const ViewersList = cetech1.ArrayList(Viewer);

pub const Pass = struct {
    setup: *const fn (pass: *Pass, builder: GraphBuilder) anyerror!void,
    execute: *const fn (builder: GraphBuilder, gpu_api: *const GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) anyerror!void,

    pub fn implement(comptime T: type) Pass {
        if (!std.meta.hasFn(T, "setup")) @compileError("implement me");
        if (!std.meta.hasFn(T, "execute")) @compileError("implement me");

        const p = Pass{
            .setup = &T.setup,
            .execute = &T.execute,
        };

        return p;
    }
};

pub const Module = struct {
    pub fn addPass(self: Module, pass: Pass) !void {
        return self.vtable.addPass(self.ptr, pass);
    }
    pub fn addModule(self: Module, module: Module) !void {
        return self.vtable.addModule(self.ptr, module);
    }
    pub fn addExtensionPoint(self: Module, name: cetech1.StrId32) !void {
        return self.vtable.addExtensionPoint(self.ptr, name);
    }
    pub fn addToExtensionPoint(self: Module, name: cetech1.StrId32, module: Module) !void {
        return self.vtable.addToExtensionPoint(self.ptr, name, module);
    }
    pub fn setupBuilder(self: Module, builder: GraphBuilder) !void {
        return self.vtable.setupBuilder(self.ptr, builder);
    }
    pub fn cleanup(self: Module) !void {
        return self.vtable.cleanup(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModule: *const fn (self: *anyopaque, module: Module) anyerror!void,
        addExtensionPoint: *const fn (self: *anyopaque, name: cetech1.StrId32) anyerror!void,
        addToExtensionPoint: *const fn (self: *anyopaque, name: cetech1.StrId32, module: Module) anyerror!void,
        setupBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) anyerror!void,
        cleanup: *const fn (self: *anyopaque) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPass")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addExtensionPoint")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setupBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "cleanup")) @compileError("implement me");

            return VTable{
                .addPass = &T.addPass,
                .addModule = &T.addModule,
                .addExtensionPoint = &T.addExtensionPoint,
                .setupBuilder = &T.setupBuilder,
                .cleanup = &T.cleanup,
            };
        }
    };
};

pub const Viewer = struct {
    mtx: [16]f32,
    proj: [16]f32,
    camera: camera.Camera,
    context: cetech1.StrId32,
};

pub const ResourceId = cetech1.StrId32;

pub const TextureInfo = struct {
    has_mip: bool = true,
    num_layers: u16 = 1,
    format: gpu.TextureFormat,
    flags: gpu.TextureFlags,
    ratio: gpu.BackbufferRatio = .Equal,
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
    pub inline fn addPass(builder: GraphBuilder, name: []const u8, pass: *Pass, layer: ?[]const u8) !void {
        return builder.vtable.addPass(builder.ptr, name, pass, layer);
    }
    pub inline fn importTexture(builder: GraphBuilder, texture_name: []const u8, texture: gpu.TextureHandle) !void {
        return builder.vtable.importTexture(builder.ptr, texture_name, texture);
    }

    pub inline fn clearStencil(builder: GraphBuilder, pass: *Pass, clear_value: u8) !void {
        return builder.vtable.clearStencil(builder.ptr, pass, clear_value);
    }

    pub inline fn createTexture2D(builder: GraphBuilder, pass: *Pass, texture: []const u8, info: TextureInfo) !void {
        return builder.vtable.createTexture2D(builder.ptr, pass, texture, info);
    }

    pub inline fn writeTexture(builder: GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return builder.vtable.writeTexture(builder.ptr, pass, texture);
    }

    pub inline fn readTexture(builder: GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return builder.vtable.readTexture(builder.ptr, pass, texture);
    }

    pub inline fn setAttachment(builder: GraphBuilder, pass: *Pass, id: u32, texture: []const u8) !void {
        return builder.vtable.setAttachment(builder.ptr, pass, id, texture);
    }

    pub inline fn getTexture(builder: GraphBuilder, texture: []const u8) ?gpu.TextureHandle {
        return builder.vtable.getTexture(builder.ptr, texture);
    }

    pub inline fn getLayer(builder: GraphBuilder, layer: []const u8) gpu.ViewId {
        return builder.vtable.getLayer(builder.ptr, layer);
    }

    pub inline fn getLayerById(builder: GraphBuilder, layer: cetech1.StrId32) gpu.ViewId {
        return builder.vtable.getLayerById(builder.ptr, layer);
    }

    pub inline fn compile(builder: GraphBuilder, allocator: std.mem.Allocator) !void {
        return builder.vtable.compile(builder.ptr, allocator);
    }
    pub inline fn execute(builder: GraphBuilder, allocator: std.mem.Allocator, vp_size: [2]f32, viewers: []const Viewer) !void {
        return builder.vtable.execute(builder.ptr, allocator, vp_size, viewers);
    }

    pub inline fn clear(builder: GraphBuilder) !void {
        return builder.vtable.clear(builder.ptr);
    }

    pub inline fn getViewers(builder: GraphBuilder) []Viewer {
        return builder.vtable.getViewers(builder.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (builder: *anyopaque, name: []const u8, pass: *Pass, layer: ?[]const u8) anyerror!void,

        importTexture: *const fn (builder: *anyopaque, texture_name: []const u8, texture: gpu.TextureHandle) anyerror!void,
        clearStencil: *const fn (builder: *anyopaque, pass: *Pass, clear_value: u8) anyerror!void,

        createTexture2D: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8, info: TextureInfo) anyerror!void,
        writeTexture: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8) anyerror!void,
        readTexture: *const fn (builder: *anyopaque, pass: *Pass, texture: []const u8) anyerror!void,

        setAttachment: *const fn (builder: *anyopaque, pass: *Pass, id: u32, texture: []const u8) anyerror!void,

        getTexture: *const fn (builder: *anyopaque, texture: []const u8) ?gpu.TextureHandle,
        getLayer: *const fn (builder: *anyopaque, layer: []const u8) gpu.ViewId,
        getLayerById: *const fn (builder: *anyopaque, layer: cetech1.StrId32) gpu.ViewId,

        getViewers: *const fn (builder: *anyopaque) []Viewer,

        compile: *const fn (builder: *anyopaque, allocator: std.mem.Allocator) anyerror!void,
        execute: *const fn (builder: *anyopaque, allocator: std.mem.Allocator, vp_size: [2]f32, viewers: []const Viewer) anyerror!void,

        clear: *const fn (builder: *anyopaque) anyerror!void,
    };
};

pub const RenderGraphApi = struct {
    createModule: *const fn () anyerror!Module,
    destroyModule: *const fn (module: Module) void,

    createBuilder: *const fn (allocator: std.mem.Allocator) anyerror!GraphBuilder,
    destroyBuilder: *const fn (builder: GraphBuilder) void,
};
