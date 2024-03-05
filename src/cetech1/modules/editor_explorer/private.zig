const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");
const editor_tree = @import("editor_tree");

const Icons = cetech1.editorui.CoreIcons;

const MODULE_NAME = "editor_explorer";
const EXPLORER_TAB_NAME = "ct_editor_explorer_tab";

const EXPLORER_PROPERTIES_EDITOR_ICON = Icons.FA_BARS_STAGGERED;

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _editortree: *editor_tree.TreeAPI = undefined;
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
    selection: cetech1.cdb.ObjId = .{},
    inter_selection: cetech1.cdb.ObjId,
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
    .can_open = tabCanOpen,

    .create = tabCreate,
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
    .obj_selected = tabSelectedObject,
    .focused = tabFocused,
});

// Can open tab
fn tabCanOpen(db: *cetech1.cdb.Db, selection: cetech1.cdb.ObjId) bool {
    _ = db;
    _ = selection;

    return true;
}

fn tabMenuItem() [:0]const u8 {
    return EXPLORER_PROPERTIES_EDITOR_ICON ++ " Explorer";
}

// Return tab title
fn tabTitle(inst: *editor.TabO) [:0]const u8 {
    _ = inst;
    return EXPLORER_PROPERTIES_EDITOR_ICON ++ " Explorer";
}

// Create new FooTab instantce
fn tabCreate(dbc: *cetech1.cdb.Db) ?*editor.EditorTabI {
    var tab_inst = _allocator.create(ExplorerTab) catch undefined;
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    tab_inst.* = ExplorerTab{
        .tab_i = .{
            .vt = _g.tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = db,
        .inter_selection = editorui.ObjSelectionType.createObject(&db) catch return null,
    };
    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: *editor.EditorTabI) void {
    const tab_o: *ExplorerTab = @alignCast(@ptrCast(tab_inst.inst));
    tab_o.db.destroyObject(tab_o.inter_selection);
    _allocator.destroy(tab_o);
}

fn tabFocused(inst: *editor.TabO) void {
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));
    _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
}

// Draw tab menu
fn tabMenu(inst: *editor.TabO) void {
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));

    if (_editorui.beginMenu("Object", !tab_o.selection.isEmpty())) {
        defer _editorui.endMenu();
        var tmp_arena = _tempalloc.createTempArena() catch undefined;
        defer _tempalloc.destroyTempArena(tmp_arena);
        const allocator = tmp_arena.allocator();
        _editorui.objContextMenu(allocator, &tab_o.db, tab_o.selection, null, null) catch undefined;
    }
}

// Draw tab content
fn tabUi(inst: *editor.TabO) void {
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));

    if (tab_o.selection.id == 0 and tab_o.selection.type_hash.id == 0) {
        return;
    }

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    if (_editorui.beginChild("Explorer", .{ .border = true })) {
        defer _editorui.endChild();

        _editorui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
        defer _editorui.popStyleVar(.{});

        // Draw only asset content
        if (_editorui.getSelected(allocator, &tab_o.db, tab_o.selection)) |selected_objs| {
            defer allocator.free(selected_objs);

            for (selected_objs) |obj| {
                if (!cetech1.assetdb.AssetType.isSameType(obj)) continue;

                // Draw asset_object
                _editortree.cdbTreeView(allocator, &tab_o.db, obj, tab_o.inter_selection, .{
                    .expand_object = true,
                    .multiselect = true,
                    .opened_obj = obj,
                }) catch undefined;

                const selection_version = tab_o.db.getVersion(tab_o.inter_selection);
                if (selection_version != tab_o.db.getVersion(tab_o.inter_selection)) {
                    _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
                }
            }
        }
    }
}

// Selected object
fn tabSelectedObject(inst: *editor.TabO, cdb: *cetech1.cdb.Db, selection: cetech1.cdb.ObjId) void {
    _ = cdb;
    var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));
    if (tab_o.inter_selection.eq(selection)) return;
    tab_o.selection = selection;
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
    _editortree = apidb.getZigApi(editor_tree.TreeAPI).?;

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
