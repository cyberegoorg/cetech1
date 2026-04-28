const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;
const apidb = cetech1.apidb;

const editor = @import("editor");

pub const GizmoResult = struct {
    manipulate: bool = false,
    using: bool = false,
};

pub fn ecsGizmoMenu(allocator: std.mem.Allocator, world: ecs.World, entity: ecs.EntityId, selected_ent_obj: cdb.ObjId, selected_component: ?cdb.ObjId, options: *editor.GizmoOptions) anyerror!void {
    return api.ecsGizmoMenu(allocator, world, entity, selected_ent_obj, selected_component, options);
}
pub fn ecsGizmoSupported(allocator: std.mem.Allocator, db: cdb.DbId, entity_obj: cdb.ObjId, component_obj: ?cdb.ObjId) anyerror!bool {
    return api.ecsGizmoSupported(allocator, db, entity_obj, component_obj);
}
pub fn ecsGizmo(allocator: std.mem.Allocator, options: editor.GizmoOptions, db: cdb.DbId, world: ecs.World, entity: ecs.EntityId, entity_obj: cdb.ObjId, component_obj: ?cdb.ObjId, view: math.Mat44f, projection: math.Mat44f, origin: math.Vec2f, size: math.Vec2f) anyerror!GizmoResult {
    return api.ecsGizmo(allocator, options, db, world, entity, entity_obj, component_obj, view, projection, origin, size);
}

pub const EditorGizmoApi = struct {
    ecsGizmoMenu: *const fn (
        allocator: std.mem.Allocator,
        world: ecs.World,
        entity: ecs.EntityId,
        selected_ent_obj: cdb.ObjId,
        selected_component: ?cdb.ObjId,
        options: *editor.GizmoOptions,
    ) anyerror!void,

    ecsGizmoSupported: *const fn (
        allocator: std.mem.Allocator,
        db: cdb.DbId,
        entity_obj: cdb.ObjId,
        component_obj: ?cdb.ObjId,
    ) anyerror!bool,

    ecsGizmo: *const fn (
        allocator: std.mem.Allocator,
        options: editor.GizmoOptions,
        db: cdb.DbId,
        world: ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: ?cdb.ObjId,
        view: math.Mat44f,
        projection: math.Mat44f,
        origin: math.Vec2f,
        size: math.Vec2f,
    ) anyerror!GizmoResult,
};

pub var api: *const EditorGizmoApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, EditorGizmoApi).?;
}
