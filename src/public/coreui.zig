// TODO: TMP SHIT big module
const std = @import("std");

const cetech1 = @import("cetech1.zig");
const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const math = cetech1.math;

const apidb = cetech1.apidb;
const host = @import("host.zig");
const gpu = @import("gpu.zig");
const ArraySet = @import("cetech1.zig").ArraySet;

const log = std.log.scoped(.coreui);

pub const CoreIcons = @import("coreui_icons.zig").Icons;

pub const SelectedObj = struct {
    top_level_obj: cdb.ObjId,
    obj: cdb.ObjId,

    in_set_obj: ?cdb.ObjId = null,
    parent_obj: ?cdb.ObjId = null,
    prop_idx: ?u32 = null,

    pub fn isEmpty(self: SelectedObj) bool {
        return self.obj.isEmpty();
    }

    pub fn empty() SelectedObj {
        return .{ .top_level_obj = .{}, .obj = .{} };
    }

    pub fn eql(self: SelectedObj, other: SelectedObj) SelectedObj {
        return std.mem.eql(u8, std.mem.toBytes(self), std.mem.toBytes(other));
    }
};

// TODO: TEMP solution. need api
pub const Selection = struct {
    const Item = SelectedObj;
    const SetImpl = ArraySet(Item);

    storage: SetImpl = .empty,

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

        return SelectedObj.empty();
    }

    pub fn isEmpty(self: Selection) bool {
        return self.storage.isEmpty();
    }
};

pub const Colors = struct {
    pub const Deleted: math.Color4f = .{ .r = 0.7, .a = 1.0 };
    pub const Remove: math.Color4f = .{ .r = 0.7, .a = 1.0 };
    pub const Modified: math.Color4f = .{ .r = 0.9, .g = 0.9, .a = 1.0 };
};

pub const Icons = struct {
    pub const Open = CoreIcons.ICON_LC_FOLDER_OPEN;
    pub const OpenProject = CoreIcons.ICON_LC_FOLDER_OPEN;
    pub const Create = CoreIcons.ICON_LC_CIRCLE_PLUS;

    pub const OpenTab = CoreIcons.ICON_LC_MAXIMIZE;
    pub const CloseTab = CoreIcons.ICON_LC_CIRCLE_X;

    pub const Save = CoreIcons.ICON_LC_SAVE;
    pub const SaveAll = CoreIcons.ICON_LC_SAVE_ALL;

    pub const Add = CoreIcons.ICON_LC_CIRCLE_PLUS;
    pub const AddFile = CoreIcons.ICON_LC_CIRCLE_PLUS;
    pub const AddAsset = CoreIcons.ICON_LC_CIRCLE_PLUS;
    pub const AddFolder = CoreIcons.ICON_LC_CIRCLE_PLUS;
    pub const Remove = CoreIcons.ICON_LC_CIRCLE_MINUS;
    pub const Close = CoreIcons.ICON_LC_X_SQUARE;
    pub const Delete = CoreIcons.ICON_LC_TRASH;

    pub const Restart = CoreIcons.ICON_LC_REPEAT;

    pub const CopyToClipboard = CoreIcons.ICON_LC_CLIPBOARD;

    pub const Nothing = CoreIcons.ICON_LC_SMILE;
    pub const Deleted = CoreIcons.ICON_LC_TRASH;
    pub const Quit = CoreIcons.ICON_LC_DOOR_CLOSED;

    pub const Debug = CoreIcons.ICON_LC_BUG;

    pub const Revive = CoreIcons.ICON_LC_SYRINGE;

    pub const Tag = CoreIcons.ICON_LC_TAG;
    pub const Tags = CoreIcons.ICON_LC_TAGS;

    pub const Folder = CoreIcons.ICON_LC_FOLDER_CLOSED;
    pub const Asset = CoreIcons.ICON_LC_FILE;

    pub const Move = CoreIcons.ICON_LC_MOVE;
    pub const MoveHere = CoreIcons.ICON_LC_ARROW_DOWN;

    pub const Settings = CoreIcons.ICON_LC_SETTINGS;
    pub const Properties = CoreIcons.ICON_LC_SLIDERS;
    pub const Buffer = CoreIcons.ICON_LC_GROUP;
    pub const Windows = CoreIcons.ICON_LC_APP_WINDOW;
    pub const Editor = CoreIcons.ICON_LC_HOUSE;
    pub const Colors = CoreIcons.ICON_LC_PALETTE;
    pub const TickRate = CoreIcons.ICON_LC_WATCH;
    pub const ContextMenu = CoreIcons.ICON_LC_COLUMNS_SETTINGS;
    pub const Explorer = CoreIcons.ICON_LC_LIST_TREE;
    pub const Clear = CoreIcons.ICON_LC_BRUSH_CLEANING;
    pub const Select = CoreIcons.ICON_LC_BOX_SELECT;
    pub const Rename = CoreIcons.ICON_LC_PENCIL;
    pub const UITest = CoreIcons.ICON_LC_SPARKLES;

    pub const Reveal = @This().Folder;
    pub const EditInOs = CoreIcons.ICON_LC_PENCIL;

    pub const Copy = CoreIcons.ICON_LC_COPY;
    pub const Clone = CoreIcons.ICON_LC_COPY_PLUS;
    pub const Instansiate = CoreIcons.ICON_LC_COPY_PLUS;

    pub const Help = CoreIcons.ICON_LC_CIRCLE_HELP;
    pub const Externals = CoreIcons.ICON_LC_THUMBS_UP;
    pub const Authors = CoreIcons.ICON_LC_PERSON_STANDING;

    pub const Link = CoreIcons.ICON_LC_LINK;

    pub const Graph = CoreIcons.ICON_LC_WORKFLOW;
    pub const FitContent = CoreIcons.ICON_LC_MAXIMIZE;
    pub const Build = CoreIcons.ICON_LC_HAMMER;

    pub const Group = CoreIcons.ICON_LC_GROUP;
    pub const Node = CoreIcons.ICON_LC_VECTOR_SQUARE;
    pub const Connection = CoreIcons.ICON_LC_LINK;
    pub const Const = CoreIcons.ICON_LC_PENCIL;
    pub const Random = CoreIcons.ICON_LC_SHUFFLE;
    pub const Bounding = CoreIcons.ICON_LC_SCAN;

    pub const Input = CoreIcons.ICON_LC_SQUARE_ARROW_RIGHT_ENTER;
    pub const Output = CoreIcons.ICON_LC_SQUARE_ARROW_RIGHT_EXIT;

    pub const Metrics = CoreIcons.ICON_LC_CHART_LINE;

    pub const Entity = CoreIcons.ICON_LC_BOT;
    pub const Component = CoreIcons.ICON_LC_PUZZLE;

    pub const Position = CoreIcons.ICON_LC_MOVE_3D;
    pub const Rotation = CoreIcons.ICON_LC_ROTATE_3D;
    pub const Scale = CoreIcons.ICON_LC_SCALE_3D;

    pub const LocalMode = CoreIcons.ICON_LC_LOCATE;
    pub const WorldMode = CoreIcons.ICON_LC_GLOBE;
    pub const Gizmo = CoreIcons.ICON_LC_CROSSHAIR;
    pub const Snap = CoreIcons.ICON_LC_MAGNET;

    pub const Play = CoreIcons.ICON_LC_PLAY;
    pub const Pause = CoreIcons.ICON_LC_PAUSE;
    pub const Stop = CoreIcons.ICON_LC_SQUARE;
    pub const ForwardStep = CoreIcons.ICON_LC_STEP_FORWARD;

    pub const Camera = CoreIcons.ICON_LC_CAMERA;
    pub const Draw = CoreIcons.ICON_LC_BRUSH;

    pub const Filter = CoreIcons.ICON_LC_FILTER;

    pub const Light = CoreIcons.ICON_LC_LIGHTBULB;

    pub const RenderPipeline = CoreIcons.ICON_LC_FILM;

    pub const Explosion = CoreIcons.ICON_LC_BOMB;

    pub const BoundingBox = CoreIcons.ICON_LC_BOX;
    pub const BoundingSphere = CoreIcons.ICON_LC_CIRCLE;

    pub const FreezeCamera = CoreIcons.ICON_LC_SNOWFLAKE;

    pub const FontScale = CoreIcons.ICON_LC_SCALING;
    pub const Culling = CoreIcons.ICON_LC_SQUARE_DASHED_TOP_SOLID;

    pub const PhysicsShapes = CoreIcons.ICON_LC_SHAPES;
    pub const PhysicsBody = CoreIcons.ICON_LC_PERSON_STANDING;
    pub const PhysicsWorld = CoreIcons.ICON_LC_GLOBE;

    pub const Search = CoreIcons.ICON_LC_SEARCH;
    pub const List = CoreIcons.ICON_LC_LIST;
    pub const Poo = CoreIcons.ICON_LC_GHOST;

    pub const Lock = CoreIcons.ICON_LC_LOCK;
    pub const Unlock = CoreIcons.ICON_LC_LOCK_OPEN;

    pub const Gamepad = CoreIcons.ICON_LC_GAMEPAD;
    pub const Gears = CoreIcons.ICON_LC_COG;

    pub const Timer = CoreIcons.ICON_LC_TIMER;
    pub const Print = CoreIcons.ICON_LC_CAPTIONS;

    pub const Logs = CoreIcons.ICON_LC_SCROLL_TEXT;
    pub const Error = CoreIcons.ICON_LC_MESSAGE_CIRCLE_X;
    pub const Warning = CoreIcons.ICON_LC_MESSAGE_CIRCLE_WARNING;
    pub const Info = CoreIcons.ICON_LC_MESSAGE_CIRCLE;
    // pub const Debug = CoreIcons.ICON_LC_MESSAGE_CIRCLE_DASHED;

    pub const ScrollDown = CoreIcons.ICON_LC_LIST_END;

    pub const Elispis = CoreIcons.ICON_LC_ELLIPSIS;
    pub const ElispisVertical = CoreIcons.ICON_LC_ELLIPSIS_VERTICAL;

    pub const ResetToPrototype = CoreIcons.ICON_LC_ROTATE_CCW;
    pub const PropagateToProtoype = CoreIcons.ICON_LC_ARROW_UP;
    pub const PrototypeBtn = CoreIcons.ICON_LC_SWATCH_BOOK;

    pub const ChevronRight = CoreIcons.ICON_LC_CHEVRON_RIGHT;
    pub const ChevronsRight = CoreIcons.ICON_LC_CHEVRONS_RIGHT;
    pub const Smile = CoreIcons.ICON_LC_SMILE;

    pub const Modified = CoreIcons.ICON_LC_SQUARE_DOT;
    pub const Preview = CoreIcons.ICON_LC_EYE;

    pub const Cubes = CoreIcons.ICON_LC_BOXES;
    pub const AssetBrowser = CoreIcons.ICON_LC_FOLDER_TREE;
};

