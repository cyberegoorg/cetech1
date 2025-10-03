// TODO: TMP SHIT big module
const std = @import("std");

const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const cetech1 = @import("root.zig");

const platform = @import("platform.zig");
const gpu = @import("gpu.zig");
const ArraySet = @import("root.zig").ArraySet;

const log = std.log.scoped(.coreui);

pub const CoreIcons = @import("coreui_icons.zig").Icons;

// TODO: taged union?
pub const SelectionItem = struct {
    top_level_obj: cdb.ObjId,
    obj: cdb.ObjId,

    in_set_obj: ?cdb.ObjId = null,
    parent_obj: ?cdb.ObjId = null,
    prop_idx: ?u32 = null,

    pub fn isEmpty(self: SelectionItem) bool {
        return self.obj.isEmpty();
    }

    pub fn empty() SelectionItem {
        return .{ .top_level_obj = .{}, .obj = .{} };
    }

    pub fn eql(self: SelectionItem, other: SelectionItem) SelectionItem {
        return std.mem.eql(u8, std.mem.toBytes(self), std.mem.toBytes(other));
    }
};

// TODO: TEMP solution. need api
pub const Selection = struct {
    const Item = SelectionItem;
    const SetImpl = ArraySet(Item);

    storage: SetImpl = .init(),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Selection {
        return Selection{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Selection) void {
        self.storage.deinit(self.allocator);
    }

    pub fn clear(self: *Selection) void {
        self.storage.clearRetainingCapacity();
    }

    pub fn add(self: *Selection, objs: []const Item) !void {
        _ = try self.storage.appendSlice(self.allocator, objs);
    }

    pub fn remove(self: *Selection, objs: []const Item) void {
        self.storage.removeAllSlice(objs);
    }

    pub fn set(self: *Selection, objs: []const Item) !void {
        self.clear();
        try self.add(objs);
    }

    pub fn isSelected(self: *Selection, obj: Item) bool {
        return self.storage.contains(obj);
    }

    pub fn isSelectedAll(self: *Selection, obj: []const Item) bool {
        return self.storage.containsAllSlice(obj);
    }

    pub fn count(self: Selection) usize {
        return self.storage.cardinality();
    }

    pub fn toSlice(self: Selection, allocator: std.mem.Allocator) ?[]Item {
        var result = cetech1.ArrayList(Item).initCapacity(allocator, self.count()) catch return null;
        var it = self.storage.iterator();

        while (it.next()) |v| {
            result.appendAssumeCapacity(v.key_ptr.*);
        }

        return result.toOwnedSlice(allocator) catch return null;
    }

    pub fn first(self: Selection) Item {
        var it = self.storage.iterator();
        while (it.next()) |v| {
            return v.key_ptr.*;
        }

        return SelectionItem.empty();
    }

    pub fn isEmpty(self: Selection) bool {
        return self.storage.isEmpty();
    }
};

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

    pub const Add = CoreIcons.FA_CIRCLE_PLUS;
    pub const AddFile = CoreIcons.FA_FILE_CIRCLE_PLUS;
    pub const AddAsset = CoreIcons.FA_FILE_CIRCLE_PLUS;
    pub const AddFolder = CoreIcons.FA_FOLDER_PLUS;
    pub const Remove = CoreIcons.FA_CIRCLE_MINUS;
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

    pub const Graph = CoreIcons.FA_DIAGRAM_PROJECT;
    pub const FitContent = CoreIcons.FA_ARROWS_TO_CIRCLE;
    pub const Build = CoreIcons.FA_GEARS;

    pub const Group = CoreIcons.FA_OBJECT_GROUP;
    pub const Node = CoreIcons.FA_VECTOR_SQUARE;
    pub const Connection = CoreIcons.FA_LINK;
    pub const Const = CoreIcons.FA_PENCIL;
    pub const Random = CoreIcons.FA_SHUFFLE;
    pub const Bounding = CoreIcons.FA_ENVELOPE;

    pub const Input = CoreIcons.FA_RIGHT_TO_BRACKET;
    pub const Output = CoreIcons.FA_RIGHT_FROM_BRACKET;

    pub const Metrics = CoreIcons.FA_CHART_LINE;

    pub const Entity = CoreIcons.FA_ROBOT;
    pub const Component = CoreIcons.FA_POO;

    pub const Position = CoreIcons.FA_UP_DOWN_LEFT_RIGHT;
    pub const Rotation = CoreIcons.FA_ROTATE;
    pub const Scale = CoreIcons.FA_UP_RIGHT_AND_DOWN_LEFT_FROM_CENTER;

    pub const Play = CoreIcons.FA_PLAY;
    pub const Pause = CoreIcons.FA_PAUSE;

    pub const Camera = CoreIcons.FA_CAMERA;
    pub const Draw = CoreIcons.FA_BRUSH;

    pub const Filter = CoreIcons.FA_FILTER;

    pub const Light = CoreIcons.FA_LIGHTBULB;

    pub const RenderPipeline = CoreIcons.FA_PHOTO_FILM;
};

