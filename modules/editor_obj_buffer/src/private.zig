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
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cetech1.cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _editortree: *const editor_tree.TreeAPI = undefined;
var _assetdb: *const cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

// Global state
const G = struct {
    tab_vt: *editor.TabTypeI = undefined,
    last_focused: ?*ObjBufferTab = null,
};
var _g: *G = undefined;

pub var api = public.EditorObjBufferAPI{
    .addToFirst = addToFirst,
};

fn addToFirst(allocator: std.mem.Allocator, db: cetech1.cdb.DbId, obj: coreui.SelectionItem) !void {
    _ = db; // autofix
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
        try tab_o.obj_buffer.add(&.{obj});
        try tab_o.inter_selection.set(&.{obj});

        if (tab_o.inter_selection.toSlice(allocator)) |objs| {
            _editor.propagateSelection(tab_o, objs);
        }
    }
}

const ObjBufferTab = struct {
    tab_i: editor.TabI,

    inter_selection: coreui.Selection,
    obj_buffer: coreui.Selection,
};

// Fill editor tab interface
var obj_buffer_tab = editor.TabTypeI.implement(
    editor.TabTypeIArgs{
        .tab_name = TAB_NAME,
        .tab_hash = cetech1.strid.strId32(TAB_NAME),

        .create_on_init = true,
        .show_pin_object = false,
        .show_sel_obj_in_title = false,
    },
    struct {
        pub fn menuName() ![:0]const u8 {
            return coreui.Icons.Buffer ++ "  " ++ "Obj buffer";
        }

        // Return tab title
        pub fn title(inst: *editor.TabO) ![:0]const u8 {
            _ = inst;
            return coreui.Icons.Buffer ++ "  " ++ "Obj buffer";
        }

        // Create new ObjBufferTab instantce
        pub fn create(tab_id: u32) !?*editor.TabI {
            _ = tab_id;
            var tab_inst = try _allocator.create(ObjBufferTab);
            tab_inst.* = ObjBufferTab{
                .tab_i = .{
                    .vt = _g.tab_vt,
                    .inst = @ptrCast(tab_inst),
                },

                .inter_selection = coreui.Selection.init(_allocator),
                .obj_buffer = coreui.Selection.init(_allocator),
            };
            return &tab_inst.tab_i;
        }

        // Destroy ObjBufferTab instantce
        pub fn destroy(tab_inst: *editor.TabI) !void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab_inst.inst));

            tab_o.inter_selection.deinit();
            tab_o.obj_buffer.deinit();

            _editor.propagateSelection(tab_inst, &.{.{ .top_level_obj = .{}, .obj = cetech1.cdb.OBJID_ZERO }});

            if (_g.last_focused == tab_o) {
                _g.last_focused = null;
            }

            _allocator.destroy(tab_o);
        }

        pub fn focused(inst: *editor.TabO) !void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

            const allocator = try _tempalloc.create();
            defer _tempalloc.destroy(allocator);

            _g.last_focused = tab_o;
        }

        pub fn assetRootOpened(inst: *editor.TabO) !void {
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));
            tab_o.inter_selection.clear();
            tab_o.obj_buffer.clear();
        }

        // Draw tab menu
        pub fn menu(inst: *editor.TabO) !void {
            var tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

            if (_coreui.beginMenu(_allocator, coreui.Icons.ContextMenu, !tab_o.inter_selection.isEmpty(), null)) {
                defer _coreui.endMenu();
                const allocator = try _tempalloc.create();
                defer _tempalloc.destroy(allocator);

                try _editor.showObjContextMenu(allocator, tab_o, &.{public.objectBufferContext}, tab_o.inter_selection.first());
            }
        }

        // Draw tab content
        pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick; // autofix
            _ = dt; // autofix
            const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));

            const allocator = try _tempalloc.create();
            defer _tempalloc.destroy(allocator);

            defer _coreui.endChild();
            if (_coreui.beginChild("ObjBuffer", .{ .child_flags = .{ .border = true } })) {
                _coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
                defer _coreui.popStyleVar(.{});

                if (tab_o.obj_buffer.toSlice(allocator)) |selected_objs| {
                    defer allocator.free(selected_objs);

                    for (selected_objs) |obj| {
                        _ = try _editortree.cdbTreeView(
                            allocator,
                            tab_o,
                            &.{ public.objectBufferContext, editor.Contexts.open },
                            obj,
                            &tab_o.inter_selection,
                            0,
                            .{
                                .multiselect = true,
                                .expand_object = false,
                                .show_root = true,
                            },
                        );
                    }
                }
            }
        }
    },
);

