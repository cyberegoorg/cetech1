const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_tags.zig");
const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const TagType = cetech1.assetdb.TagType;

const editor = @import("editor");
const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_tags";

const FOLDER_PROPERTY_CONFIG_ASPECT_NAME = "ct_project_setings_properties_config_aspect";
const TAGS_SETTINGS_TAGS_VISUAL_CONFIG_ASPECT_NAME = "ct_tags_settings_tags_config_aspect";
const TAGS_SETTINGS_ASPECT_NAME = "ct_tags_setings_aspect";
const TAGS_ASPECT_NAME = "ct_tags_property_aspect";
const TAG_VISUAL_ASPECT_NAME = "ct_tag_visual_aspect";
const SETTINGS_VISUAL_ASPECT_NAME = "ct_project_setings_visual_aspect";

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;

// Global state
const G = struct {
    tag_prop_aspect: *editorui.UiEmbedPropertyAspect = undefined,
    tag_visual_aspect: *editorui.UiVisualAspect = undefined,
    noproto_config_aspect: *editorui.UiPropertiesConfigAspect = undefined,
    tags_settings_prop_aspect: *editorui.UiPropertiesAspect = undefined,
};
var _g: *G = undefined;

var api = public.EditorTagsApi{
    .tagsInput = tagsInput,
};

fn tagButton(db: *cetech1.cdb.CdbDb, tag: cetech1.cdb.ObjId, wrap: bool) bool {
    var buff: [128:0]u8 = undefined;
    const tag_r = db.readObj(tag) orelse return false;
    const tag_name = TagType.readStr(db, tag_r, .Name) orelse "NO NAME =(";
    const tag_color = getTagColor(db, tag_r);

    const color_scale = 0.80;
    const tag_color_normal = .{ tag_color[0] * color_scale, tag_color[1] * color_scale, tag_color[2] * color_scale, 1.0 };

    _editorui.pushObjId(tag);
    defer _editorui.popId();

    const label = std.fmt.bufPrintZ(&buff, editorui.Icons.Tag ++ "  " ++ "{s}", .{tag_name}) catch return false;

    if (wrap) {
        const style = _editorui.getStyle();
        const pos_a = _editorui.getItemRectMax()[0];
        const text_size = _editorui.calcTextSize(label, .{})[0] + 2 * style.frame_padding[0];

        if (pos_a + text_size + style.item_spacing[0] < _editorui.getWindowPos()[0] + _editorui.getWindowContentRegionMax()[0]) {
            _editorui.sameLine(.{});
        }
    }

    _editorui.pushStyleColor4f(.{ .c = tag_color_normal, .idx = .button });
    _editorui.pushStyleColor4f(.{ .c = tag_color, .idx = .button_active });
    _editorui.pushStyleColor4f(.{ .c = tag_color, .idx = .button_hovered });
    defer _editorui.popStyleColor(.{ .count = 3 });

    _editorui.pushStyleVar1f(.{ .idx = .frame_rounding, .v = 10 });
    _editorui.pushStyleVar2f(.{ .idx = .frame_padding, .v = .{ 6, 3 } });
    defer _editorui.popStyleVar(.{ .count = 2 });

    const button = (_editorui.button(label, .{}));

    return button;
}

fn tagsInput(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    prop_idx: u32,
    in_table: bool,
    filter: ?[*:0]const u8,
) !bool {
    _ = filter;
    const obj_r = db.readObj(obj) orelse return false;

    if (in_table) {
        _editorui.tableNextColumn();
    }

    if (_editorui.button(editorui.Icons.Tag ++ " " ++ editorui.Icons.Add, .{})) {
        _editorui.openPopup("ui_tag_add_popup", .{});
    }

    var any_tag_set = false;
    if (db.readRefSet(obj_r, prop_idx, allocator)) |tags| {
        for (tags) |tag| {
            any_tag_set = true;
            if (tagButton(db, tag, true)) {
                const obj_w = db.writeObj(obj).?;
                defer db.writeCommit(obj_w);
                try db.removeFromRefSet(obj_w, prop_idx, tag);
            }
        }
    }

    if (_editorui.beginPopup("ui_tag_add_popup", .{})) {
        defer _editorui.endPopup();

        if (db.getAllObjectByType(allocator, cetech1.assetdb.TagType.type_hash)) |tags| {
            for (tags) |tag| {
                if (db.isInSet(obj_r, prop_idx, tag)) continue;
                if (tagButton(db, tag, true)) {
                    const obj_w = db.writeObj(obj).?;
                    defer db.writeCommit(obj_w);
                    try db.addRefToSet(obj_w, prop_idx, &.{tag});
                    _editorui.closeCurrentPopup();
                }
            }
        }
    }

    return any_tag_set;
}

//
// Create tag asset