pub const CoreUII = struct {
    pub const c_name = "ct_coreui_ui_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

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

pub const ImGuiTestGuiFunc = fn (context: *TestContext) callconv(.c) void;
pub const ImGuiTestTestFunc = fn (context: *TestContext) callconv(.c) void;
pub const Test = anyopaque;
pub const TestContext = opaque {
    pub inline fn setRef(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8) void {
        return coreui_api.testContextSetRef(ctx, ref);
    }

    pub inline fn itemAction(ctx: *TestContext, coreui_api: *const CoreUIApi, action: Actions, ref: [:0]const u8, flags: TestOpFlags, action_arg: ?*anyopaque) void {
        return coreui_api.testItemAction(ctx, action, ref, flags, action_arg);
    }

    pub inline fn windowFocus(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8) void {
        return coreui_api.testContextWindowFocus(ctx, ref);
    }

    pub inline fn yield(ctx: *TestContext, coreui_api: *const CoreUIApi, frame_count: i32) void {
        return coreui_api.testContextYield(ctx, frame_count);
    }

    pub inline fn menuAction(ctx: *TestContext, coreui_api: *const CoreUIApi, action: Actions, ref: [:0]const u8) void {
        return coreui_api.testContextMenuAction(ctx, action, ref);
    }

    pub inline fn itemInputStrValue(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8, value: [:0]const u8) void {
        return coreui_api.testItemInputStrValue(ctx, ref, value);
    }

    pub inline fn itemInputIntValue(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8, value: i32) void {
        return coreui_api.testItemInputIntValue(ctx, ref, value);
    }

    pub inline fn itemInputFloatValue(ctx: *TestContext, coreui_api: *const CoreUIApi, ref: [:0]const u8, value: f32) void {
        return coreui_api.testItemInputFloatValue(ctx, ref, value);
    }
    pub inline fn dragAndDrop(ctx: *TestContext, coreui_api: *const CoreUIApi, ref_src: [:0]const u8, ref_dst: [:0]const u8, button: MouseButton) void {
        return coreui_api.testDragAndDrop(ctx, ref_src, ref_dst, button);
    }
    pub inline fn keyDown(ctx: *TestContext, coreui_api: *const CoreUIApi, key_chord: Key) void {
        return coreui_api.testKeyDown(ctx, key_chord);
    }

    pub inline fn keyUp(ctx: *TestContext, coreui_api: *const CoreUIApi, key_chord: Key) void {
        return coreui_api.testKeyUp(ctx, key_chord);
    }
};

pub const RegisterTestsI = struct {
    pub const c_name = "ct_coreui_register_tests_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

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

const BeginDisabled = struct {
    disabled: bool = true,
};

pub const ComboArgs = struct {
    current_item: *i32,
    items_separated_by_zeros: [:0]const u8,
    popup_max_height_in_items: i32 = -1,
};

pub const CoreUIApi = struct {
    pub inline fn checkTestError(
        coreui_api: *const CoreUIApi,
        src: std.builtin.SourceLocation,
        err: anyerror,
    ) void {
        var buff: [128:0]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buff, "Assert error: {}", .{err}) catch undefined;
        _ = coreui_api.testCheck(src, .{}, false, msg);
    }

    pub inline fn registerTest(
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
                    fn f(context: *TestContext) callconv(.c) void {
                        Callbacks.gui(context) catch undefined;
                    }
                }.f
            else
                null,

            if (std.meta.hasFn(Callbacks, "run"))
                struct {
                    fn f(context: *TestContext) callconv(.c) void {
                        Callbacks.run(context) catch |err| {
                            std.log.err("Test failed: {}", .{err});
                        };
                    }
                }.f
            else
                null,
        );
    }

    pub fn comboFromEnum(
        self: CoreUIApi,
        label: [:0]const u8,
        /// must be a pointer to an enum value (var my_enum: *FoodKinds = .Banana)
        /// that is backed by some kind of integer that can safely cast into an
        /// i32 (the underlying imgui restriction)
        current_item: anytype,
    ) bool {
        const EnumType = @TypeOf(current_item.*);
        const enum_type_info = getTypeInfo: {
            switch (@typeInfo(EnumType)) {
                .optional => |optional_type_info| switch (@typeInfo(optional_type_info.child)) {
                    .@"enum" => |enum_type_info| break :getTypeInfo enum_type_info,
                    else => {},
                },
                .@"enum" => |enum_type_info| break :getTypeInfo enum_type_info,
                else => {},
            }
            @compileError("Error: current_item must be a pointer-to-an-enum, not a " ++ @TypeOf(EnumType));
        };

        const FieldNameIndex = std.meta.Tuple(&.{ []const u8, i32 });
        comptime var item_names: [:0]const u8 = "";
        comptime var field_name_to_index_list: [enum_type_info.fields.len]FieldNameIndex = undefined;
        comptime var index_to_enum: [enum_type_info.fields.len]EnumType = undefined;

        comptime {
            for (enum_type_info.fields, 0..) |f, i| {
                item_names = item_names ++ f.name ++ "\x00";
                const e: EnumType = @enumFromInt(f.value);
                field_name_to_index_list[i] = .{ f.name, @intCast(i) };
                index_to_enum[i] = e;
            }
        }

        const field_name_to_index = std.StaticStringMap(i32).initComptime(&field_name_to_index_list);

        var item: i32 =
            switch (@typeInfo(EnumType)) {
                .optional => if (current_item.*) |tag| field_name_to_index.get(@tagName(tag)) orelse -1 else -1,
                .@"enum" => field_name_to_index.get(@tagName(current_item.*)) orelse -1,
                else => unreachable,
            };

        const result = self.combo(label, .{
            .items_separated_by_zeros = item_names,
            .current_item = &item,
        });

        if (item > -1) {
            current_item.* = index_to_enum[@intCast(item)];
        }

        return result;
    }

    draw: *const fn (allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) anyerror!void,

    showDemoWindow: *const fn () void,
    showMetricsWindow: *const fn () void,
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
    pushPropName: *const fn (obj: cdb.ObjId, prop_idx: u32) void,

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
    beginPopup: *const fn (str_id: [:0]const u8, flags: WindowFlags) bool,

    combo: *const fn (label: [:0]const u8, args: ComboArgs) bool,

    isItemClicked: *const fn (button: MouseButton) bool,
    isItemActivated: *const fn () bool,

    isRectVisible: *const fn (rect: [2]f32) bool,
    isItemVisible: *const fn () bool,

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
    getCursorPos: *const fn () [2]f32,
    getCursorScreenPos: *const fn () [2]f32,
    calcTextSize: *const fn (txt: []const u8, args: CalcTextSize) [2]f32,
    getWindowPos: *const fn () [2]f32,
    getWindowSize: *const fn () [2]f32,
    getContentRegionAvail: *const fn () [2]f32,
    setCursorPosX: *const fn (x: f32) void,
    setCursorPosY: *const fn (y: f32) void,

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

    handleSelection: *const fn (allocator: std.mem.Allocator, selection: *Selection, obj: SelectionItem, multiselect_enabled: bool) anyerror!void,

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

    image: *const fn (texture: gpu.TextureHandle, args: Image) void,
    getMousePos: *const fn () [2]f32,
    getMouseDragDelta: *const fn (drag_button: MouseButton, args: MouseDragDelta) [2]f32,
    setMouseCursor: *const fn (cursor: Cursor) void,

    popItemWidth: *const fn () void,
    pushItemWidth: *const fn (item_width: f32) void,

    mainDockSpace: *const fn (flags: DockNodeFlags) Ident,

    beginPlot: *const fn (title_id: [:0]const u8, args: BeginPlot) bool,
    endPlot: *const fn () void,
    plotLineF64: *const fn (label_id: [:0]const u8, args: PlotLineGen(f64)) void,
    plotLineValuesF64: *const fn (label_id: [:0]const u8, args: PlotLineValuesGen(f64)) void,
    setupAxis: *const fn (axis: Axis, args: SetupAxis) void,
    setupFinish: *const fn () void,
    setupLegend: *const fn (location: PlotLocation, flags: LegendFlags) void,

    getWindowDrawList: *const fn () DrawList,

    beginDisabled: *const fn (args: BeginDisabled) void,
    endDisabled: *const fn () void,

    // TODO: mode
    gizmoSetRect: *const fn (x: f32, y: f32, width: f32, height: f32) void,
    gizmoSetDrawList: *const fn (draw_list: ?DrawList) void,

    gizmoManipulate: *const fn (
        view: *const [16]f32,
        projection: *const [16]f32,
        operation: Operation,
        mode: Mode,
        matrix: *[16]f32,
        opt: struct {
            delta_matrix: ?*[16]f32 = null,
            snap: ?*const [3]f32 = null,
            local_bounds: ?*const [6]f32 = null,
            bounds_snap: ?*const [3]f32 = null,
        },
    ) bool,
};

