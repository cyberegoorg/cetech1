const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;

const public = @import("editor_asset_browser.zig");

const editor = @import("editor");
const editor_obj_buffer = @import("editor_obj_buffer");
const editor_tree = @import("editor_tree");
const editor_tags = @import("editor_tags");

const Icons = cetech1.editorui.CoreIcons;

const MODULE_NAME = "editor_asset_browser";
const ASSET_BROWSER_NAME = "ct_editor_asset_browser_tab";

const ASSET_TREE_ASPECT_NAME = "ct_asset_tree_aspect";
const FOLDER_TREE_ASPECT_NAME = "ct_folder_tree_aspect";
const FOLDER_CREATE_ASSET_I = "ct_assetbrowser_create_asset_folder_i";

const ASSET_BROWSER_ICON = Icons.FA_FOLDER_TREE;
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _editortree: *editor_tree.TreeAPI = undefined;
var _assetdb: *assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *cetech1.uuid.UuidAPI = undefined;
var _tags: *editor_tags.EditorTagsApi = undefined;
var _editor_obj_buffer: *editor_obj_buffer.EditorObjBufferAPI = undefined;

const G = struct {
    tab_vt: *editor.EditorTabTypeI = undefined,
    asset_tree_aspect: *editor_tree.UiTreeAspect = undefined,
    folder_create_asset_i: *editor.CreateAssetI = undefined,
};
var _g: *G = undefined;

var api = public.AssetBrowserAPI{
    .selectObjFromBrowserMenu = selectObjFromBrowserMenu,
};

fn selectObjFromBrowserMenu(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, ignored_obj: cetech1.cdb.ObjId, allowed_type: cetech1.strid.StrId32) ?cetech1.cdb.ObjId {
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
                label = std.fmt.bufPrintZ(&label_buff, "Select from browser {d} - {s}", .{ tab.tabid, path }) catch return null;
            } else {
                label = std.fmt.bufPrintZ(&label_buff, "Select from browser {d}", .{tab.tabid}) catch return null;
            }
        } else {
            label = std.fmt.bufPrintZ(&label_buff, "Select from browser {d}", .{tab.tabid}) catch return null;
        }
        valid = selected_n == 1 and !real_obj.eq(ignored_obj) and real_obj.type_hash.id == allowed_type.id;

        if (_editorui.menuItem(label, .{ .enabled = valid })) {
            return real_obj;
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
fn tabCreate(dbc: *cdb.Db) ?*editor.EditorTabI {
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
                        assetUiTree(
                            allocator,
                            db,
                            asset,
                            selectection,
                            true,
                            .{ .expand_object = args.expand_object, .multiselect = args.multiselect, .opened_obj = args.opened_obj },
                            null,
                        ) catch undefined;
                    }
                }
            } else {
                const assets_filtered = _assetdb.filerAsset(allocator, if (args.filter) |fil| std.mem.sliceTo(fil, 0) else "", tags_filter) catch undefined;
                defer allocator.free(assets_filtered);

                std.sort.insertion(assetdb.FilteredAsset, assets_filtered, {}, assetdb.FilteredAsset.lessThan);
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
            //assetUiTreeAsspect(allocator: std.mem.Allocator, dbc: *cdb.Db, obj: cdb.ObjId, selectection: cdb.ObjId, args: editor_tree.CdbTreeViewArgs)
            assetUiTreeAsspect(allocator, db.db, root_folder, selectection, new_args) catch undefined;
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
        .{ .filter = if (tab_o.filter == null) null else tab_o.filter.?.ptr, .multiselect = true, .expand_object = false, .opened_obj = tab_o.opened_obj },
    ) catch undefined;
    tab_o.filter = r.filter;
}

fn tabFocused(inst: *editor.TabO) void {
    const tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));
    _ = tab_o;
}
//

