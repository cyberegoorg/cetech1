const std = @import("std");
const builtin = @import("builtin");

const cetech1_options = @import("cetech1_options");

const zgui = @import("zgui");
const zguite = zgui.te;
const zf = @import("zf");
const tempalloc = @import("../../kernel/private/tempalloc.zig");
const gpu_private = @import("../../kernel/private/gpu.zig");
const cdb_private = @import("../../kernel/private/cdb.zig");

const zne = zgui.node_editor;

const backend = @import("coreui_backend.zig");
const apidb = cetech1.apidb;
const profiler = @import("../../kernel/private/profiler.zig");

const cetech1 = @import("cetech1");
const kernel = cetech1.kernel;
const gpu = cetech1.gpu;
const cdb = cetech1.cdb;
const math = cetech1.math;
const assetdb = cetech1.assetdb;
const host = cetech1.host;
const Icons = public.CoreIcons;
const node_editor = cetech1.coreui_node_editor;

const public = cetech1.coreui;

const module_name = .coreui;
const log = std.log.scoped(module_name);

const _font_main = @embedFile("font-main");
const _font_icons = @embedFile("font-icons");
const DEFAULT_IMGUI_INI = @embedFile("embed/imgui.ini");

var _allocator: std.mem.Allocator = undefined;
var _backed_initialised = false;
var _te_engine: *zguite.TestEngine = undefined;
var _te_show_window: bool = false;
var _ui_init = false;

var _junit_filename_buff: [1024:0]u8 = undefined;
var _junit_filename: ?[:0]const u8 = null;
var _scale_factor: ?f32 = null;
var _is_origin_bottom_left: bool = false;

var ui_being_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.PreUpdate,
    "CoreUI: begin",
    &[_]cetech1.StrId64{},
    0,
    struct {
        pub fn update(_: u64, _: f32) !void {
            var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "Begin-loop CoreUI");
            defer update_zone_ctx.End();

            if (!_ui_init) {
                const window = kernel.getMainWindow();
                const gpu_backend = kernel.getGpuBackend();

                try enableWithWindow(window, gpu_backend);
                _ui_init = true;
            }

            if (_ui_init) {
                newFrame();
            }
        }
    },
);

var ui_end_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.PreStore,
    "CoreUI: end",
    &[_]cetech1.StrId64{},
    0,
    struct {
        pub fn update(_: u64, _: f32) !void {
            afterAll();
        }
    },
);

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;

        // Obj selections
        // _ = try db.addType(
        //     public.ObjSelection.name,
        //     &[_]cdb.PropDef{
        //         .{ .prop_idx = public.ObjSelection.propIdx(.Selection), .name = "selection", .type = cdb.PropType.REFERENCE_SET },
        //     },
        // );
        //
    }
});

const kernel_testing = cetech1.kernel.KernelTestingI.implment(struct {
    pub fn isRunning() !bool {
        return testIsRunning();
    }
    pub fn printResult() void {
        testPrintResult();
    }
    pub fn getResult() cetech1.kernel.TestResult {
        const r = testGetResult();
        return .{
            .count_tested = r.count_tested,
            .count_success = r.count_success,
        };
    }
});

pub fn init(io: std.Io, allocator: std.mem.Allocator) !void {
    public.api = &api;
    node_editor.api = &node_editor_api;

    _allocator = allocator;

    _backed_initialised = false;
    _te_engine = undefined;
    _te_show_window = false;
    _ui_init = false;
    _junit_filename = null;

    //TODO: TEMP SHIT
    _ = std.Io.Dir.cwd().statFile(io, "imgui.ini", .{}) catch |err| {
        if (err == error.FileNotFound) {
            const f = try std.Io.Dir.cwd().createFile(io, "imgui.ini", .{});
            defer f.close(io);
            try f.writeStreamingAll(io, DEFAULT_IMGUI_INI);
        }
    };
    //

    zgui.init(io, _allocator);
    zgui.plot.init();

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &ui_being_task, true);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &ui_end_task, true);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTestingI, &kernel_testing, true);
}

pub fn deinit() void {
    if (_backed_initialised) {
        _te_engine.tryAbortEngine();
        _te_engine.stop();
    }

    zgui.plot.deinit();
    if (_backed_initialised) backend.deinit(kernel.getGpuBackend());
    zgui.deinit();
}

const api = public.CoreUIApi{
    .draw = drawUI,
    .showDemoWindow = showDemoWindow,
    .showMetricsWindow = showMetricsWindow,
    .begin = begin,
    .end = end,
    .beginPopup = beginPopup,
    .createClipper = createClipper,
    .pushStyleColor4f = pushStyleColor4f,
    .popStyleColor = popStyleColor,
    .tableSetBgColor = tableSetBgColor,
    .text = text,
    .textColored = textColored,
    .colorPicker4 = colorPicker4,
    .colorEdit4 = colorEdit4,
    .beginMainMenuBar = beginMainMenuBar,
    .endMainMenuBar = endMainMenuBar,
    .beginMenuBar = beginMenuBar,
    .endMenuBar = endMenuBar,
    .beginMenu = beginMenu,
    .endMenu = endMenu,
    .menuItem = menuItem,
    .menuItemPtr = menuItemPtr,
    .beginChild = beginChild,
    .endChild = endChild,
    .separator = separator,
    .separatorText = separatorText,
    .separatorMenu = separatorMenu,
    .setNextItemWidth = setNextItemWidth,
    .setNextWindowSize = setNextWindowSize,
    .pushPtrId = pushPtrId,
    .pushIntId = pushIntId,
    .pushObjUuid = pushObjUUID,
    .popId = popId,
    .treeNode = treeNode,
    .treeNodeFlags = treeNodeFlags,
    .treePop = treePop,
    .beginTooltip = beginTooltip,
    .endTooltip = endTooltip,
    .isItemHovered = isItemHovered,
    .setClipboardText = setClipboardText,
    .beginPopupContextItem = beginPopupContextItem,
    .beginPopupModal = beginPopupModal,
    .openPopup = openPopup,
    .endPopup = endPopup,
    .closeCurrentPopup = closeCurrentPopup,
    .isItemClicked = isItemClicked,
    .isItemActivated = isItemActivated,
    .isWindowFocused = isWindowFocused,
    .beginTable = beginTable,
    .endTable = endTable,
    .tableSetupColumn = tableSetupColumn,
    .tableHeadersRow = tableHeadersRow,
    .tableNextColumn = tableNextColumn,
    .tableNextRow = tableNextRow,
    .tableSetupScrollFreeze = tableSetupScrollFreeze,
    .getItemRectMax = getItemRectMax,
    .getItemRectMin = getItemRectMin,
    .getCursorPosX = getCursorPosX,
    .calcTextSize = calcTextSize,
    .getWindowPos = getWindowPos,
    .getWindowSize = getWindowSize,
    .getContentRegionAvail = getContentRegionAvail,
    .setCursorPosX = setCursorPosX,
    .setCursorPosY = setCursorPosY,
    .setCursorScreenPos = setCursorScreenPos,
    .selectable = selectable,
    .getStyle = getStyle,
    .pushStyleVar2f = pushStyleVar2f,
    .pushStyleVar1f = pushStyleVar1f,
    .popStyleVar = popStyleVar,
    .isKeyDown = isKeyDown,
    .labelText = labelText,
    .sameLine = sameLine,
    .indent = indent,
    .unindent = unindent,
    .button = button,
    .smallButton = smallButton,
    .invisibleButton = invisibleButton,
    .inputText = inputText,
    .inputF32 = inputF32,
    .inputF64 = inputF64,
    .inputI32 = inputI32,
    .inputU32 = inputU32,
    .inputI64 = inputI64,
    .inputU64 = inputU64,
    .dragF32 = dragF32,
    .dragVec3f = dragVec3f,
    .dragF64 = dragDouble,
    .dragI32 = dragI32,
    .dragU32 = dragU32,
    .dragU64 = dragU64,
    .dragI64 = dragI64,
    .checkbox = checkbox,
    .toggleButton = toggleButton,
    .toggleMenuItem = toggleMenuItem,
    .combo = combo,
    .alignTextToFramePadding = alignTextToFramePadding,
    .isItemToggledOpen = isItemToggledOpen,
    .dummy = dummy,
    .spacing = spacing,
    .getScrollX = getScrollX,
    .getScrollY = getScrollY,
    .getScrollMaxX = getScrollMaxX,
    .getScrollMaxY = getScrollMaxY,
    .setScrollHereY = setScrollHereY,
    .setScrollHereX = setScrollHereX,
    .uiFilterPass = uiFilterPass,
    .uiFilter = uiFilter,
    .beginDragDropSource = beginDragDropSource,
    .setDragDropPayload = setDragDropPayload,
    .endDragDropSource = endDragDropSource,
    .beginDragDropTarget = beginDragDropTarget,
    .acceptDragDropPayload = acceptDragDropPayload,
    .endDragDropTarget = endDragDropTarget,
    .getDragDropPayload = getDragDropPayload,
    .isMouseDoubleClicked = isMouseDoubleClicked,
    .isMouseDown = isMouseDown,
    .isMouseClicked = isMouseClicked,
    .beginTabBar = beginTabBar,
    .beginTabItem = beginTabItem,
    .endTabBar = endTabBar,
    .endTabItem = endTabItem,
    .handleSelection = handleSelection,
    .pushPropName = pushPropName,
    .pushName = pushName,
    .getFontSize = getFontSize,
    .popFontSize = popFontSize,
    .getCursorPos = getCursorPos,
    .getCursorScreenPos = getCursorScreenPos,
    .getMousePos = getMousePos,
    .getMouseDragDelta = getMouseDragDelta,
    .setMouseCursor = setMouseCursor,
    .popItemWidth = popItemWidth,
    .pushItemWidth = pushItemWidth,
    .isItemVisible = isItemVisible,
    .isRectVisible = isRectVisible,
    .beginDisabled = beginDisabled,
    .endDisabled = endDisabled,
    .getCurrentWindow = getCurrentWindow,
    .setScaleFactor = setScaleFactor,
    .getScaleFactor = getScaleFactor,
    .mainDockSpace = mainDockSpace,
    .image = image,
    .pushFontSize = pushFontSize,
    .showTestingWindow = showTestingWindow,
    .showExternalCredits = showExternalCredits,
    .showAuthors = showAuthors,
    .registerTest = registerTestFn,
    .reloadTests = reloadTests,
    .testRunAll = testRunAll,
    .testIsRunning = testIsRunning,
    .testPrintResult = testPrintResult,
    .testGetResult = testGetResult,
    .testSetRunSpeed = testSetRunSpeed,
    .testExportJunitResult = testExportJunitResult,
    .testCheck = @ptrCast(&zguite.check),
    .testContextSetRef = @ptrCast(&zguite.TestContext.setRef),
    .testContextWindowFocus = @ptrCast(&zguite.TestContext.windowFocus),
    .testItemAction = @ptrCast(&zguite.TestContext.itemAction),
    .testContextYield = @ptrCast(&zguite.TestContext.yield),
    .testContextMenuAction = @ptrCast(&zguite.TestContext.menuAction),
    .testItemInputStrValue = @ptrCast(&zguite.TestContext.itemInputStrValue),
    .testItemInputIntValue = @ptrCast(&zguite.TestContext.itemInputIntValue),
    .testItemInputFloatValue = @ptrCast(&zguite.TestContext.itemInputFloatValue),
    .testDragAndDrop = @ptrCast(&zguite.TestContext.dragAndDrop),
    .testKeyDown = @ptrCast(&zguite.TestContext.keyDown),
    .testKeyUp = @ptrCast(&zguite.TestContext.keyUp),
    .beginPlot = @ptrCast(&zgui.plot.beginPlot),
    .endPlot = @ptrCast(&zgui.plot.endPlot),
    .plotLineF64 = plotLineF64,
    .plotLineValuesF64 = plotLineValuesF64,
    .setupAxis = @ptrCast(&zgui.plot.setupAxis),
    .setupFinish = @ptrCast(&zgui.plot.setupFinish),
    .setupLegend = @ptrCast(&zgui.plot.setupLegend),
    .getWindowDrawList = getWindowDrawList,
    .gizmoSetRect = @ptrCast(&zgui.gizmo.setRect),
    .gizmoManipulate = gizmoManipulate,
    .gizmoSetDrawList = gizmoSetDrawList,
    .gizmoSetAlternativeWindow = @ptrCast(&zgui.gizmo.setAlternativeWindow),
    .gizmoIsUsing = @ptrCast(&zgui.gizmo.isUsing),
    .gizmoIsOver = @ptrCast(&zgui.gizmo.isOver),
};

