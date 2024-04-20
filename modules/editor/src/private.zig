const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor.zig");

const cetech1 = @import("cetech1");
const apidb = cetech1.apidb;
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const strid = cetech1.strid;

const Icons = coreui.CoreIcons;

const module_name = .editor;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
var _apidb: *const apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _coreui: *const coreui.CoreUIApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _system: *const cetech1.system.SystemApi = undefined;

const TabsSelectedObject = std.AutoArrayHashMap(*public.EditorTabI, cdb.ObjId);
const TabsMap = std.AutoArrayHashMap(*anyopaque, *public.EditorTabI);
const TabsIdPool = cetech1.mem.IdPool(u32);
const TabsIds = std.AutoArrayHashMap(strid.StrId32, TabsIdPool);

const ContextToLabel = std.AutoArrayHashMap(strid.StrId64, [:0]const u8);

const REPO_URL = "https://github.com/cyberegoorg/cetech1";
const ONLINE_DOCUMENTATION = "https://cyberegoorg.github.io/cetech1/about.html";

// Global state
const G = struct {
    main_db: cdb.Db = undefined,
    show_demos: bool = false,
    show_testing_window: bool = false,
    show_external_credits: bool = false,
    show_authors: bool = false,
    enable_colors: bool = true,
    tabs: TabsMap = undefined,
    tabids: TabsIds = undefined,
    last_focused_tab: ?*public.EditorTabI = null,
    tab2selectedobj: TabsSelectedObject = undefined,
    last_selected_obj: cdb.ObjId = undefined,

    context2label: ContextToLabel = undefined,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};
var _g: *G = undefined;

pub var api = public.EditorAPI{
    .propagateSelection = propagateSelection,
    .openTabWithPinnedObj = openTabWithPinnedObj,
    .getAllTabsByType = getAllTabsByType,
    .showObjContextMenu = showObjContextMenu,
    .buffFormatObjLabel = buffFormatObjLabel,
    .getObjColor = getObjColor,
    .getAssetColor = getAssetColor,
    .isColorsEnabled = isColorsEnabled,
    .getPropertyColor = getPropertyColor,
    .selectObjFromMenu = selectObjFromMenu,
};

fn selectObjFromMenu(allocator: std.mem.Allocator, db: cdb.Db, ignored_obj: cdb.ObjId, allowed_type: cdb.TypeIdx) ?cdb.ObjId {
    const tabs = _g.tabs.values();
    for (tabs) |tab| {
        if (tab.vt.select_obj_from_menu) |select_obj_from_menu| {
            const result = select_obj_from_menu(allocator, tab.inst, db, ignored_obj, allowed_type) catch return null;
            if (!result.isEmpty()) return result;
        }
    }

    return null;
}

fn isColorsEnabled() bool {
    return _g.enable_colors;
}

const PROTOTYPE_PROPERTY_OVERIDED_COLOR = .{ 0.0, 0.8, 1.0, 1.0 };
const PROTOTYPE_PROPERTY_COLOR = .{ 0.5, 0.5, 0.5, 1.0 };

fn getPropertyColor(db: cdb.Db, obj: cdb.ObjId, prop_idx: u32) ?[4]f32 {
    if (!isColorsEnabled()) return _coreui.getStyle().getColor(.text);

    const obj_r = db.readObj(obj).?;

    const prototype_obj = db.getPrototype(db.readObj(obj).?);
    const has_prototype = !prototype_obj.isEmpty();

    var color: ?[4]f32 = null;
    if (has_prototype) {
        color = PROTOTYPE_PROPERTY_COLOR;
        if (db.isPropertyOverrided(obj_r, prop_idx)) {
            const prop_type = db.getTypePropDef(obj.type_idx).?[prop_idx].type;

            if (prop_type == .SUBOBJECT) {
                const subobj = db.readSubObj(obj_r, prop_idx).?;
                const subobj_r = db.readObj(subobj).?;
                if (db.isIinisiated(obj_r, prop_idx, subobj_r)) {
                    color = INSIATED_COLOR;
                }
            } else {
                color = PROTOTYPE_PROPERTY_OVERIDED_COLOR;
            }
        }
    }
    return color;
}