pub const Operation = packed struct(u32) {
    translate_x: bool = false,
    translate_y: bool = false,
    translate_z: bool = false,
    rotate_x: bool = false,
    rotate_y: bool = false,
    rotate_z: bool = false,
    rotate_screen: bool = false,
    scale_x: bool = false,
    scale_y: bool = false,
    scale_z: bool = false,
    bounds: bool = false,
    scale_xu: bool = false,
    scale_yu: bool = false,
    scale_zu: bool = false,
    _padding: u18 = 0,

    pub fn translate() Operation {
        return .{ .translate_x = true, .translate_y = true, .translate_z = true };
    }
    pub fn rotate() Operation {
        return .{ .rotate_x = true, .rotate_y = true, .rotate_z = true };
    }
    pub fn scale() Operation {
        return .{ .scale_x = true, .scale_y = true, .scale_z = true };
    }
    pub fn scaleU() Operation {
        return .{ .scale_xu = true, .scale_yu = true, .scale_zu = true };
    }
    pub fn universal() Operation {
        return .{
            .translate_x = true,
            .translate_y = true,
            .translate_z = true,
            .rotate_x = true,
            .rotate_y = true,
            .rotate_z = true,
            .scale_xu = true,
            .scale_yu = true,
            .scale_zu = true,
        };
    }
};

pub const Mode = enum(u32) {
    local,
    world,
};

pub const DrawCmd = extern struct {
    clip_rect: [4]f32,
    texture_id: gpu.TextureHandle,
    vtx_offset: c_uint,
    idx_offset: c_uint,
    elem_count: c_uint,
    user_callback: ?DrawCallback,
    user_callback_data: ?*anyopaque,
    user_callback_data_size: c_int,
    user_callback_data_offset: c_int,
};

pub const DrawCallback = *const fn (*const anyopaque, *const DrawCmd) callconv(.c) void;

pub const DrawFlags = packed struct(c_int) {
    closed: bool = false,
    _padding0: u3 = 0,
    round_corners_top_left: bool = false,
    round_corners_top_right: bool = false,
    round_corners_bottom_left: bool = false,
    round_corners_bottom_right: bool = false,
    round_corners_none: bool = false,
    _padding1: u23 = 0,

    pub const round_corners_top = DrawFlags{
        .round_corners_top_left = true,
        .round_corners_top_right = true,
    };

    pub const round_corners_bottom = DrawFlags{
        .round_corners_bottom_left = true,
        .round_corners_bottom_right = true,
    };

    pub const round_corners_left = DrawFlags{
        .round_corners_top_left = true,
        .round_corners_bottom_left = true,
    };

    pub const round_corners_right = DrawFlags{
        .round_corners_top_right = true,
        .round_corners_bottom_right = true,
    };

    pub const round_corners_all = DrawFlags{
        .round_corners_top_left = true,
        .round_corners_top_right = true,
        .round_corners_bottom_left = true,
        .round_corners_bottom_right = true,
    };
};

pub const DrawIdx = u16;
pub const DrawVert = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: u32,
};

pub const DrawListFlags = packed struct(c_int) {
    anti_aliased_lines: bool = false,
    anti_aliased_lines_use_tex: bool = false,
    anti_aliased_fill: bool = false,
    allow_vtx_offset: bool = false,

    _padding: u28 = 0,
};

pub const ClipRect = struct {
    pmin: [2]f32,
    pmax: [2]f32,
    intersect_with_current: bool = false,
};

