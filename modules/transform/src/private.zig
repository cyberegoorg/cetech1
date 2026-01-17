const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;
const math = cetech1.math;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const public = @import("transform.zig");

const graphvm = @import("graphvm");
const editor = @import("editor");

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
const G = struct {
    editor_component_aspect: *editor.EditorComponentAspect = undefined,
};

var _g: *G = undefined;

const api = public.TransformApi{
    .transform = transform_entity,
    .transformOnlyChilds = transform_childs,
};

const editor_component_aspect = editor.EditorComponentAspect.implement(
    .{
        .gizmoPriority = 100,
    },
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

        pub fn gizmoGetOperation(
            world: ecs.World,
            entity: ecs.EntityId,
            entity_obj: cdb.ObjId,
            component_obj: cdb.ObjId,
        ) !editor.GizmoOptions {
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
            world_mtx: *math.Mat44f,
            local_mtx: *math.Mat44f,
        ) !void {
            _ = entity_obj;
            _ = component_obj;
            const wt = world.getComponent(public.WorldTransformComponent, entity) orelse return;
            world_mtx.* = wt.world.toMat();

            const t = world.getComponent(public.LocalTransformComponent, entity) orelse return;
            local_mtx.* = t.local.toMat();
        }

        pub fn gizmoSetMatrix(
            world: ecs.World,
            entity: ecs.EntityId,
            entity_obj: cdb.ObjId,
            component_obj: cdb.ObjId,
            mat: math.Mat44f,
        ) !void {
            _ = world;
            _ = entity;
            _ = entity_obj;

            const comp_r = public.LocalTransformComponentCdb.read(_cdb, component_obj).?;
            const pos_obj = public.LocalTransformComponentCdb.readSubObj(_cdb, comp_r, .Position).?;
            const rot_obj = public.LocalTransformComponentCdb.readSubObj(_cdb, comp_r, .Rotation).?;
            const scl_obj = public.LocalTransformComponentCdb.readSubObj(_cdb, comp_r, .Scale).?;

            {
                const translate = mat.getTranslation();
                const w = cdb_types.PositionCdb.write(_cdb, pos_obj).?;
                cdb_types.PositionCdb.setValue(f32, _cdb, w, .X, translate.x);
                cdb_types.PositionCdb.setValue(f32, _cdb, w, .Y, translate.y);
                cdb_types.PositionCdb.setValue(f32, _cdb, w, .Z, translate.z);
                try cdb_types.PositionCdb.commit(_cdb, w);
            }

            {
                const r = mat.getRotation().toRollPitchYaw();
                const w = cdb_types.RotationCdb.write(_cdb, rot_obj).?;
                cdb_types.RotationCdb.setValue(f32, _cdb, w, .X, std.math.radiansToDegrees(r.x));
                cdb_types.RotationCdb.setValue(f32, _cdb, w, .Y, std.math.radiansToDegrees(r.y));
                cdb_types.RotationCdb.setValue(f32, _cdb, w, .Z, std.math.radiansToDegrees(r.z));
                try cdb_types.RotationCdb.commit(_cdb, w);
            }

            {
                const sc = mat.getScale();
                const w = cdb_types.ScaleCdb.write(_cdb, scl_obj).?;
                cdb_types.ScaleCdb.setValue(f32, _cdb, w, .X, sc.x);
                cdb_types.ScaleCdb.setValue(f32, _cdb, w, .Y, sc.y);
                cdb_types.ScaleCdb.setValue(f32, _cdb, w, .Z, sc.z);
                try cdb_types.ScaleCdb.commit(_cdb, w);
            }
        }
    },
);

const local_transform_c = ecs.ComponentI.implement(
    public.LocalTransformComponent,
    .{
        .display_name = "Local transform",
        .cdb_type_hash = public.LocalTransformComponentCdb.type_hash,
        .category = "Transform",
        .category_order = 0.3,
        .with = &.{ecs.id(public.WorldTransformComponent)},
        .default_data = std.mem.asBytes(&public.LocalTransformComponent{}),
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const t = _cdb.readObj(obj) orelse return;

            const transform = std.mem.bytesAsValue(public.LocalTransformComponent, data);

            const pos_obj = public.LocalTransformComponentCdb.readSubObj(_cdb, t, .Position).?;
            const pos_r = cdb_types.PositionCdb.read(_cdb, pos_obj).?;
            transform.local.position = .{
                .x = cdb_types.PositionCdb.readValue(f32, _cdb, pos_r, .X),
                .y = cdb_types.PositionCdb.readValue(f32, _cdb, pos_r, .Y),
                .z = cdb_types.PositionCdb.readValue(f32, _cdb, pos_r, .Z),
            };

            const rot_obj = public.LocalTransformComponentCdb.readSubObj(_cdb, t, .Rotation).?;
            const rot_r = cdb_types.PositionCdb.read(_cdb, rot_obj).?;
            transform.local.rotation = .fromRollPitchYaw(
                std.math.degreesToRadians(cdb_types.RotationCdb.readValue(f32, _cdb, rot_r, .X)),
                std.math.degreesToRadians(cdb_types.RotationCdb.readValue(f32, _cdb, rot_r, .Y)),
                std.math.degreesToRadians(cdb_types.RotationCdb.readValue(f32, _cdb, rot_r, .Z)),
            );

            const scale_obj = public.LocalTransformComponentCdb.readSubObj(_cdb, t, .Scale).?;
            const scale_r = cdb_types.ScaleCdb.read(_cdb, scale_obj).?;
            transform.local.scale = .{
                .x = cdb_types.ScaleCdb.readValue(f32, _cdb, scale_r, .X),
                .y = cdb_types.ScaleCdb.readValue(f32, _cdb, scale_r, .Y),
                .z = cdb_types.ScaleCdb.readValue(f32, _cdb, scale_r, .Z),
            };
        }
    },
);

