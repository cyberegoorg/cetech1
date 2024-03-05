const std = @import("std");

const c = @import("c.zig").c;
const cdb = @import("cdb.zig");
const modules = @import("modules.zig");

const system = @import("system.zig");
const gpu = @import("gpu.zig");

pub const CoreIcons = @import("editorui_icons.zig").Icons;

pub const ObjSelectionType = cdb.CdbTypeDecl(
    "ct_obj_selection",
    enum(u32) {
        Selection = 0,
    },
);

pub const Colors = struct {
    pub const Deleted = .{ 0.7, 0.0, 0.0, 1.0 };
    pub const Remove = .{ 0.7, 0.0, 0.0, 1.0 };
    pub const Modified = .{ 0.9, 0.9, 0.0, 1.0 };
};

pub const Icons = struct {
    pub const Open = CoreIcons.FA_FOLDER_OPEN;
    pub const OpenProject = CoreIcons.FA_FOLDER_OPEN;

    pub const OpenTab = CoreIcons.FA_WINDOW_MAXIMIZE;
    pub const CloseTab = CoreIcons.FA_RECTANGLE_XMARK;

    pub const Save = CoreIcons.FA_FLOPPY_DISK;
    pub const SaveAll = CoreIcons.FA_FLOPPY_DISK;

    pub const Add = CoreIcons.FA_PLUS;
    pub const AddFile = CoreIcons.FA_FILE_CIRCLE_PLUS;
    pub const AddFolder = CoreIcons.FA_FOLDER_PLUS;
    pub const Remove = CoreIcons.FA_MINUS;
    pub const Close = CoreIcons.FA_XMARK;
    pub const Delete = CoreIcons.FA_TRASH;

    pub const Restart = CoreIcons.FA_REPEAT;

    pub const CopyToClipboard = CoreIcons.FA_CLIPBOARD;

    pub const Nothing = CoreIcons.FA_FACE_SMILE_WINK;
    pub const Deleted = CoreIcons.FA_TRASH;
    pub const Quit = CoreIcons.FA_POWER_OFF;

    pub const Debug = CoreIcons.FA_BUG;

    pub const Revive = CoreIcons.FA_SYRINGE;

    pub const Tag = CoreIcons.FA_TAG;
    pub const Tags = CoreIcons.FA_TAGS;

    pub const Folder = CoreIcons.FA_FOLDER_CLOSED;
    pub const Asset = CoreIcons.FA_FILE;

    pub const MoveHere = CoreIcons.FA_ARROWS_UP_DOWN_LEFT_RIGHT;
};

pub const EditorUII = extern struct {
    pub const c_name = "ct_editorui_ui_i";

    ui: *const fn (allocator: *const std.mem.Allocator) callconv(.C) void,

    pub inline fn implement(
        ui_fn: *const fn (
            allocator: std.mem.Allocator,
        ) anyerror!void,
    ) EditorUII {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
            ) callconv(.C) void {
                ui_fn(allocator.*) catch |err| {
                    std.log.err("EditorUII {}", .{err});
                    std.debug.assert(false);
                };
            }
        };

        return EditorUII{
            .ui = Wrap.ui_c,
        };
    }
};

pub const color4f = extern struct {
    c: [4]f32,
};

pub const UiVisualAspect = extern struct {
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
    ) callconv(.C) color4f = null,

    ui_tooltip: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui_name: ?*const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
        ) anyerror![:0]const u8,
        ui_icons: ?*const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
        ) anyerror![:0]const u8,
        ui_color: ?*const fn (
            db: *cdb.Db,
            obj: cdb.ObjId,
        ) anyerror![4]f32,
        ui_tooltip: ?*const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
        ) void,
    ) UiVisualAspect {
        const Wrap = struct {
            pub fn ui_name_c(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                obj: cdb.ObjId,
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
                db: *cdb.Db,
                obj: cdb.ObjId,
            ) callconv(.C) [*c]const u8 {
                const icons = ui_icons.?(allocator.*, db, obj) catch |err| {
                    std.log.err("UiVisualAspect {}", .{err});
                    @breakpoint();
                    return allocator.dupeZ(u8, "") catch undefined;
                };
                return icons;
            }

            pub fn ui_color_c(
                db: *cdb.Db,
                obj: cdb.ObjId,
            ) callconv(.C) color4f {
                const color = ui_color.?(db, obj) catch |err| {
                    std.log.err("UiVisualAspect {}", .{err});
                    return .{ .c = .{ 1.0, 1.0, 1.0, 1.0 } };
                };
                return .{ .c = .{ color[0], color[1], color[2], color[3] } };
            }

            pub fn ui_tooltip_c(allocator: std.mem.Allocator, db: *cdb.Db, obj: cdb.ObjId) callconv(.C) void {
                ui_icons.?(allocator.*, db, obj) catch |err| {
                    std.log.err("UiVisualAspect {}", .{err});
                    @breakpoint();
                };
            }
        };

        return UiVisualAspect{
            .ui_name = if (ui_name) |_| Wrap.ui_name_c else null,
            .ui_icons = if (ui_icons) |_| Wrap.ui_icons_c else null,
            .ui_color = if (ui_color) |_| Wrap.ui_color_c else null,
            .ui_tooltip = if (ui_tooltip) |_| Wrap.ui_tooltip_c else null,
        };
    }
};

