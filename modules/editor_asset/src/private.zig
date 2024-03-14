const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_asset.zig");

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const assetdb = cetech1.assetdb;
const strid = cetech1.strid;
const TagType = assetdb.TagType;

const editor = @import("editor");
const Icons = cetech1.coreui.Icons;

const editor_inspector = @import("editor_inspector");
const editor_tree = @import("editor_tree");
const editor_obj_buffer = @import("editor_obj_buffer");

const MODULE_NAME = "editor_asset";
pub const std_options = struct {
    pub const logFn = cetech1.log.zigLogFnGen(&_log);
};
const log = std.log.scoped(.editor_asset);

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _uuid: *cetech1.uuid.UuidAPI = undefined;
var _coreui: *cetech1.coreui.CoreUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _assetdb: *assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _editor_inspector: *editor_inspector.InspectorAPI = undefined;
var _editor_tree: *editor_tree.TreeAPI = undefined;
var _editor_obj_buffer: *editor_obj_buffer.EditorObjBufferAPI = undefined;

// Global state
const G = struct {
    asset_tree_aspect: *editor_tree.UiTreeAspect = undefined,
};
var _g: *G = undefined;

var rename_context_menu_i = editor.ObjContextMenuI.implement(struct {
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
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (contexts.id != editor.Contexts.edit.id) return false;

        if (filter) |f| {
            return _coreui.uiFilterPass(allocator, f, "Rename", false) != null;
        }

        if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
            defer allocator.free(selected_objs);
            for (selected_objs) |obj| {
                if (!assetdb.AssetType.isSameType(obj)) return false;
                if (_assetdb.getObjForAsset(obj)) |o| if (assetdb.ProjectType.isSameType(o)) return false;
                if (_assetdb.isRootFolder(&db, obj)) return false;
            }
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        tab: *editor.TabO,
        context: strid.StrId64,
        selection: cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cdb.ObjId,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;
        _ = in_set_obj;

        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (_coreui.beginMenu(allocator, coreui.Icons.Rename ++ "  " ++ "Rename" ++ "###Rename", true, filter)) {
            defer _coreui.endMenu();

            if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
                defer allocator.free(selected_objs);
                var buff: [128:0]u8 = undefined;

                for (selected_objs) |obj| {
                    if (!assetdb.AssetType.isSameType(obj)) continue;

                    _coreui.pushObjUUID(obj);
                    _coreui.pushIntId(prop_idx orelse 0);
                    defer _coreui.popId();
                    defer _coreui.popId();

                    const asset_label = _editor.buffFormatObjLabel(allocator, &buff, &db, obj, false) orelse "Not implemented";
                    const asset_color = _editor.getAssetColor(&db, obj);
                    _ = _editor_inspector.uiPropLabel(allocator, asset_label, asset_color, .{});

                    _editor_inspector.uiPropInputRaw(&db, obj, assetdb.AssetType.propIdx(.Name)) catch undefined;
                }
            }
        }
    }
});

fn moveToFolderMenuInner(allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId, folder: cdb.ObjId, is_root: bool) !void {
    const name = assetdb.AssetType.readStr(db, db.readObj(folder).?, .Name);
    const folder_obj = _assetdb.getObjForAsset(folder).?;
    var buff: [256:0]u8 = undefined;
    const label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Folder ++ "  " ++ "{s}" ++ "###{s}", .{ name orelse "ROOT", name orelse "ROOT" });

    var open = true;
    if (!is_root) {
        const asset_color = _editor.getAssetColor(db, folder);
        _coreui.pushStyleColor4f(.{ .idx = .text, .c = asset_color });
        open = _coreui.beginMenu(allocator, label, true, null);
        _coreui.popStyleColor(.{});
    }

    if (open) {
        defer if (!is_root) _coreui.endMenu();

        const set = try db.getReferencerSet(folder_obj, allocator);
        defer allocator.free(set);

        var any_folder = false;
        for (set) |ref_obj| {
            if (!_assetdb.isAssetFolder(ref_obj)) continue;
            if (_coreui.isSelected(db, selection, ref_obj)) continue;

            any_folder = true;
            try moveToFolderMenuInner(allocator, db, selection, ref_obj, false);
        }

        if (any_folder) {
            _coreui.separator();
        }

        if (_coreui.menuItem(allocator, coreui.Icons.MoveHere ++ " " ++ "Move here" ++ "###MoveHere", .{}, null)) {
            if (_coreui.getSelected(allocator, db, selection)) |selected_objs| {
                defer allocator.free(selected_objs);
                for (selected_objs) |obj| {
                    if (assetdb.AssetType.isSameType(obj)) {
                        const w = db.writeObj(obj).?;
                        try assetdb.AssetType.setRef(db, w, .Folder, folder_obj);
                        try db.writeCommit(w);
                    }
                }
            }
        }
    }
}