fn getAssetColor(db: cdb.Db, obj: cdb.ObjId) [4]f32 {
    if (!_g.enable_colors) return _coreui.getStyle().getColor(.text);

    if (assetdb.Asset.isSameType(db, obj)) {
        const is_modified = _assetdb.isAssetModified(obj);
        const is_deleted = _assetdb.isToDeleted(obj);

        if (is_modified) {
            return coreui.Colors.Modified;
        } else if (is_deleted) {
            return coreui.Colors.Deleted;
        }
        const r = db.readObj(obj).?;

        if (assetdb.Asset.readSubObj(db, r, .Object)) |asset_obj| {
            return getObjColor(db, asset_obj, null, null);
        }
    }

    return _coreui.getStyle().getColor(.text);
}

const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };

fn getObjColor(db: cdb.Db, obj: cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cdb.ObjId) [4]f32 {
    if (!_g.enable_colors) return _coreui.getStyle().getColor(.text);

    if (prop_idx != null and in_set_obj != null) {
        const obj_r = db.readObj(obj).?;
        const is_inisiated = db.isIinisiated(obj_r, prop_idx.?, db.readObj(in_set_obj.?).?);
        if (is_inisiated) return INSIATED_COLOR;
    }

    if (in_set_obj) |s_obj| {
        if (db.getAspect(public.UiVisualAspect, s_obj.type_idx)) |aspect| {
            if (aspect.ui_color) |color| {
                return color(db, s_obj) catch _coreui.getStyle().getColor(.text);
            }
        }
    } else {
        if (db.getAspect(public.UiVisualAspect, obj.type_idx)) |aspect| {
            if (aspect.ui_color) |color| {
                return color(db, obj) catch _coreui.getStyle().getColor(.text);
            }
        }
    }
    return _coreui.getStyle().getColor(.text);
}

fn buffFormatObjLabel(allocator: std.mem.Allocator, buff: [:0]u8, db: cdb.Db, obj: cdb.ObjId, with_id: bool) ?[:0]u8 {
    var label: [:0]u8 = undefined;
    if (db.getAspect(public.UiVisualAspect, obj.type_idx)) |aspect| {
        var name: []const u8 = undefined;
        defer allocator.free(name);

        if (aspect.ui_name) |ui_name| {
            name = ui_name(allocator, db, obj) catch return null;
        } else {
            const asset_obj = _assetdb.getAssetForObj(obj).?;
            const obj_r = db.readObj(asset_obj).?;

            if (_assetdb.isAssetFolder(obj)) {
                const asset_name = assetdb.Asset.readStr(db, obj_r, .Name) orelse "ROOT";
                name = std.fmt.allocPrintZ(
                    allocator,
                    "{s}",
                    .{
                        asset_name,
                    },
                ) catch "";
            } else {
                const asset_name = assetdb.Asset.readStr(db, obj_r, .Name) orelse "No NAME =()";
                const type_name = db.getTypeName(asset_obj.type_idx).?;
                name = std.fmt.allocPrintZ(
                    allocator,
                    "{s}.{s}",
                    .{
                        asset_name,
                        type_name,
                    },
                ) catch "";
            }
        }

        if (aspect.ui_icons) |icons| {
            const icon = icons(allocator, db, obj) catch return null;
            defer allocator.free(icon);

            if (with_id) {
                label = std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}###{s}", .{ icon, name, name }) catch return null;
            } else {
                label = std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}", .{ icon, name }) catch return null;
            }
        } else {
            if (with_id) {
                label = std.fmt.bufPrintZ(buff, "{s}###{s}", .{ name, name }) catch return null;
            } else {
                label = std.fmt.bufPrintZ(buff, "{s}", .{name}) catch return null;
            }
        }
    } else {
        return null;
    }

    return label;
}

