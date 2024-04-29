const std = @import("std");

const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const strid = @import("strid.zig");

const platform = @import("platform.zig");
const gfx = @import("gfx.zig");

const log = std.log.scoped(.coreui);

pub const CoreIcons = @import("coreui_icons.zig").Icons;

pub const ObjSelection = cdb.CdbTypeDecl(
    "ct_obj_selection",
    enum(u32) {
        Selection = 0,
    },
    struct {},
);

pub const Colors = struct {
    pub const Deleted = .{ 0.7, 0.0, 0.0, 1.0 };
    pub const Remove = .{ 0.7, 0.0, 0.0, 1.0 };
    pub const Modified = .{ 0.9, 0.9, 0.0, 1.0 };
};

pub const Icons = struct {
    pub const Open = CoreIcons.FA_FOLDER_OPEN;
    pub const OpenProject = CoreIcons.FA_FOLDER_OPEN;
    pub const Create = CoreIcons.FA_CIRCLE_PLUS;

    pub const OpenTab = CoreIcons.FA_WINDOW_MAXIMIZE;
    pub const CloseTab = CoreIcons.FA_RECTANGLE_XMARK;

    pub const Save = CoreIcons.FA_FLOPPY_DISK;
    pub const SaveAll = CoreIcons.FA_FLOPPY_DISK;

    pub const Add = CoreIcons.FA_PLUS;
    pub const AddFile = CoreIcons.FA_FILE_CIRCLE_PLUS;
    pub const AddAsset = CoreIcons.FA_FILE_CIRCLE_PLUS;
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

    pub const Move = CoreIcons.FA_ARROWS_UP_DOWN_LEFT_RIGHT;
    pub const MoveHere = CoreIcons.FA_DOWN_LONG;

    pub const Settings = CoreIcons.FA_SCREWDRIVER_WRENCH;
    pub const Properties = CoreIcons.FA_SLIDERS;
    pub const Buffer = CoreIcons.FA_LAYER_GROUP;
    pub const Windows = CoreIcons.FA_WINDOW_RESTORE;
    pub const Editor = CoreIcons.FA_HOUSE;
    pub const Colors = CoreIcons.FA_PALETTE;
    pub const TickRate = CoreIcons.FA_STOPWATCH_20;
    pub const ContextMenu = CoreIcons.FA_BARS;
    pub const Explorer = CoreIcons.FA_TREE;
    pub const Clear = CoreIcons.FA_BROOM;
    pub const Select = CoreIcons.FA_HAND_POINTER;
    pub const Rename = CoreIcons.FA_PENCIL;
    pub const UITest = CoreIcons.FA_WAND_MAGIC_SPARKLES;

    pub const Reveal = @This().Folder;
    pub const EditInOs = CoreIcons.FA_PENCIL;

    pub const Copy = CoreIcons.FA_COPY;
    pub const Clone = CoreIcons.FA_CLONE;
    pub const Instansiate = CoreIcons.FA_CLONE;

    pub const Help = CoreIcons.FA_CIRCLE_QUESTION;
    pub const Externals = CoreIcons.FA_THUMBS_UP;
    pub const Authors = CoreIcons.FA_USER_INJURED;

    pub const Link = CoreIcons.FA_LINK;
};

pub const CoreUII = struct {
    pub const c_name = "ct_coreui_ui_i";
    pub const name_hash = strid.strId64(@This().c_name);

    ui: *const fn (allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) anyerror!void,

    pub inline fn implement(comptime T: type) CoreUII {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return CoreUII{
            .ui = T.ui,
        };
    }
};

// Test
pub const Actions = enum(c_int) {
    Unknown = 0,
    Hover, // Move mouse
    Click, // Move mouse and click
    DoubleClick, // Move mouse and double-click
    Check, // Check item if unchecked (Checkbox, MenuItem or any widget reporting ImGuiItemStatusFlags_Checkable)
    Uncheck, // Uncheck item if checked
    Open, // Open item if closed (TreeNode, BeginMenu or any widget reporting ImGuiItemStatusFlags_Openable)
    Close, // Close item if opened
    Input, // Start text inputing into a field (e.g. CTRL+Click on Drags/Slider, click on InputText etc.)
    NavActivate, // Activate item with navigation
    COUNT,
};

