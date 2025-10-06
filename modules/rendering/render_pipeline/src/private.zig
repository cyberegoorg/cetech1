const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const zm = cetech1.math.zmath;

const public = @import("render_pipeline.zig");

// const renderer = @import("render_viewport");
const render_graph = @import("render_graph");

const module_name = .render_pipeline;

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

var _dd: *const gpu.GpuDDApi = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;

fn createDefault(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: ecs.World) !public.RenderPipeline {
    const impls = try _apidb.getImpl(allocator, public.RenderPipelineI);
    defer allocator.free(impls);
    if (impls.len == 0) return error.NoPipelineDefined;

    const iface = impls[impls.len - 1];

    const inst = try iface.create(allocator, gpu_backend, world);
    return .{
        .ptr = inst,
        .vtable = iface,
    };
}

pub const api = public.RenderPipelineApi{
    .createDefault = createDefault,
};

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _apidb = apidb;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    // _render_viewport = apidb.getZigApi(module_name, renderer.RenderViewportApi).?;

    try apidb.setOrRemoveZigApi(module_name, public.RenderPipelineApi, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_render_pipeline(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
