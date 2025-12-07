const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;
const Tag = assetdb.Tag;
const Icons = cetech1.coreui.Icons;
const zm = cetech1.math.zm;
const ecs = cetech1.ecs;

const transform = @import("transform");
const public = @import("gizmo.zig");

const module_name = .editor_gizmo;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _ecs: *const cetech1.ecs.EcsAPI = undefined;

// Global state
const G = struct {};
var _g: *G = undefined;

var api = public.EditorGizmoApi{
    .ecsGizmoMenu = ecsGizmoMenu,
    .ecsGizmo = ecsGizmo,
    .ecsGizmoSupported = ecsGizmoSupported,
};

fn lessThanGizmoPriority(_: void, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const db = _cdb.getDbFromObjid(lhs);

    const l_order = blk: {
        const component = _ecs.findComponentIByCdbHash(_cdb.getTypeHash(db, lhs.type_idx).?) orelse break :blk std.math.inf(f32);
        break :blk component.gizmoPriority;
    };

    const r_order = blk: {
        const component = _ecs.findComponentIByCdbHash(_cdb.getTypeHash(db, rhs.type_idx).?) orelse break :blk std.math.inf(f32);
        break :blk component.gizmoPriority;
    };

    return l_order > r_order;
}

fn ecsGizmoMenu(allocator: std.mem.Allocator, world: ecs.World, entity: ecs.EntityId, entity_obj: cdb.ObjId, component_obj: ?cdb.ObjId, options: *ecs.GizmoOptions) !void {
    const db = _cdb.getDbFromObjid(entity_obj);

    if (!try ecsGizmoSupported(
        allocator,
        db,
        entity_obj,
        component_obj,
    )) return;

    var component_gizmo_options: ecs.GizmoOptions = .{};
    if (component_obj) |c_obj| {
        const component_hash = _cdb.getTypeHash(db, c_obj.type_idx).?;
        const ci = _ecs.findComponentIByCdbHash(component_hash).?;

        if (ci.gizmoGetOperation) |gizmoGetOperation| {
            component_gizmo_options = try gizmoGetOperation(world, entity, entity_obj, c_obj);
        }
    } else {
        const top_level_obj_r = ecs.EntityCdb.read(_cdb, entity_obj).?;
        if (try ecs.EntityCdb.readSubObjSet(_cdb, top_level_obj_r, .components, allocator)) |components| {
            defer allocator.free(components);

            std.sort.insertion(cdb.ObjId, components, {}, lessThanGizmoPriority);

            for (components) |c_obj| {
                const component_hash = _cdb.getTypeHash(db, c_obj.type_idx).?;
                const ci = _ecs.findComponentIByCdbHash(component_hash).?;

                if (ci.gizmoGetOperation) |gizmoGetOperation| {
                    component_gizmo_options = try gizmoGetOperation(world, entity, entity_obj, c_obj);
                    break;
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
        if (_coreui.beginMenu(allocator, Icons.Gizmo, true, null)) {
            defer _coreui.endMenu();

            var local_mode = options.mode == .local;
            var world_mode = options.mode == .world;

            if (_coreui.menuItemPtr(allocator, Icons.WorldMode ++ "  " ++ "World", .{ .selected = &world_mode }, null)) {
                options.mode = if (world_mode) .world else .local;
            }
            if (_coreui.menuItemPtr(allocator, Icons.LocalMode ++ "  " ++ "Local", .{ .selected = &local_mode }, null)) {
                options.mode = if (local_mode) .local else .world;
            }

            _coreui.separator();
            _coreui.text(Icons.Snap ++ "  " ++ "Snap");
            _coreui.sameLine(.{});
            var snap = options.snap[0];
            _coreui.setNextItemWidth(4.0 * _coreui.getStyle().font_size_base);
            if (_coreui.dragF32("", .{
                .v = &snap,
                .min = 0,
                .max = 100,
            })) {
                options.snap = @splat(snap);
            }
        }
    }

    {
        if (_coreui.toggleButton(Icons.Snap, &options.snap_enabled)) {}
    }

    {
        _coreui.beginDisabled(.{ .disabled = !(component_gizmo_options.translate_x or component_gizmo_options.translate_y or component_gizmo_options.translate_z) });
        _coreui.endDisabled();
        var enabled = (options.translate_x or options.translate_y or options.translate_z);
        if (_coreui.toggleButton(Icons.Position, &enabled)) {
            options.translate_x = enabled;
            options.translate_y = enabled;
            options.translate_z = enabled;
        }
    }

    {
        _coreui.beginDisabled(.{ .disabled = !(component_gizmo_options.rotate_x or component_gizmo_options.rotate_y or component_gizmo_options.rotate_z) });
        _coreui.endDisabled();
        var enabled = (options.rotate_x or options.rotate_y or options.rotate_z);
        if (_coreui.toggleButton(Icons.Rotation, &enabled)) {
            options.rotate_x = enabled;
            options.rotate_y = enabled;
            options.rotate_z = enabled;
        }
    }

    {
        _coreui.beginDisabled(.{ .disabled = !(component_gizmo_options.scale_x or component_gizmo_options.scale_y or component_gizmo_options.scale_z) });
        _coreui.endDisabled();
        var enabled = (options.scale_x or options.scale_y or options.scale_z);
        if (_coreui.toggleButton(Icons.Scale, &enabled)) {
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
    var component_i: ?*const ecs.ComponentI = null;

    if (component_obj) |c_obj| {
        gizmo_component_obj = c_obj;

        const component_hash = _cdb.getTypeHash(db, c_obj.type_idx).?;
        const ci = _ecs.findComponentIByCdbHash(component_hash).?;

        if (ci.gizmoGetMatrix) |gizmoGetMatrix| {
            _ = gizmoGetMatrix;
            component_i = ci;
        }
    } else {
        const top_level_obj_r = ecs.EntityCdb.read(_cdb, entity_obj).?;
        if (try ecs.EntityCdb.readSubObjSet(_cdb, top_level_obj_r, .components, allocator)) |components| {
            defer allocator.free(components);

            std.sort.insertion(cdb.ObjId, components, {}, lessThanGizmoPriority);

            for (components) |c_obj| {
                const component_hash = _cdb.getTypeHash(db, c_obj.type_idx).?;
                const ci = _ecs.findComponentIByCdbHash(component_hash).?;

                if (ci.gizmoGetMatrix) |gizmoGetMatrix| {
                    _ = gizmoGetMatrix;
                    component_i = ci;
                    gizmo_component_obj = c_obj;
                    break;
                }
            }
        }
    }

    return component_i != null;
}

fn ecsGizmo(
    allocator: std.mem.Allocator,
    options: ecs.GizmoOptions,
    db: cdb.DbId,
    world: ecs.World,
    entity: ecs.EntityId,
    entity_obj: cdb.ObjId,
    component_obj: ?cdb.ObjId,
    view: [16]f32,
    projection: [16]f32,
    origin: [2]f32,
    size: [2]f32,
) !public.GizmoResult {
    var gizmo_manipulate = false;
    var gizmo_using = false;

    var gizmo_component_obj: ?cdb.ObjId = null;
    var component_i: ?*const ecs.ComponentI = null;

    if (component_obj) |c_obj| {
        gizmo_component_obj = c_obj;

        const component_hash = _cdb.getTypeHash(db, c_obj.type_idx).?;
        const ci = _ecs.findComponentIByCdbHash(component_hash).?;

        if (ci.gizmoGetMatrix) |gizmoGetMatrix| {
            _ = gizmoGetMatrix;
            component_i = ci;
        }
    } else {
        const top_level_obj_r = ecs.EntityCdb.read(_cdb, entity_obj).?;
        if (try ecs.EntityCdb.readSubObjSet(_cdb, top_level_obj_r, .components, allocator)) |components| {
            defer allocator.free(components);

            std.sort.insertion(cdb.ObjId, components, {}, lessThanGizmoPriority);

            for (components) |c_obj| {
                const component_hash = _cdb.getTypeHash(db, c_obj.type_idx).?;
                const ci = _ecs.findComponentIByCdbHash(component_hash).?;

                if (ci.gizmoGetMatrix) |gizmoGetMatrix| {
                    _ = gizmoGetMatrix;
                    component_i = ci;
                    gizmo_component_obj = c_obj;
                    break;
                }
            }
        }
    }

    if (component_i) |ci| {
        var world_mtx = zm.identity();
        var local_mtx = zm.identity();

        try ci.gizmoGetMatrix.?(
            world,
            entity,
            entity_obj,
            gizmo_component_obj.?,
            &world_mtx,
            &local_mtx,
        );

        var world_mtx_arr = zm.matToArr(world_mtx);

        _coreui.gizmoSetAlternativeWindow(_coreui.getCurrentWindow());
        _coreui.gizmoSetDrawList(_coreui.getWindowDrawList());
        _coreui.gizmoSetRect(origin[0], origin[1], size[0], size[1]);

        const gizmo_options = try component_i.?.gizmoGetOperation.?(world, entity, entity_obj, gizmo_component_obj.?);
        var delta_mtx = zm.matToArr(zm.identity());

        gizmo_manipulate = _coreui.gizmoManipulate(
            &view,
            &projection,
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
            &world_mtx_arr,
            .{
                .snap = if (options.snap_enabled) &options.snap else null,
                .delta_matrix = &delta_mtx,
            },
        );
        gizmo_using = _coreui.gizmoIsOver() or _coreui.gizmoIsUsing();

        if (gizmo_manipulate) {
            if (component_i.?.gizmoSetMatrix) |gizmoSetMatrix| {
                try gizmoSetMatrix(
                    world,
                    entity,
                    entity_obj,
                    gizmo_component_obj.?,
                    zm.mul(local_mtx, zm.matFromArr(delta_mtx)),
                );
            }
        }
    }

    return .{ .manipulate = gizmo_manipulate, .using = gizmo_using };
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _ecs = apidb.getZigApi(module_name, cetech1.ecs.EcsAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    //
    try apidb.setOrRemoveZigApi(module_name, public.EditorGizmoApi, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_gizmo(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