const world_tranform_c = cetech1.ecs.ComponentI.implement(
    public.WorldTransformComponent,
    .{
        .display_name = "World transform",
        .default_data = std.mem.asBytes(&public.WorldTransformComponent{}),
    },
    struct {
        pub fn onCreate(transforms: []public.WorldTransformComponent) !void {
            for (transforms) |*t| {
                t.* = .{};
            }
        }
    },
);

fn transform_entity(world: ecs.World, entity: ecs.EntityId) void {
    const parent_transform =
        if (world.parent(entity)) |parent|
            if (world.getComponent(public.WorldTransformComponent, parent)) |c|
                c.world
            else
                null
        else
            null;

    transform_entity_parented(world, entity, parent_transform, false);
}
fn transform_childs(world: ecs.World, entity: ecs.EntityId) void {
    const parent_transform =
        if (world.parent(entity)) |parent|
            if (world.getComponent(public.WorldTransformComponent, parent)) |c|
                c.world
            else
                null
        else
            null;

    transform_entity_parented(world, entity, parent_transform, true);
}

fn transform_entity_parented(world: ecs.World, entity: ecs.EntityId, parent_transform: ?math.Transform, only_child: bool) void {
    const local_transform = world.getComponent(public.LocalTransformComponent, entity).?;

    const final = blk: {
        if (only_child) break :blk world.getComponent(public.WorldTransformComponent, entity).?.world;

        if (parent_transform) |pt| break :blk local_transform.local.mulTransform(pt) else break :blk local_transform.local;
    };

    if (!only_child) {
        var world_tranform = world.getMutComponent(public.WorldTransformComponent, entity).?;
        world_tranform.world = final;
    }

    world.modified(entity, public.WorldTransformComponent);

    var child_it = world.children(entity);
    while (child_it.nextChildren()) {
        for (child_it.entities()) |ent| {
            transform_entity_parented(world, ent, final, false);
        }
    }
}

// TODO: SHIT
const transform_system_i = ecs.SystemI.implement(
    .{
        .name = "transform.transform",
        .multi_threaded = true,
        .phase = ecs.PostUpdate,
        .query = &.{
            .{ .id = ecs.id(public.WorldTransformComponent), .inout = .Out },
            .{ .id = ecs.id(public.WorldTransformComponent), .inout = .In, .oper = .Optional, .src = .{ .id = ecs.Cascade } },
            .{ .id = ecs.id(public.LocalTransformComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            // while (it.next()) {
            var zone_iner_ctx = _profiler.ZoneN(@src(), "Transform iner");
            defer zone_iner_ctx.End();

            const world_transforms = it.field(public.WorldTransformComponent, 0).?;
            const parent_world_transforms = it.field(public.WorldTransformComponent, 1);

            const transforms = it.field(public.TransformComponent, 2).?;

            const count = it.count();

            // log.debug("{}", .{count});

            if (parent_world_transforms) |parent_transform| {
                if (it.isSelf(2)) {
                    for (0..count) |i| {
                        // world_transform[i].world = parent_transform[0].world.mulTransform(transform[i].local);
                        world_transforms[i].world = transforms[i].local.mulTransform(parent_transform[0].world);
                    }
                } else {
                    for (0..count) |i| {
                        // world_transform[i].world = parent_transform[0].world.mulTransform(transform[0].local);
                        world_transforms[i].world = transforms[0].local.mulTransform(parent_transform[0].world);
                    }
                }
            } else {
                if (it.isSelf(2)) {
                    for (0..count) |i| {
                        world_transforms[i].world = transforms[i].local;
                    }
                } else {
                    for (0..count) |i| {
                        world_transforms[i].world = transforms[0].local;
                    }
                }
            }
        }
        // }
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
            _, const position = in_pins.read(math.Vec3f, 2) orelse return;

            const w = _graphvm.getContext(anyopaque, args.instance, ecs.ECS_WORLD_CONTEXT) orelse return;
            const world = _ecs.toWorld(w);

            var t = world.getMutComponent(public.LocalTransformComponent, ent).?;
            t.local.position = position;

            // _ = world.setComponent(public.TransformComponent, ent, &t);
            transform_entity(world, ent);
        }
    },
);

const get_position_node_i = graphvm.NodeI.implement(
    .{
        .name = "Get position",
        .type_name = "transform_get_position",
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
                    graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", false), ecs.PinTypes.Entity, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", true), graphvm.PinTypes.VEC3F, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;

            _, const ent = in_pins.read(ecs.EntityId, 0) orelse return;

            const w = _graphvm.getContext(anyopaque, args.instance, ecs.ECS_WORLD_CONTEXT) orelse return;
            const world = _ecs.toWorld(w);

            const t = world.getComponent(public.WorldTransformComponent, ent) orelse return;

            try out_pins.writeTyped(
                math.Vec3f,
                0,
                cetech1.strId64(&std.mem.toBytes(t.world.position)).id,
                t.world.position,
            );
        }
    },
);

