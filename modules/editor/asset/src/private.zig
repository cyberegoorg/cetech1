const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_asset.zig");

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const assetdb = cetech1.assetdb;

const Tag = assetdb.Tag;

const editor = @import("editor");
const Icons = cetech1.coreui.Icons;

const editor_inspector = @import("editor_inspector");
const editor_tree = @import("editor_tree");
const editor_obj_buffer = @import("editor_obj_buffer");

const module_name = .editor_asset;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _uuid: *const cetech1.uuid.UuidAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _editor_inspector: *const editor_inspector.InspectorAPI = undefined;
var _editor_tree: *const editor_tree.TreeAPI = undefined;
var _editor_obj_buffer: *const editor_obj_buffer.EditorObjBufferAPI = undefined;
var _platform: *const cetech1.platform.PlatformApi = undefined;

// Global state
const G = struct {
    asset_tree_aspect: *editor_tree.UiTreeAspect = undefined,
};
var _g: *G = undefined;

var rename_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (contexts.id != editor.Contexts.edit.id) return false;

        if (filter) |f| {
            return _coreui.uiFilterPass(allocator, f, "Rename", false) != null;
        }

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
            if (_assetdb.isRootFolder(obj.obj)) return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        if (_coreui.beginMenu(allocator, coreui.Icons.Rename ++ "  " ++ "Rename" ++ "###Rename", true, filter)) {
            defer _coreui.endMenu();

            var buff: [128:0]u8 = undefined;

            for (selection) |obj| {
                if (!obj.obj.type_idx.eql(AssetTypeIdx)) continue;

                _coreui.pushObjUUID(obj.obj);
                _coreui.pushIntId(selection[0].prop_idx orelse 0);
                defer _coreui.popId();
                defer _coreui.popId();

                const asset_label = _editor.buffFormatObjLabel(allocator, &buff, obj.obj, false, false) orelse "Not implemented";
                const asset_color = _editor.getAssetColor(obj.obj);
                _ = _editor_inspector.uiPropLabel(allocator, asset_label, asset_color, true, .{});

                _editor_inspector.uiPropInputRaw(obj.obj, assetdb.Asset.propIdx(.Name), .{}) catch undefined;
            }
        }
    }
});

fn moveToFolderMenuInner(allocator: std.mem.Allocator, selection: []const coreui.SelectionItem, folder: cdb.ObjId, is_root: bool) !void {
    const name = assetdb.Asset.readStr(_cdb, _cdb.readObj(folder).?, .Name);
    const folder_obj = _assetdb.getObjForAsset(folder).?;
    var buff: [256:0]u8 = undefined;
    const label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Folder ++ "  " ++ "{s}" ++ "###{s}", .{ name orelse "ROOT", name orelse "ROOT" });

    var open = true;
    if (!is_root) {
        const asset_color = _editor.getAssetColor(folder);
        _coreui.pushStyleColor4f(.{ .idx = .text, .c = asset_color });
        open = _coreui.beginMenu(allocator, label, true, null);
        _coreui.popStyleColor(.{});
    }

    if (open) {
        defer if (!is_root) _coreui.endMenu();

        const set = try _cdb.getReferencerSet(allocator, folder_obj);
        defer allocator.free(set);

        var any_folder = false;
        for (set) |ref_obj| {
            if (!_assetdb.isAssetFolder(ref_obj)) continue;

            const contain = for (selection) |s| {
                if (s.obj.eql(ref_obj)) break true;
            } else false;
            if (contain) continue;

            any_folder = true;
            try moveToFolderMenuInner(allocator, selection, ref_obj, false);
        }

        if (any_folder) {
            _coreui.separator();
        }

        if (_coreui.menuItem(allocator, coreui.Icons.MoveHere ++ "  " ++ "Move here" ++ "###MoveHere", .{}, null)) {
            for (selection) |obj| {
                if (obj.obj.type_idx.eql(AssetTypeIdx)) {
                    const w = assetdb.Asset.write(_cdb, obj.obj).?;
                    try assetdb.Asset.setRef(_cdb, w, .Folder, folder_obj);
                    try assetdb.Asset.commit(_cdb, w);
                }
            }
        }
    }
}