pub const CoreUII = struct {
    pub const c_name = "ct_coreui_ui_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    ui: *const fn (allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) anyerror!void,

    pub inline fn implement(comptime T: type) CoreUII {
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
    pub inline fn setRef(ctx: *TestContext, ref: [:0]const u8) void {
        return testContextSetRef(ctx, ref);
    }

    pub inline fn itemAction(ctx: *TestContext, action: Actions, ref: [:0]const u8, flags: TestOpFlags, action_arg: ?*anyopaque) void {
        return testItemAction(ctx, action, ref, flags, action_arg);
    }

    pub inline fn windowFocus(ctx: *TestContext, ref: [:0]const u8) void {
        return testContextWindowFocus(ctx, ref);
    }

    pub inline fn yield(ctx: *TestContext, frame_count: i32) void {
        return testContextYield(ctx, frame_count);
    }

    pub inline fn menuAction(ctx: *TestContext, action: Actions, ref: [:0]const u8) void {
        return testContextMenuAction(ctx, action, ref);
    }

    pub inline fn itemInputStrValue(ctx: *TestContext, ref: [:0]const u8, value: [:0]const u8) void {
        return testItemInputStrValue(ctx, ref, value);
    }

    pub inline fn itemInputIntValue(ctx: *TestContext, ref: [:0]const u8, value: i32) void {
        return testItemInputIntValue(ctx, ref, value);
    }

    pub inline fn itemInputFloatValue(ctx: *TestContext, ref: [:0]const u8, value: f32) void {
        return testItemInputFloatValue(ctx, ref, value);
    }
    pub inline fn dragAndDrop(ctx: *TestContext, ref_src: [:0]const u8, ref_dst: [:0]const u8, mouse_button: MouseButton) void {
        return testDragAndDrop(ctx, ref_src, ref_dst, mouse_button);
    }
    pub inline fn keyDown(ctx: *TestContext, key_chord: Key) void {
        return testKeyDown(ctx, key_chord);
    }

    pub inline fn keyUp(ctx: *TestContext, key_chord: Key) void {
        return testKeyUp(ctx, key_chord);
    }
};

pub const RegisterTestsI = struct {
    pub const c_name = "ct_coreui_register_tests_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    register_tests: *const fn () anyerror!void,

    pub inline fn implement(comptime T: type) @This() {
        return @This(){
            .register_tests = T.registerTests,
        };
    }
};

pub const FilterItem = extern struct {
    name: [*:0]const u8,
    spec: [*:0]const u8,
};

pub const BeginDisabled = struct {
    disabled: bool = true,
};

pub const ComboArgs = struct {
    current_item: *i32,
    items_separated_by_zeros: [:0]const u8,
    popup_max_height_in_items: i32 = -1,
};

pub inline fn checkTestError(
    src: std.builtin.SourceLocation,
    err: anyerror,
) void {
    var buff: [128:0]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buff, "Assert error: {}", .{err}) catch undefined;
    _ = testCheck(src, .{}, false, msg);
}

