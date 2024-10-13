const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math;

const public = @import("transform.zig");

const module_name = .transform;

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

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const position_c = ecs.ComponentI.implement(
    public.Position,

    public.PositionCdb.type_hash,
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Position});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Position, data);
            position.* = public.Position{
                .x = public.PositionCdb.readValue(f32, _cdb, r, .X),
                .y = public.PositionCdb.readValue(f32, _cdb, r, .Y),
                .z = public.PositionCdb.readValue(f32, _cdb, r, .Z),
            };
        }
    },
);

const rotation_c = ecs.ComponentI.implement(
    public.Rotation,

    public.RotationCdb.type_hash,
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Rotation});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Rotation, data);
            position.* = public.Rotation{
                .q = zm.quatFromRollPitchYaw(
                    std.math.degreesToRadians(public.RotationCdb.readValue(f32, _cdb, r, .X)),
                    std.math.degreesToRadians(public.RotationCdb.readValue(f32, _cdb, r, .Y)),
                    std.math.degreesToRadians(public.RotationCdb.readValue(f32, _cdb, r, .Z)),
                ),
            };
        }
    },
);

const scale_c = ecs.ComponentI.implement(
    public.Scale,

    public.ScaleCdb.type_hash,
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Scale});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Scale, data);
            position.* = public.Scale{
                .x = public.ScaleCdb.readValue(f32, _cdb, r, .X),
                .y = public.ScaleCdb.readValue(f32, _cdb, r, .Y),
                .z = public.ScaleCdb.readValue(f32, _cdb, r, .Z),
            };
        }
    },
);

const world_tranform_c = cetech1.ecs.ComponentI.implement(public.WorldTransform, null, struct {});

const transform_system_i = ecs.SystemI.implement(
    .{
        .name = "transform.transform",
        .multi_threaded = false,
        .instanced = true,
        .phase = ecs.OnValidate,
        .query = &.{
            .{ .id = ecs.id(public.WorldTransform), .inout = .Out },
            .{ .id = ecs.id(public.WorldTransform), .inout = .In, .oper = .Optional, .src = .{ .id = ecs.Up | ecs.Cascade } },
            .{ .id = ecs.id(public.Position), .inout = .In }, // .src = .{ .id = ecs.Self_ | ecs.Up }
            .{ .id = ecs.id(public.Rotation), .inout = .In, .oper = .Optional },
            .{ .id = ecs.id(public.Scale), .inout = .In, .oper = .Optional },
        },
    },
    struct {
        pub fn iterate(iter: *ecs.IterO) !void {
            var it = _ecs.toIter(iter);
            var zone_ctx = _profiler.ZoneN(@src(), "Transform system");
            defer zone_ctx.End();

            while (it.next()) {
                if (!it.changed()) {
                    it.skip();
                    continue;
                }

                var zone_iner_ctx = _profiler.ZoneN(@src(), "Transform iner");
                defer zone_iner_ctx.End();

                const world_transform = it.field(public.WorldTransform, 0).?;
                const parent_world_transform = it.field(public.WorldTransform, 1);

                const positions = it.field(public.Position, 2).?;
                const rotations = it.field(public.Rotation, 3);
                const scales = it.field(public.Scale, 4);
                const count = it.count();

                if (parent_world_transform) |p| {
                    if (it.isSelf(2)) {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[i].x, positions[i].y, positions[i].z);
                            world_transform[i].mtx = zm.mul(p[0].mtx, model_mat);
                        }
                    } else {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[0].x, positions[0].y, positions[0].z);
                            world_transform[i].mtx = zm.mul(p[0].mtx, model_mat);
                        }
                    }
                } else {
                    if (it.isSelf(2)) {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[i].x, positions[i].y, positions[i].z);
                            world_transform[i].mtx = model_mat;
                        }
                    } else {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[0].x, positions[0].y, positions[0].z);
                            world_transform[i].mtx = model_mat;
                        }
                    }
                }

                if (rotations) |r| {
                    if (it.isSelf(3)) {
                        for (0..count) |i| {
                            const mat = zm.quatToMat(r[i].q);
                            world_transform[i].mtx = zm.mul(mat, world_transform[i].mtx);
                        }
                    } else {
                        for (0..count) |i| {
                            const mat = zm.quatToMat(r[0].q);
                            world_transform[i].mtx = zm.mul(mat, world_transform[i].mtx);
                        }
                    }
                }

                if (scales) |s| {
                    for (0..count) |i| {
                        const mat = zm.scaling(s[i].x, s[i].y, s[i].z);
                        world_transform[i].mtx = zm.mul(mat, world_transform[i].mtx);
                    }
                }
            }
        }
    },
);