fn showObjContextMenu(
    allocator: std.mem.Allocator,
    db: cdb.Db,
    tab: *public.TabO,
    contexts: []const strid.StrId64,
    obj_or_selection: cdb.ObjId,
    prop_idx: ?u32,
    in_set_obj: ?cdb.ObjId,
) !void {
    var selection = obj_or_selection;
    var obj = obj_or_selection;

    if (!coreui.ObjSelection.isSameType(db, obj_or_selection)) {
        selection = try coreui.ObjSelection.createObject(db);
        const w = coreui.ObjSelection.write(db, selection).?;
        try coreui.ObjSelection.addRefToSet(db, w, .Selection, &.{obj_or_selection});
        try coreui.ObjSelection.commit(db, w);
    } else {
        obj = _coreui.getFirstSelected(allocator, db, selection);
    }

    defer {
        if (!coreui.ObjSelection.isSameType(db, obj_or_selection)) {
            db.destroyObject(selection);
        }
    }

    _g.filter = _coreui.uiFilter(&_g.filter_buff, _g.filter);

    // Property based context
    if (prop_idx) |pidx| {
        const prop_defs = db.getTypePropDef(obj.type_idx).?;
        const prop_def = prop_defs[pidx];

        if (in_set_obj) |set_obj| {
            const obj_r = db.readObj(obj) orelse return;

            if (db.canIinisiated(obj_r, db.readObj(set_obj).?)) {
                if (_coreui.menuItem(allocator, coreui.Icons.Instansiate ++ "  " ++ "Instansiate" ++ "###Inisiate", .{}, null)) {
                    const w = db.writeObj(obj).?;
                    _ = try db.instantiateSubObjFromSet(w, pidx, set_obj);
                    try db.writeCommit(w);
                }

                _coreui.separator();
            }

            {
                _coreui.pushStyleColor4f(.{ .idx = .text, .c = coreui.Colors.Remove });
                defer _coreui.popStyleColor(.{});
                if (_coreui.menuItem(allocator, coreui.Icons.Remove ++ "  " ++ "Remove" ++ "###Remove", .{}, null)) {
                    const w = db.writeObj(obj).?;
                    if (prop_def.type == .REFERENCE_SET) {
                        try db.removeFromRefSet(w, pidx, set_obj);
                    } else {
                        const subobj_w = db.writeObj(set_obj).?;
                        try db.removeFromSubObjSet(w, pidx, subobj_w);
                        try db.writeCommit(subobj_w);
                    }

                    try db.writeCommit(w);
                }
            }
        } else {
            if (prop_def.type == .SUBOBJECT_SET or prop_def.type == .REFERENCE_SET) {
                if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ "  " ++ "Add to set" ++ "###AddToSet", true, null)) {
                    defer _coreui.endMenu();

                    const set_menus_aspect = db.getPropertyAspect(public.UiSetMenusAspect, obj.type_idx, pidx);
                    if (set_menus_aspect) |aspect| {
                        aspect.add_menu(&allocator, db, obj, pidx);
                    } else {
                        if (prop_def.type == .REFERENCE_SET) {
                            if (selectObjFromMenu(
                                allocator,
                                db,
                                _assetdb.getObjForAsset(obj) orelse obj,
                                db.getTypeIdx(prop_def.type_hash) orelse .{},
                            )) |selected| {
                                const w = db.writeObj(obj).?;
                                try db.addRefToSet(w, pidx, &.{selected});
                                try db.writeCommit(w);
                            }
                        } else {
                            if (prop_def.type_hash.id != 0) {
                                if (_coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Add new" ++ "###AddNew", .{}, null)) {
                                    const w = db.writeObj(obj).?;

                                    const new_obj = try db.createObject(db.getTypeIdx(prop_def.type_hash).?);
                                    const new_obj_w = db.writeObj(new_obj).?;

                                    try db.addSubObjToSet(w, pidx, &.{new_obj_w});

                                    try db.writeCommit(new_obj_w);
                                    try db.writeCommit(w);
                                }
                            }
                        }
                    }
                }
            } else if (prop_def.type == .SUBOBJECT) {
                const obj_r = db.readObj(obj) orelse return;

                if (db.readSubObj(obj_r, pidx)) |subobj| {
                    const subobj_r = db.readObj(subobj).?;

                    if (db.canIinisiated(obj_r, subobj_r)) {
                        if (_coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Inisiate" ++ "###Inisiate", .{}, null)) {
                            const w = db.writeObj(obj).?;
                            _ = try db.instantiateSubObj(w, pidx);
                            try db.writeCommit(w);
                        }
                    }
                } else {
                    if (prop_def.type_hash.id != 0) {
                        if (_coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Add new", .{}, null)) {
                            const w = db.writeObj(obj).?;

                            const new_obj = try db.createObject(db.getTypeIdx(prop_def.type_hash).?);
                            const new_obj_w = db.writeObj(new_obj).?;

                            try db.setSubObj(w, pidx, new_obj_w);

                            try db.writeCommit(new_obj_w);
                            try db.writeCommit(w);
                        }
                    }
                }
            }
        }

        // Obj based context
    } else {
        var context_counter = std.AutoArrayHashMap(strid.StrId64, std.ArrayList(*const public.ObjContextMenuI)).init(allocator);
        defer {
            for (context_counter.values()) |*v| {
                v.deinit();
            }
            context_counter.deinit();
        }

        var it = _apidb.getFirstImpl(public.ObjContextMenuI);
        while (it) |node| : (it = node.next) {
            const iface = apidb.ApiDbAPI.toInterface(public.ObjContextMenuI, node);
            if (iface.*.is_valid) |is_valid| {
                for (contexts) |context| {
                    if (is_valid(
                        allocator,
                        db,
                        tab,
                        context,
                        selection,
                        prop_idx,
                        in_set_obj,
                        _g.filter,
                    ) catch false) {
                        if (!context_counter.contains(context)) {
                            try context_counter.put(context, std.ArrayList(*const public.ObjContextMenuI).init(allocator));
                        }
                        var array = context_counter.getPtr(context).?;
                        try array.append(iface);
                    }
                }
            }
        }

        for (contexts) |context| {
            if (context_counter.get(context)) |iface_list| {
                if (iface_list.items.len == 0) continue;

                const label = _g.context2label.get(context) orelse "";
                if (label.len != 0) {
                    _coreui.separatorText(label);
                }

                for (iface_list.items) |iface| {
                    if (iface.*.menu) |menu| {
                        try menu(
                            allocator,
                            db,
                            tab,
                            context,
                            selection,
                            prop_idx,
                            in_set_obj,
                            _g.filter,
                        );
                    }
                }
            }
        }
    }
}

