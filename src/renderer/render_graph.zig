const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const math = cetech1.math;
const apidb = cetech1.apidb;

const camera = cetech1.camera;
const shader_system = cetech1.renderer.shader_system;
const visibility_flags = cetech1.renderer.visibility_flags;

const GpuBackendApi = gpu.GpuBackendApi;

pub const RENDERER_GRAPH_KERNEL_TASK = cetech1.strId64("Renderer graph");

pub const ViewersList = cetech1.ArrayList(Viewer);
pub const Viewer = struct {
    mtx: math.Mat44f,
    proj: math.Mat44f,
    camera: camera.Camera,
    viewid: ?gpu.ViewId,
    visibility_mask: visibility_flags.VisibilityFlags,

    viewer_system: shader_system.System,
    viewer_system_uniforms: shader_system.UniformBufferInstance,
};

pub const PassApi = struct {
    setup: *const fn (pass: *Pass, builder: *GraphBuilder) anyerror!void,
    execute: *const fn (pass: *const Pass, builder: *GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) anyerror!void,

    pub fn implement(comptime T: type) PassApi {
        const p = PassApi{
            .setup = &T.setup,
            .execute = &T.execute,
        };

        return p;
    }
};

pub const Pass = struct {
    name: []const u8,
    const_data: ?[]const u8 = null,
    runtime_data_size: usize = 0,
    api: *const PassApi,

    runtime_data: ?[]u8 = null,
};

pub const EditorMenuUII = struct {
    name: [:0]const u8,
    data: *anyopaque,
    menui: *const fn (allocator: std.mem.Allocator, data: *anyopaque) anyerror!void,

    pub fn implement(
        name: [:0]const u8,
        data: *anyopaque,
        comptime T: type,
    ) EditorMenuUII {
        return EditorMenuUII{
            .name = name,
            .data = data,
            .menui = T.menui,
        };
    }
};

pub const Module = opaque {
    pub fn addPass(self: *Module, pass: Pass) !void {
        return api.addPass(self, pass);
    }
    pub fn addPassWithData(self: *Module, name: []const u8, comptime ConstDataT: type, RuntimeDataT: type, const_data: *const ConstDataT, pass_api: *const PassApi) !void {
        return api.addPass(self, Pass{
            .name = name,
            .const_data = std.mem.asBytes(const_data),
            .runtime_data_size = @sizeOf(RuntimeDataT),
            .api = pass_api,
        });
    }

    pub fn addModule(self: *Module, module: *Module) !void {
        return api.addModule(self, module);
    }
    pub fn addExtensionPoint(self: *Module, name: cetech1.StrId32) !void {
        return api.addExtensionPoint(self, name);
    }
    pub fn addToExtensionPoint(self: *Module, name: cetech1.StrId32, module: *Module) !void {
        return api.addToExtensionPoint(self, name, module);
    }
    pub fn setEditorMenuUi(self: *Module, editor_menu_ui: EditorMenuUII) void {
        return api.setEditorMenuUi(self, editor_menu_ui);
    }
    pub fn editorMenuUi(self: *Module, allocator: std.mem.Allocator) !void {
        return api.editorMenuUi(self, allocator);
    }
};

pub const ResourceId = cetech1.StrId32;

pub const TextureInfo = struct {
    has_mip: bool = false,
    num_layers: u16 = 1,
    format: gpu.TextureFormat,
    flags: gpu.TextureFlags,
    sampler_flags: gpu.SamplerFlags = .{},
    ratio: f32 = 1,
    clear_color: ?math.SRGBA = null,
    clear_depth: ?f32 = null,

    pub fn eql(self: TextureInfo, other: TextureInfo) bool {
        return self.has_mip == other.has_mip and
            self.num_layers == other.num_layers and
            self.format == other.format and
            std.meta.eql(self.flags, other.flags) and
            std.meta.eql(self.sampler_flags, other.sampler_flags) and
            self.ratio == other.ratio and
            std.meta.eql(self.clear_color, other.clear_color) and
            self.clear_depth == other.clear_depth;
    }
};

pub const BlackboardValue = union(enum) {
    int32: i32,
    uint32: u32,
    int64: i64,
    uint64: u64,
    boolean: bool,
    data: *anyopaque,
    str: []const u8,
    resource_Id: ResourceId,
};

