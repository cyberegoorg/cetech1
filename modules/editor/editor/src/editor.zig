const std = @import("std");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const strid = cetech1.strid;

const log = std.log.scoped(.editor);

pub const Contexts = struct {
    pub const edit = cetech1.strId64("ct_edit_context");
    pub const create = cetech1.strId64("ct_create_context");
    pub const delete = cetech1.strId64("ct_delete_context");
    pub const open = cetech1.strId64("ct_open_context");
    pub const debug = cetech1.strId64("ct_debug_context");
};

pub const UiSetMenusAspect = struct {
    pub const c_name = "ct_ui_set_menus_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    add_menu: *const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiSetMenusAspect {
        if (!std.meta.hasFn(T, "addMenu")) @compileError("implement me");
        return UiSetMenusAspect{
            .add_menu = &T.addMenu,
        };
    }
};

pub const UiSetSortPropertyAspect = struct {
    pub const c_name = "ct_ui_set_sort_property_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    sort: *const fn (allocator: std.mem.Allocator, objs: []cdb.ObjId) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiSetSortPropertyAspect {
        if (!std.meta.hasFn(T, "sort")) @compileError("implement me");
        return UiSetSortPropertyAspect{
            .sort = &T.sort,
        };
    }
};

pub const UiVisualAspect = struct {
    pub const c_name = "ct_ui_visual_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_name: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    ui_icons: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    ui_color: ?*const fn (
        obj: cdb.ObjId,
    ) anyerror![4]f32 = null,

    ui_tooltip: ?*const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror!void = null,

    pub fn implement(comptime T: type) UiVisualAspect {
        return UiVisualAspect{
            .ui_name = if (std.meta.hasFn(T, "uiName")) T.uiName else null,
            .ui_icons = if (std.meta.hasFn(T, "uiIcons")) T.uiIcons else null,
            .ui_color = if (std.meta.hasFn(T, "uiColor")) T.uiColor else null,
            .ui_tooltip = if (std.meta.hasFn(T, "uiTooltip")) T.uiTooltip else null,
        };
    }
};

pub const UiDropObj = struct {
    pub const c_name = "ct_ui_drop_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_drop_obj: *const fn (
        allocator: std.mem.Allocator,
        tab: *TabO,
        obj: cdb.ObjId,
        prop_idx: ?u32,
        drag_obj: cdb.ObjId,
    ) anyerror!void,

    pub fn implement(comptime T: type) UiDropObj {
        if (!std.meta.hasFn(T, "uiDropObj")) @compileError("implement me");

        return UiDropObj{
            .ui_drop_obj = T.uiDropObj,
        };
    }
};

pub const ObjContextMenuI = struct {
    pub const c_name = "ct_editor_obj_context_menu_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    is_valid: ?*const fn (
        allocator: std.mem.Allocator,
        tab: *TabO,
        context: cetech1.StrId64,
        obj: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) anyerror!bool,

    menu: ?*const fn (
        allocator: std.mem.Allocator,
        tab: *TabO,
        context: cetech1.StrId64,
        obj: []const coreui.SelectionItem,
        filter: ?[:0]const u8,
    ) anyerror!void,

    pub fn implement(comptime T: type) ObjContextMenuI {
        if (!std.meta.hasFn(T, "isValid")) @compileError("implement me");
        if (!std.meta.hasFn(T, "menu")) @compileError("implement me");

        return ObjContextMenuI{
            .is_valid = T.isValid,
            .menu = T.menu,
        };
    }
};

pub const CreateAssetI = struct {
    pub const c_name = "ct_assetbrowser_create_asset_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    cdb_type: cetech1.StrId32,

    menu_item: *const fn () anyerror![:0]const u8,

    create: *const fn (
        allocator: std.mem.Allocator,
        db: cdb.DbId,
        folder: cdb.ObjId,
    ) anyerror!void,

    pub fn implement(cdb_type: cetech1.StrId32, comptime T: type) CreateAssetI {
        if (!std.meta.hasFn(T, "menuItem")) @compileError("implement me");
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");

        return CreateAssetI{
            .cdb_type = cdb_type,

            .create = T.create,
            .menu_item = T.menuItem,
        };
    }
};

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

pub const EditorAPI = struct {
    // Selection
    propagateSelection: *const fn (tab: *TabO, obj: []const coreui.SelectionItem) void,

    // Tabs
    openTabWithPinnedObj: *const fn (tab_type_hash: cetech1.StrId32, obj: coreui.SelectionItem) void,
    getAllTabsByType: *const fn (allocator: std.mem.Allocator, tab_type_hash: cetech1.StrId32) anyerror![]*TabI,

    showObjContextMenu: *const fn (
        allocator: std.mem.Allocator,
        tab: *TabO,
        contexts: []const cetech1.StrId64,
        obj: coreui.SelectionItem,
    ) anyerror!void,

    buffFormatObjLabel: *const fn (allocator: std.mem.Allocator, buff: [:0]u8, obj: cdb.ObjId, with_id: bool, uuid_id: bool) ?[:0]u8,

    getStateColor: *const fn (state: cdb.ObjRelation) [4]f32,
    getObjColor: *const fn (obj: cdb.ObjId, in_set_obj: ?cdb.ObjId) ?[4]f32,
    getAssetColor: *const fn (obj: cdb.ObjId) [4]f32,

    isColorsEnabled: *const fn () bool,
    selectObjFromMenu: *const fn (allocator: std.mem.Allocator, ignored_obj: cdb.ObjId, allowed_type: cdb.TypeIdx) ?cdb.ObjId,
};