pub const UiSetMenus = extern struct {
    add_menu: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) callconv(.C) void = null,

    pub inline fn implement(
        add_menu: *const fn (
            allocator: std.mem.Allocator,
            dbc: *cdb.Db,
            obj: cdb.ObjId,
            prop_idx: u32,
        ) anyerror!void,
    ) UiSetMenus {
        const Wrap = struct {
            pub fn add_menu_c(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                obj: cdb.ObjId,
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

// Properties

pub const hidePropertyAspect = UiPropertyAspect{};

pub const UiPropertyAspect = extern struct {
    ui_property: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
            prop_idx: u32,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiPropertyAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                obj: cdb.ObjId,
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
        db: *cdb.Db,
        obj: cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiPropertiesAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                obj: cdb.ObjId,
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
        db: *cdb.Db,
        obj: cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiEmbedPropertiesAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                obj: cdb.ObjId,
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
        db: *cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui: *const fn (
            allocator: std.mem.Allocator,
            db: *cdb.Db,
            obj: cdb.ObjId,
            prop_idx: u32,
            args: cdbPropertiesViewArgs,
        ) anyerror!void,
    ) UiEmbedPropertyAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                obj: cdb.ObjId,
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

pub const UiPropertiesConfigAspect = extern struct {
    hide_prototype: bool = false,
};

pub const UiPropertyConfigAspect = extern struct {
    hide_prototype: bool = false,
};

pub const UiVisualPropertyConfigAspect = extern struct {
    no_subtree: bool = false,
};

pub const cdbPropertiesViewArgs = extern struct {
    filter: ?[*:0]const u8 = null,
};

pub const EditorUIApi = struct {
    enableWithWindow: *const fn (window: *system.Window, gpuctx: *gpu.GpuContext) void,
    newFrame: *const fn () void,
    showDemoWindow: *const fn () void,

    // Filter
    uiFilter: *const fn (buf: []u8, filter: ?[:0]const u8) ?[:0]const u8,
    uiFilterPass: *const fn (allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64,

    // NFD
    openFileDialog: *const fn (filter: ?[:0]const u8, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    saveFileDialog: *const fn (filter: ?[:0]const u8, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    openFolderDialog: *const fn (default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    freePath: *const fn (path: []const u8) void,

    // shit from the pointer deep.
    begin: *const fn (name: [:0]const u8, args: Begin) bool,
    end: *const fn () void,

    isItemToggledOpen: *const fn () bool,
    dummy: *const fn (args: Dummy) void,
    spacing: *const fn () void,
    getScrollX: *const fn () f32,

    getStyle: *const fn () *Style,
    pushStyleVar2f: *const fn (args: PushStyleVar2f) void,
    pushStyleVar1f: *const fn (args: PushStyleVar1f) void,
    pushStyleColor4f: *const fn (args: PushStyleColor4f) void,
    popStyleColor: *const fn (args: PopStyleColor) void,
    popStyleVar: *const fn (args: PopStyleVar) void,

    isKeyDown: *const fn (key: Key) bool,

    tableSetBgColor: *const fn (args: TableSetBgColor) void,

    colorConvertFloat4ToU32: *const fn (in: [4]f32) u32,

    textUnformatted: *const fn (txt: []const u8) void,
    textUnformattedColored: *const fn (color: [4]f32, txt: []const u8) void,

    colorPicker4: *const fn (label: [:0]const u8, args: ColorPicker4) bool,
    colorEdit4: *const fn (label: [:0]const u8, args: ColorEdit4) bool,

    beginMainMenuBar: *const fn () void,
    endMainMenuBar: *const fn () void,
    beginMenuBar: *const fn () void,
    endMenuBar: *const fn () void,

    beginMenu: *const fn (label: [:0]const u8, enabled: bool) bool,
    endMenu: *const fn () void,
    menuItem: *const fn (label: [:0]const u8, args: MenuItem) bool,
    menuItemPtr: *const fn (label: [:0]const u8, args: MenuItemPtr) bool,

    beginChild: *const fn (str_id: [:0]const u8, args: BeginChild) bool,
    endChild: *const fn () void,

    pushPtrId: *const fn (ptr_id: *const anyopaque) void,
    pushIntId: *const fn (int_id: u32) void,
    pushObjId: *const fn (obj: cdb.ObjId) void,

    popId: *const fn () void,

    treeNode: *const fn (label: [:0]const u8) bool,
    treeNodeFlags: *const fn (label: [:0]const u8, flags: TreeNodeFlags) bool,
    treePop: *const fn () void,

    alignTextToFramePadding: *const fn () void,

    isItemHovered: *const fn (flags: HoveredFlags) bool,
    isWindowFocused: *const fn (flags: FocusedFlags) bool,

    labelText: *const fn (label: [:0]const u8, text: [:0]const u8) void,
    button: *const fn (label: [:0]const u8, args: Button) bool,
    smallButton: *const fn (label: [:0]const u8) bool,
    invisibleButton: *const fn (label: [:0]const u8, args: InvisibleButton) bool,

    sameLine: *const fn (args: SameLine) void,

    inputText: *const fn (label: [:0]const u8, args: InputText) bool,
    inputFloat: *const fn (label: [:0]const u8, args: InputFloat) bool,
    inputDouble: *const fn (label: [:0]const u8, args: InputDouble) bool,
    inputI32: *const fn (label: [:0]const u8, args: InputScalarGen(i32)) bool,
    inputU32: *const fn (label: [:0]const u8, args: InputScalarGen(u32)) bool,
    inputI64: *const fn (label: [:0]const u8, args: InputScalarGen(i64)) bool,
    inputU64: *const fn (label: [:0]const u8, args: InputScalarGen(u64)) bool,
    checkbox: *const fn (label: [:0]const u8, args: Checkbox) bool,
    setClipboardText: *const fn (value: [:0]const u8) void,

    beginPopupContextItem: *const fn () bool,
    beginPopup: *const fn (str_id: [*:0]const u8, flags: WindowFlags) bool,

    isItemClicked: *const fn (button: MouseButton) bool,
    isItemActivated: *const fn () bool,

    beginPopupModal: *const fn (name: [:0]const u8, args: Begin) bool,
    openPopup: *const fn (str_id: [:0]const u8, flags: PopupFlags) void,
    endPopup: *const fn () void,
    closeCurrentPopup: *const fn () void,

    beginTooltip: *const fn () void,
    endTooltip: *const fn () void,

    separator: *const fn () void,
    separatorText: *const fn (label: [:0]const u8) void,

    setNextItemWidth: *const fn (item_width: f32) void,

    beginTable: *const fn (name: [:0]const u8, args: BeginTable) bool,
    endTable: *const fn () void,
    tableSetupColumn: *const fn (label: [:0]const u8, args: TableSetupColumn) void,
    tableHeadersRow: *const fn () void,
    tableNextColumn: *const fn () void,
    tableNextRow: *const fn (args: TableNextRow) void,
    getItemRectMax: *const fn () [2]f32,
    getItemRectMin: *const fn () [2]f32,
    getCursorPosX: *const fn () f32,
    calcTextSize: *const fn (txt: []const u8, args: CalcTextSize) [2]f32,
    getWindowPos: *const fn () [2]f32,
    getWindowContentRegionMax: *const fn () [2]f32,
    getContentRegionMax: *const fn () [2]f32,
    getContentRegionAvail: *const fn () [2]f32,
    setCursorPosX: *const fn (x: f32) void,

    beginDragDropSource: *const fn (flags: DragDropFlags) bool,
    setDragDropPayload: *const fn (payload_type: [*:0]const u8, data: []const u8, cond: Condition) bool,
    endDragDropSource: *const fn () void,
    beginDragDropTarget: *const fn () bool,
    acceptDragDropPayload: *const fn (payload_type: [*:0]const u8, flags: DragDropFlags) ?*Payload,
    endDragDropTarget: *const fn () void,
    getDragDropPayload: *const fn () ?*Payload,

    isMouseDoubleClicked: *const fn (mouse_button: MouseButton) bool,
    isMouseDown: *const fn (mouse_button: MouseButton) bool,
    isMouseClicked: *const fn (mouse_button: MouseButton) bool,

    buffFormatObjLabel: *const fn (allocator: std.mem.Allocator, buff: [:0]u8, db: *cdb.CdbDb, obj: cdb.ObjId) ?[:0]u8,
    getObjColor: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cdb.ObjId) [4]f32,
    objContextMenu: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cdb.ObjId) anyerror!void,

    // Selection OBJ
    isSelected: *const fn (db: *cdb.CdbDb, selection: cdb.ObjId, obj: cdb.ObjId) bool,
    addToSelection: *const fn (db: *cdb.CdbDb, selection: cdb.ObjId, obj: cdb.ObjId) anyerror!void,
    removeFromSelection: *const fn (db: *cdb.CdbDb, selection: cdb.ObjId, obj: cdb.ObjId) anyerror!void,
    clearSelection: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId) anyerror!void,
    setSelection: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId, obj: cdb.ObjId) anyerror!void,
    selectedCount: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId) u32,
    getFirstSelected: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId) cdb.ObjId,
    getSelected: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId) ?[]const cdb.ObjId,
    handleSelection: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, selection: cdb.ObjId, obj: cdb.ObjId, multiselect_enabled: bool) anyerror!void,
};