pub const PathRect = struct {
    bmin: [2]f32,
    bmax: [2]f32,
    rounding: f32 = 0.0,
    flags: DrawFlags = .{},
};
pub const DrawList = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn getOwnerName(self: DrawList) ?[*:0]const u8 {
        return self.vtable.getOwnerName(self.ptr);
    }
    pub inline fn reset(self: DrawList) void {
        self.vtable.reset(self.ptr);
    }
    pub inline fn clearMemory(self: DrawList) void {
        self.vtable.clearMemory(self.ptr);
    }
    pub inline fn getVertexBufferLength(self: DrawList) i32 {
        return self.vtable.getVertexBufferLength(self.ptr);
    }
    pub inline fn getVertexBufferData(self: DrawList) [*]DrawVert {
        return @ptrCast(self.vtable.getVertexBufferData(self.ptr));
    }

    pub inline fn getIndexBufferLength(self: DrawList) i32 {
        return self.vtable.getIndexBufferLength(self.ptr);
    }
    pub inline fn getIndexBufferData(self: DrawList) [*]DrawIdx {
        return self.vtable.getIndexBufferData(self.ptr);
    }

    pub inline fn getCurrentIndex(self: DrawList) u32 {
        return self.vtable.getCurrentIndex(self.ptr);
    }
    pub inline fn getCmdBufferLength(self: DrawList) i32 {
        return self.vtable.getCmdBufferLength(self.ptr);
    }
    pub inline fn getCmdBufferData(self: DrawList) [*]DrawCmd {
        return @ptrCast(self.vtable.getCmdBufferData(self.ptr));
    }

    pub inline fn setDrawListFlags(self: DrawList, flags: DrawListFlags) void {
        return self.vtable.setDrawListFlags(self.ptr, .{
            .anti_aliased_lines = flags.anti_aliased_lines,
            .anti_aliased_lines_use_tex = flags.anti_aliased_lines_use_tex,
            .anti_aliased_fill = flags.anti_aliased_fill,
            .allow_vtx_offset = flags.allow_vtx_offset,
        });
    }
    pub inline fn getDrawListFlags(self: DrawList) DrawListFlags {
        const flags = self.vtable.getDrawListFlags(
            self.ptr,
        );
        return .{
            .anti_aliased_lines = flags.anti_aliased_lines,
            .anti_aliased_lines_use_tex = flags.anti_aliased_lines_use_tex,
            .anti_aliased_fill = flags.anti_aliased_fill,
            .allow_vtx_offset = flags.allow_vtx_offset,
        };
    }
    pub inline fn pushClipRect(self: DrawList, args: ClipRect) void {
        return self.vtable.pushClipRect(self.ptr, .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .intersect_with_current = args.intersect_with_current,
        });
    }
    pub inline fn pushClipRectFullScreen(self: DrawList) void {
        return self.vtable.pushClipRectFullScreen(
            self.ptr,
        );
    }
    pub inline fn popClipRect(self: DrawList) void {
        return self.vtable.popClipRect(
            self.ptr,
        );
    }
    pub inline fn pushTextureId(self: DrawList, texture_id: gpu.TextureHandle) void {
        return self.vtable.pushTextureId(self.ptr, @ptrFromInt(texture_id.idx));
    }
    pub inline fn popTextureId(self: DrawList) void {
        return self.vtable.popTextureId(
            self.ptr,
        );
    }
    pub inline fn getClipRectMin(self: DrawList) [2]f32 {
        return self.vtable.getClipRectMin(
            self.ptr,
        );
    }
    pub inline fn getClipRectMax(self: DrawList) [2]f32 {
        return self.vtable.getClipRectMax(
            self.ptr,
        );
    }
    pub inline fn addLine(self: DrawList, args: struct { p1: [2]f32, p2: [2]f32, col: u32, thickness: f32 }) void {
        self.vtable.addLine(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub inline fn addRect(self: DrawList, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col: u32,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        self.vtable.addRect(self.ptr, .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .col = args.col,
            .rounding = args.rounding,
            .flags = .{
                .closed = args.flags.closed,
                .round_corners_top_left = args.flags.round_corners_top_left,
                .round_corners_top_right = args.flags.round_corners_top_right,
                .round_corners_bottom_left = args.flags.round_corners_bottom_left,
                .round_corners_bottom_right = args.flags.round_corners_bottom_right,
                .round_corners_none = args.flags.round_corners_none,
            },
            .thickness = args.thickness,
        });
    }
    pub inline fn addRectFilled(self: DrawList, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col: u32,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
    }) void {
        self.vtable.addRectFilled(self.ptr, .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .col = args.col,
            .rounding = args.rounding,
            .flags = .{
                .closed = args.flags.closed,
                .round_corners_top_left = args.flags.round_corners_top_left,
                .round_corners_top_right = args.flags.round_corners_top_right,
                .round_corners_bottom_left = args.flags.round_corners_bottom_left,
                .round_corners_bottom_right = args.flags.round_corners_bottom_right,
                .round_corners_none = args.flags.round_corners_none,
            },
        });
    }
    pub inline fn addRectFilledMultiColor(self: DrawList, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col_upr_left: u32,
        col_upr_right: u32,
        col_bot_right: u32,
        col_bot_left: u32,
    }) void {
        self.vtable.addRectFilledMultiColor(self.ptr, .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .col_upr_left = args.col_upr_left,
            .col_upr_right = args.col_upr_right,
            .col_bot_right = args.col_bot_right,
            .col_bot_left = args.col_bot_left,
        });
    }
    pub inline fn addQuad(self: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.addQuad(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub inline fn addQuadFilled(self: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
    }) void {
        self.vtable.addQuadFilled(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
        });
    }
    pub inline fn addTriangle(self: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.addTriangle(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub inline fn addTriangleFilled(self: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
    }) void {
        self.vtable.addTriangleFilled(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
        });
    }
    pub inline fn addCircle(self: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: i32 = 0,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.addCircle(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub inline fn addCircleFilled(self: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u16 = 0,
    }) void {
        self.vtable.addCircleFilled(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addNgon(self: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u32,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.addNgon(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub inline fn addNgonFilled(self: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u32,
    }) void {
        self.vtable.addNgonFilled(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addTextUnformatted(self: DrawList, pos: [2]f32, col: u32, txt: []const u8) void {
        self.vtable.addTextUnformatted(self.ptr, pos, col, txt);
    }
    pub inline fn addPolyline(self: DrawList, points: []const [2]f32, args: struct {
        col: u32,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        self.vtable.addPolyline(self.ptr, points, .{
            .col = args.col,
            .flags = .{
                .closed = args.flags.closed,
                .round_corners_top_left = args.flags.round_corners_top_left,
                .round_corners_top_right = args.flags.round_corners_top_right,
                .round_corners_bottom_left = args.flags.round_corners_bottom_left,
                .round_corners_bottom_right = args.flags.round_corners_bottom_right,
                .round_corners_none = args.flags.round_corners_none,
            },
            .thickness = args.thickness,
        });
    }
    pub inline fn addConvexPolyFilled(self: DrawList, points: []const [2]f32, col: u32) void {
        self.vtable.addConvexPolyFilled(self.ptr, points, col);
    }
    pub inline fn addBezierCubic(self: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        self.vtable.addBezierCubic(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addBezierQuadratic(self: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        self.vtable.addBezierQuadratic(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addImage(self: DrawList, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        uvmin: [2]f32 = .{ 0, 0 },
        uvmax: [2]f32 = .{ 1, 1 },
        col: u32 = 0xff_ff_ff_ff,
    }) void {
        self.vtable.addImage(self.ptr, @ptrFromInt(user_texture_id.idx), .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .uvmin = args.uvmin,
            .uvmax = args.uvmax,
            .col = args.col,
        });
    }
    pub inline fn addImageQuad(self: DrawList, user_texture_id: gpu.TextureHandle, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        uv1: [2]f32 = .{ 0, 0 },
        uv2: [2]f32 = .{ 1, 0 },
        uv3: [2]f32 = .{ 1, 1 },
        uv4: [2]f32 = .{ 0, 1 },
        col: u32 = 0xff_ff_ff_ff,
    }) void {
        self.vtable.addImageQuad(self.ptr, @ptrFromInt(user_texture_id.idx), .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .uv1 = args.uv1,
            .uv2 = args.uv2,
            .uv3 = args.uv3,
            .uv4 = args.uv4,
            .col = args.col,
        });
    }
    pub inline fn addImageRounded(self: DrawList, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        uvmin: [2]f32 = .{ 0, 0 },
        uvmax: [2]f32 = .{ 1, 1 },
        col: u32 = 0xff_ff_ff_ff,
        rounding: f32 = 4.0,
        flags: DrawFlags = .{},
    }) void {
        self.vtable.addImageRounded(self.ptr, @ptrFromInt(user_texture_id.idx), .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .uvmin = args.uvmin,
            .uvmax = args.uvmax,
            .col = args.col,
            .rounding = args.rounding,
            .flags = .{
                .closed = args.flags.closed,
                .round_corners_top_left = args.flags.round_corners_top_left,
                .round_corners_top_right = args.flags.round_corners_top_right,
                .round_corners_bottom_left = args.flags.round_corners_bottom_left,
                .round_corners_bottom_right = args.flags.round_corners_bottom_right,
                .round_corners_none = args.flags.round_corners_none,
            },
        });
    }
    pub inline fn pathClear(self: DrawList) void {
        self.vtable.pathClear(
            self.ptr,
        );
    }
    pub inline fn pathLineTo(self: DrawList, pos: [2]f32) void {
        self.vtable.pathLineTo(self.ptr, pos);
    }
    pub inline fn pathLineToMergeDuplicate(self: DrawList, pos: [2]f32) void {
        self.vtable.pathLineToMergeDuplicate(self.ptr, pos);
    }
    pub inline fn pathFillConvex(self: DrawList, col: u32) void {
        self.vtable.pathFillConvex(self.ptr, col);
    }
    pub inline fn pathStroke(self: DrawList, args: struct {
        col: u32,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        self.vtable.pathStroke(self.ptr, .{
            .col = args.col,
            .flags = .{
                .closed = args.flags.closed,
                .round_corners_top_left = args.flags.round_corners_top_left,
                .round_corners_top_right = args.flags.round_corners_top_right,
                .round_corners_bottom_left = args.flags.round_corners_bottom_left,
                .round_corners_bottom_right = args.flags.round_corners_bottom_right,
                .round_corners_none = args.flags.round_corners_none,
            },
            .thickness = args.thickness,
        });
    }
    pub inline fn pathArcTo(self: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        amin: f32,
        amax: f32,
        num_segments: u16 = 0,
    }) void {
        self.vtable.pathArcTo(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .amin = args.amin,
            .amax = args.amax,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn pathArcToFast(self: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        amin_of_12: u16,
        amax_of_12: u16,
    }) void {
        self.vtable.pathArcToFast(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .amin_of_12 = args.amin_of_12,
            .amax_of_12 = args.amax_of_12,
        });
    }
    pub inline fn pathBezierCubicCurveTo(self: DrawList, args: struct {
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        num_segments: u16 = 0,
    }) void {
        self.vtable.pathBezierCubicCurveTo(self.ptr, .{
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn pathBezierQuadraticCurveTo(self: DrawList, args: struct {
        p2: [2]f32,
        p3: [2]f32,
        num_segments: u16 = 0,
    }) void {
        self.vtable.pathBezierQuadraticCurveTo(self.ptr, .{
            .p2 = args.p2,
            .p3 = args.p3,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn pathRect(self: DrawList, args: PathRect) void {
        self.vtable.pathRect(self.ptr, .{
            .bmin = args.bmin,
            .bmax = args.bmax,
            .rounding = args.rounding,
            .flags = .{
                .closed = args.flags.closed,
                .round_corners_top_left = args.flags.round_corners_top_left,
                .round_corners_top_right = args.flags.round_corners_top_right,
                .round_corners_bottom_left = args.flags.round_corners_bottom_left,
                .round_corners_bottom_right = args.flags.round_corners_bottom_right,
                .round_corners_none = args.flags.round_corners_none,
            },
        });
    }
    pub inline fn primReserve(self: DrawList, idx_count: i32, vtx_count: i32) void {
        self.vtable.primReserve(self.ptr, idx_count, vtx_count);
    }
    pub inline fn primUnreserve(self: DrawList, idx_count: i32, vtx_count: i32) void {
        self.vtable.primUnreserve(self.ptr, idx_count, vtx_count);
    }
    pub inline fn primRect(self: DrawList, a: [2]f32, b: [2]f32, col: u32) void {
        self.vtable.primRect(self.ptr, a, b, col);
    }
    pub inline fn primRectUV(self: DrawList, a: [2]f32, b: [2]f32, uv_a: [2]f32, uv_b: [2]f32, col: u32) void {
        self.vtable.primRectUV(
            self.ptr,
            a,
            b,
            uv_a,
            uv_b,
            col,
        );
    }
    pub inline fn primQuadUV(self: DrawList, a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32, uv_a: [2]f32, uv_b: [2]f32, uv_c: [2]f32, uv_d: [2]f32, col: u32) void {
        self.vtable.primQuadUV(
            self.ptr,
            a,
            b,
            c,
            d,
            uv_a,
            uv_b,
            uv_c,
            uv_d,
            col,
        );
    }
    pub inline fn primWriteVtx(self: DrawList, pos: [2]f32, uv: [2]f32, col: u32) void {
        self.vtable.primWriteVtx(self.ptr, pos, uv, col);
    }
    pub inline fn primWriteIdx(self: DrawList, idx: DrawIdx) void {
        self.vtable.primWriteIdx(self.ptr, idx);
    }
    pub inline fn addCallback(self: DrawList, callback: DrawCallback, callback_data: ?*anyopaque) void {
        self.vtable.addCallback(self.ptr, @ptrCast(callback), callback_data);
    }
    pub inline fn addResetRenderStateCallback(self: DrawList) void {
        self.vtable.addResetRenderStateCallback(self.ptr);
    }

    pub const VTable = struct {
        getOwnerName: *const fn (draw_list: *anyopaque) ?[*:0]const u8,
        reset: *const fn (draw_list: *anyopaque) void,
        clearMemory: *const fn (draw_list: *anyopaque) void,
        getVertexBufferLength: *const fn (draw_list: *anyopaque) i32,
        getVertexBufferData: *const fn (draw_list: *anyopaque) [*]DrawVert,
        getIndexBufferLength: *const fn (draw_list: *anyopaque) i32,
        getIndexBufferData: *const fn (draw_list: *anyopaque) [*]DrawIdx,
        getCurrentIndex: *const fn (draw_list: *anyopaque) u32,
        getCmdBufferLength: *const fn (draw_list: *anyopaque) i32,
        getCmdBufferData: *const fn (draw_list: *anyopaque) [*]DrawCmd,
        setDrawListFlags: *const fn (draw_list: *anyopaque, flags: DrawListFlags) void,
        getDrawListFlags: *const fn (draw_list: *anyopaque) DrawListFlags,
        pushClipRect: *const fn (draw_list: *anyopaque, args: ClipRect) void,
        pushClipRectFullScreen: *const fn (draw_list: *anyopaque) void,
        popClipRect: *const fn (draw_list: *anyopaque) void,
        pushTextureId: *const fn (draw_list: *anyopaque, texture_id: gpu.TextureHandle) void,
        popTextureId: *const fn (draw_list: *anyopaque) void,
        getClipRectMin: *const fn (draw_list: *anyopaque) [2]f32,
        getClipRectMax: *const fn (draw_list: *anyopaque) [2]f32,
        addLine: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            col: u32,
            thickness: f32,
        }) void,
        addRect: *const fn (draw_list: *anyopaque, args: struct {
            pmin: [2]f32,
            pmax: [2]f32,
            col: u32,
            rounding: f32 = 0.0,
            flags: DrawFlags = .{},
            thickness: f32 = 1.0,
        }) void,
        addRectFilled: *const fn (draw_list: *anyopaque, args: struct {
            pmin: [2]f32,
            pmax: [2]f32,
            col: u32,
            rounding: f32 = 0.0,
            flags: DrawFlags = .{},
        }) void,
        addRectFilledMultiColor: *const fn (draw_list: *anyopaque, args: struct {
            pmin: [2]f32,
            pmax: [2]f32,
            col_upr_left: u32,
            col_upr_right: u32,
            col_bot_right: u32,
            col_bot_left: u32,
        }) void,
        addQuad: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            p4: [2]f32,
            col: u32,
            thickness: f32 = 1.0,
        }) void,
        addQuadFilled: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            p4: [2]f32,
            col: u32,
        }) void,
        addTriangle: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            col: u32,
            thickness: f32 = 1.0,
        }) void,
        addTriangleFilled: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            col: u32,
        }) void,
        addCircle: *const fn (draw_list: *anyopaque, args: struct {
            p: [2]f32,
            r: f32,
            col: u32,
            num_segments: i32 = 0,
            thickness: f32 = 1.0,
        }) void,
        addCircleFilled: *const fn (draw_list: *anyopaque, args: struct {
            p: [2]f32,
            r: f32,
            col: u32,
            num_segments: u16 = 0,
        }) void,
        addNgon: *const fn (draw_list: *anyopaque, args: struct {
            p: [2]f32,
            r: f32,
            col: u32,
            num_segments: u32,
            thickness: f32 = 1.0,
        }) void,
        addNgonFilled: *const fn (draw_list: *anyopaque, args: struct {
            p: [2]f32,
            r: f32,
            col: u32,
            num_segments: u32,
        }) void,
        addTextUnformatted: *const fn (draw_list: *anyopaque, pos: [2]f32, col: u32, txt: []const u8) void,
        addPolyline: *const fn (draw_list: *anyopaque, points: []const [2]f32, args: struct {
            col: u32,
            flags: DrawFlags = .{},
            thickness: f32 = 1.0,
        }) void,
        addConvexPolyFilled: *const fn (
            draw_list: *anyopaque,
            points: []const [2]f32,
            col: u32,
        ) void,
        addBezierCubic: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            p4: [2]f32,
            col: u32,
            thickness: f32 = 1.0,
            num_segments: u32 = 0,
        }) void,
        addBezierQuadratic: *const fn (draw_list: *anyopaque, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            col: u32,
            thickness: f32 = 1.0,
            num_segments: u32 = 0,
        }) void,
        addImage: *const fn (draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
            pmin: [2]f32,
            pmax: [2]f32,
            uvmin: [2]f32 = .{ 0, 0 },
            uvmax: [2]f32 = .{ 1, 1 },
            col: u32 = 0xff_ff_ff_ff,
        }) void,
        addImageQuad: *const fn (draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
            p1: [2]f32,
            p2: [2]f32,
            p3: [2]f32,
            p4: [2]f32,
            uv1: [2]f32 = .{ 0, 0 },
            uv2: [2]f32 = .{ 1, 0 },
            uv3: [2]f32 = .{ 1, 1 },
            uv4: [2]f32 = .{ 0, 1 },
            col: u32 = 0xff_ff_ff_ff,
        }) void,
        addImageRounded: *const fn (draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
            pmin: [2]f32,
            pmax: [2]f32,
            uvmin: [2]f32 = .{ 0, 0 },
            uvmax: [2]f32 = .{ 1, 1 },
            col: u32 = 0xff_ff_ff_ff,
            rounding: f32 = 4.0,
            flags: DrawFlags = .{},
        }) void,
        pathClear: *const fn (draw_list: *anyopaque) void,
        pathLineTo: *const fn (draw_list: *anyopaque, pos: [2]f32) void,
        pathLineToMergeDuplicate: *const fn (draw_list: *anyopaque, pos: [2]f32) void,
        pathFillConvex: *const fn (draw_list: *anyopaque, col: u32) void,
        pathStroke: *const fn (draw_list: *anyopaque, args: struct {
            col: u32,
            flags: DrawFlags = .{},
            thickness: f32 = 1.0,
        }) void,
        pathArcTo: *const fn (draw_list: **anyopaque, args: struct {
            p: [2]f32,
            r: f32,
            amin: f32,
            amax: f32,
            num_segments: u16 = 0,
        }) void,
        pathArcToFast: *const fn (draw_list: *anyopaque, args: struct {
            p: [2]f32,
            r: f32,
            amin_of_12: u16,
            amax_of_12: u16,
        }) void,
        pathBezierCubicCurveTo: *const fn (draw_list: *anyopaque, args: struct {
            p2: [2]f32,
            p3: [2]f32,
            p4: [2]f32,
            num_segments: u16 = 0,
        }) void,
        pathBezierQuadraticCurveTo: *const fn (draw_list: *anyopaque, args: struct {
            p2: [2]f32,
            p3: [2]f32,
            num_segments: u16 = 0,
        }) void,
        pathRect: *const fn (draw_list: *anyopaque, args: PathRect) void,
        primReserve: *const fn (
            draw_list: *anyopaque,
            idx_count: i32,
            vtx_count: i32,
        ) void,
        primUnreserve: *const fn (
            draw_list: *anyopaque,
            idx_count: i32,
            vtx_count: i32,
        ) void,
        primRect: *const fn (
            draw_list: *anyopaque,
            a: [2]f32,
            b: [2]f32,
            col: u32,
        ) void,
        primRectUV: *const fn (
            draw_list: *anyopaque,
            a: [2]f32,
            b: [2]f32,
            uv_a: [2]f32,
            uv_b: [2]f32,
            col: u32,
        ) void,
        primQuadUV: *const fn (
            draw_list: *anyopaque,
            a: [2]f32,
            b: [2]f32,
            c: [2]f32,
            d: [2]f32,
            uv_a: [2]f32,
            uv_b: [2]f32,
            uv_c: [2]f32,
            uv_d: [2]f32,
            col: u32,
        ) void,
        primWriteVtx: *const fn (
            draw_list: *anyopaque,
            pos: [2]f32,
            uv: [2]f32,
            col: u32,
        ) void,
        primWriteIdx: *const fn (
            draw_list: *anyopaque,
            idx: DrawIdx,
        ) void,
        addCallback: *const fn (draw_list: *anyopaque, callback: DrawCallback, callback_data: ?*anyopaque) void,
        addResetRenderStateCallback: *const fn (draw_list: *anyopaque) void,

        pub fn implement(comptime T: type) VTable {
            return VTable{
                .getOwnerName = @ptrCast(&T.getOwnerName),
                .reset = @ptrCast(&T.reset),
                .clearMemory = @ptrCast(&T.clearMemory),
                .getVertexBufferLength = @ptrCast(&T.getVertexBufferLength),
                .getVertexBufferData = @ptrCast(&T.getVertexBufferData),
                .getIndexBufferLength = @ptrCast(&T.getIndexBufferLength),
                .getIndexBufferData = @ptrCast(&T.getIndexBufferData),
                .getCurrentIndex = @ptrCast(&T.getCurrentIndex),
                .getCmdBufferLength = @ptrCast(&T.getCmdBufferLength),
                .getCmdBufferData = @ptrCast(&T.getCmdBufferData),
                .setDrawListFlags = @ptrCast(&T.setDrawListFlags),
                .getDrawListFlags = @ptrCast(&T.getDrawListFlags),
                .pushClipRect = @ptrCast(&T.pushClipRect),
                .pushClipRectFullScreen = @ptrCast(&T.pushClipRectFullScreen),
                .popClipRect = @ptrCast(&T.popClipRect),
                .pushTextureId = @ptrCast(&T.pushTextureId),
                .popTextureId = @ptrCast(&T.popTextureId),
                .getClipRectMin = @ptrCast(&T.getClipRectMin),
                .getClipRectMax = @ptrCast(&T.getClipRectMax),
                .addLine = @ptrCast(&T.addLine),
                .addRect = @ptrCast(&T.addRect),
                .addRectFilled = @ptrCast(&T.addRectFilled),
                .addRectFilledMultiColor = @ptrCast(&T.addRectFilledMultiColor),
                .addQuad = @ptrCast(&T.addQuad),
                .addQuadFilled = @ptrCast(&T.addQuadFilled),
                .addTriangle = @ptrCast(&T.addTriangle),
                .addTriangleFilled = @ptrCast(&T.addTriangleFilled),
                .addCircle = @ptrCast(&T.addCircle),
                .addCircleFilled = @ptrCast(&T.addCircleFilled),
                .addNgon = @ptrCast(&T.addNgon),
                .addNgonFilled = @ptrCast(&T.addNgonFilled),
                .addTextUnformatted = @ptrCast(&T.addTextUnformatted),
                .addPolyline = @ptrCast(&T.addPolyline),
                .addConvexPolyFilled = @ptrCast(&T.addConvexPolyFilled),
                .addBezierCubic = @ptrCast(&T.addBezierCubic),
                .addBezierQuadratic = @ptrCast(&T.addBezierQuadratic),
                .addImage = @ptrCast(&T.addImage),
                .addImageQuad = @ptrCast(&T.addImageQuad),
                .addImageRounded = @ptrCast(&T.addImageRounded),
                .pathClear = @ptrCast(&T.pathClear),
                .pathLineTo = @ptrCast(&T.pathLineTo),
                .pathLineToMergeDuplicate = @ptrCast(&T.pathLineToMergeDuplicate),
                .pathFillConvex = @ptrCast(&T.pathFillConvex),
                .pathStroke = @ptrCast(&T.pathStroke),
                .pathArcTo = @ptrCast(&T.pathArcTo),
                .pathArcToFast = @ptrCast(&T.pathArcToFast),
                .pathBezierCubicCurveTo = @ptrCast(&T.pathBezierCubicCurveTo),
                .pathBezierQuadraticCurveTo = @ptrCast(&T.pathBezierQuadraticCurveTo),
                .pathRect = @ptrCast(&T.pathRect),
                .primReserve = @ptrCast(&T.primReserve),
                .primUnreserve = @ptrCast(&T.primUnreserve),
                .primRect = @ptrCast(&T.primRect),
                .primRectUV = @ptrCast(&T.primRectUV),
                .primQuadUV = @ptrCast(&T.primQuadUV),
                .primWriteVtx = @ptrCast(&T.primWriteVtx),
                .primWriteIdx = @ptrCast(&T.primWriteIdx),
                .addCallback = @ptrCast(&T.addCallback),
                .addResetRenderStateCallback = @ptrCast(&T.addResetRenderStateCallback),
            };
        }
    };
};

