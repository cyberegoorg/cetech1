const std = @import("std");
const Allocator = std.mem.Allocator;

const public = cetech1.editor.assetdb;

const kernel = cetech1.kernel;
const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const assetdb = cetech1.assetdb;
const math = cetech1.math;

const Tag = assetdb.TagCdb;

const editor = cetech1.editor;
const editor_tabs = cetech1.editor.tabs;
const Icons = cetech1.coreui.Icons;

const editor_inspector = cetech1.editor.inspector;
const editor_tree = cetech1.editor.tree;
const editor_obj_buffer = cetech1.editor.obj_buffer;

const module_name = .editor_asset;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const uuid = cetech1.uuid;

var _assetdb: *const assetdb.AssetDBAPI = undefined;

const tempalloc = cetech1.tempalloc;

var _editor_tree: *const editor_tree.TreeAPI = undefined;

var _platform: *const cetech1.host.PlatformApi = undefined;

// Global state
const G = struct {
    asset_tree_aspect: *editor_tree.UiTreeAspect = undefined,
    asset_drop_aspect: *editor.UiDropObj = undefined,
    tag_prop_aspect: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
    tag_visual_aspect: *editor.UiVisualAspect = undefined,
    noproto_config_aspect: *editor_inspector.UiPropertiesConfigAspect = undefined,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};
var _g: *G = undefined;

var folder_properties_config_aspect = editor_inspector.UiPropertiesConfigAspect{
    .hide_prototype = true,
};

// Tag visual aspect
var tag_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;
        return std.fmt.bufPrintZ(buff, "{s}", .{
            Tag.readStr(obj_r, .Name) orelse "No NAME =()",
        });
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;

        _ = obj;
        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Tag});
    }

    pub fn uiColor(
        obj: cdb.ObjId,
    ) !math.Color4f {
        if (Tag.readSubObj(cdb.readObj(obj).?, .Color)) |color_obj| {
            return cetech1.cdb_types.Color4fCdb.f.to(color_obj);
        }
        return .white;
    }
});

// Tag property  aspect
var tag_prop_aspect = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = try tagsInput(allocator, obj, prop_idx, false, args.filter);
    }
});

fn getTagColor(db: cdb.DbId, tag_r: *cdb.Obj) math.Color4f {
    _ = db;
    if (!editor.isColorsEnabled()) return .white;

    const tag_color_obj = Tag.readSubObj(tag_r, .Color);
    var color: math.Color4f = .white;
    if (tag_color_obj) |color_obj| {
        color = cetech1.cdb_types.Color4fCdb.f.to(color_obj);
    }
    return color;
}

fn tagButton(db: cdb.DbId, filter: ?[:0]const u8, tag: cdb.ObjId, wrap: bool) bool {
    var buff: [128:0]u8 = undefined;
    const tag_r = cdb.readObj(tag) orelse return false;
    const tag_name = Tag.readStr(tag_r, .Name) orelse "NO NAME =(";
    const tag_color = getTagColor(db, tag_r);

    const color_scale = 0.80;
    const tag_color_normal: math.Color4f = .{
        .r = tag_color.r * color_scale,
        .g = tag_color.g * color_scale,
        .b = tag_color.b * color_scale,
        .a = 1.0,
    };

    coreui.pushObjUUID(tag);
    defer coreui.popId();

    const label = std.fmt.bufPrintZ(&buff, coreui.Icons.Tag ++ "  " ++ "{s}###Tag", .{tag_name}) catch return false;

    if (filter) |f| {
        if (coreui.uiFilterPass(_allocator, f, label, false) == null) return false;
    }

    if (wrap) {
        const style = coreui.getStyle();
        const pos_a = coreui.getItemRectMax().x;
        const text_size = coreui.calcTextSize(label, .{}).x + 2 * style.frame_padding.x;

        if (pos_a + text_size + style.item_spacing.x < coreui.getWindowPos().x + coreui.getContentRegionAvail().x) {
            coreui.sameLine(.{});
        }
    }

    coreui.pushStyleColor4f(.{ .c = tag_color_normal, .idx = .button });
    coreui.pushStyleColor4f(.{ .c = tag_color, .idx = .button_active });
    coreui.pushStyleColor4f(.{ .c = tag_color, .idx = .button_hovered });
    defer coreui.popStyleColor(.{ .count = 3 });

    coreui.pushStyleVar1f(.{ .idx = .frame_rounding, .v = 10 });
    coreui.pushStyleVar2f(.{ .idx = .frame_padding, .v = .{ .x = 6, .y = 3 } });
    defer coreui.popStyleVar(.{ .count = 2 });

    const button = (coreui.button(label, .{}));

    return button;
}

