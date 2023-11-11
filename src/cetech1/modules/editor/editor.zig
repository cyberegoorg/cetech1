const std = @import("std");
const cetech1 = @import("cetech1");

pub const c = @cImport({
    @cInclude("cetech1/modules/editor/editor.h");
});

pub const Colors = struct {
    pub const Deleted = .{ 0.7, 0.0, 0.0, 1.0 };
    pub const Remove = .{ 0.7, 0.0, 0.0, 1.0 };
};

pub const Icons = struct {
    pub const Open = cetech1.editorui.Icons.FA_FOLDER_OPEN;
    pub const OpenProject = cetech1.editorui.Icons.FA_FOLDER_OPEN;

    pub const OpenTab = cetech1.editorui.Icons.FA_WINDOW_MAXIMIZE;
    pub const CloseTab = cetech1.editorui.Icons.FA_RECTANGLE_XMARK;

    pub const Save = cetech1.editorui.Icons.FA_FLOPPY_DISK;
    pub const SaveAll = cetech1.editorui.Icons.FA_FLOPPY_DISK;

    pub const Add = cetech1.editorui.Icons.FA_PLUS;
    pub const AddFile = cetech1.editorui.Icons.FA_FILE_CIRCLE_PLUS;
    pub const AddFolder = cetech1.editorui.Icons.FA_FOLDER_PLUS;
    pub const Remove = cetech1.editorui.Icons.FA_MINUS;
    pub const Close = cetech1.editorui.Icons.FA_XMARK;
    pub const Delete = cetech1.editorui.Icons.FA_TRASH;

    pub const Restart = cetech1.editorui.Icons.FA_REPEAT;

    pub const CopyToClipboard = cetech1.editorui.Icons.FA_CLIPBOARD;

    pub const Nothing = cetech1.editorui.Icons.FA_FACE_SMILE_WINK;
    pub const Deleted = cetech1.editorui.Icons.FA_TRASH;
    pub const Quit = cetech1.editorui.Icons.FA_POWER_OFF;

    pub const Debug = cetech1.editorui.Icons.FA_BUG;

    pub const Revive = cetech1.editorui.Icons.FA_SYRINGE;

    pub const Tag = cetech1.editorui.Icons.FA_TAG;
    pub const Tags = cetech1.editorui.Icons.FA_TAGS;
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
        std.mem.copy(u8, &data.data, std.mem.asBytes(&value));
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

pub const ObjSelectionType = cetech1.cdb.CdbTypeDecl(
    "ct_obj_selection",
    enum(u32) {
        Selection = 0,
    },
);

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

pub const EditorAPI = struct {
    propagateSelection: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void,

    // Tabs
    openTabWithPinnedObj: *const fn (db: *cetech1.cdb.CdbDb, tab_type_hash: cetech1.strid.StrId32, obj: cetech1.cdb.ObjId) void,

    openModal: *const fn (modal_hash: cetech1.strid.StrId32, on_set: UiModalI.OnSetFN, data: UiModalI.Data) void,

    //TODO: to editor ui
    buffFormatObjLabel: *const fn (buff: [:0]u8, allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) ?[:0]u8,
    getObjColor: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cetech1.cdb.ObjId) [4]f32,
    objContextMenu: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cetech1.cdb.ObjId) anyerror!void,

    // Selection OBJ
    isSelected: *const fn (db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) bool,
    addToSelection: *const fn (db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) anyerror!void,
    removeFromSelection: *const fn (db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) anyerror!void,
    setSelection: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) anyerror!void,
    selectedCount: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) u32,
    getFirstSelected: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) cetech1.cdb.ObjId,
    getSelected: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) ?[]const cetech1.cdb.ObjId,
    handleSelection: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId, multiselect_enabled: bool) anyerror!void,
};

// Asset
pub const SelectAssetModal = cetech1.strid.strId32("select_asset_modal");

pub const SelectAssetParams = extern struct {
    obj: cetech1.cdb.ObjId,
    prop_idx: u32 = 0,
    ignored_object: cetech1.cdb.ObjId = .{},
    only_types: cetech1.strid.StrId32 = .{},
    multiselect: bool,
    expand: bool,
};

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