fn moveToFolderMenu(allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId, filter: ?[:0]const u8) !void {
    if (_coreui.beginMenu(allocator, coreui.Icons.Folder ++ "  " ++ "Move" ++ "###MoveAsset", true, filter)) {
        defer _coreui.endMenu();
        try moveToFolderMenuInner(allocator, db, selection, _assetdb.getRootFolder(), true);
    }
}

var move_to_context_menu_i = editor.ObjContextMenuI.implement(struct {
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
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (contexts.id != editor.Contexts.edit.id) return false;
        if (filter) |f| {
            return _coreui.uiFilterPass(allocator, f, "Move", false) != null;
        }

        if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
            defer allocator.free(selected_objs);
            for (selected_objs) |obj| {
                if (!assetdb.AssetType.isSameType(obj)) return false;
                if (_assetdb.getObjForAsset(obj)) |o| if (assetdb.ProjectType.isSameType(o)) return false;
                if (_assetdb.isRootFolder(&db, obj)) return false;
            }
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        tab: *editor.TabO,
        context: strid.StrId64,
        selection: cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cdb.ObjId,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        moveToFolderMenu(allocator, &db, selection, filter) catch undefined;
    }
});

// Asset cntx menu
// TODO: split this shit
var asset_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        dbc: *cetech1.cdb.Db,
        tab: *editor.TabO,
        context: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;

        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
            defer allocator.free(selected_objs);
            for (selected_objs) |obj| {
                if (!assetdb.AssetType.isSameType(obj)) return false;
                if (context.id != editor.Contexts.delete.id) continue;
                if (_assetdb.getObjForAsset(obj)) |o| if (assetdb.ProjectType.isSameType(o)) return false;
            }
        }

        var valid = true;
        if (filter) |f| {
            valid = false;

            switch (context.id) {
                editor.Contexts.delete.id => {
                    if (_coreui.uiFilterPass(allocator, f, "Revive asset", false) != null) return true;
                    if (_coreui.uiFilterPass(allocator, f, "Delete asset", false) != null) return true;
                },
                editor.Contexts.debug.id => {
                    if (_coreui.uiFilterPass(allocator, f, "Copy to clipboard", false) != null) return true;
                    if (_coreui.uiFilterPass(allocator, f, "Force save", false) != null) return true;
                },
                else => {},
            }
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        tab: *editor.TabO,
        context: strid.StrId64,
        selection: cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cdb.ObjId,
        filter: ?[:0]const u8,
    ) !void {
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;

        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        const obj = _coreui.getFirstSelected(allocator, &db, selection);

        var is_root_folder = false;
        const is_folder = _assetdb.isAssetFolder(obj);
        if (is_folder) {
            const ref = assetdb.AssetType.readRef(&db, db.readObj(obj).?, .Folder);
            is_root_folder = ref == null;
        }

        switch (context.id) {
            editor.Contexts.delete.id => {
                if (_assetdb.isToDeleted(obj)) {
                    if (_coreui.menuItem(allocator, coreui.Icons.Revive ++ " " ++ "Revive asset" ++ "###ReviveAsset", .{ .enabled = !is_root_folder }, filter)) {
                        _assetdb.reviveDeleted(obj);
                    }
                } else {
                    if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete asset" ++ "###DeleteAsset", .{ .enabled = !is_root_folder }, filter)) {
                        if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
                            defer allocator.free(selected_objs);
                            for (selected_objs) |selected_obj| {
                                if (_assetdb.isAssetFolder(selected_obj)) {
                                    _assetdb.deleteFolder(&db, selected_obj) catch undefined;
                                } else {
                                    _assetdb.deleteAsset(&db, selected_obj) catch undefined;
                                }
                            }
                        }
                    }
                }
            },
            editor.Contexts.debug.id => {
                if (_coreui.beginMenu(allocator, coreui.Icons.CopyToClipboard ++ " " ++ "Copy to clipboard", true, filter)) {
                    defer _coreui.endMenu();

                    if (_coreui.menuItem(allocator, "Asset UUID", .{}, filter)) {
                        const uuid = _assetdb.getUuid(obj).?;
                        var buff: [128]u8 = undefined;
                        const uuid_str = std.fmt.bufPrintZ(&buff, "{s}", .{uuid}) catch undefined;
                        _coreui.setClipboardText(uuid_str);
                    }
                }

                if (_coreui.menuItem(allocator, coreui.Icons.Save ++ " " ++ "Force save", .{}, filter)) {
                    if (_coreui.getSelected(allocator, &db, selection)) |selected_objs| {
                        defer allocator.free(selected_objs);
                        for (selected_objs) |selected_obj| {
                            _assetdb.saveAsset(allocator, selected_obj) catch undefined;
                        }
                    }
                }
            },
            else => {},
        }
    }
});