fn moveToFolderMenu(allocator: std.mem.Allocator, selection: []const coreui.SelectionItem, filter: ?[:0]const u8) !void {
    if (_coreui.beginMenu(allocator, coreui.Icons.Folder ++ "  " ++ "Move" ++ "###MoveAsset", true, filter)) {
        defer _coreui.endMenu();
        try moveToFolderMenuInner(allocator, selection, _assetdb.getRootFolder(), true);
    }
}

var move_to_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (contexts.id != editor.Contexts.edit.id) return false;
        if (filter) |f| {
            return _coreui.uiFilterPass(allocator, f, "Move", false) != null;
        }

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
            if (_assetdb.isRootFolder(obj.obj)) return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        moveToFolderMenu(allocator, selection, filter) catch undefined;
    }
});

// Asset cntx menu
var debug_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.debug.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (_coreui.uiFilterPass(allocator, f, "Copy to clipboard", false) != null) return true;
            if (_coreui.uiFilterPass(allocator, f, "Force save", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        var is_root_folder = false;
        const is_folder = _assetdb.isAssetFolder(obj.obj);
        if (is_folder) {
            const ref = assetdb.Asset.readRef(_cdb, _cdb.readObj(obj.obj).?, .Folder);
            is_root_folder = ref == null;
        }

        if (_coreui.beginMenu(allocator, coreui.Icons.CopyToClipboard ++ "  " ++ "Copy to clipboard", true, filter)) {
            defer _coreui.endMenu();

            if (_coreui.menuItem(allocator, "Asset UUID", .{}, filter)) {
                const uuid = try _assetdb.getOrCreateUuid(obj.obj);
                var buff: [128]u8 = undefined;
                const uuid_str = std.fmt.bufPrintZ(&buff, "{s}", .{uuid}) catch undefined;
                _coreui.setClipboardText(uuid_str);
            }
        }

        if (_coreui.menuItem(allocator, coreui.Icons.Save ++ "  " ++ "Force save", .{}, filter)) {
            for (selection) |selected_obj| {
                _assetdb.saveAsset(allocator, selected_obj.obj) catch undefined;
            }
        }
    }
});

var create_from_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.create.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (_coreui.uiFilterPass(allocator, f, "Create new based on", false) != null) return true;
            if (_coreui.uiFilterPass(allocator, f, "Clone", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        var is_root_folder = false;
        const is_folder = _assetdb.isAssetFolder(obj.obj);
        if (is_folder) {
            const ref = assetdb.Asset.readRef(_cdb, _cdb.readObj(obj.obj).?, .Folder);
            is_root_folder = ref == null;
        }

        const is_project = if (_assetdb.getObjForAsset(obj.obj)) |o| o.type_idx.eql(ProjectTypeIdx) else false;

        if (!is_project and !is_folder and _coreui.menuItem(allocator, coreui.Icons.Instansiate ++ "  " ++ "Instansiate" ++ "###CreateNewAssetFromPrototype", .{}, filter)) {
            _ = try _assetdb.createNewAssetFromPrototype(_assetdb.getAssetForObj(obj.obj).?);
        }
        if (!is_project and !is_folder and _coreui.menuItem(allocator, coreui.Icons.Copy ++ "  " ++ "Clone" ++ "###CloneNewFrom", .{}, filter)) {
            _ = try _assetdb.cloneNewAssetFrom(_assetdb.getAssetForObj(obj.obj).?);
        }
    }
});

var reviel_in_os = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.edit.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (_coreui.uiFilterPass(allocator, f, "Reveal in OS", false) != null) return true;
            if (_coreui.uiFilterPass(allocator, f, "Open in OS", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        const is_folder = _assetdb.isAssetFolder(obj.obj);

        if (!is_folder and _coreui.menuItem(allocator, coreui.Icons.EditInOs ++ "  " ++ "Open in OS", .{}, filter)) {
            try _assetdb.openInOs(allocator, .edit, _assetdb.getAssetForObj(obj.obj).?);
        }

        if (_coreui.menuItem(allocator, coreui.Icons.Reveal ++ "  " ++ "Reveal in OS", .{}, filter)) {
            try _assetdb.openInOs(allocator, .reveal, _assetdb.getAssetForObj(obj.obj).?);
        }
    }
});

