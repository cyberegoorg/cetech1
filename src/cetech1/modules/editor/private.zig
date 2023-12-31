const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const public = @import("editor.zig");
const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor";

const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;

const TabsSelectedObject = std.AutoArrayHashMap(*public.EditorTabI, cetech1.cdb.ObjId);
const TabsMap = std.AutoArrayHashMap(*anyopaque, *public.EditorTabI);
const TabsIdPool = cetech1.mem.IdPool(u32);
const TabsIds = std.AutoArrayHashMap(cetech1.strid.StrId32, TabsIdPool);

const ModalInstances = std.AutoArrayHashMap(cetech1.strid.StrId32, *anyopaque);

// Global state
const G = struct {
    main_db: cetech1.cdb.CdbDb = undefined,
    show_demos: bool = false,
    tabs: TabsMap = undefined,
    tabids: TabsIds = undefined,
    tab2selectedobj: TabsSelectedObject = undefined,
    last_selected_obj: cetech1.cdb.ObjId = undefined,
    last_focused_tab: ?*public.EditorTabI = null,
    modal_instances: ModalInstances = undefined,
};
var _g: *G = undefined;

pub var api = public.EditorAPI{
    .propagateSelection = propagateSelection,
    .openTabWithPinnedObj = openTabWithPinnedObj,
    .openModal = openModal,

    .buffFormatObjLabel = buffFormatObjLabel,
    .getObjColor = getObjColor,
    .objContextMenu = objContextMenu,
    .isSelected = isSelected,
    .addToSelection = addToSelection,
    .setSelection = setSelection,
    .selectedCount = selectedCount,
    .getFirstSelected = getFirstSelected,
    .getSelected = getSelected,
    .handleSelection = handleSelection,
    .removeFromSelection = removeFromSelection,
};

fn removeFromSelection(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const w = db.writeObj(selection).?;
    defer db.writeCommit(w);
    try public.ObjSelectionType.removeFromRefSet(db, w, .Selection, obj);
}

fn handleSelection(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId, multiselect_enabled: bool) !void {
    if (multiselect_enabled and _editorui.isKeyDown(.mod_super) or _editorui.isKeyDown(.mod_ctrl)) {
        if (api.isSelected(db, selection, obj)) {
            try api.removeFromSelection(db, selection, obj);
        } else {
            try api.addToSelection(db, selection, obj);
        }
    } else {
        try api.setSelection(allocator, db, selection, obj);
    }
}

fn getSelected(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) ?[]const cetech1.cdb.ObjId {
    const r = db.readObj(selection).?;
    return public.ObjSelectionType.readRefSet(db, r, .Selection, allocator);
}

fn isSelected(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) bool {
    return public.ObjSelectionType.isInSet(db, db.readObj(selection).?, .Selection, obj);
}

fn addToSelection(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const w = db.writeObj(selection).?;
    defer db.writeCommit(w);

    try public.ObjSelectionType.addRefToSet(db, w, .Selection, &.{obj});
}

fn setSelection(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const r = db.readObj(selection).?;

    const w = db.writeObj(selection).?;
    defer db.writeCommit(w);

    // TODO: clear to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |ref| {
            try public.ObjSelectionType.removeFromRefSet(db, w, .Selection, ref);
        }
    }
    try public.ObjSelectionType.addRefToSet(db, w, .Selection, &.{obj});
}

fn selectedCount(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) u32 {
    const r = db.readObj(selection).?;

    // TODO: count to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        return @truncate(set.len);
    }
    return 0;
}

fn getFirstSelected(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) cetech1.cdb.ObjId {
    const r = db.readObj(selection).?;

    // TODO: count to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |s| {
            return s;
        }
    }
    return .{};
}