fn pushFontSize(font_size_base_unscaled: f32) void {
    zgui.pushFont(null, font_size_base_unscaled);
}

fn getCurrentWindow() *public.ImGuiWindow {
    return @ptrCast(@alignCast(zgui.getCurrentWindow()));
}

fn getMousePos() math.Vec2f {
    return .fromArray(zgui.getMousePos());
}
fn getMouseDragDelta(drag_button: public.MouseButton, args: public.MouseDragDelta) math.Vec2f {
    return .fromArray(zgui.getMouseDragDelta(@enumFromInt(@intFromEnum(drag_button)), .{ .lock_threshold = args.lock_threshold }));
}
fn setMouseCursor(cursor: public.Cursor) void {
    zgui.setMouseCursor(@enumFromInt(@intFromEnum(cursor)));
}
fn popItemWidth() void {
    zgui.popItemWidth();
}
fn pushItemWidth(item_width: f32) void {
    zgui.pushItemWidth(item_width);
}

fn beginDisabled(args: public.BeginDisabled) void {
    zgui.beginDisabled(.{ .disabled = args.disabled });
}
fn endDisabled() void {
    zgui.endDisabled();
}

fn begin(name: [:0]const u8, args: public.Begin) bool {
    return zgui.begin(name, .{
        .flags = @bitCast(args.flags),
        .popen = args.popen,
    });
}
fn end() void {
    zgui.end();
}
fn isItemToggledOpen() bool {
    return zgui.isItemToggledOpen();
}
fn dummy(args: public.Dummy) void {
    zgui.dummy(.{ .w = args.w, .h = args.h });
}
fn spacing() void {
    zgui.spacing();
}
fn getScrollX() f32 {
    return zgui.getScrollX();
}
fn getScrollY() f32 {
    return zgui.getScrollY();
}
fn getScrollMaxX() f32 {
    return zgui.getScrollMaxX();
}
fn getScrollMaxY() f32 {
    return zgui.getScrollMaxY();
}
fn setScrollHereY(args: public.SetScrollHereY) void {
    zgui.setScrollHereY(.{ .center_y_ratio = args.center_y_ratio });
}
fn setScrollHereX(args: public.SetScrollHereX) void {
    zgui.setScrollHereX(.{ .center_x_ratio = args.center_x_ratio });
}
fn getFontSize() f32 {
    return zgui.getFontSize();
}
fn popFontSize() void {
    zgui.popFont();
}
fn getStyle() *public.Style {
    return @ptrCast(@alignCast(zgui.getStyle()));
}
fn pushStyleVar2f(args: public.PushStyleVar2f) void {
    zgui.pushStyleVar2f(.{ .idx = @enumFromInt(@intFromEnum(args.idx)), .v = args.v.toArray() });
}
fn pushStyleVar1f(args: public.PushStyleVar1f) void {
    zgui.pushStyleVar1f(.{ .idx = @enumFromInt(@intFromEnum(args.idx)), .v = args.v });
}
fn pushStyleColor4f(args: public.PushStyleColor4f) void {
    zgui.pushStyleColor4f(.{ .idx = @enumFromInt(@intFromEnum(args.idx)), .c = args.c.toArray() });
}
fn popStyleColor(args: public.PopStyleColor) void {
    zgui.popStyleColor(.{ .count = args.count });
}
fn popStyleVar(args: public.PopStyleVar) void {
    zgui.popStyleVar(.{ .count = args.count });
}
fn isKeyDown(key: public.Key) bool {
    return zgui.isKeyDown(@enumFromInt(@intFromEnum(key)));
}
fn tableSetBgColor(args: public.TableSetBgColor) void {
    zgui.tableSetBgColor(.{ .color = args.color.toU32(), .column_n = args.column_n, .target = @enumFromInt(@intFromEnum(args.target)) });
}
fn text(txt: []const u8) void {
    zgui.textUnformatted(txt);
}
fn textColored(color: math.Color4f, txt: []const u8) void {
    zgui.textUnformattedColored(color.toArray(), txt);
}
fn colorPicker4(label: [:0]const u8, args: public.ColorPicker4) bool {
    return zgui.colorPicker4(label, .{ .flags = @bitCast(args.flags), .col = @ptrCast(args.col), .ref_col = args.ref_col });
}
fn colorEdit4(label: [:0]const u8, args: public.ColorEdit4) bool {
    return zgui.colorEdit4(label, .{ .col = @ptrCast(args.col), .flags = @bitCast(args.flags) });
}
fn beginMainMenuBar() bool {
    return zgui.beginMainMenuBar();
}
fn endMainMenuBar() void {
    zgui.endMainMenuBar();
}
fn beginMenuBar() bool {
    return zgui.beginMenuBar();
}
fn endMenuBar() void {
    zgui.endMenuBar();
}
fn endMenu() void {
    zgui.endMenu();
}
fn beginChild(str_id: [:0]const u8, args: public.BeginChild) bool {
    return zgui.beginChild(str_id, .{
        .h = args.h,
        .w = args.w,
        .child_flags = @bitCast(args.child_flags),
        .window_flags = @bitCast(args.window_flags),
    });
}
fn endChild() void {
    zgui.endChild();
}
fn pushPtrId(ptr_id: *const anyopaque) void {
    zgui.pushPtrId(ptr_id);
}
fn pushIntId(int_id: u32) void {
    zgui.pushIntId(@bitCast(int_id));
}
fn popId() void {
    zgui.popId();
}
fn treeNode(label: [:0]const u8) bool {
    return zgui.treeNode(label);
}
fn treeNodeFlags(label: [:0]const u8, flags: public.TreeNodeFlags) bool {
    return zgui.treeNodeFlags(label, @bitCast(flags));
}
fn treePop() void {
    zgui.treePop();
}
fn alignTextToFramePadding() void {
    zgui.alignTextToFramePadding();
}
fn isItemHovered(flags: public.HoveredFlags) bool {
    return zgui.isItemHovered(@bitCast(flags));
}
fn isWindowFocused(flags: public.FocusedFlags) bool {
    return zgui.isWindowFocused(@bitCast(flags));
}
fn button(label: [:0]const u8, args: public.Button) bool {
    return zgui.button(label, .{ .h = args.h, .w = args.w });
}
fn smallButton(label: [:0]const u8) bool {
    return zgui.smallButton(label);
}
fn invisibleButton(label: [:0]const u8, args: public.InvisibleButton) bool {
    return zgui.invisibleButton(label, .{ .h = args.h, .w = args.w, .flags = @bitCast(args.flags) });
}
fn sameLine(args: public.SameLine) void {
    return zgui.sameLine(.{ .offset_from_start_x = args.offset_from_start_x, .spacing = args.spacing });
}
fn indent(args: public.Indent) void {
    zgui.indent(.{ .indent_w = args.indent_w });
}
fn unindent(args: public.Unindent) void {
    zgui.unindent(.{ .indent_w = args.indent_w });
}

