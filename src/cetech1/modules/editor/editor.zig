const std = @import("std");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const editorui = cetech1.editorui;
const strid = cetech1.strid;

pub const c = @cImport(@cInclude("cetech1/modules/editor/editor.h"));

pub const Contexts = struct {
    pub const edit = cetech1.strid.strId64("ct_edit_context");
    pub const create = cetech1.strid.strId64("ct_create_context");
    pub const delete = cetech1.strid.strId64("ct_delete_context");
    pub const open = cetech1.strid.strId64("ct_open_context");
    pub const move = cetech1.strid.strId64("ct_move_context");
    pub const debug = cetech1.strid.strId64("ct_debug_context");
};

pub const UiSetMenusAspect = extern struct {
    pub const c_name = "ct_ui_set_menus_aspect";
    pub const name_hash = strid.strId32(UiSetMenusAspect.c_name);

    add_menu: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiSetMenusAspect {
        if (!std.meta.hasFn(T, "addMenu")) @compileError("implement me");
        return UiSetMenusAspect{
            .add_menu = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                    prop_idx: u32,
                ) callconv(.C) void {
                    T.addMenu(allocator.*, db, obj, prop_idx) catch |err| {
                        std.log.err("UiSetMenus {}", .{err});
                        @breakpoint();
                    };
                }
            }.f,
        };
    }
};

pub const UiVisualAspect = extern struct {
    pub const c_name = "ct_ui_visual_aspect";
    pub const name_hash = strid.strId32(UiVisualAspect.c_name);

    ui_name: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
    ) callconv(.C) [*c]const u8 = null,

    ui_icons: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
    ) callconv(.C) [*c]const u8 = null,

    ui_color: ?*const fn (
        db: *cdb.Db,
        obj: cdb.ObjId,
    ) callconv(.C) editorui.color4f = null,

    ui_tooltip: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiVisualAspect {
        return UiVisualAspect{
            .ui_name = if (std.meta.hasFn(T, "uiName")) struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                ) callconv(.C) [*c]const u8 {
                    const name = T.uiName(allocator.*, db, obj) catch |err| {
                        std.log.err("UiVisualAspect {}", .{err});
                        @breakpoint();
                        return "";
                    };
                    return name;
                }
            }.f else null,
            .ui_icons = if (std.meta.hasFn(T, "uiIcons")) struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                ) callconv(.C) [*c]const u8 {
                    const icons = T.uiIcons(allocator.*, db, obj) catch |err| {
                        std.log.err("UiVisualAspect {}", .{err});
                        @breakpoint();
                        return allocator.dupeZ(u8, "") catch undefined;
                    };
                    return icons;
                }
            }.f else null,
            .ui_color = if (std.meta.hasFn(T, "uiColor")) struct {
                pub fn f(
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                ) callconv(.C) editorui.color4f {
                    const color = T.uiColor(db, obj) catch |err| {
                        std.log.err("UiVisualAspect {}", .{err});
                        return .{ .c = .{ 1.0, 1.0, 1.0, 1.0 } };
                    };
                    return .{ .c = .{ color[0], color[1], color[2], color[3] } };
                }
            }.f else null,
            .ui_tooltip = if (std.meta.hasFn(T, "uiTooltip")) struct {
                pub fn f(allocator: *const std.mem.Allocator, db: *cdb.Db, obj: cdb.ObjId) callconv(.C) void {
                    T.uiTooltip(allocator.*, db, obj);
                }
            }.f else null,
        };
    }
};