fn tagsInput(
    allocator: std.mem.Allocator,
    obj: cdb.ObjId,
    prop_idx: u32,
    in_table: bool,
    filter: ?[:0]const u8,
) !bool {
    _ = filter;
    _ = in_table;
    const obj_r = cdb.readObj(obj) orelse return false;
    const db = cdb.getDbFromObjid(obj);

    if (coreui.button(coreui.Icons.Add ++ "###AddTags", .{})) {
        coreui.openPopup("ui_tag_add_popup", .{});
    }

    var any_tag_set = false;
    if (cdb.readRefSet(obj_r, prop_idx, allocator)) |tags| {
        for (tags) |tag| {
            any_tag_set = true;
            if (tagButton(db, null, tag, true)) {
                const obj_w = cdb.writeObj(obj).?;
                try cdb.removeFromRefSet(obj_w, prop_idx, tag);
                try cdb.writeCommit(obj_w);
            }
        }
    }

    if (coreui.beginPopup("ui_tag_add_popup", .{})) {
        defer coreui.endPopup();

        _g.filter = coreui.uiFilter(&_g.filter_buff, _g.filter);

        if (cdb.getAllObjectByType(allocator, db, assetdb.TagCdb.typeIdx(db))) |tags| {
            for (tags) |tag| {
                if (cdb.isInSet(obj_r, prop_idx, tag)) continue;
                if (tagButton(db, _g.filter, tag, true)) {
                    const obj_w = cdb.writeObj(obj).?;
                    try cdb.addRefToSet(obj_w, prop_idx, &.{tag});
                    coreui.closeCurrentPopup();
                    try cdb.writeCommit(obj_w);
                }
            }
        }
    }

    return any_tag_set;
}

// var rename_context_menu_i = editor.ObjContextMenuI.implement(struct {
//     pub fn isValid(
//         allocator: std.mem.Allocator,
//         tab: *editor_tabs.TabO,
//         contexts: cetech1.StrId64,
//         selection: []const coreui.SelectedObj,
//         filter: ?[:0]const u8,
//     ) !bool {
//         _ = tab;
//
//         if (contexts.id != editor.Contexts.edit.id) return false;
//
//         if (filter) |f| {
//             return coreui.uiFilterPass(allocator, f, "Rename", false) != null;
//         }
//
//         for (selection) |obj| {
//             if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
//             if (assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
//             if (assetdb.isRootFolder(obj.obj)) return false;
//         }
//
//         return true;
//     }
//
//     pub fn menu(
//         allocator: std.mem.Allocator,
//         tab: *editor_tabs.TabO,
//         context: cetech1.StrId64,
//         selection: []const coreui.SelectedObj,
//         filter: ?[:0]const u8,
//     ) !void {
//         _ = context;
//         _ = tab;
//
//         if (coreui.beginMenu(allocator, coreui.Icons.Rename ++ "  " ++ "Rename" ++ "###Rename", true, filter)) {
//             defer coreui.endMenu();
//
//             var buff: [128:0]u8 = undefined;
//
//             for (selection) |obj| {
//                 if (!obj.obj.type_idx.eql(AssetTypeIdx)) continue;
//
//                 coreui.pushObjUUID(obj.obj);
//                 coreui.pushIntId(selection[0].prop_idx orelse 0);
//                 defer coreui.popId();
//                 defer coreui.popId();
//
//                 const asset_label = editor.buffFormatObjLabel(allocator, &buff, obj.obj, .{ .with_txt = true, .with_status_icons = true }) orelse "Not implemented";
//                 const asset_color = editor.getAssetColor(obj.obj);
//                 if (editor_inspector.uiPropBegin(allocator, asset_label, asset_color, true, .{})) {
//                     defer editor_inspector.uiPropEnd(true, .{});
//                     editor_inspector.uiPropInputRaw(obj.obj, assetdb.AssetCdb.propIdx(.Name), .{}) catch undefined;
//                 }
//             }
//         }
//     }
// });

fn moveToFolderMenuInner(allocator: std.mem.Allocator, selection: []const coreui.SelectedObj, folder: cdb.ObjId, is_root: bool) !void {
    const name = assetdb.AssetCdb.readStr(cdb.readObj(folder).?, .Name);
    const folder_obj = assetdb.getObjForAsset(folder).?;
    var buff: [256:0]u8 = undefined;
    const label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Folder ++ "  " ++ "{s}" ++ "###{s}", .{ name orelse "ROOT", name orelse "ROOT" });

    var open = true;
    if (!is_root) {
        const asset_color = editor.getAssetColor(folder);
        coreui.pushStyleColor4f(.{ .idx = .text, .c = asset_color });
        open = coreui.beginMenu(allocator, label, true, null);
        coreui.popStyleColor(.{});
    }

    if (open) {
        defer if (!is_root) coreui.endMenu();

        const set = try cdb.getReferencerSet(allocator, folder_obj);
        defer allocator.free(set);

        var any_folder = false;
        for (set) |ref_obj| {
            if (!assetdb.isAssetFolder(ref_obj)) continue;

            const contain = for (selection) |s| {
                if (s.obj.eql(ref_obj)) break true;
            } else false;
            if (contain) continue;

            any_folder = true;
            try moveToFolderMenuInner(allocator, selection, ref_obj, false);
        }

        if (any_folder) {
            coreui.separator();
        }

        if (coreui.menuItem(allocator, coreui.Icons.MoveHere ++ "  " ++ "Move here" ++ "###MoveHere", .{}, null)) {
            for (selection) |obj| {
                if (obj.obj.type_idx.eql(AssetTypeIdx)) {
                    const w = assetdb.AssetCdb.write(obj.obj).?;
                    try assetdb.AssetCdb.setRef(w, .Folder, folder_obj);
                    try assetdb.AssetCdb.commit(w);
                }
            }
        }
    }
}

