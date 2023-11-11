const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_explorer";
const EXPLORER_TAB_NAME = "ct_editor_explorer_tab";

const EXPLORER_PROPERTIES_EDITOR_ICON = Icons.FA_BARS_STAGGERED;

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
    tab_vt: *editor.EditorTabTypeI = undefined,
};
var _g: *G = undefined;

const ExplorerTab = struct {
    tab_i: editor.EditorTabI,
    db: cetech1.cdb.CdbDb,
    selected_obj: cetech1.cdb.ObjId = .{},
    selected_asset: ?cetech1.cdb.ObjId = null,
};

// Fill editor tab interface
var explorer_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = EXPLORER_TAB_NAME,
    .tab_hash = cetech1.strid.strId32(EXPLORER_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,

    .menu_name = tabMenuItem,
    .title = tabTitle,
    .create = tabCreate,
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
    .obj_selected = tabSelectedObject,
});

fn tabMenuItem() [:0]const u8 {
    return EXPLORER_PROPERTIES_EDITOR_ICON ++ " Explorer";
}

// Return tab title
fn tabTitle(inst: *editor.TabO) [:0]const u8 {
    _ = inst;
    return EXPLORER_PROPERTIES_EDITOR_ICON ++ " Explorer";
}

// Create new FooTab instantce
fn tabCreate(db: *cetech1.cdb.Db) ?*editor.EditorTabI {
    var tab_inst = _allocator.create(ExplorerTab) catch undefined;
    tab_inst.* = ExplorerTab{
        .tab_i = .{
            .vt = _g.tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = cetech1.cdb.CdbDb.fromDbT(db, _cdb),
    };
    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: *editor.EditorTabI) void {
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(tab_inst.inst));
    _allocator.destroy(tab_o);
}

// Draw tab menu
fn tabMenu(inst: *editor.TabO) void {
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));
    _ = tab_o;
}

// Draw tab content
fn tabUi(inst: *editor.TabO) void {
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));

    if (tab_o.selected_obj.id == 0 and tab_o.selected_obj.type_hash.id == 0) {
        return;
    }

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);

    // Draw only asset content
    if (tab_o.selected_asset) |selected_asset| {
        if (cetech1.assetdb.AssetType.readSubObj(&tab_o.db, tab_o.db.readObj(selected_asset).?, .Object)) |asset_obj| {
            const type_name = tab_o.db.getTypeName(selected_asset.type_hash).?;
            const asset_name_str = cetech1.assetdb.AssetType.readStr(&tab_o.db, tab_o.db.readObj(selected_asset).?, .Name).?;
            var asset_name_buf: [128]u8 = undefined;
            const asset_name = std.fmt.bufPrintZ(&asset_name_buf, "{s}.{s}", .{ asset_name_str, type_name }) catch undefined;

            // Draw asset as tree root.
            const open = _editor.cdbTreeNode(asset_name, true, false, tab_o.selected_obj.eq(selected_asset), .{});
            if (_editorui.isItemActivated()) {
                _editor.selectObj(&tab_o.db, selected_asset);
            }
            if (open) {

                // Draw asset_object
                if (_editor.cdbTreeView(tmp_arena.allocator(), &tab_o.db, asset_obj, tab_o.selected_obj, .{ .expand_object = true }) catch undefined) |new_selected| {
                    _editor.selectObj(&tab_o.db, new_selected);
                }

                _editor.cdbTreePop();
            }
        }
    }
}

// Selected object
fn tabSelectedObject(inst: *editor.TabO, cdb: *cetech1.cdb.Db, obj: cetech1.cdb.ObjId) void {
    _ = cdb;
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));

    if (obj.isEmpty()) {
        tab_o.selected_asset = null;
        tab_o.selected_obj = obj;
    }

    if (obj.type_hash.id == cetech1.assetdb.AssetType.type_hash.id) {
        tab_o.selected_asset = .{ .id = obj.id, .type_hash = .{ .id = obj.type_hash.id } };
    }

    tab_o.selected_obj = .{ .id = obj.id, .type_hash = .{ .id = obj.type_hash.id } };
}

fn cdbCreateTypes(db_: ?*cetech1.cdb.Db) !void {
    _ = db_;
}

var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);

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

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, EXPLORER_TAB_NAME, .{});
    _g.tab_vt.* = explorer_tab;

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.EditorTabTypeI, &explorer_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_explorer(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