fn onAddToSet(selected_data: ?*anyopaque, data: public.UiModalI.Data) callconv(.C) void {
    const selection: *cetech1.cdb.ObjId = @alignCast(@ptrCast(selected_data orelse return));

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    const params = std.mem.bytesToValue(public.SelectAssetParams, data.data[0..@sizeOf(public.SelectAssetParams)]);

    if (api.getSelected(allocator, &_g.main_db, selection.*)) |selected| {
        defer allocator.free(selected);
        const w = _g.main_db.writeObj(params.obj).?;
        defer _g.main_db.writeCommit(w);

        for (selected) |asset| {
            const asset_obj = cetech1.assetdb.AssetType.readSubObj(&_g.main_db, _g.main_db.readObj(asset).?, .Object).?;

            const propdef = _g.main_db.getTypePropDef(params.obj.type_hash).?;
            const prop_type = propdef[params.prop_idx].type;
            if (prop_type == .REFERENCE_SET) {
                _g.main_db.addRefToSet(w, params.prop_idx, &[_]cetech1.cdb.ObjId{asset_obj}) catch |err| {
                    _log.err(MODULE_NAME, "Could not add reference {} to set prop_idx {} : {}", .{ params.obj, params.prop_idx, err });
                };
            } else if (prop_type == .SUBOBJECT_SET) {
                const sub_w = _g.main_db.writeObj(asset_obj).?;
                defer _g.main_db.writeCommit(sub_w);
                _g.main_db.addSubObjToSet(w, params.prop_idx, &[_]*cetech1.cdb.Obj{sub_w}) catch |err| {
                    _log.err(MODULE_NAME, "Could not add reference {} to set prop_idx {} : {}", .{ params.obj, params.prop_idx, err });
                };
            }
        }
    }
}

fn objContextMenu(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    prop_idx: ?u32,
    in_set_obj: ?cetech1.cdb.ObjId,
) !void {
    const prop_defs = db.getTypePropDef(obj.type_hash).?;

    // Property based context
    if (prop_idx) |pidx| {
        const prop_def = prop_defs[pidx];

        if (in_set_obj) |set_obj| {
            const obj_r = db.readObj(obj) orelse return;

            const can_inisiate = db.canIinisiated(obj_r, db.readObj(set_obj).?);

            if (can_inisiate) {
                if (_editorui.menuItem(public.Icons.Add ++ "  " ++ "Inisiated", .{})) {
                    const w = db.writeObj(obj).?;
                    defer db.writeCommit(w);
                    _ = try db.instantiateSubObjFromSet(w, pidx, set_obj);
                }

                _editorui.separator();
            }

            {
                _editorui.pushStyleColor4f(.{ .idx = .text, .c = public.Colors.Remove });
                defer _editorui.popStyleColor(.{});
                if (_editorui.menuItem(public.Icons.Remove ++ "  " ++ "Remove", .{})) {
                    const w = db.writeObj(obj).?;
                    defer db.writeCommit(w);
                    if (prop_def.type == .REFERENCE_SET) {
                        try db.removeFromRefSet(w, pidx, set_obj);
                    } else {
                        const subobj_w = db.writeObj(set_obj).?;
                        defer db.writeCommit(subobj_w);
                        try db.removeFromSubObjSet(w, pidx, subobj_w);
                    }
                }
            }
        } else {
            if (prop_def.type == .SUBOBJECT_SET or prop_def.type == .REFERENCE_SET) {
                if (_editorui.beginMenu(public.Icons.Add ++ "  " ++ "Add to set", true)) {
                    defer _editorui.endMenu();

                    const set_menus_aspect = db.getPropertyAspect(public.UiSetMenus, obj.type_hash, pidx);
                    if (set_menus_aspect) |aspect| {
                        if (aspect.add_menu) |add_menu| {
                            add_menu(&allocator, db.db, obj, pidx);
                        }
                    } else {
                        if (prop_def.type == .REFERENCE_SET) {
                            if (_editorui.menuItem(public.Icons.Add ++ "  " ++ "Add Reference", .{})) {
                                const data = public.UiModalI.makeData(public.SelectAssetParams{
                                    .obj = obj,
                                    .prop_idx = pidx,
                                    .ignored_object = obj,
                                    .only_types = prop_def.type_hash,
                                    .multiselect = true,
                                    .expand = false,
                                });
                                api.openModal(public.SelectAssetModal, onAddToSet, data);
                            }
                        } else {
                            if (prop_def.type_hash.id != 0) {
                                if (_editorui.menuItem(public.Icons.Add ++ "  " ++ "Add new", .{})) {
                                    const w = db.writeObj(obj).?;
                                    defer db.writeCommit(w);

                                    const new_obj = try db.createObject(prop_def.type_hash);
                                    const new_obj_w = db.writeObj(new_obj).?;
                                    defer db.writeCommit(new_obj_w);

                                    try db.addSubObjToSet(w, pidx, &.{new_obj_w});
                                }
                            }
                        }
                    }
                }
            } else if (prop_def.type == .SUBOBJECT) {
                const obj_r = db.readObj(obj) orelse return;

                const subobj = db.readSubObj(obj_r, pidx);
                if (subobj == null) {
                    if (prop_def.type_hash.id != 0) {
                        if (_editorui.menuItem(public.Icons.Add ++ "  " ++ "Add new", .{})) {
                            const w = db.writeObj(obj).?;
                            defer db.writeCommit(w);

                            const new_obj = try db.createObject(prop_def.type_hash);
                            const new_obj_w = db.writeObj(new_obj).?;
                            defer db.writeCommit(new_obj_w);

                            try db.setSubObj(w, pidx, new_obj_w);
                        }
                    }
                }
            }
        }

        // Obj based context
    } else {}
}