fn moveToFolderMenu(allocator: std.mem.Allocator, selection: []const coreui.SelectedObj, filter: ?[:0]const u8) !void {
    if (coreui.beginMenu(allocator, coreui.Icons.Folder ++ "  " ++ "Move" ++ "###MoveAsset", true, filter)) {
        defer coreui.endMenu();
        try moveToFolderMenuInner(allocator, selection, assetdb.getRootFolder(), true);
    }
}

var move_to_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (contexts.id != editor.Contexts.edit.id) return false;
        if (filter) |f| {
            return coreui.uiFilterPass(allocator, f, "Move", false) != null;
        }

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
            if (assetdb.isRootFolder(obj.obj)) return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
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
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.debug.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (coreui.uiFilterPass(allocator, f, "Copy to clipboard", false) != null) return true;
            if (coreui.uiFilterPass(allocator, f, "Force save", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        var is_root_folder = false;
        const is_folder = assetdb.isAssetFolder(obj.obj);
        if (is_folder) {
            const ref = assetdb.AssetCdb.readRef(cdb.readObj(obj.obj).?, .Folder);
            is_root_folder = ref == null;
        }

        if (coreui.beginMenu(allocator, coreui.Icons.CopyToClipboard ++ "  " ++ "Copy to clipboard", true, filter)) {
            defer coreui.endMenu();

            if (coreui.menuItem(allocator, "Asset UUID", .{}, filter)) {
                const obj_uuid = try cdb.getOrCreateUuid(obj.obj);
                var buff: [128]u8 = undefined;
                const uuid_str = std.fmt.bufPrintZ(&buff, "{f}", .{obj_uuid}) catch undefined;
                coreui.setClipboardText(uuid_str);
            }
        }

        if (coreui.menuItem(allocator, coreui.Icons.Save ++ "  " ++ "Force save", .{}, filter)) {
            for (selection) |selected_obj| {
                assetdb.saveAsset(allocator, selected_obj.obj) catch undefined;
            }
        }
    }
});

var create_from_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.create.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (coreui.uiFilterPass(allocator, f, "Create new based on", false) != null) return true;
            if (coreui.uiFilterPass(allocator, f, "Clone", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        var is_root_folder = false;
        const is_folder = assetdb.isAssetFolder(obj.obj);
        if (is_folder) {
            const ref = assetdb.AssetCdb.readRef(cdb.readObj(obj.obj).?, .Folder);
            is_root_folder = ref == null;
        }

        const is_project = if (assetdb.getObjForAsset(obj.obj)) |o| o.type_idx.eql(ProjectTypeIdx) else false;

        if (!is_project and !is_folder and coreui.menuItem(allocator, coreui.Icons.Instansiate ++ "  " ++ "Instansiate" ++ "###CreateNewAssetFromPrototype", .{}, filter)) {
            _ = try assetdb.createNewAssetFromPrototype(assetdb.getAssetForObj(obj.obj).?);
        }
        if (!is_project and !is_folder and coreui.menuItem(allocator, coreui.Icons.Copy ++ "  " ++ "Clone" ++ "###CloneNewFrom", .{}, filter)) {
            _ = try assetdb.cloneNewAssetFrom(assetdb.getAssetForObj(obj.obj).?);
        }
    }
});

var reviel_in_os = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.edit.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (coreui.uiFilterPass(allocator, f, "Reveal in OS", false) != null) return true;
            if (coreui.uiFilterPass(allocator, f, "Open in OS", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        const is_folder = assetdb.isAssetFolder(obj.obj);

        if (!is_folder and coreui.menuItem(allocator, coreui.Icons.EditInOs ++ "  " ++ "Open in OS", .{}, filter)) {
            try assetdb.openInOs(allocator, .Edit, assetdb.getAssetForObj(obj.obj).?);
        }

        if (coreui.menuItem(allocator, coreui.Icons.Reveal ++ "  " ++ "Reveal in OS", .{}, filter)) {
            try assetdb.openInOs(allocator, .Reveal, assetdb.getAssetForObj(obj.obj).?);
        }
    }
});