fn getAllTabsByType(allocator: std.mem.Allocator, tab_type_hash: strid.StrId32) ![]*public.EditorTabI {
    var result = std.ArrayList(*public.EditorTabI).init(allocator);
    defer result.deinit();

    const tabs = _g.tabs.values();

    for (tabs) |tab| {
        if (tab.vt.*.tab_hash.id != tab_type_hash.id) continue;
        try result.append(tab);
    }

    return result.toOwnedSlice();
}

fn openTabWithPinnedObj(db: cdb.Db, tab_type_hash: strid.StrId32, obj: cdb.ObjId) void {
    if (createNewTab(tab_type_hash)) |new_tab| {
        const selection = coreui.ObjSelection.createObject(db) catch undefined;
        _coreui.addToSelection(db, selection, obj) catch undefined;
        tabSelectObj(db, selection, new_tab);
        new_tab.pinned_obj = selection;
    }
}

fn tabSelectObj(db: cdb.Db, obj: cdb.ObjId, tab: *public.EditorTabI) void {
    _g.tab2selectedobj.put(tab, obj) catch undefined;
    if (tab.vt.*.obj_selected) |obj_selected| {
        obj_selected(tab.inst, db, .{ .id = obj.id, .type_idx = .{ .idx = obj.type_idx.idx } }) catch undefined;
    }
}

fn propagateSelection(db: cdb.Db, obj: cdb.ObjId) void {
    for (_g.tabs.values()) |tab| {
        if (!tab.pinned_obj.isEmpty()) continue;
        tabSelectObj(db, obj, tab);
    }
    _g.last_selected_obj = obj;
}

fn alocateTabId(tab_hash: strid.StrId32) !u32 {
    var get_or_put = try _g.tabids.getOrPut(tab_hash);
    if (!get_or_put.found_existing) {
        const pool = TabsIdPool.init(_allocator);
        get_or_put.value_ptr.* = pool;
    }

    return get_or_put.value_ptr.create(null);
}

fn dealocateTabId(tab_hash: strid.StrId32, tabid: u32) !void {
    var pool = _g.tabids.getPtr(tab_hash).?;
    try pool.destroy(tabid);
}

fn createNewTab(tab_hash: strid.StrId32) ?*public.EditorTabI {
    var it = _apidb.getFirstImpl(public.EditorTabTypeI);
    while (it) |node| : (it = node.next) {
        const iface = apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);
        if (iface.tab_hash.id != tab_hash.id) continue;

        const tab_inst = (iface.*.create(_g.main_db) catch null) orelse continue;
        _g.tabs.put(tab_inst.*.inst, tab_inst) catch undefined;
        tab_inst.*.tabid = alocateTabId(.{ .id = tab_inst.*.vt.*.tab_hash.id }) catch undefined;
        return tab_inst;
    }
    return null;
}

fn destroyTab(tab: *public.EditorTabI) void {
    if (!tab.pinned_obj.isEmpty()) {
        _g.main_db.destroyObject(tab.pinned_obj);
    }

    if (_g.last_focused_tab == tab) {
        _g.last_focused_tab = null;
    }

    dealocateTabId(.{ .id = tab.vt.*.tab_hash.id }, tab.tabid) catch undefined;
    _ = _g.tabs.swapRemove(tab.inst);
    tab.vt.destroy(tab) catch undefined;
}

