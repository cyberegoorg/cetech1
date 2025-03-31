const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor.zig");

const cetech1 = @import("cetech1");
const apidb = cetech1.apidb;
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const strid = cetech1.strid;
const task = cetech1.task;

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
var _platform: *const cetech1.platform.PlatformApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;

const TabsSelectedObject = cetech1.AutoArrayHashMap(*public.TabI, coreui.SelectionItem);
const TabsMap = cetech1.AutoArrayHashMap(*anyopaque, *public.TabI);
const TabsIdPool = cetech1.heap.IdPool(u32);
const TabsIds = cetech1.AutoArrayHashMap(cetech1.StrId32, TabsIdPool);

const ContextToLabel = cetech1.AutoArrayHashMap(cetech1.StrId64, [:0]const u8);

// TODO: from config
const REPO_URL = "https://github.com/cyberegoorg/cetech1";
const ONLINE_DOCUMENTATION = "https://cyberegoorg.github.io/cetech1/about.html";

// Global state
const G = struct {
    main_db: cdb.DbId = undefined,
    show_demos: bool = false,
    show_metrics: bool = false,
    show_testing_window: bool = false,
    show_external_credits: bool = false,
    show_authors: bool = false,
    enable_colors: bool = true,
    tabs: TabsMap = undefined,
    tabids: TabsIds = undefined,
    last_focused_tab: ?*public.TabI = null,
    tab2selectedobj: TabsSelectedObject = undefined,
    last_selected_obj: coreui.SelectionItem = undefined,

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

    .getAssetColor = getAssetColor,
    .isColorsEnabled = isColorsEnabled,
    .selectObjFromMenu = selectObjFromMenu,

    .getStateColor = getStateColor,
    .getObjColor = getObjColor,
};

fn selectObjFromMenu(allocator: std.mem.Allocator, ignored_obj: cdb.ObjId, allowed_type: cdb.TypeIdx) ?cdb.ObjId {
    const tabs = _g.tabs.values();
    for (tabs) |tab| {
        if (tab.vt.select_obj_from_menu) |select_obj_from_menu| {
            const result = select_obj_from_menu(allocator, tab.inst, ignored_obj, allowed_type) catch return null;
            if (!result.isEmpty()) return result;
        }
    }

    return null;
}

fn isColorsEnabled() bool {
    return _g.enable_colors;
}

const PROTOTYPE_PROPERTY_OVERIDED_COLOR = .{ 0.0, 0.8, 1.0, 1.0 };
const PROTOTYPE_PROPERTY_COLOR = .{ 0.83, 0.83, 0.83, 1.0 };
const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };
const NOT_OWNED_PROPERTY_COLOR = .{ 0.5, 0.5, 0.5, 1.0 };

fn getStateColor(state: cdb.ObjRelation) [4]f32 {
    if (!_g.enable_colors) return _coreui.getStyle().getColor(.text);

    return switch (state) {
        .inisiated => INSIATED_COLOR,
        .overide => PROTOTYPE_PROPERTY_OVERIDED_COLOR,
        .inheried => PROTOTYPE_PROPERTY_COLOR,
        .owned => _coreui.getStyle().getColor(.text),
        .not_owned => NOT_OWNED_PROPERTY_COLOR, //TODO: remove
    };
}

fn getObjColor(obj: cdb.ObjId, in_set_obj: ?cdb.ObjId) ?[4]f32 {
    const db = _cdb.getDbFromObjid(obj);

    if (in_set_obj) |s_obj| {
        if (_cdb.getAspect(public.UiVisualAspect, db, s_obj.type_idx)) |aspect| {
            if (aspect.ui_color) |color| {
                return color(s_obj) catch _coreui.getStyle().getColor(.text);
            }
        }
    } else {
        if (_cdb.getAspect(public.UiVisualAspect, db, obj.type_idx)) |aspect| {
            if (aspect.ui_color) |color| {
                return color(obj) catch _coreui.getStyle().getColor(.text);
            }
        }
    }
    return null;
}