var delete_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.delete.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (_coreui.uiFilterPass(allocator, f, "Revive asset", false) != null) return true;
            if (_coreui.uiFilterPass(allocator, f, "Delete asset", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        var is_root_folder = false;
        const is_folder = _assetdb.isAssetFolder(obj.obj);
        if (is_folder) {
            const ref = assetdb.Asset.readRef(_cdb, _cdb.readObj(obj.obj).?, .Folder);
            is_root_folder = ref == null;
        }

        if (_assetdb.isToDeleted(obj.obj)) {
            if (_coreui.menuItem(allocator, coreui.Icons.Revive ++ "  " ++ "Revive asset" ++ "###ReviveAsset", .{ .enabled = !is_root_folder }, filter)) {
                _assetdb.reviveDeleted(obj.obj);
            }
        } else {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete asset" ++ "###DeleteAsset", .{ .enabled = !is_root_folder }, filter)) {
                for (selection) |selected_obj| {
                    if (_assetdb.isAssetFolder(selected_obj.obj)) {
                        _assetdb.deleteFolder(selected_obj.obj) catch undefined;
                    } else {
                        _assetdb.deleteAsset(selected_obj.obj) catch undefined;
                    }
                }
            }
        }
    }
});

fn getFolderForSelectedObj(selected_obj: cdb.ObjId) ?cdb.ObjId {
    if (_assetdb.isAssetFolder(selected_obj)) return selected_obj;

    var parent_folder: cdb.ObjId = _assetdb.getRootFolder();
    const asset = _assetdb.getAssetForObj(selected_obj) orelse return null;

    if (_cdb.readObj(asset)) |r| {
        parent_folder = assetdb.Asset.readRef(_cdb, r, .Folder).?;
    }

    return _assetdb.getAssetForObj(parent_folder).?;
}

var create_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = selection;

        if (contexts.id != editor.Contexts.create.id) return false;

        if (filter) |f| {
            const impls = try _apidb.getImpl(allocator, editor.CreateAssetI);
            defer allocator.free(impls);
            for (impls) |iface| {
                const menu_name = iface.menu_item() catch "";

                if (_coreui.uiFilterPass(allocator, f, menu_name, false) != null) return true;
            }
            return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        var menu_open = false;
        if (filter == null) {
            menu_open = _coreui.beginMenu(allocator, coreui.Icons.AddAsset ++ "  " ++ "Asset" ++ "###AddAsset", true, filter);
        }

        defer {
            if (filter == null and menu_open) _coreui.endMenu();
        }

        const db = _cdb.getDbFromObjid(selection[0].obj);

        if (menu_open or filter != null) {
            const impls = try _apidb.getImpl(allocator, editor.CreateAssetI);
            defer allocator.free(impls);
            for (impls) |iface| {
                const menu_name = try iface.menu_item();
                var buff: [256:0]u8 = undefined;
                const type_name = _cdb.getTypeName(db, _cdb.getTypeIdx(db, iface.cdb_type).?).?;
                const label = try std.fmt.bufPrintZ(&buff, "{s}###{s}", .{ menu_name, type_name });

                if (_coreui.menuItem(allocator, label, .{}, filter)) {
                    var parent_folder = getFolderForSelectedObj(selection[0].obj) orelse _assetdb.getRootFolder();
                    if (!parent_folder.isEmpty()) {
                        try iface.create(allocator, db, parent_folder);
                    }
                }
            }
        }
    }
});

// Create folder
var create_folder_i = editor.CreateAssetI.implement(
    assetdb.Folder.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try _assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                _cdb.getTypeIdx(db, assetdb.Folder.type_hash).?,
                "NewFolder",
            );

            _ = try _assetdb.createNewFolder(db, folder, name);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Folder ++ "  " ++ "Folder";
        }
    },
);

