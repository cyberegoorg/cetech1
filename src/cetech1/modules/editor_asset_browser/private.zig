const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const strid = cetech1.strid;

const public = @import("editor_asset_browser.zig");

const editor = @import("editor");
const editor_tree = @import("editor_tree");
const editor_tags = @import("editor_tags");

const Icons = cetech1.editorui.CoreIcons;

const MODULE_NAME = "editor_asset_browser";
const ASSET_BROWSER_NAME = "ct_editor_asset_browser_tab";

const ASSET_BROWSER_ICON = Icons.FA_FOLDER_TREE;
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

const MAIN_CONTEXTS = &.{
    editor.Contexts.edit,
    editor.Contexts.open,
    editor.Contexts.create,
    editor.Contexts.move,
    editor.Contexts.delete,
    editor.Contexts.debug,
};

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _editor_tree: *editor_tree.TreeAPI = undefined;
var _assetdb: *assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *cetech1.uuid.UuidAPI = undefined;
var _tags: *editor_tags.EditorTagsApi = undefined;

const G = struct {
    tab_vt: *editor.EditorTabTypeI = undefined,
};
var _g: *G = undefined;

var api = public.AssetBrowserAPI{
    .selectObjFromBrowserMenu = selectObjFromBrowserMenu,
};

fn selectObjFromBrowserMenu(allocator: std.mem.Allocator, db: *cdb.CdbDb, ignored_obj: cdb.ObjId, allowed_type: strid.StrId32) ?cdb.ObjId {
    const tabs = _editor.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch return null;
    defer allocator.free(tabs);

    var label_buff: [1024]u8 = undefined;
    for (tabs) |tab| {
        const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab.inst));
        const selected_n = _editorui.selectedCount(allocator, db, tab_o.selection_obj);

        const selected_obj = _editorui.getFirstSelected(allocator, db, tab_o.selection_obj);

        var valid = false;
        var label: [:0]u8 = undefined;

        var real_obj = selected_obj;
        if (db.readObj(selected_obj)) |r| {
            if (assetdb.AssetType.isSameType(selected_obj)) {
                real_obj = assetdb.AssetType.readSubObj(db, r, .Object).?;

                const path = _assetdb.getFilePathForAsset(selected_obj, allocator) catch undefined;
                defer allocator.free(path);
                label = std.fmt.bufPrintZ(&label_buff, "browser {d} - {s}", .{ tab.tabid, path }) catch return null;
            } else {
                label = std.fmt.bufPrintZ(&label_buff, "browser {d}", .{tab.tabid}) catch return null;
            }
        } else {
            label = std.fmt.bufPrintZ(&label_buff, "browser {d}", .{tab.tabid}) catch return null;
        }
        valid = selected_n == 1 and !real_obj.eq(ignored_obj) and (allowed_type.id == 0 or real_obj.type_hash.id == allowed_type.id);

        if (_editorui.beginMenu(allocator, editorui.Icons.Select ++ " " ++ "From", true, null)) {
            defer _editorui.endMenu();

            if (_editorui.menuItem(allocator, label, .{ .enabled = valid }, null)) {
                return real_obj;
            }
        }
    }

    return null;
}

const AssetBrowserTab = struct {
    tab_i: editor.EditorTabI,
    db: cdb.CdbDb,
    selection_obj: cdb.ObjId,
    opened_obj: cdb.ObjId,
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
    tags: cdb.ObjId,
};

// Fill editor tab interface

var asset_browser_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = ASSET_BROWSER_NAME,
    .tab_hash = .{ .id = strid.strId32(ASSET_BROWSER_NAME).id },
    .create_on_init = true,
}, struct {
    pub fn menuName() [:0]const u8 {
        return ASSET_BROWSER_ICON ++ " Asset browser";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) [:0]const u8 {
        _ = inst;
        return ASSET_BROWSER_ICON ++ " Asset browser";
    }

    // Create new FooTab instantce
    pub fn create(dbc: *cdb.Db) ?*editor.EditorTabI {
        var tab_inst = _allocator.create(AssetBrowserTab) catch undefined;
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        tab_inst.* = AssetBrowserTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },
            .db = db,
            .tags = assetdb.TagsType.createObject(&db) catch return null,
            .selection_obj = editorui.ObjSelectionType.createObject(&db) catch return null,
            .opened_obj = editorui.ObjSelectionType.createObject(&db) catch return null,
        };
        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) void {
        var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab_inst.inst));
        tab_o.db.destroyObject(tab_o.tags);
        tab_o.db.destroyObject(tab_o.selection_obj);
        _allocator.destroy(tab_o);
    }

    pub fn menu(inst: *editor.TabO) void {
        var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

        var tmp_arena = _tempalloc.createTempArena() catch undefined;
        defer _tempalloc.destroyTempArena(tmp_arena);
        const allocator = tmp_arena.allocator();

        const selected_count = _editorui.selectedCount(allocator, &tab_o.db, tab_o.selection_obj);

        if (_editorui.beginMenu(allocator, editorui.Icons.ContextMenu, selected_count != 0, null)) {
            defer _editorui.endMenu();
            _editor.showObjContextMenu(
                allocator,
                &tab_o.db,
                tab_o,
                MAIN_CONTEXTS,
                tab_o.selection_obj,
                null,
                null,
            ) catch undefined;
        }

        if (_editorui.beginMenu(allocator, editorui.Icons.AddAsset, selected_count != 0, null)) {
            defer _editorui.endMenu();

            _editor.showObjContextMenu(
                allocator,
                &tab_o.db,
                tab_o,
                &.{editor.Contexts.create},
                tab_o.selection_obj,
                null,
                null,
            ) catch undefined;
        }
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO) void {
        var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

        const root_folder = _assetdb.getRootFolder();
        if (root_folder.isEmpty()) {
            _editorui.textUnformatted("No root folder");
            return;
        }

        var tmp_arena = _tempalloc.createTempArena() catch undefined;
        defer _tempalloc.destroyTempArena(tmp_arena);

        const allocator = tmp_arena.allocator();

        const r = uiAssetBrowser(
            allocator,
            &tab_o.db,
            tab_o,
            MAIN_CONTEXTS,
            root_folder,
            tab_o.selection_obj,
            &tab_o.filter_buff,
            tab_o.tags,
            .{
                .filter = if (tab_o.filter == null) null else tab_o.filter.?.ptr,
                .multiselect = true,
                .expand_object = false,
                .opened_obj = tab_o.opened_obj,
            },
        ) catch undefined;
        tab_o.filter = r.filter;
    }

    pub fn focused(inst: *editor.TabO) void {
        const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));
        _ = tab_o;
    }
});