fn getFolderForSelectedObj(db: *cdb.CdbDb, selected_obj: cdb.ObjId) ?cdb.ObjId {
    if (_assetdb.isAssetFolder(selected_obj)) return selected_obj;

    var parent_folder: cdb.ObjId = _assetdb.getRootFolder();
    const asset = _assetdb.getAssetForObj(selected_obj) orelse return null;

    if (db.readObj(asset)) |r| {
        parent_folder = assetdb.AssetType.readRef(db, r, .Folder).?;
    }

    return _assetdb.getAssetForObj(parent_folder).?;
}

var create_context_menu_i = editor.ObjContextMenuI.implement(struct {
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
        if (contexts.id != editor.Contexts.create.id) return false;

        if (filter) |f| {
            return _coreui.uiFilterPass(allocator, f, "Asset", false) != null;
        }
        return true;
        // if (filter) |f| {
        //     var it = _apidb.getFirstImpl(editor.CreateAssetI);
        //     while (it) |node| : (it = node.next) {
        //         const iface = cetech1.apidb.ApiDbAPI.toInterface(editor.CreateAssetI, node);
        //         const menu_name = iface.menu_item.?();
        //         var buff: [256:0]u8 = undefined;
        //         const label = std.fmt.bufPrintZ(&buff, "{s}", .{cetech1.fromCstrZ(menu_name)}) catch undefined;
        //         _ = _coreui.uiFilterPass(allocator, f, label, false) orelse continue;
        //         return true;
        //     }
        //     return false;
        // }
        // return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        tab: *editor.TabO,
        context: strid.StrId64,
        selection: cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cdb.ObjId,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (_coreui.beginMenu(allocator, coreui.Icons.AddAsset ++ "  " ++ "Asset" ++ "###AddAsset", true, filter)) {
            defer _coreui.endMenu();

            var it = _apidb.getFirstImpl(editor.CreateAssetI);
            while (it) |node| : (it = node.next) {
                const iface = cetech1.apidb.ApiDbAPI.toInterface(editor.CreateAssetI, node);
                const menu_name = iface.menu_item.?();
                var buff: [256:0]u8 = undefined;
                const type_name = db.getTypeName(iface.cdb_type).?;
                const label = try std.fmt.bufPrintZ(&buff, "{s}###{s}", .{ cetech1.fromCstrZ(menu_name), type_name });

                if (_coreui.menuItem(allocator, label, .{}, filter)) {
                    var parent_folder = getFolderForSelectedObj(&db, _coreui.getFirstSelected(allocator, &db, selection)) orelse _assetdb.getRootFolder();
                    if (!parent_folder.isEmpty()) {
                        iface.create.?(&allocator, db.db, parent_folder);
                    }
                }
            }
        }
    }
});