var delete_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != editor.Contexts.delete.id) return false;

        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (context.id != editor.Contexts.delete.id) continue;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (o.type_idx.eql(ProjectTypeIdx)) return false;
        }

        var valid = true;
        if (filter) |f| {
            valid = false;
            if (coreui.uiFilterPass(allocator, f, "Revive asset", false) != null) return true;
            if (coreui.uiFilterPass(allocator, f, "Delete asset", false) != null) return true;
        }
        return valid;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const obj = selection[0];

        var is_root_folder = false;
        const is_folder = assetdb.isAssetFolder(obj.obj);
        if (is_folder) {
            const ref = assetdb.AssetCdb.readRef(cdb.readObj(obj.obj).?, .Folder);
            is_root_folder = ref == null;
        }

        if (assetdb.isToDeleted(obj.obj)) {
            if (coreui.menuItem(allocator, coreui.Icons.Revive ++ "  " ++ "Revive asset" ++ "###ReviveAsset", .{ .enabled = !is_root_folder }, filter)) {
                assetdb.reviveDeleted(obj.obj);
            }
        } else {
            if (coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete asset" ++ "###DeleteAsset", .{ .enabled = !is_root_folder }, filter)) {
                for (selection) |selected_obj| {
                    if (assetdb.isAssetFolder(selected_obj.obj)) {
                        assetdb.deleteFolder(selected_obj.obj) catch undefined;
                    } else {
                        assetdb.deleteAsset(selected_obj.obj) catch undefined;
                    }
                }
            }
        }
    }
});

fn getFolderForSelectedObj(selected_obj: cdb.ObjId) ?cdb.ObjId {
    if (assetdb.isAssetFolder(selected_obj)) return selected_obj;

    var parent_folder: cdb.ObjId = assetdb.getRootFolder();
    const asset = assetdb.getAssetForObj(selected_obj) orelse return null;

    if (cdb.readObj(asset)) |r| {
        parent_folder = assetdb.AssetCdb.readRef(r, .Folder).?;
    }

    return assetdb.getAssetForObj(parent_folder).?;
}

var create_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = selection;

        if (contexts.id != editor.Contexts.create.id) return false;

        if (filter) |f| {
            const impls = try apidb.getImpl(allocator, public.CreateAssetI);
            defer allocator.free(impls);
            for (impls) |iface| {
                const menu_name = iface.menu_item() catch "";

                if (coreui.uiFilterPass(allocator, f, menu_name, false) != null) return true;
            }
            return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        var menu_open = false;
        if (filter == null) {
            menu_open = coreui.beginMenu(allocator, coreui.Icons.AddAsset ++ "  " ++ "Asset" ++ "###AddAsset", true, filter);
        }

        defer {
            if (filter == null and menu_open) coreui.endMenu();
        }

        const db = cdb.getDbFromObjid(selection[0].obj);

        if (menu_open or filter != null) {
            const impls = try apidb.getImpl(allocator, public.CreateAssetI);
            defer allocator.free(impls);
            for (impls) |iface| {
                const menu_name = try iface.menu_item();
                var buff: [256:0]u8 = undefined;
                const type_name = cdb.getTypeName(db, cdb.getTypeIdx(db, iface.cdb_type).?).?;
                const label = try std.fmt.bufPrintZ(&buff, "{s}###{s}", .{ menu_name, type_name });

                if (coreui.menuItem(allocator, label, .{}, filter)) {
                    var parent_folder = getFolderForSelectedObj(selection[0].obj) orelse assetdb.getRootFolder();
                    if (!parent_folder.isEmpty()) {
                        try iface.create(allocator, db, parent_folder);
                    }
                }
            }
        }
    }
});

