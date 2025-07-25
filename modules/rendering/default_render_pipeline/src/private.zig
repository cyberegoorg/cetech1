const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const zm = cetech1.math.zmath;

const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");
const render_graph = @import("render_graph");
const shader_system = @import("shader_system");

const module_name = .default_render_pipeline;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;
var _dd: *const gpu.GpuDDApi = undefined;
var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _shader: *const shader_system.ShaderSystemAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    rg_vt: *render_pipeline.RenderPipelineI = undefined,
};
var _g: *G = undefined;

const depth_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "depth",
            .{
                .format = gpu.TextureFormat.D24,
                .flags = 0 |
                    gpu.TextureFlags_Rt,
                .clear_depth = 1.0,
            },
        );
        try builder.setAttachment(pass, 0, "depth");
        try builder.addPass("depth_pass", pass, "depth");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = gpu_api;
        _ = viewid;
    }
});

const simple_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "foo",
            .{
                .format = gpu.TextureFormat.BGRA8,
                .flags = 0 |
                    gpu.TextureFlags_Rt |
                    gpu.SamplerFlags_MinPoint |
                    gpu.SamplerFlags_MipMask |
                    gpu.SamplerFlags_MagPoint |
                    gpu.SamplerFlags_MipPoint |
                    gpu.SamplerFlags_UClamp |
                    gpu.SamplerFlags_VClamp,

                .clear_color = 0x66CCFFff,
            },
        );
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "foo");
        try builder.setAttachment(pass, 1, "depth");

        try builder.addPass("simple_pass", pass, "color");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        gpu_api.touch(viewid);
    }
});

const dd_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.writeTexture(pass, "foo");
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "foo");
        try builder.setAttachment(pass, 1, "depth");

        try builder.addPass("dd_pass", pass, "debugdraw");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            const dd = _dd.encoderCreate();
            defer _dd.encoderDestroy(dd);
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, 0, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
            }
        }
    }
});

const blit_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.readTexture(pass, "foo");
        try builder.writeTexture(pass, render_viewport.ColorResource);
        try builder.addPass("blit", pass, null);
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        const fb_size = vp_size;

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            const out_tex = builder.getTexture(render_viewport.ColorResource).?;
            const foo_tex = builder.getTexture("foo").?;
            e.blit(
                viewid,
                out_tex,
                0,
                0,
                0,
                0,
                foo_tex,
                0,
                0,
                0,
                0,
                @intFromFloat(fb_size[0]),
                @intFromFloat(fb_size[1]),
                0,
            );
        }
    }
});

const DefaultPipelineInst = struct {
    allocator: std.mem.Allocator,

    time_system: shader_system.SystemInstance = undefined,
    viewer_system: shader_system.SystemInstance = undefined,
    depth_system: shader_system.SystemInstance = undefined,
};

const rg_i = render_pipeline.RenderPipelineI.implement(struct {
    pub fn create(allocator: std.mem.Allocator) !*anyopaque {
        const inst = try allocator.create(DefaultPipelineInst);
        inst.* = .{
            .allocator = allocator,

            .time_system = try _shader.createSystemInstance(cetech1.strId32("time_system")),
            .viewer_system = try _shader.createSystemInstance(cetech1.strId32("viewer_system")),
            .depth_system = try _shader.createSystemInstance(cetech1.strId32("depth_system")),
        };
        return inst;
    }

    pub fn destroy(pipeline: *anyopaque) void {
        var inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));

        _shader.destroySystemInstance(&inst.time_system);
        _shader.destroySystemInstance(&inst.viewer_system);
        _shader.destroySystemInstance(&inst.depth_system);

        inst.allocator.destroy(inst);
    }

    pub fn fillModule(pipeline: *anyopaque, module: render_graph.Module) !void {
        const inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));
        _ = inst;

        try module.addExtensionPoint(render_pipeline.extensions.init);
        try module.addExtensionPoint(render_pipeline.extensions.render);
        try module.addExtensionPoint(render_pipeline.extensions.dd);

        {
            const render_module = try _render_graph.createModule();
            try render_module.addPass(depth_pass);
            try render_module.addPass(simple_pass);
            try module.addToExtensionPoint(render_pipeline.extensions.render, render_module);
        }

        {
            const dd_module = try _render_graph.createModule();
            try dd_module.addPass(dd_pass);
            try module.addToExtensionPoint(render_pipeline.extensions.dd, dd_module);
        }

        try module.addPass(blit_pass);
    }

    pub fn begin(pipeline: *anyopaque, context: *shader_system.ShaderContext, now_s: f32) !void {
        const inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));

        try context.addSystem(&inst.time_system);
        try context.addSystem(&inst.viewer_system);
        try context.addSystem(&inst.depth_system);

        try inst.time_system.uniforms.?.set(cetech1.strId32("time"), [4]f32{ now_s, 0, 0, 0 });
    }

    pub fn end(pipeline: *anyopaque, context: *shader_system.ShaderContext) !void {
        _ = pipeline;
        _ = context;
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.rg_vt = try apidb.setGlobalVarValue(render_pipeline.RenderPipelineI, module_name, "rg_vt", rg_i);
    try apidb.implOrRemove(module_name, render_pipeline.RenderPipelineI, _g.rg_vt, load);

    // impl interface

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_default_render_pipeline(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
