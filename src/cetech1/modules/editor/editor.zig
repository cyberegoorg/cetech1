const std = @import("std");
const cetech1 = @import("cetech1");

pub const c = @cImport(@cInclude("cetech1/modules/editor/editor.h"));

pub const CreateAssetI = extern struct {
    pub const c_name = "ct_assetbrowser_create_asset_i";
    menu_item: ?*const fn () callconv(.C) [*]const u8,

    create: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        folder: cetech1.cdb.ObjId,
    ) callconv(.C) void = null,

    pub inline fn implement(
        menu_item: *const fn () [*]const u8,
        create: *const fn (
            allocator: *const std.mem.Allocator,
            db: *cetech1.cdb.Db,
            folder: cetech1.cdb.ObjId,
        ) anyerror!void,
    ) CreateAssetI {
        const Wrap = struct {
            pub fn menu_item_c() callconv(.C) [*]const u8 {
                return menu_item();
            }

            pub fn create_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                folder: cetech1.cdb.ObjId,
            ) callconv(.C) void {
                create(allocator, db, folder) catch undefined;
            }
        };

        return CreateAssetI{
            .create = Wrap.create_c,
            .menu_item = Wrap.menu_item_c,
        };
    }
};

pub const UiModalI = extern struct {
    pub const c_name = "ct_editor_modal_i";
    pub const OnSetFN = *const fn (selected_data: ?*anyopaque, data: Data) callconv(.C) void;
    pub const Data = extern struct { data: [64]u8 = std.mem.zeroes([64]u8) };

    modal_hash: cetech1.strid.StrId32,
    ui_modal: ?*const fn (allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, modal_inst: *anyopaque) callconv(.C) bool = null,
    create: ?*const fn (allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, on_set: OnSetFN, data: Data) callconv(.C) ?*anyopaque,
    destroy: ?*const fn (allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, modal_inst: *anyopaque) callconv(.C) void,

    pub fn makeData(value: anytype) Data {
        var data: Data = .{};
        std.mem.copyForwards(u8, &data.data, std.mem.asBytes(&value));
        return data;
    }

    pub inline fn implement(
        modal_hash: cetech1.strid.StrId32,
        ui_modal: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.Db, modal_inst: *anyopaque) anyerror!bool,
        create: *const fn (allocator: std.mem.Allocator, *cetech1.cdb.Db, on_set: OnSetFN, data: Data) ?*anyopaque,
        destroy: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.Db, modal_inst: *anyopaque) anyerror!void,
    ) UiModalI {
        const Wrap = struct {
            pub fn ui_c(allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, modal_inst: *anyopaque) callconv(.C) bool {
                return ui_modal(allocator.*, db, modal_inst) catch undefined;
            }
            pub fn create_c(allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, on_set: OnSetFN, data: Data) callconv(.C) *anyopaque {
                return create(allocator.*, db, on_set, data).?;
            }

            pub fn destroy_c(allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, modal_inst: *anyopaque) callconv(.C) void {
                destroy(allocator.*, db, modal_inst) catch undefined;
            }
        };

        return UiModalI{
            .modal_hash = modal_hash,
            .ui_modal = Wrap.ui_c,
            .create = Wrap.create_c,
            .destroy = Wrap.destroy_c,
        };
    }
};

pub const TabO = anyopaque;

pub const EditorTabI = extern struct {
    vt: *EditorTabTypeI,
    inst: *TabO,
    tabid: u32 = 0,
    pinned_obj: cetech1.cdb.ObjId = .{},
};

pub const EditorTabTypeIArgs = struct {
    tab_name: [:0]const u8,
    tab_hash: cetech1.strid.StrId32,
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,

    menu_name: ?*const fn () [:0]const u8 = null,
    title: ?*const fn (*TabO) [:0]const u8 = null,
    can_open: ?*const fn (*cetech1.cdb.Db, cetech1.cdb.ObjId) bool = null,
    create: ?*const fn (*cetech1.cdb.Db) ?*EditorTabI = null,
    destroy: ?*const fn (*EditorTabI) void = null,
    menu: ?*const fn (*TabO) void = null,
    ui: ?*const fn (*TabO) void = null,
    obj_selected: ?*const fn (*TabO, *cetech1.cdb.Db, cetech1.cdb.ObjId) void = null,
    focused: ?*const fn (*TabO) void = null,
};

