const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_asset_browser";
const ASSET_BROWSER_NAME = "ct_editor_asset_browser_tab";

const ASSET_TREE_ASPECT_NAME = "ct_asset_tree_aspect";
const FOLDER_TREE_ASPECT_NAME = "ct_folder_tree_aspect";
const FOLDER_CREATE_ASSET_I = "ct_assetbrowser_create_asset_folder_i";

const ASSET_BROWSER_ICON = Icons.FA_FOLDER_TREE;
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

const ASSET_MODIFIED_TEXT_COLOR = [4]f32{ 0.9, 0.9, 0.0, 1.0 };

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _editortree: *editor.TreeAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *cetech1.uuid.UuidAPI = undefined;
var _tags: *editor.AssetTagsApi = undefined;
var _inspector: *editor.InspectorAPI = undefined;

const G = struct {
    asset_browser_tab_vt: *editor.EditorTabTypeI = undefined,
    asset_tree_aspect: *editor.UiTreeAspect = undefined,
    folder_tree_aspect: *editor.UiTreeAspect = undefined,
    folder_create_asset_i: *editor.CreateAssetI = undefined,
};
var _g: *G = undefined;

var api = editor.AssetBrowserAPI{
    .buffGetValidName = buffGetValidName,
};

const AssetBrowserTab = struct {
    tab_i: editor.EditorTabI,
    db: cetech1.cdb.CdbDb,
    selection_obj: cetech1.cdb.ObjId,
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
    tags: cetech1.cdb.ObjId,
};

// Fill editor tab interface

var foo_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = ASSET_BROWSER_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(ASSET_BROWSER_NAME).id },
    .create_on_init = true,
    .menu_name = tabMenuName,
    .title = tabTitle,
    .create = tabCreate,
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
    .focused = tabFocused,
});

fn tabMenuName() [:0]const u8 {
    return ASSET_BROWSER_ICON ++ " Asset browser";
}

// Return tab title
fn tabTitle(inst: *editor.TabO) [:0]const u8 {
    _ = inst;
    return ASSET_BROWSER_ICON ++ " Asset browser";
}

// Create new FooTab instantce
fn tabCreate(dbc: *cetech1.cdb.Db) ?*editor.EditorTabI {
    var tab_inst = _allocator.create(AssetBrowserTab) catch undefined;
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    tab_inst.* = AssetBrowserTab{
        .tab_i = .{
            .vt = _g.asset_browser_tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = db,
        .tags = cetech1.assetdb.AssetTagsType.createObject(&db) catch return null,
        .selection_obj = editor.ObjSelectionType.createObject(&db) catch return null,
    };
    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: *editor.EditorTabI) void {
    var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab_inst.inst));
    tab_o.db.destroyObject(tab_o.tags);
    tab_o.db.destroyObject(tab_o.selection_obj);
    _allocator.destroy(tab_o);
}

fn isUuid(str: [:0]const u8) bool {
    return (str.len == 36 and str[8] == '-' and str[13] == '-' and str[18] == '-' and str[23] == '-');
}

const UiAssetBrowserResult = struct {
    filter: ?[:0]const u8 = null,
};

fn getTagColor(db: *cetech1.cdb.CdbDb, tag_r: *cetech1.cdb.Obj) [4]f32 {
    const tag_color_obj = cetech1.assetdb.AssetTagType.readSubObj(db, tag_r, .Color);
    var color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    if (tag_color_obj) |color_obj| {
        color = cetech1.cdb_types.color4fToSlice(db, color_obj);
    }

    return color;
}