// Asset visual aspect
var asset_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiTooltip(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) !void {
        if (_assetdb.getUuid(obj)) |uuuid| {
            var buff: [256:0]u8 = undefined;
            const uuid_str = try std.fmt.bufPrintZ(&buff, "Asset UUID: {s}", .{uuuid});
            _coreui.text(uuid_str);
        }

        const asset_obj = _assetdb.getObjForAsset(obj).?;
        const db = _cdb.getDbFromObjid(obj);

        if (_cdb.getAspect(editor.UiVisualAspect, db, asset_obj.type_idx)) |aspect| {
            if (aspect.ui_tooltip) |tooltip| {
                _coreui.separator();
                try tooltip(allocator, asset_obj);
            }
        }
    }

    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = _cdb.readObj(obj).?;
        const asset_obj = assetdb.Asset.readSubObj(_cdb, obj_r, .Object).?;

        if (asset_obj.type_idx.eql(FolderTypeIdx)) {
            const asset_name = assetdb.Asset.readStr(_cdb, obj_r, .Name) orelse "ROOT";
            return std.fmt.bufPrintZ(buff, "{s}", .{asset_name}) catch "";
        } else {
            const db = _cdb.getDbFromObjid(obj);
            const asset_name = assetdb.Asset.readStr(_cdb, obj_r, .Name) orelse "No NAME =()";
            const type_name = _cdb.getTypeName(db, asset_obj.type_idx).?;
            return std.fmt.bufPrintZ(buff, "{s}.{s}", .{ asset_name, type_name }) catch "";
        }
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]u8 {
        const db = _cdb.getDbFromObjid(obj);
        const obj_r = _cdb.readObj(obj).?;
        const asset_obj = assetdb.Asset.readSubObj(_cdb, obj_r, .Object).?;

        var icon_buf: [16:0]u8 = undefined;

        var ui_icon: ?[:0]const u8 = null;
        if (_cdb.getAspect(editor.UiVisualAspect, db, asset_obj.type_idx)) |aspect| {
            if (aspect.ui_icons) |icons| {
                ui_icon = icons(&icon_buf, allocator, asset_obj) catch "";
            }
        }

        const is_modified = _assetdb.isAssetModified(obj);
        const is_deleted = _assetdb.isToDeleted(obj);

        return try std.fmt.bufPrintZ(
            buff,
            "{s} {s}{s}",
            .{
                if (ui_icon) |i| i else cetech1.coreui.Icons.Asset,
                if (is_modified) cetech1.coreui.CoreIcons.FA_STAR_OF_LIFE else "",
                if (is_deleted) "  " ++ cetech1.coreui.Icons.Deleted else "",
            },
        );
    }

    pub fn uiColor(
        obj: cdb.ObjId,
    ) ![4]f32 {
        return _editor.getAssetColor(obj);
    }
});

// Folder visual aspect
var folder_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiColor(
        obj: cdb.ObjId,
    ) ![4]f32 {
        const r = assetdb.Folder.read(_cdb, obj).?;
        if (assetdb.Folder.readSubObj(_cdb, r, .Color)) |color_obj| {
            return cdb_types.Color4f.f.toSlice(_cdb, color_obj);
        }

        return .{ 1.0, 1.0, 1.0, 1.0 };
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]u8 {
        _ = allocator; // autofix

        _ = obj;
        return try std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{cetech1.coreui.Icons.Folder},
        );
    }
});

// Asset tree aspect
fn lessThanAsset(_: void, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const l_name = _cdb.readStr(_cdb.readObj(lhs).?, assetdb.Asset.propIdx(.Name)) orelse return false;
    const r_name = _cdb.readStr(_cdb.readObj(rhs).?, assetdb.Asset.propIdx(.Name)) orelse return false;
    return std.ascii.lessThanIgnoreCase(l_name, r_name);
}

