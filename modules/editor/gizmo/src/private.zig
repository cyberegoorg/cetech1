const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;
const Icons = cetech1.coreui.Icons;
const zm = cetech1.math.zm;
const ecs = cetech1.ecs;
const math = cetech1.math;

const transform = @import("transform");
const editor = @import("editor");
const public = @import("gizmo.zig");

const module_name = .editor_gizmo;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _assetdb: *const assetdb.AssetDBAPI = undefined;

const tempalloc = cetech1.tempalloc;

// Global state
const G = struct {};
var _g: *G = undefined;

const api = public.EditorGizmoApi{
    .ecsGizmoMenu = ecsGizmoMenu,
    .ecsGizmo = ecsGizmo,
    .ecsGizmoSupported = ecsGizmoSupported,
};

fn lessThanGizmoPriority(_: void, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const db = cdb.getDbFromObjid(lhs);

    const l_order = blk: {
        const component = cdb.getAspect(editor.EditorComponentAspect, db, lhs.type_idx) orelse break :blk std.math.inf(f32);
        break :blk component.gizmoPriority;
    };

    const r_order = blk: {
        const component = cdb.getAspect(editor.EditorComponentAspect, db, rhs.type_idx) orelse break :blk std.math.inf(f32);
        break :blk component.gizmoPriority;
    };

    return l_order > r_order;
}

fn ecsGizmoMenu(allocator: std.mem.Allocator, world: ecs.World, entity: ecs.EntityId, entity_obj: cdb.ObjId, component_obj: ?cdb.ObjId, options: *editor.GizmoOptions) !void {
    const db = cdb.getDbFromObjid(entity_obj);

    if (!try ecsGizmoSupported(
        allocator,
        db,
        entity_obj,
        component_obj,
    )) return;

    var component_gizmo_options: editor.GizmoOptions = .{};
    if (component_obj) |c_obj| {
        if (cdb.getAspect(editor.EditorComponentAspect, db, c_obj.type_idx)) |aspect| {
            if (aspect.gizmoGetOperation) |gizmoGetOperation| {
                component_gizmo_options = try gizmoGetOperation(world, entity, entity_obj, c_obj);
            }
        }
    } else {
        const top_level_obj_r = ecs.EntityCdb.read(entity_obj).?;
        if (try ecs.EntityCdb.readSubObjSet(top_level_obj_r, .Components, allocator)) |components| {
            defer allocator.free(components);

            std.sort.insertion(cdb.ObjId, components, {}, lessThanGizmoPriority);

            for (components) |c_obj| {
                if (cdb.getAspect(editor.EditorComponentAspect, db, c_obj.type_idx)) |aspect| {
                    if (aspect.gizmoGetOperation) |gizmoGetOperation| {
                        component_gizmo_options = try gizmoGetOperation(world, entity, entity_obj, c_obj);
                        break;
                    }
                }
            }
        }
    }

    if (options.empty()) {
        options.* = component_gizmo_options;

        options.scale_x = false;
        options.scale_y = false;
        options.scale_z = false;
    }

    {
        if (coreui.beginMenu(allocator, Icons.Gizmo, true, null)) {
            defer coreui.endMenu();

            var local_mode = options.mode == .Local;
            var world_mode = options.mode == .World;

            if (coreui.menuItemPtr(allocator, Icons.WorldMode ++ "  " ++ "World", .{ .selected = &world_mode }, null)) {
                options.mode = if (world_mode) .World else .Local;
            }
            if (coreui.menuItemPtr(allocator, Icons.LocalMode ++ "  " ++ "Local", .{ .selected = &local_mode }, null)) {
                options.mode = if (local_mode) .Local else .World;
            }

            coreui.separator();
            coreui.text(Icons.Snap ++ "  " ++ "Snap");
            coreui.sameLine(.{});
            var snap = options.snap.x;
            coreui.setNextItemWidth(4.0 * coreui.getStyle().font_size_base);
            if (coreui.dragF32("", .{
                .v = &snap,
                .min = 0,
                .max = 100,
            })) {
                options.snap = .splat(snap);
            }
        }
    }

    {
        if (coreui.toggleButton(Icons.Snap, &options.snap_enabled)) {}
    }

    {
        coreui.beginDisabled(.{ .disabled = !(component_gizmo_options.translate_x or component_gizmo_options.translate_y or component_gizmo_options.translate_z) });
        coreui.endDisabled();
        var enabled = (options.translate_x or options.translate_y or options.translate_z);
        if (coreui.toggleButton(Icons.Position, &enabled)) {
            options.translate_x = enabled;
            options.translate_y = enabled;
            options.translate_z = enabled;
        }
    }

    {
        coreui.beginDisabled(.{ .disabled = !(component_gizmo_options.rotate_x or component_gizmo_options.rotate_y or component_gizmo_options.rotate_z) });
        coreui.endDisabled();
        var enabled = (options.rotate_x or options.rotate_y or options.rotate_z);
        if (coreui.toggleButton(Icons.Rotation, &enabled)) {
            options.rotate_x = enabled;
            options.rotate_y = enabled;
            options.rotate_z = enabled;
        }
    }

    {
        coreui.beginDisabled(.{ .disabled = !(component_gizmo_options.scale_x or component_gizmo_options.scale_y or component_gizmo_options.scale_z) });
        coreui.endDisabled();
        var enabled = (options.scale_x or options.scale_y or options.scale_z);
        if (coreui.toggleButton(Icons.Scale, &enabled)) {
            options.scale_x = enabled;
            options.scale_y = enabled;
            options.scale_z = enabled;
        }
    }
}

