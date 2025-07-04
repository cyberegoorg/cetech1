const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;

const public = @import("asset_browser.zig");

const editor = @import("editor");
const editor_tree = @import("editor_tree");
const editor_tags = @import("editor_tags");
const editor_asset = @import("editor_asset");

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_asset_browser;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const ASSET_BROWSER_NAME = "ct_editor_asset_browser_tab";

const ASSET_BROWSER_ICON = Icons.FA_FOLDER_TREE;
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

const MAIN_CONTEXTS = &.{
    editor.Contexts.open,
    editor.Contexts.edit,
    editor.Contexts.create,
    editor.Contexts.delete,
    editor.Contexts.debug,
};

const TypeFilter = cetech1.ArraySet(cdb.TypeIdx);

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _editor_tree: *const editor_tree.TreeAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *const cetech1.uuid.UuidAPI = undefined;
var _tags: *const editor_tags.EditorTagsApi = undefined;
var _editor_asset: *const editor_asset.EditorAssetAPI = undefined;

const G = struct {
    tab_vt: *editor.TabTypeI = undefined,
};
var _g: *G = undefined;

var api = public.AssetBrowserAPI{};

const AssetBrowserTab = struct {
    tab_i: editor.TabI,

    selection_obj: coreui.Selection,
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
    tags: cdb.ObjId,

    type_filter: TypeFilter = .init(),
};

// Fill editor tab interface
var asset_browser_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = ASSET_BROWSER_NAME,
    .tab_hash = cetech1.strId32(ASSET_BROWSER_NAME),
    .create_on_init = true,
}, struct {
    pub fn menuName() ![:0]const u8 {
        return ASSET_BROWSER_ICON ++ "  " ++ "Asset browser";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return ASSET_BROWSER_ICON ++ "  " ++ "Asset browser";
    }

    // Create new FooTab instantce
    pub fn create(tab_id: u32) !?*editor.TabI {
        _ = tab_id;
        var tab_inst = try _allocator.create(AssetBrowserTab);

        tab_inst.* = AssetBrowserTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },

            .tags = try assetdb.Tags.createObject(_cdb, _assetdb.getDb()),
            .selection_obj = coreui.Selection.init(_allocator),
        };
        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab_inst.inst));
        _cdb.destroyObject(tab_o.tags);
        tab_o.selection_obj.deinit();
        tab_o.type_filter.deinit(_allocator);
        _allocator.destroy(tab_o);
    }

    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        const selected_count = tab_o.selection_obj.count();
        const first_selected_obj = tab_o.selection_obj.first();

        if (_coreui.beginMenu(allocator, coreui.Icons.ContextMenu ++ "###ObjContextMenu", selected_count != 0, null)) {
            defer _coreui.endMenu();
            _editor.showObjContextMenu(
                allocator,
                tab_o,
                MAIN_CONTEXTS,
                first_selected_obj,
            ) catch undefined;
        }

        if (_coreui.beginMenu(allocator, coreui.Icons.AddAsset ++ "###AddAsset", selected_count != 0, null)) {
            defer _coreui.endMenu();

            try _editor.showObjContextMenu(
                allocator,
                tab_o,
                &.{editor.Contexts.create},
                first_selected_obj,
            );
        }
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;
        var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

        const root_folder = _assetdb.getRootFolder();
        if (root_folder.isEmpty()) {
            _coreui.text("No root folder");
            return;
        }

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        const r = try uiAssetBrowser(
            allocator,
            tab_o,
            MAIN_CONTEXTS,
            root_folder,
            &tab_o.selection_obj,
            &tab_o.filter_buff,
            tab_o.tags,
            .{
                .filter = tab_o.filter,
                .multiselect = true,
                .expand_object = false,
                .only_types = tab_o.type_filter.unmanaged.keys(),
            },
        );
        tab_o.filter = r.filter;
    }

    pub fn focused(inst: *editor.TabO) !void {
        const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));
        _ = tab_o;
    }

    // pub fn assetRootOpened(inst: *editor.TabO) !void {
    //     const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));
    //     tab_o.filter = null;
    //     tab_o.selection_obj.clear();
    // }

    pub fn selectObjFromMenu(allocator: std.mem.Allocator, tab: *editor.TabO, ignored_obj: cdb.ObjId, allowed_type: cdb.TypeIdx) !cdb.ObjId {
        var label_buff: [1024]u8 = undefined;

        const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab));

        const selected_n = tab_o.selection_obj.count();
        const selected_obj = tab_o.selection_obj.first();

        var valid = false;
        var label: [:0]u8 = undefined;

        var real_obj = selected_obj.obj;
        if (_cdb.readObj(selected_obj.obj)) |r| {
            if (selected_obj.obj.type_idx.eql(AssetTypeIdx)) {
                real_obj = assetdb.Asset.readSubObj(_cdb, r, .Object).?;

                var buff: [1024]u8 = undefined;
                const path = _assetdb.getFilePathForAsset(&buff, selected_obj.obj) catch undefined;

                label = std.fmt.bufPrintZ(&label_buff, "browser {d} - {s}" ++ "###{d}", .{ tab_o.tab_i.tabid, path, tab_o.tab_i.tabid }) catch return .{};
            } else {
                label = std.fmt.bufPrintZ(&label_buff, "browser {d}" ++ "###{d}", .{ tab_o.tab_i.tabid, tab_o.tab_i.tabid }) catch return .{};
            }
        } else {
            label = std.fmt.bufPrintZ(&label_buff, "browser {d}" ++ "###{d}", .{ tab_o.tab_i.tabid, tab_o.tab_i.tabid }) catch return .{};
        }
        valid = selected_n == 1 and !real_obj.eql(ignored_obj) and (allowed_type.isEmpty() or real_obj.type_idx.eql(allowed_type));

        if (_coreui.beginMenu(allocator, coreui.Icons.Select ++ "  " ++ "From" ++ "###SelectFrom", true, null)) {
            defer _coreui.endMenu();

            if (_coreui.menuItem(allocator, label, .{ .enabled = valid }, null)) {
                return real_obj;
            }
        }

        return .{};
    }
});

