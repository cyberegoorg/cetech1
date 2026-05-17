const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const node_editor = cetech1.coreui_node_editor;
const assetdb = cetech1.assetdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;

const editor = cetech1.editor;
const Icons = coreui.CoreIcons;

const asset_preview = cetech1.editor.asset_preview;
const editor_tree = cetech1.editor.tree;
const editor_tabs = cetech1.editor.tabs;
const editor_inspector = cetech1.editor.inspector;
const editor_assetdb = cetech1.editor.assetdb;

const module_name = .editor_entity_asset;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _assetdb: *const assetdb.AssetDBAPI = undefined;
const tempalloc = cetech1.tempalloc;

// Global state that can surive hot-reload
const G = struct {
    component_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
    entity_visual_aspect: *editor.UiVisualAspect = undefined,
    component_visual_aspect: *editor.UiVisualAspect = undefined,
    components_sort_aspect: *editor.UiSetSortPropertyAspect = undefined,
    entity_preview_aspect: *asset_preview.AssetPreviewAspectI = undefined,
    entity_children_drop_aspect: *editor.UiDropObj = undefined,
    entity_flaten_aspect: *editor_tree.UiTreeFlatenPropertyAspect = undefined,
    entity_child_storage_prop_aspect: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
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
            const name = try assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                cdb.getTypeIdx(db, ecs.EntityCdb.type_hash).?,
                "NewEntity",
            );

            const new_obj = try ecs.EntityCdb.createObject(db);

            _ = assetdb.createAsset(name, folder, new_obj);
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
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.create.id) return false;

        for (selection) |obj| {
            const db = cdb.getDbFromObjid(obj.obj);
            const ent_obj = assetdb.getObjForAsset(obj.obj) orelse obj.obj;

            if (!ent_obj.type_idx.eql(ecs.EntityCdb.typeIdx(db))) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (coreui.uiFilterPass(allocator, f, "Add component", false) != null) return true;
        }
        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        const ent_obj = assetdb.getObjForAsset(obj.obj) orelse obj.obj;
        if (coreui.beginMenu(allocator, coreui.Icons.Add ++ "  " ++ "Add component", true, filter)) {
            defer coreui.endMenu();

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
        _ = prop_idx;

        const db = cdb.getDbFromObjid(obj);
        const entity_r = ecs.EntityCdb.read(obj).?;

        var components_set = cetech1.ArraySet(cdb.TypeIdx).empty;
        defer components_set.deinit(allocator);

        if (try ecs.EntityCdb.readSubObjSet(entity_r, .Components, allocator)) |components| {
            defer allocator.free(components);

            for (components) |component_obj| {
                _ = try components_set.add(allocator, component_obj.type_idx);
            }
        }

        var icon_buff: [32:0]u8 = undefined;
        var labbel_buff: [128:0]u8 = undefined;

        const impls = try apidb.getImpl(allocator, ecs.ComponentI);
        defer allocator.free(impls);

        // Create category menu first
        if (filter == null) {
            for (impls) |iface| {
                if (iface.cdb_type_hash.isEmpty()) continue;
                if (components_set.contains(cdb.getTypeIdx(db, iface.cdb_type_hash).?)) continue;

                var buff: [128:0]u8 = undefined;
                if (iface.category) |category| {
                    const label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Folder ++ "  " ++ "{s}###{s}", .{ category, category });

                    if (coreui.beginMenu(allocator, label, true, null)) {
                        coreui.endMenu();
                    }
                }
            }
        }

        for (impls) |iface| {
            if (iface.cdb_type_hash.isEmpty()) continue;
            if (components_set.contains(cdb.getTypeIdx(db, iface.cdb_type_hash).?)) continue;

            if (filter) |f| {
                if (coreui.uiFilterPass(allocator, f, iface.display_name, false) == null) continue;
            }

            var category_open = true;
            if (filter == null) {
                if (iface.category) |category| {
                    var buff: [128:0]u8 = undefined;
                    const label = try std.fmt.bufPrintZ(&buff, "###{s}", .{category});
                    category_open = coreui.beginMenu(allocator, label, true, null);
                }
            }

            var icon: [:0]const u8 = coreui.Icons.Component;
            const aspect = cdb.getAspect(
                editor.EditorComponentAspect,
                db,
                cdb.getTypeIdx(db, iface.cdb_type_hash).?,
            );

            icon = blk: {
                if (aspect) |a| {
                    if (a.uiIcons) |uiIcons| break :blk (try uiIcons(&icon_buff, allocator, .{}));
                }
                break :blk coreui.Icons.Component;
            };

            const label = blk: {
                if (filter == null or iface.category == null) {
                    break :blk try std.fmt.bufPrintZ(&labbel_buff, "{s}  {s}", .{ icon, iface.display_name });
                } else {
                    break :blk try std.fmt.bufPrintZ(&labbel_buff, "{s}  {s}/{s}", .{ icon, iface.category.?, iface.display_name });
                }
            };

            if (category_open and coreui.menuItem(allocator, label, .{}, null)) {
                const obj_w = ecs.EntityCdb.write(obj).?;

                const value_obj = try cdb.createObject(db, cdb.getTypeIdx(db, iface.cdb_type_hash).?);
                const value_obj_w = cdb.writeObj(value_obj).?;

                try ecs.EntityCdb.addSubObjToSet(obj_w, .Components, &.{value_obj_w});

                try cdb.writeCommit(value_obj_w);
                try cdb.writeCommit(obj_w);
            }

            if (category_open and iface.category != null and filter == null) {
                coreui.endMenu();
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
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;

        if (ecs.EntityCdb.readStr(obj_r, .Name)) |name| {
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
        _ = obj;
        _ = allocator;

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Entity});
    }
});