fn buffFormatObjLabel(buff: [:0]u8, allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) ?[:0]u8 {
    var label: [:0]u8 = undefined;
    const ui_visual_aspect = db.getAspect(public.UiVisualAspect, obj.type_hash);
    if (ui_visual_aspect) |aspect| {
        const name = aspect.ui_name.?(&allocator, db.db, obj);
        if (aspect.ui_icons) |icons| {
            const icon = icons(&allocator, db, obj);
            label = std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}", .{ icon, name }) catch return null;
        } else {
            label = std.fmt.bufPrintZ(buff, "{s}", .{name}) catch return null;
        }
    } else {
        return null;
    }

    return label;
}

fn getObjColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cetech1.cdb.ObjId) [4]f32 {
    if (prop_idx != null and in_set_obj != null) {
        const obj_r = db.readObj(obj).?;
        const is_inisiated = db.isIinisiated(obj_r, prop_idx.?, db.readObj(in_set_obj.?).?);
        if (is_inisiated) return INSIATED_COLOR;
    }

    if (in_set_obj) |s_obj| {
        const ui_visual_aspect = db.getAspect(public.UiVisualAspect, s_obj.type_hash);
        if (ui_visual_aspect) |aspect| {
            if (aspect.ui_color) |color| {
                return color(db.db, s_obj).c;
            }
        }
    }
    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn openModal(
    modal_hash: cetech1.strid.StrId32,
    on_set: public.UiModalI.OnSetFN,
    data: public.UiModalI.Data,
) void {
    var it = _apidb.getFirstImpl(public.UiModalI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.UiModalI, node);
        if (iface.modal_hash.id != modal_hash.id) continue;
        var inst = iface.*.create.?(&_allocator, _g.main_db.db, on_set, data);
        if (inst) |valid_inst| {
            _g.modal_instances.put(iface.modal_hash, valid_inst) catch undefined;
        }
    }
}

fn openTabWithPinnedObj(db: *cetech1.cdb.CdbDb, tab_type_hash: cetech1.strid.StrId32, obj: cetech1.cdb.ObjId) void {
    if (createNewTab(tab_type_hash)) |new_tab| {
        var selection = public.ObjSelectionType.createObject(db) catch undefined;
        api.addToSelection(db, selection, obj) catch undefined;
        tabSelectObj(db, selection, new_tab);
        new_tab.pinned_obj = selection;
    }
}

fn tabSelectObj(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, tab: *public.EditorTabI) void {
    _g.tab2selectedobj.put(tab, obj) catch undefined;
    if (tab.vt.*.obj_selected) |obj_selected| {
        obj_selected(tab.inst, @ptrCast(db.db), .{ .id = obj.id, .type_hash = .{ .id = obj.type_hash.id } });
    }
}