// Create folder
var create_folder_i = editor.CreateAssetI.implement(
    assetdb.FolderType.type_hash,
    struct {
        pub fn create(
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

        pub fn menuItem() ![*]const u8 {
            return coreui.Icons.Folder ++ "  " ++ "Folder";
        }
    },
);

// Asset visual aspect
var asset_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiTooltip(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) !void {
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (_assetdb.getUuid(obj)) |uuuid| {
            var buff: [256:0]u8 = undefined;
            const uuid_str = try std.fmt.bufPrintZ(&buff, "Asset UUID: {s}", .{uuuid});
            _coreui.textUnformatted(uuid_str);
        }

        const asset_obj = _assetdb.getObjForAsset(obj).?;

        if (db.getAspect(editor.UiVisualAspect, asset_obj.type_hash)) |aspect| {
            if (aspect.ui_tooltip) |tooltip| {
                _coreui.separator();
                tooltip(&allocator, db.db, asset_obj);
            }
        }
    }

    pub fn uiName(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);
        const obj_r = db.readObj(obj).?;
        const asset_obj = assetdb.AssetType.readSubObj(&db, obj_r, .Object).?;

        if (assetdb.FolderType.isSameType(asset_obj)) {
            const asset_name = assetdb.AssetType.readStr(&db, obj_r, .Name) orelse "ROOT";
            return std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{
                    asset_name,
                },
            ) catch "";
        } else {
            const asset_name = assetdb.AssetType.readStr(&db, obj_r, .Name) orelse "No NAME =()";
            const type_name = db.getTypeName(asset_obj.type_hash).?;
            return std.fmt.allocPrintZ(
                allocator,
                "{s}.{s}",
                .{
                    asset_name,
                    type_name,
                },
            ) catch "";
        }
    }

    pub fn uiIcons(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);
        const obj_r = db.readObj(obj).?;
        const asset_obj = assetdb.AssetType.readSubObj(&db, obj_r, .Object).?;
        const ui_visual_aspect = db.getAspect(editor.UiVisualAspect, asset_obj.type_hash);
        var ui_icon: ?[:0]const u8 = null;
        if (ui_visual_aspect) |aspect| {
            if (aspect.ui_icons) |icons| {
                ui_icon = std.mem.span(icons(&allocator, &db, asset_obj));
            }
        }
        defer {
            if (ui_icon) |i| {
                allocator.free(i);
            }
        }

        const is_modified = _assetdb.isAssetModified(obj);
        const is_deleted = _assetdb.isToDeleted(obj);

        return try std.fmt.allocPrintZ(
            allocator,
            "{s} {s}{s}",
            .{
                if (ui_icon) |i| i else cetech1.coreui.Icons.Asset,
                if (is_modified) cetech1.coreui.CoreIcons.FA_STAR_OF_LIFE else "",
                if (is_deleted) " " ++ cetech1.coreui.Icons.Deleted else "",
            },
        );
    }

    pub fn uiColor(
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) ![4]f32 {
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);
        return _editor.getAssetColor(&db, obj);
    }
});

// Folder visual aspect
var folder_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiColor(
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) ![4]f32 {
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);
        const r = assetdb.FolderType.read(&db, obj).?;
        if (assetdb.FolderType.readSubObj(&db, r, .Color)) |color_obj| {
            return cdb_types.color4fToSlice(&db, color_obj);
        }

        return .{ 1.0, 1.0, 1.0, 1.0 };
    }

    pub fn uiIcons(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = dbc;
        _ = obj;

        return try std.fmt.allocPrintZ(
            allocator,
            "{s}",
            .{cetech1.coreui.Icons.Folder},
        );
    }
});