// Create folder
var create_folder_i = public.CreateAssetI.implement(
    assetdb.FolderCdb.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                cdb.getTypeIdx(db, assetdb.FolderCdb.type_hash).?,
                "NewFolder",
            );

            _ = try assetdb.createNewFolder(db, folder, name);
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
        const uuuid = try cdb.getOrCreateUuid(obj);
        var buff: [256:0]u8 = undefined;
        const uuid_str = try std.fmt.bufPrintZ(&buff, "Asset UUID: {f}", .{uuuid});
        coreui.text(uuid_str);

        const asset_obj = assetdb.getObjForAsset(obj).?;
        const db = cdb.getDbFromObjid(obj);

        if (cdb.getAspect(editor.UiVisualAspect, db, asset_obj.type_idx)) |aspect| {
            if (aspect.ui_tooltip) |tooltip| {
                coreui.separator();
                try tooltip(allocator, asset_obj);
            }
        }
    }

    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;
        const asset_obj = assetdb.AssetCdb.readSubObj(obj_r, .Object).?;

        if (asset_obj.type_idx.eql(FolderTypeIdx)) {
            const asset_name = assetdb.AssetCdb.readStr(obj_r, .Name) orelse "ROOT";
            return std.fmt.bufPrintZ(buff, "{s}", .{asset_name}) catch "";
        } else {
            const db = cdb.getDbFromObjid(obj);
            const asset_name = assetdb.AssetCdb.readStr(obj_r, .Name) orelse "No NAME =()";
            const type_name = cdb.getTypeName(db, asset_obj.type_idx).?;
            return std.fmt.bufPrintZ(buff, "{s}.{s}", .{ asset_name, type_name }) catch "";
        }
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]u8 {
        const db = cdb.getDbFromObjid(obj);
        const obj_r = cdb.readObj(obj).?;
        const asset_obj = assetdb.AssetCdb.readSubObj(obj_r, .Object).?;

        var icon_buf: [16:0]u8 = undefined;

        var ui_icon: ?[:0]const u8 = null;
        if (cdb.getAspect(editor.UiVisualAspect, db, asset_obj.type_idx)) |aspect| {
            if (aspect.ui_icons) |icons| {
                ui_icon = icons(&icon_buf, allocator, asset_obj) catch "";
            }
        }

        return try std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                if (ui_icon) |i| i else cetech1.coreui.Icons.Asset,
            },
        );
    }

    pub fn uiStatusIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]u8 {
        _ = allocator;

        const is_modified = assetdb.isAssetModified(obj);
        const is_deleted = assetdb.isToDeleted(obj);

        return try std.fmt.bufPrintZ(
            buff,
            "{s}{s}",
            .{
                if (is_modified) cetech1.coreui.Icons.Modified else "",
                if (is_deleted) "  " ++ cetech1.coreui.Icons.Deleted else "",
            },
        );
    }

    pub fn uiColor(
        obj: cdb.ObjId,
    ) !math.Color4f {
        return editor.getAssetColor(obj);
    }
});

// Folder visual aspect
var folder_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiColor(
        obj: cdb.ObjId,
    ) !math.Color4f {
        const r = assetdb.FolderCdb.read(obj).?;
        if (assetdb.FolderCdb.readSubObj(r, .Color)) |color_obj| {
            return cdb_types.Color4fCdb.f.to(color_obj);
        }

        return .white;
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]u8 {
        _ = allocator;

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
    const l_name = cdb.readStr(cdb.readObj(lhs).?, assetdb.AssetCdb.propIdx(.Name)) orelse return false;
    const r_name = cdb.readStr(cdb.readObj(rhs).?, assetdb.AssetCdb.propIdx(.Name)) orelse return false;
    return std.ascii.lessThanIgnoreCase(l_name, r_name);
}

var asset_drop_obj_asspect = editor.UiDropObj.implement(
    struct {
        pub fn uiDropObj(
            allocator: std.mem.Allocator,
            tab: *editor_tabs.TabO,
            obj: cdb.ObjId,
            prop_idx: ?u32,
            drop_obj: cdb.ObjId,
        ) !void {
            _ = allocator;
            _ = tab;
            _ = prop_idx;

            if (drop_obj.type_idx.eql(AssetTypeIdx)) {
                const obj_r = cdb.readObj(obj) orelse return;

                const is_folder = assetdb.isAssetFolder(obj);
                if (is_folder) {
                    const asset_obj = assetdb.AssetCdb.readSubObj(obj_r, .Object).?;

                    const drag_obj_folder = assetdb.AssetCdb.readRef(cdb.readObj(drop_obj).?, .Folder).?;
                    if (!drag_obj_folder.eql(asset_obj)) {
                        const w = assetdb.AssetCdb.write(drop_obj).?;
                        try assetdb.AssetCdb.setRef(w, .Folder, asset_obj);
                        try assetdb.AssetCdb.commit(w);
                    }
                } else {
                    const folder_obj = assetdb.AssetCdb.readRef(obj_r, .Folder).?;
                    const drag_obj_folder = assetdb.AssetCdb.readRef(cdb.readObj(drop_obj).?, .Folder).?;
                    if (!drag_obj_folder.eql(folder_obj)) {
                        const w = assetdb.AssetCdb.write(drop_obj).?;
                        try assetdb.AssetCdb.setRef(w, .Folder, folder_obj);
                        try assetdb.AssetCdb.commit(w);
                    }
                }
            }
        }
    },
);

