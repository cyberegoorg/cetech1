const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;

const kernel = cetech1.kernel;
const editor = cetech1.editor;
const editor_tree = cetech1.editor.tree;
const editor_tabs = cetech1.editor.tabs;

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_explorer;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

const EXPLORER_TAB_NAME = "ct_editor_explorer_tab";

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _assetdb: *const assetdb.AssetDBAPI = undefined;

const tempalloc = cetech1.tempalloc;
const uuid = cetech1.uuid;

// Global state
const G = struct {
    tab_vt: *editor_tabs.TabTypeI = undefined,
};
var _g: *G = undefined;

const ExplorerTab = struct {
    tab_i: editor_tabs.TabI,

    selection: coreui.SelectedObj = coreui.SelectedObj.empty(),
    inter_selection: coreui.Selection,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};

// Fill editor tab interface
var explorer_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = EXPLORER_TAB_NAME,
    .tab_hash = .fromStr(EXPLORER_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
    .ignore_selection_from_tab = &.{.fromStr("ct_editor_asset_browser_tab")},
}, struct {

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectedObj) !bool {
        _ = allocator;
        _ = selection;

        return true;
    }

    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Explorer ++ "  " ++ "Explorer";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Explorer ++ "  " ++ "Explorer";
    }

    // Create new FooTab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
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
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *ExplorerTab = @ptrCast(@alignCast(tab_inst.inst));
        tab_o.inter_selection.deinit();
        _allocator.destroy(tab_o);
    }

    pub fn focused(inst: *editor_tabs.TabO) !void {
        const tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (tab_o.inter_selection.toSlice(allocator)) |objs| {
            defer allocator.free(objs);
            editor_tabs.propagateSelection(inst, objs);
        }
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        var tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        if (coreui.beginMenu(_allocator, coreui.Icons.ContextMenu ++ "###ObjContextMenu", !tab_o.selection.isEmpty(), null)) {
            defer coreui.endMenu();

            const allocator = try tempalloc.create();
            defer tempalloc.destroy(allocator);

            const first_selected_obj = tab_o.inter_selection.first();
            try editor.showObjContextMenu(
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
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        var tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        var allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        // tab_o.filter = coreui.uiFilter(&tab_o.filter_buff, tab_o.filter);

        defer coreui.endChild();
        if (coreui.beginChild("Explorer", .{ .child_flags = .{ .border = true } })) {
            //coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 30 });
            //defer coreui.popStyleVar(.{});

            // Draw only asset content
            // Draw asset_object
            if (!tab_o.selection.isEmpty() or tab_o.filter != null) {
                var o = tab_o.selection;
                o.obj = o.top_level_obj;

                const r = try editor_tree.cdbTreeView(
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
                        .filter = tab_o.filter,
                    },
                );

                if (r) {
                    if (tab_o.inter_selection.toSlice(allocator)) |objs| {
                        defer allocator.free(objs);
                        editor_tabs.propagateSelection(inst, objs);
                    }
                }
            }
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectedObj, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash;

        var tab_o: *ExplorerTab = @ptrCast(@alignCast(inst));

        if (tab_o.inter_selection.isSelectedAll(selection)) return;
        try tab_o.inter_selection.set(selection);
        tab_o.selection = if (selection.len != 0) selection[0] else coreui.SelectedObj.empty();
    }
});

// Test
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = coreui.registerTest(
            "Explorer",
            "opened_asset_should_edit_in_explorer",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###foo.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_explorer_tab_1");
                    ctx.windowFocus("");
                    ctx.itemAction(.Click, "**/###foo.ct_foo_asset/###subobject", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_open_asset_in_explorer",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###foo.ct_foo_asset", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###OpenIn_ct_editor_explorer_tab");

                    ctx.yield(1);

                    ctx.setRef("###ct_editor_explorer_tab_2");
                    ctx.windowFocus("");
                    ctx.itemAction(.Click, "**/###foo.ct_foo_asset/###subobject", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_add_subobject_to_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###empty.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_explorer_tab_1");
                    ctx.windowFocus("");

                    ctx.itemAction(.Click, "**/###empty.ct_foo_asset/###subobject_set", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###AddToSet/###AddNew");

                    const obj = assetdb.getObjId(uuid.fromStr("018e7ba0-571a-71e9-a03e-cbe1fdcf2581").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(cdb.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 1) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_inisiated_subobject_in_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###child_asset.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_explorer_tab_1");
                    ctx.windowFocus("");

                    ctx.itemAction(.Click, "**/###child_asset.ct_foo_asset/###subobject_set/###018e7ba3-4f75-7e4f-bb0a-697eff5b21e2", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###Inisiate");

                    const obj = assetdb.getObjId(uuid.fromStr("018e7ba2-d04a-7176-8374-c38cca68b3ab").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(cdb.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                    defer _allocator.free(set.?);

                    std.testing.expect(set.?.len == 1) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                    const inisiated_obj = set.?[0];
                    const inisiated_obj_r = assetdb.FooAsset.read(inisiated_obj).?;
                    const obj_r = assetdb.FooAsset.read(obj).?;
                    const is_inisiated = cdb.isIinisiated(obj_r, assetdb.FooAsset.propIdx(.SubobjectSet), inisiated_obj_r);
                    std.testing.expect(is_inisiated) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_delete_subobject_in_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###parent_asset.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_explorer_tab_1");
                    ctx.windowFocus("");
                    ctx.itemAction(.Click, "**/###parent_asset.ct_foo_asset/###subobject_set/###018e7ba3-4f75-7e4f-bb0a-697eff5b21e2", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###Remove");

                    const obj = assetdb.getObjId(uuid.fromStr("018e7ba3-3540-7790-bb65-3e63081a76f7").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(cdb.readObj(obj).?, .SubobjectSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 0) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_inisiate_subobject",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_explorer");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###child_asset.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_explorer_tab_1");
                    ctx.windowFocus("");

                    ctx.itemAction(.Click, "**/###child_asset.ct_foo_asset/###subobject", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###Inisiate");

                    const obj = assetdb.getObjId(uuid.fromStr("018e7ba2-d04a-7176-8374-c38cca68b3ab").?).?;

                    const subobj = assetdb.FooAsset.readSubObj(cdb.readObj(obj).?, .Subobject);
                    std.testing.expect(subobj != null) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    const inisiated_obj = subobj.?;
                    const inisiated_obj_r = assetdb.FooAsset.read(inisiated_obj).?;
                    const obj_r = assetdb.FooAsset.read(obj).?;
                    const is_inisiated = cdb.isIinisiated(obj_r, assetdb.FooAsset.propIdx(.Subobject), inisiated_obj_r);
                    std.testing.expect(is_inisiated) catch |err| {
                        coreui.checkTestError(@src(), err);
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
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, EXPLORER_TAB_NAME, explorer_tab);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &explorer_tab, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_explorer(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
