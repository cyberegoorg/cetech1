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

const ObjBufferTab = struct {
    tab_i: editor.EditorTabI,
    db: cetech1.cdb.CdbDb,
    selection: cetech1.cdb.ObjId = .{},
    inter_selection: cetech1.cdb.ObjId,
    obj_buffer: cetech1.cdb.ObjId,
};

// Fill editor tab interface
var obj_buffer_tab = editor.EditorTabTypeI.implement(
    editor.EditorTabTypeIArgs{
        .tab_name = TAB_NAME,
        .tab_hash = cetech1.strid.strId32(TAB_NAME),

        .create_on_init = true,
        .show_pin_object = false,
        .show_sel_obj_in_title = false,
    },
    struct {
        pub fn menuName() [:0]const u8 {
            return editorui.Icons.Buffer ++ " Obj buffer";
        }

        // Return tab title
        pub fn title(inst: *editor.TabO) [:0]const u8 {
            _ = inst;
            return editorui.Icons.Buffer ++ " Obj buffer";
        }

        // Create new ObjBufferTab instantce
        pub fn create(dbc: *cetech1.cdb.Db) ?*editor.EditorTabI {
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
        pub fn destroy(tab_inst: *editor.EditorTabI) void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab_inst.inst));
            tab_o.db.destroyObject(tab_o.obj_buffer);
            tab_o.db.destroyObject(tab_o.inter_selection);
            _editor.propagateSelection(&tab_o.db, cetech1.cdb.OBJID_ZERO);
            _allocator.destroy(tab_o);
        }

        pub fn focused(inst: *editor.TabO) void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));
            _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
        }

        // Draw tab menu
        pub fn menu(inst: *editor.TabO) void {
            var tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

            if (_editorui.beginMenu(_allocator, editorui.Icons.ContextMenu, !tab_o.inter_selection.isEmpty(), null)) {
                defer _editorui.endMenu();
                var tmp_arena = _tempalloc.createTempArena() catch undefined;
                defer _tempalloc.destroyTempArena(tmp_arena);
                const allocator = tmp_arena.allocator();

                _editor.showObjContextMenu(allocator, &tab_o.db, tab_o, &.{public.objectBufferContext}, tab_o.inter_selection, null, null) catch undefined;
            }
        }

        // Draw tab content
        pub fn ui(inst: *editor.TabO) void {
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
                            &.{ public.objectBufferContext, editor.Contexts.open },
                            obj,
                            tab_o.inter_selection,
                            .{
                                .multiselect = true,
                                .expand_object = false,
                            },
                        ) catch undefined;
                    }
                }
            }
        }

        pub fn objSelected(inst: *editor.TabO, cdb: *cetech1.cdb.Db, selection: cetech1.cdb.ObjId) void {
            _ = cdb;
            _ = inst;
            _ = selection;
        }
    },
);

fn objContextMenu(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj_buffer: cetech1.cdb.ObjId,
    selection: cetech1.cdb.ObjId,
    filter: ?[:0]const u8,
) !void {
    // Open

    if (_editorui.menuItem(
        allocator,
        editorui.Icons.Remove ++ "  " ++ "Remove from buffer",
        .{ .enabled = _editorui.selectedCount(allocator, db, selection) != 0 },
        filter,
    )) {
        if (_editorui.getSelected(allocator, db, selection)) |selected| {
            defer allocator.free(selected);
            for (selected) |obj| {
                try _editorui.removeFromSelection(db, obj_buffer, obj);
                try _editorui.removeFromSelection(db, selection, obj);
            }
        }
    }

    if (_editorui.menuItem(
        allocator,
        editorui.Icons.Remove ++ "  " ++ "Clear buffer",
        .{ .enabled = _editorui.selectedCount(allocator, db, selection) != 0 },
        filter,
    )) {
        try _editorui.clearSelection(allocator, db, selection);
        try _editorui.clearSelection(allocator, db, obj_buffer);
    }
}

// TODO: separe
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

var buffer_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        dbc: *cetech1.cdb.Db,
        tab: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) bool {
        _ = dbc;
        _ = tab;
        _ = selection;
        _ = prop_idx;
        _ = in_set_obj;

        if (contexts.id != public.objectBufferContext.id) return false;

        if (filter) |f| {
            if (_editorui.uiFilterPass(allocator, f, "Remove from buffer", false) != null) return true;
            if (_editorui.uiFilterPass(allocator, f, "Clear buffer", false) != null) return true;
            return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        dbc: *cetech1.cdb.Db,
        tab: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) void {
        _ = contexts;
        _ = prop_idx;
        _ = in_set_obj;

        var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
        const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab));

        _editorui.separatorText("Obj buffer");
        objContextMenu(allocator, &db, tab_o.obj_buffer, selection, filter) catch undefined;
    }
});

var add_to_buffer_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        dbc: *cetech1.cdb.Db,
        tab: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) bool {
        _ = dbc;
        _ = tab;
        _ = selection;
        _ = prop_idx;
        _ = in_set_obj;

        if (contexts.id != editor.Contexts.edit.id) return false;

        const tabs = _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        if (filter) |f| {
            var label_buff: [1024]u8 = undefined;
            for (tabs) |t| {
                const label = std.fmt.bufPrintZ(&label_buff, "In buffer {d}", .{t.tabid}) catch undefined;
                if (_editorui.uiFilterPass(allocator, f, label, false) != null) return true;
            }
            return false;
        }
        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        dbc: *cetech1.cdb.Db,
        tab_: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) void {
        _ = tab_;
        _ = contexts;
        _ = prop_idx;
        _ = in_set_obj;

        var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

        const tabs = _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        var label_buff: [1024]u8 = undefined;
        for (tabs) |tab| {
            const label = std.fmt.bufPrintZ(&label_buff, editorui.Icons.Buffer ++ "  " ++ "In buffer {d}", .{tab.tabid}) catch undefined;

            if (_editorui.menuItem(allocator, label, .{}, filter)) {
                if (_editorui.getSelected(allocator, &db, selection)) |selected_objs| {
                    defer allocator.free(selected_objs);

                    const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab.inst));
                    const w = db.writeObj(tab_o.obj_buffer).?;

                    for (selected_objs, 0..) |obj, idx| {
                        editorui.ObjSelectionType.addRefToSet(&db, w, .Selection, &.{obj}) catch undefined;
                        if (idx == 0) {
                            _editorui.setSelection(allocator, &db, tab_o.inter_selection, obj) catch undefined;
                        } else {
                            _editorui.addToSelection(&db, tab_o.inter_selection, obj) catch undefined;
                        }
                    }
                    db.writeCommit(w) catch undefined;
                    _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
                }
            }
        }
    }
});

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
    _g.tab_vt.* = obj_buffer_tab;

    try apidb.implOrRemove(editor.EditorTabTypeI, &obj_buffer_tab, load);
    try apidb.implOrRemove(editor.ObjContextMenuI, &buffer_context_menu_i, load);
    try apidb.implOrRemove(editor.ObjContextMenuI, &add_to_buffer_context_menu_i, load);

    try apidb.setOrRemoveZigApi(public.EditorObjBufferAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_obj_buffer(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