const modal_quit = "Quit?###quit_unsaved_modal";
var show_quit_modal = false;
fn quitSaveModal() !void {
    if (show_quit_modal) {
        _coreui.openPopup(modal_quit, .{});
    }

    if (_coreui.beginPopupModal(
        modal_quit,
        .{ .flags = .{
            .always_auto_resize = true,
            .no_saved_settings = true,
        } },
    )) {
        defer _coreui.endPopup();

        _coreui.text("Project have unsaved changes.\nWhat do you do?");

        _coreui.separator();

        if (_coreui.button(coreui.Icons.SaveAll ++ "  " ++ coreui.Icons.Quit ++ "  " ++ "Save and Quit", .{})) {
            show_quit_modal = false;
            _coreui.closeCurrentPopup();

            const allocator = _tempalloc.create() catch undefined;
            defer _tempalloc.destroy(allocator);

            try _assetdb.saveAllModifiedAssets(allocator);
            _kernel.quit();
        }

        _coreui.sameLine(.{});
        if (_coreui.button(coreui.Icons.Quit ++ "  " ++ "Quit", .{})) {
            show_quit_modal = false;
            _coreui.closeCurrentPopup();
            _kernel.quit();
        }

        _coreui.sameLine(.{});
        if (_coreui.button(coreui.Icons.Nothing ++ "" ++ "Nothing", .{})) {
            show_quit_modal = false;
            _coreui.closeCurrentPopup();
        }
    }
}

fn tryQuit() void {
    if (_assetdb.isProjectModified()) {
        show_quit_modal = true;
    } else {
        _kernel.quit();
    }
}

fn doMainMenu(allocator: std.mem.Allocator) !void {
    _coreui.beginMainMenuBar();
    defer _coreui.endMainMenuBar();
    if (_coreui.beginMenu(allocator, coreui.Icons.Editor, true, null)) {
        defer _coreui.endMenu();

        if (_coreui.menuItem(allocator, coreui.Icons.OpenProject ++ "  " ++ "Open project", .{ .enabled = _coreui.supportFileDialog() }, null)) {
            var buf: [256:0]u8 = undefined;
            const str = try std.fs.cwd().realpath(".", &buf);
            buf[str.len] = 0;

            if (try _coreui.openFileDialog(allocator, &.{.{ .name = "Project file", .spec = assetdb.Project.name }}, @ptrCast(&buf))) |path| {
                defer allocator.free(path);
                const dir = std.fs.path.dirname(path).?;
                propagateSelection(_g.main_db, cdb.OBJID_ZERO);
                _kernel.openAssetRoot(dir);
            }
        }

        if (_coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Save all", .{ .enabled = _assetdb.isProjectOpened() and _assetdb.isProjectModified() }, null)) {
            try _assetdb.saveAllModifiedAssets(allocator);
        }

        if (_coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Save project as", .{ .enabled = _coreui.supportFileDialog() }, null)) {
            var buf: [256:0]u8 = undefined;
            const str = try std.fs.cwd().realpath(".", &buf);
            buf[str.len] = 0;
            if (try _coreui.openFolderDialog(allocator, @ptrCast(&buf))) |path| {
                defer allocator.free(path);
                try _assetdb.saveAsAllAssets(allocator, path);
                _kernel.openAssetRoot(path);
            }
        }

        _coreui.separator();

        if (_coreui.menuItem(allocator, coreui.Icons.Restart ++ "  " ++ "Restart", .{ .enabled = true }, null)) {
            _kernel.restart();
        }

        _coreui.separator();

        if (_coreui.menuItem(allocator, coreui.Icons.Quit ++ "  " ++ "Quit", .{}, null)) tryQuit();
    }

    try doTabMainMenu(allocator);

    if (_coreui.beginMenu(allocator, coreui.Icons.Settings, true, null)) {
        defer _coreui.endMenu();
        _ = _coreui.menuItemPtr(allocator, coreui.Icons.Colors ++ "  " ++ "Colors", .{ .selected = &_g.enable_colors }, null);

        // TODO: but neeed imgui docking
        // if (_coreui.beginMenu(allocator, coreui.Icons.TickRate ++ "  " ++ "Scale factor", true, null)) {
        //     defer _coreui.endMenu();
        //     var scale_factor = _coreui.getScaleFactor();
        //     if (_coreui.inputF32("###kernel_tick_rate", .{ .v = &scale_factor, .flags = .{ .enter_returns_true = true } })) {
        //         _coreui.setScaleFactor(scale_factor);
        //     }
        // }

        if (_coreui.beginMenu(allocator, coreui.Icons.TickRate ++ "  " ++ "Kernel tick rate", true, null)) {
            defer _coreui.endMenu();

            var rate = _kernel.getKernelTickRate();
            if (_coreui.inputU32("###kernel_tick_rate", .{ .v = &rate, .flags = .{ .enter_returns_true = true } })) {
                _kernel.setKernelTickRate(rate);
            }
        }
    }

    if (_coreui.beginMenu(allocator, coreui.Icons.Debug, true, null)) {
        defer _coreui.endMenu();

        _ = _coreui.menuItemPtr(allocator, coreui.Icons.UITest ++ "  " ++ "Test UI", .{ .selected = &_g.show_testing_window }, null);

        _coreui.separator();

        _ = _coreui.menuItemPtr(allocator, "ImGUI demos", .{ .selected = &_g.show_demos }, null);

        _coreui.separator();
        if (_coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Force save all", .{ .enabled = _assetdb.isProjectOpened() }, null)) {
            try _assetdb.saveAllAssets(allocator);
        }
    }

    if (_coreui.beginMenu(allocator, coreui.Icons.Help, true, null)) {
        defer _coreui.endMenu();

        if (_coreui.menuItem(allocator, coreui.Icons.Link ++ "  " ++ "GitHub", .{}, null)) {
            try _system.openIn(allocator, .open_url, REPO_URL);
        }

        if (_coreui.menuItem(allocator, coreui.Icons.Link ++ "  " ++ "Docs (online)", .{}, null)) {
            try _system.openIn(allocator, .open_url, ONLINE_DOCUMENTATION);
        }

        _coreui.separator();

        _ = _coreui.menuItemPtr(allocator, coreui.Icons.Authors ++ "  " ++ "Authors", .{ .selected = &_g.show_authors }, null);
        _ = _coreui.menuItemPtr(allocator, coreui.Icons.Externals ++ "  " ++ "Externals", .{ .selected = &_g.show_external_credits }, null);
    }
}