// Asset tree aspect
fn lessThanAsset(db: *cdb.CdbDb, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const l_name = db.readStr(db.readObj(lhs).?, assetdb.AssetType.propIdx(.Name)) orelse return false;
    const r_name = db.readStr(db.readObj(rhs).?, assetdb.AssetType.propIdx(.Name)) orelse return false;
    return std.ascii.lessThanIgnoreCase(l_name, r_name);
}

var asset_ui_tree_aspect = editor_tree.UiTreeAspect.implement(struct {
    pub fn uiTree(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        tab: *editor.TabO,
        contexts: []const strid.StrId64,
        obj: cdb.ObjId,
        selection: cdb.ObjId,
        args: editor_tree.CdbTreeViewArgs,
    ) !editor_tree.SelectInTreeResult {
        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        var result: editor_tree.SelectInTreeResult = .{ .is_changed = false };

        const obj_r = db.readObj(obj) orelse return result;
        const asset_obj = assetdb.AssetType.readSubObj(&db, obj_r, .Object).?;

        const is_folder = _assetdb.isAssetFolder(obj);
        const is_root_folder = assetdb.AssetType.readRef(&db, obj_r, .Folder) == null;

        if (!args.ignored_object.isEmpty() and args.ignored_object.eq(asset_obj)) {
            return result;
        }

        if (!args.expand_object and args.only_types.id != 0 and asset_obj.type_hash.id != args.only_types.id) {
            return result;
        }

        const expand = is_folder or (args.expand_object and db.hasTypeSet(asset_obj.type_hash));

        const open = _editor_tree.cdbObjTreeNode(
            allocator,
            &db,
            tab,
            contexts,
            selection,
            obj,
            is_root_folder or args.opened_obj.eq(obj),
            false,
            !expand,
            args,
        );

        if (_coreui.isItemHovered(.{}) and _coreui.isMouseDoubleClicked(.left)) {
            try _editor_obj_buffer.addToFirst(allocator, &db, obj);
        }

        if (_coreui.isItemActivated() or (_coreui.isItemHovered(.{}) and _coreui.isMouseClicked(.right) and _coreui.selectedCount(allocator, &db, selection) == 1)) {
            try _coreui.handleSelection(allocator, &db, selection, obj, args.multiselect);
        }

        try formatTagsToLabel(allocator, &db, obj, assetdb.AssetType.propIdx(.Tags));

        if (open) {
            defer _coreui.treePop();

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

                std.sort.insertion(cdb.ObjId, folders.items, &db, lessThanAsset);
                std.sort.insertion(cdb.ObjId, assets.items, &db, lessThanAsset);

                for (folders.items) |folder| {
                    const r = try _editor_tree.cdbTreeView(allocator, &db, tab, contexts, folder, selection, args);
                    if (r.isChanged()) result = r;
                }
                for (assets.items) |asset| {
                    const r = try _editor_tree.cdbTreeView(allocator, &db, tab, contexts, asset, selection, args);
                    if (r.isChanged()) result = r;
                }
            } else {
                if (args.expand_object) {
                    const r = try _editor_tree.cdbTreeView(allocator, &db, tab, contexts, asset_obj, selection, args);
                    if (r.isChanged()) result = r;
                }
            }
        }

        return result;
    }

    pub fn uiDropObj(
        allocator: std.mem.Allocator,
        dbc: *cdb.Db,
        tab: *editor.TabO,
        obj: cdb.ObjId,
        drop_obj: cdb.ObjId,
    ) !void {
        _ = allocator;
        _ = tab;

        var db = cdb.CdbDb.fromDbT(dbc, _cdb);

        if (!drop_obj.eq(obj) and assetdb.AssetType.isSameType(drop_obj)) {
            const obj_r = db.readObj(obj) orelse return;

            const is_folder = _assetdb.isAssetFolder(obj);
            if (is_folder) {
                const asset_obj = assetdb.AssetType.readSubObj(&db, obj_r, .Object).?;

                const drag_obj_folder = assetdb.AssetType.readRef(&db, db.readObj(drop_obj).?, .Folder).?;
                if (!drag_obj_folder.eq(asset_obj)) {
                    const w = db.writeObj(drop_obj).?;
                    try assetdb.AssetType.setRef(&db, w, .Folder, asset_obj);
                    try db.writeCommit(w);
                }
            } else {
                const folder_obj = assetdb.AssetType.readRef(&db, obj_r, .Folder).?;
                const drag_obj_folder = assetdb.AssetType.readRef(&db, db.readObj(drop_obj).?, .Folder).?;
                if (!drag_obj_folder.eq(folder_obj)) {
                    const w = db.writeObj(drop_obj).?;
                    try assetdb.AssetType.setRef(&db, w, .Folder, folder_obj);
                    try db.writeCommit(w);
                }
            }
        }
    }
});