fn isUuid(str: [:0]const u8) bool {
    return (str.len == 36 and str[8] == '-' and str[13] == '-' and str[18] == '-' and str[23] == '-');
}

const UiAssetBrowserResult = struct {
    filter: ?[:0]const u8 = null,
};

fn getTagColor(db: *cdb.CdbDb, tag_r: *cdb.Obj) [4]f32 {
    const tag_color_obj = assetdb.TagType.readSubObj(db, tag_r, .Color);
    var color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    if (tag_color_obj) |color_obj| {
        color = cetech1.cdb_types.color4fToSlice(db, color_obj);
    }

    return color;
}

fn uiAssetBrowser(
    allocator: std.mem.Allocator,
    db: *cdb.CdbDb,
    tab: *editor.TabO,
    context: []const strid.StrId64,
    root_folder: cdb.ObjId,
    selectection: cdb.ObjId,
    filter_buff: [:0]u8,
    tags_filter: cdb.ObjId,
    args: editor_tree.CdbTreeViewArgs,
) !UiAssetBrowserResult {
    var result = UiAssetBrowserResult{};
    const new_args = args;

    const filter = if (args.filter) |filter| filter[0..std.mem.len(filter) :0] else null;

    const new_filter = _editorui.uiFilter(filter_buff, filter);
    const tag_filter_used = try _tags.tagsInput(allocator, db, tags_filter, assetdb.TagsType.propIdx(.Tags), false, null);

    var buff: [128]u8 = undefined;
    const final_label = try std.fmt.bufPrintZ(
        &buff,
        "AssetBrowser##{d}",
        .{root_folder.toU64()},
    );

    if (_editorui.beginChild(final_label, .{ .border = true, .flags = .{ .always_auto_resize = true } })) {
        defer _editorui.endChild();

        // Filter
        if (new_filter != null or tag_filter_used) {
            if (new_filter) |f| {
                result.filter = f;
            }

            if (new_filter != null and isUuid(new_filter.?)) {
                if (_uuid.fromStr(new_filter.?)) |uuid| {
                    if (_assetdb.getObjId(uuid)) |asset| {
                        _editor_tree.cdbTreeView(
                            allocator,
                            db,
                            tab,
                            context,
                            asset,
                            selectection,
                            .{ .expand_object = args.expand_object, .multiselect = args.multiselect, .opened_obj = args.opened_obj },
                        ) catch undefined;
                    }
                }
            } else {
                const assets_filtered = _assetdb.filerAsset(allocator, if (args.filter) |fil| std.mem.sliceTo(fil, 0) else "", tags_filter) catch undefined;
                defer allocator.free(assets_filtered);

                std.sort.insertion(assetdb.FilteredAsset, assets_filtered, {}, assetdb.FilteredAsset.lessThan);
                for (assets_filtered) |asset| {
                    _editor_tree.cdbTreeView(
                        allocator,
                        db,
                        tab,
                        context,
                        asset.obj,
                        selectection,
                        new_args,
                    ) catch undefined;
                }
            }

            // Show clasic tree view
        } else {
            _editorui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
            defer _editorui.popStyleVar(.{});
            _editor_tree.cdbTreeView(
                allocator,
                db,
                tab,
                context,
                root_folder,
                selectection,
                args,
            ) catch undefined;
        }
    }
    return result;
}

//

// Cdb

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;

    // basic
    _allocator = allocator;
    _log = log;
    _apidb = apidb;
    _cdb = apidb.getZigApi(cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;
    _editor = apidb.getZigApi(editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;
    _uuid = apidb.getZigApi(cetech1.uuid.UuidAPI).?;
    _editor_tree = apidb.getZigApi(editor_tree.TreeAPI).?;
    _tags = apidb.getZigApi(editor_tags.EditorTagsApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, ASSET_BROWSER_NAME, .{});
    _g.tab_vt.* = asset_browser_tab;

    try apidb.implOrRemove(editor.EditorTabTypeI, &asset_browser_tab, load);

    try apidb.setOrRemoveZigApi(public.AssetBrowserAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_browser(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