fn doTabMainMenu(allocator: std.mem.Allocator) !void {
    if (_coreui.beginMenu(allocator, coreui.Icons.Windows, true, null)) {
        defer _coreui.endMenu();
        if (_coreui.beginMenu(allocator, coreui.Icons.OpenTab ++ "  " ++ "Create", true, null)) {
            defer _coreui.endMenu();

            // Create tabs
            var it = _apidb.getFirstImpl(public.EditorTabTypeI);
            while (it) |node| : (it = node.next) {
                const iface = apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);
                const menu_name = try iface.menu_name();

                const tab_type_menu_name = menu_name;
                if (_coreui.menuItem(allocator, tab_type_menu_name, .{}, null)) {
                    const tab_inst = createNewTab(.{ .id = iface.tab_hash.id });
                    _ = tab_inst;
                }
            }
        }

        if (_coreui.beginMenu(allocator, coreui.Icons.CloseTab ++ "  " ++ "Close", _g.tabs.count() != 0, null)) {
            defer _coreui.endMenu();

            var tabs = std.ArrayList(*public.EditorTabI).init(allocator);
            defer tabs.deinit();
            try tabs.appendSlice(_g.tabs.values());

            for (tabs.items) |tab| {
                var buf: [128]u8 = undefined;
                const tab_title_full = try std.fmt.bufPrintZ(&buf, "{s} {d}", .{ try tab.vt.*.menu_name(), tab.tabid });
                if (_coreui.menuItem(allocator, tab_title_full, .{}, null)) {
                    destroyTab(tab);
                }
            }
        }
    }
}