var create_tag_asset_i = editor.CreateAssetI.implement(
    createFooAssetMenuItem,
    createFooAssetMenuItemCreate,
);
fn createFooAssetMenuItemCreate(
    allocator: *const std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    folder: cetech1.cdb.ObjId,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buff: [256:0]u8 = undefined;
    const name = try _assetdb.buffGetValidName(
        allocator.*,
        &buff,
        &db,
        folder,
        cetech1.assetdb.FooAsset.type_hash,
        "NewTag",
    );
    const new_obj = try cetech1.assetdb.TagType.createObject(&db);

    _ = _assetdb.createAsset(name, folder, new_obj);
}

fn createFooAssetMenuItem() [*]const u8 {
    return editorui.Icons.Tag ++ "  " ++ "Tag asset";
}

// Tag property  aspect
var tag_prop_aspect = editorui.UiEmbedPropertyAspect.implement(tagsPropertyUiPropertyAspect);
fn tagsPropertyUiPropertyAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    prop_idx: u32,
    args: editorui.cdbPropertiesViewArgs,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    _ = try tagsInput(allocator, &db, obj, prop_idx, true, args.filter);
}
//

fn getTagColor(db: *cetech1.cdb.CdbDb, tag_r: *cetech1.cdb.Obj) [4]f32 {
    const tag_color_obj = TagType.readSubObj(db, tag_r, .Color);
    var color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    if (tag_color_obj) |color_obj| {
        color = cetech1.cdb_types.color4fToSlice(db, color_obj);
    }
    return color;
}

// Tag visual aspect
var tag_visual_aspect = editorui.UiVisualAspect.implement(
    tagNameUIVisalAspect,
    tagIconUIVisalAspect,
    tagColorUIVisalAspect,
);
fn tagNameUIVisalAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![:0]const u8 {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    const obj_r = db.readObj(obj).?;
    return std.fmt.allocPrintZ(allocator, "{s}", .{
        TagType.readStr(&db, obj_r, .Name) orelse "No NAME =()",
    });
}
fn tagIconUIVisalAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![:0]const u8 {
    _ = dbc;
    _ = obj;
    return std.fmt.allocPrintZ(allocator, "{s}", .{editorui.Icons.Tag});
}

fn tagColorUIVisalAspect(
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![4]f32 {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    if (TagType.readSubObj(&db, db.readObj(obj).?, .Color)) |color_obj| {
        return cetech1.cdb_types.color4fToSlice(&db, color_obj);
    }
    return .{ 1.0, 1.0, 1.0, 1.0 };
}
//
// Settings visual aspect
var settings_visual_aspect = editorui.UiVisualAspect.implement(
    settingsNameUIVisalAspect,
    settingsIconUIVisalAspect,
    null,
);
fn settingsNameUIVisalAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![:0]const u8 {
    _ = dbc;
    _ = obj;

    return std.fmt.allocPrintZ(allocator, "Tags settings", .{});
}
fn settingsIconUIVisalAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![:0]const u8 {
    _ = dbc;
    _ = obj;

    return std.fmt.allocPrintZ(allocator, "{s}", .{editorui.Icons.Tag});
}
//

// Create cdb types
var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);
fn cdbCreateTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, _cdb);

    try cetech1.assetdb.TagType.addAspect(
        &db,
        editorui.UiPropertiesConfigAspect,
        _g.noproto_config_aspect,
    );

    try cetech1.assetdb.TagType.addAspect(
        &db,
        editorui.UiVisualAspect,
        _g.tag_visual_aspect,
    );

    try cetech1.assetdb.FolderType.addPropertyAspect(
        &db,
        editorui.UiEmbedPropertyAspect,
        .Tags,
        _g.tag_prop_aspect,
    );

    try cetech1.assetdb.AssetType.addPropertyAspect(
        &db,
        editorui.UiEmbedPropertyAspect,
        .Tags,
        _g.tag_prop_aspect,
    );
}

//
var folder_properties_config_aspect = editorui.UiPropertiesConfigAspect{
    .hide_prototype = true,
};

var settings_visual_config_aspect = editorui.UiVisualPropertyConfigAspect{
    .no_subtree = true,
};

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log;
    _apidb = apidb;
    _cdb = apidb.getZigApi(cetech1.cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;
    _editor = apidb.getZigApi(editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(cetech1.assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.noproto_config_aspect = try apidb.globalVar(editorui.UiPropertiesConfigAspect, MODULE_NAME, FOLDER_PROPERTY_CONFIG_ASPECT_NAME, .{});
    _g.noproto_config_aspect.* = folder_properties_config_aspect;

    _g.tag_prop_aspect = try apidb.globalVar(editorui.UiEmbedPropertyAspect, MODULE_NAME, TAGS_ASPECT_NAME, .{});
    _g.tag_prop_aspect.* = tag_prop_aspect;

    _g.tag_visual_aspect = try apidb.globalVar(editorui.UiVisualAspect, MODULE_NAME, TAG_VISUAL_ASPECT_NAME, .{});
    _g.tag_visual_aspect.* = tag_visual_aspect;

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.CreateAssetI, &create_tag_asset_i, load);

    try apidb.setOrRemoveZigApi(public.EditorTagsApi, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_tags(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