fn formatTagsToLabel(allocator: std.mem.Allocator, db: *cdb.CdbDb, obj: cdb.ObjId, tag_prop_idx: u32) !void {
    const obj_r = db.readObj(obj) orelse return;

    if (db.readRefSet(obj_r, tag_prop_idx, allocator)) |tags| {
        var begin_pos: ?f32 = null;
        for (tags) |tag| {
            const tag_r = db.readObj(tag) orelse continue;

            var tag_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
            if (assetdb.TagType.readSubObj(db, tag_r, .Color)) |c| {
                tag_color = cetech1.cdb_types.color4fToSlice(db, c);
            }
            const tag_name = assetdb.TagType.readStr(db, tag_r, .Name) orelse "No name =/";

            _editorui.pushObjId(tag);
            defer _editorui.popId();

            if (begin_pos == null) {
                _editorui.sameLine(.{ .offset_from_start_x = 0 });
            } else {
                begin_pos.? += 6.0;
                _editorui.sameLine(.{ .offset_from_start_x = begin_pos.? });
            }

            var tag_buf: [128:0]u8 = undefined;
            const tag_lbl = try std.fmt.bufPrintZ(&tag_buf, editorui.Icons.Tag, .{});
            if (begin_pos == null) {
                begin_pos = _editorui.getCursorPosX();
            }

            _editorui.textUnformattedColored(tag_color, tag_lbl);

            if (_editorui.isItemHovered(.{})) {
                _editorui.beginTooltip();
                defer _editorui.endTooltip();

                const name_lbl = try std.fmt.bufPrintZ(&tag_buf, editorui.Icons.Tag ++ " " ++ "{s}", .{tag_name});
                _editorui.textUnformatted(name_lbl);

                const tag_asset = _assetdb.getAssetForObj(tag).?;
                const desription = assetdb.AssetType.readStr(db, db.readObj(tag_asset).?, .Description);
                if (desription) |d| {
                    _editorui.textUnformatted(d);
                }
            }
        }
    }
}

// Folder aspect
fn lessThanAsset(db: *cdb.CdbDb, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const l_name = db.readStr(db.readObj(lhs).?, assetdb.AssetType.propIdx(.Name)) orelse return false;
    const r_name = db.readStr(db.readObj(rhs).?, assetdb.AssetType.propIdx(.Name)) orelse return false;
    return std.ascii.lessThanIgnoreCase(l_name, r_name);
}

// Asset tree aspect
var asset_ui_tree_aspect = editor_tree.UiTreeAspect.implement(assetUiTreeAsspect);
fn assetUiTreeAsspect(
    allocator: std.mem.Allocator,
    dbc: *cdb.Db,
    obj: cdb.ObjId,
    selectection: cdb.ObjId,
    args: editor_tree.CdbTreeViewArgs,
) !void {
    var db = cdb.CdbDb.fromDbT(dbc, _cdb);
    try assetUiTree(allocator, &db, obj, selectection, false, args, null);
}