fn isUuid(str: [:0]const u8) bool {
    return (str.len == 36 and str[8] == '-' and str[13] == '-' and str[18] == '-' and str[23] == '-');
}

const UiAssetBrowserResult = struct {
    filter: ?[:0]const u8 = null,
};

fn filterType(allocator: std.mem.Allocator, tab: *editor.TabO, db: cdb.DbId) !void {
    const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab));

    if (_coreui.beginPopup("asset_browser_filter_popup", .{})) {
        defer _coreui.endPopup();
        const impls = try _apidb.getImpl(allocator, editor.CreateAssetI);
        defer allocator.free(impls);

        const folder_type_idx = assetdb.Folder.typeIdx(_cdb, db);

        for (impls) |iface| {
            const menu_name = try iface.menu_item();
            var buff: [256:0]u8 = undefined;
            const type_idx = _cdb.getTypeIdx(db, iface.cdb_type).?;
            const type_name = _cdb.getTypeName(db, type_idx).?;
            const label = try std.fmt.bufPrintZ(&buff, "{s}###{s}", .{ menu_name, type_name });

            var selected = tab_o.type_filter.contains(type_idx);

            if (_coreui.menuItemPtr(allocator, label, .{ .selected = &selected }, null)) {
                if (selected) {
                    _ = try tab_o.type_filter.add(_allocator, type_idx);
                    _ = try tab_o.type_filter.add(_allocator, folder_type_idx);
                } else {
                    _ = tab_o.type_filter.remove(type_idx);
                    if (tab_o.type_filter.cardinality() == 1) {
                        _ = tab_o.type_filter.remove(folder_type_idx);
                    }
                }
            }
        }
    }

    if (_coreui.button(coreui.Icons.Filter ++ "###FilterAssetByType", .{})) {
        _coreui.openPopup("asset_browser_filter_popup", .{});
    }
}