const spawn_transform_world_system_i = ecs.SystemI.implement(
    .{
        .name = "transform.spawn_world",
        .multi_threaded = true,
        .phase = ecs.PostLoad,
        .query = &.{
            .{ .id = ecs.id(public.WorldTransform), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.Rotation), .inout = .In, .oper = .Or },
            .{ .id = ecs.id(public.Scale), .inout = .In, .oper = .Or },
            .{ .id = ecs.id(public.Position), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *ecs.IterO) !void {
            var it = _ecs.toIter(iter);

            const world = it.getWorld();
            const ents = it.entities();
            for (0..it.count()) |i| {
                _ = world.setId(public.WorldTransform, ents[i], &public.WorldTransform{});
            }
        }
    },
);

// const set_position_node_i = graphvm.NodeI.implement(
//     .{
//         .name = "Set position",
//         .type_name = "transform_set_position",
//         .category = "Transform",
//         .sidefect = true,
//     },
//     null,
//     struct {
//         pub fn getInputPins(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
//             _ = node_obj; // autofix
//             _ = graph_obj; // autofix
//             return allocator.dupe(graphvm.NodePin, &.{
//                 graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", false), graphvm.PinTypes.Flow),
//                 graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", false), ecs.PinTypes.Entity),
//                 graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", false), graphvm.PinTypes.VEC3F),
//             });
//         }

//         pub fn getOutputPins(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
//             _ = node_obj; // autofix
//             _ = graph_obj; // autofix
//             return allocator.dupe(graphvm.NodePin, &.{});
//         }

//         pub fn execute(args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
//             _ = out_pins; // autofix

//             _, const ent = in_pins.read(ecs.EntityId, 1) orelse return;
//             _, const position = in_pins.read([3]f32, 2) orelse return;

//             const w = graphvm_private.api.getContext(anyopaque, args.instance, ecs.ECS_WORLD_CONTEXT) orelse return;

//             const world = ecs_private.api.toWorld(w);
//             _ = world.setId(
//                 public.Position,
//                 ent,
//                 &public.Position{
//                     .x = position[0],
//                     .y = position[1],
//                     .z = position[2],
//                 },
//             );
//         }
//     },
// );

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // Position
        {
            _ = try _cdb.addType(
                db,
                public.PositionCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.PositionCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.PositionCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.PositionCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }

        // Scale
        {
            const scale_idx = try _cdb.addType(
                db,
                public.ScaleCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.ScaleCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.ScaleCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.ScaleCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            const default_scale = try _cdb.createObject(db, scale_idx);
            const default_scale_w = _cdb.writeObj(default_scale).?;
            public.ScaleCdb.setValue(f32, _cdb, default_scale_w, .X, 1.0);
            public.ScaleCdb.setValue(f32, _cdb, default_scale_w, .Y, 1.0);
            public.ScaleCdb.setValue(f32, _cdb, default_scale_w, .Z, 1.0);
            try _cdb.writeCommit(default_scale_w);
            _cdb.setDefaultObject(default_scale);
        }

        // Rotation
        {
            const rot_idx = try _cdb.addType(
                db,
                public.RotationCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.RotationCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.RotationCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.RotationCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            const default_quat = try _cdb.createObject(db, rot_idx);
            const default_quat_w = _cdb.writeObj(default_quat).?;
            public.RotationCdb.setValue(f32, _cdb, default_quat_w, .X, 0.0);
            public.RotationCdb.setValue(f32, _cdb, default_quat_w, .Y, 0.0);
            public.RotationCdb.setValue(f32, _cdb, default_quat_w, .Z, 0.0);
            try _cdb.writeCommit(default_quat_w);
            _cdb.setDefaultObject(default_quat);
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

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, ecs.ComponentI, &world_tranform_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &position_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &rotation_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &scale_c, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &transform_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &spawn_transform_world_system_i, load);

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_transform(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
