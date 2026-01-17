const std = @import("std");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const coreui = cetech1.coreui;

const log = std.log.scoped(.editor_tabs);

pub const TabO = anyopaque;

pub const TabI = struct {
    vt: *TabTypeI,
    inst: *TabO,
    tabid: u32 = 0,
    pinned_obj: coreui.SelectionItem = coreui.SelectionItem.empty(),
};

pub const TabTypeIArgs = struct {
    tab_name: [:0]const u8,
    tab_hash: cetech1.StrId32,
    category: ?[:0]const u8 = null,
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,
    ignore_selection_from_tab: ?[]const cetech1.StrId32 = null,
    only_selection_from_tab: ?[]const cetech1.StrId32 = null,
};

pub const TabTypeI = struct {
    pub const c_name = "ct_editor_tab_type_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    tab_name: [:0]const u8 = undefined,
    tab_hash: cetech1.StrId32 = .{},
    category: ?[:0]const u8 = null,
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,
    ignore_selection_from_tab: ?[]const cetech1.StrId32 = null,
    only_selection_from_tab: ?[]const cetech1.StrId32 = null,

    menu_name: *const fn () anyerror![:0]const u8 = undefined,
    title: *const fn (*TabO) anyerror![:0]const u8 = undefined,
    can_open: ?*const fn (std.mem.Allocator, []const coreui.SelectionItem) anyerror!bool = null,

    create: *const fn (tab_id: u32) anyerror!?*TabI = undefined,
    destroy: *const fn (*TabI) anyerror!void = undefined,

    menu: ?*const fn (*TabO) anyerror!void = null,
    ui: *const fn (*TabO, kernel_tick: u64, dt: f32) anyerror!void = undefined,
    obj_selected: ?*const fn (*TabO, []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) anyerror!void = null,
    focused: ?*const fn (*TabO) anyerror!void = null,
    asset_root_opened: ?*const fn (*TabO) anyerror!void = null,

    select_obj_from_menu: ?*const fn (
        allocator: std.mem.Allocator,
        *TabO,
        ignored_obj: cdb.ObjId,
        allowed_type: cdb.TypeIdx,
    ) anyerror!cdb.ObjId = null,

    pub fn implement(args: TabTypeIArgs, comptime T: type) TabTypeI {
        if (!std.meta.hasFn(T, "menuName")) @compileError("implement me");
        if (!std.meta.hasFn(T, "title")) @compileError("implement me");
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");
        if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return TabTypeI{
            .tab_name = args.tab_name,
            .tab_hash = args.tab_hash,
            .category = args.category,
            .create_on_init = args.create_on_init,
            .show_pin_object = args.show_pin_object,
            .show_sel_obj_in_title = args.show_sel_obj_in_title,

            .ignore_selection_from_tab = args.ignore_selection_from_tab,
            .only_selection_from_tab = args.only_selection_from_tab,

            .select_obj_from_menu = if (std.meta.hasFn(T, "selectObjFromMenu")) T.selectObjFromMenu else null,
            .can_open = if (std.meta.hasFn(T, "canOpen")) T.canOpen else null,
            .focused = if (std.meta.hasFn(T, "focused")) T.focused else null,
            .obj_selected = if (std.meta.hasFn(T, "objSelected")) T.objSelected else null,
            .asset_root_opened = if (std.meta.hasFn(T, "assetRootOpened")) T.assetRootOpened else null,
            .menu = if (std.meta.hasFn(T, "menu")) T.menu else null,

            .menu_name = T.menuName,
            .title = T.title,
            .create = T.create,
            .destroy = T.destroy,
            .ui = T.ui,
        };
    }
};

pub const TabsAPI = struct {
    // Selection
    propagateSelection: *const fn (tab: *TabO, obj: []const coreui.SelectionItem) void,

    // Tabs
    openTabWithPinnedObj: *const fn (tab_type_hash: cetech1.StrId32, obj: coreui.SelectionItem) void,
    getAllTabsByType: *const fn (allocator: std.mem.Allocator, tab_type_hash: cetech1.StrId32) anyerror![]*TabI,

    doTabMainMenu: *const fn (allocator: std.mem.Allocator) anyerror!void,
    doTabs: *const fn (allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) anyerror!void,

    selectObjFromMenu: *const fn (allocator: std.mem.Allocator, ignored_obj: cdb.ObjId, allowed_type: cdb.TypeIdx) ?cdb.ObjId,
};
