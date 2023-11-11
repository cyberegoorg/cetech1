const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const TagsProjectSettingsType = cetech1.assetdb.AssetTagsProjectSettingsType;
const AssetTagType = cetech1.assetdb.AssetTagType;

const MODULE_NAME = "editor_settings";

const ASSET_PROPERTIES_ASPECT_NAME = "ct_project_setings_properties_aspect";
const FOLDER_PROPERTY_CONFIG_ASPECT_NAME = "ct_project_setings_properties_config_aspect";
const SETTINGS_MENU_ASPECT_NAME = "ct_project_setings_menu_aspect";

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _inspector: *editor.InspectorAPI = undefined;

// Global state
const G = struct {
    settings_prop_aspect: *editor.UiPropertyAspect = undefined,
    settings_menus_aspect: *editor.UiSetMenus = undefined,
    noproto_config_aspect: *editor.UiPropertiesConfigAspect = undefined,
};
var _g: *G = undefined;

fn getSettingInterface(type_hash: cetech1.strid.StrId32) ?*editor.ProjectSettingsI {
    var it = _apidb.getFirstImpl(editor.ProjectSettingsI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(editor.ProjectSettingsI, node);
        if (iface.setting_type_hash.id == type_hash.id) return iface;
    }
    return null;
}

// settings menus aspect
var settings_menus_aspect = editor.UiSetMenus.implement(addMenuSettingsMenusAspect);
fn addMenuSettingsMenusAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    prop_idx: u32,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    var obj_r = db.readObj(obj).?;

    var set = try db.readSubObjSet(obj_r, prop_idx, allocator);

    var added_settings = std.AutoArrayHashMap(cetech1.strid.StrId32, void).init(allocator);
    defer added_settings.deinit();

    if (set) |s| {
        for (s) |setting| {
            try added_settings.put(setting.type_hash, {});
        }
    }

    var it = _apidb.getFirstImpl(editor.ProjectSettingsI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(editor.ProjectSettingsI, node);

        if (added_settings.contains(iface.setting_type_hash)) continue;

        var menu_name = iface.menu_item.?();
        var buff: [256:0]u8 = undefined;
        var label = try std.fmt.bufPrintZ(&buff, "{s}", .{cetech1.fromCstrZ(menu_name)});
        if (_editorui.menuItem(label, .{})) {
            var setting_obj = iface.create.?(&allocator, db.db);
            var obj_w = db.writeObj(obj).?;
            var setting_obj_w = db.writeObj(setting_obj).?;
            try db.addSubObjToSet(obj_w, prop_idx, &.{setting_obj_w});
            db.writeCommit(setting_obj_w);
            db.writeCommit(obj_w);
        }
    }
}

// Create cdb types
var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);
fn cdbCreateTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, _cdb);

    // try cetech1.assetdb.ProjectType.addPropertyAspect(
    //     &db,
    //     editor.UiPropertyAspect,
    //     .Settings,
    //     _g.settings_prop_aspect,
    // );

    // try cetech1.assetdb.ProjectType.addPropertyAspect(
    //     &db,
    //     editor.UiVisualAspect,
    //     .Settings,
    //     _g.settings_visual_aspect,
    // );

    try cetech1.assetdb.AssetTagsProjectSettingsType.addAspect(
        &db,
        editor.UiPropertiesConfigAspect,
        _g.noproto_config_aspect,
    );

    try cetech1.assetdb.ProjectType.addPropertyAspect(
        &db,
        editor.UiSetMenus,
        .Settings,
        _g.settings_menus_aspect,
    );
}

//
var folder_properties_config_aspect = editor.UiPropertiesConfigAspect{
    .hide_prototype = true,
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
    _inspector = apidb.getZigApi(editor.InspectorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.noproto_config_aspect = try apidb.globalVar(editor.UiPropertiesConfigAspect, MODULE_NAME, FOLDER_PROPERTY_CONFIG_ASPECT_NAME, .{});
    _g.noproto_config_aspect.* = folder_properties_config_aspect;

    _g.settings_menus_aspect = try apidb.globalVar(editor.UiSetMenus, MODULE_NAME, SETTINGS_MENU_ASPECT_NAME, .{});
    _g.settings_menus_aspect.* = settings_menus_aspect;

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_settings(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