fn formatTagsToLabel(allocator: std.mem.Allocator, db: *cdb.CdbDb, obj: cdb.ObjId, tag_prop_idx: u32) !void {
    const obj_r = db.readObj(obj) orelse return;

    if (db.readRefSet(obj_r, tag_prop_idx, allocator)) |tags| {
        var begin_pos: ?f32 = null;
        for (tags) |tag| {
            const tag_r = db.readObj(tag) orelse continue;

            var tag_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
            if (_editor.isColorsEnabled()) {
                if (assetdb.TagType.readSubObj(db, tag_r, .Color)) |c| {
                    tag_color = cetech1.cdb_types.color4fToSlice(db, c);
                }
            }
            const tag_name = assetdb.TagType.readStr(db, tag_r, .Name) orelse "No name =/";

            _coreui.pushObjUUID(tag);
            defer _coreui.popId();

            const max_region = _coreui.getContentRegionMax();

            const begin_offset = _coreui.getFontSize() / 2;
            const item_size = _coreui.getFontSize() / 3;
            if (begin_pos == null) {
                _coreui.sameLine(.{ .offset_from_start_x = max_region[0] - begin_offset - (item_size * @as(f32, @floatFromInt(tags.len))) });
            } else {
                begin_pos.? += item_size;
                _coreui.sameLine(.{ .offset_from_start_x = begin_pos.? });
            }

            var tag_buf: [128:0]u8 = undefined;
            const tag_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag, .{});
            if (begin_pos == null) {
                begin_pos = _coreui.getCursorPosX();
            }

            _coreui.textUnformattedColored(tag_color, tag_lbl);

            if (_coreui.isItemHovered(.{})) {
                _coreui.beginTooltip();
                defer _coreui.endTooltip();

                const name_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag ++ " " ++ "{s}", .{tag_name});
                _coreui.textUnformatted(name_lbl);

                const tag_asset = _assetdb.getAssetForObj(tag).?;
                const desription = assetdb.AssetType.readStr(db, db.readObj(tag_asset).?, .Description);
                if (desription) |d| {
                    _coreui.textUnformatted(d);
                }
            }
        }
    }
}

