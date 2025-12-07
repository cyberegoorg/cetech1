const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const public = @import("transform.zig");

const graphvm = @import("graphvm");

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
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _graphvm: *const graphvm.GraphVMApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const transform_c = ecs.ComponentI.implement(public.Transform, .{
    .cdb_type_hash = public.TransformCdb.type_hash,
    .category = "Transform",
    .category_order = 0.3,
    .gizmoPriority = 100,
    .with = &.{ecs.id(public.WorldTransform)},
}, struct {
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

        const t = _cdb.readObj(obj) orelse return;

        const transform = std.mem.bytesAsValue(public.Transform, data);

        const pos_obj = public.TransformCdb.readSubObj(_cdb, t, .Position).?;
        const pos_r = public.PositionCdb.read(_cdb, pos_obj).?;
        transform.position = public.Position{
            .x = public.PositionCdb.readValue(f32, _cdb, pos_r, .X),
            .y = public.PositionCdb.readValue(f32, _cdb, pos_r, .Y),
            .z = public.PositionCdb.readValue(f32, _cdb, pos_r, .Z),
        };

        const rot_obj = public.TransformCdb.readSubObj(_cdb, t, .Rotation).?;
        const rot_r = public.PositionCdb.read(_cdb, rot_obj).?;
        transform.rotation.q = zm.quatFromRollPitchYaw(
            std.math.degreesToRadians(public.RotationCdb.readValue(f32, _cdb, rot_r, .X)),
            std.math.degreesToRadians(public.RotationCdb.readValue(f32, _cdb, rot_r, .Y)),
            std.math.degreesToRadians(public.RotationCdb.readValue(f32, _cdb, rot_r, .Z)),
        );

        const scale_obj = public.TransformCdb.readSubObj(_cdb, t, .Scale).?;
        const scale_r = public.ScaleCdb.read(_cdb, scale_obj).?;
        transform.scale = public.Scale{
            .x = public.ScaleCdb.readValue(f32, _cdb, scale_r, .X),
            .y = public.ScaleCdb.readValue(f32, _cdb, scale_r, .Y),
            .z = public.ScaleCdb.readValue(f32, _cdb, scale_r, .Z),
        };
    }

    pub fn gizmoGetOperation(
        world: ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: cdb.ObjId,
    ) !ecs.GizmoOptions {
        _ = world;
        _ = entity;
        _ = entity_obj;
        _ = component_obj;
        return .{
            .translate_x = true,
            .translate_y = true,
            .translate_z = true,

            .rotate_x = true,
            .rotate_y = true,
            .rotate_z = true,

            .scale_x = true,
            .scale_y = true,
            .scale_z = true,
        };
    }

    pub fn gizmoGetMatrix(
        world: ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: cdb.ObjId,
        world_mtx: *zm.Mat,
        local_mtx: *zm.Mat,
    ) !void {
        _ = entity_obj;
        _ = component_obj;
        const wt = world.getComponent(public.WorldTransform, entity) orelse return;
        world_mtx.* = wt.mtx;

        const t = world.getComponent(public.Transform, entity) orelse return;
        local_mtx.* = t.toMat();
    }

    pub fn gizmoSetMatrix(
        world: ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: cdb.ObjId,
        mat: zm.Mat,
    ) !void {
        _ = world;
        _ = entity;
        _ = entity_obj;

        const comp_r = public.TransformCdb.read(_cdb, component_obj).?;
        const pos_obj = public.TransformCdb.readSubObj(_cdb, comp_r, .Position).?;
        const rot_obj = public.TransformCdb.readSubObj(_cdb, comp_r, .Rotation).?;
        const scl_obj = public.TransformCdb.readSubObj(_cdb, comp_r, .Scale).?;

        {
            const translate = zm.util.getTranslationVec(mat);
            const w = public.PositionCdb.write(_cdb, pos_obj).?;
            public.PositionCdb.setValue(f32, _cdb, w, .X, translate[0]);
            public.PositionCdb.setValue(f32, _cdb, w, .Y, translate[1]);
            public.PositionCdb.setValue(f32, _cdb, w, .Z, translate[2]);
            try public.PositionCdb.commit(_cdb, w);
        }

        {
            const r = zm.quatToRollPitchYaw(zm.util.getRotationQuat(mat));
            const w = public.RotationCdb.write(_cdb, rot_obj).?;
            public.RotationCdb.setValue(f32, _cdb, w, .X, std.math.radiansToDegrees(r[0]));
            public.RotationCdb.setValue(f32, _cdb, w, .Y, std.math.radiansToDegrees(r[1]));
            public.RotationCdb.setValue(f32, _cdb, w, .Z, std.math.radiansToDegrees(r[2]));
            try public.RotationCdb.commit(_cdb, w);
        }

        {
            const sc = zm.util.getScaleVec(mat);
            const w = public.ScaleCdb.write(_cdb, scl_obj).?;
            public.ScaleCdb.setValue(f32, _cdb, w, .X, sc[0]);
            public.ScaleCdb.setValue(f32, _cdb, w, .Y, sc[1]);
            public.ScaleCdb.setValue(f32, _cdb, w, .Z, sc[2]);
            try public.ScaleCdb.commit(_cdb, w);
        }
    }
});