fn assetUiTree(
    allocator: std.mem.Allocator,
    db: *cdb.CdbDb,
    obj: cdb.ObjId,
    selection: cdb.ObjId,
    path_label: bool,
    args: editor_tree.CdbTreeViewArgs,
    score: ?f64,
) !void {
    _ = score;
    _ = path_label;

    var buff: [256:0]u8 = undefined;

    const obj_r = db.readObj(obj) orelse return;
    const asset_obj = assetdb.AssetType.readSubObj(db, obj_r, .Object).?;

    const is_folder = _assetdb.isAssetFolder(obj);
    const is_root_folder = assetdb.AssetType.readRef(db, obj_r, .Folder) == null;

    if (!args.ignored_object.isEmpty() and args.ignored_object.eq(asset_obj)) {
        return;
    }

    if (!args.expand_object and args.only_types.id != 0 and asset_obj.type_hash.id != args.only_types.id) {
        return;
    }

    // if (score) |s| {
    //     const scr: f32 = @min(@as(f32, @floatCast(s)), 1.0);
    //     const inv_scr: f32 = 1 - scr;
    //     const color: f32 = if (inv_scr == scr) 1.0 else @max(0.7, 1.0 * inv_scr);
    //     _editorui.pushStyleColor4f(.{ .idx = .text, .c = .{ color, color, color, 1.0 } });
    // }

    const expand = is_folder or (args.expand_object and db.hasTypeSet(obj.type_hash));

    const open = _editortree.cdbObjTreeNode(
        allocator,
        db,
        obj,
        is_root_folder or args.opened_obj.eq(obj),
        false,
        _editorui.isSelected(db, selection, obj),
        !expand,
        args,
    );

    if (_editorui.beginDragDropTarget()) {
        defer _editorui.endDragDropTarget();

        if (_editorui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
            const drag_obj: cdb.ObjId = std.mem.bytesToValue(cdb.ObjId, payload.data);
            if (!drag_obj.eq(obj) and assetdb.AssetType.isSameType(drag_obj)) {
                if (is_folder) {
                    const drag_obj_folder = assetdb.AssetType.readRef(db, db.readObj(drag_obj).?, .Folder).?;
                    if (!drag_obj_folder.eq(asset_obj)) {
                        const w = db.writeObj(drag_obj).?;
                        try assetdb.AssetType.setRef(db, w, .Folder, asset_obj);
                        try db.writeCommit(w);
                    }
                } else {
                    const folder_obj = assetdb.AssetType.readRef(db, obj_r, .Folder).?;
                    const drag_obj_folder = assetdb.AssetType.readRef(db, db.readObj(drag_obj).?, .Folder).?;
                    if (!drag_obj_folder.eq(folder_obj)) {
                        const w = db.writeObj(drag_obj).?;
                        try assetdb.AssetType.setRef(db, w, .Folder, folder_obj);
                        try db.writeCommit(w);
                    }
                }
            }
        }
    }

    if (_editorui.beginDragDropSource(.{})) {
        defer _editorui.endDragDropSource();

        const drop_open = _editortree.cdbObjTreeNode(allocator, db, obj, false, false, _editorui.isSelected(db, selection, obj), !args.expand_object, args);

        if (_editorui.selectedCount(allocator, db, selection) == 1) {
            _ = _editorui.setDragDropPayload("obj", &std.mem.toBytes(obj), .once);
        } else {
            _ = _editorui.setDragDropPayload("objs", &std.mem.toBytes(selection), .once);
        }
        if (drop_open) {
            _editortree.cdbTreePop();
        }
    }

    if (_editorui.isItemHovered(.{}) and _editorui.isMouseDoubleClicked(.left)) {
        try _editor_obj_buffer.addToFirst(allocator, db, obj);
    }

    if (_editorui.isItemActivated() or (_editorui.isItemHovered(.{}) and _editorui.isMouseClicked(.right) and _editorui.selectedCount(allocator, db, selection) == 1)) {
        try _editorui.handleSelection(allocator, db, selection, obj, args.multiselect);
    }

    if (_editorui.beginPopupContextItem()) {
        defer _editorui.endPopup();
        try selectionContextMenu(allocator, db, selection, obj);
    }

    if (_editorui.isItemHovered(.{})) {
        _editorui.beginTooltip();
        defer _editorui.endTooltip();

        if (_assetdb.getUuid(obj)) |uuid| {
            const uuid_str = try std.fmt.bufPrintZ(&buff, "Asset UUID: {s}", .{uuid});
            _editorui.textUnformatted(uuid_str);
        }
    }

    try formatTagsToLabel(allocator, db, obj, assetdb.AssetType.propIdx(.Tags));

    if (open) {
        defer _editorui.treePop();

        // if (score != null) {
        //     _editorui.popStyleColor(.{});
        // }

        if (is_folder) {
            var folders = std.ArrayList(cdb.ObjId).init(allocator);
            defer folders.deinit();

            var assets = std.ArrayList(cdb.ObjId).init(allocator);
            defer assets.deinit();

            const set = try db.getReferencerSet(asset_obj, allocator);
            defer allocator.free(set);

            for (set) |ref_obj| {
                if (assetdb.AssetType.isSameType(ref_obj)) {
                    if (_assetdb.isAssetFolder(ref_obj)) {
                        try folders.append(ref_obj);
                    } else {
                        try assets.append(ref_obj);
                    }
                }
            }

            std.sort.insertion(cdb.ObjId, folders.items, db, lessThanAsset);
            std.sort.insertion(cdb.ObjId, assets.items, db, lessThanAsset);

            for (folders.items) |folder| {
                try _editortree.cdbTreeView(allocator, db, folder, selection, args);
            }
            for (assets.items) |asset| {
                try _editortree.cdbTreeView(allocator, db, asset, selection, args);
            }
        } else {
            if (args.expand_object) {
                try _editortree.cdbTreeView(allocator, db, asset_obj, selection, args);
            }
        }
    }
}

