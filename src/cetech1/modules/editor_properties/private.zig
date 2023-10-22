const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_properties";
const PROPERTIES_TAB_NAME = "ct_editor_properies_tab";

const PROPERTIES_EDITOR_ICON = Icons.FA_LIST;

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
    tab_vt: *editor.c.ct_editorui_tab_type_i = undefined,
};
var _g: *G = undefined;

const PropertyTab = struct {
    tab_i: editor.c.ct_editorui_tab_i,
    db: cetech1.cdb.CdbDb,
    selected_obj: cetech1.cdb.ObjId,
};

// Fill editor tab interface
var properties_tab = editor.c.ct_editorui_tab_type_i{
    .tab_name = PROPERTIES_TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(PROPERTIES_TAB_NAME).id },

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,

    .menu_name = tabMenuItem,
    .title = tabTitle,
    .create = @ptrCast(&tabCreate),
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
    .obj_selected = tabSelectedObject,
};

fn tabMenuItem() callconv(.C) [*]const u8 {
    return PROPERTIES_EDITOR_ICON ++ " Properies editor";
}

// Return tab title
fn tabTitle(inst: ?*editor.c.ct_editorui_tab_o) callconv(.C) [*]const u8 {
    _ = inst;
    return PROPERTIES_EDITOR_ICON ++ " Properies";
}

// Create new FooTab instantce
fn tabCreate(db: ?*cetech1.c.ct_cdb_db_t) callconv(.C) ?*editor.c.ct_editorui_tab_i {
    var tab_inst = _allocator.create(PropertyTab) catch undefined;
    tab_inst.* = PropertyTab{
        .tab_i = .{
            .vt = _g.tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = cetech1.cdb.CdbDb.fromDbT(db.?, _cdb),
        .selected_obj = .{},
    };
    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: ?*editor.c.ct_editorui_tab_i) callconv(.C) void {
    var tab_o: *PropertyTab = @alignCast(@ptrCast(tab_inst.?.inst));
    _allocator.destroy(tab_o);
}

// Draw tab menu
fn tabMenu(inst: ?*editor.c.ct_editorui_tab_o) callconv(.C) void {
    var tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
    _ = tab_o;
}

// Draw tab content
fn tabUi(inst: ?*editor.c.ct_editorui_tab_o) callconv(.C) void {
    var tab_o: *PropertyTab = @alignCast(@ptrCast(inst.?));

    if (tab_o.selected_obj.id == 0 and tab_o.selected_obj.type_hash.id == 0) {
        return;
    }

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);

    _editor.cdbPropertiesView(tmp_arena.allocator(), &tab_o.db, tab_o.selected_obj, .{}) catch |err| {
        _log.err(MODULE_NAME, "Problem in cdbProperties {}", .{err});
    };
}

// Selected object
fn tabSelectedObject(inst: ?*editor.c.ct_editorui_tab_o, cdb: ?*editor.c.ct_cdb_db_t, obj: editor.c.ct_cdb_objid_t) callconv(.C) void {
    var tab_o: *PropertyTab = @alignCast(@ptrCast(inst.?));
    _ = cdb;
    tab_o.selected_obj = .{ .id = obj.id, .type_hash = .{ .id = obj.type_hash.id } };
}

fn cdb_create_types(db_: ?*cetech1.c.struct_ct_cdb_db_t) callconv(.C) void {
    var db = cetech1.cdb.CdbDb.fromDbT(@ptrCast(db_.?), _cdb);
    _ = db;
}
var create_cdb_types_i = cetech1.c.ct_cdb_create_types_i{ .create_types = cdb_create_types };

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

    _g.tab_vt = try apidb.globalVar(editor.c.ct_editorui_tab_type_i, MODULE_NAME, PROPERTIES_TAB_NAME, .{});
    _g.tab_vt.* = properties_tab;

    try apidb.implOrRemove(cetech1.c.ct_cdb_create_types_i, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.c.ct_editorui_tab_type_i, &properties_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_properties(__apidb: ?*const cetech1.c.ct_apidb_api_t, __allocator: ?*const cetech1.c.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
