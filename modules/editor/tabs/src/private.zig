const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const apidb = cetech1.apidb;
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const math = cetech1.math;

const task = cetech1.task;

const Icons = coreui.CoreIcons;

const public = @import("tabs.zig");

const module_name = .editor_tabs;

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
var _platform: *const cetech1.host.PlatformApi = undefined;
var _platform_system: *const cetech1.host.SystemApi = undefined;
var _platform_dialogs: *const cetech1.host.DialogsApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;

const TabsSelectedObject = cetech1.AutoArrayHashMap(*public.TabI, coreui.SelectionItem);
const TabsMap = cetech1.AutoArrayHashMap(*anyopaque, *public.TabI);
const TabsIdPool = cetech1.heap.IdPool(u32);
const TabsIds = cetech1.AutoArrayHashMap(cetech1.StrId32, TabsIdPool);

// Global state
const G = struct {
    main_db: cdb.DbId = undefined,

    tabs: TabsMap = undefined,
    tabids: TabsIds = undefined,
    last_focused_tab: ?*public.TabI = null,
    tab2selectedobj: TabsSelectedObject = undefined,
    last_selected_obj: coreui.SelectionItem = undefined,
};
var _g: *G = undefined;

pub var api = public.TabsAPI{
    .propagateSelection = propagateSelection,
    .openTabWithPinnedObj = openTabWithPinnedObj,
    .getAllTabsByType = getAllTabsByType,
    .selectObjFromMenu = selectObjFromMenu,
    .doTabMainMenu = doTabMainMenu,
    .doTabs = doTabs,
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
    var zone_ctx = _profiler.ZoneN(@src(), "Editor: create new tab");
    defer zone_ctx.End();

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

fn doTabMainMenu(allocator: std.mem.Allocator) !void {
    if (_coreui.beginMenu(allocator, coreui.Icons.Windows, true, null)) {
        defer _coreui.endMenu();

        {
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

        // Close section
        _coreui.separator();

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
                            if (assetdb.AssetCdb.readStr(_cdb, _cdb.readObj(asset) orelse continue, .Name)) |asset_name_str| {
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
                var z_ctx = _profiler.ZoneN(@src(), "menu");
                defer z_ctx.End();

                _coreui.beginMenuBar();
                defer _coreui.endMenuBar();

                // If needed show pin object button
                if (tab.vt.*.show_pin_object) {
                    var new_pinned = !tab.pinned_obj.isEmpty();
                    if (_coreui.menuItemPtr(
                        allocator,
                        if (!tab.pinned_obj.isEmpty()) Icons.FA_LOCK else Icons.FA_LOCK_OPEN ++ "",
                        .{ .selected = &new_pinned },
                        null,
                    )) {
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
                    _coreui.separatorMenu();
                }

                try tab_menu(tab.inst);
            }

            // Draw content if needed.
            {
                var z_ctx = _profiler.ZoneN(@src(), "ui");
                defer z_ctx.End();
                try tab.vt.*.ui(tab.inst, kernel_tick, dt);
            }
        }
        _coreui.end();

        if (!tab_open) {
            destroyTab(tab);
        }
    }
}

var editor_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Editor tabs",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            _g.main_db = _kernel.getDb();
            _g.tabs = .{};
            _g.tabids = .{};
            _g.tab2selectedobj = .{};

            // Create tab that has create_on_init == true. Primary for basic toolchain
            const impls = _apidb.getImpl(_allocator, public.TabTypeI) catch undefined;
            defer _allocator.free(impls);
            for (impls) |iface| {
                if (iface.create_on_init) {
                    _ = createNewTab(.{ .id = iface.tab_hash.id });
                }
            }
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
        }
    },
);

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
    _platform = _apidb.getZigApi(module_name, cetech1.host.PlatformApi).?;
    _platform_system = _apidb.getZigApi(module_name, cetech1.host.SystemApi).?;
    _platform_dialogs = _apidb.getZigApi(module_name, cetech1.host.DialogsApi).?;
    _profiler = _apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _task = _apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    try _apidb.setOrRemoveZigApi(module_name, public.TabsAPI, &api, load);

    try _apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &editor_kernel_task, load);
    try _apidb.implOrRemove(module_name, assetdb.AssetRootOpenedI, &asset_root_opened_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_tabs(__apidb: *const apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {}