const world_tranform_c = cetech1.ecs.ComponentI.implement(public.WorldTransform, .{}, struct {});

// TODO: SHIT
const transform_system_i = ecs.SystemI.implement(
    .{
        .name = "transform.transform",
        .multi_threaded = true,
        .phase = ecs.OnValidate,
        .query = &.{
            .{ .id = ecs.id(public.WorldTransform), .inout = .Out },
            .{ .id = ecs.id(public.WorldTransform), .inout = .In, .oper = .Optional, .src = .{ .id = ecs.Cascade } },
            .{ .id = ecs.id(public.Transform), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            while (it.next()) {
                var zone_iner_ctx = _profiler.ZoneN(@src(), "Transform iner");
                defer zone_iner_ctx.End();

                const world_transform = it.field(public.WorldTransform, 0).?;
                const parent_world_transform = it.field(public.WorldTransform, 1);

                const transform = it.field(public.Transform, 2).?;

                const count = it.count();

                // log.debug("{}", .{count});

                if (parent_world_transform) |p| {
                    if (it.isSelf(2)) {
                        for (0..count) |i| {
                            const translate_model_mat = zm.translation(transform[i].position.x, transform[i].position.y, transform[i].position.z);
                            const rot_model_mat = zm.quatToMat(transform[i].rotation.q);
                            const scl_model_mat = zm.scaling(transform[i].scale.x, transform[i].scale.y, transform[i].scale.z);

                            world_transform[i].mtx = zm.mul(p[0].mtx, translate_model_mat);
                            world_transform[i].mtx = zm.mul(rot_model_mat, world_transform[i].mtx);
                            world_transform[i].mtx = zm.mul(scl_model_mat, world_transform[i].mtx);
                        }
                    } else {
                        for (0..count) |i| {
                            const translate_model_mat = zm.translation(transform[0].position.x, transform[0].position.y, transform[0].position.z);
                            const rot_model_mat = zm.quatToMat(transform[0].rotation.q);
                            const scl_model_mat = zm.scaling(transform[0].scale.x, transform[0].scale.y, transform[0].scale.z);

                            world_transform[i].mtx = zm.mul(p[0].mtx, translate_model_mat);
                            world_transform[i].mtx = zm.mul(rot_model_mat, world_transform[i].mtx);
                            world_transform[i].mtx = zm.mul(scl_model_mat, world_transform[i].mtx);
                        }
                    }
                } else {
                    if (it.isSelf(2)) {
                        for (0..count) |i| {
                            const translate_model_mat = zm.translation(transform[i].position.x, transform[i].position.y, transform[i].position.z);
                            const rot_model_mat = zm.quatToMat(transform[i].rotation.q);
                            const scl_model_mat = zm.scaling(transform[i].scale.x, transform[i].scale.y, transform[i].scale.z);

                            world_transform[i].mtx = translate_model_mat;
                            world_transform[i].mtx = zm.mul(rot_model_mat, world_transform[i].mtx);
                            world_transform[i].mtx = zm.mul(scl_model_mat, world_transform[i].mtx);
                        }
                    } else {
                        for (0..count) |i| {
                            const translate_model_mat = zm.translation(transform[0].position.x, transform[0].position.y, transform[0].position.z);
                            const rot_model_mat = zm.quatToMat(transform[0].rotation.q);
                            const scl_model_mat = zm.scaling(transform[0].scale.x, transform[0].scale.y, transform[0].scale.z);

                            world_transform[i].mtx = translate_model_mat;
                            world_transform[i].mtx = zm.mul(rot_model_mat, world_transform[i].mtx);
                            world_transform[i].mtx = zm.mul(scl_model_mat, world_transform[i].mtx);
                        }
                    }
                }
            }
        }
    },
);

const set_position_node_i = graphvm.NodeI.implement(
    .{
        .name = "Set position",
        .type_name = "transform_set_position",
        .category = "Transform",
        .sidefect = true,
    },
    null,
    struct {
        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = self;
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", false), graphvm.PinTypes.Flow, null),
                    graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", false), ecs.PinTypes.Entity, null),
                    graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", false), graphvm.PinTypes.VEC3F, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{}),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = out_pins; // autofix
            _ = self;

            _, const ent = in_pins.read(ecs.EntityId, 1) orelse return;
            _, const position = in_pins.read([3]f32, 2) orelse return;

            const w = _graphvm.getContext(anyopaque, args.instance, ecs.ECS_WORLD_CONTEXT) orelse return;
            const world = _ecs.toWorld(w);

            var t = world.getComponent(public.Transform, ent).?.*;
            t.position = .{
                .x = position[0],
                .y = position[1],
                .z = position[2],
            };
            _ = world.setId(public.Transform, ent, &t);
        }
    },
);

