const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;

const editor = @import("editor");
const editor_asset_browser = @import("editor_asset_browser");

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_fixtures;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _assetdb: *const cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

// Global state
const G = struct {};
var _g: *G = undefined;

// Create foo asset
var create_foo_asset_i = editor.CreateAssetI.implement(
    cetech1.assetdb.FooAsset.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            dbc: *cdb.Db,
            folder: cdb.ObjId,
        ) !void {
            var db = cdb.CdbDb.fromDbT(dbc, _cdb);

            var buff: [256:0]u8 = undefined;
            const name = try _assetdb.buffGetValidName(
                allocator,
                &buff,
                &db,
                folder,
                db.getTypeIdx(cetech1.assetdb.FooAsset.type_hash).?,
                "NewFooAsset",
            );
            const new_obj = try cetech1.assetdb.FooAsset.createObject(&db);

            _ = _assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return Icons.FA_FACE_SMILE_WINK ++ "  " ++ "Foo";
        }
    },
);

// Folder visual aspect
var folder_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiIcons(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = dbc;
        _ = obj;

        return try std.fmt.allocPrintZ(
            allocator,
            "{s}",
            .{
                Icons.FA_FACE_SMILE_WINK,
            },
        );
    }
});

// Create cdb types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: *cdb.Db) !void {
        var db = cdb.CdbDb.fromDbT(db_, _cdb);

        try cetech1.assetdb.FooAsset.addAspect(&db, editor.UiVisualAspect, &folder_visual_aspect);
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
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(module_name, cetech1.assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, editor.CreateAssetI, &create_foo_asset_i, load);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_fixtures(__apidb: *const cetech1.apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}