var asset_ui_tree_aspect = editor_tree.UiTreeAspect.implement(struct {
    pub fn uiTree(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        contexts: []const cetech1.StrId64,
        obj: coreui.SelectionItem,
        selection: *coreui.Selection,
        depth: u32,
        args: editor_tree.CdbTreeViewArgs,
    ) !bool {
        var result = false;

        const obj_r = _cdb.readObj(obj.obj) orelse return result;
        const asset_obj = assetdb.Asset.readSubObj(_cdb, obj_r, .Object).?;

        const is_folder = _assetdb.isAssetFolder(obj.obj);
        const is_root_folder = assetdb.Asset.readRef(_cdb, obj_r, .Folder) == null;

        if (!args.ignored_object.isEmpty() and args.ignored_object.eql(asset_obj)) {
            return result;
        }

        if (!args.expand_object and !editor_tree.filterOnlyTypes(args.only_types, asset_obj)) {
            return result;
        }

        const db = _cdb.getDbFromObjid(obj.obj);
        const expand = is_folder or (args.expand_object and _cdb.hasTypeSet(db, asset_obj.type_idx));

        const open = _editor_tree.cdbObjTreeNode(
            allocator,
            tab,
            contexts,
            selection,
            obj,
            is_root_folder or args.opened_obj.eql(obj.obj),
            false,
            !expand,
            args,
        );

        if (_coreui.isItemHovered(.{}) and _coreui.isMouseDoubleClicked(.left)) {
            try _editor_obj_buffer.addToFirst(allocator, db, obj);
        }

        if (_coreui.isItemActivated() or (_coreui.isItemHovered(.{}) and _coreui.isMouseClicked(.left) and selection.count() == 1)) {
            try _coreui.handleSelection(allocator, selection, obj, args.multiselect);
            result = true;
        }

        try formatTagsToLabel(allocator, obj.obj, assetdb.Asset.propIdx(.Tags));

        if (open) {
            defer _coreui.treePop();

            if (is_folder) {
                var folders = cetech1.cdb.ObjIdList{};
                defer folders.deinit(allocator);

                var assets = cetech1.cdb.ObjIdList{};
                defer assets.deinit(allocator);

                const set = try _cdb.getReferencerSet(allocator, asset_obj);
                defer allocator.free(set);

                for (set) |ref_obj| {
                    if (ref_obj.type_idx.eql(AssetTypeIdx)) {
                        if (_assetdb.isAssetFolder(ref_obj)) {
                            try folders.append(allocator, ref_obj);
                        } else {
                            try assets.append(allocator, ref_obj);
                        }
                    }
                }

                std.sort.insertion(cdb.ObjId, folders.items, {}, lessThanAsset);
                std.sort.insertion(cdb.ObjId, assets.items, {}, lessThanAsset);

                for (folders.items) |folder| {
                    const r = try _editor_tree.cdbTreeView(allocator, tab, contexts, .{ .top_level_obj = folder, .obj = folder }, selection, depth + 1, args);
                    if (r) result = r;
                }
                for (assets.items) |asset| {
                    const r = try _editor_tree.cdbTreeView(allocator, tab, contexts, .{ .top_level_obj = asset, .obj = asset }, selection, depth + 1, args);
                    if (r) result = r;
                }
            } else {
                if (args.expand_object) {
                    const r = try _editor_tree.cdbTreeView(allocator, tab, contexts, .{ .top_level_obj = obj.obj, .obj = asset_obj }, selection, depth + 1, args);
                    if (r) result = r;
                }
            }
        }

        return result;
    }

    pub fn uiDropObj(
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        obj: cdb.ObjId,
        drop_obj: cdb.ObjId,
    ) !void {
        _ = allocator;
        _ = tab;

        if (drop_obj.type_idx.eql(AssetTypeIdx)) {
            const obj_r = _cdb.readObj(obj) orelse return;

            const is_folder = _assetdb.isAssetFolder(obj);
            if (is_folder) {
                const asset_obj = assetdb.Asset.readSubObj(_cdb, obj_r, .Object).?;

                const drag_obj_folder = assetdb.Asset.readRef(_cdb, _cdb.readObj(drop_obj).?, .Folder).?;
                if (!drag_obj_folder.eql(asset_obj)) {
                    const w = assetdb.Asset.write(_cdb, drop_obj).?;
                    try assetdb.Asset.setRef(_cdb, w, .Folder, asset_obj);
                    try assetdb.Asset.commit(_cdb, w);
                }
            } else {
                const folder_obj = assetdb.Asset.readRef(_cdb, obj_r, .Folder).?;
                const drag_obj_folder = assetdb.Asset.readRef(_cdb, _cdb.readObj(drop_obj).?, .Folder).?;
                if (!drag_obj_folder.eql(folder_obj)) {
                    const w = assetdb.Asset.write(_cdb, drop_obj).?;
                    try assetdb.Asset.setRef(_cdb, w, .Folder, folder_obj);
                    try assetdb.Asset.commit(_cdb, w);
                }
            }
        }
    }
});