fn getAssetColor(obj: cdb.ObjId) [4]f32 {
    if (!_g.enable_colors) return _coreui.getStyle().getColor(.text);

    if (obj.type_idx.eql(AssetTypeIdx)) {
        const is_modified = _assetdb.isAssetModified(obj);
        const is_deleted = _assetdb.isToDeleted(obj);

        if (is_modified) {
            return coreui.Colors.Modified;
        } else if (is_deleted) {
            return coreui.Colors.Deleted;
        }
        const r = _cdb.readObj(obj).?;

        if (assetdb.Asset.readSubObj(_cdb, r, .Object)) |asset_obj| {
            return getObjColor(asset_obj, null) orelse _coreui.getStyle().getColor(.text);
        }
    }

    return _coreui.getStyle().getColor(.text);
}

fn buffFormatObjLabel(allocator: std.mem.Allocator, buff: [:0]u8, obj: cdb.ObjId, with_id: bool, uuid_id: bool) ?[:0]u8 {
    var name_buff: [128:0]u8 = undefined;

    const db = _cdb.getDbFromObjid(obj);
    if (_cdb.getAspect(public.UiVisualAspect, db, obj.type_idx)) |aspect| {
        var name: []const u8 = undefined;

        if (aspect.ui_name) |ui_name| {
            name = ui_name(&name_buff, allocator, obj) catch return null;
        } else {
            const asset_obj = _assetdb.getAssetForObj(obj).?;
            const obj_r = _cdb.readObj(asset_obj).?;

            if (_assetdb.isAssetFolder(obj)) {
                const asset_name = assetdb.Asset.readStr(_cdb, obj_r, .Name) orelse "ROOT";
                name = std.fmt.bufPrintZ(&name_buff, "{s}", .{asset_name}) catch "";
            } else {
                const asset_name = assetdb.Asset.readStr(_cdb, obj_r, .Name) orelse "No NAME =()";
                const type_name = _cdb.getTypeName(db, asset_obj.type_idx).?;
                name = std.fmt.bufPrintZ(&name_buff, "{s}.{s}", .{ asset_name, type_name }) catch "";
            }
        }

        if (aspect.ui_icons) |icons| {
            var icon_buf: [16:0]u8 = undefined;

            const icon = icons(&icon_buf, allocator, obj) catch return null;

            if (with_id) {
                if (uuid_id) {
                    return std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}###{s}", .{ icon, name, _assetdb.getOrCreateUuid(obj) catch return null }) catch return null;
                } else {
                    return std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}###{s}", .{ icon, name, name }) catch return null;
                }
            } else {
                return std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}", .{ icon, name }) catch return null;
            }
        } else {
            if (with_id) {
                if (uuid_id) {
                    return std.fmt.bufPrintZ(buff, "{s}###{s}", .{ name, _assetdb.getOrCreateUuid(obj) catch return null }) catch return null;
                } else {
                    return std.fmt.bufPrintZ(buff, "{s}###{s}", .{ name, name }) catch return null;
                }
            } else {
                return std.fmt.bufPrintZ(buff, "{s}", .{name}) catch return null;
            }
        }
    }

    return null;
}