fn inputText(label: [:0]const u8, args: public.InputText) bool {
    return zgui.inputText(label, .{
        .buf = args.buf,
        .user_data = args.user_data,
        .callback = @ptrCast(@alignCast(args.callback)),
        .flags = @bitCast(args.flags),
    });
}
fn inputF32(label: [:0]const u8, args: public.InputF32) bool {
    return zgui.inputFloat(label, .{
        .v = args.v,
        .cfmt = args.cfmt,
        .step = args.step,
        .step_fast = args.step_fast,
    });
}
fn inputF64(label: [:0]const u8, args: public.InputF64) bool {
    return zgui.inputDouble(label, .{
        .v = args.v,
        .cfmt = args.cfmt,
        .step = args.step,
        .step_fast = args.step_fast,
    });
}
fn dragF32(label: [:0]const u8, args: public.DragFloatGen(f32)) bool {
    return zgui.dragFloat(label, .{
        .cfmt = args.cfmt,
        .v = args.v,
        .max = args.max,
        .min = args.min,
        .speed = args.speed,
        .flags = @bitCast(args.flags),
    });
}
fn dragVec3f(label: [:0]const u8, args: public.DragFloatGen(math.Vec3f)) bool {
    return zgui.dragFloat3(label, .{
        .cfmt = args.cfmt,
        .v = @ptrCast(args.v),
        .max = args.max,
        .min = args.min,
        .speed = args.speed,
        .flags = @bitCast(args.flags),
    });
}
fn checkbox(label: [:0]const u8, args: public.Checkbox) bool {
    return zgui.checkbox(label, .{ .v = args.v });
}
fn setClipboardText(value: [:0]const u8) void {
    zgui.setClipboardText(value);
}
fn beginPopupContextItem() bool {
    return zgui.beginPopupContextItem();
}
fn isItemClicked(buttonn: public.MouseButton) bool {
    return zgui.isItemClicked(@enumFromInt(@intFromEnum(buttonn)));
}
fn isItemActivated() bool {
    return zgui.isItemActivated();
}
fn isRectVisible(rect: math.Vec2f) bool {
    return zgui.isRectVisible(@constCast(&rect.toArray()));
}
fn isItemVisible() bool {
    return zgui.isItemVisible();
}
fn beginPopupModal(name: [:0]const u8, args: public.Begin) bool {
    return zgui.beginPopupModal(name, .{ .popen = args.popen, .flags = @bitCast(args.flags) });
}
fn endPopup() void {
    zgui.endPopup();
}
fn closeCurrentPopup() void {
    zgui.closeCurrentPopup();
}
fn beginTooltip() bool {
    return zgui.beginTooltip();
}
fn endTooltip() void {
    zgui.endTooltip();
}
fn separator() void {
    zgui.separator();
}
fn separatorText(label: [:0]const u8) void {
    zgui.separatorText(label);
}
fn setNextItemWidth(item_width: f32) void {
    zgui.setNextItemWidth(item_width);
}
fn setNextWindowSize(args: public.SetNextWindowSize) void {
    zgui.setNextWindowSize(.{ .h = args.h, .w = args.w, .cond = @enumFromInt(@intFromEnum(args.cond)) });
}
fn beginTable(name: [:0]const u8, args: public.BeginTable) bool {
    return zgui.beginTable(name, .{ .column = args.column, .inner_width = args.inner_width, .outer_size = args.outer_size.toArray(), .flags = @bitCast(args.flags) });
}
fn endTable() void {
    zgui.endTable();
}
fn tableSetupColumn(label: [:0]const u8, args: public.TableSetupColumn) void {
    zgui.tableSetupColumn(label, .{ .user_id = args.user_id, .init_width_or_height = args.init_width_or_height, .flags = @bitCast(args.flags) });
}
fn tableHeadersRow() void {
    zgui.tableHeadersRow();
}
fn tableNextColumn() bool {
    return zgui.tableNextColumn();
}
fn tableNextRow(args: public.TableNextRow) void {
    zgui.tableNextRow(.{ .min_row_height = args.min_row_height, .row_flags = @bitCast(args.row_flags) });
}
fn tableSetupScrollFreeze(cols: i32, rows: i32) void {
    zgui.tableSetupScrollFreeze(cols, rows);
}
fn getItemRectMax() math.Vec2f {
    return .fromArray(zgui.getItemRectMax());
}
fn getItemRectMin() math.Vec2f {
    return .fromArray(zgui.getItemRectMin());
}
fn getCursorPosX() f32 {
    return zgui.getCursorPosX();
}
fn getCursorPos() math.Vec2f {
    return .fromArray(zgui.getCursorPos());
}
fn getCursorScreenPos() math.Vec2f {
    return .fromArray(zgui.getCursorScreenPos());
}
fn calcTextSize(txt: []const u8, args: public.CalcTextSize) math.Vec2f {
    return .fromArray(zgui.calcTextSize(txt, .{ .hide_text_after_double_hash = args.hide_text_after_double_hash, .wrap_width = args.wrap_width }));
}
fn getWindowPos() math.Vec2f {
    return .fromArray(zgui.getWindowPos());
}
fn getWindowSize() math.Vec2f {
    return .fromArray(zgui.getWindowSize());
}
fn getContentRegionAvail() math.Vec2f {
    return .fromArray(zgui.getContentRegionAvail());
}
fn setCursorPosX(x: f32) void {
    zgui.setCursorPosX(x);
}
fn setCursorPosY(y: f32) void {
    zgui.setCursorPosY(y);
}
fn setCursorScreenPos(pos: math.Vec2f) void {
    zgui.setCursorScreenPos(pos.toArray());
}
fn selectable(label: [:0]const u8, args: public.Selectable) bool {
    return zgui.selectable(label, .{ .h = args.h, .w = args.w, .selected = args.selected, .flags = @bitCast(args.flags) });
}
fn beginDragDropSource(flags: public.DragDropFlags) bool {
    return zgui.beginDragDropSource(@bitCast(flags));
}
fn setDragDropPayload(payload_type: [*:0]const u8, data: []const u8, cond: public.Condition) bool {
    return zgui.setDragDropPayload(payload_type, data, @enumFromInt(@intFromEnum(cond)));
}
fn endDragDropSource() void {
    zgui.endDragDropSource();
}
fn beginDragDropTarget() bool {
    return zgui.beginDragDropTarget();
}
fn acceptDragDropPayload(payload_type: [*:0]const u8, flags: public.DragDropFlags) ?*public.Payload {
    return @ptrCast(@alignCast(zgui.acceptDragDropPayload(payload_type, @bitCast(flags))));
}
fn endDragDropTarget() void {
    zgui.endDragDropTarget();
}
fn getDragDropPayload() ?*public.Payload {
    return @ptrCast(@alignCast(zgui.getDragDropPayload()));
}
fn isMouseDown(mouse_button: public.MouseButton) bool {
    return zgui.isMouseDown(@enumFromInt(@intFromEnum(mouse_button)));
}
fn beginTabBar(label: [:0]const u8, flags: public.TabBarFlags) bool {
    return zgui.beginTabBar(label, @bitCast(flags));
}
fn beginTabItem(label: [:0]const u8, args: public.BeginTabItem) bool {
    return zgui.beginTabItem(label, .{ .flags = @bitCast(args.flags), .p_open = args.p_open });
}
fn endTabBar() void {
    zgui.endTabBar();
}
fn endTabItem() void {
    zgui.endTabItem();
}

fn gizmoManipulate(
    view: math.Mat44f,
    projection: math.Mat44f,
    operation: public.Operation,
    mode: public.GizmoMode,
    matrix: *math.Mat44f,
    opt: public.GuizmoOpt,
) bool {
    return zgui.gizmo.manipulate(
        &view.toArray(),
        &projection.toArray(),
        @bitCast(operation),
        @enumFromInt(@intFromEnum(mode)),
        @ptrCast(matrix),
        .{
            .delta_matrix = @ptrCast(opt.delta_matrix),
            .snap = if (opt.snap) |s| &s.toArray() else null,
            .local_bounds = opt.local_bounds,
            .bounds_snap = if (opt.bounds_snap) |s| &s.toArray() else null,
        },
    );
}

fn isMouseDoubleClicked(mouse_button: public.MouseButton) bool {
    return zgui.isMouseDoubleClicked(@enumFromInt(@intFromEnum(mouse_button)));
}

fn isMouseClicked(mouse_button: public.MouseButton) bool {
    return zgui.isMouseClicked(@enumFromInt(@intFromEnum(mouse_button)));
}

fn beginPopup(str_id: [:0]const u8, flags: public.WindowFlags) bool {
    return zgui.beginPopup(str_id, std.mem.bytesToValue(zgui.WindowFlags, std.mem.asBytes(&flags)));
}

fn openPopup(str_id: [:0]const u8, flags: public.PopupFlags) void {
    zgui.openPopup(str_id, std.mem.bytesToValue(zgui.PopupFlags, std.mem.asBytes(&flags)));
}

pub fn gizmoSetDrawList(draw_list: ?public.DrawList) void {
    zgui.gizmo.setDrawList(if (draw_list) |dl| @ptrCast(dl.ptr) else null);
}

fn getWindowDrawList() public.DrawList {
    return public.DrawList{
        .ptr = zgui.getWindowDrawList(),
        .vtable = &drawlist_vtable,
    };
}

fn separatorMenu() void {
    zgui.textUnformatted("|");
}