pub inline fn registerTest(
    category: [:0]const u8,
    name: [:0]const u8,
    src: std.builtin.SourceLocation,
    comptime Callbacks: type,
) *Test {
    return registerTestFn(
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
    label: [:0]const u8,
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

    const result = combo(label, .{
        .items_separated_by_zeros = item_names,
        .current_item = &item,
    });

    if (item > -1) {
        current_item.* = index_to_enum[@intCast(item)];
    }

    return result;
}

pub fn createClipper() ListClipper {
    return api.createClipper();
}
pub fn draw(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, viewid: gpu.ViewId, kernel_tick: u64, dt: f32) anyerror!void {
    return api.draw(allocator, gpu_backend, viewid, kernel_tick, dt);
}
pub fn showDemoWindow() void {
    return api.showDemoWindow();
}
pub fn showMetricsWindow() void {
    return api.showMetricsWindow();
}
pub fn showTestingWindow(show: *bool) void {
    return api.showTestingWindow(show);
}
pub fn showExternalCredits(show: *bool) void {
    return api.showExternalCredits(show);
}
pub fn showAuthors(show: *bool) void {
    return api.showAuthors(show);
}
pub fn uiFilter(buf: []u8, filter: ?[:0]const u8) ?[:0]const u8 {
    return api.uiFilter(buf, filter);
}
pub fn uiFilterPass(allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64 {
    return api.uiFilterPass(allocator, filter, value, is_path);
}
pub fn begin(name: [:0]const u8, args: Begin) bool {
    return api.begin(name, args);
}
pub fn end() void {
    return api.end();
}
pub fn isItemToggledOpen() bool {
    return api.isItemToggledOpen();
}
pub fn dummy(args: Dummy) void {
    return api.dummy(args);
}
pub fn spacing() void {
    return api.spacing();
}
pub fn getScrollX() f32 {
    return api.getScrollX();
}
pub fn getScrollY() f32 {
    return api.getScrollY();
}
pub fn getScrollMaxX() f32 {
    return api.getScrollMaxX();
}
pub fn getScrollMaxY() f32 {
    return api.getScrollMaxY();
}
pub fn setScrollHereY(args: SetScrollHereY) void {
    return api.setScrollHereY(args);
}
pub fn setScrollHereX(args: SetScrollHereX) void {
    return api.setScrollHereX(args);
}
pub fn getFontSize() f32 {
    return api.getFontSize();
}
pub fn pushFontSize(size: f32) void {
    return api.pushFontSize(size);
}
pub fn popFontSize() void {
    return api.popFontSize();
}
pub fn getStyle() *Style {
    return api.getStyle();
}
pub fn pushStyleVar2f(args: PushStyleVar2f) void {
    return api.pushStyleVar2f(args);
}
pub fn pushStyleVar1f(args: PushStyleVar1f) void {
    return api.pushStyleVar1f(args);
}
pub fn pushStyleColor4f(args: PushStyleColor4f) void {
    return api.pushStyleColor4f(args);
}
pub fn popStyleColor(args: PopStyleColor) void {
    return api.popStyleColor(args);
}
pub fn popStyleVar(args: PopStyleVar) void {
    return api.popStyleVar(args);
}
pub fn isKeyDown(key: Key) bool {
    return api.isKeyDown(key);
}
pub fn tableSetBgColor(args: TableSetBgColor) void {
    return api.tableSetBgColor(args);
}
pub fn text(txt: []const u8) void {
    return api.text(txt);
}
pub fn textColored(color: math.Color4f, txt: []const u8) void {
    return api.textColored(color, txt);
}
pub fn colorPicker4(label: [:0]const u8, args: ColorPicker4) bool {
    return api.colorPicker4(label, args);
}
pub fn colorEdit4(label: [:0]const u8, args: ColorEdit4) bool {
    return api.colorEdit4(label, args);
}
pub fn beginMainMenuBar() bool {
    return api.beginMainMenuBar();
}
pub fn endMainMenuBar() void {
    return api.endMainMenuBar();
}
pub fn beginMenuBar() bool {
    return api.beginMenuBar();
}
pub fn endMenuBar() void {
    return api.endMenuBar();
}
pub fn beginMenu(allocator: std.mem.Allocator, label: [:0]const u8, enabled: bool, filter: ?[:0]const u8) bool {
    return api.beginMenu(allocator, label, enabled, filter);
}
pub fn endMenu() void {
    return api.endMenu();
}
pub fn menuItem(allocator: std.mem.Allocator, label: [:0]const u8, args: MenuItem, filter: ?[:0]const u8) bool {
    return api.menuItem(allocator, label, args, filter);
}
pub fn menuItemPtr(allocator: std.mem.Allocator, label: [:0]const u8, args: MenuItemPtr, filter: ?[:0]const u8) bool {
    return api.menuItemPtr(allocator, label, args, filter);
}
pub fn beginChild(str_id: [:0]const u8, args: BeginChild) bool {
    return api.beginChild(str_id, args);
}
pub fn endChild() void {
    return api.endChild();
}
pub fn pushPtrId(ptr_id: *const anyopaque) void {
    return api.pushPtrId(ptr_id);
}
pub fn pushIntId(int_id: u32) void {
    return api.pushIntId(int_id);
}
pub fn pushObjUUID(obj: cdb.ObjId) void {
    return api.pushObjUuid(obj);
}
pub fn pushPropName(obj: cdb.ObjId, prop_idx: u32) void {
    return api.pushPropName(obj, prop_idx);
}
pub fn pushName(str_id: [:0]const u8) void {
    return api.pushName(str_id);
}
pub fn popId() void {
    return api.popId();
}
pub fn treeNode(label: [:0]const u8) bool {
    return api.treeNode(label);
}
pub fn treeNodeFlags(label: [:0]const u8, flags: TreeNodeFlags) bool {
    return api.treeNodeFlags(label, flags);
}
pub fn treePop() void {
    return api.treePop();
}
pub fn alignTextToFramePadding() void {
    return api.alignTextToFramePadding();
}
pub fn isItemHovered(flags: HoveredFlags) bool {
    return api.isItemHovered(flags);
}
pub fn isWindowFocused(flags: FocusedFlags) bool {
    return api.isWindowFocused(flags);
}
pub fn labelText(label: [:0]const u8, txt: [:0]const u8) void {
    return api.labelText(label, txt);
}
pub fn button(label: [:0]const u8, args: Button) bool {
    return api.button(label, args);
}
pub fn smallButton(label: [:0]const u8) bool {
    return api.smallButton(label);
}
pub fn invisibleButton(label: [:0]const u8, args: InvisibleButton) bool {
    return api.invisibleButton(label, args);
}
pub fn sameLine(args: SameLine) void {
    return api.sameLine(args);
}
pub fn indent(args: Indent) void {
    return api.indent(args);
}
pub fn unindent(args: Unindent) void {
    return api.unindent(args);
}
pub fn inputText(label: [:0]const u8, args: InputText) bool {
    return api.inputText(label, args);
}
pub fn inputF32(label: [:0]const u8, args: InputF32) bool {
    return api.inputF32(label, args);
}
pub fn inputF64(label: [:0]const u8, args: InputF64) bool {
    return api.inputF64(label, args);
}
pub fn inputI32(label: [:0]const u8, args: InputScalarGen(i32)) bool {
    return api.inputI32(label, args);
}
pub fn inputU32(label: [:0]const u8, args: InputScalarGen(u32)) bool {
    return api.inputU32(label, args);
}
pub fn inputI64(label: [:0]const u8, args: InputScalarGen(i64)) bool {
    return api.inputI64(label, args);
}
pub fn inputU64(label: [:0]const u8, args: InputScalarGen(u64)) bool {
    return api.inputU64(label, args);
}
pub fn dragF32(label: [:0]const u8, args: DragFloatGen(f32)) bool {
    return api.dragF32(label, args);
}
pub fn dragF64(label: [:0]const u8, args: DragScalarGen(f64)) bool {
    return api.dragF64(label, args);
}
pub fn dragI32(label: [:0]const u8, args: DragScalarGen(i32)) bool {
    return api.dragI32(label, args);
}
pub fn dragU32(label: [:0]const u8, args: DragScalarGen(u32)) bool {
    return api.dragU32(label, args);
}
pub fn dragI64(label: [:0]const u8, args: DragScalarGen(i64)) bool {
    return api.dragI64(label, args);
}
pub fn dragU64(label: [:0]const u8, args: DragScalarGen(u64)) bool {
    return api.dragU64(label, args);
}
pub fn dragVec3f(label: [:0]const u8, args: DragFloatGen(math.Vec3f)) bool {
    return api.dragVec3f(label, args);
}
pub fn checkbox(label: [:0]const u8, args: Checkbox) bool {
    return api.checkbox(label, args);
}
pub fn toggleButton(label: [:0]const u8, toggled: *bool) bool {
    return api.toggleButton(label, toggled);
}
pub fn toggleMenuItem(label: [:0]const u8, toggled: *bool) bool {
    return api.toggleMenuItem(label, toggled);
}
pub fn setClipboardText(value: [:0]const u8) void {
    return api.setClipboardText(value);
}
pub fn beginPopupContextItem() bool {
    return api.beginPopupContextItem();
}
pub fn beginPopup(str_id: [:0]const u8, flags: WindowFlags) bool {
    return api.beginPopup(str_id, flags);
}
pub fn combo(label: [:0]const u8, args: ComboArgs) bool {
    return api.combo(label, args);
}
pub fn isItemClicked(mouse_button: MouseButton) bool {
    return api.isItemClicked(mouse_button);
}
pub fn isItemActivated() bool {
    return api.isItemActivated();
}
pub fn isRectVisible(rect: math.Vec2f) bool {
    return api.isRectVisible(rect);
}
pub fn isItemVisible() bool {
    return api.isItemVisible();
}
pub fn beginPopupModal(name: [:0]const u8, args: Begin) bool {
    return api.beginPopupModal(name, args);
}
pub fn openPopup(str_id: [:0]const u8, flags: PopupFlags) void {
    return api.openPopup(str_id, flags);
}
pub fn endPopup() void {
    return api.endPopup();
}
pub fn closeCurrentPopup() void {
    return api.closeCurrentPopup();
}
pub fn beginTooltip() bool {
    return api.beginTooltip();
}
pub fn endTooltip() void {
    return api.endTooltip();
}
pub fn separator() void {
    return api.separator();
}
pub fn separatorText(label: [:0]const u8) void {
    return api.separatorText(label);
}
pub fn separatorMenu() void {
    return api.separatorMenu();
}
pub fn setNextItemWidth(item_width: f32) void {
    return api.setNextItemWidth(item_width);
}
pub fn setNextWindowSize(args: SetNextWindowSize) void {
    return api.setNextWindowSize(args);
}
pub fn beginTable(name: [:0]const u8, args: BeginTable) bool {
    return api.beginTable(name, args);
}
pub fn endTable() void {
    return api.endTable();
}
pub fn tableSetupColumn(label: [:0]const u8, args: TableSetupColumn) void {
    return api.tableSetupColumn(label, args);
}
pub fn tableHeadersRow() void {
    return api.tableHeadersRow();
}
pub fn tableNextColumn() bool {
    return api.tableNextColumn();
}
pub fn tableNextRow(args: TableNextRow) void {
    return api.tableNextRow(args);
}
pub fn tableSetupScrollFreeze(cols: i32, rows: i32) void {
    return api.tableSetupScrollFreeze(cols, rows);
}
pub fn getItemRectMax() math.Vec2f {
    return api.getItemRectMax();
}
pub fn getItemRectMin() math.Vec2f {
    return api.getItemRectMin();
}
pub fn getCursorPosX() f32 {
    return api.getCursorPosX();
}
pub fn getCursorPos() math.Vec2f {
    return api.getCursorPos();
}
pub fn getCursorScreenPos() math.Vec2f {
    return api.getCursorScreenPos();
}
pub fn calcTextSize(txt: []const u8, args: CalcTextSize) math.Vec2f {
    return api.calcTextSize(txt, args);
}
pub fn getWindowPos() math.Vec2f {
    return api.getWindowPos();
}
pub fn getWindowSize() math.Vec2f {
    return api.getWindowSize();
}
pub fn getContentRegionAvail() math.Vec2f {
    return api.getContentRegionAvail();
}
pub fn setCursorPosX(x: f32) void {
    return api.setCursorPosX(x);
}
pub fn setCursorPosY(y: f32) void {
    return api.setCursorPosY(y);
}
pub fn setCursorScreenPos(pos: math.Vec2f) void {
    return api.setCursorScreenPos(pos);
}
pub fn selectable(label: [:0]const u8, args: Selectable) bool {
    return api.selectable(label, args);
}
pub fn beginDragDropSource(flags: DragDropFlags) bool {
    return api.beginDragDropSource(flags);
}
pub fn setDragDropPayload(payload_type: [*:0]const u8, data: []const u8, cond: Condition) bool {
    return api.setDragDropPayload(payload_type, data, cond);
}
pub fn endDragDropSource() void {
    return api.endDragDropSource();
}
pub fn beginDragDropTarget() bool {
    return api.beginDragDropTarget();
}
pub fn acceptDragDropPayload(payload_type: [*:0]const u8, flags: DragDropFlags) ?*Payload {
    return api.acceptDragDropPayload(payload_type, flags);
}
pub fn endDragDropTarget() void {
    return api.endDragDropTarget();
}
pub fn getDragDropPayload() ?*Payload {
    return api.getDragDropPayload();
}
pub fn isMouseDoubleClicked(mouse_button: MouseButton) bool {
    return api.isMouseDoubleClicked(mouse_button);
}
pub fn isMouseDown(mouse_button: MouseButton) bool {
    return api.isMouseDown(mouse_button);
}
pub fn isMouseClicked(mouse_button: MouseButton) bool {
    return api.isMouseClicked(mouse_button);
}
pub fn handleSelection(allocator: std.mem.Allocator, selection: *Selection, obj: SelectedObj, multiselect_enabled: bool) anyerror!void {
    return api.handleSelection(allocator, selection, obj, multiselect_enabled);
}
pub fn beginTabBar(label: [:0]const u8, flags: TabBarFlags) bool {
    return api.beginTabBar(label, flags);
}
pub fn beginTabItem(label: [:0]const u8, args: BeginTabItem) bool {
    return api.beginTabItem(label, args);
}
pub fn endTabBar() void {
    return api.endTabBar();
}
pub fn endTabItem() void {
    return api.endTabItem();
}
pub fn reloadTests() anyerror!void {
    return api.reloadTests();
}
pub fn registerTestFn(category: [*]const u8, name: [*]const u8, src: [*]const u8, src_line: c_int, gui_fce: ?*const ImGuiTestGuiFunc, gui_test_fce: ?*const ImGuiTestTestFunc) *Test {
    return api.registerTest(category, name, src, src_line, gui_fce, gui_test_fce);
}
pub fn testContextSetRef(ctx: *TestContext, ref: [:0]const u8) void {
    return api.testContextSetRef(ctx, ref);
}
pub fn testContextWindowFocus(ctx: *TestContext, ref: [:0]const u8) void {
    return api.testContextWindowFocus(ctx, ref);
}
pub fn testItemAction(ctx: *TestContext, action: Actions, ref: [:0]const u8, flags: TestOpFlags, action_arg: ?*anyopaque) void {
    return api.testItemAction(ctx, action, ref, flags, action_arg);
}
pub fn testItemInputStrValue(ctx: *TestContext, ref: [:0]const u8, value: [:0]const u8) void {
    return api.testItemInputStrValue(ctx, ref, value);
}
pub fn testItemInputIntValue(ctx: *TestContext, ref: [:0]const u8, value: i32) void {
    return api.testItemInputIntValue(ctx, ref, value);
}
pub fn testItemInputFloatValue(ctx: *TestContext, ref: [:0]const u8, value: f32) void {
    return api.testItemInputFloatValue(ctx, ref, value);
}
pub fn testContextYield(ctx: *TestContext, frame_count: i32) void {
    return api.testContextYield(ctx, frame_count);
}
pub fn testContextMenuAction(ctx: *TestContext, action: Actions, ref: [:0]const u8) void {
    return api.testContextMenuAction(ctx, action, ref);
}
pub fn testDragAndDrop(ctx: *TestContext, ref_src: [:0]const u8, ref_dst: [:0]const u8, mouse_button: MouseButton) void {
    return api.testDragAndDrop(ctx, ref_src, ref_dst, mouse_button);
}
pub fn testKeyDown(ctx: *TestContext, key_chord: Key) void {
    return api.testKeyDown(ctx, key_chord);
}
pub fn testKeyUp(ctx: *TestContext, key_chord: Key) void {
    return api.testKeyUp(ctx, key_chord);
}
pub fn testIsRunning() bool {
    return api.testIsRunning();
}
pub fn testRunAll(filter: [:0]const u8) void {
    return api.testRunAll(filter);
}
pub fn testPrintResult() void {
    return api.testPrintResult();
}
pub fn testGetResult() TestResult {
    return api.testGetResult();
}
pub fn testSetRunSpeed(speed: ImGuiTestRunSpeed) void {
    return api.testSetRunSpeed(speed);
}
pub fn testExportJunitResult(filename: [:0]const u8) void {
    return api.testExportJunitResult(filename);
}
pub fn testCheck(src: std.builtin.SourceLocation, flags: CheckFlags, resul: bool, expr: [:0]const u8) bool {
    return api.testCheck(src, flags, resul, expr);
}
pub fn setScaleFactor(scale_factor: f32) void {
    return api.setScaleFactor(scale_factor);
}
pub fn getScaleFactor() f32 {
    return api.getScaleFactor();
}
pub fn image(texture: gpu.TextureHandle, args: Image) void {
    return api.image(texture, args);
}
pub fn getMousePos() math.Vec2f {
    return api.getMousePos();
}
pub fn getMouseDragDelta(drag_button: MouseButton, args: MouseDragDelta) math.Vec2f {
    return api.getMouseDragDelta(drag_button, args);
}
pub fn setMouseCursor(cursor: Cursor) void {
    return api.setMouseCursor(cursor);
}
pub fn popItemWidth() void {
    return api.popItemWidth();
}
pub fn pushItemWidth(item_width: f32) void {
    return api.pushItemWidth(item_width);
}
pub fn mainDockSpace(flags: DockNodeFlags) Ident {
    return api.mainDockSpace(flags);
}
pub fn beginPlot(title_id: [:0]const u8, args: BeginPlot) bool {
    return api.beginPlot(title_id, args);
}
pub fn endPlot() void {
    return api.endPlot();
}
pub fn plotLineF64(label_id: [:0]const u8, args: PlotLineGen(f64)) void {
    return api.plotLineF64(label_id, args);
}
pub fn plotLineValuesF64(label_id: [:0]const u8, args: PlotLineValuesGen(f64)) void {
    return api.plotLineValuesF64(label_id, args);
}
pub fn setupAxis(axis: Axis, args: SetupAxis) void {
    return api.setupAxis(axis, args);
}
pub fn setupFinish() void {
    return api.setupFinish();
}
pub fn setupLegend(location: PlotLocation, flags: LegendFlags) void {
    return api.setupLegend(location, flags);
}
pub fn getWindowDrawList() DrawList {
    return api.getWindowDrawList();
}
pub fn beginDisabled(args: BeginDisabled) void {
    return api.beginDisabled(args);
}
pub fn endDisabled() void {
    return api.endDisabled();
}
pub fn getCurrentWindow() *ImGuiWindow {
    return api.getCurrentWindow();
}
pub fn gizmoSetRect(x: f32, y: f32, width: f32, height: f32) void {
    return api.gizmoSetRect(x, y, width, height);
}
pub fn gizmoSetDrawList(draw_list: ?DrawList) void {
    return api.gizmoSetDrawList(draw_list);
}
pub fn gizmoManipulate(view: math.Mat44f, projection: math.Mat44f, operation: Operation, mode: GizmoMode, matrix: *math.Mat44f, opt: GuizmoOpt) bool {
    return api.gizmoManipulate(view, projection, operation, mode, matrix, opt);
}
pub fn gizmoSetAlternativeWindow(window: *ImGuiWindow) void {
    return api.gizmoSetAlternativeWindow(window);
}
pub fn gizmoIsUsing() bool {
    return api.gizmoIsUsing();
}
pub fn gizmoIsOver() bool {
    return api.gizmoIsOver();
}

pub const CoreUIApi = struct {
    const Self = @This();

    createClipper: *const fn () ListClipper,
    draw: *const fn (allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, viewid: gpu.ViewId, kernel_tick: u64, dt: f32) anyerror!void,
    showDemoWindow: *const fn () void,
    showMetricsWindow: *const fn () void,
    showTestingWindow: *const fn (show: *bool) void,
    showExternalCredits: *const fn (show: *bool) void,
    showAuthors: *const fn (show: *bool) void,
    uiFilter: *const fn (buf: []u8, filter: ?[:0]const u8) ?[:0]const u8,
    uiFilterPass: *const fn (allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64,
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
    pushFontSize: *const fn (size: f32) void,
    popFontSize: *const fn () void,
    getStyle: *const fn () *Style,
    pushStyleVar2f: *const fn (args: PushStyleVar2f) void,
    pushStyleVar1f: *const fn (args: PushStyleVar1f) void,
    pushStyleColor4f: *const fn (args: PushStyleColor4f) void,
    popStyleColor: *const fn (args: PopStyleColor) void,
    popStyleVar: *const fn (args: PopStyleVar) void,
    isKeyDown: *const fn (key: Key) bool,
    tableSetBgColor: *const fn (args: TableSetBgColor) void,
    text: *const fn (txt: []const u8) void,
    textColored: *const fn (color: math.Color4f, txt: []const u8) void,
    colorPicker4: *const fn (label: [:0]const u8, args: ColorPicker4) bool,
    colorEdit4: *const fn (label: [:0]const u8, args: ColorEdit4) bool,
    beginMainMenuBar: *const fn () bool,
    endMainMenuBar: *const fn () void,
    beginMenuBar: *const fn () bool,
    endMenuBar: *const fn () void,
    beginMenu: *const fn (allocator: std.mem.Allocator, label: [:0]const u8, enabled: bool, filter: ?[:0]const u8) bool,
    endMenu: *const fn () void,
    menuItem: *const fn (allocator: std.mem.Allocator, label: [:0]const u8, args: MenuItem, filter: ?[:0]const u8) bool,
    menuItemPtr: *const fn (allocator: std.mem.Allocator, label: [:0]const u8, args: MenuItemPtr, filter: ?[:0]const u8) bool,
    beginChild: *const fn (str_id: [:0]const u8, args: BeginChild) bool,
    endChild: *const fn () void,
    pushPtrId: *const fn (ptr_id: *const anyopaque) void,
    pushIntId: *const fn (int_id: u32) void,
    pushObjUuid: *const fn (obj: cdb.ObjId) void,
    pushPropName: *const fn (obj: cdb.ObjId, prop_idx: u32) void,
    pushName: *const fn (str_id: [:0]const u8) void,
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
    indent: *const fn (args: Indent) void,
    unindent: *const fn (args: Unindent) void,
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
    dragVec3f: *const fn (label: [:0]const u8, args: DragFloatGen(math.Vec3f)) bool,
    checkbox: *const fn (label: [:0]const u8, args: Checkbox) bool,
    toggleButton: *const fn (label: [:0]const u8, toggled: *bool) bool,
    toggleMenuItem: *const fn (label: [:0]const u8, toggled: *bool) bool,
    setClipboardText: *const fn (value: [:0]const u8) void,
    beginPopupContextItem: *const fn () bool,
    beginPopup: *const fn (str_id: [:0]const u8, flags: WindowFlags) bool,
    combo: *const fn (label: [:0]const u8, args: ComboArgs) bool,
    isItemClicked: *const fn (button: MouseButton) bool,
    isItemActivated: *const fn () bool,
    isRectVisible: *const fn (rect: math.Vec2f) bool,
    isItemVisible: *const fn () bool,
    beginPopupModal: *const fn (name: [:0]const u8, args: Begin) bool,
    openPopup: *const fn (str_id: [:0]const u8, flags: PopupFlags) void,
    endPopup: *const fn () void,
    closeCurrentPopup: *const fn () void,
    beginTooltip: *const fn () bool,
    endTooltip: *const fn () void,
    separator: *const fn () void,
    separatorText: *const fn (label: [:0]const u8) void,
    separatorMenu: *const fn () void,
    setNextItemWidth: *const fn (item_width: f32) void,
    setNextWindowSize: *const fn (args: SetNextWindowSize) void,
    beginTable: *const fn (name: [:0]const u8, args: BeginTable) bool,
    endTable: *const fn () void,
    tableSetupColumn: *const fn (label: [:0]const u8, args: TableSetupColumn) void,
    tableHeadersRow: *const fn () void,
    tableNextColumn: *const fn () bool,
    tableNextRow: *const fn (args: TableNextRow) void,
    tableSetupScrollFreeze: *const fn (cols: i32, rows: i32) void,
    getItemRectMax: *const fn () math.Vec2f,
    getItemRectMin: *const fn () math.Vec2f,
    getCursorPosX: *const fn () f32,
    getCursorPos: *const fn () math.Vec2f,
    getCursorScreenPos: *const fn () math.Vec2f,
    calcTextSize: *const fn (txt: []const u8, args: CalcTextSize) math.Vec2f,
    getWindowPos: *const fn () math.Vec2f,
    getWindowSize: *const fn () math.Vec2f,
    getContentRegionAvail: *const fn () math.Vec2f,
    setCursorPosX: *const fn (x: f32) void,
    setCursorPosY: *const fn (y: f32) void,
    setCursorScreenPos: *const fn (pos: math.Vec2f) void,
    selectable: *const fn (label: [:0]const u8, args: Selectable) bool,
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
    handleSelection: *const fn (allocator: std.mem.Allocator, selection: *Selection, obj: SelectedObj, multiselect_enabled: bool) anyerror!void,
    beginTabBar: *const fn (label: [:0]const u8, flags: TabBarFlags) bool,
    beginTabItem: *const fn (label: [:0]const u8, args: BeginTabItem) bool,
    endTabBar: *const fn () void,
    endTabItem: *const fn () void,
    reloadTests: *const fn () anyerror!void,
    registerTest: *const fn (category: [*]const u8, name: [*]const u8, src: [*]const u8, src_line: c_int, gui_fce: ?*const ImGuiTestGuiFunc, gui_test_fce: ?*const ImGuiTestTestFunc) *Test,
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
    getMousePos: *const fn () math.Vec2f,
    getMouseDragDelta: *const fn (drag_button: MouseButton, args: MouseDragDelta) math.Vec2f,
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
    getCurrentWindow: *const fn () *ImGuiWindow,
    gizmoSetRect: *const fn (x: f32, y: f32, width: f32, height: f32) void,
    gizmoSetDrawList: *const fn (draw_list: ?DrawList) void,
    gizmoManipulate: *const fn (view: math.Mat44f, projection: math.Mat44f, operation: Operation, mode: GizmoMode, matrix: *math.Mat44f, opt: GuizmoOpt) bool,
    gizmoSetAlternativeWindow: *const fn (window: *ImGuiWindow) void,
    gizmoIsUsing: *const fn () bool,
    gizmoIsOver: *const fn () bool,
};

pub var api: *const CoreUIApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, CoreUIApi).?;
}

pub const ImGuiWindow = opaque {};

pub const GuizmoOpt = struct {
    delta_matrix: ?*math.Mat44f = null,
    snap: ?math.Vec3f = null,
    local_bounds: ?*const [6]f32 = null,
    bounds_snap: ?math.Vec3f = null,
};

pub const Operation = packed struct(c_int) {
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

    pub const translate: Operation = .{ .translate_x = true, .translate_y = true, .translate_z = true };
    pub const rotate: Operation = .{ .rotate_x = true, .rotate_y = true, .rotate_z = true };
    pub const scale: Operation = .{ .scale_x = true, .scale_y = true, .scale_z = true };
    pub const scaleU: Operation = .{ .scale_xu = true, .scale_yu = true, .scale_zu = true };
    pub const universal: Operation = .{
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
};

pub const GizmoMode = enum(u32) {
    Local = 0,
    World = 1,
};

pub const TextureStatus = enum(c_int) {
    ok,
    destroyed,
    want_create,
    want_updates,
    want_destroy,
};

pub const TextureFormat = enum(c_int) {
    rgba32,
    alpha8,
};

fn Vector(comptime T: type) type {
    return extern struct {
        len: c_int,
        capacity: c_int,
        items: [*]T,
    };
}

pub const TextureRect = extern struct {
    x: c_ushort,
    y: c_ushort,
    w: c_ushort,
    h: c_ushort,
};

pub const TextureData = extern struct {
    unique_id: c_int,
    status: TextureStatus,
    backend_user_data: ?*anyopaque,
    tex_id: TextureIdent,
    format: TextureFormat,
    width: c_int,
    height: c_int,
    bytes_per_pixel: c_int,
    pixels: [*]u8,
    used_rect: TextureRect,
    update_Rect: TextureRect,
    updates: Vector(TextureRect),
    unused_Frames: c_int,
    ref_count: c_ushort,
    use_colors: bool,
    want_destroy_next_frame: bool,
};

pub const TextureIdent = enum(u64) { _ };
pub const TextureRef = extern struct {
    tex_data: ?*TextureData,
    tex_id: TextureIdent,
};

pub const DrawCmd = extern struct {
    clip_rect: [4]f32,
    texture_id: TextureRef,
    vtx_offset: c_uint,
    idx_offset: c_uint,
    elem_count: c_uint,
    user_callback: ?DrawCallback,
    user_callback_data: ?*anyopaque,
    user_callback_data_size: c_int,
    user_callback_data_offset: c_int,
};

// TODO: remove callconv
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
    pos: math.Vec2f,
    uv: math.Vec2f,
    color: math.SRGBA,
};

pub const DrawListFlags = packed struct(c_int) {
    anti_aliased_lines: bool = false,
    anti_aliased_lines_use_tex: bool = false,
    anti_aliased_fill: bool = false,
    allow_vtx_offset: bool = false,

    _padding: u28 = 0,
};

pub const ClipRect = struct {
    pmin: math.Vec2f,
    pmax: math.Vec2f,
    intersect_with_current: bool = false,
};

pub const PathRect = struct {
    bmin: math.Vec2f,
    bmax: math.Vec2f,
    rounding: f32 = 0.0,
    flags: DrawFlags = .{},
};
pub const DrawList = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn getOwnerName(self: DrawList) ?[*:0]const u8 {
        return self.vtable.get_owner_name(self.ptr);
    }
    pub inline fn reset(self: DrawList) void {
        self.vtable.reset(self.ptr);
    }
    pub inline fn clearMemory(self: DrawList) void {
        self.vtable.clear_memory(self.ptr);
    }
    pub inline fn getVertexBufferLength(self: DrawList) i32 {
        return self.vtable.get_vertex_buffer_length(self.ptr);
    }
    pub inline fn getVertexBufferData(self: DrawList) [*]DrawVert {
        return @ptrCast(self.vtable.get_vertex_buffer_data(self.ptr));
    }

    pub inline fn getIndexBufferLength(self: DrawList) i32 {
        return self.vtable.get_index_buffer_length(self.ptr);
    }
    pub inline fn getIndexBufferData(self: DrawList) [*]DrawIdx {
        return self.vtable.get_index_buffer_data(self.ptr);
    }

    pub inline fn getCurrentIndex(self: DrawList) u32 {
        return self.vtable.get_current_index(self.ptr);
    }
    pub inline fn getCmdBufferLength(self: DrawList) i32 {
        return self.vtable.get_cmd_buffer_length(self.ptr);
    }
    pub inline fn getCmdBufferData(self: DrawList) [*]DrawCmd {
        return @ptrCast(self.vtable.get_cmd_buffer_data(self.ptr));
    }

    pub inline fn setDrawListFlags(self: DrawList, flags: DrawListFlags) void {
        return self.vtable.set_draw_list_flags(self.ptr, .{
            .anti_aliased_lines = flags.anti_aliased_lines,
            .anti_aliased_lines_use_tex = flags.anti_aliased_lines_use_tex,
            .anti_aliased_fill = flags.anti_aliased_fill,
            .allow_vtx_offset = flags.allow_vtx_offset,
        });
    }
    pub inline fn getDrawListFlags(self: DrawList) DrawListFlags {
        const flags = self.vtable.get_draw_list_flags(
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
        return self.vtable.push_clip_rect(self.ptr, .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .intersect_with_current = args.intersect_with_current,
        });
    }
    pub inline fn pushClipRectFullScreen(self: DrawList) void {
        return self.vtable.push_clip_rect_full_screen(
            self.ptr,
        );
    }
    pub inline fn popClipRect(self: DrawList) void {
        return self.vtable.pop_clip_rect(
            self.ptr,
        );
    }
    pub inline fn pushTextureId(self: DrawList, texture_id: gpu.TextureHandle) void {
        return self.vtable.push_texture_id(self.ptr, @ptrFromInt(texture_id.idx));
    }
    pub inline fn popTextureId(self: DrawList) void {
        return self.vtable.pop_texture_id(
            self.ptr,
        );
    }
    pub inline fn getClipRectMin(self: DrawList) math.Vec2f {
        return self.vtable.get_clip_rect_min(
            self.ptr,
        );
    }
    pub inline fn getClipRectMax(self: DrawList) math.Vec2f {
        return self.vtable.get_clip_rect_max(
            self.ptr,
        );
    }
    pub inline fn addLine(self: DrawList, args: struct { p1: math.Vec2f, p2: math.Vec2f, col: math.SRGBA, thickness: f32 }) void {
        self.vtable.add_line(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub inline fn addRect(self: DrawList, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        col: math.SRGBA,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        self.vtable.add_rect(self.ptr, .{
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
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        col: math.SRGBA,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
    }) void {
        self.vtable.add_rect_filled(self.ptr, .{
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
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        col_upr_left: u32,
        col_upr_right: u32,
        col_bot_right: u32,
        col_bot_left: u32,
    }) void {
        self.vtable.add_rect_filled_multi_color(self.ptr, .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .col_upr_left = args.col_upr_left,
            .col_upr_right = args.col_upr_right,
            .col_bot_right = args.col_bot_right,
            .col_bot_left = args.col_bot_left,
        });
    }
    pub inline fn addQuad(self: DrawList, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.add_quad(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub inline fn addQuadFilled(self: DrawList, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        col: math.SRGBA,
    }) void {
        self.vtable.add_quad_filled(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
        });
    }
    pub inline fn addTriangle(self: DrawList, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.add_triangle(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub inline fn addTriangleFilled(self: DrawList, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        col: math.SRGBA,
    }) void {
        self.vtable.add_triangle_filled(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
        });
    }
    pub inline fn addCircle(self: DrawList, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: i32 = 0,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.add_circle(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub inline fn addCircleFilled(self: DrawList, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: u16 = 0,
    }) void {
        self.vtable.add_circle_filled(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addNgon(self: DrawList, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: u32,
        thickness: f32 = 1.0,
    }) void {
        self.vtable.add_ngone(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub inline fn addNgonFilled(self: DrawList, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: u32,
    }) void {
        self.vtable.add_ngon_filled(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addTextUnformatted(self: DrawList, pos: math.Vec2f, col: math.SRGBA, txt: []const u8) void {
        self.vtable.add_text_unformatted(self.ptr, pos, col, txt);
    }
    pub inline fn addPolyline(self: DrawList, points: []const math.Vec2f, args: struct {
        col: math.SRGBA,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        self.vtable.add_polyline(self.ptr, points, .{
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
    pub inline fn addConvexPolyFilled(self: DrawList, points: []const math.Vec2f, col: math.SRGBA) void {
        self.vtable.add_convex_poly_filled(self.ptr, points, col);
    }
    pub inline fn addBezierCubic(self: DrawList, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        self.vtable.add_bezier_cubic(self.ptr, .{
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
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        self.vtable.add_bezier_quadratic(self.ptr, .{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn addImage(self: DrawList, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        uvmin: math.Vec2f = .{},
        uvmax: math.Vec2f = .{ 1, 1 },
        col: math.SRGBA = .white,
    }) void {
        self.vtable.add_image(self.ptr, @ptrFromInt(user_texture_id.idx), .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .uvmin = args.uvmin,
            .uvmax = args.uvmax,
            .col = args.col,
        });
    }
    pub inline fn addImageQuad(self: DrawList, user_texture_id: gpu.TextureHandle, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        uv1: math.Vec2f = .{},
        uv2: math.Vec2f = .{ 1, 0 },
        uv3: math.Vec2f = .{ 1, 1 },
        uv4: math.Vec2f = .{ 0, 1 },
        col: math.SRGBA = .white,
    }) void {
        self.vtable.add_image_quad(self.ptr, @ptrFromInt(user_texture_id.idx), .{
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
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        uvmin: math.Vec2f = .{},
        uvmax: math.Vec2f = .{ 1, 1 },
        col: math.SRGBA = .white,
        rounding: f32 = 4.0,
        flags: DrawFlags = .{},
    }) void {
        self.vtable.add_image_rounded(self.ptr, @ptrFromInt(user_texture_id.idx), .{
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
        self.vtable.path_clear(
            self.ptr,
        );
    }
    pub inline fn pathLineTo(self: DrawList, pos: math.Vec2f) void {
        self.vtable.path_line_to(self.ptr, pos);
    }
    pub inline fn pathLineToMergeDuplicate(self: DrawList, pos: math.Vec2f) void {
        self.vtable.path_line_to_merge_duplicate(self.ptr, pos);
    }
    pub inline fn pathFillConvex(self: DrawList, col: math.SRGBA) void {
        self.vtable.path_fill_convex(self.ptr, col);
    }
    pub inline fn pathStroke(self: DrawList, args: struct {
        col: math.SRGBA,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        self.vtable.path_stroke(self.ptr, .{
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
        p: math.Vec2f,
        r: f32,
        amin: f32,
        amax: f32,
        num_segments: u16 = 0,
    }) void {
        self.vtable.path_arc_to(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .amin = args.amin,
            .amax = args.amax,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn pathArcToFast(self: DrawList, args: struct {
        p: math.Vec2f,
        r: f32,
        amin_of_12: u16,
        amax_of_12: u16,
    }) void {
        self.vtable.path_arc_to_fast(self.ptr, .{
            .p = args.p,
            .r = args.r,
            .amin_of_12 = args.amin_of_12,
            .amax_of_12 = args.amax_of_12,
        });
    }
    pub inline fn pathBezierCubicCurveTo(self: DrawList, args: struct {
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        num_segments: u16 = 0,
    }) void {
        self.vtable.path_bezier_cubic_curve_to(self.ptr, .{
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn pathBezierQuadraticCurveTo(self: DrawList, args: struct {
        p2: math.Vec2f,
        p3: math.Vec2f,
        num_segments: u16 = 0,
    }) void {
        self.vtable.path_bezier_quadratic_curve_to(self.ptr, .{
            .p2 = args.p2,
            .p3 = args.p3,
            .num_segments = args.num_segments,
        });
    }
    pub inline fn pathRect(self: DrawList, args: PathRect) void {
        self.vtable.path_rect(self.ptr, .{
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
        self.vtable.prim_reserve(self.ptr, idx_count, vtx_count);
    }
    pub inline fn primUnreserve(self: DrawList, idx_count: i32, vtx_count: i32) void {
        self.vtable.prim_unreserve(self.ptr, idx_count, vtx_count);
    }
    pub inline fn primRect(self: DrawList, a: math.Vec2f, b: math.Vec2f, col: math.SRGBA) void {
        self.vtable.prim_rect(self.ptr, a, b, col);
    }
    pub inline fn primRectUV(self: DrawList, a: math.Vec2f, b: math.Vec2f, uv_a: math.Vec2f, uv_b: math.Vec2f, col: math.SRGBA) void {
        self.vtable.prim_rect_u_v(
            self.ptr,
            a,
            b,
            uv_a,
            uv_b,
            col,
        );
    }
    pub inline fn primQuadUV(self: DrawList, a: math.Vec2f, b: math.Vec2f, c: math.Vec2f, d: math.Vec2f, uv_a: math.Vec2f, uv_b: math.Vec2f, uv_c: math.Vec2f, uv_d: math.Vec2f, col: math.SRGBA) void {
        self.vtable.prim_quad_u_v(
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
    pub inline fn primWriteVtx(self: DrawList, pos: math.Vec2f, uv: math.Vec2f, col: math.SRGBA) void {
        self.vtable.prim_write_vtx(self.ptr, pos, uv, col);
    }
    pub inline fn primWriteIdx(self: DrawList, idx: DrawIdx) void {
        self.vtable.prim_write_idx(self.ptr, idx);
    }
    pub inline fn addCallback(self: DrawList, callback: DrawCallback, callback_data: ?*anyopaque) void {
        self.vtable.add_callback(self.ptr, @ptrCast(callback), callback_data);
    }
    pub inline fn addResetRenderStateCallback(self: DrawList) void {
        self.vtable.add_reset_render_state_callback(self.ptr);
    }

    pub const VTable = struct {
        get_owner_name: *const fn (draw_list: *anyopaque) ?[*:0]const u8,
        reset: *const fn (draw_list: *anyopaque) void,
        clear_memory: *const fn (draw_list: *anyopaque) void,
        get_vertex_buffer_length: *const fn (draw_list: *anyopaque) i32,
        get_vertex_buffer_data: *const fn (draw_list: *anyopaque) [*]DrawVert,
        get_index_buffer_length: *const fn (draw_list: *anyopaque) i32,
        get_index_buffer_data: *const fn (draw_list: *anyopaque) [*]DrawIdx,
        get_current_index: *const fn (draw_list: *anyopaque) u32,
        get_cmd_buffer_length: *const fn (draw_list: *anyopaque) i32,
        get_cmd_buffer_data: *const fn (draw_list: *anyopaque) [*]DrawCmd,
        set_draw_list_flags: *const fn (draw_list: *anyopaque, flags: DrawListFlags) void,
        get_draw_list_flags: *const fn (draw_list: *anyopaque) DrawListFlags,
        push_clip_rect: *const fn (draw_list: *anyopaque, args: ClipRect) void,
        push_clip_rect_full_screen: *const fn (draw_list: *anyopaque) void,
        pop_clip_rect: *const fn (draw_list: *anyopaque) void,
        push_texture_id: *const fn (draw_list: *anyopaque, texture_id: gpu.TextureHandle) void,
        pop_texture_id: *const fn (draw_list: *anyopaque) void,
        get_clip_rect_min: *const fn (draw_list: *anyopaque) math.Vec2f,
        get_clip_rect_max: *const fn (draw_list: *anyopaque) math.Vec2f,
        add_line: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            col: math.SRGBA,
            thickness: f32,
        }) void,
        add_rect: *const fn (draw_list: *anyopaque, args: struct {
            pmin: math.Vec2f,
            pmax: math.Vec2f,
            col: math.SRGBA,
            rounding: f32 = 0.0,
            flags: DrawFlags = .{},
            thickness: f32 = 1.0,
        }) void,
        add_rect_filled: *const fn (draw_list: *anyopaque, args: struct {
            pmin: math.Vec2f,
            pmax: math.Vec2f,
            col: math.SRGBA,
            rounding: f32 = 0.0,
            flags: DrawFlags = .{},
        }) void,
        add_rect_filled_multi_color: *const fn (draw_list: *anyopaque, args: struct {
            pmin: math.Vec2f,
            pmax: math.Vec2f,
            col_upr_left: u32,
            col_upr_right: u32,
            col_bot_right: u32,
            col_bot_left: u32,
        }) void,
        add_quad: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            p4: math.Vec2f,
            col: math.SRGBA,
            thickness: f32 = 1.0,
        }) void,
        add_quad_filled: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            p4: math.Vec2f,
            col: math.SRGBA,
        }) void,
        add_triangle: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            col: math.SRGBA,
            thickness: f32 = 1.0,
        }) void,
        add_triangle_filled: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            col: math.SRGBA,
        }) void,
        add_circle: *const fn (draw_list: *anyopaque, args: struct {
            p: math.Vec2f,
            r: f32,
            col: math.SRGBA,
            num_segments: i32 = 0,
            thickness: f32 = 1.0,
        }) void,
        add_circle_filled: *const fn (draw_list: *anyopaque, args: struct {
            p: math.Vec2f,
            r: f32,
            col: math.SRGBA,
            num_segments: u16 = 0,
        }) void,
        add_ngone: *const fn (draw_list: *anyopaque, args: struct {
            p: math.Vec2f,
            r: f32,
            col: math.SRGBA,
            num_segments: u32,
            thickness: f32 = 1.0,
        }) void,
        add_ngon_filled: *const fn (draw_list: *anyopaque, args: struct {
            p: math.Vec2f,
            r: f32,
            col: math.SRGBA,
            num_segments: u32,
        }) void,
        add_text_unformatted: *const fn (draw_list: *anyopaque, pos: math.Vec2f, col: math.SRGBA, txt: []const u8) void,
        add_polyline: *const fn (draw_list: *anyopaque, points: []const math.Vec2f, args: struct {
            col: math.SRGBA,
            flags: DrawFlags = .{},
            thickness: f32 = 1.0,
        }) void,
        add_convex_poly_filled: *const fn (
            draw_list: *anyopaque,
            points: []const math.Vec2f,
            col: math.SRGBA,
        ) void,
        add_bezier_cubic: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            p4: math.Vec2f,
            col: math.SRGBA,
            thickness: f32 = 1.0,
            num_segments: u32 = 0,
        }) void,
        add_bezier_quadratic: *const fn (draw_list: *anyopaque, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            col: math.SRGBA,
            thickness: f32 = 1.0,
            num_segments: u32 = 0,
        }) void,
        add_image: *const fn (draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
            pmin: math.Vec2f,
            pmax: math.Vec2f,
            uvmin: math.Vec2f = .{},
            uvmax: math.Vec2f = .{ .x = 1, .y = 1 },
            col: math.SRGBA = .white,
        }) void,
        add_image_quad: *const fn (draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
            p1: math.Vec2f,
            p2: math.Vec2f,
            p3: math.Vec2f,
            p4: math.Vec2f,
            uv1: math.Vec2f = .{},
            uv2: math.Vec2f = .{ .x = 1 },
            uv3: math.Vec2f = .{ .x = 1, .y = 1 },
            uv4: math.Vec2f = .{ .y = 1 },
            col: math.SRGBA = .white,
        }) void,
        add_image_rounded: *const fn (draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
            pmin: math.Vec2f,
            pmax: math.Vec2f,
            uvmin: math.Vec2f = .{},
            uvmax: math.Vec2f = .{ .x = 1, .y = 1 },
            col: math.SRGBA = .white,
            rounding: f32 = 4.0,
            flags: DrawFlags = .{},
        }) void,
        path_clear: *const fn (draw_list: *anyopaque) void,
        path_line_to: *const fn (draw_list: *anyopaque, pos: math.Vec2f) void,
        path_line_to_merge_duplicate: *const fn (draw_list: *anyopaque, pos: math.Vec2f) void,
        path_fill_convex: *const fn (draw_list: *anyopaque, col: math.SRGBA) void,
        path_stroke: *const fn (draw_list: *anyopaque, args: struct {
            col: math.SRGBA,
            flags: DrawFlags = .{},
            thickness: f32 = 1.0,
        }) void,
        path_arc_to: *const fn (draw_list: **anyopaque, args: struct {
            p: math.Vec2f,
            r: f32,
            amin: f32,
            amax: f32,
            num_segments: u16 = 0,
        }) void,
        path_arc_to_fast: *const fn (draw_list: *anyopaque, args: struct {
            p: math.Vec2f,
            r: f32,
            amin_of_12: u16,
            amax_of_12: u16,
        }) void,
        path_bezier_cubic_curve_to: *const fn (draw_list: *anyopaque, args: struct {
            p2: math.Vec2f,
            p3: math.Vec2f,
            p4: math.Vec2f,
            num_segments: u16 = 0,
        }) void,
        path_bezier_quadratic_curve_to: *const fn (draw_list: *anyopaque, args: struct {
            p2: math.Vec2f,
            p3: math.Vec2f,
            num_segments: u16 = 0,
        }) void,
        path_rect: *const fn (draw_list: *anyopaque, args: PathRect) void,
        prim_reserve: *const fn (
            draw_list: *anyopaque,
            idx_count: i32,
            vtx_count: i32,
        ) void,
        prim_unreserve: *const fn (
            draw_list: *anyopaque,
            idx_count: i32,
            vtx_count: i32,
        ) void,
        prim_rect: *const fn (
            draw_list: *anyopaque,
            a: math.Vec2f,
            b: math.Vec2f,
            col: math.SRGBA,
        ) void,
        prim_rect_u_v: *const fn (
            draw_list: *anyopaque,
            a: math.Vec2f,
            b: math.Vec2f,
            uv_a: math.Vec2f,
            uv_b: math.Vec2f,
            col: math.SRGBA,
        ) void,
        prim_quad_u_v: *const fn (
            draw_list: *anyopaque,
            a: math.Vec2f,
            b: math.Vec2f,
            c: math.Vec2f,
            d: math.Vec2f,
            uv_a: math.Vec2f,
            uv_b: math.Vec2f,
            uv_c: math.Vec2f,
            uv_d: math.Vec2f,
            col: math.SRGBA,
        ) void,
        prim_write_vtx: *const fn (
            draw_list: *anyopaque,
            pos: math.Vec2f,
            uv: math.Vec2f,
            col: math.SRGBA,
        ) void,
        prim_write_idx: *const fn (
            draw_list: *anyopaque,
            idx: DrawIdx,
        ) void,
        add_callback: *const fn (draw_list: *anyopaque, callback: DrawCallback, callback_data: ?*anyopaque) void,
        add_reset_render_state_callback: *const fn (draw_list: *anyopaque) void,

        // TODO: remove ptrCast
        pub fn implement(comptime T: type) VTable {
            return VTable{
                .get_owner_name = T.getOwnerName,
                .reset = @ptrCast(&T.reset),
                .clear_memory = @ptrCast(&T.clearMemory),
                .get_vertex_buffer_length = @ptrCast(&T.getVertexBufferLength),
                .get_vertex_buffer_data = @ptrCast(&T.getVertexBufferData),
                .get_index_buffer_length = @ptrCast(&T.getIndexBufferLength),
                .get_index_buffer_data = @ptrCast(&T.getIndexBufferData),
                .get_current_index = @ptrCast(&T.getCurrentIndex),
                .get_cmd_buffer_length = @ptrCast(&T.getCmdBufferLength),
                .get_cmd_buffer_data = @ptrCast(&T.getCmdBufferData),
                .set_draw_list_flags = @ptrCast(&T.setDrawListFlags),
                .get_draw_list_flags = @ptrCast(&T.getDrawListFlags),
                .push_clip_rect = @ptrCast(&T.pushClipRect),
                .push_clip_rect_full_screen = @ptrCast(&T.pushClipRectFullScreen),
                .pop_clip_rect = @ptrCast(&T.popClipRect),
                .push_texture_id = @ptrCast(&T.pushTextureId),
                .pop_texture_id = @ptrCast(&T.popTextureId),
                .get_clip_rect_min = @ptrCast(&T.getClipRectMin),
                .get_clip_rect_max = @ptrCast(&T.getClipRectMax),
                .add_line = @ptrCast(&T.addLine),
                .add_rect = @ptrCast(&T.addRect),
                .add_rect_filled = @ptrCast(&T.addRectFilled),
                .add_rect_filled_multi_color = @ptrCast(&T.addRectFilledMultiColor),
                .add_quad = @ptrCast(&T.addQuad),
                .add_quad_filled = @ptrCast(&T.addQuadFilled),
                .add_triangle = @ptrCast(&T.addTriangle),
                .add_triangle_filled = @ptrCast(&T.addTriangleFilled),
                .add_circle = @ptrCast(&T.addCircle),
                .add_circle_filled = @ptrCast(&T.addCircleFilled),
                .add_ngone = @ptrCast(&T.addNgon),
                .add_ngon_filled = @ptrCast(&T.addNgonFilled),
                .add_text_unformatted = @ptrCast(&T.addTextUnformatted),
                .add_polyline = @ptrCast(&T.addPolyline),
                .add_convex_poly_filled = @ptrCast(&T.addConvexPolyFilled),
                .add_bezier_cubic = @ptrCast(&T.addBezierCubic),
                .add_bezier_quadratic = @ptrCast(&T.addBezierQuadratic),
                .add_image = @ptrCast(&T.addImage),
                .add_image_quad = @ptrCast(&T.addImageQuad),
                .add_image_rounded = @ptrCast(&T.addImageRounded),
                .path_clear = @ptrCast(&T.pathClear),
                .path_line_to = @ptrCast(&T.pathLineTo),
                .path_line_to_merge_duplicate = @ptrCast(&T.pathLineToMergeDuplicate),
                .path_fill_convex = @ptrCast(&T.pathFillConvex),
                .path_stroke = @ptrCast(&T.pathStroke),
                .path_arc_to = @ptrCast(&T.pathArcTo),
                .path_arc_to_fast = @ptrCast(&T.pathArcToFast),
                .path_bezier_cubic_curve_to = @ptrCast(&T.pathBezierCubicCurveTo),
                .path_bezier_quadratic_curve_to = @ptrCast(&T.pathBezierQuadraticCurveTo),
                .path_rect = @ptrCast(&T.pathRect),
                .prim_reserve = @ptrCast(&T.primReserve),
                .prim_unreserve = @ptrCast(&T.primUnreserve),
                .prim_rect = @ptrCast(&T.primRect),
                .prim_rect_u_v = @ptrCast(&T.primRectUV),
                .prim_quad_u_v = @ptrCast(&T.primQuadUV),
                .prim_write_vtx = @ptrCast(&T.primWriteVtx),
                .prim_write_idx = @ptrCast(&T.primWriteIdx),
                .add_callback = @ptrCast(&T.addCallback),
                .add_reset_render_state_callback = @ptrCast(&T.addResetRenderStateCallback),
            };
        }
    };
};

pub const ListClipper = extern struct {
    ctx: ?*anyopaque = null,
    display_start: c_int = 0,
    display_end: c_int = 0,
    items_count: c_int = 0,
    items_height: f32 = 0,
    start_pos_y: f64 = 0,
    start_seek_offset_y: f64 = 0,
    temp_data: ?*anyopaque = null,
    vtable: *const VTable,

    pub fn begin(self: *ListClipper, items_count: ?i32, items_height: ?f32) void {
        self.vtable.begin(self, items_count orelse std.math.maxInt(i32), items_height orelse -1.0);
    }

    pub fn end(self: *ListClipper) void {
        self.vtable.end(self);
    }
    pub fn includeItemsByIndex(self: *ListClipper, item_begin: i32, item_end: i32) void {
        self.vtable.include_items_by_index(self, item_begin, item_end);
    }
    pub fn step(self: *ListClipper) bool {
        return self.vtable.step(self);
    }

    pub const VTable = struct {
        begin: *const fn (self: *ListClipper, items_count: ?i32, items_height: ?f32) void,
        end: *const fn (self: *ListClipper) void,
        include_items_by_index: *const fn (self: *ListClipper, item_begin: i32, item_end: i32) void,
        step: *const fn (self: *ListClipper) bool,

        pub fn implement(comptime T: type) VTable {
            return VTable{
                .begin = T.begin,
                .end = T.end,
                .include_items_by_index = T.includeItemsByIndex,
                .step = T.step,
            };
        }
    };
};

pub const Image = struct {
    w: f32,
    h: f32,
    uv0: math.Vec2f = .{},
    uv1: math.Vec2f = .{ .x = 1.0, .y = 1.0 },
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

pub const SetScrollHereX = struct {
    center_x_ratio: f32 = 0.5,
};
pub const SetScrollHereY = struct {
    center_y_ratio: f32 = 0.5,
};

pub const SetNextWindowSize = struct {
    w: f32,
    h: f32,
    cond: Condition = .none,
};

pub const TestResult = struct {
    count_tested: i32,
    count_success: i32,
};

pub const Begin = struct {
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
pub const TableFlags = packed struct(c_int) {
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

    // Miscellaneous
    highlight_hovered_column: bool = false,

    _padding: u3 = 0,
};

pub const TableRowFlags = packed struct(c_int) {
    headers: bool = false,

    _padding: u31 = 0,
};

pub const TableColumnFlags = packed struct(c_int) {
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
    RowBg0 = 1,
    RowBg1 = 2,
    CellBg = 3,
};

pub const BeginTable = struct {
    column: i32,
    flags: TableFlags = .{},
    outer_size: math.Vec2f = .{},
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
    elide_left: bool = false,
    callback_completion: bool = false,
    callback_history: bool = false,
    callback_always: bool = false,
    callback_char_filter: bool = false,
    callback_resize: bool = false,
    callback_edit: bool = false,
    world_wrap: bool = false,
    _padding: u7 = 0,
};

pub const InputText = struct {
    buf: [:0]u8,
    flags: InputTextFlags = .{},
    callback: ?*anyopaque = null,
    user_data: ?*anyopaque = null,
};

pub const TableNextRow = struct {
    row_flags: TableRowFlags = .{},
    min_row_height: f32 = 0,
};

pub const InputF32 = struct {
    v: *f32,
    step: f32 = 0.0,
    step_fast: f32 = 0.0,
    cfmt: [:0]const u8 = "%.3f",
    flags: InputTextFlags = .{},
};

pub const InputF64 = struct {
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

pub const Checkbox = struct {
    v: *bool,
};

pub const PopupFlags = packed struct(c_int) {
    _reserved0: bool = false,
    _reserved1: bool = false,
    mouse_button_left: bool = false,
    mouse_button_right: bool = false,
    // mouse_button_middle == left nad right true

    _reserved2: bool = false,
    no_reopen: bool = false,
    _reserved3: bool = false,

    no_open_over_existing_popup: bool = false,
    no_open_over_items: bool = false,
    any_popup_id: bool = false,
    any_popup_level: bool = false,
    _padding: u21 = 0,

    pub const any_popup = PopupFlags{ .any_popup_id = true, .any_popup_level = true };
};

pub const SelectableFlags = packed struct(c_int) {
    no_auto_close_popups: bool = false,
    span_all_columns: bool = false,
    allow_double_click: bool = false,
    disabled: bool = false,
    allow_overlap: bool = false,
    highlight: bool = false,
    _padding: u26 = 0,
};

pub const Selectable = struct {
    selected: bool = false,
    flags: SelectableFlags = .{},
    w: f32 = 0,
    h: f32 = 0,
};

pub const Button = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
};

pub const SameLine = struct {
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
    drag_drop_target_bg,
    unsaved_marker,
    nav_cursor,
    nav_windowing_highlight,
    nav_windowing_dim_bg,
    modal_window_dim_bg,
};
pub const PushStyleColor4f = struct {
    idx: StyleCol,
    c: math.Color4f,
};

pub const PopStyleColor = struct {
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
    color: math.SRGBA,
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
    no_color_markers: bool = false,
    alpha_opaque: bool = false,
    alpha_no_bg: bool = false,
    alpha_preview_half: bool = false,
    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    alpha_bar: bool = false,
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
pub const ColorPicker4 = struct {
    col: *math.Color4f,
    flags: ColorEditFlags = .{},
    ref_col: ?[*]const f32 = null,
};

pub const ColorEdit4 = struct {
    col: *math.Color4f,
    flags: ColorEditFlags = .{},
};

pub const CalcTextSize = struct {
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
    window_padding: math.Vec2f,
    window_rounding: f32,
    window_border_size: f32,
    window_border_hover_padding: f32,
    window_min_size: math.Vec2f,
    window_title_align: math.Vec2f,
    window_menu_button_position: Direction,
    child_rounding: f32,
    child_border_size: f32,
    popup_rounding: f32,
    popup_border_size: f32,
    frame_padding: math.Vec2f,
    frame_rounding: f32,
    frame_border_size: f32,
    item_spacing: math.Vec2f,
    item_inner_spacing: math.Vec2f,
    cell_padding: math.Vec2f,
    touch_extra_padding: math.Vec2f,
    indent_spacing: f32,
    columns_min_spacing: f32,
    scrollbar_size: f32,
    scrollbar_rounding: f32,
    scrollbar_padding: f32,
    grab_min_size: f32,
    grab_rounding: f32,
    log_slider_deadzone: f32,
    image_rounding: f32,
    image_border_size: f32,
    tab_rounding: f32,
    tab_border_size: f32,
    tab_min_width_base: f32,
    tab_min_width_shrink: f32,
    tab_close_button_min_width_selected: f32,
    tab_close_button_min_width_unselected: f32,
    tab_bar_border_size: f32,
    tab_bar_overline_size: f32,
    table_angled_header_angle: f32,
    table_angled_headers_text_align: math.Vec2f,
    tree_lines_flags: TreeNodeFlags,
    tree_lines_size: f32,
    tree_lines_rounding: f32,
    drag_drop_target_rounding: f32,
    drag_drop_target_border_size: f32,
    drag_drop_target_padding: f32,
    color_marker_size: f32,
    color_button_position: Direction,
    button_text_align: math.Vec2f,
    selectable_text_align: math.Vec2f,
    separator_text_border_size: f32,
    separator_text_align: math.Vec2f,
    separator_text_padding: math.Vec2f,
    display_window_padding: math.Vec2f,
    display_safe_area_padding: math.Vec2f,
    docking_node_has_close_button: bool,
    docking_separator_size: f32,
    mouse_cursor_scale: f32,
    anti_aliased_lines: bool,
    anti_aliased_lines_use_tex: bool,
    anti_aliased_fill: bool,
    curve_tessellation_tol: f32,
    circle_tessellation_max_error: f32,

    colors: [@typeInfo(StyleCol).@"enum".fields.len]math.Color4f,

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

    pub inline fn getColor(style: Style, idx: StyleCol) math.Color4f {
        return style.colors[@intCast(@intFromEnum(idx))];
    }
    pub inline fn setColor(style: *Style, idx: StyleCol, color: math.Color4f) void {
        style.colors[@intCast(@intFromEnum(idx))] = color;
    }
};

pub const ButtonFlags = packed struct(c_int) {
    mouse_button_left: bool = false,
    mouse_button_right: bool = false,
    mouse_button_middle: bool = false,
    _padding: u29 = 0,
};
pub const InvisibleButton = struct {
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
    scrollbar_padding, // 1f
    grab_min_size, // 1f
    grab_rounding, // 1f
    image_rouding, // 1f
    image_border_size, // 1f
    tab_rounding, // 1f
    tab_border_size, // 1f
    tab_min_width_base, // 1f
    tab_min_width_shrink, // 1f
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

pub const PushStyleVar2f = struct {
    idx: StyleVar,
    v: math.Vec2f,
};

pub const PushStyleVar1f = struct {
    idx: StyleVar,
    v: f32,
};

pub const PopStyleVar = struct {
    count: i32 = 1,
};

pub const BeginChild = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
    child_flags: ChildFlags = .{},
    window_flags: WindowFlags = .{},
};

pub const Dummy = struct {
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
    accept_draw_as_hovered: bool = false,

    _padding1: u18 = 0,

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

    pub fn toValue(self: Payload, comptime T: type) T {
        const v: *T = @ptrCast(@alignCast(self.data));
        return v.*;
    }
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
    clamp_in_out: bool = false,
    clamp_zero_range: bool = false,
    no_speed_tweaks: bool = false,
    color_markers: bool = false,
    _padding: u19 = 0,
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

//--------------------------------------------------------------------------------------------------
//
// Tabs
//
//--------------------------------------------------------------------------------------------------
pub const TabBarFlags = packed struct(c_int) {
    reorderable: bool = false,
    auto_select_new_tabs: bool = false,
    tab_list_popup_button: bool = false,
    no_close_with_middle_mouse_button: bool = false,
    no_tab_list_scrolling_buttons: bool = false,
    no_tooltip: bool = false,
    draw_selected_overline: bool = false,
    fitting_policy_mixed: bool = false,
    fitting_policy_shrink: bool = false,
    fitting_policy_scroll: bool = false,
    _padding: u22 = 0,
};
pub const TabItemFlags = packed struct(c_int) {
    unsaved_document: bool = false,
    set_selected: bool = false,
    no_close_with_middle_mouse_button: bool = false,
    no_push_id: bool = false,
    no_tooltip: bool = false,
    no_reorder: bool = false,
    leading: bool = false,
    trailing: bool = false,
    no_assumed_closure: bool = false,
    _padding: u23 = 0,
};

pub const BeginTabItem = struct {
    p_open: ?*bool = null,
    flags: TabItemFlags = .{},
};

pub const Indent = struct {
    indent_w: f32 = 0.0,
};

pub const Unindent = struct {
    indent_w: f32 = 0.0,
};
pub const PlotFlags = packed struct(c_int) {
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
pub const LineFlags = packed struct(c_int) {
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

pub const AxisFlags = packed struct(c_int) {
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

pub const PlotLocation = packed struct(c_int) {
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
pub const LegendFlags = packed struct(c_int) {
    no_buttons: bool = false,
    no_highlight_item: bool = false,
    no_highlight_axis: bool = false,
    no_menus: bool = false,
    outside: bool = false,
    horizontal: bool = false,
    _padding: u26 = 0,
};