fn showObjContextMenu(
    allocator: std.mem.Allocator,
    tab: *public.TabO,
    contexts: []const cetech1.StrId64,
    selection: coreui.SelectionItem,
) !void {
    const obj = selection.parent_obj orelse selection.obj;

    if (selection.isEmpty()) return;

    _g.filter = _coreui.uiFilter(&_g.filter_buff, _g.filter);

    const db = _cdb.getDbFromObjid(obj);

    const is_child = _cdb.isChildOff(selection.top_level_obj, selection.in_set_obj orelse selection.obj);
    const enabled = is_child;

    // Property based context
    if (selection.prop_idx) |pidx| {
        const prop_defs = _cdb.getTypePropDef(db, obj.type_idx).?;
        const prop_def = prop_defs[pidx];

        if (selection.in_set_obj) |set_obj| {
            const obj_r = _cdb.readObj(obj) orelse return;
            const has_prototype = !_cdb.getPrototype(obj_r).isEmpty();
            const set_obj_r = _cdb.readObj(set_obj) orelse return;
            if (_cdb.canIinisiated(obj_r, set_obj_r)) {
                if (_coreui.menuItem(allocator, coreui.Icons.Instansiate ++ "  " ++ "Instansiate" ++ "###Inisiate", .{}, null)) {
                    const w = _cdb.writeObj(obj).?;
                    _ = try _cdb.instantiateSubObjFromSet(w, pidx, set_obj);
                    try _cdb.writeCommit(w);
                }

                _coreui.separator();
            }

            {
                _coreui.pushStyleColor4f(.{ .idx = .text, .c = coreui.Colors.Remove });
                defer _coreui.popStyleColor(.{});
                if (_coreui.menuItem(allocator, coreui.Icons.Remove ++ "  " ++ "Remove" ++ "###Remove", .{
                    .enabled = !has_prototype or _cdb.canIinisiated(obj_r, set_obj_r),
                }, null)) {
                    const w = _cdb.writeObj(obj).?;
                    if (prop_def.type == .REFERENCE_SET) {
                        try _cdb.removeFromRefSet(w, pidx, set_obj);
                    } else {
                        const subobj_w = _cdb.writeObj(set_obj).?;
                        try _cdb.removeFromSubObjSet(w, pidx, subobj_w);
                        try _cdb.writeCommit(subobj_w);
                    }

                    try _cdb.writeCommit(w);
                }
            }
        } else {
            if (prop_def.type == .SUBOBJECT_SET or prop_def.type == .REFERENCE_SET) {
                var menu_open = true;

                if (_g.filter == null) {
                    menu_open = _coreui.beginMenu(allocator, coreui.Icons.Add ++ "  " ++ "Add to set" ++ "###AddToSet", enabled, null);
                }

                if (menu_open) {
                    defer if (_g.filter == null) _coreui.endMenu();

                    const set_menus_aspect = _cdb.getPropertyAspect(public.UiSetMenusAspect, db, obj.type_idx, pidx);
                    if (set_menus_aspect) |aspect| {
                        try aspect.add_menu(allocator, obj, pidx, _g.filter);
                    } else {
                        if (prop_def.type == .REFERENCE_SET) {
                            if (selectObjFromMenu(
                                allocator,
                                _assetdb.getObjForAsset(obj) orelse obj,
                                _cdb.getTypeIdx(db, prop_def.type_hash) orelse .{},
                            )) |selected| {
                                const w = _cdb.writeObj(obj).?;
                                try _cdb.addRefToSet(w, pidx, &.{selected});
                                try _cdb.writeCommit(w);
                            }
                        } else {
                            if (prop_def.type_hash.id != 0) {
                                if (_coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Add new" ++ "###AddNew", .{ .enabled = enabled }, null)) {
                                    const w = _cdb.writeObj(obj).?;

                                    const new_obj = try _cdb.createObject(db, _cdb.getTypeIdx(db, prop_def.type_hash).?);
                                    const new_obj_w = _cdb.writeObj(new_obj).?;

                                    try _cdb.addSubObjToSet(w, pidx, &.{new_obj_w});

                                    try _cdb.writeCommit(new_obj_w);
                                    try _cdb.writeCommit(w);
                                }
                            }
                        }
                    }
                }
            } else if (prop_def.type == .SUBOBJECT) {
                const obj_r = _cdb.readObj(obj) orelse return;

                const set_menus_aspect = _cdb.getPropertyAspect(public.UiSetMenusAspect, db, obj.type_idx, pidx);
                if (set_menus_aspect) |aspect| {
                    try aspect.add_menu(allocator, obj, pidx, _g.filter);
                } else if (_cdb.readSubObj(obj_r, pidx)) |subobj| {
                    const subobj_r = _cdb.readObj(subobj).?;

                    if (_cdb.canIinisiated(obj_r, subobj_r)) {
                        if (_coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Inisiate" ++ "###Inisiate", .{}, null)) {
                            const w = _cdb.writeObj(obj).?;
                            _ = try _cdb.instantiateSubObj(w, pidx);
                            try _cdb.writeCommit(w);
                        }
                    }
                } else {
                    if (prop_def.type_hash.id != 0) {
                        if (_coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Add new", .{ .enabled = enabled }, null)) {
                            const w = _cdb.writeObj(obj).?;

                            const new_obj = try _cdb.createObject(db, _cdb.getTypeIdx(db, prop_def.type_hash).?);
                            const new_obj_w = _cdb.writeObj(new_obj).?;

                            try _cdb.setSubObj(w, pidx, new_obj_w);

                            try _cdb.writeCommit(new_obj_w);
                            try _cdb.writeCommit(w);
                        }
                    }
                }
            }
        }

        // Obj based context
    } else {
        var context_counter = cetech1.AutoArrayHashMap(cetech1.StrId64, cetech1.ArrayList(*const public.ObjContextMenuI)){};
        defer {
            for (context_counter.values()) |*v| {
                v.deinit(allocator);
            }
            context_counter.deinit(allocator);
        }

        const impls = try _apidb.getImpl(allocator, public.ObjContextMenuI);
        defer allocator.free(impls);
        for (impls) |iface| {
            if (iface.is_valid) |is_valid| {
                for (contexts) |context| {
                    if (is_valid(
                        allocator,
                        tab,
                        context,
                        &.{selection},
                        _g.filter,
                    ) catch false) {
                        if (!context_counter.contains(context)) {
                            try context_counter.put(allocator, context, .{});
                        }
                        var array = context_counter.getPtr(context).?;
                        try array.append(allocator, iface);
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
                            tab,
                            context,
                            &.{selection},
                            _g.filter,
                        );
                    }
                }
            }
        }
    }
}