pub const AssetBrowserAPI = struct {
    buffGetValidName: *const fn (
        allocator: std.mem.Allocator,
        buf: [:0]u8,
        db: *cetech1.cdb.CdbDb,
        folder: cetech1.cdb.ObjId,
        type_hash: cetech1.strid.StrId32,
        base_name: [:0]const u8,
    ) anyerror![:0]const u8,
};

// TREE

pub const UiTreeAspect = extern struct {
    ui_tree: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
        selected_obj: cetech1.cdb.ObjId,
        args: CdbTreeViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui_tree: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            selected_obj: cetech1.cdb.ObjId,
            args: CdbTreeViewArgs,
        ) anyerror!void,
    ) UiTreeAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                selected_obj: cetech1.cdb.ObjId,
                args: CdbTreeViewArgs,
            ) callconv(.C) void {
                ui_tree(allocator.*, db, obj, selected_obj, args) catch undefined;
            }
        };

        return UiTreeAspect{
            .ui_tree = Wrap.ui_c,
        };
    }
};

pub const CdbTreeViewArgs = extern struct {
    expand_object: bool = true,
    ignored_object: cetech1.cdb.ObjId = .{},
    only_types: cetech1.strid.StrId32 = .{},
    filter: ?[*:0]const u8 = null,
    multiselect: bool = false,
};

pub const TreeAPI = struct {
    // Tree view
    cdbTreeView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, selection: cetech1.cdb.ObjId, args: CdbTreeViewArgs) anyerror!void,
    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool,
    cdbTreePop: *const fn () void,
};

// Settings

pub const ProjectSettingsI = extern struct {
    pub const c_name = "ct_project_settings_i";

    setting_type_hash: cetech1.strid.StrId32,
    menu_item: ?*const fn () callconv(.C) [*]const u8,
    create: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
    ) callconv(.C) cetech1.cdb.ObjId = null,

    pub inline fn implement(
        setting_type_hash: cetech1.strid.StrId32,
        menu_item: *const fn () [*]const u8,
        create: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
        ) anyerror!cetech1.cdb.ObjId,
    ) ProjectSettingsI {
        const Wrap = struct {
            pub fn menu_item_c() callconv(.C) [*]const u8 {
                return menu_item();
            }

            pub fn create_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
            ) callconv(.C) cetech1.cdb.ObjId {
                return create(allocator.*, db) catch undefined;
            }
        };

        return ProjectSettingsI{
            .setting_type_hash = setting_type_hash,
            .menu_item = Wrap.menu_item_c,
            .create = Wrap.create_c,
        };
    }
};

// Properties

pub const hidePropertyAspect = UiPropertyAspect{};

pub const UiPropertyAspect = extern struct {
    ui_property: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        cetech1.cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

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
                    @breakpoint();
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
        obj: cetech1.cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiPropertiesAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                args: cdbPropertiesViewArgs,
            ) callconv(.C) void {
                ui(allocator.*, db, obj, args) catch |err| {
                    std.log.err("UiPropertiesAspect {}", .{err});
                    @breakpoint();
                };
            }
        };

        return UiPropertiesAspect{
            .ui_properties = Wrap.ui_c,
        };
    }
};

pub const UiEmbedPropertiesAspect = extern struct {
    ui_properties: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiEmbedPropertiesAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                args: cdbPropertiesViewArgs,
            ) callconv(.C) void {
                ui(allocator.*, db, obj, args) catch |err| {
                    std.log.err("UiEmbedPropertiesAspect {}", .{err});
                    @breakpoint();
                };
            }
        };

        return UiEmbedPropertiesAspect{
            .ui_properties = Wrap.ui_c,
        };
    }
};

pub const UiEmbedPropertyAspect = extern struct {
    ui_properties: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            prop_idx: u32,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiEmbedPropertyAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                prop_idx: u32,
                args: cdbPropertiesViewArgs,
            ) callconv(.C) void {
                ui(allocator.*, db, obj, prop_idx, args) catch |err| {
                    std.log.err("UiEmbedPropertyAspect {}", .{err});
                    @breakpoint();
                };
            }
        };

        return UiEmbedPropertyAspect{
            .ui_properties = Wrap.ui_c,
        };
    }
};