// Copy from zgui
pub const Ident = u32;

const Begin = struct {
    popen: ?*bool = null,
    flags: WindowFlags = .{},
};

pub const WindowFlags = packed struct(u32) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scrollbar: bool = false,
    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,
    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scrollbar: bool = false,
    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scrollbar: bool = false,
    always_horizontal_scrollbar: bool = false,
    always_use_window_padding: bool = false,
    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    _padding: u12 = 0,

    pub const no_nav = WindowFlags{ .no_nav_inputs = true, .no_nav_focus = true };
    pub const no_decoration = WindowFlags{
        .no_title_bar = true,
        .no_resize = true,
        .no_scrollbar = true,
        .no_collapse = true,
    };
    pub const no_inputs = WindowFlags{
        .no_mouse_inputs = true,
        .no_nav_inputs = true,
        .no_nav_focus = true,
    };
};

pub const MenuItem = struct {
    shortcut: ?[:0]const u8 = null,
    selected: bool = false,
    enabled: bool = true,
};

pub const MenuItemPtr = struct {
    shortcut: ?[:0]const u8 = null,
    selected: *bool,
    enabled: bool = true,
};

pub const TreeNodeFlags = packed struct(u32) {
    selected: bool = false,
    framed: bool = false,
    allow_item_overlap: bool = false,
    no_tree_push_on_open: bool = false,
    no_auto_open_on_log: bool = false,
    default_open: bool = false,
    open_on_double_click: bool = false,
    open_on_arrow: bool = false,
    leaf: bool = false,
    bullet: bool = false,
    frame_padding: bool = false,
    span_avail_width: bool = false,
    span_full_width: bool = false,
    nav_left_jumps_back_here: bool = false,
    _padding: u18 = 0,

    pub const collapsing_header = TreeNodeFlags{
        .framed = true,
        .no_tree_push_on_open = true,
        .no_auto_open_on_log = true,
    };
};

