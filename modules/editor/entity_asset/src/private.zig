const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const node_editor = cetech1.coreui_node_editor;
const assetdb = cetech1.assetdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const asset_preview = @import("asset_preview");
const editor_tree = @import("editor_tree");
const editor_tabs = @import("editor_tabs");
const editor_inspector = @import("editor_inspector");
const editor_assetdb = @import("editor_assetdb");

const module_name = .editor_entity_asset;

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
var _coreui: *const coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _editor_tree: *const editor_tree.TreeAPI = undefined;
var _inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    component_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
    entity_visual_aspect: *editor.UiVisualAspect = undefined,
    component_visual_aspect: *editor.UiVisualAspect = undefined,
    components_sort_aspect: *editor.UiSetSortPropertyAspect = undefined,
    entity_preview_aspect: *asset_preview.AssetPreviewAspectI = undefined,
    entity_children_drop_aspect: *editor.UiDropObj = undefined,
    entity_flaten_aspect: *editor_tree.UiTreeFlatenPropertyAspect = undefined,
    entity_child_storage_prop_aspect: *editor_inspector.UiPropertyAspect = undefined,
};
var _g: *G = undefined;

// Create entity asset
var create_entity_i = editor_assetdb.CreateAssetI.implement(
    ecs.EntityCdb.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try _assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                _cdb.getTypeIdx(db, ecs.EntityCdb.type_hash).?,
                "NewEntity",
            );

            const new_obj = try ecs.EntityCdb.createObject(_cdb, db);

            _ = _assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Entity ++ "  " ++ "Entity";
        }
    },
);

var debug_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.create.id) return false;

        for (selection) |obj| {
            const db = _cdb.getDbFromObjid(obj.obj);
            const ent_obj = _assetdb.getObjForAsset(obj.obj) orelse obj.obj;

            if (!ent_obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, db))) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (_coreui.uiFilterPass(allocator, f, "Add component", false) != null) return true;
        }
        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        const ent_obj = _assetdb.getObjForAsset(obj.obj) orelse obj.obj;
        if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ "  " ++ "Add component", true, filter)) {
            defer _coreui.endMenu();

            try entity_component_menu_aspect.add_menu(allocator, ent_obj, ecs.EntityCdb.propIdx(.Components), filter);
        }
    }
});

// Aspects
const entity_component_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx; // autofix

        const db = _cdb.getDbFromObjid(obj);
        const entity_r = ecs.EntityCdb.read(_cdb, obj).?;

        var components_set = cetech1.ArraySet(cdb.TypeIdx).init();
        defer components_set.deinit(allocator);

        if (try ecs.EntityCdb.readSubObjSet(_cdb, entity_r, .Components, allocator)) |components| {
            defer allocator.free(components);
            //try components_set.ensureTotalCapacity(components.len);

            for (components) |component_obj| {
                _ = try components_set.add(allocator, component_obj.type_idx);
            }
        }

        var icon_buff: [32:0]u8 = undefined;
        var labbel_buff: [128:0]u8 = undefined;

        const impls = try _apidb.getImpl(allocator, ecs.ComponentI);
        defer allocator.free(impls);

        // Create category menu first
        if (filter == null) {
            for (impls) |iface| {
                if (iface.cdb_type_hash.isEmpty()) continue;
                if (components_set.contains(_cdb.getTypeIdx(db, iface.cdb_type_hash).?)) continue;

                var buff: [128:0]u8 = undefined;
                if (iface.category) |category| {
                    const label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Folder ++ "  " ++ "{s}###{s}", .{ category, category });

                    if (_coreui.beginMenu(allocator, label, true, null)) {
                        _coreui.endMenu();
                    }
                }
            }
        }

        for (impls) |iface| {
            if (iface.cdb_type_hash.isEmpty()) continue;
            if (components_set.contains(_cdb.getTypeIdx(db, iface.cdb_type_hash).?)) continue;

            if (filter) |f| {
                if (_coreui.uiFilterPass(allocator, f, iface.display_name, false) == null) continue;
            }

            var category_open = true;
            if (filter == null) {
                if (iface.category) |category| {
                    var buff: [128:0]u8 = undefined;
                    const label = try std.fmt.bufPrintZ(&buff, "###{s}", .{category});
                    category_open = _coreui.beginMenu(allocator, label, true, null);
                }
            }

            var icon: [:0]const u8 = coreui.Icons.Component;
            const aspect = _cdb.getAspect(
                editor.EditorComponentAspect,
                db,
                _cdb.getTypeIdx(db, iface.cdb_type_hash).?,
            );

            icon = blk: {
                if (aspect) |a| {
                    if (a.uiIcons) |uiIcons| break :blk (try uiIcons(&icon_buff, allocator, .{}));
                }
                break :blk "";
            };

            const label = blk: {
                if (filter == null or iface.category == null) {
                    break :blk try std.fmt.bufPrintZ(&labbel_buff, "{s}  {s}", .{ icon, iface.display_name });
                } else {
                    break :blk try std.fmt.bufPrintZ(&labbel_buff, "{s}  {s}/{s}", .{ icon, iface.category.?, iface.display_name });
                }
            };

            if (category_open and _coreui.menuItem(allocator, label, .{}, null)) {
                const obj_w = ecs.EntityCdb.write(_cdb, obj).?;

                const value_obj = try _cdb.createObject(db, _cdb.getTypeIdx(db, iface.cdb_type_hash).?);
                const value_obj_w = _cdb.writeObj(value_obj).?;

                try ecs.EntityCdb.addSubObjToSet(_cdb, obj_w, .Components, &.{value_obj_w});

                try _cdb.writeCommit(value_obj_w);
                try _cdb.writeCommit(obj_w);
            }

            if (category_open and iface.category != null and filter == null) {
                _coreui.endMenu();
            }
        }
    }
});