fn uiAssetBrowser(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    root_folder: cetech1.cdb.ObjId,
    selectection: cetech1.cdb.ObjId,
    filter_buff: [:0]u8,
    tags_filter: cetech1.cdb.ObjId,
    args: editor.CdbTreeViewArgs,
) !UiAssetBrowserResult {
    var result = UiAssetBrowserResult{};
    const new_args = args;

    const filter = if (args.filter) |filter| filter[0..std.mem.len(filter) :0] else null;

    const new_filter = _editorui.uiFilter(filter_buff, filter);
    const tag_filter_used = try _tags.tagsInput(allocator, db, tags_filter, cetech1.assetdb.AssetTagsType.propIdx(.Tags), false, null);

    //_editorui.separator();

    if (_editorui.beginChild("AssetBrowser", .{ .border = true, .flags = .{ .always_auto_resize = true } })) {
        defer _editorui.endChild();

        // Filter
        if (new_filter != null or tag_filter_used) {
            if (new_filter) |f| {
                result.filter = f;
            }

            if (new_filter != null and isUuid(new_filter.?)) {
                if (_uuid.fromStr(new_filter.?)) |uuid| {
                    if (_assetdb.getObjId(uuid)) |asset| {
                        assetUiTree(
                            allocator,
                            db,
                            asset,
                            selectection,
                            true,
                            .{ .expand_object = args.expand_object, .multiselect = args.multiselect },
                            null,
                        ) catch undefined;
                    }
                }
            } else {
                const assets_filtered = _assetdb.filerAsset(allocator, if (args.filter) |fil| std.mem.sliceTo(fil, 0) else "", tags_filter) catch undefined;
                defer allocator.free(assets_filtered);

                std.sort.insertion(cetech1.assetdb.FilteredAsset, assets_filtered, {}, cetech1.assetdb.FilteredAsset.lessThan);
                for (assets_filtered) |asset| {
                    assetUiTree(
                        allocator,
                        db,
                        asset.obj,
                        selectection,
                        true,
                        new_args,
                        asset.score,
                    ) catch undefined;
                }
            }

            // Show clasic tree view
        } else {
            _editorui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
            defer _editorui.popStyleVar(.{});
            folderUiTreeAspect(allocator, db.db, root_folder, selectection, new_args) catch undefined;
        }
    }
    return result;
}

// Draw tab content
fn tabUi(inst: *editor.TabO) void {
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
        root_folder,
        tab_o.selection_obj,
        &tab_o.filter_buff,
        tab_o.tags,
        .{ .filter = if (tab_o.filter == null) null else tab_o.filter.?.ptr, .multiselect = true, .expand_object = false },
    ) catch undefined;

    tab_o.filter = r.filter;
}

fn tabFocused(inst: *editor.TabO) void {
    var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));
    _editor.propagateSelection(&tab_o.db, tab_o.selection_obj);
}
//

fn buffFormatAssetLabel(
    allocator: std.mem.Allocator,
    buff: []u8,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    path_label: bool,
) ![:0]u8 {
    var final_label: [:0]u8 = undefined;

    const obj_r = db.readObj(obj) orelse return error.InvalidObjId;

    const is_modified = _assetdb.isAssetModified(obj);
    const is_deleted = _assetdb.isToDeleted(obj);
    if (cetech1.assetdb.FolderType.isSameType(obj)) {
        var folder_name = cetech1.assetdb.FolderType.readStr(db, obj_r, .Name);
        const folder_parent = cetech1.assetdb.FolderType.readRef(db, obj_r, .Parent);

        if (folder_parent == null) {
            folder_name = "Root";
        }

        final_label = try std.fmt.bufPrintZ(
            buff,
            "{s}" ++ "{s}" ++ "{s}" ++ "  " ++ "{s}" ++ "###{d}",
            .{
                FOLDER_ICON,
                if (is_modified) " " ++ Icons.FA_STAR_OF_LIFE else "",
                if (is_deleted) " " ++ editor.Icons.Deleted else "",
                folder_name.?,
                obj.toU64(),
            },
        );
    } else {
        const asset_obj = cetech1.assetdb.AssetType.readSubObj(db, obj_r, .Object).?;
        const asset_status_fmt = "{s} {s}{s}";

        if (!path_label) {
            const asset_name = cetech1.assetdb.AssetType.readStr(db, obj_r, .Name).?;
            const type_name = db.getTypeName(asset_obj.type_hash).?;

            final_label = try std.fmt.bufPrintZ(
                buff,
                asset_status_fmt ++ "  " ++ "{s}.{s}",
                .{
                    ASSET_ICON,
                    if (is_modified) Icons.FA_STAR_OF_LIFE else "",
                    if (is_deleted) " " ++ editor.Icons.Deleted else "",
                    asset_name,
                    type_name,
                },
            );
        } else {
            const path = _assetdb.getFilePathForAsset(obj, allocator) catch undefined;
            defer allocator.free(path);

            final_label = try std.fmt.bufPrintZ(
                buff,
                asset_status_fmt ++ "  " ++ "{s}",
                .{
                    ASSET_ICON,
                    if (is_modified) Icons.FA_STAR_OF_LIFE else "",
                    if (is_deleted) " " ++ editor.Icons.Deleted else "",
                    path,
                },
            );
        }
    }

    return final_label;
}