fn formatTagsToLabel(allocator: std.mem.Allocator, obj: cdb.ObjId, tag_prop_idx: u32) !void {
    const obj_r = _cdb.readObj(obj) orelse return;

    if (_cdb.readRefSet(obj_r, tag_prop_idx, allocator)) |tags| {
        var begin_pos: ?f32 = null;
        for (tags) |tag| {
            const tag_r = _cdb.readObj(tag) orelse continue;

            var tag_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
            if (_editor.isColorsEnabled()) {
                if (assetdb.Tag.readSubObj(_cdb, tag_r, .Color)) |c| {
                    tag_color = cetech1.cdb_types.Color4f.f.toSlice(_cdb, c);
                }
            }
            const tag_name = assetdb.Tag.readStr(_cdb, tag_r, .Name) orelse "No name =/";

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

            _coreui.textColored(tag_color, tag_lbl);

            if (_coreui.isItemHovered(.{})) {
                _coreui.beginTooltip();
                defer _coreui.endTooltip();

                const name_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag ++ "  " ++ "{s}", .{tag_name});
                _coreui.text(name_lbl);

                const tag_asset = _assetdb.getAssetForObj(tag).?;
                const desription = assetdb.Asset.readStr(_cdb, _cdb.readObj(tag_asset).?, .Description);
                if (desription) |d| {
                    _coreui.text(d);
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

        // TODO: probably problem with multiselect
        // _ = _coreui.registerTest(
        //     "ContextMenu",
        //     "should_rename_multiple_asset",
        //     @src(),
        //     struct {
        //         pub fn run(ctx: *coreui.TestContext) !void {
        //             _kernel.openAssetRoot("fixtures/test_asset");
        //             ctx.yield(_coreui, 1);

        //             ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
        //             ctx.windowFocus(_coreui, "");

        //             ctx.keyDown(_coreui, .mod_super);
        //             ctx.itemAction(_coreui, .Click, "**/###ROOT/###foo.ct_foo_asset", .{}, null);
        //             ctx.itemAction(_coreui, .Click, "**/###ROOT/###core", .{}, null);
        //             ctx.keyUp(_coreui, .mod_super);

        //             ctx.menuAction(_coreui, .Hover, "###ObjContextMenu/###Rename");

        //             ctx.itemInputStrValue(_coreui, "**/018b5846-c2d5-7b88-95f9-a7538a00e76b/$$0/###edit", "new_foo");
        //             ctx.itemInputStrValue(_coreui, "**/018e0f87-9fc7-7fa5-afc8-4814fd500014/$$0/###edit", "new_core");

        //             const db = _kernel.getDb();

        //             {
        //                 const foo = _assetdb.getObjId(_uuid.fromStr("018b5846-c2d5-7b88-95f9-a7538a00e76b").?).?;
        //                 const name = assetdb.Asset.readStr(db, db.readObj(foo).?, .Name);

        //                 std.testing.expect(name != null) catch |err| {
        //                     _coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //                 std.testing.expectEqualStrings(name.?, "new_foo") catch |err| {
        //                     _coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //             }

        //             {
        //                 const core = _assetdb.getObjId(_uuid.fromStr("018e0f87-9fc7-7fa5-afc8-4814fd500014").?).?;
        //                 const name = assetdb.Asset.readStr(db, db.readObj(core).?, .Name);

        //                 std.testing.expect(name != null) catch |err| {
        //                     _coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //                 std.testing.expectEqualStrings(name.?, "new_core") catch |err| {
        //                     _coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //             }

        //             ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###new_foo.ct_foo_asset", .{}, null);
        //             ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###new_core", .{}, null);
        //         }
        //     },
        // );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_move_asset_by_ctx_menu",
            @src(),
            struct {
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
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_b", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###MoveAsset/###folder_a/###MoveHere");

                    //TODO: Check moved
                    //ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_a/###asset_a.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_delete_and_revive_folder_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e48d4-df07-7602-9068-55d32eb8bb1d").?).?;
                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_b", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###DeleteAsset");

                    std.testing.expect(_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###folder_b", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###ReviveAsset");

                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_delete_and_revive_asset_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    const obj = _assetdb.getObjId(_uuid.fromStr("018e48d3-3837-705a-979f-94f28d478284").?).?;
                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_b.ct_foo_asset", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###DeleteAsset");

                    std.testing.expect(_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_b.ct_foo_asset", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###ReviveAsset");

                    std.testing.expect(!_assetdb.isToDeleted(obj)) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_create_new_asset_from_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_a.ct_foo_asset", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###CreateNewAssetFromPrototype");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_a2.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_clone_new_asset_from",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_a.ct_foo_asset", .{}, null);
                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###CloneNewFrom");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset_a2.ct_foo_asset", .{}, null);
                }
            },
        );
    }
});

