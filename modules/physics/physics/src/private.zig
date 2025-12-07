const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const transform = @import("transform");

const public = @import("physics.zig");

const module_name = .physics;

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
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _gpu: *const cetech1.gpu.GpuBackendApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const velocity_c = ecs.ComponentI.implement(
    public.Velocity,
    .{
        .cdb_type_hash = public.VelocityCdb.type_hash,
        .category = "Physics",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.CoreIcons.FA_ANGLES_RIGHT});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Velocity, data);
            position.* = public.Velocity{
                .x = public.VelocityCdb.readValue(f32, _cdb, r, .X),
                .y = public.VelocityCdb.readValue(f32, _cdb, r, .Y),
                .z = public.VelocityCdb.readValue(f32, _cdb, r, .Z),
            };
        }
    },
);

const move_system_i = ecs.SystemI.implement(
    .{
        .name = "move_system",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(transform.Transform), .inout = .InOut },
            .{ .id = ecs.id(public.Velocity), .inout = .In },
        },
    },
    struct {
        pub fn update(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;

            const p = it.field(transform.Transform, 0).?;
            const v = it.field(public.Velocity, 1).?;

            for (0..it.count()) |i| {
                p[i].position.x += v[i].x * dt;
                p[i].position.y += v[i].y * dt;
                p[i].position.z += v[i].z * dt;
            }
        }
    },
);

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // VelocityCdb
        {
            _ = try _cdb.addType(
                db,
                public.VelocityCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.VelocityCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.VelocityCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.VelocityCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }
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
    _gpu = apidb.getZigApi(module_name, cetech1.gpu.GpuBackendApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &velocity_c, load);

    // System
    try apidb.implOrRemove(module_name, ecs.SystemI, &move_system_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_physics(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
