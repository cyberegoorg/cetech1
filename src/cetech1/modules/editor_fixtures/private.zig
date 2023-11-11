const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_fixtures";

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _asset_browser: *editor.AssetBrowserAPI = undefined;

// Global state
const G = struct {};
var _g: *G = undefined;

// Create foo asset
var create_foo_asset_i = editor.CreateAssetI.implement(
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
    const name = try _asset_browser.buffGetValidName(
        allocator.*,
        &buff,
        &db,
        folder,
        cetech1.assetdb.FooAsset.type_hash,
        "NewFooAsset",
    );
    const new_obj = try cetech1.assetdb.FooAsset.createObject(&db);

    _ = _assetdb.createAsset(name, folder, new_obj);
}

fn createFooAssetMenuItem() [*]const u8 {
    return Icons.FA_FACE_SMILE_WINK ++ "  " ++ "Foo asset";
}

// Create cdb types
var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);
fn cdbCreateTypes(db_: ?*cetech1.cdb.Db) !void {
    _ = db_;
}

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
    _asset_browser = apidb.getZigApi(editor.AssetBrowserAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.CreateAssetI, &create_foo_asset_i, load);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_fixtures(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