var entity_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = _cdb.readObj(obj).?;

        if (ecs.EntityCdb.readStr(_cdb, obj_r, .Name)) |name| {
            return std.fmt.bufPrintZ(
                buff,
                "{s}",
                .{
                    name,
                },
            ) catch "Entity";
        }

        return std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                "Entity",
            },
        ) catch "Entity";
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = obj; // autofix
        _ = allocator; // autofix

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Entity});
    }
});

var entity_preview_aspect = asset_preview.AssetPreviewAspectI.implement(struct {
    pub fn createPreviewEntity(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        world: ecs.World,
    ) anyerror!ecs.EntityId {
        const ents = try _ecs.spawnManyFromCDB(allocator, world, obj, 1);
        return ents[0];
    }
});

var entity_children_drop_aspect = editor.UiDropObj.implement(struct {
    pub fn uiDropObj(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        obj: cdb.ObjId,
        prop_idx: ?u32,
        drag_obj: cdb.ObjId,
    ) !void {
        _ = allocator; // autofix
        _ = tab; // autofix
        _ = prop_idx; // autofix

        const db = _cdb.getDbFromObjid(obj);

        if (drag_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(_cdb, db))) {
            const asset_entity_obj = _assetdb.getObjForAsset(drag_obj).?;

            if (asset_entity_obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, db))) {
                const new_obj = try _cdb.createObjectFromPrototype(asset_entity_obj);

                const new_obj_w = ecs.EntityCdb.write(_cdb, new_obj).?;
                const entiy_obj_w = ecs.EntityCdb.write(_cdb, obj).?;

                try ecs.EntityCdb.addSubObjToSet(_cdb, entiy_obj_w, .Childrens, &.{new_obj_w});

                try ecs.EntityCdb.commit(_cdb, new_obj_w);
                try ecs.EntityCdb.commit(_cdb, entiy_obj_w);
            }
        }
    }
});

fn lessThanAsset(_: void, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const db = _cdb.getDbFromObjid(lhs);

    const l_order = blk: {
        const component = _ecs.findComponentIByCdbHash(_cdb.getTypeHash(db, lhs.type_idx).?) orelse break :blk std.math.inf(f32);
        const category = _ecs.findCategoryById(.fromStr(component.category orelse break :blk std.math.inf(f32))) orelse break :blk std.math.inf(f32);
        break :blk category.order + component.category_order;
    };

    const r_order = blk: {
        const component = _ecs.findComponentIByCdbHash(_cdb.getTypeHash(db, rhs.type_idx).?) orelse break :blk std.math.inf(f32);
        const category = _ecs.findCategoryById(.fromStr(component.category orelse break :blk std.math.inf(f32))) orelse break :blk std.math.inf(f32);
        break :blk category.order + component.category_order;
    };

    return l_order < r_order;
}