fn getAssetColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) [4]f32 {
    _ = db;
    const is_modified = _assetdb.isAssetModified(obj);
    const is_deleted = _assetdb.isToDeleted(obj);

    if (is_modified) {
        return ASSET_MODIFIED_TEXT_COLOR;
    } else if (is_deleted) {
        return editor.Colors.Deleted;
    }
    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn formatTagsToLabel(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, tag_prop_idx: u32) !void {
    const obj_r = db.readObj(obj) orelse return;

    if (db.readRefSet(obj_r, tag_prop_idx, allocator)) |tags| {
        var begin_pos: ?f32 = null;
        for (tags) |tag| {
            const tag_r = db.readObj(tag) orelse continue;

            var tag_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
            if (cetech1.assetdb.AssetTagType.readSubObj(db, tag_r, .Color)) |c| {
                tag_color = cetech1.cdb_types.color4fToSlice(db, c);
            }
            const tag_name = cetech1.assetdb.AssetTagType.readStr(db, tag_r, .Name) orelse "No name =/";

            _editorui.pushObjId(tag);
            defer _editorui.popId();

            if (begin_pos == null) {
                _editorui.sameLine(.{});
            } else {
                begin_pos.? += 6.0;
                _editorui.sameLine(.{ .offset_from_start_x = begin_pos.? });
            }

            var tag_buf: [128:0]u8 = undefined;
            const tag_lbl = try std.fmt.bufPrintZ(&tag_buf, editor.Icons.Tag, .{});
            if (begin_pos == null) {
                begin_pos = _editorui.getCursorPosX();
            }

            _editorui.textUnformattedColored(tag_color, tag_lbl);

            if (_editorui.isItemHovered(.{})) {
                _editorui.beginTooltip();
                const name_lbl = try std.fmt.bufPrintZ(&tag_buf, editor.Icons.Tag ++ " " ++ "{s}", .{tag_name});
                _editorui.textUnformatted(name_lbl);

                const desription = cetech1.assetdb.AssetTagType.readStr(db, tag_r, .Description);
                if (desription) |d| {
                    _editorui.textUnformatted(d);
                }
                _editorui.endTooltip();
            }
        }
    }
}

// Folder aspect
fn lessThanAssetFolder(db: *cetech1.cdb.CdbDb, lhs: cetech1.cdb.ObjId, rhs: cetech1.cdb.ObjId) bool {
    std.debug.assert(cetech1.assetdb.FolderType.propIdx(.Name) == cetech1.assetdb.AssetType.propIdx(.Name));

    const l_name = db.readStr(db.readObj(lhs).?, cetech1.assetdb.FolderType.propIdx(.Name)) orelse return false;
    const r_name = db.readStr(db.readObj(rhs).?, cetech1.assetdb.FolderType.propIdx(.Name)) orelse return false;
    return std.ascii.lessThanIgnoreCase(l_name, r_name);
}

var folder_ui_tree_aspect = editor.UiTreeAspect.implement(folderUiTreeAspect);
fn folderUiTreeAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    selection: cetech1.cdb.ObjId,
    args: editor.CdbTreeViewArgs,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buff: [128]u8 = undefined;

    const obj_r = db.readObj(obj) orelse return;

    var folder_name = cetech1.assetdb.FolderType.readStr(&db, obj_r, .Name);
    const folder_parent = cetech1.assetdb.FolderType.readRef(&db, obj_r, .Parent);

    if (folder_parent == null) {
        folder_name = "Root";
    }

    var open = true;
    var tree_open = false;

    const folder_label = try buffFormatAssetLabel(
        allocator,
        &buff,
        &db,
        obj,
        false,
    );

    _editorui.pushStyleColor4f(.{ .idx = .text, .c = getAssetColor(&db, obj) });
    tree_open = _editortree.cdbTreeNode(folder_label, folder_parent == null, false, _editor.isSelected(&db, selection, obj), false, args);
    _editorui.popStyleColor(.{});

    if (_editorui.isItemHovered(.{})) {
        _editorui.beginTooltip();
        const desription = cetech1.assetdb.FolderType.readStr(&db, obj_r, .Description);
        if (desription) |d| {
            _editorui.textUnformatted(d);
        }
        _editorui.endTooltip();
    }

    if (_editorui.isItemActivated()) {
        try _editor.handleSelection(allocator, &db, selection, obj, args.multiselect);
    }

    if (_editorui.beginPopupContextItem()) {
        try objContextMenu(allocator, &db, obj);
        _editorui.endPopup();
    }

    try formatTagsToLabel(allocator, &db, obj, cetech1.assetdb.FolderType.propIdx(.Tags));

    open = tree_open;

    if (open) {
        var folders = std.ArrayList(cetech1.cdb.ObjId).init(allocator);
        defer folders.deinit();

        var assets = std.ArrayList(cetech1.cdb.ObjId).init(allocator);
        defer assets.deinit();

        const set = try db.getReferencerSet(obj, allocator);
        defer allocator.free(set);

        for (set) |ref_obj| {
            if (cetech1.assetdb.AssetType.isSameType(ref_obj)) {
                try assets.append(ref_obj);
            } else if (cetech1.assetdb.FolderType.isSameType(ref_obj)) {
                try folders.append(ref_obj);
            }
        }

        std.sort.insertion(cetech1.cdb.ObjId, folders.items, &db, lessThanAssetFolder);
        std.sort.insertion(cetech1.cdb.ObjId, assets.items, &db, lessThanAssetFolder);

        for (folders.items) |folder| {
            try _editortree.cdbTreeView(allocator, &db, folder, selection, args);
        }
        for (assets.items) |asset| {
            try _editortree.cdbTreeView(allocator, &db, asset, selection, args);
        }

        if (tree_open) {
            _editortree.cdbTreePop();
        }
    }
}