fn doTabs(tmp_allocator: std.mem.Allocator) !void {
    var tabs = std.ArrayList(*public.EditorTabI).init(tmp_allocator);
    defer tabs.deinit();
    try tabs.appendSlice(_g.tabs.values());

    for (tabs.items) |tab| {
        var tab_open = true;

        const tab_title = try tab.vt.title(tab.inst);

        const tab_selected_object = _g.tab2selectedobj.get(tab);
        var asset_name_buf: [128]u8 = undefined;
        var asset_name: ?[]u8 = null;

        if (tab.vt.*.show_sel_obj_in_title) {
            if (tab_selected_object) |selected_obj| {
                if (selected_obj.isEmpty()) continue;
                const fo = _coreui.getFirstSelected(tmp_allocator, _g.main_db, selected_obj);
                if (!fo.isEmpty()) {
                    if (_assetdb.getAssetForObj(fo)) |asset| {
                        const type_name = _g.main_db.getTypeName(asset.type_idx).?;
                        if (assetdb.Asset.readStr(_g.main_db, _g.main_db.readObj(asset).?, .Name)) |asset_name_str| {
                            asset_name = try std.fmt.bufPrint(&asset_name_buf, "- {s}.{s}", .{ asset_name_str, type_name });
                        }
                    }
                }
            }
        }

        // {s}###{} => ### use last part as id and survive label change. ## use lable+id
        var buf: [128]u8 = undefined;
        const tab_title_full = try std.fmt.bufPrintZ(
            &buf,
            "{s} {d} " ++ "{s}" ++ "###{s}_{d}",
            .{
                tab_title,
                tab.tabid,
                if (asset_name) |n| n else "",
                tab.vt.tab_name,
                tab.tabid,
            },
        );

        const tab_flags = coreui.WindowFlags{
            .menu_bar = tab.vt.*.menu != null,
            //.no_saved_settings = true,
        };
        _coreui.setNextWindowSize(.{ .w = 200, .h = 200, .cond = .first_use_ever });
        if (_coreui.begin(tab_title_full, .{ .popen = &tab_open, .flags = tab_flags })) {
            if (_coreui.isWindowFocused(coreui.FocusedFlags.root_and_child_windows)) {
                if (_g.last_focused_tab != tab) {
                    _g.last_focused_tab = tab;
                    if (tab.vt.*.focused) |focused| {
                        try focused(tab.inst);
                    }
                }
            }

            // Draw menu if needed.
            if (tab.vt.*.menu) |tab_menu| {
                _coreui.beginMenuBar();
                defer _coreui.endMenuBar();

                // If needed show pin object button
                if (tab.vt.*.show_pin_object) {
                    var new_pinned = !tab.pinned_obj.isEmpty();
                    if (_coreui.menuItemPtr(tmp_allocator, if (!tab.pinned_obj.isEmpty()) Icons.FA_LOCK else Icons.FA_LOCK_OPEN ++ "", .{ .selected = &new_pinned }, null)) {
                        // Unpin
                        if (!new_pinned) {
                            _g.main_db.destroyObject(tab.pinned_obj);
                            tab.pinned_obj = .{};
                            tabSelectObj(_g.main_db, _g.last_selected_obj, tab);
                        } else {
                            const tab_selection = _g.last_selected_obj; //_g.tab2selectedobj.get(tab) orelse continue;
                            const selection = _g.main_db.cloneObject(tab_selection) catch undefined;
                            tabSelectObj(_g.main_db, selection, tab);
                            tab.pinned_obj = selection;
                        }
                    }
                }

                try tab_menu(tab.inst);
            }

            // Draw content if needed.

            try tab.vt.*.ui(tab.inst);
        }
        _coreui.end();

        if (!tab_open) {
            destroyTab(tab);
        }
    }
}

var coreui_ui_i = coreui.CoreUII.implement(struct {
    pub fn ui(allocator: std.mem.Allocator) !void {
        _ = _coreui.mainDockSpace(coreui.DockNodeFlags{ .passthru_central_node = true });

        try doMainMenu(allocator);
        try quitSaveModal();
        try doTabs(allocator);

        if (_g.show_demos) _coreui.showDemoWindow();
        _coreui.showTestingWindow(&_g.show_testing_window);
        _coreui.showExternalCredits(&_g.show_external_credits);
        _coreui.showAuthors(&_g.show_authors);
    }
});