const node_editor_api = node_editor.NodeEditorApi{
    .createEditor = createEditor,
    .destroyEditor = @ptrCast(&zne.EditorContext.destroy),
    .setCurrentEditor = @ptrCast(&zne.setCurrentEditor),
    .begin = @ptrCast(&zne.begin),
    .end = @ptrCast(&zne.end),
    .beginCreate = @ptrCast(&zne.beginCreate),
    .endCreate = @ptrCast(&zne.endCreate),
    .showBackgroundContextMenu = @ptrCast(&zne.showBackgroundContextMenu),
    .ssuspend = @ptrCast(&zne.suspend_),
    .rresume = @ptrCast(&zne.resume_),
    .beginNode = @ptrCast(&zne.beginNode),
    .endNode = @ptrCast(&zne.endNode),
    .deleteNode = @ptrCast(&zne.deleteNode),
    .beginPin = @ptrCast(&zne.beginPin),
    .endPin = @ptrCast(&zne.endPin),
    .setNodePosition = @ptrCast(&zne.setNodePosition),
    .getNodePosition = @ptrCast(&zne.getNodePosition),
    .link = @ptrCast(&zne.link),
    .queryNewLink = @ptrCast(&zne.queryNewLink),
    .acceptNewItem = @ptrCast(&zne.acceptNewItem),
    .rejectNewItem = @ptrCast(&zne.rejectNewItem),
    .deleteLink = @ptrCast(&zne.deleteLink),
    .beginDelete = @ptrCast(&zne.beginDelete),
    .endDelete = @ptrCast(&zne.endDelete),
    .queryDeletedLink = @ptrCast(&zne.queryDeletedLink),
    .queryDeletedNode = @ptrCast(&zne.queryDeletedNode),
    .acceptDeletedItem = @ptrCast(&zne.acceptDeletedItem),
    .rejectDeletedItem = @ptrCast(&zne.rejectDeletedItem),
    .showNodeContextMenu = @ptrCast(&zne.showNodeContextMenu),
    .showLinkContextMenu = @ptrCast(&zne.showLinkContextMenu),
    .showPinContextMenu = @ptrCast(&zne.showPinContextMenu),
    .navigateToContent = @ptrCast(&zne.navigateToContent),
    .navigateToSelection = @ptrCast(&zne.navigateToSelection),
    .pinHadAnyLinks = @ptrCast(&zne.pinHadAnyLinks),
    .breakPinLinks = @ptrCast(&zne.breakPinLinks),
    .getStyleColorName = @ptrCast(&zne.getStyleColorName),
    .getStyle = @ptrCast(&zne.getStyle),
    .pushStyleColor = @ptrCast(&zne.pushStyleColor),
    .popStyleColor = @ptrCast(&zne.popStyleColor),
    .pushStyleVar1f = @ptrCast(&zne.pushStyleVar1f),
    .pushStyleVar2f = @ptrCast(&zne.pushStyleVar2f),
    .pushStyleVar4f = @ptrCast(&zne.pushStyleVar4f),
    .popStyleVar = @ptrCast(&zne.popStyleVar),
    .hasSelectionChanged = @ptrCast(&zne.hasSelectionChanged),
    .getSelectedObjectCount = @ptrCast(&zne.getSelectedObjectCount),
    .clearSelection = @ptrCast(&zne.clearSelection),
    .getSelectedNodes = @ptrCast(&zne.getSelectedNodes),
    .getSelectedLinks = @ptrCast(&zne.getSelectedLinks),
    .selectNode = @ptrCast(&zne.selectNode),
    .selectLink = @ptrCast(&zne.selectLink),
    .group = @ptrCast(&zne.group),
    .getNodeSize = @ptrCast(&zne.getNodeSize),
    .getHintForegroundDrawList = getHintForegroundDrawList,
    .getHintBackgroundDrawList = getHintBackgroundDrawList,
    .getNodeBackgroundDrawList = getNodeBackgroundDrawList,
    .pinRect = @ptrCast(&zne.pinRect),
    .pinPivotRect = @ptrCast(&zne.pinPivotRect),
    .pinPivotSize = @ptrCast(&zne.pinPivotSize),
    .pinPivotScale = @ptrCast(&zne.pinPivotScale),
    .pinPivotAlignment = @ptrCast(&zne.pinPivotAlignment),
};

fn getHintForegroundDrawList() public.DrawList {
    return public.DrawList{
        .ptr = zne.getHintForegroundDrawList(),
        .vtable = &drawlist_vtable,
    };
}
fn getHintBackgroundDrawList() public.DrawList {
    return public.DrawList{
        .ptr = zne.getHintBackgroundDrawLis(),
        .vtable = &drawlist_vtable,
    };
}
fn getNodeBackgroundDrawList(node_id: node_editor.NodeId) public.DrawList {
    return public.DrawList{
        .ptr = zne.getNodeBackgroundDrawList(node_id),
        .vtable = &drawlist_vtable,
    };
}

fn createEditor(cfg: node_editor.Config) *node_editor.EditorContext {
    const node_editor_cfg = zne.Config{
        .settings_file = cfg.settings_file,
        .begin_save_session = @ptrCast(cfg.begin_save_session),
        .end_save_session = @ptrCast(cfg.end_save_session),
        .save_settings = @ptrCast(cfg.save_settings),
        .load_settings = @ptrCast(cfg.load_settings),
        .save_node_settings = @ptrCast(cfg.save_node_settings),
        .load_node_settings = cfg.load_node_settings,
        .user_pointer = cfg.user_pointer,
        .canvas_size_mode = @enumFromInt(@intFromEnum(cfg.canvas_size_mode)),
        .drag_button_index = cfg.drag_button_index,
        .select_button_index = cfg.select_button_index,
        .navigate_button_index = cfg.navigate_button_index,
        .context_menu_button_index = cfg.context_menu_button_index,
        .enable_smooth_zoom = cfg.enable_smooth_zoom,
        .smooth_zoom_power = cfg.smooth_zoom_power,
    };

    return @ptrCast(zne.EditorContext.create(node_editor_cfg));
}

const clipper_vtable = public.ListClipper.VTable.implement(struct {
    pub fn begin(self: *public.ListClipper, items_count: ?i32, items_height: ?f32) void {
        zgui.ListClipper.begin(@ptrCast(self), items_count, items_height);
    }

    pub fn end(self: *public.ListClipper) void {
        zgui.ListClipper.end(@ptrCast(self));
    }
    pub fn includeItemsByIndex(self: *public.ListClipper, item_begin: i32, item_end: i32) void {
        zgui.ListClipper.includeItemsByIndex(@ptrCast(self), item_begin, item_end);
    }
    pub fn step(self: *public.ListClipper) bool {
        return zgui.ListClipper.step(@ptrCast(self));
    }
});