fn getAllTabsByType(allocator: std.mem.Allocator, tab_type_hash: cetech1.StrId32) ![]*public.TabI {
    var result = cetech1.ArrayList(*public.TabI){};
    defer result.deinit(allocator);

    const tabs = _g.tabs.values();

    for (tabs) |tab| {
        if (tab.vt.*.tab_hash.id != tab_type_hash.id) continue;
        try result.append(allocator, tab);
    }

    return result.toOwnedSlice(allocator);
}

fn openTabWithPinnedObj(tab_type_hash: cetech1.StrId32, obj: coreui.SelectionItem) void {
    if (createNewTab(tab_type_hash)) |new_tab| {
        tabSelectObj(
            &.{obj},
            new_tab,
            null,
        );
        new_tab.pinned_obj = obj;
    }
}

fn tabSelectObj(obj: []const coreui.SelectionItem, tab: *public.TabI, sender_tab: ?*public.TabI) void {
    const o: []const coreui.SelectionItem = if (obj.len == 0) &.{.{ .top_level_obj = .{}, .obj = .{} }} else obj;

    _g.tab2selectedobj.put(_allocator, tab, o[0]) catch undefined;

    if (tab.vt.*.obj_selected) |obj_selected| {
        //log.debug("Selectedobj: {s} {any}", .{o[0]});
        obj_selected(
            tab.inst,
            o,
            if (sender_tab) |st| st.vt.tab_hash else null,
        ) catch undefined;
    }
}

fn findTabFromTabO(tab: *public.TabO) ?*public.TabI {
    for (_g.tabs.values()) |t| {
        if (t.inst == tab) return t;
    }

    return null;
}

fn propagateSelection(tab_inst: *public.TabO, obj: []const coreui.SelectionItem) void {
    const tab = findTabFromTabO(tab_inst);

    tab_loop: for (_g.tabs.values()) |t| {
        if (!t.pinned_obj.isEmpty()) continue;
        const vt = t.vt;

        if (tab) |sender| {
            if (vt.only_selection_from_tab) |only_from| {
                for (only_from) |of| { // 5EUR per month (.) (.)
                    if (!sender.vt.tab_hash.eql(of)) continue :tab_loop;
                }
            }

            if (vt.ignore_selection_from_tab) |ignores| {
                for (ignores) |ig| {
                    if (sender.vt.tab_hash.eql(ig)) continue :tab_loop;
                }
            }
        }

        tabSelectObj(
            obj,
            t,
            tab,
        );
    }

    _g.last_selected_obj = if (obj.len != 0) obj[0] else coreui.SelectionItem.empty();
}

fn alocateTabId(tab_hash: cetech1.StrId32) !u32 {
    var get_or_put = try _g.tabids.getOrPut(_allocator, tab_hash);
    if (!get_or_put.found_existing) {
        const pool = TabsIdPool.init(_allocator);
        get_or_put.value_ptr.* = pool;
    }

    return get_or_put.value_ptr.create(null);
}