pub const UiSetMenus = extern struct {
    add_menu: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
        prop_idx: u32,
    ) callconv(.C) void = null,

    pub inline fn implement(
        add_menu: *const fn (
            allocator: std.mem.Allocator,
            dbc: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            prop_idx: u32,
        ) anyerror!void,
    ) UiSetMenus {
        const Wrap = struct {
            pub fn add_menu_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                prop_idx: u32,
            ) callconv(.C) void {
                add_menu(allocator.*, db, obj, prop_idx) catch |err| {
                    std.log.err("UiSetMenus {}", .{err});
                    @breakpoint();
                };
            }
        };

        return UiSetMenus{
            .add_menu = Wrap.add_menu_c,
        };
    }
};

pub const color4f = extern struct {
    c: [4]f32,
};

pub const UiVisualAspect = extern struct {
    ui_name: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
    ) callconv(.C) [*c]const u8 = null,

    ui_icons: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
    ) callconv(.C) [*c]const u8 = null,

    ui_color: ?*const fn (
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
    ) callconv(.C) color4f = null,

    pub inline fn implement(
        ui_name: ?*const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) anyerror![:0]const u8,
        ui_icons: ?*const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) anyerror![:0]const u8,
        ui_color: ?*const fn (
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) anyerror![4]f32,
    ) UiVisualAspect {
        const Wrap = struct {
            pub fn ui_name_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
            ) callconv(.C) [*c]const u8 {
                const name = ui_name.?(allocator.*, db, obj) catch |err| {
                    std.log.err("UiVisualAspect {}", .{err});
                    @breakpoint();
                    return "";
                };
                return name;
            }

            pub fn ui_icons_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
            ) callconv(.C) [*c]const u8 {
                const icons = ui_icons.?(allocator.*, db, obj) catch |err| {
                    std.log.err("UiVisualAspect {}", .{err});
                    @breakpoint();
                    return "";
                };
                return icons;
            }

            pub fn ui_color_c(
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
            ) callconv(.C) color4f {
                const color = ui_color.?(db, obj) catch |err| {
                    std.log.err("UiVisualAspect {}", .{err});
                    return .{ .c = .{ 1.0, 1.0, 1.0, 1.0 } };
                };
                return .{ .c = .{ color[0], color[1], color[2], color[3] } };
            }
        };

        return UiVisualAspect{
            .ui_name = if (ui_name) |_| Wrap.ui_name_c else null,
            .ui_icons = if (ui_icons) |_| Wrap.ui_icons_c else null,
            .ui_color = if (ui_color) |_| Wrap.ui_color_c else null,
        };
    }
};

pub const UiPropertiesConfigAspect = extern struct {
    hide_prototype: bool = false,
};

pub const UiPropertyConfigAspect = extern struct {
    hide_prototype: bool = false,
};

pub const cdbPropertiesViewArgs = extern struct {
    filter: ?[*:0]const u8 = null,
};

pub const UiVisualPropertyConfigAspect = extern struct {
    no_subtree: bool = false,
};

pub const InspectorAPI = struct {
    uiPropLabel: *const fn (allocator: std.mem.Allocator, name: [:0]const u8, color: ?[4]f32, args: cdbPropertiesViewArgs) bool,
    uiPropInput: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputBegin: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputEnd: *const fn () void,
    uiAssetInput: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32, read_only: bool, in_table: bool) anyerror!void,

    // Property utils
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,
    getPropertyColor: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32,

    // Property view
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,

    beginSection: *const fn (label: [:0]const u8, leaf: bool, default_open: bool) bool,
    endSection: *const fn (open: bool) void,

    openNewInspectorForObj: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void,
};

// Tags

pub const AssetTagsApi = struct {
    tagsInput: *const fn (
        allocator: std.mem.Allocator,
        db: *cetech1.cdb.CdbDb,
        obj: cetech1.cdb.ObjId,
        prop_idx: u32,
        in_table: bool,
        filter: ?[*:0]const u8,
    ) anyerror!bool,
};