pub const Image = struct {
    w: f32,
    h: f32,
    uv0: [2]f32 = .{ 0.0, 0.0 },
    uv1: [2]f32 = .{ 1.0, 1.0 },
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
    _padding_0: u2 = 0,

    // Extended enum entries from imgui_internal (unstable, subject to change, use at own risk)
    dock_space: bool = false,
    central_node: bool = false,
    no_tab_bar: bool = false,
    hidden_tab_bar: bool = false,
    no_window_menu_button: bool = false,
    no_close_button: bool = false,
    no_resize_x: bool = false,
    no_resize_y: bool = false,
    docked_windows_in_focus_route: bool = false,
    no_docking_split_other: bool = false,
    no_docking_over_me: bool = false,
    no_docking_over_other: bool = false,
    no_docking_over_empty: bool = false,
    _padding_1: u9 = 0,
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
    always_use_window_padding: bool = false,
    resize_x: bool = false,
    resize_y: bool = false,
    auto_resize_x: bool = false,
    auto_resize_y: bool = false,
    always_auto_resize: bool = false,
    frame_style: bool = false,
    nav_flattened: bool = false,
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
    span_label_width: bool = false,
    span_all_columns: bool = false,
    label_span_all_columns: bool = false,
    _padding0: u1 = 0,
    nav_left_jumps_to_parent: bool = false,
    draw_lines_none: bool = false,
    draw_lines_full: bool = false,
    draw_lines_to_nodes: bool = false,
    _padding1: u11 = 0,

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

pub const MouseButton = enum(c_int) {
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

pub const InputTextFlags = packed struct(c_int) {
    chars_decimal: bool = false,
    chars_hexadecimal: bool = false,
    chars_scientific: bool = false,
    chars_uppercase: bool = false,
    chars_no_blank: bool = false,
    allow_tab_input: bool = false,
    enter_returns_true: bool = false,
    escape_clears_all: bool = false,
    ctrl_enter_for_new_line: bool = false,
    read_only: bool = false,
    password: bool = false,
    always_overwrite: bool = false,
    auto_select_all: bool = false,
    parse_empty_ref_val: bool = false,
    display_empty_ref_val: bool = false,
    no_horizontal_scroll: bool = false,
    no_undo_redo: bool = false,
    callback_completion: bool = false,
    callback_history: bool = false,
    callback_always: bool = false,
    callback_char_filter: bool = false,
    callback_resize: bool = false,
    callback_edit: bool = false,
    _padding: u9 = 0,
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
    input_text_cursor,
    tab_hovered,
    tab,
    tab_selected,
    tab_selected_overline,
    tab_dimmed,
    tab_dimmed_selected,
    tab_dimmed_selected_overline,
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
    text_link,
    text_selected_bg,
    tree_lines,
    drag_drop_target,
    nav_cursor,
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
    font_size_base: f32,
    font_scale_main: f32,
    font_scale_dpi: f32,
    alpha: f32,
    disabled_alpha: f32,
    window_padding: [2]f32,
    window_rounding: f32,
    window_border_size: f32,
    window_border_hover_padding: f32,
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
    image_border_size: f32,
    tab_rounding: f32,
    tab_border_size: f32,
    tab_close_button_min_width_selected: f32,
    tab_close_button_min_width_unselected: f32,
    tab_bar_border_size: f32,
    tab_bar_overline_size: f32,
    table_angled_header_angle: f32,
    table_angled_headers_text_align: [2]f32,
    tree_lines_flags: TreeNodeFlags,
    tree_lines_size: f32,
    tree_lines_rounding: f32,
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

    colors: [@typeInfo(StyleCol).@"enum".fields.len][4]f32,

    hover_stationary_delay: f32,
    hover_delay_short: f32,
    hover_delay_normal: f32,

    hover_flags_for_tooltip_mouse: HoveredFlags,
    hover_flags_for_tooltip_nav: HoveredFlags,

    _main_scale: f32,
    _next_frame_font_size_base: f32,

    /// `pub fn init() Style`
    pub const init = zguiStyle_Init;
    extern fn zguiStyle_Init() Style;

    /// `pub fn scaleAllSizes(style: *Style, scale_factor: f32) void`
    pub const scaleAllSizes = zguiStyle_ScaleAllSizes;
    extern fn zguiStyle_ScaleAllSizes(style: *Style, scale_factor: f32) void;

    pub inline fn getColor(style: Style, idx: StyleCol) [4]f32 {
        return style.colors[@intCast(@intFromEnum(idx))];
    }
    pub inline fn setColor(style: *Style, idx: StyleCol, color: [4]f32) void {
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
    tab_border_size, // 1f
    tab_bar_border_size, // 1f
    tab_bar_overline_size, // 1f
    table_angled_headers_angle, // 1f
    table_angled_headers_text_align, // 2f
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
    payload_auto_expire: bool = false,
    payload_no_cross_context: bool = false,
    payload_no_cross_process: bool = false,

    _padding0: u2 = 0,

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
    wrap_around: bool = false,
    _padding: u23 = 0,
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

pub const PlotFlags = packed struct(u32) {
    no_title: bool = false,
    no_legend: bool = false,
    no_mouse_text: bool = false,
    no_inputs: bool = false,
    no_menus: bool = false,
    no_box_select: bool = false,
    no_frame: bool = false,
    equal: bool = false,
    crosshairs: bool = false,
    _padding: u23 = 0,

    pub const canvas_only = PlotFlags{
        .no_title = true,
        .no_legend = true,
        .no_menus = true,
        .no_box_select = true,
        .no_mouse_text = true,
    };
};
pub const BeginPlot = struct {
    w: f32 = -1.0,
    h: f32 = 0.0,
    flags: PlotFlags = .{},
};
pub const LineFlags = packed struct(u32) {
    _reserved0: bool = false,
    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    _reserved4: bool = false,
    _reserved5: bool = false,
    _reserved6: bool = false,
    _reserved7: bool = false,
    _reserved8: bool = false,
    _reserved9: bool = false,
    segments: bool = false,
    loop: bool = false,
    skip_nan: bool = false,
    no_clip: bool = false,
    shaded: bool = false,
    _padding: u17 = 0,
};
pub fn PlotLineGen(comptime T: type) type {
    return struct {
        xv: []const T,
        yv: []const T,
        flags: LineFlags = .{},
        offset: i32 = 0,
        stride: i32 = @sizeOf(T),
    };
}

pub fn PlotLineValuesGen(comptime T: type) type {
    return struct {
        v: []const T,
        xscale: f64 = 1.0,
        xstart: f64 = 0.0,
        flags: LineFlags = .{},
        offset: i32 = 0,
        stride: i32 = @sizeOf(T),
    };
}

pub const AxisFlags = packed struct(u32) {
    no_label: bool = false,
    no_grid_lines: bool = false,
    no_tick_marks: bool = false,
    no_tick_labels: bool = false,
    no_initial_fit: bool = false,
    no_menus: bool = false,
    no_side_switch: bool = false,
    no_highlight: bool = false,
    opposite: bool = false,
    foreground: bool = false,
    invert: bool = false,
    auto_fit: bool = false,
    range_fit: bool = false,
    pan_stretch: bool = false,
    lock_min: bool = false,
    lock_max: bool = false,
    _padding: u16 = 0,

    pub const lock = AxisFlags{
        .lock_min = true,
        .lock_max = true,
    };
    pub const no_decorations = AxisFlags{
        .no_label = true,
        .no_grid_lines = true,
        .no_tick_marks = true,
        .no_tick_labels = true,
    };
    pub const aux_default = AxisFlags{
        .no_grid_lines = true,
        .opposite = true,
    };
};
pub const Axis = enum(u32) { x1, x2, x3, y1, y2, y3 };
pub const SetupAxis = struct {
    label: ?[:0]const u8 = null,
    flags: AxisFlags = .{},
};

pub const PlotLocation = packed struct(u32) {
    north: bool = false,
    south: bool = false,
    west: bool = false,
    east: bool = false,
    _padding: u28 = 0,

    pub const north_west = PlotLocation{ .north = true, .west = true };
    pub const north_east = PlotLocation{ .north = true, .east = true };
    pub const south_west = PlotLocation{ .south = true, .west = true };
    pub const south_east = PlotLocation{ .south = true, .east = true };
};
pub const LegendFlags = packed struct(u32) {
    no_buttons: bool = false,
    no_highlight_item: bool = false,
    no_highlight_axis: bool = false,
    no_menus: bool = false,
    outside: bool = false,
    horizontal: bool = false,
    _padding: u26 = 0,
};