pub const HoveredFlags = packed struct(u32) {
    child_windows: bool = false,
    root_window: bool = false,
    any_window: bool = false,
    no_popup_hierarchy: bool = false,
    _reserved0: bool = false,
    allow_when_blocked_by_popup: bool = false,
    _reserved1: bool = false,
    allow_when_blocked_by_active_item: bool = false,
    allow_when_overlapped: bool = false,
    allow_when_disabled: bool = false,
    no_nav_override: bool = false,
    _padding: u21 = 0,

    pub const rect_only = HoveredFlags{
        .allow_when_blocked_by_popup = true,
        .allow_when_blocked_by_active_item = true,
        .allow_when_overlapped = true,
    };
    pub const root_and_child_windows = HoveredFlags{ .root_window = true, .child_windows = true };
};

pub const MouseButton = enum(u32) {
    left = 0,
    right = 1,
    middle = 2,
};

pub const Key = enum(u32) {
    none = 0,
    tab = 512,
    left_arrow,
    right_arrow,
    up_arrow,
    down_arrow,
    page_up,
    page_down,
    home,
    end,
    insert,
    delete,
    back_space,
    space,
    enter,
    escape,
    left_ctrl,
    left_shift,
    left_alt,
    left_super,
    right_ctrl,
    right_shift,
    right_alt,
    right_super,
    menu,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    apostrophe,
    comma,
    minus,
    period,
    slash,
    semicolon,
    equal,
    left_bracket,
    back_slash,
    right_bracket,
    grave_accent,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_decimal,
    keypad_divide,
    keypad_multiply,
    keypad_subtract,
    keypad_add,
    keypad_enter,
    keypad_equal,

    gamepad_start,
    gamepad_back,
    gamepad_faceleft,
    gamepad_faceright,
    gamepad_faceup,
    gamepad_facedown,
    gamepad_dpadleft,
    gamepad_dpadright,
    gamepad_dpadup,
    gamepad_dpaddown,
    gamepad_l1,
    gamepad_r1,
    gamepad_l2,
    gamepad_r2,
    gamepad_l3,
    gamepad_r3,
    gamepad_lstickleft,
    gamepad_lstickright,
    gamepad_lstickup,
    gamepad_lstickdown,
    gamepad_rstickleft,
    gamepad_rstickright,
    gamepad_rstickup,
    gamepad_rstickdown,

    mouse_left,
    mouse_right,
    mouse_middle,
    mouse_x1,
    mouse_x2,

    mouse_wheel_x,
    mouse_wheel_y,

    mod_ctrl = 1 << 12,
    mod_shift = 1 << 13,
    mod_alt = 1 << 14,
    mod_super = 1 << 15,
    mod_mask_ = 0xf000,
};