// Asset tree aspect
var asset_ui_tree_aspect = editor.UiTreeAspect.implement(assetUiTreeAsspect);
fn assetUiTreeAsspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    selectection: cetech1.cdb.ObjId,
    args: editor.CdbTreeViewArgs,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    try assetUiTree(allocator, &db, obj, selectection, false, args, null);
}

fn assetUiTree(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    selection: cetech1.cdb.ObjId,
    path_label: bool,
    args: editor.CdbTreeViewArgs,
    score: ?f64,
) !void {
    _ = score;
    var buff: [128:0]u8 = undefined;

    const obj_r = db.readObj(obj) orelse return;

    const asset_obj = cetech1.assetdb.AssetType.readSubObj(db, obj_r, .Object).?;

    if (!args.ignored_object.isEmpty() and args.ignored_object.eq(asset_obj)) {
        return;
    }

    if (!args.expand_object and args.only_types.id != 0 and asset_obj.type_hash.id != args.only_types.id) {
        return;
    }

    const is_modified = _assetdb.isAssetModified(obj);
    const is_deleted = _assetdb.isToDeleted(obj);

    const asset_label = try buffFormatAssetLabel(allocator, &buff, db, obj, path_label);

    const asset_status_fmt = "{s} {s}{s}";
    _ = asset_status_fmt;

    if (is_modified) {
        _editorui.pushStyleColor4f(.{ .idx = .text, .c = ASSET_MODIFIED_TEXT_COLOR });
    } else if (is_deleted) {
        _editorui.pushStyleColor4f(.{ .idx = .text, .c = editor.Colors.Deleted });
    } else {
        _editorui.pushStyleColor4f(.{ .idx = .text, .c = .{ 1.0, 1.0, 1.0, 1.0 } });
    }

    // if (score) |s| {
    //     const scr: f32 = @min(@as(f32, @floatCast(s)), 1.0);
    //     const inv_scr: f32 = 1 - scr;
    //     const color: f32 = if (inv_scr == scr) 1.0 else @max(0.7, 1.0 * inv_scr);
    //     _editorui.pushStyleColor4f(.{ .idx = .text, .c = .{ color, color, color, 1.0 } });
    // }

    const open = _editorui.treeNodeFlags(asset_label, .{ .leaf = !args.expand_object, .selected = _editor.isSelected(db, selection, obj) });
    _editorui.popStyleColor(.{});

    if (open) {

        // if (score != null) {
        //     _editorui.popStyleColor(.{});
        // }

        if (_editorui.isItemActivated()) {
            try _editor.handleSelection(allocator, db, selection, obj, args.multiselect);
        }

        if (_editorui.beginPopupContextItem()) {
            try objContextMenu(allocator, db, obj);
            _editorui.endPopup();
        }

        if (_editorui.isItemHovered(.{})) {
            _editorui.beginTooltip();
            const uuid = _assetdb.getUuid(obj).?;
            const uuid_str = try std.fmt.bufPrintZ(&buff, "Asset UUID: {s}", .{uuid});
            _editorui.textUnformatted(uuid_str);
            _editorui.endTooltip();
        }

        try formatTagsToLabel(allocator, db, obj, cetech1.assetdb.AssetType.propIdx(.Tags));

        if (args.expand_object) {
            try _editortree.cdbTreeView(allocator, db, asset_obj, selection, args);
        }

        _editorui.treePop();
    }
}

