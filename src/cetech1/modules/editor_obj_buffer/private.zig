const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");
const public = @import("editor_obj_buffer.zig");
const editor_tree = @import("editor_tree");
const Icons = cetech1.editorui.CoreIcons;

const MODULE_NAME = "editor_obj_buffer";
const TAB_NAME = "ct_editor_obj_buffer_tab";

const EDITOR_ICON = Icons.FA_BARS_STAGGERED;

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

pub var api = public.EditorObjBufferAPI{
    .openInBufferMenu = openInBufferMenu,
    .addToFirst = addToFirst,
};

fn addToFirst(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) !void {
    const tabs = try _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash);
    defer allocator.free(tabs);
    for (tabs) |tab| {
        const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab.inst));
        {
            const w = db.writeObj(tab_o.obj_buffer).?;
            try editorui.ObjSelectionType.addRefToSet(db, w, .Selection, &.{obj});
            try _editorui.setSelection(allocator, db, tab_o.inter_selection, obj);
            _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
            try db.writeCommit(w);
        }

        break;
    }
}

fn openInBufferMenu(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) !void {
    const tabs = try _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash);
    defer allocator.free(tabs);

    var label_buff: [1024]u8 = undefined;
    for (tabs) |tab| {
        const label = try std.fmt.bufPrintZ(&label_buff, editorui.Icons.Add ++ "  " ++ "Add to buffer {d}", .{tab.tabid});

        if (_editorui.menuItem(label, .{})) {
            if (_editorui.getSelected(allocator, db, selection)) |selected_objs| {
                defer allocator.free(selected_objs);

                const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab.inst));
                const w = db.writeObj(tab_o.obj_buffer).?;

                for (selected_objs, 0..) |obj, idx| {
                    try editorui.ObjSelectionType.addRefToSet(db, w, .Selection, &.{obj});
                    if (idx == 0) {
                        try _editorui.setSelection(allocator, db, tab_o.inter_selection, obj);
                    } else {
                        try _editorui.addToSelection(db, tab_o.inter_selection, obj);
                    }
                }
                try db.writeCommit(w);

                _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
            }
        }
    }
}

const ObjBufferTab = struct {
    tab_i: editor.EditorTabI,
    db: cetech1.cdb.CdbDb,
    selection: cetech1.cdb.ObjId = .{},
    inter_selection: cetech1.cdb.ObjId,
    obj_buffer: cetech1.cdb.ObjId,
};

// Fill editor tab interface
var explorer_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = cetech1.strid.strId32(TAB_NAME),

    .create_on_init = true,
    .show_pin_object = false,
    .show_sel_obj_in_title = true,

    .menu_name = tabMenuItem,
    .title = tabTitle,
    .create = tabCreate,
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
    .obj_selected = tabSelectedObject,
    .focused = tabFocused,
});

fn tabMenuItem() [:0]const u8 {
    return EDITOR_ICON ++ " Obj buffer";
}

// Return tab title
fn tabTitle(inst: *editor.TabO) [:0]const u8 {
    _ = inst;
    return EDITOR_ICON ++ " Obj buffer";
}

// Create new ObjBufferTab instantce
fn tabCreate(dbc: *cetech1.cdb.Db) ?*editor.EditorTabI {
    var tab_inst = _allocator.create(ObjBufferTab) catch undefined;
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    tab_inst.* = ObjBufferTab{
        .tab_i = .{
            .vt = _g.tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = db,
        .inter_selection = editorui.ObjSelectionType.createObject(&db) catch return null,
        .obj_buffer = editorui.ObjSelectionType.createObject(&db) catch return null,
    };
    return &tab_inst.tab_i;
}

// Destroy ObjBufferTab instantce
fn tabDestroy(tab_inst: *editor.EditorTabI) void {
    const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab_inst.inst));
    tab_o.db.destroyObject(tab_o.obj_buffer);
    tab_o.db.destroyObject(tab_o.inter_selection);
    _editor.propagateSelection(&tab_o.db, cetech1.cdb.OBJID_ZERO);
    _allocator.destroy(tab_o);
}

fn tabFocused(inst: *editor.TabO) void {
    const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));
    _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
}

// Draw tab menu
fn tabMenu(inst: *editor.TabO) void {
    var tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

    if (_editorui.beginMenu("Buffer", !tab_o.inter_selection.isEmpty())) {
        defer _editorui.endMenu();
        var tmp_arena = _tempalloc.createTempArena() catch undefined;
        defer _tempalloc.destroyTempArena(tmp_arena);
        const allocator = tmp_arena.allocator();

        _editor.objContextMenu(allocator, &tab_o.db, tab_o, &.{public.objectBufferContext}, tab_o.inter_selection, null, null) catch undefined;
    }
}