var components_sort_aspect = editor.UiSetSortPropertyAspect.implement(struct {
    pub fn sort(allocator: std.mem.Allocator, objs: []cdb.ObjId) !void {
        _ = allocator;
        std.sort.insertion(cdb.ObjId, objs, {}, lessThanAsset);
    }
});

var entity_flaten_aspect = editor_tree.UiTreeFlatenPropertyAspect.implement();

var component_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const db = _cdb.getDbFromObjid(obj);
        const component_cdb_type = _cdb.getTypeHash(db, obj.type_idx).?;
        const iface = _ecs.findComponentIByCdbHash(component_cdb_type).?;

        return std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                iface.display_name,
            },
        ) catch "Invalid component!!!";
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const db = _cdb.getDbFromObjid(obj);

        const aspect = _cdb.getAspect(
            editor.EditorComponentAspect,
            db,
            obj.type_idx,
        );

        if (aspect) |a| {
            if (a.uiIcons) |fce| return fce(buff, allocator, obj);
        }

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Component});
    }
});

var children_storage_prop_aspect = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix

        const r = ecs.EntityCdb.read(_cdb, obj).?;
        const type_str = ecs.EntityCdb.readStr(_cdb, r, .ChildrenStorage) orelse "";
        var type_enum: ecs.ChildrenStorageType = std.meta.stringToEnum(ecs.ChildrenStorageType, type_str) orelse .Parent;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = ecs.EntityCdb.write(_cdb, obj).?;
            try ecs.EntityCdb.setStr(_cdb, w, .ChildrenStorage, @tagName(type_enum));
            try ecs.EntityCdb.commit(_cdb, w);
        }
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        try ecs.EntityCdb.addPropertyAspect(
            editor.UiSetMenusAspect,
            _cdb,
            db,
            .Components,
            _g.component_value_menu_aspect,
        );

        try ecs.EntityCdb.addAspect(
            editor.UiVisualAspect,
            _cdb,
            db,
            _g.entity_visual_aspect,
        );

        try ecs.EntityCdb.addAspect(
            asset_preview.AssetPreviewAspectI,
            _cdb,
            db,
            _g.entity_preview_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor.UiDropObj,
            _cdb,
            db,
            .Childrens,
            _g.entity_children_drop_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor_tree.UiTreeFlatenPropertyAspect,
            _cdb,
            db,
            .Components,
            _g.entity_flaten_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor.UiSetSortPropertyAspect,
            _cdb,
            db,
            .Components,
            _g.components_sort_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor_inspector.UiPropertyAspect,
            _cdb,
            db,
            .ChildrenStorage,
            _g.entity_child_storage_prop_aspect,
        );

        // Register UI aspect for CDB component types if there any.
        const impls = try _apidb.getImpl(_allocator, ecs.ComponentI);
        defer _allocator.free(impls);
        for (impls) |iface| {
            if (iface.cdb_type_hash.isEmpty()) continue;
            try _cdb.addAspect(editor.UiVisualAspect, db, _cdb.getTypeIdx(db, iface.cdb_type_hash).?, _g.component_visual_aspect);
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;

    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, editor_assetdb.CreateAssetI, &create_entity_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &debug_context_menu_i, load);

    _g.component_value_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_entity_components_menu_aspect", entity_component_menu_aspect);
    _g.entity_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_entity_visual_aspect", entity_visual_aspect);
    _g.component_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_component_visual_aspect", component_visual_aspect);
    _g.entity_preview_aspect = try apidb.setGlobalVarValue(asset_preview.AssetPreviewAspectI, module_name, "ct_entity_preview_aspect", entity_preview_aspect);
    _g.entity_children_drop_aspect = try apidb.setGlobalVarValue(editor.UiDropObj, module_name, "ct_entity_children_drop_aspect", entity_children_drop_aspect);
    _g.components_sort_aspect = try apidb.setGlobalVarValue(editor.UiSetSortPropertyAspect, module_name, "ct_components_sort_aspect", components_sort_aspect);
    _g.entity_flaten_aspect = try apidb.setGlobalVarValue(editor_tree.UiTreeFlatenPropertyAspect, module_name, "ct_entity_flaten_aspect", entity_flaten_aspect);
    _g.entity_child_storage_prop_aspect = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_entity_child_storage_prop_aspect", children_storage_prop_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_entity_asset(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