fn getFolderForSelectedObj(db: *cdb.CdbDb, selected_obj: cdb.ObjId) cdb.ObjId {
    if (_assetdb.isAssetFolder(selected_obj)) return selected_obj;

    var parent_folder: cdb.ObjId = _assetdb.getRootFolder();

    if (db.readObj(_assetdb.getAssetForObj(selected_obj).?)) |r| {
        parent_folder = assetdb.AssetType.readRef(db, r, .Folder).?;
    }

    return _assetdb.getAssetForObj(parent_folder).?;
}

fn moveToFolderMenuInner(allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId, folder: cdb.ObjId) !void {
    const name = assetdb.AssetType.readStr(db, db.readObj(folder).?, .Name);
    const folder_obj = _assetdb.getObjForAsset(folder).?;
    var buff: [256:0]u8 = undefined;
    const label = try std.fmt.bufPrintZ(&buff, editorui.Icons.Folder ++ "  " ++ "{s}", .{name orelse "ROOT"});

    if (_editorui.beginMenu(label, true)) {
        defer _editorui.endMenu();

        const set = try db.getReferencerSet(folder_obj, allocator);
        defer allocator.free(set);

        var any_folder = false;
        for (set) |ref_obj| {
            if (!_assetdb.isAssetFolder(ref_obj)) continue;
            any_folder = true;
            try moveToFolderMenuInner(allocator, db, selection, ref_obj);
        }

        if (any_folder) {
            _editorui.separator();
        }

        if (_editorui.menuItem("Move here", .{})) {
            if (_editorui.getSelected(allocator, db, selection)) |selected_objs| {
                defer allocator.free(selected_objs);
                for (selected_objs) |obj| {
                    const w = db.writeObj(obj).?;

                    if (assetdb.AssetType.isSameType(obj)) {
                        try assetdb.AssetType.setRef(db, w, .Folder, folder_obj);
                    }
                    try db.writeCommit(w);
                }
            }
        }
    }
}

fn moveToFolderMenu(allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId) !void {
    if (_editorui.beginMenu(editorui.Icons.Folder ++ "  " ++ "Move to", true)) {
        defer _editorui.endMenu();
        try moveToFolderMenuInner(allocator, db, selection, _assetdb.getRootFolder());
    }
}