// CDB types
var AssetTypeIdx: cdb.TypeIdx = undefined;
var FolderTypeIdx: cdb.TypeIdx = undefined;
var ProjectTypeIdx: cdb.TypeIdx = undefined;

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // ASSET
        try assetdb.Asset.addAspect(
            editor_tree.UiTreeAspect,
            _cdb,
            db,
            _g.asset_tree_aspect,
        );

        try assetdb.Asset.addAspect(
            editor.UiVisualAspect,
            _cdb,
            db,
            &asset_visual_aspect,
        );
        try assetdb.Folder.addAspect(
            editor.UiVisualAspect,
            _cdb,
            db,
            &folder_visual_aspect,
        );

        AssetTypeIdx = assetdb.Asset.typeIdx(_cdb, db);
        FolderTypeIdx = assetdb.Folder.typeIdx(_cdb, db);
        ProjectTypeIdx = assetdb.Project.typeIdx(_cdb, db);
    }
});

fn filerAsset(allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cdb.ObjId) !assetdb.FilteredAssets {
    var result = cetech1.ArrayList(assetdb.FilteredAsset){};
    var buff: [256:0]u8 = undefined;
    var buff2: [256:0]u8 = undefined;
    var buff3: [256:0]u8 = undefined;

    var filter_set = cetech1.AutoArrayHashMap(cdb.ObjId, void){};
    defer filter_set.deinit(allocator);

    if (_cdb.readObj(tags_filter)) |filter_r| {
        if (assetdb.Tags.readRefSet(_cdb, filter_r, .Tags, allocator)) |tags| {
            defer allocator.free(tags);
            for (tags) |tag| {
                try filter_set.put(allocator, tag, {});
            }
        }
    }
    const set = try assetdb.AssetRoot.readSubObjSet(_cdb, _cdb.readObj(_assetdb.getAssetRootObj()).?, .Assets, allocator);
    if (set) |s| {
        defer allocator.free(s);

        for (s) |obj| {
            if (filter_set.count() != 0) {
                if (_cdb.readObj(obj)) |asset_r| {
                    if (assetdb.Asset.readRefSet(_cdb, asset_r, .Tags, allocator)) |asset_tags| {
                        defer allocator.free(asset_tags);

                        var pass_n: u32 = 0;
                        for (asset_tags) |tag| {
                            if (filter_set.contains(tag)) pass_n += 1;
                        }
                        if (pass_n != filter_set.count()) continue;
                    }
                }
            }

            const path = try _assetdb.getFilePathForAsset(&buff3, obj);

            const f = try std.fmt.bufPrintZ(&buff, "{s}", .{filter});
            const p = try std.fmt.bufPrintZ(&buff2, "{s}", .{path});

            const score = _coreui.uiFilterPass(allocator, f, p, true) orelse continue;
            try result.append(allocator, .{ .score = score, .obj = obj });
        }
    }

    return result.toOwnedSlice(allocator);
}

const api = public.EditorAssetAPI{
    .filerAsset = &filerAsset,
};

const ASSET_TREE_ASPECT_NAME = "ct_asset_tree_aspect";
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
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _editor_inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;
    _editor_tree = apidb.getZigApi(module_name, editor_tree.TreeAPI).?;
    _editor_obj_buffer = apidb.getZigApi(module_name, editor_obj_buffer.EditorObjBufferAPI).?;
    _platform = apidb.getZigApi(module_name, cetech1.platform.PlatformApi).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.setOrRemoveZigApi(module_name, public.EditorAssetAPI, &api, load);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &move_to_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &rename_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &debug_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &delete_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &create_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &reviel_in_os, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &create_from_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.CreateAssetI, &create_folder_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    _g.asset_tree_aspect = try apidb.setGlobalVarValue(editor_tree.UiTreeAspect, module_name, ASSET_TREE_ASPECT_NAME, asset_ui_tree_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
