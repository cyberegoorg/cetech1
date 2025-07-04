const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

const public = @import("renderer_nodes.zig");

const graphvm = @import("graphvm");

const shader_system = @import("shader_system");

const render_viewport = @import("render_viewport");
const vertex_system = @import("vertex_system");

const module_name = .renderer_nodes;

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
var _gpu: *const gpu.GpuApi = undefined;

var _dd: *const gpu.GpuDDApi = undefined;
var _metrics: *const cetech1.metrics.MetricsAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;

var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _viewport: *const render_viewport.RenderViewportApi = undefined;
var _vertex_system: *const vertex_system.VertexSystemApi = undefined;

// Global state
const G = struct {};

var _g: *G = undefined;

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

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _metrics = apidb.getZigApi(module_name, cetech1.metrics.MetricsAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;

    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _vertex_system = apidb.getZigApi(module_name, vertex_system.VertexSystemApi).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // impl interface

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_renderer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
