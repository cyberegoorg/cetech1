const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const shader_system = @import("shader_system");
const transform = @import("transform");

const public = @import("instance_system.zig");

const module_name = .instance_system;

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
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;

var _gpu: *const gpu.GpuApi = undefined;
var _dd: *const gpu.GpuDDApi = undefined;
var _shader_system: *const shader_system.ShaderSystemAPI = undefined;

const MAX_INSTNACE_MTX = 100_000; // TODO
const MTX_SIZE = 64;
// Global state that can surive hot-reload
const G = struct {
    instance_mtx_buffer: gpu.DynamicVertexBufferHandle = undefined,
    instance_mtx_buffer_offset: std.atomic.Value(u32) = .init(0),
};
var _g: *G = undefined;

pub const api = public.InstanceSystemApi{
    .createInstanceSystem = createInstanceSystem,
    .destroyInstanceSystem = destroyInstanceSystem,
};

const instance_system_header_strid = cetech1.strId32("instance_system_header");
const instance_system_mtx_strid = cetech1.strId32("instance_system_mtx");

fn createInstanceSystem(mtxs: []const transform.WorldTransform) !public.InstanceSystem {
    const isntance_system = _shader_system.findSystemByName(.fromStr("instance_system")).?;
    const system_io = _shader_system.getSystemIO(isntance_system);

    const isntance_system_uniforms = (try _shader_system.createUniformBuffer(system_io)).?;
    const isntance_system_resources = (try _shader_system.createResourceBuffer(system_io)).?;

    const curr_size = _g.instance_mtx_buffer_offset.load(.monotonic);
    if (curr_size + (mtxs.len * 16) >= MAX_INSTNACE_MTX * 16) {
        return error.InstanceMtxBufferFull;
    }

    const offset = _g.instance_mtx_buffer_offset.fetchAdd(@truncate(mtxs.len * 16), .monotonic);

    _gpu.updateDynamicVertexBuffer(
        _g.instance_mtx_buffer,
        offset,
        _gpu.copy(mtxs.ptr, @truncate(@sizeOf(transform.WorldTransform) * mtxs.len)),
    );

    try _shader_system.updateUniforms(system_io, isntance_system_uniforms, &.{
        .{
            .name = instance_system_header_strid,
            .value = std.mem.asBytes(&[4]f32{
                @bitCast(offset / 4),
                0,
                0,
                0,
            }),
        },
    });

    try _shader_system.updateResources(
        system_io,
        isntance_system_resources,
        &.{.{ .name = instance_system_mtx_strid, .value = .{ .buffer = .{ .dvb = _g.instance_mtx_buffer } } }},
    );

    return .{
        .system = isntance_system,
        .uniforms = isntance_system_uniforms,
        .resources = isntance_system_resources,
    };
}

fn destroyInstanceSystem(inst_system: public.InstanceSystem) void {
    const system_io = _shader_system.getSystemIO(inst_system.system);
    _shader_system.destroyResourceBuffer(system_io, inst_system.resources.?);
    _shader_system.destroyUniformBuffer(system_io, inst_system.uniforms.?);
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "InstanceSystem",
    &[_]cetech1.StrId64{.fromStr("ShaderSystem")},
    struct {
        pub fn init() !void {
            _g.instance_mtx_buffer = _gpu.createDynamicVertexBuffer(MAX_INSTNACE_MTX * 16, _gpu.getFloatBufferLayout(), gpu.BufferFlags_ComputeRead);

            // Viewer system
            try _shader_system.addSystemDefiniton(
                "instance_system",
                .{
                    .imports = &.{
                        .{ .name = "instance_system_header", .type = .vec4 },
                        .{ .name = "instance_system_mtx", .type = .buffer, .buffer_type = .vec4, .buffer_acces = .read },
                    },

                    .common_block = @embedFile("shaders/common_block.glsl"),

                    .vertex_block = .{
                        .import_semantic = &.{.instance_id},
                        .common_block = @embedFile("shaders/vs_common_block.glsl"),
                    },
                },
            );
        }

        pub fn shutdown() !void {
            _gpu.destroyDynamicVertexBuffer(_g.instance_mtx_buffer);
        }
    },
);

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "InstanceSystem",
    &[_]cetech1.StrId64{},
    null,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);
            _g.instance_mtx_buffer_offset.store(0, .monotonic);
        }
    },
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;

    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _shader_system = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;

    try apidb.setOrRemoveZigApi(module_name, public.InstanceSystemApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_instance_system(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