var entity_preview_aspect = asset_preview.AssetPreviewAspectI.implement(struct {
    pub fn createPreviewEntity(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        world: *ecs.World,
    ) anyerror!ecs.EntityId {
        const ents = try ecs.spawnManyFromCDB(allocator, world, obj, 1);
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
        _ = allocator;
        _ = tab;
        _ = prop_idx;

        const db = cdb.getDbFromObjid(obj);

        if (drag_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(db))) {
            const asset_entity_obj = assetdb.getObjForAsset(drag_obj).?;

            if (asset_entity_obj.type_idx.eql(ecs.EntityCdb.typeIdx(db))) {
                const new_obj = try cdb.createObjectFromPrototype(asset_entity_obj);

                const new_obj_w = ecs.EntityCdb.write(new_obj).?;
                const entiy_obj_w = ecs.EntityCdb.write(obj).?;

                try ecs.EntityCdb.addSubObjToSet(entiy_obj_w, .Childrens, &.{new_obj_w});

                try ecs.EntityCdb.commit(new_obj_w);
                try ecs.EntityCdb.commit(entiy_obj_w);
            }
        }
    }
});

fn lessThanAsset(_: void, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const db = cdb.getDbFromObjid(lhs);

    const l_order = blk: {
        const component = ecs.findComponentIByCdbHash(cdb.getTypeHash(db, lhs.type_idx).?) orelse break :blk std.math.inf(f32);
        const category = ecs.findCategoryById(.fromStr(component.category orelse break :blk std.math.inf(f32))) orelse break :blk std.math.inf(f32);
        break :blk category.order + component.category_order;
    };

    const r_order = blk: {
        const component = ecs.findComponentIByCdbHash(cdb.getTypeHash(db, rhs.type_idx).?) orelse break :blk std.math.inf(f32);
        const category = ecs.findCategoryById(.fromStr(component.category orelse break :blk std.math.inf(f32))) orelse break :blk std.math.inf(f32);
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
        const db = cdb.getDbFromObjid(obj);
        const component_cdb_type = cdb.getTypeHash(db, obj.type_idx).?;
        const iface = ecs.findComponentIByCdbHash(component_cdb_type).?;

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
        const db = cdb.getDbFromObjid(obj);

        const aspect = cdb.getAspect(
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

var children_storage_prop_aspect = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = prop_idx;
        _ = allocator;
        _ = args;

        const r = ecs.EntityCdb.read(obj).?;

        var type_enum = ecs.EntityCdb.readStrEnum(ecs.ChildrenStorageType, r, .Storage, .Parent);

        coreui.setNextItemWidth(-1.0);
        if (coreui.comboFromEnum("##select_child_storage", &type_enum)) {
            const w = ecs.EntityCdb.write(obj).?;
            try ecs.EntityCdb.setStr(w, .Storage, @tagName(type_enum));
            try ecs.EntityCdb.commit(w);
        }
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        try ecs.EntityCdb.addPropertyAspect(
            editor.UiSetMenusAspect,

            db,
            .Components,
            _g.component_value_menu_aspect,
        );

        try ecs.EntityCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.entity_visual_aspect,
        );

        try ecs.EntityCdb.addAspect(
            asset_preview.AssetPreviewAspectI,

            db,
            _g.entity_preview_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor.UiDropObj,

            db,
            .Childrens,
            _g.entity_children_drop_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor_tree.UiTreeFlatenPropertyAspect,

            db,
            .Components,
            _g.entity_flaten_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor.UiSetSortPropertyAspect,

            db,
            .Components,
            _g.components_sort_aspect,
        );

        try ecs.EntityCdb.addPropertyAspect(
            editor_inspector.UiInspectorPropertyValueAspect,

            db,
            .Storage,
            _g.entity_child_storage_prop_aspect,
        );

        // Register UI aspect for CDB component types if there any.
        const impls = try apidb.getImpl(_allocator, ecs.ComponentI);
        defer _allocator.free(impls);
        for (impls) |iface| {
            if (iface.cdb_type_hash.isEmpty()) continue;
            try cdb.addAspect(editor.UiVisualAspect, db, cdb.getTypeIdx(db, iface.cdb_type_hash).?, _g.component_visual_aspect);
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;

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
    _g.entity_child_storage_prop_aspect = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_entity_child_storage_prop_aspect", children_storage_prop_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_entity_asset(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