// Draw tab content
fn tabUi(inst: *editor.TabO) void {
    var tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    const obj_buffer = tab_o.obj_buffer;

    if (_editorui.beginChild("ObjBuffer", .{ .border = true })) {
        defer _editorui.endChild();

        _editorui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
        defer _editorui.popStyleVar(.{});

        if (_editorui.getSelected(allocator, &tab_o.db, obj_buffer)) |selected_objs| {
            defer allocator.free(selected_objs);
            for (selected_objs) |obj| {
                _editortree.cdbTreeView(
                    allocator,
                    &tab_o.db,
                    tab_o,
                    &.{public.objectBufferContext},
                    obj,
                    tab_o.inter_selection,
                    .{
                        .expand_object = false,
                    },
                ) catch undefined;
                // const open = _editortree.cdbObjTreeNode(
                //     allocator,
                //     &tab_o.db,
                //     obj,
                //     false,
                //     false,
                //     _editorui.isSelected(&tab_o.db, tab_o.inter_selection, obj),
                //     true,
                //     .{},
                // );
                // if (open) {
                //     defer _editorui.treePop();

                //     if (_editorui.beginPopupContextItem()) {
                //         defer _editorui.endPopup();
                //         objContextMenu(allocator, &tab_o.db, obj_buffer, tab_o.inter_selection) catch undefined;
                //     }

                //     if (_editorui.isItemActivated() or (_editorui.isItemHovered(.{}) and _editorui.isMouseClicked(.right) and _editorui.selectedCount(allocator, &tab_o.db, tab_o.inter_selection) == 1)) {
                //         _editorui.handleSelection(allocator, &tab_o.db, tab_o.inter_selection, obj, true) catch undefined;
                //         _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
                //     }
                // }
            }
        }
    }
}
fn objContextMenu(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj_buffer: cetech1.cdb.ObjId, selection: cetech1.cdb.ObjId) !void {
    // Open

    if (_editorui.menuItem(editorui.Icons.Remove ++ "  " ++ "Remove from buffer", .{ .enabled = _editorui.selectedCount(allocator, db, selection) != 0 })) {
        if (_editorui.getSelected(allocator, db, selection)) |selected| {
            defer allocator.free(selected);
            for (selected) |obj| {
                try _editorui.removeFromSelection(db, obj_buffer, obj);
                try _editorui.removeFromSelection(db, selection, obj);
            }
        }
    }
    if (_editorui.menuItem(editorui.Icons.Remove ++ "  " ++ "Clear buffer", .{ .enabled = _editorui.selectedCount(allocator, db, selection) != 0 })) {
        try _editorui.clearSelection(allocator, db, selection);
        try _editorui.clearSelection(allocator, db, obj_buffer);
    }
}

// TODO: separe
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

//

// Selected object
fn tabSelectedObject(inst: *editor.TabO, cdb: *cetech1.cdb.Db, selection: cetech1.cdb.ObjId) void {
    _ = cdb;
    _ = inst;
    _ = selection;
}

// Asset cntx menu
var buffer_context_menu_i = editor.ObjContextMenuI.implement(
    bufferContextMenuIsValid,
    bufferContextMenu,
);

fn bufferContextMenuIsValid(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    contexts: []const cetech1.strid.StrId64,
    selection: cetech1.cdb.ObjId,
) f32 {
    _ = dbc; // autofix
    _ = allocator; // autofix
    _ = selection; // autofix

    //var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    for (contexts) |context| {
        if (context.id == public.objectBufferContext.id) return 1000;
    }

    return 0;
}

fn bufferContextMenu(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    tab: *editor.TabO,
    context: []const cetech1.strid.StrId64,
    selection: cetech1.cdb.ObjId,
    prop_idx: ?u32,
    in_set_obj: ?cetech1.cdb.ObjId,
) void {
    _ = context; // autofix
    _ = prop_idx; // autofix
    _ = in_set_obj; // autofix

    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab));

    objContextMenu(allocator, &db, tab_o.obj_buffer, selection) catch undefined;

    return;
}

//
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

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, TAB_NAME, .{});
    _g.tab_vt.* = explorer_tab;

    try apidb.implOrRemove(editor.EditorTabTypeI, &explorer_tab, load);
    try apidb.implOrRemove(editor.ObjContextMenuI, &buffer_context_menu_i, load);

    try apidb.setOrRemoveZigApi(public.EditorObjBufferAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_obj_buffer(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