fn uiAssetBrowser(
    allocator: std.mem.Allocator,
    tab: *editor.TabO,
    context: []const cetech1.StrId64,
    root_folder: cdb.ObjId,
    selectection: *coreui.Selection,
    filter_buff: [:0]u8,
    tags_filter: cdb.ObjId,
    args: editor_tree.CdbTreeViewArgs,
) !UiAssetBrowserResult {
    var result = UiAssetBrowserResult{};
    const new_args = args;

    const filter = args.filter;

    const new_filter = _coreui.uiFilter(filter_buff, filter);
    try filterType(allocator, tab, root_folder.db);
    _coreui.sameLine(.{});
    const tag_filter_used = try _tags.tagsInput(allocator, tags_filter, assetdb.Tags.propIdx(.Tags), false, null);

    var buff: [128]u8 = undefined;
    const final_label = try std.fmt.bufPrintZ(
        &buff,
        "AssetBrowser",
        .{},
    );

    defer _coreui.endChild();
    if (_coreui.beginChild(final_label, .{ .child_flags = .{ .border = true } })) {
        // Filter
        if (new_filter != null or tag_filter_used) {
            if (new_filter) |f| {
                result.filter = f;
            }

            if (new_filter != null and isUuid(new_filter.?)) {
                if (_uuid.fromStr(new_filter.?)) |uuid| {
                    if (_assetdb.getObjId(uuid)) |asset| {
                        _ = try _editor_tree.cdbTreeView(
                            allocator,
                            tab,
                            context,
                            .{ .top_level_obj = asset, .obj = asset },
                            selectection,
                            0,
                            .{ .expand_object = args.expand_object, .multiselect = args.multiselect, .opened_obj = args.opened_obj },
                        );
                    }
                }
            } else {
                const assets_filtered = _editor_asset.filerAsset(allocator, if (args.filter) |f| f else "", tags_filter) catch undefined;
                defer allocator.free(assets_filtered);

                std.sort.insertion(assetdb.FilteredAsset, assets_filtered, {}, assetdb.FilteredAsset.lessThan);
                for (assets_filtered) |asset| {
                    _ = try _editor_tree.cdbTreeView(
                        allocator,
                        tab,
                        context,
                        .{ .top_level_obj = asset.obj, .obj = asset.obj },
                        selectection,
                        0,
                        new_args,
                    );
                }
            }

            // Show clasic tree view
        } else {
            //_coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
            //defer _coreui.popStyleVar(.{});
            const new_selected = try _editor_tree.cdbTreeView(
                allocator,
                tab,
                context,
                .{ .top_level_obj = root_folder, .obj = root_folder },
                selectection,
                0,
                args,
            );
            if (new_selected) {
                const s = selectection.toSlice(allocator).?;
                defer allocator.free(s);

                _editor.propagateSelection(tab, s);
            }
        }
    }
    return result;
}

// Tests
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_filter_assets_and_folders",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemInputStrValue(_coreui, "###filter", "foo");

                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_core.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_core2.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_subcore.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###core_subfolder", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_filter_assets_by_uuid",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemInputStrValue(_coreui, "###filter", "018b5c74-06f7-740e-be81-d727adec5fb4");

                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_subcore.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_filter_assets_by_tag",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/###AddTags", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/018e0348-b358-779f-b40c-7d34d3fca2a7/###Tag", .{}, null);

                    ctx.itemAction(_coreui, .DoubleClick, "**/###core", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_subcore.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_move_assets_to_folder_by_drag_and_drop",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");

                    //ctx.itemAction(_coreui, .Click, "**/###ROOT/###asset_a.ct_foo_asset", .{}, null);
                    ctx.yield(_coreui, 1);

                    ctx.dragAndDrop(
                        _coreui,
                        "**/###ROOT/###asset_a.ct_foo_asset",
                        "**/###ROOT/###folder_b",
                        //"//###ct_editor_asset_browser_tab_1/**/###ROOT/###folder_a",
                        .left,
                    );
                }
            },
        );
    }
});

// Cdb
var AssetTypeIdx: cdb.TypeIdx = undefined;

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        AssetTypeIdx = assetdb.Asset.typeIdx(_cdb, db);
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
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;
    _editor_tree = apidb.getZigApi(module_name, editor_tree.TreeAPI).?;
    _tags = apidb.getZigApi(module_name, editor_tags.EditorTagsApi).?;
    _editor_asset = apidb.getZigApi(module_name, editor_asset.EditorAssetAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.setGlobalVarValue(editor.TabTypeI, module_name, ASSET_BROWSER_NAME, asset_browser_tab);

    try apidb.implOrRemove(module_name, editor.TabTypeI, &asset_browser_tab, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.AssetBrowserAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_browser(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
