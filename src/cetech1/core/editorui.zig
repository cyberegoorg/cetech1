const std = @import("std");

const c = @import("c.zig").c;
const cdb = @import("cdb.zig");
const modules = @import("modules.zig");

const system = @import("system.zig");
const gpu = @import("gpu.zig");
const icons = @import("editorui_icons.zig");

pub const Icons = icons.Icons;

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
                    std.log.err("UiPropertyAspect {}", .{err});
                };
            }
        };

        return EditorUII{
            .ui = Wrap.ui_c,
        };
    }
};

pub const EditorUIApi = struct {
    enableWithWindow: *const fn (window: *system.Window, gpuctx: *gpu.GpuContext) void,
    newFrame: *const fn () void,
    showDemoWindow: *const fn () void,

    // NFD
    openFileDialog: *const fn (filter: ?[:0]const u8, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    saveFileDialog: *const fn (filter: ?[:0]const u8, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    openFolderDialog: *const fn (default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    freePath: *const fn (path: []const u8) void,

    // shit from the pointer deep.
    begin: *const fn (name: [:0]const u8, args: Begin) bool,
    end: *const fn () void,

    isItemToggledOpen: *const fn () bool,

    pushStyleColor4f: *const fn (args: PushStyleColor4f) void,
    popStyleColor: *const fn (args: PopStyleColor) void,
    tableSetBgColor: *const fn (args: TableSetBgColor) void,

    colorConvertFloat4ToU32: *const fn (in: [4]f32) u32,

    textUnformatted: *const fn (txt: []const u8) void,
    textUnformattedColored: *const fn (color: [4]f32, txt: []const u8) void,

    beginMainMenuBar: *const fn () void,
    endMainMenuBar: *const fn () void,
    beginMenuBar: *const fn () void,
    endMenuBar: *const fn () void,

    beginMenu: *const fn (label: [:0]const u8, enabled: bool) bool,
    endMenu: *const fn () void,
    menuItem: *const fn (label: [:0]const u8, args: MenuItem) bool,
    menuItemPtr: *const fn (label: [:0]const u8, args: MenuItemPtr) bool,

    pushPtrId: *const fn (ptr_id: *const anyopaque) void,
    pushIntId: *const fn (int_id: u32) void,
    popId: *const fn () void,

    treeNode: *const fn (label: [:0]const u8) bool,
    treeNodeFlags: *const fn (label: [:0]const u8, flags: TreeNodeFlags) bool,
    treePop: *const fn () void,

    alignTextToFramePadding: *const fn () void,

    isItemHovered: *const fn (flags: HoveredFlags) bool,
    isWindowFocused: *const fn (flags: FocusedFlags) bool,

    labelText: *const fn (label: [:0]const u8, text: [:0]const u8) void,
    button: *const fn (label: [:0]const u8, args: Button) bool,

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
