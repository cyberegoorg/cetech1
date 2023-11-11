const std = @import("std");
const cetech1 = @import("cetech1");

pub const c = @cImport({
    @cInclude("cetech1/modules/editor/editor.h");
});

pub const Icons = struct {
    pub const Open = cetech1.editorui.Icons.FA_FOLDER_OPEN;
    pub const OpenProject = cetech1.editorui.Icons.FA_FOLDER_OPEN;

    pub const OpenTab = cetech1.editorui.Icons.FA_WINDOW_MAXIMIZE;
    pub const CloseTab = cetech1.editorui.Icons.FA_RECTANGLE_XMARK;

    pub const Save = cetech1.editorui.Icons.FA_FLOPPY_DISK;
    pub const SaveAll = cetech1.editorui.Icons.FA_FLOPPY_DISK;

    pub const Add = cetech1.editorui.Icons.FA_PLUS;
    pub const Remove = cetech1.editorui.Icons.FA_MINUS;
    pub const Close = cetech1.editorui.Icons.FA_XMARK;

    pub const CopyToClipboard = cetech1.editorui.Icons.FA_CLIPBOARD;

    pub const Nothing = cetech1.editorui.Icons.FA_FACE_SMILE_WINK;
    pub const Deleted = cetech1.editorui.Icons.FA_TRASH;
    pub const Quit = cetech1.editorui.Icons.FA_DOOR_OPEN;

    pub const Debug = cetech1.editorui.Icons.FA_BUG;
};

pub const hidePropertyAspect = UiPropertyAspect{};

pub const UiPropertyAspect = extern struct {
    ui_property: ?*const fn (allocator: *const std.mem.Allocator, db: *cetech1.cdb.Db, cetech1.cdb.ObjId, prop_idx: u32, args: cdbPropertiesViewArgs) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            prop_idx: u32,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiPropertyAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                prop_idx: u32,
                args: cdbPropertiesViewArgs,
            ) callconv(.C) void {
                ui(allocator.*, db, obj, prop_idx, args) catch |err| {
                    std.log.err("UiPropertyAspect {}", .{err});
                };
            }
        };

        return UiPropertyAspect{
            .ui_property = Wrap.ui_c,
        };
    }
};

pub const UiPropertiesAspect = extern struct {
    ui_properties: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        cetech1.cdb.ObjId,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) anyerror!void,
    ) UiPropertiesAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
            ) callconv(.C) void {
                ui(allocator.*, db, obj) catch |err| {
                    std.log.err("UiPropertiesAspect {}", .{err});
                };
            }
        };

        return UiPropertiesAspect{
            .ui_properties = Wrap.ui_c,
        };
    }
};

pub const UiTreeAspect = extern struct {
    ui_tree: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
        selected_obj: cetech1.cdb.ObjId,
        args: CdbTreeViewArgs,
    ) callconv(.C) cetech1.cdb.ObjId = null,

    pub inline fn implement(
        ui_tree: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            selected_obj: cetech1.cdb.ObjId,
            args: CdbTreeViewArgs,
        ) anyerror!?cetech1.cdb.ObjId,
    ) UiTreeAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                selected_obj: cetech1.cdb.ObjId,
                args: CdbTreeViewArgs,
            ) callconv(.C) cetech1.cdb.ObjId {
                var new_selected = ui_tree(allocator.*, db, obj, selected_obj, args) catch undefined;
                return new_selected orelse .{};
            }
        };

        return UiTreeAspect{
            .ui_tree = Wrap.ui_c,
        };
    }
};

pub const TabO = anyopaque;

pub const EditorTabI = extern struct {
    vt: *EditorTabTypeI,
    inst: *TabO,
    tabid: u32 = 0,
    pinned_obj: bool = false,
};

pub const EditorTabTypeIArgs = struct {
    tab_name: [:0]const u8,
    tab_hash: cetech1.strid.StrId32,
    create_on_init: bool = false,
    show_pin_object: bool = false,
    show_sel_obj_in_title: bool = false,

    menu_name: ?*const fn () [:0]const u8 = null,
    title: ?*const fn (*TabO) [:0]const u8 = null,
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
            .create = Wrap.create_c,
            .destroy = Wrap.destroy_c,
            .menu = Wrap.menu_c,
            .ui = Wrap.ui_c,
            .obj_selected = Wrap.obj_selected_c,
            .focused = Wrap.focused_c,
        };
    }
};

pub const CdbTreeViewArgs = extern struct {
    expand_object: bool = true,
};

pub const cdbPropertiesViewArgs = extern struct {};

pub const EditorAPI = struct {
    selectObj: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void,

    // Tabs
    openTabWithPinnedObj: *const fn (db: *cetech1.cdb.CdbDb, tab_type_hash: cetech1.strid.StrId32, obj: cetech1.cdb.ObjId) void,

    // UI elements
    uiAssetInput: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, read_only: bool) anyerror!void,
    uiPropLabel: *const fn (name: [:0]const u8, color: ?[4]f32) void,
    uiPropInput: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputBegin: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputEnd: *const fn () void,

    // Property utils
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,
    getPropertyColor: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32,

    // Property view
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,

    // Tree view
    cdbTreeView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, selected_obj: cetech1.cdb.ObjId, args: CdbTreeViewArgs) anyerror!?cetech1.cdb.ObjId,
    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, args: CdbTreeViewArgs) bool,
    cdbTreePop: *const fn () void,
};