// TODO: TEST SHIT
const vec3_to_color = graphvm.NodeI.implement(
    .{
        .name = "vec3 to color",
        .type_name = "vec3_to_color",
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
                    graphvm.NodePin.init("Vector", graphvm.NodePin.pinHash("position", false), graphvm.PinTypes.VEC3F, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Color", graphvm.NodePin.pinHash("color", true), graphvm.PinTypes.Color4f, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            _ = args;

            _, const position = in_pins.read(math.Vec3f, 0) orelse return;

            try out_pins.writeTyped(math.Vec4f, 0, cetech1.strId64(&std.mem.toBytes(position)).id, .{
                .x = position.x,
                .y = position.y,
                .z = position.z,
                .w = 1.0,
            });
        }
    },
);

const transform_ecs_category_i = ecs.ComponentCategoryI.implement(.{ .name = "Transform", .order = 10 });

const transform_set_observer_i = ecs.ObserverI.implement(
    .{
        .name = "transform.transform_set_observer_i",
        .query = &.{
            .{ .id = ecs.id(public.LocalTransformComponent), .inout = .In },
            .{ .id = ecs.id(public.WorldTransformComponent), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnSet},
    },
    struct {
        pub fn tick(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            // _ = world;
            _ = dt;

            // const local_transforms = it.field(public.TransformComponent, 0).?;
            // const world_transforms = &it.field(public.WorldTransformComponent, 1).?[0];

            // _ = local_transforms;
            // _ = world_transforms;
            // log.debug("dddd : {d}", .{it.count()});

            while (it.next()) {
                for (it.entities()) |ent| {
                    transform_entity(world, ent);
                }
            }
        }
    },
);

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // Transform
        {
            const idx = try _cdb.addType(
                db,
                public.LocalTransformComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.LocalTransformComponentCdb.propIdx(.Position),
                        .name = "position",
                        .type = .SUBOBJECT,
                        .type_hash = cdb_types.PositionCdb.type_hash,
                    },
                    .{
                        .prop_idx = public.LocalTransformComponentCdb.propIdx(.Rotation),
                        .name = "rotation",
                        .type = .SUBOBJECT,
                        .type_hash = cdb_types.RotationCdb.type_hash,
                    },
                    .{
                        .prop_idx = public.LocalTransformComponentCdb.propIdx(.Scale),
                        .name = "scale",
                        .type = .SUBOBJECT,
                        .type_hash = cdb_types.ScaleCdb.type_hash,
                    },
                },
            );

            try public.LocalTransformComponentCdb.addAspect(
                editor.EditorComponentAspect,
                _cdb,
                db,
                _g.editor_component_aspect,
            );

            //
            // Default
            //
            const default_quat = try _cdb.createObject(db, idx);
            const default_quat_w = _cdb.writeObj(default_quat).?;

            const default_pos = try cdb_types.PositionCdb.createObject(_cdb, db);
            const default_pos_w = cdb_types.PositionCdb.write(_cdb, default_pos).?;
            try public.LocalTransformComponentCdb.setSubObj(_cdb, default_quat_w, .Position, default_pos_w);

            const default_rot = try cdb_types.RotationCdb.createObject(_cdb, db);
            const default_rot_w = cdb_types.RotationCdb.write(_cdb, default_rot).?;
            try public.LocalTransformComponentCdb.setSubObj(_cdb, default_quat_w, .Rotation, default_rot_w);

            const default_scale = try cdb_types.ScaleCdb.createObject(_cdb, db);
            const default_scale_w = cdb_types.ScaleCdb.write(_cdb, default_scale).?;
            try public.LocalTransformComponentCdb.setSubObj(_cdb, default_quat_w, .Scale, default_scale_w);

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

    // impl api
    try apidb.setOrRemoveZigApi(module_name, public.TransformApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, ecs.ComponentCategoryI, &transform_ecs_category_i, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &world_tranform_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &local_transform_c, load);
    //try apidb.implOrRemove(module_name, ecs.SystemI, &transform_system_i, load);

    try apidb.implOrRemove(module_name, ecs.ObserverI, &transform_set_observer_i, load);

    // Impl graphvm nodes
    try apidb.implOrRemove(module_name, graphvm.NodeI, &set_position_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &get_position_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &vec3_to_color, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});
    _g.editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_editor_component_aspect", editor_component_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_transform(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