var editor_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Editor",
    &[_]strid.StrId64{},
    struct {
        pub fn init() !void {
            _g.main_db = _kernel.getDb();
            _g.tabs = TabsMap.init(_allocator);
            _g.tabids = TabsIds.init(_allocator);
            _g.tab2selectedobj = TabsSelectedObject.init(_allocator);
            _g.context2label = ContextToLabel.init(_allocator);

            // Create tab that has create_on_init == true. Primary for basic toolchain
            var it = _apidb.getFirstImpl(public.EditorTabTypeI);
            while (it) |node| : (it = node.next) {
                const iface = apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);
                if (iface.create_on_init) {
                    _ = createNewTab(.{ .id = iface.tab_hash.id });
                }
            }

            try _g.context2label.put(public.Contexts.edit, "Edit");
            try _g.context2label.put(public.Contexts.create, "Create");
            try _g.context2label.put(public.Contexts.delete, "Delete");
            try _g.context2label.put(public.Contexts.open, "Open");
            try _g.context2label.put(public.Contexts.debug, "Debug");
        }

        pub fn shutdown() !void {
            var tabs = std.ArrayList(*public.EditorTabI).init(_allocator);
            defer tabs.deinit();
            try tabs.appendSlice(_g.tabs.values());

            for (tabs.items) |tab| {
                destroyTab(tab);
            }

            for (_g.tabids.values()) |*value| {
                value.deinit();
            }

            _g.tabs.deinit();
            _g.tabids.deinit();
            _g.tab2selectedobj.deinit();
            _g.context2label.deinit();
        }
    },
);

fn kernelQuitHandler() bool {
    tryQuit();
    return true;
}

var open_in_context_menu_i = public.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        db: cetech1.cdb.Db,
        tab: *public.TabO,
        context: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;

        if (context.id != public.Contexts.open.id) return false;
        var pass = true;

        if (filter) |f| {
            pass = false;
            var it = _apidb.getFirstImpl(public.EditorTabTypeI);
            while (it) |node| : (it = node.next) {
                const iface = apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);

                if (iface.can_open) |can_open| {
                    if (try can_open(db, selection)) {
                        const name = try iface.menu_name();
                        if (_coreui.uiFilterPass(allocator, f, name, false) != null) {
                            pass = true;
                        }
                    }
                }
            }
        }

        return pass;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        db: cetech1.cdb.Db,
        tab: *public.TabO,
        context: cetech1.strid.StrId64,
        selection: cetech1.cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cetech1.cdb.ObjId,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;
        _ = prop_idx;
        _ = in_set_obj;

        var it = _apidb.getFirstImpl(public.EditorTabTypeI);
        while (it) |node| : (it = node.next) {
            const iface = apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);

            if (iface.can_open) |can_open| {
                if (try can_open(db, selection)) {
                    const name = try iface.menu_name();

                    var buff: [128]u8 = undefined;
                    const label = std.fmt.bufPrintZ(&buff, "{s}###OpenIn_{s}", .{ name, iface.tab_name }) catch undefined;

                    if (_coreui.menuItem(allocator, label, .{}, filter)) {
                        if (_coreui.getSelected(allocator, db, selection)) |selected_objs| {
                            defer allocator.free(selected_objs);
                            for (selected_objs) |obj| {
                                openTabWithPinnedObj(db, iface.tab_hash, obj);
                            }
                        }
                    }
                }
            }
        }
    }
});

// Assetdb opened
var asset_root_opened_i = assetdb.AssetRootOpenedI.implement(struct {
    pub fn opened() !void {
        var tabs = std.ArrayList(*public.EditorTabI).init(_allocator);
        defer tabs.deinit();
        try tabs.appendSlice(_g.tabs.values());

        for (tabs.items) |tab| {
            if (tab.vt.*.create_on_init and tab.tabid == 1) {
                if (tab.vt.*.asset_root_opened) |asset_root_opened| {
                    try asset_root_opened(tab.inst);
                }
                continue;
            }
            if (tab.tabid == 1) continue;
            destroyTab(tab);
        }
    }
});

// Cdb

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb_: *const apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb_;
    _cdb = _apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = _apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _kernel = _apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _assetdb = _apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _tempalloc = _apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _system = _apidb.getZigApi(module_name, cetech1.system.SystemApi).?;

    // create global variable that can survive reload
    _g = try _apidb.globalVar(G, module_name, "_g", .{});

    try _apidb.setOrRemoveZigApi(module_name, public.EditorAPI, &api, load);

    try _apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &editor_kernel_task, load);
    try _apidb.implOrRemove(module_name, coreui.CoreUII, &coreui_ui_i, load);
    try _apidb.implOrRemove(module_name, public.ObjContextMenuI, &open_in_context_menu_i, load);
    try _apidb.implOrRemove(module_name, assetdb.AssetRootOpenedI, &asset_root_opened_i, true);

    _kernel.setCanQuit(kernelQuitHandler);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor(__apidb: *const apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {}