var asset_ui_tree_aspect = editor_tree.UiTreeAspect.implement(struct {
    pub fn uiTree(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: []const cetech1.StrId64,
        obj: coreui.SelectedObj,
        selection: *coreui.Selection,
        depth: u32,
        args: editor_tree.CdbTreeViewArgs,
    ) !bool {
        var result = false;

        const obj_r = cdb.readObj(obj.obj) orelse return result;
        const asset_obj = assetdb.AssetCdb.readSubObj(obj_r, .Object).?;

        const is_folder = assetdb.isAssetFolder(obj.obj);
        const is_root_folder = assetdb.AssetCdb.readRef(obj_r, .Folder) == null;

        if (!args.ignored_object.isEmpty() and args.ignored_object.eql(asset_obj)) {
            return result;
        }

        if (!args.expand_object and !public.filterOnlyTypes(args.only_types, asset_obj)) {
            return result;
        }

        const db = cdb.getDbFromObjid(obj.obj);
        const expand = is_folder or (args.expand_object and cdb.hasTypeSet(db, asset_obj.type_idx));

        const open = editor_tree.cdbObjTreeNode(
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

        if (coreui.isItemHovered(.{}) and coreui.isMouseDoubleClicked(.left)) {
            try editor_obj_buffer.addToFirst(allocator, db, obj);
        }

        if (coreui.isItemActivated() or (coreui.isItemHovered(.{}) and coreui.isMouseClicked(.left) and selection.count() == 1)) {
            try coreui.handleSelection(allocator, selection, obj, args.multiselect);
            result = true;
        }

        try formatTagsToLabel(allocator, obj.obj, assetdb.AssetCdb.propIdx(.Tags));

        if (open) {
            defer coreui.treePop();

            if (is_folder) {
                var folders = cetech1.cdb.ObjIdList.empty;
                defer folders.deinit(allocator);

                var assets = cetech1.cdb.ObjIdList.empty;
                defer assets.deinit(allocator);

                const set = try cdb.getReferencerSet(allocator, asset_obj);
                defer allocator.free(set);

                for (set) |ref_obj| {
                    if (ref_obj.type_idx.eql(AssetTypeIdx)) {
                        if (assetdb.isAssetFolder(ref_obj)) {
                            try folders.append(allocator, ref_obj);
                        } else {
                            try assets.append(allocator, ref_obj);
                        }
                    }
                }

                std.sort.insertion(cdb.ObjId, folders.items, {}, lessThanAsset);
                std.sort.insertion(cdb.ObjId, assets.items, {}, lessThanAsset);

                for (folders.items) |folder| {
                    const r = try editor_tree.cdbObjTree(
                        allocator,
                        tab,
                        contexts,
                        .{ .top_level_obj = folder, .obj = folder },
                        selection,
                        depth + 1,
                        args,
                    );
                    if (r) result = r;
                }
                for (assets.items) |asset| {
                    const r = try editor_tree.cdbObjTree(
                        allocator,
                        tab,
                        contexts,
                        .{ .top_level_obj = asset, .obj = asset },
                        selection,
                        depth + 1,
                        args,
                    );
                    if (r) result = r;
                }
            } else {
                if (args.expand_object) {
                    const r = try editor_tree.cdbObjTree(
                        allocator,
                        tab,
                        contexts,
                        .{ .top_level_obj = obj.obj, .obj = asset_obj },
                        selection,
                        depth + 1,
                        args,
                    );
                    if (r) result = r;
                }
            }
        }

        return result;
    }
});

fn formatTagsToLabel(allocator: std.mem.Allocator, obj: cdb.ObjId, tag_prop_idx: u32) !void {
    const obj_r = cdb.readObj(obj) orelse return;

    if (cdb.readRefSet(obj_r, tag_prop_idx, allocator)) |tags| {
        var begin_pos: ?f32 = null;
        for (tags) |tag| {
            const tag_r = cdb.readObj(tag) orelse continue;

            var tag_color: math.Color4f = .white;
            if (editor.isColorsEnabled()) {
                if (assetdb.TagCdb.readSubObj(tag_r, .Color)) |c| {
                    tag_color = cetech1.cdb_types.Color4fCdb.f.to(c);
                }
            }
            tag_color.a = 1.0;

            const tag_name = assetdb.TagCdb.readStr(tag_r, .Name) orelse "No name =/";

            coreui.pushObjUUID(tag);
            defer coreui.popId();

            const max_region = .{
                coreui.getContentRegionAvail().x + coreui.getCursorScreenPos().x - coreui.getWindowPos().x,
                coreui.getContentRegionAvail().y + coreui.getCursorScreenPos().y - coreui.getWindowPos().y,
            };

            const begin_offset = coreui.getFontSize() / 2;
            const item_size = coreui.getFontSize() / 3;
            if (begin_pos == null) {
                coreui.sameLine(.{ .offset_from_start_x = max_region[0] - begin_offset - (item_size * @as(f32, @floatFromInt(tags.len))) });
            } else {
                begin_pos.? += item_size;
                coreui.sameLine(.{ .offset_from_start_x = begin_pos.? });
            }

            var tag_buf: [128:0]u8 = undefined;
            const tag_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag, .{});
            if (begin_pos == null) {
                begin_pos = coreui.getCursorPosX();
            }

            coreui.textColored(tag_color, tag_lbl);

            if (coreui.isItemHovered(.{})) {
                if (coreui.beginTooltip()) {
                    defer coreui.endTooltip();

                    const name_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag ++ "  " ++ "{s}", .{tag_name});
                    coreui.text(name_lbl);

                    const tag_asset = assetdb.getAssetForObj(tag).?;
                    const desription = assetdb.AssetCdb.readStr(cdb.readObj(tag_asset).?, .Description);
                    if (desription) |d| {
                        coreui.text(d);
                    }
                }
            }
        }
    }
}