fn propagateSelection(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void {
    std.debug.assert(public.ObjSelectionType.isSameType(obj));
    for (_g.tabs.values()) |tab| {
        if (!tab.pinned_obj.isEmpty()) continue;
        tabSelectObj(db, obj, tab);
    }
    _g.last_selected_obj = obj;
}

fn alocateTabId(tab_hash: cetech1.strid.StrId32) !u32 {
    var get_or_put = try _g.tabids.getOrPut(tab_hash);
    if (!get_or_put.found_existing) {
        var pool = TabsIdPool.init(_allocator);
        get_or_put.value_ptr.* = pool;
    }

    return get_or_put.value_ptr.create(null);
}

fn dealocateTabId(tab_hash: cetech1.strid.StrId32, tabid: u32) !void {
    var pool = _g.tabids.getPtr(tab_hash).?;
    try pool.destroy(tabid);
}

fn createNewTab(tab_hash: cetech1.strid.StrId32) ?*public.EditorTabI {
    var it = _apidb.getFirstImpl(public.EditorTabTypeI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);
        if (iface.tab_hash.id != tab_hash.id) continue;

        var tab_inst = iface.*.create.?(_g.main_db.db) orelse continue;
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
    tab.vt.destroy.?(tab);
}

const modal_quit = "Quit?###quit_unsaved_modal";
var show_quit_modal = false;
fn quitSaveModal() !void {
    if (show_quit_modal) {
        _editorui.openPopup(modal_quit, .{});
    }

    if (_editorui.beginPopupModal(
        modal_quit,
        .{ .flags = .{
            .always_auto_resize = true,
            .no_saved_settings = true,
        } },
    )) {
        defer _editorui.endPopup();

        _editorui.textUnformatted("Project have unsaved changes.\nWhat do you do?");

        _editorui.separator();

        if (_editorui.button(public.Icons.SaveAll ++ " " ++ public.Icons.Quit ++ " " ++ "Save and Quit", .{})) {
            _editorui.closeCurrentPopup();

            var tmp_arena = _tempalloc.createTempArena() catch undefined;
            defer _tempalloc.destroyTempArena(tmp_arena);

            try _assetdb.saveAllModifiedAssets(tmp_arena.allocator());
            _kernel.quit();
            show_quit_modal = false;
        }

        _editorui.sameLine(.{});
        if (_editorui.button(public.Icons.Quit ++ " " ++ "Quit", .{})) {
            _editorui.closeCurrentPopup();
            _kernel.quit();
            show_quit_modal = false;
        }

        _editorui.sameLine(.{});
        if (_editorui.button(public.Icons.Nothing ++ "" ++ "Nothing", .{})) {
            _editorui.closeCurrentPopup();
            show_quit_modal = false;
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

fn doMainMenu(alocator: std.mem.Allocator) !void {
    _editorui.beginMainMenuBar();

    if (_editorui.beginMenu("Editor", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem(public.Icons.OpenProject ++ "  " ++ "Open project", .{})) {
            var buf: [256:0]u8 = undefined;
            var str = try std.fs.cwd().realpath(".", &buf);
            buf[str.len] = 0;

            if (try _editorui.openFileDialog(cetech1.assetdb.ProjectType.name, @ptrCast(&buf))) |path| {
                defer _editorui.freePath(path);
                var dir = std.fs.path.dirname(path).?;
                propagateSelection(&_g.main_db, cetech1.cdb.OBJID_ZERO);
                _kernel.restart(dir);
            }
        }

        if (_editorui.menuItem(public.Icons.SaveAll ++ "  " ++ "Save all", .{ .enabled = _assetdb.isProjectModified() })) {
            try _assetdb.saveAllModifiedAssets(alocator);
        }

        if (_editorui.menuItem(public.Icons.SaveAll ++ "  " ++ "Save project as", .{ .enabled = true })) {
            var buf: [256:0]u8 = undefined;
            var str = try std.fs.cwd().realpath(".", &buf);
            buf[str.len] = 0;
            if (try _editorui.openFolderDialog(@ptrCast(&buf))) |path| {
                defer _editorui.freePath(path);
                try _assetdb.saveAsAllAssets(alocator, path);
                _kernel.restart(path);
            }
        }

        _editorui.separator();

        if (_editorui.menuItem(public.Icons.Quit ++ "  " ++ "Quit", .{})) tryQuit();
    }

    try doTabMainMenu(alocator);

    if (_editorui.beginMenu("Window", true)) {
        _editorui.endMenu();
    }

    if (_editorui.beginMenu(public.Icons.Debug, true)) {
        if (_editorui.menuItem(public.Icons.SaveAll ++ "  " ++ "Force save all", .{ .enabled = _assetdb.isProjectOpened() })) {
            try _assetdb.saveAllAssets(alocator);
        }

        if (_editorui.menuItem(public.Icons.Restart ++ "  " ++ "Restart", .{ .enabled = true })) {
            _kernel.restart(null);
        }

        _editorui.separator();
        _ = _editorui.menuItemPtr("ImGUI demos", .{ .selected = &_g.show_demos });

        _editorui.separatorText("Kernel tick rate");

        var rate = _kernel.getKernelTickRate();
        if (_editorui.inputU32("###kernel_tick_rate", .{ .v = &rate, .flags = .{ .enter_returns_true = true } })) {
            _kernel.setKernelTickRate(rate);
        }

        _editorui.endMenu();
    }

    _editorui.endMainMenuBar();
}

fn doTabMainMenu(alocator: std.mem.Allocator) !void {
    if (_editorui.beginMenu("Tabs", true)) {
        if (_editorui.beginMenu(public.Icons.OpenTab ++ "  " ++ "Create", true)) {
            // Create tabs
            var it = _apidb.getFirstImpl(public.EditorTabTypeI);
            while (it) |node| : (it = node.next) {
                const iface = cetech1.apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);
                const menu_name = iface.menu_name.?();

                const tab_type_menu_name = cetech1.fromCstrZ(menu_name);
                if (_editorui.menuItem(tab_type_menu_name, .{})) {
                    var tab_inst = createNewTab(.{ .id = iface.tab_hash.id });
                    _ = tab_inst;
                }
            }
            _editorui.endMenu();
        }

        if (_editorui.beginMenu(public.Icons.CloseTab ++ "  " ++ "Close", _g.tabs.count() != 0)) {
            var tabs = std.ArrayList(*public.EditorTabI).init(alocator);
            defer tabs.deinit();
            try tabs.appendSlice(_g.tabs.values());

            for (tabs.items) |tab| {
                var buf: [128]u8 = undefined;
                var tab_title_full = try std.fmt.bufPrintZ(&buf, "{s} {d}", .{ cetech1.fromCstrZ(tab.vt.*.menu_name.?()), tab.tabid });
                if (_editorui.menuItem(tab_title_full, .{})) {
                    destroyTab(tab);
                }
            }
            _editorui.endMenu();
        }

        _editorui.endMenu();
    }
}

fn doTabs(tmp_allocator: std.mem.Allocator) !void {
    var tabs = std.ArrayList(*public.EditorTabI).init(tmp_allocator);
    defer tabs.deinit();
    try tabs.appendSlice(_g.tabs.values());

    for (tabs.items) |tab| {
        var tab_open = true;

        var tab_title = tab.vt.title.?(tab.inst);

        var tab_selected_object = _g.tab2selectedobj.get(tab);
        var asset_name_buf: [128]u8 = undefined;
        var asset_name: ?[]u8 = null;

        if (tab.vt.*.show_sel_obj_in_title) {
            if (tab_selected_object) |selected_obj| {
                if (_assetdb.getAssetForObj(selected_obj)) |asset| {
                    const type_name = _g.main_db.getTypeName(asset.type_hash).?;
                    const asset_name_str = cetech1.assetdb.AssetType.readStr(&_g.main_db, _g.main_db.readObj(asset).?, .Name).?;
                    asset_name = try std.fmt.bufPrint(&asset_name_buf, "- {s}.{s}", .{ asset_name_str, type_name });
                }
            }
        }

        // {s}###{} => ### use last part as id and survive label change. ## use lable+id
        var buf: [128]u8 = undefined;
        var tab_title_full = try std.fmt.bufPrintZ(
            &buf,
            "{s} {d} " ++ "{s}" ++ "###{s}_{d}",
            .{
                cetech1.fromCstrZ(tab_title),
                tab.tabid,
                if (asset_name) |n| n else "",
                tab.vt.tab_name.?,
                tab.tabid,
            },
        );

        const tab_flags = cetech1.editorui.WindowFlags{
            .menu_bar = true, //tab.vt.*.menu != null,
            //.no_saved_settings = true,
        };
        if (_editorui.begin(tab_title_full, .{ .popen = &tab_open, .flags = tab_flags })) {
            if (_editorui.isWindowFocused(cetech1.editorui.FocusedFlags.root_and_child_windows)) {
                if (_g.last_focused_tab != tab) {
                    _g.last_focused_tab = tab;
                    if (tab.vt.*.focused) |focused| {
                        focused(tab.inst);
                    }
                }
            }

            // Draw menu if needed.
            if (tab.vt.*.menu) |tab_menu| {
                _editorui.beginMenuBar();
                defer _editorui.endMenuBar();

                // If needed show pin object button
                if (tab.vt.*.show_pin_object) {
                    var new_pinned = !tab.pinned_obj.isEmpty();
                    if (_editorui.menuItemPtr(if (!tab.pinned_obj.isEmpty()) Icons.FA_LOCK else Icons.FA_LOCK_OPEN ++ "", .{ .selected = &new_pinned })) {
                        // Unpin
                        if (!new_pinned) {
                            _g.main_db.destroyObject(tab.pinned_obj);
                            tab.pinned_obj = .{};
                            tabSelectObj(@ptrCast(&_g.main_db.db), _g.last_selected_obj, tab);
                        } else {
                            const tab_selection = _g.tab2selectedobj.get(tab) orelse continue;
                            var selection = _g.main_db.cloneObject(tab_selection) catch undefined;
                            tabSelectObj(&_g.main_db, selection, tab);
                            tab.pinned_obj = selection;
                        }
                    }
                }

                tab_menu(tab.inst);
            }

            // Draw content if needed.
            if (tab.vt.*.ui) |tab_ui| {
                tab_ui(tab.inst);
            }
        }
        _editorui.end();

        if (!tab_open) {
            destroyTab(tab);
        }
    }
}

fn doModals(allocator: std.mem.Allocator) void {
    var it = _apidb.getFirstImpl(public.UiModalI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.UiModalI, node);
        var modal_inst = _g.modal_instances.get(iface.modal_hash) orelse continue;
        if (!iface.*.ui_modal.?(&allocator, _g.main_db.db, modal_inst)) {
            iface.*.destroy.?(&_allocator, _g.main_db.db, modal_inst);
        }
    }
}

fn editorui_ui(allocator: std.mem.Allocator) !void {
    try doMainMenu(allocator);
    try quitSaveModal();
    try doTabs(allocator);

    doModals(allocator);

    if (_g.show_demos) _editorui.showDemoWindow();
}

var editorui_ui_i = cetech1.editorui.EditorUII.implement(editorui_ui);

fn init(main_db: *cetech1.cdb.Db) !void {
    _g.main_db = cetech1.cdb.CdbDb.fromDbT(main_db, _cdb);
    _g.tabs = TabsMap.init(_allocator);
    _g.tabids = TabsIds.init(_allocator);
    _g.tab2selectedobj = TabsSelectedObject.init(_allocator);
    _g.modal_instances = ModalInstances.init(_allocator);

    // Create tab that has create_on_init == true. Primary for basic toolchain
    var it = _apidb.getFirstImpl(public.EditorTabTypeI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.EditorTabTypeI, node);
        if (iface.create_on_init) {
            _ = createNewTab(.{ .id = iface.tab_hash.id });
        }
    }
}

fn shutdown() !void {
    var tabs = std.ArrayList(*public.EditorTabI).init(_allocator);
    defer tabs.deinit();
    try tabs.appendSlice(_g.tabs.values());

    for (tabs.items) |tab| {
        destroyTab(tab);
    }

    _g.tabs.deinit();
    _g.tabids.deinit();
    _g.tab2selectedobj.deinit();
    _g.modal_instances.deinit();
}

var editor_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "EditorUI",
    &[_]cetech1.strid.StrId64{},
    init,
    shutdown,
);

fn kernelQuitHandler() bool {
    tryQuit();
    return true;
}

// Cdb
var create_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);
fn cdbCreateTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, _cdb);

    // Obj selections
    // Color4f
    _ = try db.addType(
        public.ObjSelectionType.name,
        &[_]cetech1.cdb.PropDef{
            .{ .prop_idx = public.ObjSelectionType.propIdx(.Selection), .name = "selection", .type = cetech1.cdb.PropType.REFERENCE_SET },
        },
    );
    //
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log;
    _apidb = apidb;
    _cdb = apidb.getZigApi(cetech1.cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _assetdb = apidb.getZigApi(cetech1.assetdb.AssetDBAPI).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    try apidb.setOrRemoveZigApi(public.EditorAPI, &api, load);

    try apidb.implOrRemove(cetech1.kernel.KernelTaskI, &editor_kernel_task, load);
    try apidb.implOrRemove(cetech1.editorui.EditorUII, &editorui_ui_i, load);

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_types_i, true);

    _kernel.setCanQuit(kernelQuitHandler);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {}