pub const TableBorderFlags = packed struct(u4) {
    inner_h: bool = false,
    outer_h: bool = false,
    inner_v: bool = false,
    outer_v: bool = false,

    pub const h = TableBorderFlags{
        .inner_h = true,
        .outer_h = true,
    }; // Draw horizontal borders.
    pub const v = TableBorderFlags{
        .inner_v = true,
        .outer_v = true,
    }; // Draw vertical borders.
    pub const inner = TableBorderFlags{
        .inner_v = true,
        .inner_h = true,
    }; // Draw inner borders.
    pub const outer = TableBorderFlags{
        .outer_v = true,
        .outer_h = true,
    }; // Draw outer borders.
    pub const all = TableBorderFlags{
        .inner_v = true,
        .inner_h = true,
        .outer_v = true,
        .outer_h = true,
    }; // Draw all borders.
};
pub const TableFlags = packed struct(u32) {
    resizable: bool = false,
    reorderable: bool = false,
    hideable: bool = false,
    sortable: bool = false,
    no_saved_settings: bool = false,
    context_menu_in_body: bool = false,
    row_bg: bool = false,
    borders: TableBorderFlags = .{},
    no_borders_in_body: bool = false,
    no_borders_in_body_until_resize: bool = false,

    // Sizing Policy
    sizing: enum(u3) {
        none = 0,
        fixed_fit = 1,
        fixed_same = 2,
        stretch_prop = 3,
        stretch_same = 4,
    } = .none,

    // Sizing Extra Options
    no_host_extend_x: bool = false,
    no_host_extend_y: bool = false,
    no_keep_columns_visible: bool = false,
    precise_widths: bool = false,

    // Clipping
    no_clip: bool = false,

    // Padding
    pad_outer_x: bool = false,
    no_pad_outer_x: bool = false,
    no_pad_inner_x: bool = false,

    // Scrolling
    scroll_x: bool = false,
    scroll_y: bool = false,

    // Sorting
    sort_multi: bool = false,
    sort_tristate: bool = false,

    _padding: u4 = 0,
};

pub const TableRowFlags = packed struct(u32) {
    headers: bool = false,

    _padding: u31 = 0,
};

