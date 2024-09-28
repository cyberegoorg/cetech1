const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const transform = cetech1.transform;

const renderer = cetech1.renderer;
const gpu = cetech1.gpu;
const zm = cetech1.math;

const module_name = .default_rg;

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
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;

const simple_pass = renderer.Pass.implement(struct {
    pub fn setup(pass: *renderer.Pass, builder: renderer.GraphBuilder) !void {
        try builder.exportLayer(pass, "color");

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
        try builder.createTexture2D(
            pass,
            "foo_depth",
            .{
                .format = gpu.TextureFormat.D24,
                .flags = 0 |
                    gpu.TextureFlags_Rt |
                    gpu.SamplerFlags_MinPoint |
                    gpu.SamplerFlags_MagPoint |
                    gpu.SamplerFlags_MipPoint |
                    gpu.SamplerFlags_UClamp |
                    gpu.SamplerFlags_VClamp,

                .clear_depth = 1.0,
            },
        );

        try builder.addPass("simple_pass", pass);
    }

    pub fn render(builder: renderer.GraphBuilder, gfx_api: *const gpu.GpuApi, viewport: renderer.Viewport, viewid: gpu.ViewId) !void {
        _ = builder;

        const fb_size = viewport.getSize();
        const aspect_ratio = fb_size[0] / fb_size[1];
        const projMtx = zm.perspectiveFovRhGl(
            0.25 * std.math.pi,
            aspect_ratio,
            0.1,
            1000.0,
        );

        const viewMtx = viewport.getViewMtx();
        gfx_api.setViewTransform(viewid, &viewMtx, &zm.matToArr(projMtx));

        if (gfx_api.getEncoder()) |e| {
            e.touch(viewid);

            const dd = viewport.getDD();
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, 0, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
            }
        }
    }
});

const blit_pass = renderer.Pass.implement(struct {
    pub fn setup(pass: *renderer.Pass, builder: renderer.GraphBuilder) !void {
        try builder.writeTexture(pass, renderer.ViewportColorResource);
        try builder.readTexture(pass, "foo");
        try builder.addPass("blit", pass);
    }

    pub fn render(builder: renderer.GraphBuilder, gfx_api: *const gpu.GpuApi, viewport: renderer.Viewport, viewid: gpu.ViewId) !void {
        const fb_size = viewport.getSize();

        if (gfx_api.getEncoder()) |e| {
            const out_tex = builder.getTexture(renderer.ViewportColorResource).?;
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

const rg_i = renderer.DefaultRenderGraphI.implement(struct {
    pub fn create(allocator: std.mem.Allocator, rg_api: *const renderer.RenderGraphApi, graph: renderer.Graph) !void {
        _ = allocator; // autofix
        _ = rg_api; // autofix
        try graph.addPass(simple_pass);
        try graph.addPass(blit_pass);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;

    try apidb.implOrRemove(module_name, renderer.DefaultRenderGraphI, &rg_i, load);

    // impl interface

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_default_rg(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