pub const TestOpFlags = packed struct(c_int) {
    NoCheckHoveredId: bool = false, // Don't check for HoveredId after aiming for a widget. A few situations may want this: while e.g. dragging or another items prevents hovering, or for items that don't use ItemHoverable()
    NoError: bool = false, // Don't abort/error e.g. if the item cannot be found or the operation doesn't succeed.
    NoFocusWindow: bool = false, // Don't focus window when aiming at an item
    NoAutoUncollapse: bool = false, // Disable automatically uncollapsing windows (useful when specifically testing Collapsing behaviors)
    NoAutoOpenFullPath: bool = false, // Disable automatically opening intermediaries (e.g. ItemClick("Hello/OK") will automatically first open "Hello" if "OK" isn't found. Only works if ref is a string path.
    IsSecondAttempt: bool = false, // Used by recursing functions to indicate a second attempt
    MoveToEdgeL: bool = false, // Simple Dumb aiming helpers to test widget that care about clicking position. May need to replace will better functionalities.
    MoveToEdgeR: bool = false,
    MoveToEdgeU: bool = false,
    MoveToEdgeD: bool = false,
    _padding: u22 = 0,
};

pub const ImGuiTestRunSpeed = enum(c_int) {
    Fast = 0, // Run tests as fast as possible (teleport mouse, skip delays, etc.)
    Normal = 1, // Run tests at human watchable speed (for debugging)
    Cinematic = 2, // Run tests with pauses between actions (for e.g. tutorials)
};

pub const CheckFlags = packed struct(c_int) {
    silentSuccess: bool = false,
    _padding: u31 = 0,
};

pub const ImGuiTestGuiFunc = fn (context: *TestContext) callconv(.C) void;
pub const ImGuiTestTestFunc = fn (context: *TestContext) callconv(.C) void;
pub const Test = anyopaque;
pub const TestContext = opaque {
    pub fn setRef(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8) void {
        return coreui_api.testContextSetRef(ctx, ref);
    }

    pub fn itemAction(ctx: *TestContext, coreui_api: *const CoreUIApi, action: Actions, ref: [:0]const u8, flags: TestOpFlags, action_arg: ?*anyopaque) void {
        return coreui_api.testItemAction(ctx, action, ref, flags, action_arg);
    }

    pub fn windowFocus(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8) void {
        return coreui_api.testContextWindowFocus(ctx, ref);
    }

    pub fn yield(ctx: *TestContext, coreui_api: *const CoreUIApi, frame_count: i32) void {
        return coreui_api.testContextYield(ctx, frame_count);
    }

    pub fn menuAction(ctx: *TestContext, coreui_api: *const CoreUIApi, action: Actions, ref: [:0]const u8) void {
        return coreui_api.testContextMenuAction(ctx, action, ref);
    }

    pub fn itemInputStrValue(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8, value: [:0]const u8) void {
        return coreui_api.testItemInputStrValue(ctx, ref, value);
    }

    pub fn itemInputIntValue(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8, value: i32) void {
        return coreui_api.testItemInputIntValue(ctx, ref, value);
    }

    pub fn itemInputFloatValue(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8, value: f32) void {
        return coreui_api.testItemInputFloatValue(ctx, ref, value);
    }
    pub fn dragAndDrop(ctx: *TestContext, coreui_api: *const CoreUIApi, ref_src: [:0]const u8, ref_dst: [:0]const u8, button: MouseButton) void {
        return coreui_api.testDragAndDrop(ctx, ref_src, ref_dst, button);
    }
    pub fn keyDown(ctx: *TestContext, coreui_api: *const CoreUIApi, key_chord: Key) void {
        return coreui_api.testKeyDown(ctx, key_chord);
    }

    pub fn keyUp(ctx: *TestContext, coreui_api: *const CoreUIApi, key_chord: Key) void {
        return coreui_api.testKeyUp(ctx, key_chord);
    }
};