fn buffGetValidName(allocator: std.mem.Allocator, buf: [:0]u8, db: *cetech1.cdb.CdbDb, folder: cetech1.cdb.ObjId, type_hash: cetech1.strid.StrId32, base_name: [:0]const u8) ![:0]const u8 {
    const set = try db.getReferencerSet(folder, allocator);
    defer allocator.free(set);

    var name_set = std.StringArrayHashMap(void).init(allocator);
    defer name_set.deinit();

    if (type_hash.id != cetech1.assetdb.FolderType.type_hash.id) {
        for (set) |obj| {
            if (obj.type_hash.id != cetech1.assetdb.AssetType.type_hash.id) continue;

            const asset_obj = cetech1.assetdb.AssetType.readSubObj(db, db.readObj(obj).?, .Object).?;
            if (asset_obj.type_hash.id != type_hash.id) continue;

            if (cetech1.assetdb.AssetType.readStr(db, db.readObj(obj).?, .Name)) |name| {
                try name_set.put(name, {});
            }
        }
    } else {
        for (set) |obj| {
            if (obj.type_hash.id != cetech1.assetdb.FolderType.type_hash.id) continue;

            if (cetech1.assetdb.AssetType.readStr(db, db.readObj(obj).?, .Name)) |name| {
                try name_set.put(name, {});
            }
        }
    }

    var number: u32 = 2;
    var name: [:0]const u8 = base_name;
    while (name_set.contains(name)) : (number += 1) {
        name = try std.fmt.bufPrintZ(buf, "{s}{d}", .{ base_name, number });
    }

    return name;
}

fn getFolderForSelectedObj(db: *cetech1.cdb.CdbDb, selected_obj: cetech1.cdb.ObjId) cetech1.cdb.ObjId {
    var parent_folder: cetech1.cdb.ObjId = _assetdb.getRootFolder();

    if (selected_obj.type_hash.id == cetech1.assetdb.FolderType.type_hash.id) {
        parent_folder = selected_obj;
    } else {
        if (db.readObj(selected_obj)) |r| {
            parent_folder = cetech1.assetdb.AssetType.readRef(db, r, .Folder).?;
        }
    }
    return parent_folder;
}