fn ecsGizmoSupported(
    allocator: std.mem.Allocator,
    db: cdb.DbId,
    entity_obj: cdb.ObjId,
    component_obj: ?cdb.ObjId,
) !bool {
    var gizmo_component_obj: ?cdb.ObjId = null;
    var component_i: ?*const editor.EditorComponentAspect = null;

    if (component_obj) |c_obj| {
        gizmo_component_obj = c_obj;

        if (cdb.getAspect(editor.EditorComponentAspect, db, c_obj.type_idx)) |aspect| {
            if (aspect.gizmoGetMatrix) |gizmoGetMatrix| {
                _ = gizmoGetMatrix;
                component_i = aspect;
            }
        }
    } else {
        const top_level_obj_r = ecs.EntityCdb.read(entity_obj) orelse return false;
        if (try ecs.EntityCdb.readSubObjSet(top_level_obj_r, .Components, allocator)) |components| {
            defer allocator.free(components);

            std.sort.insertion(cdb.ObjId, components, {}, lessThanGizmoPriority);

            for (components) |c_obj| {
                if (cdb.getAspect(editor.EditorComponentAspect, db, c_obj.type_idx)) |aspect| {
                    if (aspect.gizmoGetMatrix) |gizmoGetMatrix| {
                        _ = gizmoGetMatrix;
                        component_i = aspect;
                        gizmo_component_obj = c_obj;
                        break;
                    }
                }
            }
        }
    }

    return component_i != null;
}

fn ecsGizmo(
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
) !public.GizmoResult {
    var gizmo_manipulate = false;
    var gizmo_using = false;

    var gizmo_component_obj: ?cdb.ObjId = null;
    var component_i: ?*const editor.EditorComponentAspect = null;

    if (component_obj) |c_obj| {
        gizmo_component_obj = c_obj;

        if (cdb.getAspect(editor.EditorComponentAspect, db, c_obj.type_idx)) |aspect| {
            if (aspect.gizmoGetMatrix) |gizmoGetMatrix| {
                _ = gizmoGetMatrix;
                component_i = aspect;
            }
        }
    } else {
        const top_level_obj_r = ecs.EntityCdb.read(entity_obj).?;
        if (try ecs.EntityCdb.readSubObjSet(top_level_obj_r, .Components, allocator)) |components| {
            defer allocator.free(components);

            std.sort.insertion(cdb.ObjId, components, {}, lessThanGizmoPriority);

            for (components) |c_obj| {
                if (cdb.getAspect(editor.EditorComponentAspect, db, c_obj.type_idx)) |aspect| {
                    if (aspect.gizmoGetMatrix) |gizmoGetMatrix| {
                        _ = gizmoGetMatrix;
                        component_i = aspect;
                        gizmo_component_obj = c_obj;
                        break;
                    }
                }
            }
        }
    }

    if (component_i) |ci| {
        var world_mtx = math.Mat44f.identity;
        var local_mtx = math.Mat44f.identity;

        try ci.gizmoGetMatrix.?(
            world,
            entity,
            entity_obj,
            gizmo_component_obj.?,
            &world_mtx,
            &local_mtx,
        );

        coreui.gizmoSetAlternativeWindow(coreui.getCurrentWindow());
        coreui.gizmoSetDrawList(coreui.getWindowDrawList());
        coreui.gizmoSetRect(origin.x, origin.y, size.x, size.y);

        const gizmo_options = try ci.gizmoGetOperation.?(world, entity, entity_obj, gizmo_component_obj.?);
        var delta_mtx = math.Mat44f{};

        gizmo_manipulate = coreui.gizmoManipulate(
            view,
            projection,
            .{
                .translate_x = options.translate_x and gizmo_options.translate_x,
                .translate_y = options.translate_y and gizmo_options.translate_y,
                .translate_z = options.translate_z and gizmo_options.translate_z,
                .rotate_x = options.rotate_x and gizmo_options.rotate_x,
                .rotate_y = options.rotate_y and gizmo_options.rotate_y,
                .rotate_z = options.rotate_z and gizmo_options.rotate_z,
                .rotate_screen = options.rotate_screen and gizmo_options.rotate_screen,
                .scale_x = options.scale_x and gizmo_options.scale_x,
                .scale_y = options.scale_y and gizmo_options.scale_y,
                .scale_z = options.scale_z and gizmo_options.scale_z,
                .bounds = options.bounds and gizmo_options.bounds,
                .scale_xu = options.scale_xu and gizmo_options.scale_xu,
                .scale_yu = options.scale_yu and gizmo_options.scale_yu,
                .scale_zu = options.scale_zu and gizmo_options.scale_zu,
            },
            options.mode,
            &world_mtx,
            .{
                .snap = if (options.snap_enabled) options.snap else null,
                .delta_matrix = &delta_mtx,
            },
        );
        gizmo_using = coreui.gizmoIsOver() or coreui.gizmoIsUsing();

        if (gizmo_manipulate) {
            if (ci.gizmoSetMatrix) |gizmoSetMatrix| {
                try gizmoSetMatrix(
                    world,
                    entity,
                    entity_obj,
                    gizmo_component_obj.?,
                    local_mtx.mul(delta_mtx),
                );
            }
        }
    }

    return .{ .manipulate = gizmo_manipulate, .using = gizmo_using };
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    //
    try apidb.setOrRemoveZigApi(module_name, public.EditorGizmoApi, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_gizmo(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