const drawlist_vtable = public.DrawList.VTable.implement(struct {
    pub fn getOwnerName(draw_list: *anyopaque) ?[*:0]const u8 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getOwnerName();
    }
    pub fn reset(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.reset();
    }
    pub fn clearMemory(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.clearMemory();
    }
    pub fn getVertexBufferLength(draw_list: *anyopaque) i32 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getVertexBufferLength();
    }
    pub fn getVertexBufferData(draw_list: *anyopaque) [*]public.DrawVert {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return @ptrCast(dl.getVertexBufferData());
    }

    pub fn getIndexBufferLength(draw_list: *anyopaque) i32 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getIndexBufferLength();
    }
    pub fn getIndexBufferData(draw_list: *anyopaque) [*]public.DrawIdx {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getIndexBufferData();
    }

    pub fn getCurrentIndex(draw_list: *anyopaque) u32 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getCurrentIndex();
    }
    pub fn getCmdBufferLength(draw_list: *anyopaque) i32 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getCmdBufferLength();
    }
    pub fn getCmdBufferData(draw_list: *anyopaque) [*]public.DrawCmd {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return @ptrCast(dl.getCmdBufferData());
    }

    pub fn setDrawListFlags(draw_list: *anyopaque, flags: public.DrawListFlags) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.setDrawListFlags(.{
            .anti_aliased_lines = flags.anti_aliased_lines,
            .anti_aliased_lines_use_tex = flags.anti_aliased_lines_use_tex,
            .anti_aliased_fill = flags.anti_aliased_fill,
            .allow_vtx_offset = flags.allow_vtx_offset,
        });
    }
    pub fn getDrawListFlags(draw_list: *anyopaque) public.DrawListFlags {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        const flags = dl.getDrawListFlags();
        return .{
            .anti_aliased_lines = flags.anti_aliased_lines,
            .anti_aliased_lines_use_tex = flags.anti_aliased_lines_use_tex,
            .anti_aliased_fill = flags.anti_aliased_fill,
            .allow_vtx_offset = flags.allow_vtx_offset,
        };
    }
    pub fn pushClipRect(draw_list: *anyopaque, args: public.ClipRect) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.pushClipRect(.{
            .pmin = args.pmin.toArray(),
            .pmax = args.pmax.toArray(),
            .intersect_with_current = args.intersect_with_current,
        });
    }
    pub fn pushClipRectFullScreen(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.pushClipRectFullScreen();
    }
    pub fn popClipRect(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.popClipRect();
    }
    pub fn pushTextureId(draw_list: *anyopaque, texture_id: gpu.TextureHandle) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.pushTexture(.{ .tex_id = @enumFromInt(texture_id.idx), .tex_data = null });
    }
    pub fn popTextureId(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.popTexture();
    }
    pub fn getClipRectMin(draw_list: *anyopaque) math.Vec2f {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return .fromArray(dl.getClipRectMin());
    }
    pub fn getClipRectMax(draw_list: *anyopaque) math.Vec2f {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return .fromArray(dl.getClipRectMax());
    }
    pub fn addLine(draw_list: *anyopaque, args: struct { p1: math.Vec2f, p2: math.Vec2f, col: math.SRGBA, thickness: f32 }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addLine(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .col = args.col.toU32(),
            .thickness = args.thickness,
        });
    }
    pub fn addRect(draw_list: *anyopaque, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        col: math.SRGBA,
        rounding: f32 = 0.0,
        flags: public.DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addRect(.{
            .pmin = args.pmin.toArray(),
            .pmax = args.pmax.toArray(),
            .col = args.col.toU32(),
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
    pub fn addRectFilled(draw_list: *anyopaque, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        col: math.SRGBA,
        rounding: f32 = 0.0,
        flags: public.DrawFlags = .{},
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addRectFilled(.{
            .pmin = args.pmin.toArray(),
            .pmax = args.pmax.toArray(),
            .col = args.col.toU32(),
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
    pub fn addRectFilledMultiColor(draw_list: *anyopaque, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        col_upr_left: u32,
        col_upr_right: u32,
        col_bot_right: u32,
        col_bot_left: u32,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addRectFilledMultiColor(.{
            .pmin = args.pmin.toArray(),
            .pmax = args.pmax.toArray(),
            .col_upr_left = args.col_upr_left,
            .col_upr_right = args.col_upr_right,
            .col_bot_right = args.col_bot_right,
            .col_bot_left = args.col_bot_left,
        });
    }
    pub fn addQuad(draw_list: *anyopaque, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addQuad(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .p4 = args.p4.toArray(),
            .col = args.col.toU32(),
            .thickness = args.thickness,
        });
    }

    pub fn addQuadFilled(draw_list: *anyopaque, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        col: math.SRGBA,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addQuadFilled(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .p4 = args.p4.toArray(),
            .col = args.col.toU32(),
        });
    }
    pub fn addTriangle(draw_list: *anyopaque, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addTriangle(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .col = args.col.toU32(),
            .thickness = args.thickness,
        });
    }
    pub fn addTriangleFilled(draw_list: *anyopaque, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        col: math.SRGBA,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addTriangleFilled(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .col = args.col.toU32(),
        });
    }
    pub fn addCircle(draw_list: *anyopaque, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: i32 = 0,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addCircle(.{
            .p = args.p.toArray(),
            .r = args.r,
            .col = args.col.toU32(),
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub fn addCircleFilled(draw_list: *anyopaque, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);

        dl.addCircleFilled(.{
            .p = args.p.toArray(),
            .r = args.r,
            .col = args.col.toU32(),
            .num_segments = args.num_segments,
        });
    }
    pub fn addNgon(draw_list: *anyopaque, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: u32,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addNgon(.{
            .p = args.p.toArray(),
            .r = args.r,
            .col = args.col.toU32(),
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub fn addNgonFilled(draw_list: *anyopaque, args: struct {
        p: math.Vec2f,
        r: f32,
        col: math.SRGBA,
        num_segments: u32,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addNgonFilled(.{
            .p = args.p.toArray(),
            .r = args.r,
            .col = args.col.toU32(),
            .num_segments = args.num_segments,
        });
    }
    pub fn addTextUnformatted(draw_list: *anyopaque, pos: math.Vec2f, col: math.SRGBA, txt: []const u8) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addTextUnformatted(pos.toArray(), col.toU32(), txt);
    }
    pub fn addPolyline(draw_list: *anyopaque, points: []const math.Vec2f, args: struct {
        col: math.SRGBA,
        flags: public.DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addPolyline(std.mem.bytesAsSlice([2]f32, std.mem.sliceAsBytes(points)), .{
            .col = args.col.toU32(),
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
    pub fn addConvexPolyFilled(draw_list: *anyopaque, points: []const math.Vec2f, col: math.SRGBA) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addConvexPolyFilled(std.mem.bytesAsSlice([2]f32, std.mem.sliceAsBytes(points)), col.toU32());
    }
    pub fn addBezierCubic(draw_list: *anyopaque, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addBezierCubic(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .p4 = args.p4.toArray(),
            .col = args.col.toU32(),
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub fn addBezierQuadratic(draw_list: *anyopaque, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        col: math.SRGBA,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addBezierQuadratic(.{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .col = args.col.toU32(),
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub fn addImage(draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        uvmin: math.Vec2f = .{},
        uvmax: math.Vec2f = .{ .x = 1, .y = 1 },
        col: math.SRGBA = .white,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addImage(.{ .tex_id = @enumFromInt(user_texture_id.idx), .tex_data = null }, .{
            .pmin = args.pmin.toArray(),
            .pmax = args.pmax.toArray(),
            .uvmin = args.uvmin.toArray(),
            .uvmax = args.uvmax.toArray(),
            .col = args.col.toU32(),
        });
    }
    pub fn addImageQuad(draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
        p1: math.Vec2f,
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        uv1: math.Vec2f = .{},
        uv2: math.Vec2f = .{ .x = 1 },
        uv3: math.Vec2f = .{ .x = 1, .y = 1 },
        uv4: math.Vec2f = .{ .y = 1 },
        col: math.SRGBA = .white,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);

        dl.addImageQuad(.{ .tex_id = @enumFromInt(user_texture_id.idx), .tex_data = null }, .{
            .p1 = args.p1.toArray(),
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .p4 = args.p4.toArray(),
            .uv1 = args.uv1.toArray(),
            .uv2 = args.uv2.toArray(),
            .uv3 = args.uv3.toArray(),
            .uv4 = args.uv4.toArray(),
            .col = args.col.toU32(),
        });
    }

    pub fn addImageRounded(draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: math.Vec2f,
        pmax: math.Vec2f,
        uvmin: math.Vec2f = .{},
        uvmax: math.Vec2f = .{ .x = 1, .y = 1 },
        col: math.SRGBA = .white,
        rounding: f32 = 4.0,
        flags: public.DrawFlags = .{},
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);

        dl.addImageRounded(.{ .tex_data = null, .tex_id = @enumFromInt(user_texture_id.idx) }, .{
            .pmin = args.pmin.toArray(),
            .pmax = args.pmax.toArray(),
            .uvmin = args.uvmin.toArray(),
            .uvmax = args.uvmax.toArray(),
            .col = args.col.toU32(),
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
    pub fn pathClear(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathClear();
    }
    pub fn pathLineTo(draw_list: *anyopaque, pos: math.Vec2f) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathLineTo(pos.toArray());
    }
    pub fn pathLineToMergeDuplicate(draw_list: *anyopaque, pos: math.Vec2f) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathLineToMergeDuplicate(pos.toArray());
    }
    pub fn pathFillConvex(draw_list: *anyopaque, col: math.SRGBA) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathFillConvex(col.toU32());
    }
    pub fn pathStroke(draw_list: *anyopaque, args: struct {
        col: math.SRGBA,
        flags: public.DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathStroke(.{
            .col = args.col.toU32(),
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
    pub fn pathArcTo(draw_list: *anyopaque, args: struct {
        p: math.Vec2f,
        r: f32,
        amin: f32,
        amax: f32,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathArcTo(.{
            .p = args.p.toArray(),
            .r = args.r,
            .amin = args.amin,
            .amax = args.amax,
            .num_segments = args.num_segments,
        });
    }
    pub fn pathArcToFast(draw_list: *anyopaque, args: struct {
        p: math.Vec2f,
        r: f32,
        amin_of_12: u16,
        amax_of_12: u16,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathArcToFast(.{
            .p = args.p.toArray(),
            .r = args.r,
            .amin_of_12 = args.amin_of_12,
            .amax_of_12 = args.amax_of_12,
        });
    }
    pub fn pathBezierCubicCurveTo(draw_list: *anyopaque, args: struct {
        p2: math.Vec2f,
        p3: math.Vec2f,
        p4: math.Vec2f,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathBezierCubicCurveTo(.{
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .p4 = args.p4.toArray(),
            .num_segments = args.num_segments,
        });
    }
    pub fn pathBezierQuadraticCurveTo(draw_list: *anyopaque, args: struct {
        p2: math.Vec2f,
        p3: math.Vec2f,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathBezierQuadraticCurveTo(.{
            .p2 = args.p2.toArray(),
            .p3 = args.p3.toArray(),
            .num_segments = args.num_segments,
        });
    }
    pub fn pathRect(draw_list: *anyopaque, args: public.PathRect) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathRect(.{
            .bmin = args.bmin.toArray(),
            .bmax = args.bmax.toArray(),
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
    pub fn primReserve(draw_list: *anyopaque, idx_count: i32, vtx_count: i32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primReserve(idx_count, vtx_count);
    }
    pub fn primUnreserve(draw_list: *anyopaque, idx_count: i32, vtx_count: i32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primUnreserve(idx_count, vtx_count);
    }
    pub fn primRect(draw_list: *anyopaque, a: math.Vec2f, b: math.Vec2f, col: math.SRGBA) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primRect(a.toArray(), b.toArray(), col.toU32());
    }
    pub fn primRectUV(draw_list: *anyopaque, a: math.Vec2f, b: math.Vec2f, uv_a: math.Vec2f, uv_b: math.Vec2f, col: math.SRGBA) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primRectUV(
            a.toArray(),
            b.toArray(),
            uv_a.toArray(),
            uv_b.toArray(),
            col.toU32(),
        );
    }
    pub fn primQuadUV(draw_list: *anyopaque, a: math.Vec2f, b: math.Vec2f, c: math.Vec2f, d: math.Vec2f, uv_a: math.Vec2f, uv_b: math.Vec2f, uv_c: math.Vec2f, uv_d: math.Vec2f, col: math.SRGBA) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primQuadUV(
            a.toArray(),
            b.toArray(),
            c.toArray(),
            d.toArray(),
            uv_a.toArray(),
            uv_b.toArray(),
            uv_c.toArray(),
            uv_d.toArray(),
            col.toU32(),
        );
    }
    pub fn primWriteVtx(draw_list: *anyopaque, pos: math.Vec2f, uv: math.Vec2f, col: math.SRGBA) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primWriteVtx(pos.toArray(), uv.toArray(), col.toU32());
    }
    pub fn primWriteIdx(draw_list: *anyopaque, idx: public.DrawIdx) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primWriteIdx(idx);
    }
    pub fn addCallback(draw_list: *anyopaque, callback: public.DrawCallback, callback_data: ?*anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addCallback(@ptrCast(callback), callback_data);
    }
    pub fn addResetRenderStateCallback(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addResetRenderStateCallback();
    }
});

pub fn createClipper() public.ListClipper {
    const new_zgui = zgui.ListClipper.init();
    var new = public.ListClipper{ .vtable = &clipper_vtable };
    std.mem.copyForwards(u8, std.mem.asBytes(&new), std.mem.asBytes(&new_zgui));

    return new;
}

const BgfxImage = extern struct {
    handle: gpu.TextureHandle,
    a: u8 = 0,
    b: u8 = 0,
    c: u32 = 0,

    pub fn toTextureIdent(self: *const BgfxImage) zgui.TextureIdent {
        return std.mem.bytesToValue(zgui.TextureIdent, std.mem.asBytes(self));
    }
    pub fn fromTextureIdent(self: zgui.TextureIdent) BgfxImage {
        const p: *const BgfxImage = @ptrCast(@alignCast(&self));
        return p.*;
    }
};

fn image(texture: gpu.TextureHandle, args: public.Image) void {
    const tt = BgfxImage{
        .handle = texture,
    };

    zgui.image(.{ .tex_data = null, .tex_id = tt.toTextureIdent() }, .{
        .w = args.w,
        .h = args.h,
        .uv0 = if (_is_origin_bottom_left) .{ args.uv0.x, 1 - args.uv0.y } else args.uv0.toArray(),
        .uv1 = if (_is_origin_bottom_left) .{ args.uv1.x, 1 - args.uv1.y } else args.uv1.toArray(),
    });
}

fn mainDockSpace(flags: public.DockNodeFlags) zgui.Ident {
    const f: *zgui.DockNodeFlags = @ptrCast(@constCast(&flags));
    return zgui.dockSpaceOverViewport(0, zgui.getMainViewport(), f.*);
}

fn setScaleFactor(scale_factor: f32) void {
    _scale_factor = scale_factor;
    zgui.getStyle().font_scale_main = scale_factor;
}

fn getScaleFactor() f32 {
    return _scale_factor.?;
}

fn pushPropName(obj: cdb.ObjId, prop_idx: u32) void {
    const db = cdb.getDbFromObjid(obj);
    const props_def = cdb.getTypePropDef(db, obj.type_idx).?;
    zgui.pushStrIdZ(props_def[prop_idx].name);
}

fn pushName(str_id: [:0]const u8) void {
    zgui.pushStrIdZ(str_id);
}

fn testExportJunitResult(filename: [:0]const u8) void {
    _te_engine.exportJunitResult(filename);
}

fn testSetRunSpeed(speed: public.ImGuiTestRunSpeed) void {
    _te_engine.setRunSpeed(@enumFromInt(@intFromEnum(speed)));
}

fn testGetResult() public.TestResult {
    var count_tested: c_int = 0;
    var count_success: c_int = 0;
    _te_engine.getResult(&count_tested, &count_success);
    return .{ .count_tested = count_tested, .count_success = count_success };
}

fn testPrintResult() void {
    return _te_engine.printResultSummary();
}

fn testIsRunning() bool {
    return _backed_initialised and !_te_engine.isTestQueueEmpty();
}

fn testRunAll(filter: [:0]const u8) void {
    _te_engine.queueTests(.tests, filter, .{ .command_line = true });
}

fn reloadTests() !void {
    try registerAllTests();
}

fn registerTestFn(
    category: [*]const u8,
    name: [*]const u8,
    src: [*]const u8,
    src_line: c_int,
    gui_fce: ?*const public.ImGuiTestGuiFunc,
    gui_test_fce: ?*const public.ImGuiTestTestFunc,
) *public.Test {
    return zguite.zguiTe_RegisterTest(_te_engine, category, name, src, src_line, @ptrCast(gui_fce), @ptrCast(gui_test_fce));
}

fn showTestingWindow(show: *bool) void {
    if (show.*) {
        _te_engine.showTestEngineWindows(show);
    }
}

fn showExternalCredits(show: *bool) void {
    if (show.*) {
        setNextWindowSize(.{ .w = 600, .h = 600, .cond = .first_use_ever });
        if (begin(
            public.Icons.Externals ++ "  " ++ "External credits###ExternalCredits",
            .{ .popen = show, .flags = .{ .no_docking = true } },
        )) {
            defer end();

            _ = zgui.inputTextMultiline("###Credits", .{
                .buf = @constCast(kernel.getExternalsCredit()),
                .flags = .{ .read_only = true },
                .w = -1,
                .h = -1,
            });
        }
    }
}

fn showAuthors(show: *bool) void {
    if (show.*) {
        setNextWindowSize(.{ .w = 600, .h = 600, .cond = .first_use_ever });
        if (begin(
            public.Icons.Authors ++ "  " ++ "Authors###Authors",
            .{ .popen = show, .flags = .{ .no_docking = true } },
        )) {
            defer end();

            _ = zgui.inputTextMultiline("###Authors", .{
                .buf = @constCast(kernel.getAuthors()),
                .flags = .{ .read_only = true },
                .w = -1,
                .h = -1,
            });
        }
    }
}

fn beginMenu(allocator: std.mem.Allocator, label: [:0]const u8, enabled: bool, filter: ?[:0]const u8) bool {
    if (filter) |f| {
        if (null == uiFilterPass(allocator, f, label, false)) return false;
    }

    return zgui.beginMenu(label, enabled);
}

fn menuItem(allocator: std.mem.Allocator, label: [:0]const u8, args: public.MenuItem, filter: ?[:0]const u8) bool {
    if (filter) |f| {
        if (null == uiFilterPass(allocator, f, label, false)) return false;
    }

    return zgui.menuItem(label, .{
        .shortcut = args.shortcut,
        .selected = args.selected,
        .enabled = args.enabled,
    });
}

fn menuItemPtr(allocator: std.mem.Allocator, label: [:0]const u8, args: public.MenuItemPtr, filter: ?[:0]const u8) bool {
    if (filter) |f| {
        if (null == uiFilterPass(allocator, f, label, false)) return false;
    }
    return zgui.menuItemPtr(label, .{
        .shortcut = args.shortcut,
        .selected = args.selected,
        .enabled = args.enabled,
    });
}

fn pushObjUUID(obj: cdb.ObjId) void {
    const uuid = assetdb.getOrCreateUuid(obj) catch undefined;
    var buff: [128]u8 = undefined;
    const uuid_str = std.fmt.bufPrintZ(&buff, "{f}", .{uuid}) catch undefined;

    zgui.pushStrIdZ(uuid_str);
}

fn uiFilterPass(allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64 {
    // Collect token for filter
    var tokens = cetech1.ArrayList([]u8).empty;
    defer {
        for (tokens.items) |v| {
            allocator.free(v);
        }
        tokens.deinit(allocator);
    }

    var split = std.mem.splitAny(u8, filter, " ");
    const first = split.first();
    var it: ?[]const u8 = first;
    while (it) |word| : (it = split.next()) {
        if (word.len == 0) continue;

        const lower_token = std.ascii.allocLowerString(allocator, word) catch return null;

        tokens.append(allocator, lower_token) catch return null;
    }
    //return 0;

    return zf.rank(value, tokens.items, .{ .to_lower = true, .plain = !is_path });
}

fn uiFilter(buf: []u8, filter: ?[:0]const u8) ?[:0]const u8 {
    alignTextToFramePadding();
    text(public.Icons.Search);
    sameLine(.{});

    var input_buff: [128:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&input_buff, "{s}", .{filter orelse ""}) catch return null;

    setNextItemWidth(-1.0);
    if (inputText("###filter", .{
        .buf = &input_buff,
        .flags = .{
            .auto_select_all = true,
            //.enter_returns_true = true,
        },
    })) {
        const input = std.mem.sliceTo(&input_buff, 0);
        return std.fmt.bufPrintZ(buf, "{s}", .{input}) catch null;
    }

    if (filter) |f| {
        const len = f.len;
        if (len == 0) return null;
        return std.mem.sliceTo(f, 0);
    }

    return null;
}

pub fn labelText(label: [:0]const u8, txt: [:0]const u8) void {
    zgui.labelText(label, "{s}", .{txt});
}

pub fn drawUI(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, viewid: gpu.ViewId, kernel_tick: u64, dt: f32) !void {
    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "CoreUI: Draw UI");
    defer update_zone_ctx.End();

    const impls = try apidb.getImpl(allocator, cetech1.coreui.CoreUII);
    defer allocator.free(impls);

    for (impls) |iface| {
        try iface.ui(allocator, kernel_tick, dt);
    }

    backend.draw(gpu_backend, viewid);
}

pub fn registerToApi() !void {
    try apidb.setZigApi(module_name, public.CoreUIApi, &api);
    try apidb.setZigApi(module_name, node_editor.NodeEditorApi, &node_editor_api);
    try apidb.implOrRemove(.cdb_types, cdb.CreateTypesI, &create_cdb_types_i, true);
}

pub fn initFonts() void {
    const sized_pixel = 16; //font_size;

    // Load main font
    var main_cfg = zgui.FontConfig.init();
    main_cfg.font_data_owned_by_atlas = false;
    main_cfg.glyph_exclude_ranges = &[_:0]u16{ public.CoreIcons.ICON_MIN_LC, public.CoreIcons.ICON_MAX_LC, 0 };
    _ = zgui.io.addFontFromMemoryWithConfig(_font_main, sized_pixel, main_cfg, null);

    // Merge icons
    var icons_cfg = zgui.FontConfig.init();
    icons_cfg.font_data_owned_by_atlas = false;
    icons_cfg.merge_mode = true;
    icons_cfg.glyph_offset = .{ 0, 2 }; // TODO: WHYYYY????
    _ = zgui.io.addFontFromMemoryWithConfig(
        _font_icons,
        sized_pixel,
        icons_cfg,
        null,
    );
}

pub fn enableWithWindow(window: ?*cetech1.host.Window, gpu_backend: ?gpu.GpuBackend) !void {
    _scale_factor = scale_factor: {
        if (builtin.os.tag.isDarwin()) break :scale_factor 1;
        if (host.getWMType() == .Wayland) break :scale_factor 1;

        if (window) |w| {
            const scale = w.getContentScale();
            break :scale_factor @max(scale.x, scale.y);
        }

        break :scale_factor 1; // Headless mode
    };

    if (gpu_backend) |gpu_api| {
        _is_origin_bottom_left = gpu_api.isOriginBottomLeft();
    }

    //zgui.getStyle().frame_rounding = 8;

    zgui.io.setConfigFlags(zgui.ConfigFlags{
        .nav_enable_keyboard = true,
        .nav_enable_gamepad = true,
        .nav_enable_set_mouse_pos = true,
        .dock_enable = true,
        .dpi_enable_scale_fonts = true,
        .dpi_enable_scale_viewport = true,
    });
    zgui.io.setConfigWindowsMoveFromTitleBarOnly(true);

    // Headless
    if (window == null) {
        zgui.io.setDisplaySize(1024 * 2, 768 * 2);
    }

    _backed_initialised = true;

    initFonts();

    var style = zgui.getStyle();
    style.font_size_base = 16;
    style.font_scale_main = _scale_factor.?;
    style.frame_border_size = 1.0;
    style.docking_node_has_close_button = false;

    style.scaleAllSizes(_scale_factor.?);

    try backend.init(if (window) |w| w.getInternal(anyopaque) else null, gpu_backend);

    //TODO:
    _te_engine = zguite.getTestEngine().?;

    const test_ui = 1 == kernel.getIntArgs("--test-ui") orelse 0;
    const test_ui_filter = kernel.getStrArgs("--test-ui-filter") orelse "all";
    const test_ui_speed_value = kernel.getStrArgs("--test-ui-speed") orelse "fast";
    const test_ui_junit = kernel.getStrArgs("--test-ui-junit");
    _junit_filename = f: {
        if (test_ui_junit) |filename| {
            break :f try std.fmt.bufPrintZ(&_junit_filename_buff, "{s}", .{filename});
        } else {
            break :f null;
        }
    };

    const test_ui_speed: cetech1.coreui.ImGuiTestRunSpeed = speed: {
        if (std.mem.eql(u8, test_ui_speed_value, "fast")) {
            break :speed .Fast;
        } else if (std.mem.eql(u8, test_ui_speed_value, "normal")) {
            break :speed .Normal;
        } else if (std.mem.eql(u8, test_ui_speed_value, "cinematic")) {
            break :speed .Cinematic;
        } else {
            break :speed .Fast;
        }
    };

    try registerAllTests();

    if (test_ui) {
        const filter = try std.fmt.allocPrintSentinel(_allocator, "{s}", .{test_ui_filter}, 0);
        defer _allocator.free(filter);
        testSetRunSpeed(test_ui_speed);

        if (_junit_filename) |filename| {
            testExportJunitResult(filename);
        }

        testRunAll(filter);
    }
}

fn newFrame() void {
    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "CoreUI new frame");
    defer update_zone_ctx.End();
    backend.newFrame();
}

fn afterAll() void {
    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "CoreUI after all");
    defer update_zone_ctx.End();
    if (_backed_initialised) {
        _te_engine.postSwap();
    }
}

fn showDemoWindow() void {
    if (!isCoreUIActive()) return;
    zgui.showDemoWindow(null);
    zgui.plot.showDemoWindow(null);
}

fn showMetricsWindow() void {
    if (!isCoreUIActive()) return;
    zgui.showMetricsWindow(null);
}

fn isCoreUIActive() bool {
    return _backed_initialised;
}

// next shit

fn toggleButton(label: [:0]const u8, toggled: *bool) bool {
    const style = zgui.getStyle();

    const toggled_initial = toggled.*;

    if (toggled_initial) {
        zgui.pushStyleColor4f(.{ .idx = .button, .c = style.getColor(.button_active) });
    }
    defer if (toggled_initial) zgui.popStyleColor(.{});

    if (zgui.button(label, .{})) {
        toggled.* = !toggled.*;
        return true;
    }
    return false;
}

fn toggleMenuItem(label: [:0]const u8, toggled: *bool) bool {
    const style = zgui.getStyle();

    const toggled_initial = toggled.*;

    if (toggled_initial) {
        zgui.pushStyleColor4f(.{ .idx = .button, .c = style.getColor(.button_active) });
    }
    defer if (toggled_initial) zgui.popStyleColor(.{});

    var f = false;
    if (zgui.menuItemPtr(label, .{ .selected = &f })) {
        toggled.* = !toggled.*;
        return true;
    }
    return false;
}

fn dragDouble(label: [:0]const u8, args: public.DragScalarGen(f64)) bool {
    return zgui.dragScalar(
        label,
        f64,
        .{
            .v = args.v,
            .speed = args.speed,
            .min = args.min,
            .max = args.max,
            .cfmt = args.cfmt,
            .flags = .{
                .always_clamp = args.flags.always_clamp,
                .logarithmic = args.flags.logarithmic,
                .no_round_to_format = args.flags.no_round_to_format,
                .no_input = args.flags.no_input,
            },
        },
    );
}

fn dragI32(label: [:0]const u8, args: public.DragScalarGen(i32)) bool {
    return zgui.dragScalar(
        label,
        i32,
        .{
            .v = args.v,
            .speed = args.speed,
            .min = args.min,
            .max = args.max,
            .cfmt = "%d",
            .flags = .{
                .always_clamp = args.flags.always_clamp,
                .logarithmic = args.flags.logarithmic,
                .no_round_to_format = args.flags.no_round_to_format,
                .no_input = args.flags.no_input,
            },
        },
    );
}

fn dragU32(label: [:0]const u8, args: public.DragScalarGen(u32)) bool {
    return zgui.dragScalar(
        label,
        u32,
        .{
            .v = args.v,
            .speed = args.speed,
            .min = args.min,
            .max = args.max,
            .cfmt = "%d",
            .flags = .{
                .always_clamp = args.flags.always_clamp,
                .logarithmic = args.flags.logarithmic,
                .no_round_to_format = args.flags.no_round_to_format,
                .no_input = args.flags.no_input,
            },
        },
    );
}

fn dragI64(label: [:0]const u8, args: public.DragScalarGen(i64)) bool {
    return zgui.dragScalar(
        label,
        i64,
        .{
            .v = args.v,
            .speed = args.speed,
            .min = args.min,
            .max = args.max,
            .cfmt = "%lld",
            .flags = .{
                .always_clamp = args.flags.always_clamp,
                .logarithmic = args.flags.logarithmic,
                .no_round_to_format = args.flags.no_round_to_format,
                .no_input = args.flags.no_input,
            },
        },
    );
}

fn dragU64(label: [:0]const u8, args: public.DragScalarGen(u64)) bool {
    return zgui.dragScalar(
        label,
        u64,
        .{
            .v = args.v,
            .speed = args.speed,
            .min = args.min,
            .max = args.max,
            .cfmt = "%llu",
            .flags = .{
                .always_clamp = args.flags.always_clamp,
                .logarithmic = args.flags.logarithmic,
                .no_round_to_format = args.flags.no_round_to_format,
                .no_input = args.flags.no_input,
            },
        },
    );
}

fn combo(label: [:0]const u8, args: public.ComboArgs) bool {
    return zgui.combo(label, .{
        .current_item = args.current_item,
        .items_separated_by_zeros = args.items_separated_by_zeros,
        .popup_max_height_in_items = args.popup_max_height_in_items,
    });
}

fn inputI32(label: [:0]const u8, args: public.InputScalarGen(i32)) bool {
    const flags = zgui.InputTextFlags{
        .chars_decimal = args.flags.chars_decimal,
        .chars_hexadecimal = args.flags.chars_hexadecimal,
        .chars_uppercase = args.flags.chars_uppercase,
        .chars_no_blank = args.flags.chars_no_blank,
        .auto_select_all = args.flags.auto_select_all,
        .enter_returns_true = args.flags.enter_returns_true,
        .callback_completion = args.flags.callback_completion,
        .callback_history = args.flags.callback_history,
        .callback_always = args.flags.callback_always,
        .callback_char_filter = args.flags.callback_char_filter,
        .allow_tab_input = args.flags.allow_tab_input,
        .ctrl_enter_for_new_line = args.flags.ctrl_enter_for_new_line,
        .no_horizontal_scroll = args.flags.no_horizontal_scroll,
        .always_overwrite = args.flags.always_overwrite,
        .read_only = args.flags.read_only,
        .password = args.flags.password,
        .no_undo_redo = args.flags.no_undo_redo,
        .chars_scientific = args.flags.chars_scientific,
        .callback_resize = args.flags.callback_resize,
        .callback_edit = args.flags.callback_edit,
    };
    return zgui.inputScalar(label, i32, .{
        .v = args.v,
        .step = args.step,
        .step_fast = args.step_fast,
        .cfmt = args.cfmt,
        .flags = flags,
    });
}
fn inputU32(label: [:0]const u8, args: public.InputScalarGen(u32)) bool {
    const flags = zgui.InputTextFlags{
        .chars_decimal = args.flags.chars_decimal,
        .chars_hexadecimal = args.flags.chars_hexadecimal,
        .chars_uppercase = args.flags.chars_uppercase,
        .chars_no_blank = args.flags.chars_no_blank,
        .auto_select_all = args.flags.auto_select_all,
        .enter_returns_true = args.flags.enter_returns_true,
        .callback_completion = args.flags.callback_completion,
        .callback_history = args.flags.callback_history,
        .callback_always = args.flags.callback_always,
        .callback_char_filter = args.flags.callback_char_filter,
        .allow_tab_input = args.flags.allow_tab_input,
        .ctrl_enter_for_new_line = args.flags.ctrl_enter_for_new_line,
        .no_horizontal_scroll = args.flags.no_horizontal_scroll,
        .always_overwrite = args.flags.always_overwrite,
        .read_only = args.flags.read_only,
        .password = args.flags.password,
        .no_undo_redo = args.flags.no_undo_redo,
        .chars_scientific = args.flags.chars_scientific,
        .callback_resize = args.flags.callback_resize,
        .callback_edit = args.flags.callback_edit,
    };
    return zgui.inputScalar(label, u32, .{
        .v = args.v,
        .step = args.step,
        .step_fast = args.step_fast,
        .cfmt = args.cfmt,
        .flags = flags,
    });
}
fn inputI64(label: [:0]const u8, args: public.InputScalarGen(i64)) bool {
    const flags = zgui.InputTextFlags{
        .chars_decimal = args.flags.chars_decimal,
        .chars_hexadecimal = args.flags.chars_hexadecimal,
        .chars_uppercase = args.flags.chars_uppercase,
        .chars_no_blank = args.flags.chars_no_blank,
        .auto_select_all = args.flags.auto_select_all,
        .enter_returns_true = args.flags.enter_returns_true,
        .callback_completion = args.flags.callback_completion,
        .callback_history = args.flags.callback_history,
        .callback_always = args.flags.callback_always,
        .callback_char_filter = args.flags.callback_char_filter,
        .allow_tab_input = args.flags.allow_tab_input,
        .ctrl_enter_for_new_line = args.flags.ctrl_enter_for_new_line,
        .no_horizontal_scroll = args.flags.no_horizontal_scroll,
        .always_overwrite = args.flags.always_overwrite,
        .read_only = args.flags.read_only,
        .password = args.flags.password,
        .no_undo_redo = args.flags.no_undo_redo,
        .chars_scientific = args.flags.chars_scientific,
        .callback_resize = args.flags.callback_resize,
        .callback_edit = args.flags.callback_edit,
    };
    return zgui.inputScalar(label, i64, .{
        .v = args.v,
        .step = args.step,
        .step_fast = args.step_fast,
        .cfmt = args.cfmt,
        .flags = flags,
    });
}
fn inputU64(label: [:0]const u8, args: public.InputScalarGen(u64)) bool {
    const flags = zgui.InputTextFlags{
        .chars_decimal = args.flags.chars_decimal,
        .chars_hexadecimal = args.flags.chars_hexadecimal,
        .chars_uppercase = args.flags.chars_uppercase,
        .chars_no_blank = args.flags.chars_no_blank,
        .auto_select_all = args.flags.auto_select_all,
        .enter_returns_true = args.flags.enter_returns_true,
        .callback_completion = args.flags.callback_completion,
        .callback_history = args.flags.callback_history,
        .callback_always = args.flags.callback_always,
        .callback_char_filter = args.flags.callback_char_filter,
        .allow_tab_input = args.flags.allow_tab_input,
        .ctrl_enter_for_new_line = args.flags.ctrl_enter_for_new_line,
        .no_horizontal_scroll = args.flags.no_horizontal_scroll,
        .always_overwrite = args.flags.always_overwrite,
        .read_only = args.flags.read_only,
        .password = args.flags.password,
        .no_undo_redo = args.flags.no_undo_redo,
        .chars_scientific = args.flags.chars_scientific,
        .callback_resize = args.flags.callback_resize,
        .callback_edit = args.flags.callback_edit,
    };
    return zgui.inputScalar(label, u64, .{
        .v = args.v,
        .step = args.step,
        .step_fast = args.step_fast,
        .cfmt = args.cfmt,
        .flags = flags,
    });
}

fn removeFromSelection(db: cdb.DbId, selection: cdb.ObjId, obj: cdb.ObjId) !void {
    const w = cdb.writeObj(selection).?;
    try public.ObjSelection.removeFromRefSet(db, w, .Selection, obj);
    try cdb.writeCommit(w);
}

fn handleSelection(allocator: std.mem.Allocator, selection: *public.Selection, obj: cetech1.coreui.SelectedObj, multiselect_enabled: bool) !void {
    _ = allocator;

    if (multiselect_enabled and isKeyDown(.mod_ctrl)) {
        if (selection.isSelected(obj)) {
            selection.remove(&.{obj});
        } else {
            try selection.add(&.{obj});
        }
    } else {
        try selection.set(&.{obj});
    }
}

pub fn registerAllTests() !void {
    const impls = try apidb.getImpl(_allocator, public.RegisterTestsI);
    defer _allocator.free(impls);
    for (impls) |iface| {
        try iface.register_tests();
    }
}

fn plotLineF64(label_id: [:0]const u8, args: public.PlotLineGen(f64)) void {
    zgui.plot.plotLine(label_id, f64, .{
        .xv = args.xv,
        .yv = args.yv,
        .flags = .{
            .segments = args.flags.segments,
            .loop = args.flags.loop,
            .skip_nan = args.flags.skip_nan,
            .no_clip = args.flags.no_clip,
            .shaded = args.flags.shaded,
        },
        .offset = args.offset,
        .stride = args.stride,
    });
}

fn plotLineValuesF64(label_id: [:0]const u8, args: public.PlotLineValuesGen(f64)) void {
    zgui.plot.plotLineValues(label_id, f64, .{
        .v = args.v,
        .xscale = args.xscale,
        .xstart = args.xstart,
        .flags = .{
            .segments = args.flags.segments,
            .loop = args.flags.loop,
            .skip_nan = args.flags.skip_nan,
            .no_clip = args.flags.no_clip,
            .shaded = args.flags.shaded,
        },
        .offset = args.offset,
        .stride = args.stride,
    });
}

// const cdb_tests = @import("cdb_test.zig");

// test "coreui: should do basic operatino with selection" {
//     try cdb_tests.testInit();
//     defer cdb_tests.testDeinit();

//     try registerToApi();

//     const db = try cdb.createDb("test");
//     defer cdb.destroyDb(db);

//     const asset_type_idx = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);
//     _ = asset_type_idx;

//     const obj1 = try cetech1.assetdb.FooAsset.createObject(db);
//     defer cetech1.assetdb.FooAsset.destroyObject(db, obj1);

//     const obj2 = try cetech1.assetdb.FooAsset.createObject(db);
//     defer cetech1.assetdb.FooAsset.destroyObject(db, obj2);

//     const obj3 = try cetech1.assetdb.FooAsset.createObject(db);
//     defer cetech1.assetdb.FooAsset.destroyObject(db, obj3);

//     const obj4 = try cetech1.assetdb.FooAsset.createObject(db);
//     defer cetech1.assetdb.FooAsset.destroyObject(db, obj4);

//     const selection = try cetech1.coreui.ObjSelection.createObject(db);
//     defer cetech1.assetdb.FooAsset.destroyObject(db, selection);

//     try api.addToSelection(db, selection, obj1);
//     try api.addToSelection(db, selection, obj2);
//     try api.addToSelection(db, selection, obj3);

//     // count
//     {
//         const count = api.selectedCount(std.testing.allocator, db, selection);
//         try std.testing.expectEqual(3, count);
//     }

//     // is selected
//     {
//         try std.testing.expect(api.isSelected(db, selection, obj1));
//         try std.testing.expect(api.isSelected(db, selection, obj2));
//         try std.testing.expect(api.isSelected(db, selection, obj3));

//         try std.testing.expect(!api.isSelected(db, selection, obj4));
//     }

//     // Get selected
//     {
//         const selected = api.getSelected(std.testing.allocator, db, selection);
//         try std.testing.expect(selected != null);
//         defer std.testing.allocator.free(selected.?);
//         try std.testing.expectEqualSlices(cdb.ObjId, &.{ obj1, obj2, obj3 }, selected.?);
//     }

//     // Set selection
//     {
//         try api.setSelection(std.testing.allocator, db, selection, obj1);

//         const selected = api.getSelected(std.testing.allocator, db, selection);
//         try std.testing.expect(selected != null);
//         defer std.testing.allocator.free(selected.?);
//         try std.testing.expectEqualSlices(cdb.ObjId, &.{obj1}, selected.?);
//     }

//     // Clear selection
//     {
//         try api.clearSelection(std.testing.allocator, db, selection);

//         const selected = api.getSelected(std.testing.allocator, db, selection);
//         try std.testing.expect(selected != null);
//         defer std.testing.allocator.free(selected.?);
//         try std.testing.expectEqualSlices(cdb.ObjId, &.{}, selected.?);
//     }
// }

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(public.DrawCmd) == @sizeOf(zgui.DrawCmd));
    std.debug.assert(@sizeOf(public.DrawFlags) == @sizeOf(zgui.DrawFlags));
    std.debug.assert(@sizeOf(public.DrawVert) == @sizeOf(zgui.DrawVert));
    std.debug.assert((@sizeOf(public.ListClipper) - @sizeOf(*public.ListClipper.VTable)) == @sizeOf(zgui.ListClipper));
    std.debug.assert(@sizeOf(public.TableColumnSortSpecs) == @sizeOf(zgui.TableColumnSortSpecs));
    std.debug.assert(@sizeOf(public.TableSortSpecs) == @sizeOf(zgui.TableSortSpecs));
    std.debug.assert(@sizeOf(public.Style) == @sizeOf(zgui.Style));
    std.debug.assert(@sizeOf(public.Payload) == @sizeOf(zgui.Payload));
}