// Test
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = _coreui.registerTest(
            "ContextMenu",
            "should_create_new_folder",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_empty");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###project.ct_project", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###AddAsset/###AddAsset/###ct_folder");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###NewFolder", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_create_new_tag",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_empty");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###project.ct_project", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###AddAsset/###AddAsset/###ct_tag");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###NewTag.ct_tag", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_rename_asset",
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

                    ctx.menuAction(_coreui, .Open, "###ObjContextMenu/###Rename");
                    ctx.itemInputStrValue(_coreui, "**/###edit", "new_foo");

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###new_foo.ct_foo_asset", .{}, null);
                }
            },
        );

        // TODO:
        _ = _coreui.registerTest(
            "ContextMenu",
            "should_rename_multiple_asset",
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

                    ctx.keyDown(_coreui, .mod_super);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###core", .{}, null);
                    ctx.keyUp(_coreui, .mod_super);

                    ctx.menuAction(_coreui, .Hover, "###ObjContextMenu/###Rename");

                    ctx.itemInputStrValue(_coreui, "**/018b5846-c2d5-7b88-95f9-a7538a00e76b/$$0/###edit", "new_foo");
                    ctx.itemInputStrValue(_coreui, "**/018e0f87-9fc7-7fa5-afc8-4814fd500014/$$0/###edit", "new_core");

                    const db = _kernel.getDb();

                    {
                        const foo = _assetdb.getObjId(_uuid.fromStr("018b5846-c2d5-7b88-95f9-a7538a00e76b").?).?;
                        const name = assetdb.AssetType.readStr(db, db.readObj(foo).?, .Name);

                        std.testing.expect(name != null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return;
                        };
                        std.testing.expectEqualStrings(name.?, "new_foo") catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return;
                        };
                    }

                    {
                        const core = _assetdb.getObjId(_uuid.fromStr("018e0f87-9fc7-7fa5-afc8-4814fd500014").?).?;
                        const name = assetdb.AssetType.readStr(db, db.readObj(core).?, .Name);

                        std.testing.expect(name != null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return;
                        };
                        std.testing.expectEqualStrings(name.?, "new_core") catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return;
                        };
                    }

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###new_foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###new_core", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_move_asset_by_ctx_menu",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_a.ct_foo_asset", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###MoveAsset/###folder_a/###MoveHere");

                    //TODO: Check moved
                    //ctx.itemAction(_coreui, .Open, "**/###ROOT/###folder_a/###asset_a.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_move_folder_by_ctx_menu",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_b", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###MoveAsset/###folder_a/###MoveHere");

                    //TODO: Check moved
                    //ctx.itemAction(_coreui, .Open, "**/###ROOT/###folder_a/###asset_a.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_delete_and_revive_folder_by_ctx_menu",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e48d4-df07-7602-9068-55d32eb8bb1d").?).?;
                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_b", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###DeleteAsset");

                    std.testing.expect(_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_b", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###ReviveAsset");

                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_delete_and_revive_asset_by_ctx_menu",
            @src(),
            struct {
                pub fn gui(ctx: *coreui.TestContext) !void {
                    _ = ctx;
                }

                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e48d3-3837-705a-979f-94f28d478284").?).?;
                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_b.ct_foo_asset", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###DeleteAsset");

                    std.testing.expect(_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_b.ct_foo_asset", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###ReviveAsset");

                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return;
                    };
                }
            },
        );
    }
});

// CDB types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: *cdb.Db) !void {
        var db = cdb.CdbDb.fromDbT(db_, _cdb);

        // ASSET
        try assetdb.AssetType.addAspect(
            &db,
            editor_tree.UiTreeAspect,
            _g.asset_tree_aspect,
        );

        try assetdb.AssetType.addAspect(&db, editor.UiVisualAspect, &asset_visual_aspect);
        try assetdb.FolderType.addAspect(&db, editor.UiVisualAspect, &folder_visual_aspect);
    }
});

const ASSET_TREE_ASPECT_NAME = "ct_asset_tree_aspect";
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
    _uuid = apidb.getZigApi(cetech1.uuid.UuidAPI).?;
    _assetdb = apidb.getZigApi(assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;
    _editor_inspector = apidb.getZigApi(editor_inspector.InspectorAPI).?;
    _editor_tree = apidb.getZigApi(editor_tree.TreeAPI).?;
    _editor_obj_buffer = apidb.getZigApi(editor_obj_buffer.EditorObjBufferAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    try apidb.implOrRemove(cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(editor.ObjContextMenuI, &move_to_context_menu_i, load);
    try apidb.implOrRemove(editor.ObjContextMenuI, &rename_context_menu_i, load);
    try apidb.implOrRemove(editor.ObjContextMenuI, &asset_context_menu_i, load);
    try apidb.implOrRemove(editor.ObjContextMenuI, &create_context_menu_i, load);
    try apidb.implOrRemove(editor.CreateAssetI, &create_folder_i, load);
    try apidb.implOrRemove(coreui.RegisterTestsI, &register_tests_i, load);

    _g.asset_tree_aspect = try apidb.globalVar(editor_tree.UiTreeAspect, MODULE_NAME, ASSET_TREE_ASPECT_NAME, .{});
    _g.asset_tree_aspect.* = asset_ui_tree_aspect;

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