pub const TableColumnFlags = packed struct(u32) {
    // Input configuration flags
    disabled: bool = false,
    default_hide: bool = false,
    default_sort: bool = false,
    width_stretch: bool = false,
    width_fixed: bool = false,
    no_resize: bool = false,
    no_reorder: bool = false,
    no_hide: bool = false,
    no_clip: bool = false,
    no_sort: bool = false,
    no_sort_ascending: bool = false,
    no_sort_descending: bool = false,
    no_header_label: bool = false,
    no_header_width: bool = false,
    prefer_sort_ascending: bool = false,
    prefer_sort_descending: bool = false,
    indent_enable: bool = false,
    indent_disable: bool = false,

    _padding0: u6 = 0,

    // Output status flags, read-only via TableGetColumnFlags()
    is_enabled: bool = false,
    is_visible: bool = false,
    is_sorted: bool = false,
    is_hovered: bool = false,

    _padding1: u4 = 0,
};

pub const TableColumnSortSpecs = extern struct {
    user_id: Ident,
    index: i16,
    sort_order: i16,
    sort_direction: enum(u8) {
        none = 0,
        ascending = 1, // Ascending = 0->9, A->Z etc.
        descending = 2, // Descending = 9->0, Z->A etc.
    },
};

pub const TableSortSpecs = *extern struct {
    specs: [*]TableColumnSortSpecs,
    count: i32,
    dirty: bool,
};

pub const TableBgTarget = enum(u32) {
    none = 0,
    row_bg0 = 1,
    row_bg1 = 2,
    cell_bg = 3,
};

pub const BeginTable = struct {
    column: i32,
    flags: TableFlags = .{},
    outer_size: [2]f32 = .{ 0, 0 },
    inner_width: f32 = 0,
};

pub const TableSetupColumn = struct {
    flags: TableColumnFlags = .{},
    init_width_or_height: f32 = 0,
    user_id: Ident = 0,
};

pub const InputTextFlags = packed struct(u32) {
    chars_decimal: bool = false,
    chars_hexadecimal: bool = false,
    chars_uppercase: bool = false,
    chars_no_blank: bool = false,
    auto_select_all: bool = false,
    enter_returns_true: bool = false,
    callback_completion: bool = false,
    callback_history: bool = false,
    callback_always: bool = false,
    callback_char_filter: bool = false,
    allow_tab_input: bool = false,
    ctrl_enter_for_new_line: bool = false,
    no_horizontal_scroll: bool = false,
    always_overwrite: bool = false,
    read_only: bool = false,
    password: bool = false,
    no_undo_redo: bool = false,
    chars_scientific: bool = false,
    callback_resize: bool = false,
    callback_edit: bool = false,
    _padding: u12 = 0,
};
const InputText = struct {
    buf: []u8,
    flags: InputTextFlags = .{},
    callback: ?*anyopaque = null,
    user_data: ?*anyopaque = null,
};

pub const TableNextRow = struct {
    row_flags: TableRowFlags = .{},
    min_row_height: f32 = 0,
};

const InputFloat = struct {
    v: *f32,
    step: f32 = 0.0,
    step_fast: f32 = 0.0,
    cfmt: [:0]const u8 = "%.3f",
    flags: InputTextFlags = .{},
};

const InputDouble = struct {
    v: *f64,
    step: f64 = 0.0,
    step_fast: f64 = 0.0,
    cfmt: [:0]const u8 = "%.6f",
    flags: InputTextFlags = .{},
};

pub fn InputScalarGen(comptime T: type) type {
    return struct {
        v: *T,
        step: ?T = null,
        step_fast: ?T = null,
        cfmt: ?[:0]const u8 = null,
        flags: InputTextFlags = .{},
    };
}

const Checkbox = struct {
    v: *bool,
};

pub const PopupFlags = packed struct(u32) {
    mouse_button_left: bool = false,
    mouse_button_right: bool = false,
    mouse_button_middle: bool = false,
    mouse_button_mask_: bool = false,
    mouse_button_default_: bool = false,
    no_open_over_existing_popup: bool = false,
    no_open_over_items: bool = false,
    any_popup_id: bool = false,
    any_popup_level: bool = false,
    any_popup: bool = false,
    _padding: u22 = 0,
};

const Button = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
};