fn dealocateTabId(tab_hash: cetech1.StrId32, tabid: u32) !void {
    var pool = _g.tabids.getPtr(tab_hash).?;
    try pool.destroy(tabid);
}

fn createNewTab(tab_hash: cetech1.StrId32) ?*public.TabI {
    const impls = _apidb.getImpl(_allocator, public.TabTypeI) catch undefined;
    defer _allocator.free(impls);
    for (impls) |iface| {
        if (iface.tab_hash.id != tab_hash.id) continue;

        const tabid = alocateTabId(iface.tab_hash) catch undefined;
        errdefer dealocateTabId(iface.tab_hash, tabid);

        const tab_inst = (iface.*.create(tabid) catch null) orelse continue;
        _g.tabs.put(_allocator, tab_inst.*.inst, tab_inst) catch undefined;
        tab_inst.*.tabid = tabid;

        return tab_inst;
    }
    return null;
}

fn findTabIface(tab_hash: cetech1.StrId32) ?*const public.TabTypeI {
    const impls = _apidb.getImpl(_allocator, public.TabTypeI) catch undefined;
    defer _allocator.free(impls);
    for (impls) |iface| {
        if (iface.tab_hash.id != tab_hash.id) continue;
        return iface;
    }
    return null;
}

fn destroyTab(tab: *public.TabI) void {
    if (!tab.pinned_obj.isEmpty()) {
        //_g.main_db.destroyObject(tab.pinned_obj);
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
            if (_kernel.getMainWindow()) |w| {
                w.setShouldClose(false);
            }
            _coreui.closeCurrentPopup();
        }
    }

    if (show_quit_modal) {
        _coreui.openPopup(modal_quit, .{});
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
            const Task = struct {
                pub fn exec(_: *@This()) !void {
                    var buf: [256:0]u8 = undefined;
                    const str = try std.fs.cwd().realpath(".", &buf);
                    buf[str.len] = 0;

                    const a = _tempalloc.create() catch undefined;
                    defer _tempalloc.destroy(a);

                    if (try _coreui.openFileDialog(
                        a,
                        &.{
                            .{ .name = "Project file", .spec = assetdb.Project.name ++ ".json" },
                        },
                        @ptrCast(&buf),
                    )) |path| {
                        defer a.free(path);

                        const dir = std.fs.path.dirname(path).?;
                        _kernel.openAssetRoot(dir);
                    }
                }
            };
            const t = try _task.schedule(
                .none,
                Task{},
                .{ .affinity = 0 },
            );
            _task.wait(t);
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
        _ = _coreui.menuItemPtr(allocator, "ImGUI metrics", .{ .selected = &_g.show_metrics }, null);

        _coreui.separator();
        if (_coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Force save all", .{ .enabled = _assetdb.isProjectOpened() }, null)) {
            try _assetdb.saveAllAssets(allocator);
        }
    }

    if (_coreui.beginMenu(allocator, coreui.Icons.Help, true, null)) {
        defer _coreui.endMenu();

        if (_coreui.menuItem(allocator, coreui.Icons.Link ++ "  " ++ "GitHub", .{}, null)) {
            try _platform.openIn(allocator, .open_url, REPO_URL);
        }

        if (_coreui.menuItem(allocator, coreui.Icons.Link ++ "  " ++ "Docs (online)", .{}, null)) {
            try _platform.openIn(allocator, .open_url, ONLINE_DOCUMENTATION);
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
            const impls = try _apidb.getImpl(allocator, public.TabTypeI);
            defer allocator.free(impls);

            // Create category menu first
            for (impls) |iface| {
                var buff: [128:0]u8 = undefined;
                if (iface.category) |category| {
                    const label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Folder ++ "  " ++ "{s}###{s}", .{ category, category });

                    if (_coreui.beginMenu(allocator, label, true, null)) {
                        _coreui.endMenu();
                    }
                }
            }

            // Create tab items
            for (impls) |iface| {
                const menu_name = try iface.menu_name();

                const tab_type_menu_name = menu_name;

                var category_open = true;

                if (iface.category) |category| {
                    var buff: [128:0]u8 = undefined;
                    const label = try std.fmt.bufPrintZ(&buff, "###{s}", .{category});
                    category_open = _coreui.beginMenu(allocator, label, true, null);
                }

                if (category_open and _coreui.menuItem(allocator, tab_type_menu_name, .{}, null)) {
                    const tab_inst = createNewTab(.{ .id = iface.tab_hash.id });
                    _ = tab_inst;
                }
                if (category_open and iface.category != null) {
                    _coreui.endMenu();
                }
            }
        }

        if (_coreui.beginMenu(allocator, coreui.Icons.CloseTab ++ "  " ++ "Close", _g.tabs.count() != 0, null)) {
            defer _coreui.endMenu();

            var tabs = cetech1.ArrayList(*public.TabI){};
            defer tabs.deinit(allocator);
            try tabs.appendSlice(allocator, _g.tabs.values());

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

fn doTabs(allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "Editor: doTabs");
    defer zone_ctx.End();

    var tabs = cetech1.ArrayList(*public.TabI){};
    defer tabs.deinit(allocator);
    try tabs.appendSlice(allocator, _g.tabs.values());

    for (tabs.items) |tab| {
        var tab_zone_ctx = _profiler.Zone(@src());
        defer tab_zone_ctx.End();

        tab_zone_ctx.Name(tab.vt.tab_name);

        var tab_open = true;

        const tab_title = try tab.vt.title(tab.inst);

        const tab_selected_object = _g.tab2selectedobj.get(tab);
        var asset_name_buf: [128]u8 = undefined;
        var asset_name: ?[]u8 = null;

        if (tab.vt.*.show_sel_obj_in_title) {
            if (tab_selected_object) |selected_obj| {
                if (!selected_obj.isEmpty()) {
                    const fo = selected_obj;
                    if (!fo.isEmpty()) {
                        if (_assetdb.getAssetForObj(fo.top_level_obj)) |asset| {
                            if (assetdb.Asset.readStr(_cdb, _cdb.readObj(asset) orelse continue, .Name)) |asset_name_str| {
                                const type_name = _cdb.getTypeName(_g.main_db, asset.type_idx).?;
                                asset_name = try std.fmt.bufPrint(&asset_name_buf, "- {s}.{s}", .{ asset_name_str, type_name });
                            }
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
                    if (_coreui.menuItemPtr(allocator, if (!tab.pinned_obj.isEmpty()) Icons.FA_LOCK else Icons.FA_LOCK_OPEN ++ "", .{ .selected = &new_pinned }, null)) {
                        // Unpin
                        if (!new_pinned) {
                            tab.pinned_obj = coreui.SelectionItem.empty();
                            tabSelectObj(&.{_g.last_selected_obj}, tab, null);
                        } else {
                            const tab_selection = _g.last_selected_obj; //_g.tab2selectedobj.get(tab) orelse continue;

                            tabSelectObj(&.{tab_selection}, tab, null);
                            tab.pinned_obj = tab_selection;
                        }
                    }
                }

                try tab_menu(tab.inst);
            }

            // Draw content if needed.

            try tab.vt.*.ui(tab.inst, kernel_tick, dt);
        }
        _coreui.end();

        if (!tab_open) {
            destroyTab(tab);
        }
    }
}

var coreui_ui_i = coreui.CoreUII.implement(struct {
    pub fn ui(allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) !void {
        _ = _coreui.mainDockSpace(coreui.DockNodeFlags{ .passthru_central_node = true });

        try doMainMenu(allocator);
        try quitSaveModal();
        try doTabs(allocator, kernel_tick, dt);

        if (_g.show_demos) _coreui.showDemoWindow();
        if (_g.show_metrics) _coreui.showMetricsWindow();

        _coreui.showTestingWindow(&_g.show_testing_window);
        _coreui.showExternalCredits(&_g.show_external_credits);
        _coreui.showAuthors(&_g.show_authors);
    }
});

var editor_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Editor",
    &[_]cetech1.StrId64{cetech1.strId64("Renderer")},
    struct {
        pub fn init() !void {
            _g.main_db = _kernel.getDb();
            _g.tabs = .{};
            _g.tabids = .{};
            _g.tab2selectedobj = .{};
            _g.context2label = .{};

            // Create tab that has create_on_init == true. Primary for basic toolchain
            const impls = _apidb.getImpl(_allocator, public.TabTypeI) catch undefined;
            defer _allocator.free(impls);
            for (impls) |iface| {
                if (iface.create_on_init) {
                    _ = createNewTab(.{ .id = iface.tab_hash.id });
                }
            }

            try _g.context2label.put(_allocator, public.Contexts.edit, "Edit");
            try _g.context2label.put(_allocator, public.Contexts.create, "Create");
            try _g.context2label.put(_allocator, public.Contexts.delete, "Delete");
            try _g.context2label.put(_allocator, public.Contexts.open, "Open");
            try _g.context2label.put(_allocator, public.Contexts.debug, "Debug");
        }

        pub fn shutdown() !void {
            var tabs = cetech1.ArrayList(*public.TabI){};
            defer tabs.deinit(_allocator);
            try tabs.appendSlice(_allocator, _g.tabs.values());

            for (tabs.items) |tab| {
                destroyTab(tab);
            }

            for (_g.tabids.values()) |*value| {
                value.deinit();
            }

            _g.tabs.deinit(_allocator);
            _g.tabids.deinit(_allocator);
            _g.tab2selectedobj.deinit(_allocator);
            _g.context2label.deinit(_allocator);
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
        tab: *public.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != public.Contexts.open.id) return false;
        var pass = true;

        if (filter) |f| {
            pass = false;
            const impls = _apidb.getImpl(allocator, public.TabTypeI) catch undefined;
            defer allocator.free(impls);
            for (impls) |iface| {
                if (iface.can_open) |can_open| {
                    if (try can_open(allocator, selection)) {
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
        tab: *public.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const impls = _apidb.getImpl(allocator, public.TabTypeI) catch undefined;
        defer allocator.free(impls);
        for (impls) |iface| {
            if (iface.can_open) |can_open| {
                if (try can_open(allocator, selection)) {
                    const name = try iface.menu_name();

                    var buff: [128]u8 = undefined;
                    const label = std.fmt.bufPrintZ(&buff, "{s}###OpenIn_{s}", .{ name, iface.tab_name }) catch undefined;

                    if (_coreui.menuItem(allocator, label, .{}, filter)) {
                        for (selection) |obj| {
                            openTabWithPinnedObj(iface.tab_hash, obj);
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
        var tabs = cetech1.ArrayList(*public.TabI){};
        defer tabs.deinit(_allocator);
        try tabs.appendSlice(_allocator, _g.tabs.values());

        for (tabs.items) |tab| {
            if (tab.tabid == 1 and tab.vt.*.create_on_init) {
                if (tab.vt.*.asset_root_opened) |asset_root_opened| {
                    try asset_root_opened(tab.inst);
                    continue;
                }
            }
            //if (tab.tabid == 1) continue;
            destroyTab(tab);
        }

        for (_g.tabids.values()) |*value| {
            value.deinit();
        }
        _g.tabids.clearRetainingCapacity();

        if (tabs.items.len != 0) {
            const impls = _apidb.getImpl(_allocator, public.TabTypeI) catch undefined;
            defer _allocator.free(impls);
            for (impls) |iface| {
                if (iface.create_on_init and iface.asset_root_opened == null) {
                    _ = createNewTab(iface.tab_hash);
                } else {
                    _ = try alocateTabId(iface.tab_hash);
                }
            }
        }
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
    _platform = _apidb.getZigApi(module_name, cetech1.platform.PlatformApi).?;
    _profiler = _apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _task = _apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    try _apidb.setOrRemoveZigApi(module_name, public.EditorAPI, &api, load);

    try _apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &editor_kernel_task, load);
    try _apidb.implOrRemove(module_name, coreui.CoreUII, &coreui_ui_i, load);
    try _apidb.implOrRemove(module_name, public.ObjContextMenuI, &open_in_context_menu_i, load);
    try _apidb.implOrRemove(module_name, assetdb.AssetRootOpenedI, &asset_root_opened_i, true);
    try _apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, true);

    _kernel.setCanQuit(kernelQuitHandler);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor(__apidb: *const apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {}