fn objContextMenu(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) !void {

    // Open
    if (_editorui.beginMenu(editor.Icons.Open ++ "  " ++ "Open", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem("New inspector", .{})) {
            _inspector.openNewInspectorForObj(db, obj);
        }
    }

    // Create new asset
    if (_editorui.beginMenu(editor.Icons.AddFile ++ "  " ++ "New", true)) {
        defer _editorui.endMenu();

        var it = _apidb.getFirstImpl(editor.CreateAssetI);
        while (it) |node| : (it = node.next) {
            const iface = cetech1.apidb.ApiDbAPI.toInterface(editor.CreateAssetI, node);
            const menu_name = iface.menu_item.?();
            var buff: [256:0]u8 = undefined;
            const label = try std.fmt.bufPrintZ(&buff, "{s}", .{cetech1.fromCstrZ(menu_name)});

            if (_editorui.menuItem(label, .{})) {
                var parent_folder = getFolderForSelectedObj(db, obj);
                if (!parent_folder.isEmpty()) {
                    iface.create.?(&allocator, db.db, parent_folder);
                }
            }
        }
    }

    _editorui.separator();

    var is_root_folder = false;
    const is_folder = cetech1.assetdb.FolderType.isSameType(obj);
    if (is_folder) {
        const ref = cetech1.assetdb.FolderType.readRef(db, db.readObj(obj).?, .Parent);
        is_root_folder = ref == null;
    }

    if (_assetdb.isToDeleted(obj)) {
        if (_editorui.menuItem(editor.Icons.Revive ++ " " ++ "Revive deleted", .{ .enabled = !is_root_folder })) {
            _assetdb.reviveDeleted(obj);
        }
    } else {
        if (_editorui.menuItem(editor.Icons.Delete ++ " " ++ "Delete", .{ .enabled = !is_root_folder })) {
            if (is_folder) {
                try _assetdb.deleteFolder(db, obj);
            } else {
                try _assetdb.deleteAsset(db, obj);
            }
        }
    }

    _editorui.separator();

    // Copy
    if (_editorui.beginMenu(editor.Icons.CopyToClipboard ++ " " ++ "Copy to clipboard", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem("Asset UUID", .{})) {
            const uuid = _assetdb.getUuid(obj).?;
            var buff: [128]u8 = undefined;
            const uuid_str = try std.fmt.bufPrintZ(&buff, "{s}", .{uuid});
            _editorui.setClipboardText(uuid_str);
        }
    }
    _editorui.separator();

    // Debug
    if (_editorui.beginMenu(editor.Icons.Debug ++ "  " ++ "Debug", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem(editor.Icons.Save ++ " " ++ "Force save", .{})) {
            try _assetdb.saveAsset(allocator, obj);
        }
    }
}

//

// Draw tab menu
fn tabMenu(inst: *editor.TabO) void {
    var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    const selected_count = _editor.selectedCount(allocator, &tab_o.db, tab_o.selection_obj);

    if (_editorui.beginMenu("Asset", selected_count == 1)) {
        objContextMenu(allocator, &tab_o.db, _editor.getFirstSelected(allocator, &tab_o.db, tab_o.selection_obj)) catch undefined;
        defer _editorui.endMenu();
    }
}

//
var select_asset_uimodal = editor.UiModalI.implement(
    cetech1.strid.strId32("select_asset_modal"),
    selectAssetModalUI,
    selectAssetModalCreate,
    selectAssetModalDestroy,
);

const select_asset_modal_label = cetech1.editorui.Icons.FA_FILE ++ "  " ++ "Select asset###select_asset_modal";
const SelectAssetModalState = struct {
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
    filter_tags: cetech1.cdb.ObjId = .{},
    selection: cetech1.cdb.ObjId = .{},
    on_set: editor.UiModalI.OnSetFN = undefined,
    data: editor.UiModalI.Data = .{},
};

fn selectAssetModalCreate(allocator: std.mem.Allocator, dbc: *cetech1.cdb.Db, on_set: editor.UiModalI.OnSetFN, data: editor.UiModalI.Data) ?*anyopaque {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    var state = allocator.create(SelectAssetModalState) catch return null;

    state.* = SelectAssetModalState{
        .on_set = on_set,
        .data = data,
        .selection = editor.ObjSelectionType.createObject(&db) catch return null,
        .filter_tags = cetech1.assetdb.AssetTagsType.createObject(&db) catch return null,
    };

    return state;
}

fn selectAssetModalDestroy(allocator: std.mem.Allocator, dbc: *cetech1.cdb.Db, modal_inst: *anyopaque) !void {
    const state: *SelectAssetModalState = @alignCast(@ptrCast(modal_inst));

    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    db.destroyObject(state.selection);
    db.destroyObject(state.filter_tags);

    allocator.destroy(state);
}