pub const GraphBuilder = struct {
    pub inline fn enablePass(builder: *GraphBuilder, pass: *Pass) !void {
        return api.enablePass(builder, pass);
    }

    pub inline fn setMaterialLayer(builder: *GraphBuilder, pass: *Pass, layer: ?[]const u8) !void {
        return api.setMaterialLayer(builder, pass, layer);
    }

    pub inline fn importTexture(builder: *GraphBuilder, texture_name: []const u8, texture: gpu.TextureHandle) !void {
        return api.importTexture(builder, texture_name, texture);
    }

    pub inline fn clearStencil(builder: *GraphBuilder, pass: *Pass, clear_value: u8) !void {
        return api.clearStencil(builder, pass, clear_value);
    }

    pub inline fn createTexture2D(builder: *GraphBuilder, pass: *Pass, texture: []const u8, info: TextureInfo) !void {
        return api.createTexture2D(builder, pass, texture, info);
    }

    pub inline fn writeTexture(builder: *GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return api.writeTexture(builder, pass, texture);
    }

    pub inline fn readTexture(builder: *GraphBuilder, pass: *Pass, texture: []const u8) !void {
        return api.readTexture(builder, pass, texture);
    }

    pub inline fn setAttachment(builder: *GraphBuilder, pass: *Pass, id: u32, texture: []const u8) !void {
        return api.setAttachment(builder, pass, id, texture);
    }

    pub inline fn getTexture(builder: *GraphBuilder, texture: []const u8) ?gpu.TextureHandle {
        return api.getTexture(builder, texture);
    }

    pub inline fn getLayer(builder: *GraphBuilder, layer: []const u8) gpu.ViewId {
        return api.getLayer(builder, layer);
    }

    pub inline fn getLayerById(builder: *GraphBuilder, layer: cetech1.StrId32) gpu.ViewId {
        return api.getLayerById(builder, layer);
    }

    pub inline fn compile(builder: *GraphBuilder, allocator: std.mem.Allocator, module: *Module) !void {
        return api.compile(builder, allocator, module);
    }
    pub inline fn execute(builder: *GraphBuilder, allocator: std.mem.Allocator, vp_size: math.Vec2f, viewers: []const Viewer, freze_mtx: ?math.Mat44f) !void {
        return api.execute(builder, allocator, vp_size, viewers, freze_mtx);
    }

    pub inline fn clear(builder: *GraphBuilder) !void {
        return api.clear(builder);
    }

    pub inline fn getViewers(builder: *GraphBuilder) []Viewer {
        return api.getViewers(builder);
    }

    pub inline fn writeBlackboardValue(builder: *GraphBuilder, key: cetech1.StrId32, value: BlackboardValue) !void {
        return api.writeBlackboardValue(builder, key, value);
    }

    pub inline fn readBlackboardValue(builder: *GraphBuilder, key: cetech1.StrId32) ?BlackboardValue {
        return api.readBlackboardValue(builder, key);
    }
};

pub fn createModule() anyerror!*Module {
    return api.createModule();
}
pub fn destroyModule(module: *Module) void {
    return api.destroyModule(module);
}
pub fn createBuilder(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend) anyerror!*GraphBuilder {
    return api.createBuilder(allocator, gpu_backend);
}
pub fn destroyBuilder(builder: *GraphBuilder) void {
    return api.destroyBuilder(builder);
}
pub fn screenSpaceQuad(gpu_backend: gpu.GpuBackend, e: gpu.GpuEncoder, width: f32, height: f32) void {
    return api.screenSpaceQuad(gpu_backend, e, width, height);
}

pub const RenderGraphApi = struct {
    createModule: *const fn () anyerror!*Module,
    destroyModule: *const fn (module: *Module) void,
    createBuilder: *const fn (allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend) anyerror!*GraphBuilder,
    destroyBuilder: *const fn (builder: *GraphBuilder) void,
    screenSpaceQuad: *const fn (gpu_backend: gpu.GpuBackend, e: gpu.GpuEncoder, width: f32, height: f32) void,

    // Module
    addPass: *const fn (self: *Module, pass: Pass) anyerror!void,
    addModule: *const fn (self: *Module, module: *Module) anyerror!void,
    addExtensionPoint: *const fn (self: *Module, name: cetech1.StrId32) anyerror!void,
    addToExtensionPoint: *const fn (self: *Module, name: cetech1.StrId32, module: *Module) anyerror!void,
    setEditorMenuUi: *const fn (self: *Module, editor_menu_ui: EditorMenuUII) void,
    editorMenuUi: *const fn (self: *Module, allocator: std.mem.Allocator) anyerror!void,

    // Graph builder
    enablePass: *const fn (builder: *GraphBuilder, pass: *Pass) anyerror!void,
    setMaterialLayer: *const fn (builder: *GraphBuilder, pass: *Pass, layer: ?[]const u8) anyerror!void,
    importTexture: *const fn (builder: *GraphBuilder, texture_name: []const u8, texture: gpu.TextureHandle) anyerror!void,
    clearStencil: *const fn (builder: *GraphBuilder, pass: *Pass, clear_value: u8) anyerror!void,
    createTexture2D: *const fn (builder: *GraphBuilder, pass: *Pass, texture: []const u8, info: TextureInfo) anyerror!void,
    writeTexture: *const fn (builder: *GraphBuilder, pass: *Pass, texture: []const u8) anyerror!void,
    readTexture: *const fn (builder: *GraphBuilder, pass: *Pass, texture: []const u8) anyerror!void,
    setAttachment: *const fn (builder: *GraphBuilder, pass: *Pass, id: u32, texture: []const u8) anyerror!void,
    getTexture: *const fn (builder: *GraphBuilder, texture: []const u8) ?gpu.TextureHandle,
    getLayer: *const fn (builder: *GraphBuilder, layer: []const u8) gpu.ViewId,
    getLayerById: *const fn (builder: *GraphBuilder, layer: cetech1.StrId32) gpu.ViewId,
    getViewers: *const fn (builder: *GraphBuilder) []Viewer,
    compile: *const fn (builder: *GraphBuilder, allocator: std.mem.Allocator, module: *Module) anyerror!void,
    execute: *const fn (builder: *GraphBuilder, allocator: std.mem.Allocator, vp_size: math.Vec2f, viewers: []const Viewer, freze_mtx: ?math.Mat44f) anyerror!void,
    clear: *const fn (builder: *GraphBuilder) anyerror!void,
    writeBlackboardValue: *const fn (builder: *GraphBuilder, key: cetech1.StrId32, value: BlackboardValue) anyerror!void,
    readBlackboardValue: *const fn (builder: *GraphBuilder, key: cetech1.StrId32) ?BlackboardValue,
};

pub var api: *const RenderGraphApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, RenderGraphApi).?;
}
