const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;

const editor = @import("editor");
const editor_tree = @import("editor_tree");

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_explorer;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const EXPLORER_TAB_NAME = "ct_editor_explorer_tab";

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _editortree: *const editor_tree.TreeAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *const cetech1.uuid.UuidAPI = undefined;

// Global state
const G = struct {
    tab_vt: *editor.TabTypeI = undefined,
};
var _g: *G = undefined;

const ExplorerTab = struct {
    tab_i: editor.TabI,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    inter_selection: coreui.Selection,
};

// Fill editor tab interface
var explorer_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = EXPLORER_TAB_NAME,
    .tab_hash = cetech1.strId32(EXPLORER_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
    .ignore_selection_from_tab = &.{cetech1.strId32("ct_editor_asset_browser_tab")},
}, struct {

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectionItem) !bool {
        _ = allocator; // autofix
        _ = selection;

        return true;
    }

    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Explorer ++ "  " ++ "Explorer";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Explorer ++ "  " ++ "Explorer";
    }

    // Create new FooTab instantce
    pub fn create(tab_id: u32) !?*editor.TabI {
        _ = tab_id;
        var tab_inst = try _allocator.create(ExplorerTab);

        tab_inst.* = ExplorerTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },

            .inter_selection = coreui.Selection.init(_allocator),
        };
        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *ExplorerTab = @ptrCast(@alignCast(tab_inst.inst));
        tab_o.inter_selection.deinit();
        _allocator.destroy(tab_o);
    }

    pub fn focused(inst: *editor.TabO) !void {
        const tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (tab_o.inter_selection.toSlice(allocator)) |objs| {
            defer allocator.free(objs);
            _editor.propagateSelection(inst, objs);
        }
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        var tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        if (_coreui.beginMenu(_allocator, coreui.Icons.ContextMenu ++ "###ObjContextMenu", !tab_o.selection.isEmpty(), null)) {
            defer _coreui.endMenu();

            const allocator = try _tempalloc.create();
            defer _tempalloc.destroy(allocator);

            const first_selected_obj = tab_o.inter_selection.first();
            try _editor.showObjContextMenu(
                allocator,
                tab_o,
                &.{
                    editor.Contexts.create,
                    editor.Contexts.open,
                    editor.Contexts.debug,
                },
                first_selected_obj,
            );
        }
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        var tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        var allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        defer _coreui.endChild();
        if (_coreui.beginChild("Explorer", .{ .child_flags = .{ .border = true } })) {
            //_coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 30 });
            //defer _coreui.popStyleVar(.{});

            // Draw only asset content
            // Draw asset_object
            if (!tab_o.selection.isEmpty()) {
                var o = tab_o.selection;
                o.obj = o.top_level_obj;

                const r = try _editortree.cdbTreeView(
                    allocator,
                    tab_o,
                    &.{
                        editor.Contexts.create,
                        editor.Contexts.open,
                        editor.Contexts.debug,
                    },
                    o,
                    &tab_o.inter_selection,
                    0,
                    .{
                        .expand_object = true,
                        .multiselect = true,
                        .opened_obj = o.obj,
                    },
                );

                if (r) {
                    if (tab_o.inter_selection.toSlice(allocator)) |objs| {
                        defer allocator.free(objs);
                        _editor.propagateSelection(inst, objs);
                    }
                }
            }
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash; // autofix

        var tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        if (tab_o.inter_selection.isSelectedAll(selection)) return;
        try tab_o.inter_selection.set(selection);
        tab_o.selection = if (selection.len != 0) selection[0] else coreui.SelectionItem.empty();
    }
});

// Test
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = _coreui.registerTest(
            "Explorer",
            "opened_asset_should_edit_in_explorer",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###foo.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset/###subobject", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_open_asset_in_explorer",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###foo.ct_foo_asset", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###OpenIn_ct_editor_explorer_tab");

                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_2");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset/###subobject", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_add_subobject_to_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###empty.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/###empty.ct_foo_asset/###subobject_set", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###AddToSet/###AddNew");

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba0-571a-71e9-a03e-cbe1fdcf2581").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(_cdb, _cdb.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 1) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_inisiated_subobject_in_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###child_asset.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/###child_asset.ct_foo_asset/###subobject_set/###018e7ba3-4f75-7e4f-bb0a-697eff5b21e2", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###Inisiate");

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba2-d04a-7176-8374-c38cca68b3ab").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(_cdb, _cdb.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                    defer _allocator.free(set.?);

                    std.testing.expect(set.?.len == 1) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                    const inisiated_obj = set.?[0];
                    const inisiated_obj_r = assetdb.FooAsset.read(_cdb, inisiated_obj).?;
                    const obj_r = assetdb.FooAsset.read(_cdb, obj).?;
                    const is_inisiated = _cdb.isIinisiated(obj_r, assetdb.FooAsset.propIdx(.SubobjectSet), inisiated_obj_r);
                    std.testing.expect(is_inisiated) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_delete_subobject_in_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(_coreui, 1);

                    ctx.windowFocus(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###parent_asset.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###parent_asset.ct_foo_asset/###subobject_set/###018e7ba3-4f75-7e4f-bb0a-697eff5b21e2", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###Remove");

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba3-3540-7790-bb65-3e63081a76f7").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(_cdb, _cdb.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 0) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_inisiate_subobject",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###child_asset.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/###child_asset.ct_foo_asset/###subobject", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###Inisiate");

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba2-d04a-7176-8374-c38cca68b3ab").?).?;

                    const subobj = assetdb.FooAsset.readSubObj(_cdb, _cdb.readObj(obj).?, .Subobject);
                    std.testing.expect(subobj != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    const inisiated_obj = subobj.?;
                    const inisiated_obj_r = assetdb.FooAsset.read(_cdb, inisiated_obj).?;
                    const obj_r = assetdb.FooAsset.read(_cdb, obj).?;
                    const is_inisiated = _cdb.isIinisiated(obj_r, assetdb.FooAsset.propIdx(.Subobject), inisiated_obj_r);
                    std.testing.expect(is_inisiated) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );
    }
});

// Create cdb types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: cdb.DbId) !void {
        _ = db_;
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
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _editortree = apidb.getZigApi(module_name, editor_tree.TreeAPI).?;
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.setGlobalVarValue(editor.TabTypeI, module_name, EXPLORER_TAB_NAME, explorer_tab);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &explorer_tab, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_explorer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
