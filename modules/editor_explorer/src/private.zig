const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const strid = cetech1.strid;

const editor = @import("editor");
const editor_tree = @import("editor_tree");

const Icons = cetech1.coreui.CoreIcons;

const MODULE_NAME = "editor_explorer";
pub const std_options = struct {
    pub const logFn = cetech1.log.zigLogFnGen(&_log);
};
const log = std.log.scoped(.editor_explorer);

const EXPLORER_TAB_NAME = "ct_editor_explorer_tab";

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _coreui: *cetech1.coreui.CoreUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _editortree: *editor_tree.TreeAPI = undefined;
var _assetdb: *assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *cetech1.uuid.UuidAPI = undefined;

// Global state
const G = struct {
    tab_vt: *editor.EditorTabTypeI = undefined,
};
var _g: *G = undefined;

const ExplorerTab = struct {
    tab_i: editor.EditorTabI,
    db: cdb.CdbDb,
    selection: cdb.ObjId = .{},
    inter_selection: cdb.ObjId,
    tv_result: editor_tree.SelectInTreeResult = .{ .is_changed = false },
};

// Fill editor tab interface
var explorer_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = EXPLORER_TAB_NAME,
    .tab_hash = strid.strId32(EXPLORER_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
}, struct {

    // Can open tab
    pub fn canOpen(db: *cdb.Db, selection: cdb.ObjId) !bool {
        _ = db;
        _ = selection;

        return true;
    }

    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Explorer ++ " Explorer";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Explorer ++ " Explorer";
    }

    // Create new FooTab instantce
    pub fn create(dbc: *cdb.Db) !?*editor.EditorTabI {
        var tab_inst = try _allocator.create(ExplorerTab);
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);
        tab_inst.* = ExplorerTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },
            .db = db,
            .inter_selection = try coreui.ObjSelectionType.createObject(&db),
        };
        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *ExplorerTab = @alignCast(@ptrCast(tab_inst.inst));
        tab_o.db.destroyObject(tab_o.inter_selection);
        _allocator.destroy(tab_o);
    }

    pub fn focused(inst: *editor.TabO) !void {
        var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));
        _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));

        if (_coreui.beginMenu(_allocator, coreui.Icons.ContextMenu ++ "###ObjContextMenu", !tab_o.selection.isEmpty(), null)) {
            defer _coreui.endMenu();

            var tmp_arena = try _tempalloc.createTempArena();
            defer _tempalloc.destroyTempArena(tmp_arena);
            const allocator = tmp_arena.allocator();

            try _editor.showObjContextMenu(
                allocator,
                &tab_o.db,
                tab_o,
                &.{
                    editor.Contexts.open,
                    editor.Contexts.debug,
                },
                tab_o.inter_selection,
                if (tab_o.tv_result.is_prop) tab_o.tv_result.prop_idx else null,
                if (!tab_o.tv_result.in_set_obj.isEmpty()) tab_o.tv_result.in_set_obj else null,
            );
        }
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO) !void {
        var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));

        if (tab_o.selection.id == 0 and tab_o.selection.type_hash.id == 0) {
            return;
        }

        var tmp_arena = try _tempalloc.createTempArena();
        defer _tempalloc.destroyTempArena(tmp_arena);
        const allocator = tmp_arena.allocator();

        if (_coreui.beginChild("Explorer", .{ .border = true })) {
            defer _coreui.endChild();

            _coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
            defer _coreui.popStyleVar(.{});

            // Draw only asset content
            if (_coreui.getSelected(allocator, &tab_o.db, tab_o.selection)) |selected_objs| {
                defer allocator.free(selected_objs);

                for (selected_objs) |obj| {
                    if (!assetdb.AssetType.isSameType(obj)) continue;

                    // Draw asset_object
                    const r = try _editortree.cdbTreeView(
                        allocator,
                        &tab_o.db,
                        tab_o,
                        &.{
                            editor.Contexts.open,
                            editor.Contexts.debug,
                        },
                        obj,
                        tab_o.inter_selection,
                        .{
                            .expand_object = true,
                            .multiselect = true,
                            .opened_obj = obj,
                            .sr = tab_o.tv_result,
                        },
                    );

                    if (r.isChanged()) tab_o.tv_result = r;

                    const selection_version = tab_o.db.getVersion(tab_o.inter_selection);
                    if (selection_version != tab_o.db.getVersion(tab_o.inter_selection)) {
                        _editor.propagateSelection(&tab_o.db, tab_o.inter_selection);
                    }
                }
            }
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, db: *cdb.Db, selection: cdb.ObjId) !void {
        _ = db;

        var tab_o: *ExplorerTab = @alignCast(@ptrCast(inst));
        if (tab_o.inter_selection.eq(selection)) return;
        tab_o.selection = selection;
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
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset/018b5846-c2d5-712f-bb12-9d9d15321ecb/Subobject", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_open_asset_in_explorer",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

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
                    ctx.itemAction(_coreui, .Click, "**/###foo.ct_foo_asset/018b5846-c2d5-712f-bb12-9d9d15321ecb/Subobject", .{}, null);
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

                    ctx.itemAction(_coreui, .Click, "**/###empty.ct_foo_asset/018e7ba0-571a-71e9-a03e-cbe1fdcf2581/Subobject set", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###AddToSet/###AddNew");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba0-571a-71e9-a03e-cbe1fdcf2581").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(db, db.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 1) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
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

                    ctx.itemAction(_coreui, .Click, "**/###child_asset.ct_foo_asset/018e7ba2-d04a-7176-8374-c38cca68b3ab/Subobject set/0", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###Inisiate");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba2-d04a-7176-8374-c38cca68b3ab").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(db, db.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };
                    defer _allocator.free(set.?);

                    std.testing.expect(set.?.len == 1) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };
                    const inisiated_obj = set.?[0];
                    const inisiated_obj_r = assetdb.FooAsset.read(db, inisiated_obj).?;
                    const obj_r = assetdb.FooAsset.read(db, obj).?;
                    const is_inisiated = db.isIinisiated(obj_r, assetdb.FooAsset.propIdx(.SubobjectSet), inisiated_obj_r);
                    std.testing.expect(is_inisiated) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
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

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###parent_asset.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_explorer_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .Click, "**/###parent_asset.ct_foo_asset/018e7ba3-3540-7790-bb65-3e63081a76f7/Subobject set/0", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###Remove");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e7ba3-3540-7790-bb65-3e63081a76f7").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(db, db.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 0) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };
                }
            },
        );
    }
});

// Create cdb types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: ?*cdb.Db) !void {
        _ = db_;
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(cetech1.coreui.CoreUIApi).?;
    _editor = apidb.getZigApi(editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;
    _editortree = apidb.getZigApi(editor_tree.TreeAPI).?;
    _uuid = apidb.getZigApi(cetech1.uuid.UuidAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, EXPLORER_TAB_NAME, .{});
    _g.tab_vt.* = explorer_tab;

    try apidb.implOrRemove(cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.EditorTabTypeI, &explorer_tab, load);
    try apidb.implOrRemove(coreui.RegisterTestsI, &register_tests_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_explorer(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
