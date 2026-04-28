const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const gpu_dd = cetech1.gpu_dd;

const public = @import("render_pipeline.zig");

// const renderer = @import("render_viewport");
const render_graph = @import("render_graph");

const module_name = .render_pipeline;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;

fn createDefault(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: ecs.World) !public.RenderPipeline {
    const impls = try apidb.getImpl(allocator, public.RenderPipelineI);
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
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);

    // try kernel.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);

    try ecs.loadAPI(module_name);

    try render_graph.loadAPI(module_name);

    try apidb.setOrRemoveZigApi(module_name, public.RenderPipelineApi, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_render_pipeline(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