//
// Create tag asset
//

var create_tag_asset_i = public.CreateAssetI.implement(
    assetdb.TagCdb.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                cdb.getTypeIdx(db, assetdb.TagCdb.type_hash).?,
                "NewTag",
            );
            const new_obj = try assetdb.TagCdb.createObject(db);
            {
                const w = cdb.writeObj(new_obj).?;
                try assetdb.TagCdb.setStr(w, .Name, name);
                try cdb.writeCommit(w);
            }

            _ = assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Tag ++ "  " ++ "Tag";
        }
    },
);

// Test
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = coreui.registerTest(
            "ContextMenu",
            "should_create_new_folder",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_empty");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");

                    ctx.itemAction(.DoubleClick, "**/###project.ct_project", .{}, null);

                    ctx.menuAction(.Click, "###AddAsset/###AddAsset/###ct_folder");
                    ctx.itemAction(.DoubleClick, "**/###NewFolder", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_create_new_tag",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_empty");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");

                    ctx.itemAction(.DoubleClick, "**/###project.ct_project", .{}, null);

                    ctx.menuAction(.Click, "###AddAsset/###AddAsset/###ct_tag");
                    ctx.itemAction(.DoubleClick, "**/###NewTag.ct_tag", .{}, null);
                }
            },
        );

        // TODO: redesign
        // _ = coreui.registerTest(
        //     "ContextMenu",
        //     "should_rename_asset",
        //     @src(),
        //     struct {
        //         pub fn run(ctx: *coreui.TestContext) !void {
        //             kernel.openAssetRoot("fixtures/test_asset");
        //             ctx.yield(  1);
        //
        //             ctx.setRef(  "###ct_editor_asset_browser_tab_1");
        //             ctx.windowFocus(  "");
        //             // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
        //             ctx.itemAction(  .DoubleClick, "**/###foo.ct_foo_asset", .{}, null);
        //
        //             ctx.menuAction(  .Open, "###ObjContextMenu/###Rename");
        //             ctx.itemInputStrValue(  "**/###edit", "new_foo");
        //
        //             ctx.itemAction(  .DoubleClick, "**/###new_foo.ct_foo_asset", .{}, null);
        //         }
        //     },
        // );

        // TODO: probably problem with multiselect
        // _ = coreui.registerTest(
        //     "ContextMenu",
        //     "should_rename_multiple_asset",
        //     @src(),
        //     struct {
        //         pub fn run(ctx: *coreui.TestContext) !void {
        //             kernel.openAssetRoot("fixtures/test_asset");
        //             ctx.yield(  1);

        //             ctx.setRef(  "###ct_editor_asset_browser_tab_1");
        //             ctx.windowFocus(  "");

        //             ctx.keyDown(  .mod_super);
        //             ctx.itemAction(  .Click, "**/###foo.ct_foo_asset", .{}, null);
        //             ctx.itemAction(  .Click, "**/###core", .{}, null);
        //             ctx.keyUp(  .mod_super);

        //             ctx.menuAction(  .Hover, "###ObjContextMenu/###Rename");

        //             ctx.itemInputStrValue(  "**/018b5846-c2d5-7b88-95f9-a7538a00e76b/$$0/###edit", "new_foo");
        //             ctx.itemInputStrValue(  "**/018e0f87-9fc7-7fa5-afc8-4814fd500014/$$0/###edit", "new_core");

        //             const db = kernel.getDb();

        //             {
        //                 const foo = cdb.getObjId(assetdb.getDb(),uuid.fromStr("018b5846-c2d5-7b88-95f9-a7538a00e76b").?).?;
        //                 const name = assetdb.Asset.readStr(db, db.readObj(foo).?, .Name);

        //                 std.testing.expect(name != null) catch |err| {
        //                     coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //                 std.testing.expectEqualStrings(name.?, "new_foo") catch |err| {
        //                     coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //             }

        //             {
        //                 const core = cdb.getObjId(assetdb.getDb(),uuid.fromStr("018e0f87-9fc7-7fa5-afc8-4814fd500014").?).?;
        //                 const name = assetdb.Asset.readStr(db, db.readObj(core).?, .Name);

        //                 std.testing.expect(name != null) catch |err| {
        //                     coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //                 std.testing.expectEqualStrings(name.?, "new_core") catch |err| {
        //                     coreui.checkTestError(@src(), err);
        //                     return err;
        //                 };
        //             }

        //             ctx.itemAction(  .DoubleClick, "**/###new_foo.ct_foo_asset", .{}, null);
        //             ctx.itemAction(  .DoubleClick, "**/###new_core", .{}, null);
        //         }
        //     },
        // );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_move_asset_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset_a.ct_foo_asset", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###MoveAsset/###folder_a/###MoveHere");

                    //TODO: Check moved
                    //ctx.itemAction(  .Open, "**/###folder_a/###asset_a.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_move_folder_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###folder_b", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###MoveAsset/###folder_a/###MoveHere");

                    //TODO: Check moved
                    //ctx.itemAction(  .DoubleClick, "**/###folder_a/###asset_a.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_delete_and_revive_folder_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(1);

                    const obj = cdb.getObjId(assetdb.getDb(), uuid.fromStr("018e48d4-df07-7602-9068-55d32eb8bb1d").?).?;
                    std.testing.expect(!assetdb.isToDeleted(obj)) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###folder_b", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###DeleteAsset");

                    std.testing.expect(assetdb.isToDeleted(obj)) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.itemAction(.DoubleClick, "**/###folder_b", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###ReviveAsset");

                    std.testing.expect(!assetdb.isToDeleted(obj)) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_delete_and_revive_asset_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(1);

                    const obj = cdb.getObjId(assetdb.getDb(), uuid.fromStr("018e48d3-3837-705a-979f-94f28d478284").?).?;
                    std.testing.expect(!assetdb.isToDeleted(obj)) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset_b.ct_foo_asset", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###DeleteAsset");

                    std.testing.expect(assetdb.isToDeleted(obj)) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    ctx.itemAction(.DoubleClick, "**/###asset_b.ct_foo_asset", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###ReviveAsset");

                    std.testing.expect(!assetdb.isToDeleted(obj)) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_create_new_asset_from_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset_a.ct_foo_asset", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###CreateNewAssetFromPrototype");
                    ctx.itemAction(.DoubleClick, "**/###asset_a2.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_clone_new_asset_from",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset_a.ct_foo_asset", .{}, null);
                    ctx.menuAction(.Click, "###ObjContextMenu/###CloneNewFrom");
                    ctx.itemAction(.DoubleClick, "**/###asset_a2.ct_foo_asset", .{}, null);
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
        try assetdb.AssetCdb.addAspect(
            editor_tree.UiTreeAspect,

            db,
            _g.asset_tree_aspect,
        );
        try assetdb.AssetCdb.addAspect(
            editor.UiDropObj,

            db,
            _g.asset_drop_aspect,
        );

        try assetdb.AssetCdb.addAspect(
            editor.UiVisualAspect,

            db,
            &asset_visual_aspect,
        );
        try assetdb.FolderCdb.addAspect(
            editor.UiVisualAspect,

            db,
            &folder_visual_aspect,
        );

        try assetdb.TagCdb.addAspect(
            editor_inspector.UiPropertiesConfigAspect,

            db,
            _g.noproto_config_aspect,
        );

        try assetdb.TagCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.tag_visual_aspect,
        );

        try assetdb.AssetCdb.addPropertyAspect(
            editor_inspector.UiInspectorPropertyValueAspect,

            db,
            .Tags,
            _g.tag_prop_aspect,
        );

        AssetTypeIdx = assetdb.AssetCdb.typeIdx(db);
        FolderTypeIdx = assetdb.FolderCdb.typeIdx(db);
        ProjectTypeIdx = assetdb.ProjectCdb.typeIdx(db);
    }
});