fn selectionContextMenu(allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId, clicked_obj: cdb.ObjId) !void {
    _ = clicked_obj;

    //Add to buffer
    try _editor_obj_buffer.openInBufferMenu(allocator, db, selection);

    _editorui.separator();

    // Open
    _editor.openSelectionInCtxMenu(allocator, db, selection);

    const obj = _editorui.getFirstSelected(allocator, db, selection);

    // Create new asset
    if (_editorui.beginMenu(editorui.Icons.AddFile ++ "  " ++ "New", true)) {
        defer _editorui.endMenu();

        var it = _apidb.getFirstImpl(editor.CreateAssetI);
        while (it) |node| : (it = node.next) {
            const iface = cetech1.apidb.ApiDbAPI.toInterface(editor.CreateAssetI, node);
            const menu_name = iface.menu_item.?();
            var buff: [256:0]u8 = undefined;
            const label = try std.fmt.bufPrintZ(&buff, "{s}", .{cetech1.fromCstrZ(menu_name)});

            if (_editorui.menuItem(label, .{})) {
                var parent_folder = getFolderForSelectedObj(db, _editorui.getFirstSelected(allocator, db, selection));
                if (!parent_folder.isEmpty()) {
                    iface.create.?(&allocator, db.db, parent_folder);
                }
            }
        }
    }

    try moveToFolderMenu(allocator, db, selection);

    _editorui.separator();

    var is_root_folder = false;
    const is_folder = _assetdb.isAssetFolder(obj);
    if (is_folder) {
        const ref = assetdb.AssetType.readRef(db, db.readObj(obj).?, .Folder);
        is_root_folder = ref == null;
    }

    if (_assetdb.isToDeleted(obj)) {
        if (_editorui.menuItem(editorui.Icons.Revive ++ " " ++ "Revive deleted", .{ .enabled = !is_root_folder })) {
            _assetdb.reviveDeleted(obj);
        }
    } else {
        if (_editorui.menuItem(editorui.Icons.Delete ++ " " ++ "Delete", .{ .enabled = !is_root_folder })) {
            if (_editorui.getSelected(allocator, db, selection)) |selected_objs| {
                defer allocator.free(selected_objs);
                for (selected_objs) |selected_obj| {
                    if (_assetdb.isAssetFolder(selected_obj)) {
                        try _assetdb.deleteFolder(db, selected_obj);
                    } else {
                        try _assetdb.deleteAsset(db, selected_obj);
                    }
                }
            }
        }
    }

    _editorui.separator();

    // Copy
    if (_editorui.beginMenu(editorui.Icons.CopyToClipboard ++ " " ++ "Copy to clipboard", true)) {
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
    if (_editorui.beginMenu(editorui.Icons.Debug ++ "  " ++ "Debug", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem(editorui.Icons.Save ++ " " ++ "Force save", .{})) {
            if (_editorui.getSelected(allocator, db, selection)) |selected_objs| {
                defer allocator.free(selected_objs);
                for (selected_objs) |selected_obj| {
                    try _assetdb.saveAsset(allocator, selected_obj);
                }
            }
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

    const selected_count = _editorui.selectedCount(allocator, &tab_o.db, tab_o.selection_obj);

    if (_editorui.beginMenu("Asset", selected_count != 0)) {
        selectionContextMenu(allocator, &tab_o.db, tab_o.selection_obj, cdb.OBJID_ZERO) catch undefined;
        defer _editorui.endMenu();
    }
}

// Create folder
var create_folder_i = editor.CreateAssetI.implement(
    createAssetFolderMenuItem,
    createAssetFolderMenuItemCreate,
);
fn createAssetFolderMenuItemCreate(
    allocator: *const std.mem.Allocator,
    dbc: *cdb.Db,
    folder: cdb.ObjId,
) !void {
    var db = cdb.CdbDb.fromDbT(dbc, _cdb);

    var buff: [256:0]u8 = undefined;
    const name = try _assetdb.buffGetValidName(
        allocator.*,
        &buff,
        &db,
        folder,
        assetdb.FolderType.type_hash,
        "NewFolder",
    );

    try _assetdb.createNewFolder(&db, folder, name);
}

fn createAssetFolderMenuItem() [*]const u8 {
    return Icons.FA_FOLDER ++ "  " ++ "Folder";
}

// Cdb
fn cdbCreateTypes(db_: *cdb.Db) !void {
    var db = cdb.CdbDb.fromDbT(db_, _cdb);

    // // FOLDER
    // try assetdb.FolderType.addAspect(
    //     &db,
    //     editor_tree.UiTreeAspect,
    //     _g.folder_tree_aspect,
    // );

    // ASSET
    try assetdb.AssetType.addAspect(
        &db,
        editor_tree.UiTreeAspect,
        _g.asset_tree_aspect,
    );
}

var create_cdb_types_i = cdb.CreateTypesI.implement(cdbCreateTypes);

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
    _editortree = apidb.getZigApi(editor_tree.TreeAPI).?;
    _tags = apidb.getZigApi(editor_tags.EditorTagsApi).?;
    _editor_obj_buffer = apidb.getZigApi(editor_obj_buffer.EditorObjBufferAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, ASSET_BROWSER_NAME, .{});
    _g.tab_vt.* = foo_tab;

    _g.asset_tree_aspect = try apidb.globalVar(editor_tree.UiTreeAspect, MODULE_NAME, ASSET_TREE_ASPECT_NAME, .{});
    _g.asset_tree_aspect.* = asset_ui_tree_aspect;

    try apidb.implOrRemove(cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.EditorTabTypeI, &foo_tab, load);
    try apidb.implOrRemove(editor.CreateAssetI, &create_folder_i, load);

    try apidb.setOrRemoveZigApi(public.AssetBrowserAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_browser(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