pub const ObjContextMenuI = extern struct {
    pub const c_name = "ct_editor_obj_context_menu_i";
    pub const name_hash = strid.strId64(@This().c_name);

    is_valid: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        tab: *TabO,
        context: strid.StrId64,
        obj: cdb.ObjId,
        prop_idx: ?*const u32,
        in_set_obj: ?*const cdb.ObjId,
        filter: [*:0]const u8,
    ) callconv(.C) bool,

    menu: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        tab: *TabO,
        context: strid.StrId64,
        obj: cdb.ObjId,
        prop_idx: ?*const u32,
        in_set_obj: ?*const cdb.ObjId,
        filter: [*:0]const u8,
    ) callconv(.C) void,

    pub inline fn implement(comptime T: type) ObjContextMenuI {
        if (!std.meta.hasFn(T, "isValid")) @compileError("implement me");
        if (!std.meta.hasFn(T, "menu")) @compileError("implement me");

        return ObjContextMenuI{
            .is_valid = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    tab: *TabO,
                    context: strid.StrId64,
                    obj: cdb.ObjId,
                    prop_idx: ?*const u32,
                    in_set_obj: ?*const cdb.ObjId,
                    filter: [*:0]const u8,
                ) callconv(.C) bool {
                    return T.isValid(
                        allocator.*,
                        db,
                        tab,
                        context,
                        obj,
                        if (prop_idx) |pi| pi.* else null,
                        if (in_set_obj) |pi| pi.* else null,
                        if (filter[0] != 0) std.mem.span(filter) else null,
                    );
                }
            }.f,
            .menu = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    tab: *TabO,
                    context: strid.StrId64,
                    obj: cdb.ObjId,
                    prop_idx: ?*const u32,
                    in_set_obj: ?*const cdb.ObjId,
                    filter: [*:0]const u8,
                ) callconv(.C) void {
                    return T.menu(
                        allocator.*,
                        db,
                        tab,
                        context,
                        obj,
                        if (prop_idx) |pi| pi.* else null,
                        if (in_set_obj) |pi| pi.* else null,
                        if (filter[0] != 0) std.mem.span(filter) else null,
                    );
                }
            }.f,
        };
    }
};

pub const CreateAssetI = extern struct {
    pub const c_name = "ct_assetbrowser_create_asset_i";
    pub const name_hash = strid.strId64(@This().c_name);

    menu_item: ?*const fn () callconv(.C) [*]const u8,

    create: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        folder: cdb.ObjId,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) CreateAssetI {
        if (!std.meta.hasFn(T, "menuItem")) @compileError("implement me");
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");

        return CreateAssetI{
            .create = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    folder: cdb.ObjId,
                ) callconv(.C) void {
                    T.create(allocator, db, folder) catch undefined;
                }
            }.f,
            .menu_item = struct {
                pub fn f() callconv(.C) [*]const u8 {
                    return T.menuItem();
                }
            }.f,
        };
    }
};

pub const UiModalI = extern struct {
    pub const c_name = "ct_editor_modal_i";
    pub const name_hash = strid.strId64(@This().c_name);

    pub const OnSetFN = *const fn (selected_data: ?*anyopaque, data: Data) callconv(.C) void;
    pub const Data = extern struct { data: [64]u8 = std.mem.zeroes([64]u8) };

    modal_hash: strid.StrId32,
    ui_modal: ?*const fn (allocator: *const std.mem.Allocator, db: *cdb.Db, modal_inst: *anyopaque) callconv(.C) bool = null,
    create: ?*const fn (allocator: *const std.mem.Allocator, db: *cdb.Db, on_set: OnSetFN, data: Data) callconv(.C) ?*anyopaque,
    destroy: ?*const fn (allocator: *const std.mem.Allocator, db: *cdb.Db, modal_inst: *anyopaque) callconv(.C) void,

    pub fn makeData(value: anytype) Data {
        var data: Data = .{};
        std.mem.copyForwards(u8, &data.data, std.mem.asBytes(&value));
        return data;
    }

    pub inline fn implement(modal_hash: strid.StrId32, comptime T: type) UiModalI {
        if (!std.meta.hasFn(T, "uiModal")) @compileError("implement me");
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");
        if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");

        return UiModalI{
            .modal_hash = modal_hash,
            .ui_modal = struct {
                pub fn f(allocator: *const std.mem.Allocator, db: *cdb.Db, modal_inst: *anyopaque) callconv(.C) bool {
                    return T.uiModal(allocator.*, db, modal_inst) catch undefined;
                }
            }.f,
            .create = struct {
                pub fn f(allocator: *const std.mem.Allocator, db: *cdb.Db, on_set: OnSetFN, data: Data) callconv(.C) *anyopaque {
                    return T.create(allocator.*, db, on_set, data).?;
                }
            }.f,
            .destroy = struct {
                pub fn f(allocator: *const std.mem.Allocator, db: *cdb.Db, modal_inst: *anyopaque) callconv(.C) void {
                    T.destroy(allocator.*, db, modal_inst) catch undefined;
                }
            }.f,
        };
    }
};

pub const TabO = anyopaque;

pub const EditorTabI = extern struct {
    vt: *EditorTabTypeI,
    inst: *TabO,
    tabid: u32 = 0,
    pinned_obj: cdb.ObjId = .{},
};

pub const EditorTabTypeIArgs = struct {
    tab_name: [:0]const u8,
    tab_hash: strid.StrId32,
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,
};