const api = public.EditorAssetDBAPI{
    .tagsInput = tagsInput,
};

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;

    // basic
    _allocator = allocator;
    public.api = &api;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.setOrRemoveZigApi(module_name, public.EditorAssetDBAPI, &api, load);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &move_to_context_menu_i, load);
    // try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &rename_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &debug_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &delete_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &create_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &reviel_in_os, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &create_from_context_menu_i, load);
    try apidb.implOrRemove(module_name, public.CreateAssetI, &create_folder_i, load);
    try apidb.implOrRemove(module_name, public.CreateAssetI, &create_tag_asset_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    _g.asset_tree_aspect = try apidb.setGlobalVarValue(editor_tree.UiTreeAspect, module_name, "ct_asset_tree_aspect", asset_ui_tree_aspect);
    _g.asset_drop_aspect = try apidb.setGlobalVarValue(editor.UiDropObj, module_name, "ct_asset_drop_aspect", asset_drop_obj_asspect);
    _g.noproto_config_aspect = try apidb.setGlobalVarValue(editor_inspector.UiPropertiesConfigAspect, module_name, "ct_project_setings_properties_config_aspect", folder_properties_config_aspect);
    _g.tag_prop_aspect = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_tags_property_aspect", tag_prop_aspect);
    _g.tag_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_tag_visual_aspect", tag_visual_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_assetdb(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
