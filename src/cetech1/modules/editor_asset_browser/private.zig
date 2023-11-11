const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_asset_browser";
const ASSET_BROWSER_NAME = "ct_editor_asset_browser_tab";
const ASSET_PROPERTIES_ASPECT_NAME = "ct_asset_properties_aspect";
const ASSET_TREE_ASPECT_NAME = "ct_asset_tree_aspect";
const FOLDER_NAME_PROPERTY_ASPECT_NAME = "ct_folder_name_property_aspect";
const FOLDER_TREE_ASPECT_NAME = "ct_folder_tree_aspect";

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
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;

const G = struct {
    asset_browser_tab_vt: *editor.EditorTabTypeI = undefined,
    asset_prop_aspect: *editor.UiPropertiesAspect = undefined,
    folder_name_prop_aspect: *editor.UiPropertyAspect = undefined,
    asset_tree_aspect: *editor.UiTreeAspect = undefined,
    folder_tree_aspect: *editor.UiTreeAspect = undefined,
};
var _g: *G = undefined;

const AssetBrowserTab = struct {
    tab_i: editor.EditorTabI,
    db: cetech1.cdb.CdbDb,
    selected_obj: cetech1.cdb.ObjId = .{},
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
fn tabCreate(db: *cetech1.cdb.Db) ?*editor.EditorTabI {
    var tab_inst = _allocator.create(AssetBrowserTab) catch undefined;
    tab_inst.* = AssetBrowserTab{
        .tab_i = .{
            .vt = _g.asset_browser_tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = cetech1.cdb.CdbDb.fromDbT(db, _cdb),
    };
    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: *editor.EditorTabI) void {
    var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(tab_inst.inst));
    _allocator.destroy(tab_o);
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

    var new_selected = _editor.cdbTreeView(tmp_arena.allocator(), &tab_o.db, root_folder, tab_o.selected_obj, .{ .expand_object = false }) catch undefined;
    if (new_selected) |selected| {
        tab_o.selected_obj = selected;
        _editor.selectObj(&tab_o.db, selected);
    }
}

fn tabFocused(inst: *editor.TabO) void {
    var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

    // If asset browser is focused then select obj for editor by obj selected in tab =D
    if (!tab_o.selected_obj.isEmpty()) {
        _editor.selectObj(&tab_o.db, tab_o.selected_obj);
    }
}

// Folder aspect
var folder_ui_tree_aspect = editor.UiTreeAspect.implement(folderUiTreeAspect);
fn folderUiTreeAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    selected_obj: cetech1.cdb.ObjId,
    args: editor.CdbTreeViewArgs,
) !?cetech1.cdb.ObjId {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buff: [128]u8 = undefined;

    var obj_r = db.readObj(obj) orelse return .{};

    const folder_name = cetech1.assetdb.FolderType.readStr(&db, obj_r, .Name);
    var new_selected: ?cetech1.cdb.ObjId = null;
    if (folder_name) |name| {
        const is_modified = _assetdb.isAssetModified(obj);

        var folder_label = try std.fmt.bufPrintZ(
            &buff,
            "{s}" ++ "{s}" ++ "  " ++ "{s}",
            .{
                FOLDER_ICON,
                if (is_modified) " " ++ Icons.FA_STAR_OF_LIFE else "",
                name,
            },
        );

        if (is_modified) {
            _editorui.pushStyleColor4f(.{ .idx = .text, .c = ASSET_MODIFIED_TEXT_COLOR });
        }
        const open = _editor.cdbTreeNode(folder_label, false, false, selected_obj.eq(obj), args);
        if (is_modified) {
            _editorui.popStyleColor(.{});
        }

        if (_editorui.isItemActivated()) {
            new_selected = obj;
        }

        if (_editorui.beginPopupContextItem()) {
            try objContextMenu(allocator, &db, obj);
            _editorui.endPopup();
        }

        if (_editorui.isItemHovered(.{})) {
            _editorui.beginTooltip();
            const obj_uuid = _assetdb.getUuid(obj);

            if (obj_uuid) |uuid| {
                var uuid_str = try std.fmt.bufPrintZ(&buff, "Folder UUID: {s}", .{uuid});
                _editorui.textUnformatted(uuid_str);
            }

            _editorui.endTooltip();
        }

        if (open) {
            var set = try db.getReferencerSet(obj, allocator);
            defer allocator.free(set);
            for (set) |ref_obj| {
                if (try _editor.cdbTreeView(allocator, &db, ref_obj, selected_obj, args)) |new| {
                    new_selected = new;
                }
            }

            _editor.cdbTreePop();
        }
    } else {
        var set = try db.getReferencerSet(obj, allocator);
        defer allocator.free(set);
        for (set) |ref_obj| {
            if (try _editor.cdbTreeView(allocator, &db, ref_obj, selected_obj, args)) |new| {
                new_selected = new;
            }
        }
    }
    return new_selected;
}