const SameLine = struct {
    offset_from_start_x: f32 = 0.0,
    spacing: f32 = -1.0,
};

pub const StyleCol = enum(u32) {
    text,
    text_disabled,
    window_bg,
    child_bg,
    popup_bg,
    border,
    border_shadow,
    frame_bg,
    frame_bg_hovered,
    frame_bg_active,
    title_bg,
    title_bg_active,
    title_bg_collapsed,
    menu_bar_bg,
    scrollbar_bg,
    scrollbar_grab,
    scrollbar_grab_hovered,
    scrollbar_grab_active,
    check_mark,
    slider_grab,
    slider_grab_active,
    button,
    button_hovered,
    button_active,
    header,
    header_hovered,
    header_active,
    separator,
    separator_hovered,
    separator_active,
    resize_grip,
    resize_grip_hovered,
    resize_grip_active,
    tab,
    tab_hovered,
    tab_active,
    tab_unfocused,
    tab_unfocused_active,
    plot_lines,
    plot_lines_hovered,
    plot_histogram,
    plot_histogram_hovered,
    table_header_bg,
    table_border_strong,
    table_border_light,
    table_row_bg,
    table_row_bg_alt,
    text_selected_bg,
    drag_drop_target,
    nav_highlight,
    nav_windowing_highlight,
    nav_windowing_dim_bg,
    modal_window_dim_bg,
};
const PushStyleColor4f = struct {
    idx: StyleCol,
    c: [4]f32,
};

const PopStyleColor = struct {
    count: i32 = 1,
};

pub const FocusedFlags = packed struct(u32) {
    child_windows: bool = false,
    root_window: bool = false,
    any_window: bool = false,
    no_popup_hierarchy: bool = false,
    _padding: u28 = 0,

    pub const root_and_child_windows = FocusedFlags{ .root_window = true, .child_windows = true };
};

pub const TableSetBgColor = struct {
    target: TableBgTarget,
    color: u32,
    column_n: i32 = -1,
};

pub const ColorEditFlags = packed struct(u32) {
    no_alpha: bool = false,
    no_picker: bool = false,
    no_options: bool = false,
    no_small_preview: bool = false,
    no_inputs: bool = false,
    no_tooltip: bool = false,
    no_label: bool = false,
    no_side_preview: bool = false,
    no_drag_drop: bool = false,
    no_border: bool = false,

    _reserved0: bool = false,
    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    _reserved4: bool = false,

    alpha_bar: bool = false,
    alpha_preview: bool = false,
    alpha_preview_half: bool = false,
    hdr: bool = false,
    display_rgb: bool = false,
    display_hsv: bool = false,
    display_hex: bool = false,
    uint8: bool = false,
    float: bool = false,
    picker_hue_bar: bool = false,
    picker_hue_wheel: bool = false,
    input_rgb: bool = false,
    input_hsv: bool = false,

    _padding: u4 = 0,

    pub const default_options = ColorEditFlags{
        .uint8 = true,
        .display_rgb = true,
        .input_rgb = true,
        .picker_hue_bar = true,
    };
};
const ColorPicker4 = struct {
    col: *[4]f32,
    flags: ColorEditFlags = .{},
    ref_col: ?[*]const f32 = null,
};

const ColorEdit4 = struct {
    col: *[4]f32,
    flags: ColorEditFlags = .{},
};

const CalcTextSize = struct {
    hide_text_after_double_hash: bool = false,
    wrap_width: f32 = -1.0,
};

pub const Direction = enum(i32) {
    none = -1,
    left = 0,
    right = 1,
    up = 2,
    down = 3,
};