pub const RegisterTestsI = struct {
    pub const c_name = "ct_coreui_register_tests_i";
    pub const name_hash = strid.strId64(@This().c_name);

    register_tests: *const fn () anyerror!void,

    pub inline fn implement(comptime T: type) @This() {
        if (!std.meta.hasFn(T, "registerTests")) @compileError("implement me");

        return @This(){
            .register_tests = T.registerTests,
        };
    }
};

pub const FilterItem = extern struct {
    name: [*:0]const u8,
    spec: [*:0]const u8,
};

pub const CoreUIApi = struct {
    pub fn checkTestError(
        coreui_api: *const CoreUIApi,
        src: std.builtin.SourceLocation,
        err: anyerror,
    ) void {
        var buff: [128:0]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buff, "Assert error: {}", .{err}) catch undefined;
        _ = coreui_api.testCheck(src, .{}, false, msg);
    }

    pub fn registerTest(
        self: @This(),
        category: [:0]const u8,
        name: [:0]const u8,
        src: std.builtin.SourceLocation,
        comptime Callbacks: type,
    ) *Test {
        return self.registerTestFn(
            category.ptr,
            name.ptr,
            src.file.ptr,
            @intCast(src.line),
            if (std.meta.hasFn(Callbacks, "gui"))
                struct {
                    fn f(context: *TestContext) callconv(.C) void {
                        Callbacks.gui(context) catch undefined;
                    }
                }.f
            else
                null,

            if (std.meta.hasFn(Callbacks, "run"))
                struct {
                    fn f(context: *TestContext) callconv(.C) void {
                        Callbacks.run(context) catch |err| {
                            std.log.err("Test failed: {}", .{err});
                        };
                    }
                }.f
            else
                null,
        );
    }

    showDemoWindow: *const fn () void,
    showTestingWindow: *const fn (show: *bool) void,
    showExternalCredits: *const fn (show: *bool) void,
    showAuthors: *const fn (show: *bool) void,

    // Filter
    uiFilter: *const fn (buf: []u8, filter: ?[:0]const u8) ?[:0]const u8,
    uiFilterPass: *const fn (allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64,

    // NFD
    supportFileDialog: *const fn () bool,
    openFileDialog: *const fn (allocator: std.mem.Allocator, filter: ?[]const FilterItem, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    saveFileDialog: *const fn (allocator: std.mem.Allocator, filter: ?[]const FilterItem, default_path: ?[:0]const u8, default_name: ?[:0]const u8) anyerror!?[:0]const u8,
    openFolderDialog: *const fn (allocator: std.mem.Allocator, default_path: ?[:0]const u8) anyerror!?[:0]const u8,

    // shit from the pointer deep.
    begin: *const fn (name: [:0]const u8, args: Begin) bool,
    end: *const fn () void,

    isItemToggledOpen: *const fn () bool,
    dummy: *const fn (args: Dummy) void,
    spacing: *const fn () void,

    getScrollX: *const fn () f32,
    getScrollY: *const fn () f32,
    getScrollMaxX: *const fn () f32,
    getScrollMaxY: *const fn () f32,
    setScrollHereY: *const fn (args: SetScrollHereY) void,
    setScrollHereX: *const fn (args: SetScrollHereX) void,

    getFontSize: *const fn () f32,

    getStyle: *const fn () *Style,
    pushStyleVar2f: *const fn (args: PushStyleVar2f) void,
    pushStyleVar1f: *const fn (args: PushStyleVar1f) void,
    pushStyleColor4f: *const fn (args: PushStyleColor4f) void,
    popStyleColor: *const fn (args: PopStyleColor) void,
    popStyleVar: *const fn (args: PopStyleVar) void,

    isKeyDown: *const fn (key: Key) bool,

    tableSetBgColor: *const fn (args: TableSetBgColor) void,

    colorConvertFloat4ToU32: *const fn (in: [4]f32) u32,

    text: *const fn (txt: []const u8) void,
    textColored: *const fn (color: [4]f32, txt: []const u8) void,

    colorPicker4: *const fn (label: [:0]const u8, args: ColorPicker4) bool,
    colorEdit4: *const fn (label: [:0]const u8, args: ColorEdit4) bool,

    beginMainMenuBar: *const fn () void,
    endMainMenuBar: *const fn () void,
    beginMenuBar: *const fn () void,
    endMenuBar: *const fn () void,

    beginMenu: *const fn (allocator: std.mem.Allocator, label: [:0]const u8, enabled: bool, filter: ?[:0]const u8) bool,
    endMenu: *const fn () void,
    menuItem: *const fn (allocator: std.mem.Allocator, label: [:0]const u8, args: MenuItem, filter: ?[:0]const u8) bool,
    menuItemPtr: *const fn (allocator: std.mem.Allocator, label: [:0]const u8, args: MenuItemPtr, filter: ?[:0]const u8) bool,

    beginChild: *const fn (str_id: [:0]const u8, args: BeginChild) bool,
    endChild: *const fn () void,

    pushPtrId: *const fn (ptr_id: *const anyopaque) void,
    pushIntId: *const fn (int_id: u32) void,
    pushObjUUID: *const fn (obj: cdb.ObjId) void,
    pushPropName: *const fn (db: cdb.Db, obj: cdb.ObjId, prop_idx: u32) void,

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
    inputF32: *const fn (label: [:0]const u8, args: InputF32) bool,
    inputF64: *const fn (label: [:0]const u8, args: InputF64) bool,
    inputI32: *const fn (label: [:0]const u8, args: InputScalarGen(i32)) bool,
    inputU32: *const fn (label: [:0]const u8, args: InputScalarGen(u32)) bool,
    inputI64: *const fn (label: [:0]const u8, args: InputScalarGen(i64)) bool,
    inputU64: *const fn (label: [:0]const u8, args: InputScalarGen(u64)) bool,

    dragF32: *const fn (label: [:0]const u8, args: DragFloatGen(f32)) bool,
    dragF64: *const fn (label: [:0]const u8, args: DragScalarGen(f64)) bool,
    dragI32: *const fn (label: [:0]const u8, args: DragScalarGen(i32)) bool,
    dragU32: *const fn (label: [:0]const u8, args: DragScalarGen(u32)) bool,
    dragI64: *const fn (label: [:0]const u8, args: DragScalarGen(i64)) bool,
    dragU64: *const fn (label: [:0]const u8, args: DragScalarGen(u64)) bool,

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
    setNextWindowSize: *const fn (args: SetNextWindowSize) void,

    beginTable: *const fn (name: [:0]const u8, args: BeginTable) bool,
    endTable: *const fn () void,
    tableSetupColumn: *const fn (label: [:0]const u8, args: TableSetupColumn) void,
    tableHeadersRow: *const fn () void,
    tableNextColumn: *const fn () void,
    tableNextRow: *const fn (args: TableNextRow) void,
    tableSetupScrollFreeze: *const fn (cols: i32, rows: i32) void,

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

    // Selection OBJ
    isSelected: *const fn (db: cdb.Db, selection: cdb.ObjId, obj: cdb.ObjId) bool,
    addToSelection: *const fn (db: cdb.Db, selection: cdb.ObjId, obj: cdb.ObjId) anyerror!void,
    removeFromSelection: *const fn (db: cdb.Db, selection: cdb.ObjId, obj: cdb.ObjId) anyerror!void,
    clearSelection: *const fn (allocator: std.mem.Allocator, db: cdb.Db, selection: cdb.ObjId) anyerror!void,
    setSelection: *const fn (allocator: std.mem.Allocator, db: cdb.Db, selection: cdb.ObjId, obj: cdb.ObjId) anyerror!void,
    selectedCount: *const fn (allocator: std.mem.Allocator, db: cdb.Db, selection: cdb.ObjId) u32,
    getFirstSelected: *const fn (allocator: std.mem.Allocator, db: cdb.Db, selection: cdb.ObjId) cdb.ObjId,
    getSelected: *const fn (allocator: std.mem.Allocator, db: cdb.Db, selection: cdb.ObjId) ?[]const cdb.ObjId,
    handleSelection: *const fn (allocator: std.mem.Allocator, db: cdb.Db, selection: cdb.ObjId, obj: cdb.ObjId, multiselect_enabled: bool) anyerror!void,

    // TODO: MOVE?
    // Tests
    reloadTests: *const fn () anyerror!void,

    registerTestFn: *const fn (
        category: [*]const u8,
        name: [*]const u8,
        src: [*]const u8,
        src_line: c_int,
        gui_fce: ?*const ImGuiTestGuiFunc,
        gui_test_fce: ?*const ImGuiTestTestFunc,
    ) *Test,

    testContextSetRef: *const fn (ctx: *TestContext, ref: [:0]const u8) void,
    testContextWindowFocus: *const fn (ctx: *TestContext, ref: [:0]const u8) void,
    testItemAction: *const fn (ctx: *TestContext, action: Actions, ref: [:0]const u8, flags: TestOpFlags, action_arg: ?*anyopaque) void,
    testItemInputStrValue: *const fn (ctx: *TestContext, ref: [:0]const u8, value: [:0]const u8) void,
    testItemInputIntValue: *const fn (ctx: *TestContext, ref: [:0]const u8, value: i32) void,
    testItemInputFloatValue: *const fn (ctx: *TestContext, ref: [:0]const u8, value: f32) void,
    testContextYield: *const fn (ctx: *TestContext, frame_count: i32) void,
    testContextMenuAction: *const fn (ctx: *TestContext, action: Actions, ref: [:0]const u8) void,
    testDragAndDrop: *const fn (ctx: *TestContext, ref_src: [:0]const u8, ref_dst: [:0]const u8, button: MouseButton) void,
    testKeyDown: *const fn (ctx: *TestContext, key_chord: Key) void,
    testKeyUp: *const fn (ctx: *TestContext, key_chord: Key) void,
    testIsRunning: *const fn () bool,
    testRunAll: *const fn (filter: [:0]const u8) void,
    testPrintResult: *const fn () void,
    testGetResult: *const fn () TestResult,
    testSetRunSpeed: *const fn (speed: ImGuiTestRunSpeed) void,
    testExportJunitResult: *const fn (filename: [:0]const u8) void,
    testCheck: *const fn (src: std.builtin.SourceLocation, flags: CheckFlags, resul: bool, expr: [:0]const u8) bool,

    setScaleFactor: *const fn (scale_factor: f32) void,
    getScaleFactor: *const fn () f32,

    image: *const fn (texture: gfx.TextureHandle, args: Image) void,
    getMousePos: *const fn () [2]f32,
    getMouseDragDelta: *const fn (drag_button: MouseButton, args: MouseDragDelta) [2]f32,
    setMouseCursor: *const fn (cursor: Cursor) void,

    mainDockSpace: *const fn (flags: DockNodeFlags) Ident,
};

pub const Image = struct {
    flags: u8,
    mip: u8,
    w: f32,
    h: f32,
    uv0: [2]f32 = .{ 0.0, 0.0 },
    uv1: [2]f32 = .{ 1.0, 1.0 },
    tint_col: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    border_col: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
};

// Copy from zgui (THc a.k.a Temp hack)
// TODO: Make own abstract types
pub const DockNodeFlags = packed struct(c_int) {
    keep_alive_only: bool = false,
    _reserved: u1 = 0,
    no_docking_over_central_node: bool = false,
    passthru_central_node: bool = false,
    no_docking_split: bool = false,
    no_resize: bool = false,
    auto_hide_tab_bar: bool = false,
    no_undocking: bool = false,
    _padding: u24 = 0,
};

pub const Ident = u32;

const SetScrollHereX = struct {
    center_x_ratio: f32 = 0.5,
};
const SetScrollHereY = struct {
    center_y_ratio: f32 = 0.5,
};

const SetNextWindowSize = struct {
    w: f32,
    h: f32,
    cond: Condition = .none,
};

pub const TestResult = struct {
    count_tested: i32,
    count_success: i32,
};

const Begin = struct {
    popen: ?*bool = null,
    flags: WindowFlags = .{},
};

pub const WindowFlags = packed struct(c_int) {
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
    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,
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

pub const ChildFlags = packed struct(c_int) {
    border: bool = false,
    no_move: bool = false,
    always_use_window_padding: bool = false,
    resize_x: bool = false,
    resize_y: bool = false,
    auto_resize_x: bool = false,
    auto_resize_y: bool = false,
    always_auto_resize: bool = false,
    frame_style: bool = false,
    _padding: u23 = 0,
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

pub const TreeNodeFlags = packed struct(c_int) {
    selected: bool = false,
    framed: bool = false,
    allow_overlap: bool = false,
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
    span_all_columns: bool = false,
    nav_left_jumps_back_here: bool = false,
    _padding: u17 = 0,

    pub const collapsing_header = TreeNodeFlags{
        .framed = true,
        .no_tree_push_on_open = true,
        .no_auto_open_on_log = true,
    };
};

pub const HoveredFlags = packed struct(c_int) {
    child_windows: bool = false,
    root_window: bool = false,
    any_window: bool = false,
    no_popup_hierarchy: bool = false,
    dock_hierarchy: bool = false,
    allow_when_blocked_by_popup: bool = false,
    _reserved1: bool = false,
    allow_when_blocked_by_active_item: bool = false,
    allow_when_overlapped_by_item: bool = false,
    allow_when_overlapped_by_window: bool = false,
    allow_when_disabled: bool = false,
    no_nav_override: bool = false,
    for_tooltip: bool = false,
    stationary: bool = false,
    delay_none: bool = false,
    delay_normal: bool = false,
    delay_short: bool = false,
    no_shared_delay: bool = false,
    _padding: u14 = 0,

    pub const rect_only = HoveredFlags{
        .allow_when_blocked_by_popup = true,
        .allow_when_blocked_by_active_item = true,
        .allow_when_overlapped_by_item = true,
        .allow_when_overlapped_by_window = true,
    };
    pub const root_and_child_windows = HoveredFlags{ .root_window = true, .child_windows = true };
};

pub const MouseButton = enum(u32) {
    left = 0,
    right = 1,
    middle = 2,
};

pub const MouseDragDelta = struct {
    lock_threshold: f32 = -1.0,
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
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
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

    app_back,
    app_forward,

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

pub const Cursor = enum(c_int) {
    none = -1,
    arrow = 0,
    text_input,
    resize_all,
    resize_ns,
    resize_ew,
    resize_nesw,
    resize_nwse,
    hand,
    not_allowed,
    count,
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
    buf: [:0]u8,
    flags: InputTextFlags = .{},
    callback: ?*anyopaque = null,
    user_data: ?*anyopaque = null,
};

pub const TableNextRow = struct {
    row_flags: TableRowFlags = .{},
    min_row_height: f32 = 0,
};

const InputF32 = struct {
    v: *f32,
    step: f32 = 0.0,
    step_fast: f32 = 0.0,
    cfmt: [:0]const u8 = "%.3f",
    flags: InputTextFlags = .{},
};

const InputF64 = struct {
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

pub const PopupFlags = packed struct(c_int) {
    mouse_button_left: bool = false,
    mouse_button_right: bool = false,
    mouse_button_middle: bool = false,

    _reserved0: bool = false,
    _reserved1: bool = false,

    no_reopen: bool = false,
    _reserved2: bool = false,
    no_open_over_existing_popup: bool = false,
    no_open_over_items: bool = false,
    any_popup_id: bool = false,
    any_popup_level: bool = false,
    _padding: u21 = 0,

    pub const any_popup = PopupFlags{ .any_popup_id = true, .any_popup_level = true };
};

const Button = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
};

const SameLine = struct {
    offset_from_start_x: f32 = 0.0,
    spacing: f32 = -1.0,
};

pub const StyleCol = enum(c_int) {
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
    docking_preview,
    docking_empty_bg,
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

pub const FocusedFlags = packed struct(c_int) {
    child_windows: bool = false,
    root_window: bool = false,
    any_window: bool = false,
    no_popup_hierarchy: bool = false,
    dock_hierarchy: bool = false,
    _padding: u27 = 0,

    pub const root_and_child_windows = FocusedFlags{ .root_window = true, .child_windows = true };
};
pub const TableSetBgColor = struct {
    target: TableBgTarget,
    color: u32,
    column_n: i32 = -1,
};

pub const ColorEditFlags = packed struct(c_int) {
    _reserved0: bool = false,
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

    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    _reserved4: bool = false,
    _reserved5: bool = false,

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

    _padding: u3 = 0,

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

pub const Direction = enum(c_int) {
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
    tab_bar_border_size: f32,
    table_angled_header_angle: f32,
    color_button_position: Direction,
    button_text_align: [2]f32,
    selectable_text_align: [2]f32,
    separator_text_border_size: f32,
    separator_text_align: [2]f32,
    separator_text_padding: [2]f32,
    display_window_padding: [2]f32,
    display_safe_area_padding: [2]f32,
    docking_separator_size: f32,
    mouse_cursor_scale: f32,
    anti_aliased_lines: bool,
    anti_aliased_lines_use_tex: bool,
    anti_aliased_fill: bool,
    curve_tessellation_tol: f32,
    circle_tessellation_max_error: f32,

    colors: [@typeInfo(StyleCol).Enum.fields.len][4]f32,

    hover_stationary_delay: f32,
    hover_delay_short: f32,
    hover_delay_normal: f32,

    hover_flags_for_tooltip_mouse: HoveredFlags,
    hover_flags_for_tooltip_nav: HoveredFlags,

    /// `pub fn init() Style`
    pub const init = zguiStyle_Init;
    extern fn zguiStyle_Init() Style;

    /// `pub fn scaleAllSizes(style: *Style, scale_factor: f32) void`
    pub const scaleAllSizes = zguiStyle_ScaleAllSizes;
    extern fn zguiStyle_ScaleAllSizes(style: *Style, scale_factor: f32) void;

    pub fn getColor(style: Style, idx: StyleCol) [4]f32 {
        return style.colors[@intCast(@intFromEnum(idx))];
    }
    pub fn setColor(style: *Style, idx: StyleCol, color: [4]f32) void {
        style.colors[@intCast(@intFromEnum(idx))] = color;
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

pub const StyleVar = enum(c_int) {
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
    tab_bar_border_size, // 1f
    button_text_align, // 2f
    selectable_text_align, // 2f
    separator_text_border_size, // 1f
    separator_text_align, // 2f
    separator_text_padding, // 2f
    docking_separator_size, // 1f
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
    child_flags: ChildFlags = .{},
    window_flags: WindowFlags = .{},
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
    data: ?*anyopaque = null,
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

pub const SliderFlags = packed struct(c_int) {
    _reserved0: bool = false,
    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    always_clamp: bool = false,
    logarithmic: bool = false,
    no_round_to_format: bool = false,
    no_input: bool = false,
    _padding: u24 = 0,
};

pub fn DragFloatGen(comptime T: type) type {
    return struct {
        v: *T,
        speed: f32 = 1.0,
        min: f32 = 0.0,
        max: f32 = 0.0,
        cfmt: [:0]const u8 = "%.3f",
        flags: SliderFlags = .{},
    };
}

pub fn DragIntGen(comptime T: type) type {
    return struct {
        v: *T,
        speed: f32 = 1.0,
        min: i32 = 0.0,
        max: i32 = 0.0,
        cfmt: [:0]const u8 = "%d",
        flags: SliderFlags = .{},
    };
}

pub fn DragScalarGen(comptime T: type) type {
    return struct {
        v: *T,
        speed: f32 = 1.0,
        min: ?T = null,
        max: ?T = null,
        cfmt: ?[:0]const u8 = null,
        flags: SliderFlags = .{},
    };
}