// Asset tree aspect
var asset_ui_tree_aspect = editor.UiTreeAspect.implement(assetUiTreeAsspect);
fn assetUiTreeAsspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    selected_obj: cetech1.cdb.ObjId,
    args: editor.CdbTreeViewArgs,
) !?cetech1.cdb.ObjId {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    var buff: [128]u8 = undefined;

    var obj_r = db.readObj(obj) orelse return .{};

    const asset_name = cetech1.assetdb.AssetType.readStr(&db, obj_r, .Name).?;
    const asset_obj = cetech1.assetdb.AssetType.readSubObj(&db, obj_r, .Object).?;
    const type_name = db.getTypeName(asset_obj.type_hash).?;

    const is_modified = _assetdb.isAssetModified(obj);

    var new_selected: ?cetech1.cdb.ObjId = null;

    var asset_label = try std.fmt.bufPrintZ(
        &buff,
        "{s} {s}  {s}.{s}",
        .{
            ASSET_ICON,
            if (is_modified) Icons.FA_STAR_OF_LIFE else "",
            asset_name,
            type_name,
        },
    );

    if (is_modified) {
        _editorui.pushStyleColor4f(.{ .idx = .text, .c = ASSET_MODIFIED_TEXT_COLOR });
    }

    if (_editorui.treeNodeFlags(asset_label, .{ .leaf = true, .selected = selected_obj.eq(obj) })) {
        if (is_modified) {
            _editorui.popStyleColor(.{});
        }

        if (_editorui.isItemActivated()) {
            new_selected = obj;
        }

        if (_editorui.beginPopupContextItem()) {
            try objContextMenu(allocator, &db, obj);
            _editorui.endPopup();
        }

        if (_editorui.isItemHovered(.{})) {
            _editorui.beginTooltip();
            const uuid = _assetdb.getUuid(obj).?;
            var uuid_str = try std.fmt.bufPrintZ(&buff, "Asset UUID: {s}", .{uuid});
            _editorui.textUnformatted(uuid_str);
            _editorui.endTooltip();
        }

        _editorui.treePop();
    }

    if (args.expand_object) {
        if (try _editor.cdbTreeView(allocator, &db, asset_obj, selected_obj, args)) |s| {
            new_selected = s;
        }
    }

    return new_selected;
}