pub const Style = extern struct {
    alpha: f32,
    disabled_alpha: f32,
    window_padding: [2]f32,
    window_rounding: f32,
    window_border_size: f32,
    window_min_size: [2]f32,
    window_title_align: [2]f32,
    window_menu_button_position: Direction,
    child_rounding: f32,
    child_border_size: f32,
    popup_rounding: f32,
    popup_border_size: f32,
    frame_padding: [2]f32,
    frame_rounding: f32,
    frame_border_size: f32,
    item_spacing: [2]f32,
    item_inner_spacing: [2]f32,
    cell_padding: [2]f32,
    touch_extra_padding: [2]f32,
    indent_spacing: f32,
    columns_min_spacing: f32,
    scrollbar_size: f32,
    scrollbar_rounding: f32,
    grab_min_size: f32,
    grab_rounding: f32,
    log_slider_deadzone: f32,
    tab_rounding: f32,
    tab_border_size: f32,
    tab_min_width_for_close_button: f32,
    color_button_position: Direction,
    button_text_align: [2]f32,
    selectable_text_align: [2]f32,
    separator_text_border_size: f32,
    separator_text_align: [2]f32,
    separator_text_padding: [2]f32,
    display_window_padding: [2]f32,
    display_safe_area_padding: [2]f32,
    mouse_cursor_scale: f32,
    anti_aliased_lines: bool,
    anti_aliased_lines_use_tex: bool,
    anti_aliased_fill: bool,
    curve_tessellation_tol: f32,
    circle_tessellation_max_error: f32,

    colors: [@typeInfo(StyleCol).Enum.fields.len][4]f32,

    /// `pub fn init() Style`
    pub const init = zguiStyle_Init;
    extern fn zguiStyle_Init() Style;

    /// `pub fn scaleAllSizes(style: *Style, scale_factor: f32) void`
    pub const scaleAllSizes = zguiStyle_ScaleAllSizes;
    extern fn zguiStyle_ScaleAllSizes(style: *Style, scale_factor: f32) void;

    pub fn getColor(style: Style, idx: StyleCol) [4]f32 {
        return style.colors[@intFromEnum(idx)];
    }
    pub fn setColor(style: *Style, idx: StyleCol, color: [4]f32) void {
        style.colors[@intFromEnum(idx)] = color;
    }
};

pub const ButtonFlags = packed struct(u32) {
    mouse_button_left: bool = false,
    mouse_button_right: bool = false,
    mouse_button_middle: bool = false,
    _padding: u29 = 0,
};
const InvisibleButton = struct {
    w: f32,
    h: f32,
    flags: ButtonFlags = .{},
};

pub const StyleVar = enum(u32) {
    alpha, // 1f
    disabled_alpha, // 1f
    window_padding, // 2f
    window_rounding, // 1f
    window_border_size, // 1f
    window_min_size, // 2f
    window_title_align, // 2f
    child_rounding, // 1f
    child_border_size, // 1f
    popup_rounding, // 1f
    popup_border_size, // 1f
    frame_padding, // 2f
    frame_rounding, // 1f
    frame_border_size, // 1f
    item_spacing, // 2f
    item_inner_spacing, // 2f
    indent_spacing, // 1f
    cell_padding, // 2f
    scrollbar_size, // 1f
    scrollbar_rounding, // 1f
    grab_min_size, // 1f
    grab_rounding, // 1f
    tab_rounding, // 1f
    button_text_align, // 2f
    selectable_text_align, // 2f
    separator_text_border_size, // 1f
    separator_text_align, // 2f
    separator_text_padding, // 2f
};

const PushStyleVar2f = struct {
    idx: StyleVar,
    v: [2]f32,
};

const PushStyleVar1f = struct {
    idx: StyleVar,
    v: f32,
};

const PopStyleVar = struct {
    count: i32 = 1,
};

const BeginChild = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
    border: bool = false,
    flags: WindowFlags = .{},
};

const Dummy = struct {
    w: f32,
    h: f32,
};

pub const DragDropFlags = packed struct(c_int) {
    source_no_preview_tooltip: bool = false,
    source_no_disable_hover: bool = false,
    source_no_hold_open_to_others: bool = false,
    source_allow_null_id: bool = false,
    source_extern: bool = false,
    source_auto_expire_payload: bool = false,

    _padding0: u4 = 0,

    accept_before_delivery: bool = false,
    accept_no_draw_default_rect: bool = false,
    accept_no_preview_tooltip: bool = false,

    _padding1: u19 = 0,

    pub const accept_peek_only = @This(){ .accept_before_delivery = true, .accept_no_draw_default_rect = true };
};

pub const Payload = extern struct {
    data: *anyopaque = null,
    data_size: c_int = 0,
    source_id: c_uint = 0,
    source_parent_id: c_uint = 0,
    data_frame_count: c_int = -1,
    data_type: [32:0]c_char,
    preview: bool = false,
    delivery: bool = false,
};

pub const Condition = enum(c_int) {
    none = 0,
    always = 1,
    once = 2,
    first_use_ever = 4,
    appearing = 8,
};
