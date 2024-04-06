const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const editor = @import("editor");
const editor_tree = @import("editor_tree");

const public = @import("editor_obj_buffer.zig");
const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_obj_buffer;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_obj_buffer_tab";

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _coreui: *cetech1.coreui.CoreUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _editortree: *editor_tree.TreeAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;

// Global state
const G = struct {
    tab_vt: *editor.EditorTabTypeI = undefined,
    last_focused: ?*ObjBufferTab = null,
};
var _g: *G = undefined;

pub var api = public.EditorObjBufferAPI{
    .addToFirst = addToFirst,
};

fn addToFirst(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) !void {
    var tab: ?*ObjBufferTab = null;
    if (_g.last_focused) |lf| {
        tab = lf;
    } else {
        const tabs = try _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash);
        defer allocator.free(tabs);
        for (tabs) |t| {
            tab = @alignCast(@ptrCast(t.inst));
            break;
        }
    }

    if (tab) |tab_o| {
        const w = db.writeObj(tab_o.obj_buffer).?;
        try coreui.ObjSelection.addRefToSet(db, w, .Selection, &.{obj});
        try _coreui.setSelection(allocator, db, tab_o.inter_selection, obj);
        _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
        try db.writeCommit(w);
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
        pub fn menuName() ![:0]const u8 {
            return coreui.Icons.Buffer ++ " Obj buffer";
        }

        // Return tab title
        pub fn title(inst: *editor.TabO) ![:0]const u8 {
            _ = inst;
            return coreui.Icons.Buffer ++ " Obj buffer";
        }

        // Create new ObjBufferTab instantce
        pub fn create(dbc: *cetech1.cdb.Db) !?*editor.EditorTabI {
            var tab_inst = try _allocator.create(ObjBufferTab);
            var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
            tab_inst.* = ObjBufferTab{
                .tab_i = .{
                    .vt = _g.tab_vt,
                    .inst = @ptrCast(tab_inst),
                },
                .db = db,
                .inter_selection = try coreui.ObjSelection.createObject(&db),
                .obj_buffer = try coreui.ObjSelection.createObject(&db),
            };
            return &tab_inst.tab_i;
        }

        // Destroy ObjBufferTab instantce
        pub fn destroy(tab_inst: *editor.EditorTabI) !void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab_inst.inst));
            tab_o.db.destroyObject(tab_o.obj_buffer);
            tab_o.db.destroyObject(tab_o.inter_selection);
            _editor.propagateSelection(&tab_o.db, cetech1.cdb.OBJID_ZERO);

            if (_g.last_focused == tab_o) {
                _g.last_focused = null;
            }

            _allocator.destroy(tab_o);
        }

        pub fn focused(inst: *editor.TabO) !void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));
            _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
            _g.last_focused = tab_o;
        }

        // Draw tab menu
        pub fn menu(inst: *editor.TabO) !void {
            var tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

            if (_coreui.beginMenu(_allocator, coreui.Icons.ContextMenu, !tab_o.inter_selection.isEmpty(), null)) {
                defer _coreui.endMenu();
                const allocator = try _tempalloc.create();
                defer _tempalloc.destroy(allocator);

                try _editor.showObjContextMenu(allocator, &tab_o.db, tab_o, &.{public.objectBufferContext}, tab_o.inter_selection, null, null);
            }
        }

        // Draw tab content
        pub fn ui(inst: *editor.TabO) !void {
            var tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

            const allocator = try _tempalloc.create();
            defer _tempalloc.destroy(allocator);

            const obj_buffer = tab_o.obj_buffer;

            defer _coreui.endChild();
            if (_coreui.beginChild("ObjBuffer", .{ .child_flags = .{ .border = true } })) {
                _coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
                defer _coreui.popStyleVar(.{});

                if (_coreui.getSelected(allocator, &tab_o.db, obj_buffer)) |selected_objs| {
                    defer allocator.free(selected_objs);
                    for (selected_objs) |obj| {
                        _ = try _editortree.cdbTreeView(
                            allocator,
                            &tab_o.db,
                            tab_o,
                            &.{ public.objectBufferContext, editor.Contexts.open },
                            obj,
                            tab_o.inter_selection,
                            0,
                            .{
                                .multiselect = true,
                                .expand_object = false,
                            },
                        );
                    }
                }
            }
        }

        pub fn objSelected(inst: *editor.TabO, cdb: *cetech1.cdb.Db, selection: cetech1.cdb.ObjId) !void {
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

    if (_coreui.menuItem(
        allocator,
        coreui.Icons.Remove ++ "  " ++ "Remove from buffer",
        .{ .enabled = _coreui.selectedCount(allocator, db, selection) != 0 },
        filter,
    )) {
        if (_coreui.getSelected(allocator, db, selection)) |selected| {
            defer allocator.free(selected);
            for (selected) |obj| {
                try _coreui.removeFromSelection(db, obj_buffer, obj);
                try _coreui.removeFromSelection(db, selection, obj);
            }
        }
    }

    if (_coreui.menuItem(
        allocator,
        coreui.Icons.Remove ++ "  " ++ "Clear buffer",
        .{ .enabled = _coreui.selectedCount(allocator, db, selection) != 0 },
        filter,
    )) {
        try _coreui.clearSelection(allocator, db, selection);
        try _coreui.clearSelection(allocator, db, obj_buffer);
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
    ) !bool {
        _ = dbc;
        _ = tab;
        _ = selection;
        _ = prop_idx;
        _ = in_set_obj;

        if (contexts.id != public.objectBufferContext.id) return false;

        if (filter) |f| {
            if (_coreui.uiFilterPass(allocator, f, "Remove from buffer", false) != null) return true;
            if (_coreui.uiFilterPass(allocator, f, "Clear buffer", false) != null) return true;
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
    ) !void {
        _ = contexts;
        _ = prop_idx;
        _ = in_set_obj;

        var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
        const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab));

        _coreui.separatorText("Obj buffer");
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
    ) !bool {
        _ = dbc;
        _ = tab;
        _ = selection;
        _ = prop_idx;
        _ = in_set_obj;

        if (contexts.id != editor.Contexts.open.id) return false;

        const tabs = _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        if (filter) |f| {
            var label_buff: [1024]u8 = undefined;
            for (tabs) |t| {
                const label = std.fmt.bufPrintZ(&label_buff, "In buffer {d}", .{t.tabid}) catch undefined;
                if (_coreui.uiFilterPass(allocator, f, label, false) != null) return true;
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
    ) !void {
        _ = tab_;
        _ = contexts;
        _ = prop_idx;
        _ = in_set_obj;

        var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

        const tabs = _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        var label_buff: [1024]u8 = undefined;
        for (tabs) |tab| {
            const label = std.fmt.bufPrintZ(&label_buff, coreui.Icons.Buffer ++ "  " ++ "In buffer {d}" ++ "###EditInObjBuffer{d}", .{ tab.tabid, tab.tabid }) catch undefined;

            if (_coreui.menuItem(allocator, label, .{}, filter)) {
                if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
                    defer allocator.free(selected_objs);

                    const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab.inst));
                    const w = db.writeObj(tab_o.obj_buffer).?;

                    for (selected_objs, 0..) |obj, idx| {
                        coreui.ObjSelection.addRefToSet(&db, w, .Selection, &.{obj}) catch undefined;
                        if (idx == 0) {
                            _coreui.setSelection(allocator, &db, tab_o.inter_selection, obj) catch undefined;
                        } else {
                            _coreui.addToSelection(&db, tab_o.inter_selection, obj) catch undefined;
                        }
                    }
                    db.writeCommit(w) catch undefined;
                    _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
                }
            }
        }
    }
});

// Test
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = _coreui.registerTest(
            "ObjBuffer",
            "should_add_asset_to_buffer_by_double_click",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###core", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_obj_buffer_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###core", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_add_asset_to_buffer_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.keyDown(_coreui, .mod_super);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###core", .{}, null);
                    ctx.keyUp(_coreui, .mod_super);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###EditInObjBuffer1");

                    ctx.setRef(_coreui, "###ct_editor_obj_buffer_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###core", .{}, null);
                }
            },
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cetech1.cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(module_name, cetech1.assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _editortree = apidb.getZigApi(module_name, editor_tree.TreeAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, module_name, TAB_NAME, .{});
    _g.tab_vt.* = obj_buffer_tab;

    try apidb.implOrRemove(module_name, editor.EditorTabTypeI, &obj_buffer_tab, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &buffer_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &add_to_buffer_context_menu_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.EditorObjBufferAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_obj_buffer(__apidb: *const cetech1.apidb.ct_apidb_api_t, __allocator: *const cetech1.apidb.ct_allocator_t, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}