const transform_ecs_category_i = ecs.ComponentCategoryI.implement(.{ .name = "Transform", .order = 10 });

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

        // Transform
        {
            const idx = try _cdb.addType(
                db,
                public.TransformCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.TransformCdb.propIdx(.Position),
                        .name = "position",
                        .type = .SUBOBJECT,
                        .type_hash = public.PositionCdb.type_hash,
                    },
                    .{
                        .prop_idx = public.TransformCdb.propIdx(.Rotation),
                        .name = "rotation",
                        .type = .SUBOBJECT,
                        .type_hash = public.RotationCdb.type_hash,
                    },
                    .{
                        .prop_idx = public.TransformCdb.propIdx(.Scale),
                        .name = "scale",
                        .type = .SUBOBJECT,
                        .type_hash = public.ScaleCdb.type_hash,
                    },
                },
            );

            const default_quat = try _cdb.createObject(db, idx);
            const default_quat_w = _cdb.writeObj(default_quat).?;

            const default_pos = try public.PositionCdb.createObject(_cdb, db);
            const default_pos_w = public.PositionCdb.write(_cdb, default_pos).?;
            try public.TransformCdb.setSubObj(_cdb, default_quat_w, .Position, default_pos_w);

            const default_rot = try public.RotationCdb.createObject(_cdb, db);
            const default_rot_w = public.RotationCdb.write(_cdb, default_rot).?;
            try public.TransformCdb.setSubObj(_cdb, default_quat_w, .Rotation, default_rot_w);

            const default_scale = try public.ScaleCdb.createObject(_cdb, db);
            const default_scale_w = public.ScaleCdb.write(_cdb, default_scale).?;
            try public.TransformCdb.setSubObj(_cdb, default_quat_w, .Scale, default_scale_w);

            try _cdb.writeCommit(default_pos_w);
            try _cdb.writeCommit(default_rot_w);
            try _cdb.writeCommit(default_scale_w);

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
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _graphvm = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, ecs.ComponentCategoryI, &transform_ecs_category_i, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &world_tranform_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &transform_c, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &transform_system_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &set_position_node_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_transform(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