pub const EditorTabTypeI = extern struct {
    pub const c_name = "ct_editorui_tab_type_i";
    pub const name_hash = strid.strId64(@This().c_name);

    tab_name: ?[*:0]const u8 = null,
    tab_hash: strid.StrId32 = .{},
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,

    menu_name: ?*const fn () callconv(.C) [*:0]const u8 = null,
    title: ?*const fn (*TabO) callconv(.C) [*:0]const u8 = null,
    can_open: ?*const fn (*cdb.Db, cdb.ObjId) callconv(.C) bool = null,

    create: ?*const fn (*cdb.Db) callconv(.C) ?*EditorTabI = null,
    destroy: ?*const fn (*EditorTabI) callconv(.C) void = null,

    menu: ?*const fn (*TabO) callconv(.C) void = null,
    ui: ?*const fn (*TabO) callconv(.C) void = null,
    obj_selected: ?*const fn (*TabO, *cdb.Db, cdb.ObjId) callconv(.C) void = null,
    focused: ?*const fn (*TabO) callconv(.C) void = null,

    pub inline fn implement(args: EditorTabTypeIArgs, comptime T: type) EditorTabTypeI {
        if (!std.meta.hasFn(T, "menuName")) @compileError("implement me");
        if (!std.meta.hasFn(T, "title")) @compileError("implement me");
        if (!std.meta.hasFn(T, "create")) @compileError("implement me");
        if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");
        if (!std.meta.hasFn(T, "menu")) @compileError("implement me");
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return EditorTabTypeI{
            .tab_name = args.tab_name,
            .tab_hash = args.tab_hash,
            .create_on_init = args.create_on_init,
            .show_pin_object = args.show_pin_object,
            .show_sel_obj_in_title = args.show_sel_obj_in_title,

            .can_open = if (std.meta.hasFn(T, "canOpen")) struct {
                pub fn f(db: *cdb.Db, obj: cdb.ObjId) callconv(.C) bool {
                    return T.canOpen(db, obj);
                }
            }.f else null,
            .focused = if (std.meta.hasFn(T, "focused")) struct {
                pub fn f(tab: *TabO) callconv(.C) void {
                    T.focused(tab);
                }
            }.f else null,
            .obj_selected = if (std.meta.hasFn(T, "objSelected")) struct {
                pub fn f(tab: *TabO, db: *cdb.Db, obj: cdb.ObjId) callconv(.C) void {
                    T.objSelected(tab, db, obj);
                }
            }.f else null,

            .menu_name = struct {
                pub fn f() callconv(.C) [*:0]const u8 {
                    return T.menuName();
                }
            }.f,

            .title = struct {
                pub fn f(tab: *TabO) callconv(.C) [*:0]const u8 {
                    return T.title(tab);
                }
            }.f,
            .create = struct {
                pub fn f(db: *cdb.Db) callconv(.C) ?*EditorTabI {
                    return T.create(db);
                }
            }.f,
            .destroy = struct {
                pub fn f(tabi: *EditorTabI) callconv(.C) void {
                    return T.destroy(tabi);
                }
            }.f,
            .menu = struct {
                pub fn f(tab: *TabO) callconv(.C) void {
                    return T.menu(tab);
                }
            }.f,
            .ui = struct {
                pub fn f(tab: *TabO) callconv(.C) void {
                    return T.ui(tab);
                }
            }.f,
        };
    }
};

pub const EditorAPI = struct {
    // Selection
    propagateSelection: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId) void,

    // Tabs
    openTabWithPinnedObj: *const fn (db: *cdb.CdbDb, tab_type_hash: strid.StrId32, obj: cdb.ObjId) void,
    getAllTabsByType: *const fn (allocator: std.mem.Allocator, tab_type_hash: strid.StrId32) anyerror![]*EditorTabI,

    // Modal
    openModal: *const fn (modal_hash: strid.StrId32, on_set: UiModalI.OnSetFN, data: UiModalI.Data) void,

    showObjContextMenu: *const fn (
        allocator: std.mem.Allocator,
        db: *cdb.CdbDb,
        tab: *TabO,
        contexts: []const strid.StrId64,
        obj: cdb.ObjId,
        prop_idx: ?u32,
        in_set_obj: ?cdb.ObjId,
    ) anyerror!void,

    buffFormatObjLabel: *const fn (allocator: std.mem.Allocator, buff: [:0]u8, db: *cdb.CdbDb, obj: cdb.ObjId) ?[:0]u8,
    getObjColor: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cdb.ObjId) [4]f32,

    getAssetColor: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId) [4]f32,
    getPropertyColor: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: u32) ?[4]f32,
    isColorsEnabled: *const fn () bool,
};
