const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const zm = cetech1.math.zmath;

const renderer = @import("renderer");

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
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;
var _dd: *const gpu.GpuDDApi = undefined;

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

    pub fn render(builder: renderer.GraphBuilder, gfx_api: *const gpu.GpuApi, viewport: renderer.Viewport, viewid: gpu.ViewId, viewers: []const renderer.Viewer) !void {
        _ = builder;
        _ = viewport;

        const projMtx = viewers[0].proj;
        const viewMtx = viewers[0].mtx;

        gfx_api.setViewTransform(viewid, &viewMtx, &projMtx);

        if (gfx_api.getEncoder()) |e| {
            defer gfx_api.endEncoder(e);
            //e.touch(viewid);

            const dd = _dd.encoderCreate();
            defer _dd.encoderDestroy(dd);
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, 0, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);

                // Skip renderig frustrum for main camera
                for (viewers[1..]) |viewer| {
                    const m = zm.mul(zm.matFromArr(viewer.mtx), zm.matFromArr(viewer.proj));
                    const mm = zm.matToArr(m);
                    dd.drawFrustum(mm);
                }
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

    pub fn render(builder: renderer.GraphBuilder, gfx_api: *const gpu.GpuApi, viewport: renderer.Viewport, viewid: gpu.ViewId, viewers: []const renderer.Viewer) !void {
        _ = viewers; // autofix
        const fb_size = viewport.getSize();

        if (gfx_api.getEncoder()) |e| {
            defer gfx_api.endEncoder(e);

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

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;

    try apidb.implOrRemove(module_name, renderer.DefaultRenderGraphI, &rg_i, load);

    // impl interface

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_default_rg(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