fn buffGetValidNameForFolder(allocator: std.mem.Allocator, buf: [:0]u8, db: *cetech1.cdb.CdbDb, folder: cetech1.cdb.ObjId, type_hash: cetech1.strid.StrId32, base_name: [:0]const u8) ![:0]const u8 {
    var set = try db.getReferencerSet(folder, allocator);
    defer allocator.free(set);

    var name_set = std.StringArrayHashMap(void).init(allocator);
    defer name_set.deinit();

    if (type_hash.id != cetech1.assetdb.FolderType.type_hash.id) {
        for (set) |obj| {
            if (obj.type_hash.id != cetech1.assetdb.AssetType.type_hash.id) continue;

            var asset_obj = cetech1.assetdb.AssetType.readSubObj(db, db.readObj(obj).?, .Object).?;
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

fn isAssetNameValid(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, folder: cetech1.cdb.ObjId, type_hash: cetech1.strid.StrId32, base_name: [:0]const u8) !bool {
    var set = try db.getReferencerSet(folder, allocator);
    defer allocator.free(set);

    var name_set = std.StringArrayHashMap(void).init(allocator);
    defer name_set.deinit();

    if (type_hash.id != cetech1.assetdb.FolderType.type_hash.id) {
        for (set) |obj| {
            if (obj.type_hash.id != cetech1.assetdb.AssetType.type_hash.id) continue;

            var asset_obj = cetech1.assetdb.AssetType.readSubObj(db, db.readObj(obj).?, .Object).?;
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

    return !name_set.contains(base_name);
}

fn createNewFolder(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selected_obj: cetech1.cdb.ObjId) !void {
    var parent_folder: cetech1.cdb.ObjId = cetech1.cdb.OBJID_ZERO;

    if (selected_obj.type_hash.id == cetech1.assetdb.FolderType.type_hash.id) {
        parent_folder = selected_obj;
    } else {
        if (db.readObj(selected_obj)) |r| {
            parent_folder = cetech1.assetdb.AssetType.readRef(db, r, .Folder).?;
        }
    }

    if (parent_folder.isEmpty()) return;

    var buff: [256:0]u8 = undefined;
    var name = try buffGetValidNameForFolder(
        allocator,
        &buff,
        db,
        parent_folder,
        cetech1.assetdb.FolderType.type_hash,
        "NewFolder",
    );

    try _assetdb.createNewFolder(db, parent_folder, name);
}

fn objContextMenu(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) !void {
    if (_editorui.beginMenu(editor.Icons.Add ++ "  " ++ "New", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem(Icons.FA_FOLDER ++ "  " ++ "Folder", .{})) {
            try createNewFolder(allocator, db, obj);
        }
    }

    _editorui.separator();

    if (_editorui.beginMenu(editor.Icons.Open ++ "  " ++ "Open", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem("New properties editor", .{})) {
            _editor.openTabWithPinnedObj(db, cetech1.strid.strId32("ct_editor_properies_tab"), obj);
        }
    }

    if (_editorui.beginMenu(editor.Icons.CopyToClipboard ++ " " ++ "Copy to clipboard", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem("Asset UUID", .{})) {
            const uuid = _assetdb.getUuid(obj).?;
            var buff: [128]u8 = undefined;
            var uuid_str = try std.fmt.bufPrintZ(&buff, "{s}", .{uuid});
            _editorui.setClipboardText(uuid_str);
        }
    }
    _editorui.separator();

    if (_editorui.beginMenu(editor.Icons.Debug ++ "  " ++ "Debug", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem(editor.Icons.Save ++ " " ++ "Force save", .{})) {
            try _assetdb.saveAsset(allocator, obj);
        }
    }
}

//

// Asset properties aspect
var asset_properties_aspec = editor.UiPropertiesAspect.implement(assetUiProperiesAspect);
fn assetUiProperiesAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buf: [128:0]u8 = undefined;

    // Asset name
    _editor.uiPropLabel("Asset name", null);
    try _editor.uiPropInput(&db, obj, cetech1.assetdb.AssetType.propIdx(.Name));

    // Asset UUID
    _editor.uiPropLabel("Asset UUID", null);
    _editorui.separator();
    _editorui.tableNextColumn();

    const asset_uuid = _assetdb.getUuid(obj).?;
    _ = try std.fmt.bufPrintZ(&buf, "{s}", .{asset_uuid});

    _editorui.setNextItemWidth(-std.math.floatMin(f32));
    _ = _editorui.inputText("", .{
        .buf = &buf,
        .flags = .{
            .read_only = true,
            .auto_select_all = true,
        },
    });
    _editorui.separator();

    // Asset object
    try _editor.cdbPropertiesObj(allocator, &db, cetech1.assetdb.AssetType.readSubObj(&db, db.readObj(obj).?, .Object).?, .{});
}
//

// Folder properties aspect
var folder_name_prop_aspect = editor.UiPropertyAspect.implement(folderUiNameProperyAspect);
fn folderUiNameProperyAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    prop_idx: u32,
    args: editor.cdbPropertiesViewArgs,
) !void {
    _ = args;
    _ = prop_idx;

    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buf: [128:0]u8 = undefined;

    // Folder name
    //_editor.uiPropLabel("Folder name", null);

    try _editor.uiPropInputBegin(&db, obj, cetech1.assetdb.FolderType.propIdx(.Name));

    var name = cetech1.assetdb.FolderType.readStr(&db, db.readObj(obj).?, .Name);
    if (name) |str| {
        _ = try std.fmt.bufPrintZ(&buf, "{s}", .{str});
    }
    if (_editorui.inputText("", .{
        .buf = &buf,
        .flags = .{
            .enter_returns_true = true,
        },
    })) {
        var new_name_buf: [128:0]u8 = undefined;
        var new_name = try std.fmt.bufPrintZ(&new_name_buf, "{s}", .{std.mem.sliceTo(&buf, 0)});

        var parent = cetech1.assetdb.FolderType.readRef(&db, db.readObj(obj).?, .Parent).?;
        if (try isAssetNameValid(allocator, &db, parent, cetech1.assetdb.FolderType.type_hash, new_name)) {
            var w = db.writeObj(obj).?;
            defer db.writeCommit(w);
            try cetech1.assetdb.FolderType.setStr(&db, w, .Name, new_name);
        }
    }
    defer _editor.uiPropInputEnd();
}
//

// Draw tab menu
fn tabMenu(inst: *editor.TabO) void {
    var tab_o: *AssetBrowserTab = @alignCast(@ptrCast(inst));

    if (_editorui.beginMenu("Asset", !tab_o.selected_obj.isEmpty())) {
        var tmp_arena = _tempalloc.createTempArena() catch undefined;
        defer _tempalloc.destroyTempArena(tmp_arena);

        objContextMenu(tmp_arena.allocator(), &tab_o.db, tab_o.selected_obj) catch undefined;
        defer _editorui.endMenu();
    }
}

fn cdbCreateTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, _cdb);

    // FOLDER
    try cetech1.assetdb.FolderType.addAspect(
        &db,
        editor.UiTreeAspect,
        _g.folder_tree_aspect,
    );

    try cetech1.assetdb.FolderType.addPropertyAspect(
        &db,
        editor.UiPropertyAspect,
        .Parent,
        @constCast(&editor.hidePropertyAspect),
    );

    try cetech1.assetdb.FolderType.addPropertyAspect(
        &db,
        editor.UiPropertyAspect,
        .Name,
        _g.folder_name_prop_aspect,
    );

    // ASSET
    try cetech1.assetdb.AssetType.addAspect(
        &db,
        editor.UiTreeAspect,
        _g.asset_tree_aspect,
    );

    try cetech1.assetdb.AssetType.addAspect(
        &db,
        editor.UiPropertiesAspect,
        _g.asset_prop_aspect,
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

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.asset_browser_tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, ASSET_BROWSER_NAME, .{});
    _g.asset_browser_tab_vt.* = foo_tab;

    _g.asset_prop_aspect = try apidb.globalVar(editor.UiPropertiesAspect, MODULE_NAME, ASSET_PROPERTIES_ASPECT_NAME, .{});
    _g.asset_prop_aspect.* = asset_properties_aspec;

    _g.folder_name_prop_aspect = try apidb.globalVar(editor.UiPropertyAspect, MODULE_NAME, FOLDER_NAME_PROPERTY_ASPECT_NAME, .{});
    _g.folder_name_prop_aspect.* = folder_name_prop_aspect;

    _g.asset_tree_aspect = try apidb.globalVar(editor.UiTreeAspect, MODULE_NAME, ASSET_TREE_ASPECT_NAME, .{});
    _g.asset_tree_aspect.* = asset_ui_tree_aspect;

    _g.folder_tree_aspect = try apidb.globalVar(editor.UiTreeAspect, MODULE_NAME, FOLDER_TREE_ASPECT_NAME, .{});
    _g.folder_tree_aspect.* = folder_ui_tree_aspect;

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.EditorTabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_browser(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