fn selectAssetModalUI(allocator: std.mem.Allocator, dbc: *cetech1.cdb.Db, modal_inst: *anyopaque) !bool {
    var state: *SelectAssetModalState = @alignCast(@ptrCast(modal_inst));

    _editorui.openPopup(select_asset_modal_label, .{});

    if (_editorui.beginPopupModal(
        select_asset_modal_label,
        .{
            .flags = .{
                //.always_auto_resize = true,
                .no_saved_settings = true,
                //.no_scrollbar = true,
            },
        },
    )) {
        defer _editorui.endPopup();

        var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
        const params = std.mem.bytesToValue(editor.SelectAssetParams, state.data.data[0..@sizeOf(editor.SelectAssetParams)]);

        const r = try uiAssetBrowser(
            allocator,
            &db,
            _assetdb.getRootFolder(),
            state.selection,
            &state.filter_buff,
            state.filter_tags,
            .{
                .filter = if (state.filter == null) null else state.filter.?.ptr,
                .ignored_object = params.ignored_object,
                .only_types = params.only_types,
                .multiselect = params.multiselect,
                .expand_object = params.expand,
            },
        );

        // if (r.selected_obj) |selected| {
        //     try _editor.setSelection(allocator, &db, select_asset_modal_filter_selected, selected);
        // }
        state.filter = r.filter;

        _editorui.separator();
        if (_editorui.button(cetech1.editorui.Icons.FA_CHECK ++ "  " ++ "Select", .{})) {
            const selected_count = _editor.selectedCount(allocator, &db, state.selection);

            if (selected_count != 0) {
                state.on_set(@constCast(@ptrCast(&state.selection)), state.data);
            }

            _editorui.closeCurrentPopup();
            return false;
        }

        _editorui.sameLine(.{});

        if (_editorui.button(editor.Icons.Nothing ++ "  " ++ "Nothing", .{})) {
            _editorui.closeCurrentPopup();
            return false;
        }
    }

    return true;
}

// Create folder
var create_folder_i = editor.CreateAssetI.implement(
    createAssetFolderMenuItem,
    createAssetFolderMenuItemCreate,
);
fn createAssetFolderMenuItemCreate(
    allocator: *const std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    folder: cetech1.cdb.ObjId,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buff: [256:0]u8 = undefined;
    const name = try buffGetValidName(
        allocator.*,
        &buff,
        &db,
        folder,
        cetech1.assetdb.FooAsset.type_hash,
        "NewFolder",
    );

    try _assetdb.createNewFolder(&db, folder, name);
}

fn createAssetFolderMenuItem() [*]const u8 {
    return Icons.FA_FOLDER ++ "  " ++ "Folder";
}

// Cdb
fn cdbCreateTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, _cdb);

    // FOLDER
    try cetech1.assetdb.FolderType.addAspect(
        &db,
        editor.UiTreeAspect,
        _g.folder_tree_aspect,
    );

    // ASSET
    try cetech1.assetdb.AssetType.addAspect(
        &db,
        editor.UiTreeAspect,
        _g.asset_tree_aspect,
    );
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
    _uuid = apidb.getZigApi(cetech1.uuid.UuidAPI).?;
    _editortree = apidb.getZigApi(editor.TreeAPI).?;
    _tags = apidb.getZigApi(editor.AssetTagsApi).?;
    _inspector = apidb.getZigApi(editor.InspectorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.asset_browser_tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, ASSET_BROWSER_NAME, .{});
    _g.asset_browser_tab_vt.* = foo_tab;

    _g.asset_tree_aspect = try apidb.globalVar(editor.UiTreeAspect, MODULE_NAME, ASSET_TREE_ASPECT_NAME, .{});
    _g.asset_tree_aspect.* = asset_ui_tree_aspect;

    _g.folder_tree_aspect = try apidb.globalVar(editor.UiTreeAspect, MODULE_NAME, FOLDER_TREE_ASPECT_NAME, .{});
    _g.folder_tree_aspect.* = folder_ui_tree_aspect;

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.EditorTabTypeI, &foo_tab, load);
    try apidb.implOrRemove(editor.UiModalI, &select_asset_uimodal, load);
    try apidb.implOrRemove(editor.CreateAssetI, &create_folder_i, load);

    try apidb.setOrRemoveZigApi(editor.AssetBrowserAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_browser(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