fn objContextMenu(
    allocator: std.mem.Allocator,
    obj_buffer: *coreui.Selection,
    inter_selection: *coreui.Selection,
    selection: []const coreui.SelectionItem,
    filter: ?[:0]const u8,
) !void {
    // Open

    if (_coreui.menuItem(
        allocator,
        coreui.Icons.Remove ++ "  " ++ "Remove from buffer",
        .{ .enabled = selection.len != 0 },
        filter,
    )) {
        for (selection) |obj| {
            obj_buffer.remove(&.{obj});
            inter_selection.remove(&.{obj});
        }
    }

    if (_coreui.menuItem(
        allocator,
        coreui.Icons.Remove ++ "  " ++ "Clear buffer",
        .{ .enabled = selection.len != 0 },
        filter,
    )) {
        obj_buffer.clear();
        inter_selection.clear();
    }
}

// TODO: separe
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

var buffer_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = selection;

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
        tab: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = contexts;
        const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab));

        _coreui.separatorText("Obj buffer");
        objContextMenu(allocator, &tab_o.obj_buffer, &tab_o.inter_selection, selection, filter) catch undefined;
    }
});

var add_to_buffer_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = selection;

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
        tab_: *editor.TabO,
        contexts: cetech1.strid.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = tab_;
        _ = contexts;

        const tabs = _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        var label_buff: [1024]u8 = undefined;
        for (tabs) |tab| {
            const label = std.fmt.bufPrintZ(&label_buff, coreui.Icons.Buffer ++ "  " ++ "In buffer {d}" ++ "###EditInObjBuffer{d}", .{ tab.tabid, tab.tabid }) catch undefined;

            if (_coreui.menuItem(allocator, label, .{}, filter)) {
                const tab_o: *ObjBufferTab = @alignCast(@ptrCast(tab.inst));

                for (selection, 0..) |obj, idx| {
                    try tab_o.obj_buffer.add(&.{obj});
                    if (idx == 0) {
                        try tab_o.inter_selection.set(&.{obj});
                    } else {
                        try tab_o.inter_selection.add(&.{obj});
                    }
                }

                if (tab_o.inter_selection.toSlice(allocator)) |objs| {
                    defer allocator.free(objs);
                    _editor.propagateSelection(tab.inst, objs);
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

                    // TODO: FIx mutli select
                    //ctx.keyDown(_coreui, .mod_ctrl);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###foo.ct_foo_asset", .{}, null);
                    //ctx.itemAction(_coreui, .Click, "**/###ROOT/###core", .{}, null);
                    //ctx.keyUp(_coreui, .mod_ctrl);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###EditInObjBuffer1");

                    ctx.setRef(_coreui, "###ct_editor_obj_buffer_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset", .{}, null);
                    //ctx.itemAction(_coreui, .Click, "**/###core", .{}, null);
                }
            },
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
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

    _g.tab_vt = try apidb.globalVarValue(editor.TabTypeI, module_name, TAB_NAME, obj_buffer_tab);

    try apidb.implOrRemove(module_name, editor.TabTypeI, &obj_buffer_tab, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &buffer_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &add_to_buffer_context_menu_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.EditorObjBufferAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_obj_buffer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