pub const EditorTabTypeI = extern struct {
    pub const c_name = "ct_editorui_tab_type_i";

    tab_name: ?[*:0]const u8 = null,
    tab_hash: cetech1.strid.StrId32 = .{},
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,

    menu_name: ?*const fn () callconv(.C) [*:0]const u8 = null,
    title: ?*const fn (*TabO) callconv(.C) [*:0]const u8 = null,
    can_open: ?*const fn (*cetech1.cdb.Db, cetech1.cdb.ObjId) callconv(.C) bool = null,

    create: ?*const fn (*cetech1.cdb.Db) callconv(.C) ?*EditorTabI = null,
    destroy: ?*const fn (*EditorTabI) callconv(.C) void = null,

    menu: ?*const fn (*TabO) callconv(.C) void = null,
    ui: ?*const fn (*TabO) callconv(.C) void = null,
    obj_selected: ?*const fn (*TabO, *cetech1.cdb.Db, cetech1.cdb.ObjId) callconv(.C) void = null,
    focused: ?*const fn (*TabO) callconv(.C) void = null,

    pub inline fn implement(args: EditorTabTypeIArgs) EditorTabTypeI {
        const Wrap = struct {
            pub fn menu_name_c() callconv(.C) [*:0]const u8 {
                return args.menu_name.?();
            }

            pub fn can_open_c(db: *cetech1.cdb.Db, obj: cetech1.cdb.ObjId) callconv(.C) bool {
                if (args.can_open) |can_open| {
                    return can_open(db, obj);
                }
                return false;
            }

            pub fn title_c(tab: *TabO) callconv(.C) [*:0]const u8 {
                return args.title.?(tab);
            }

            pub fn create_c(db: *cetech1.cdb.Db) callconv(.C) ?*EditorTabI {
                return args.create.?(db);
            }

            pub fn destroy_c(tabi: *EditorTabI) callconv(.C) void {
                return args.destroy.?(tabi);
            }

            pub fn menu_c(tab: *TabO) callconv(.C) void {
                return args.menu.?(tab);
            }

            pub fn ui_c(tab: *TabO) callconv(.C) void {
                return args.ui.?(tab);
            }

            pub fn obj_selected_c(tab: *TabO, db: *cetech1.cdb.Db, obj: cetech1.cdb.ObjId) callconv(.C) void {
                if (args.obj_selected) |selected| selected(tab, db, obj);
            }

            pub fn focused_c(tab: *TabO) callconv(.C) void {
                if (args.focused) |focused| focused(tab);
            }
        };

        return EditorTabTypeI{
            .tab_name = args.tab_name,
            .tab_hash = args.tab_hash,
            .create_on_init = args.create_on_init,
            .show_pin_object = args.show_pin_object,
            .show_sel_obj_in_title = args.show_sel_obj_in_title,

            .menu_name = Wrap.menu_name_c,
            .title = Wrap.title_c,
            .can_open = Wrap.can_open_c,
            .create = Wrap.create_c,
            .destroy = Wrap.destroy_c,
            .menu = Wrap.menu_c,
            .ui = Wrap.ui_c,
            .obj_selected = Wrap.obj_selected_c,
            .focused = Wrap.focused_c,
        };
    }
};

pub const EditorAPI = struct {
    // Selection
    propagateSelection: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void,

    // Tabs
    openTabWithPinnedObj: *const fn (db: *cetech1.cdb.CdbDb, tab_type_hash: cetech1.strid.StrId32, obj: cetech1.cdb.ObjId) void,
    getAllTabsByType: *const fn (allocator: std.mem.Allocator, tab_type_hash: cetech1.strid.StrId32) anyerror![]*EditorTabI,
    openSelectionInCtxMenu: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) void,
    openObjInCtxMenu: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void,

    // Modal
    openModal: *const fn (modal_hash: cetech1.strid.StrId32, on_set: UiModalI.OnSetFN, data: UiModalI.Data) void,
};
