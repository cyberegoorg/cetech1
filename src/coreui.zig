const std = @import("std");

const c = @import("c.zig").c;

const cetech1_options = @import("cetech1_options");

const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zguite = zgui.te;
const znfde = @import("znfde");
const zf = @import("zf");
const tempalloc = @import("tempalloc.zig");
const kernel = @import("kernel.zig");
const gpu = @import("gpu.zig");

const zbgfx = @import("zbgfx");
const backend = @import("backend_glfw_bgfx.zig");

const apidb = @import("apidb.zig");

const profiler = @import("profiler.zig");
const assetdb = @import("assetdb.zig");

const cetech1 = @import("cetech1");
const public = cetech1.coreui;
const Icons = public.CoreIcons;
const gfx = cetech1.gfx;

const log = std.log.scoped(module_name);

const _main_font = @embedFile("embed/fonts/Roboto-Medium.ttf");
const _fa_solid_font = @embedFile("embed/fonts/fa-solid-900.ttf");
const _fa_regular_font = @embedFile("embed/fonts/fa-regular-400.ttf");

const module_name = .coreui;

const DEFAULT_IMGUI_INI = @embedFile("embed/imgui.ini");

var _allocator: std.mem.Allocator = undefined;
var _backed_initialised = false;
var _te_engine: *zguite.TestEngine = undefined;
var _te_show_window: bool = false;
var _enabled_ui = false;

var _junit_filename_buff: [1024:0]u8 = undefined;
var _junit_filename: ?[:0]const u8 = null;
var _scale_factor: ?f32 = null;
var _new_scale_factor: ?f32 = null;

const KernelTask = struct {
    pub fn update(kernel_tick: u64, dt: f32) !void {
        const tmp = try tempalloc.api.create();
        defer tempalloc.api.destroy(tmp);
        const ctx = kernel.api.getGpuCtx();
        if (_enabled_ui and ctx != null) {
            try coreUI(tmp, kernel_tick, dt);
        }
    }
};

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.PreStore,
    "CoreUI",
    &[_]cetech1.strid.StrId64{},
    KernelTask.update,
);

const _kernel_hook_i = cetech1.kernel.KernelLoopHookI.implement(struct {
    pub fn beginLoop() !void {
        const ctx = kernel.api.getGpuCtx();

        if (!_enabled_ui and ctx != null) {
            try enableWithWindow(ctx.?);
            _enabled_ui = true;
        }

        if (_enabled_ui and ctx != null) {
            var size = [2]i32{ 0, 0 };

            if (gpu.api.getWindow(ctx.?)) |w| {
                var true_window: *zglfw.Window = @ptrCast(w);
                size = true_window.getFramebufferSize();
            }

            newFrame(@intCast(size[0]), @intCast(size[1]));
        }
    }

    pub fn endLoop() !void {
        afterAll();
    }
});

var create_types_i = cetech1.cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: *cetech1.cdb.Db) !void {
        var db = cetech1.cdb.CdbDb.fromDbT(db_, &cdb_private.api);

        // Obj selections
        _ = try db.addType(
            public.ObjSelection.name,
            &[_]cetech1.cdb.PropDef{
                .{ .prop_idx = public.ObjSelection.propIdx(.Selection), .name = "selection", .type = cetech1.cdb.PropType.REFERENCE_SET },
            },
        );
        //
    }
});

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _backed_initialised = false;
    _te_engine = undefined;
    _te_show_window = false;
    _enabled_ui = false;
    _junit_filename = null;

    //TODO: TEMP SHIT
    _ = std.fs.cwd().statFile("imgui.ini") catch |err| {
        if (err == error.FileNotFound) {
            const f = try std.fs.cwd().createFile("imgui.ini", .{});
            defer f.close();
            try f.writeAll(DEFAULT_IMGUI_INI);
        }
    };
    //

    zgui.init(_allocator);
    zgui.plot.init();

    if (cetech1_options.enable_nfd) try znfde.init();

    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelLoopHookI, &_kernel_hook_i, true);
    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, true);
}

pub fn deinit() void {
    if (_backed_initialised) {
        _te_engine.tryAbortEngine();
        _te_engine.stop();
    }

    zgui.plot.deinit();
    if (_backed_initialised) backend.deinit();
    zgui.deinit();

    if (cetech1_options.enable_nfd) znfde.deinit();
    apidb.api.implOrRemove(module_name, cetech1.kernel.KernelLoopHookI, &_kernel_hook_i, false) catch undefined;
}

pub var api = public.CoreUIApi{
    .showDemoWindow = showDemoWindow,
    .begin = @ptrCast(&zgui.begin),
    .end = @ptrCast(&zgui.end),
    .beginPopup = @ptrCast(&zgui.beginPopup),
    .pushStyleColor4f = @ptrCast(&zgui.pushStyleColor4f),
    .popStyleColor = @ptrCast(&zgui.popStyleColor),
    .tableSetBgColor = @ptrCast(&zgui.tableSetBgColor),
    .colorConvertFloat4ToU32 = @ptrCast(&zgui.colorConvertFloat4ToU32),
    .text = @ptrCast(&zgui.textUnformatted),
    .textColored = @ptrCast(&zgui.textUnformattedColored),
    .colorPicker4 = @ptrCast(&zgui.colorPicker4),
    .colorEdit4 = @ptrCast(&zgui.colorEdit4),
    .beginMainMenuBar = @ptrCast(&zgui.beginMainMenuBar),
    .endMainMenuBar = @ptrCast(&zgui.endMainMenuBar),
    .beginMenuBar = @ptrCast(&zgui.beginMenuBar),
    .endMenuBar = @ptrCast(&zgui.endMenuBar),
    .beginMenu = beginMenu,
    .endMenu = @ptrCast(&zgui.endMenu),
    .menuItem = menuItem,
    .menuItemPtr = menuItemPtr,
    .beginChild = @ptrCast(&zgui.beginChild),
    .endChild = @ptrCast(&zgui.endChild),
    .separator = @ptrCast(&zgui.separator),
    .separatorText = @ptrCast(&zgui.separatorText),
    .setNextItemWidth = @ptrCast(&zgui.setNextItemWidth),
    .setNextWindowSize = @ptrCast(&zgui.setNextWindowSize),
    .pushPtrId = @ptrCast(&zgui.pushPtrId),
    .pushIntId = @ptrCast(&zgui.pushIntId),
    .pushObjUUID = pushObjUUID,
    .popId = @ptrCast(&zgui.popId),
    .treeNode = @ptrCast(&zgui.treeNode),
    .treeNodeFlags = @ptrCast(&zgui.treeNodeFlags),
    .treePop = @ptrCast(&zgui.treePop),
    .beginTooltip = @ptrCast(&zgui.beginTooltip),
    .endTooltip = @ptrCast(&zgui.endTooltip),
    .isItemHovered = @ptrCast(&zgui.isItemHovered),
    .setClipboardText = @ptrCast(&zgui.setClipboardText),
    .beginPopupContextItem = @ptrCast(&zgui.beginPopupContextItem),
    .beginPopupModal = @ptrCast(&zgui.beginPopupModal),
    .openPopup = @ptrCast(&zgui.openPopup),
    .endPopup = @ptrCast(&zgui.endPopup),
    .closeCurrentPopup = @ptrCast(&zgui.closeCurrentPopup),
    .isItemClicked = @ptrCast(&zgui.isItemClicked),
    .isItemActivated = @ptrCast(&zgui.isItemActivated),
    .isWindowFocused = @ptrCast(&zgui.isWindowFocused),
    .beginTable = @ptrCast(&zgui.beginTable),
    .endTable = @ptrCast(&zgui.endTable),
    .tableSetupColumn = @ptrCast(&zgui.tableSetupColumn),
    .tableHeadersRow = @ptrCast(&zgui.tableHeadersRow),
    .tableNextColumn = @ptrCast(&zgui.tableNextColumn),
    .tableNextRow = @ptrCast(&zgui.tableNextRow),
    .tableSetupScrollFreeze = @ptrCast(&zgui.tableSetupScrollFreeze),
    .getItemRectMax = @ptrCast(&zgui.getItemRectMax),
    .getItemRectMin = @ptrCast(&zgui.getItemRectMin),
    .getCursorPosX = @ptrCast(&zgui.getCursorPosX),
    .calcTextSize = @ptrCast(&zgui.calcTextSize),
    .getWindowPos = @ptrCast(&zgui.getWindowPos),
    .getWindowContentRegionMax = @ptrCast(&zgui.getWindowContentRegionMax),
    .getContentRegionMax = @ptrCast(&zgui.getContentRegionMax),
    .getContentRegionAvail = @ptrCast(&zgui.getContentRegionAvail),
    .setCursorPosX = @ptrCast(&zgui.setCursorPosX),
    .getStyle = @ptrCast(&zgui.getStyle),
    .pushStyleVar2f = @ptrCast(&zgui.pushStyleVar2f),
    .pushStyleVar1f = @ptrCast(&zgui.pushStyleVar1f),
    .popStyleVar = @ptrCast(&zgui.popStyleVar),
    .isKeyDown = @ptrCast(&zgui.isKeyDown),
    .labelText = labelText,
    .sameLine = @ptrCast(&zgui.sameLine),
    .button = @ptrCast(&zgui.button),
    .smallButton = @ptrCast(&zgui.smallButton),
    .invisibleButton = @ptrCast(&zgui.invisibleButton),
    .inputText = @ptrCast(&zgui.inputText),
    .inputF32 = @ptrCast(&zgui.inputFloat),
    .inputF64 = @ptrCast(&zgui.inputDouble),
    .inputI32 = inputI32,
    .inputU32 = inputU32,
    .inputI64 = inputI64,
    .inputU64 = inputU64,
    .dragF32 = @ptrCast(&zgui.dragFloat),
    .dragF64 = dragDouble,
    .dragI32 = dragI32,
    .dragU32 = dragU32,
    .dragU64 = dragU64,
    .dragI64 = dragI64,
    .checkbox = @ptrCast(&zgui.checkbox),
    .alignTextToFramePadding = @ptrCast(&zgui.alignTextToFramePadding),
    .isItemToggledOpen = @ptrCast(&zgui.isItemToggledOpen),
    .dummy = @ptrCast(&zgui.dummy),
    .spacing = @ptrCast(&zgui.spacing),
    .getScrollX = @ptrCast(&zgui.getScrollX),
    .getScrollY = @ptrCast(&zgui.getScrollY),
    .getScrollMaxX = @ptrCast(&zgui.getScrollMaxX),
    .getScrollMaxY = @ptrCast(&zgui.getScrollMaxY),
    .setScrollHereY = @ptrCast(&zgui.setScrollHereY),
    .setScrollHereX = @ptrCast(&zgui.setScrollHereX),
    .supportFileDialog = supportFileDialog,
    .openFileDialog = openFileDialog,
    .saveFileDialog = saveFileDialog,
    .openFolderDialog = openFolderDialog,
    .uiFilterPass = uiFilterPass,
    .uiFilter = uiFilter,
    .beginDragDropSource = @ptrCast(&zgui.beginDragDropSource),
    .setDragDropPayload = @ptrCast(&zgui.setDragDropPayload),
    .endDragDropSource = @ptrCast(&zgui.endDragDropSource),
    .beginDragDropTarget = @ptrCast(&zgui.beginDragDropTarget),
    .acceptDragDropPayload = @ptrCast(&zgui.acceptDragDropPayload),
    .endDragDropTarget = @ptrCast(&zgui.endDragDropTarget),
    .getDragDropPayload = @ptrCast(&zgui.getDragDropPayload),
    .isMouseDoubleClicked = @ptrCast(&zgui.isMouseDoubleClicked),
    .isMouseDown = @ptrCast(&zgui.isMouseDown),
    .isMouseClicked = @ptrCast(&zgui.isMouseClicked),
    .isSelected = isSelected,
    .addToSelection = addToSelection,
    .setSelection = setSelection,
    .selectedCount = selectedCount,
    .getFirstSelected = getFirstSelected,
    .getSelected = getSelected,
    .handleSelection = handleSelection,
    .removeFromSelection = removeFromSelection,
    .clearSelection = clearSelection,
    .pushPropName = pushPropName,
    .getFontSize = @ptrCast(&zgui.getFontSize),
    .showTestingWindow = showTestingWindow,
    .showExternalCredits = showExternalCredits,
    .showAuthors = showAuthors,
    .registerTestFn = registerTestFn,
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
    .setScaleFactor = setScaleFactor,
    .getScaleFactor = getScaleFactor,
    .mainDockSpace = mainDockSpace,
    .image = image,
};

const BgfxImage = struct {
    handle: gfx.TextureHandle,
    flags: u8,
    mip: u8,

    pub fn toTextureIdent(self: *const BgfxImage) zgui.TextureIdent {
        return std.mem.bytesToValue(zgui.TextureIdent, std.mem.asBytes(self));
    }
};

fn image(texture: gfx.TextureHandle, args: public.Image) void {
    const tt = BgfxImage{
        .handle = texture,
        .flags = args.flags,
        .mip = args.mip,
    };

    zgui.image(tt.toTextureIdent(), .{
        .w = args.w,
        .h = args.h,
        .uv0 = args.uv0,
        .uv1 = args.uv1,
        .tint_col = args.tint_col,
        .border_col = args.border_col,
    });
}

fn mainDockSpace(flags: public.DockNodeFlags) zgui.Ident {
    const f: *zgui.DockNodeFlags = @constCast(@ptrCast(&flags));
    return zgui.DockSpaceOverViewport(zgui.getMainViewport(), f.*);
}

fn setScaleFactor(scale_factor: f32) void {
    _new_scale_factor = scale_factor;
}

fn getScaleFactor() f32 {
    return _scale_factor.?;
}

fn supportFileDialog() bool {
    return cetech1_options.enable_nfd;
}

fn openFileDialog(allocator: std.mem.Allocator, filter: ?[]const public.FilterItem, default_path: ?[:0]const u8) !?[:0]const u8 {
    if (cetech1_options.enable_nfd) {
        return znfde.openFileDialog(allocator, @ptrCast(filter), default_path);
    }
    return null;
}

fn saveFileDialog(allocator: std.mem.Allocator, filter: ?[]const public.FilterItem, default_path: ?[:0]const u8, default_name: ?[:0]const u8) !?[:0]const u8 {
    if (cetech1_options.enable_nfd) {
        return znfde.saveFileDialog(allocator, @ptrCast(filter), default_path, default_name);
    }

    return null;
}

fn openFolderDialog(allocator: std.mem.Allocator, default_path: ?[:0]const u8) !?[:0]const u8 {
    if (cetech1_options.enable_nfd) {
        return znfde.openFolderDialog(allocator, default_path);
    }
    return null;
}

fn pushPropName(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) void {
    const props_def = db.getTypePropDef(obj.type_idx).?;
    zgui.pushStrIdZ(props_def[prop_idx].name);
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

fn reloadTests() void {
    registerAllTests();
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
        api.setNextWindowSize(.{ .w = 600, .h = 600, .cond = .first_use_ever });
        if (api.begin(
            public.Icons.Externals ++ "  " ++ "External credits###ExternalCredits",
            .{ .popen = show, .flags = .{ .no_docking = true } },
        )) {
            defer api.end();

            _ = zgui.inputTextMultiline("###Credits", .{
                .buf = @constCast(kernel.api.getExternalsCredit()),
                .flags = .{ .read_only = true },
                .w = -1,
                .h = -1,
            });
        }
    }
}

fn showAuthors(show: *bool) void {
    if (show.*) {
        api.setNextWindowSize(.{ .w = 600, .h = 600, .cond = .first_use_ever });
        if (api.begin(
            public.Icons.Authors ++ "  " ++ "Authors###Authors",
            .{ .popen = show, .flags = .{ .no_docking = true } },
        )) {
            defer api.end();

            _ = zgui.inputTextMultiline("###Authors", .{
                .buf = @constCast(kernel.api.getAuthors()),
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

fn clearSelection(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    selection: cetech1.cdb.ObjId,
) !void {
    const r = db.readObj(selection).?;

    const w = db.writeObj(selection).?;

    // TODO: clear to cdb
    if (public.ObjSelection.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |ref| {
            try public.ObjSelection.removeFromRefSet(db, w, .Selection, ref);
        }
    }

    try db.writeCommit(w);
}

fn pushObjUUID(obj: cetech1.cdb.ObjId) void {
    const uuid = assetdb.api.getOrCreateUuid(obj) catch undefined;
    var buff: [128]u8 = undefined;
    const uuid_str = std.fmt.bufPrintZ(&buff, "{s}", .{uuid}) catch undefined;

    zgui.pushStrIdZ(uuid_str);
}

fn uiFilterPass(allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64 {
    // Collect token for filter
    var tokens = std.ArrayList([]const u8).init(allocator);
    defer tokens.deinit();

    var split = std.mem.split(u8, filter, " ");
    const first = split.first();
    var it: ?[]const u8 = first;
    while (it) |word| : (it = split.next()) {
        if (word.len == 0) continue;
        tokens.append(word) catch return null;
    }
    //return 0;

    return zf.rank(value, tokens.items, false, !is_path);
}

fn uiFilter(buf: []u8, filter: ?[:0]const u8) ?[:0]const u8 {
    api.text(Icons.FA_MAGNIFYING_GLASS);
    api.sameLine(.{});

    var input_buff: [128:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&input_buff, "{s}", .{filter orelse ""}) catch return null;

    api.setNextItemWidth(-std.math.floatMin(f32));
    if (api.inputText("###filter", .{
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

pub fn labelText(label: [:0]const u8, text: [:0]const u8) void {
    zgui.labelText(label, "{s}", .{text});
}

pub fn coreUI(tmp_allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) !void {
    _ = kernel_tick;
    _ = dt;

    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "CoreUI");
    defer update_zone_ctx.End();

    var it = apidb.api.getFirstImpl(cetech1.coreui.CoreUII);
    while (it) |node| : (it = node.next) {
        const iface = cetech1.apidb.ApiDbAPI.toInterface(cetech1.coreui.CoreUII, node);
        iface.*.ui(&tmp_allocator);
    }

    backend.draw();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.CoreUIApi, &api);
    try apidb.api.implOrRemove(.cdb_types, cetech1.cdb.CreateTypesI, &create_types_i, true);
}

pub fn initFonts(font_size: f32, scale_factor: f32) void {
    const sized_pixel = std.math.floor(font_size * scale_factor);

    // Load main font
    var main_cfg = zgui.FontConfig.init();
    main_cfg.font_data_owned_by_atlas = false;
    _ = zgui.io.addFontFromMemoryWithConfig(_main_font, sized_pixel, main_cfg, null);

    // Merge Font Awesome
    var fa_cfg = zgui.FontConfig.init();
    fa_cfg.font_data_owned_by_atlas = false;
    fa_cfg.merge_mode = true;
    _ = zgui.io.addFontFromMemoryWithConfig(
        if (false) _fa_regular_font else _fa_solid_font,
        sized_pixel,
        fa_cfg,
        &[_]u16{ c.ICON_MIN_FA, c.ICON_MAX_FA, 0 },
    );

    zgui.getStyle().scaleAllSizes(scale_factor);
}

pub fn enableWithWindow(gpuctx: *cetech1.gpu.GpuContext) !void {
    _scale_factor = _scale_factor orelse scale_factor: {
        const scale = gpu.api.getContentScale(gpuctx);
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.getStyle().frame_rounding = 8;

    zgui.io.setConfigFlags(zgui.ConfigFlags{
        .nav_enable_keyboard = true,
        .nav_enable_gamepad = true,
        .nav_enable_set_mouse_pos = true,
        .dock_enable = true,
    });
    zgui.io.setConfigWindowsMoveFromTitleBarOnly(true);

    _backed_initialised = true;

    initFonts(16, _scale_factor.?);
    backend.init(gpu.api.getWindow(gpuctx));

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

    registerAllTests();

    if (test_ui) {
        const filter = try std.fmt.allocPrintZ(_allocator, "{s}", .{test_ui_filter});
        defer _allocator.free(filter);
        testSetRunSpeed(test_ui_speed);

        if (_junit_filename) |filename| {
            testExportJunitResult(filename);
        }

        testRunAll(filter);
    }
}

fn newFrame(fb_width: u32, fb_height: u32) void {
    if (_new_scale_factor) |nsf| {
        initFonts(16, nsf);
        _scale_factor = nsf;
    }
    backend.newFrame(fb_width, fb_height);
}

fn afterAll() void {
    if (_backed_initialised) {
        _te_engine.postSwap();
    }
}

fn showDemoWindow() void {
    if (!isCoreUIActive()) return;
    zgui.showDemoWindow(null);
    zgui.plot.showDemoWindow(null);
}

fn isCoreUIActive() bool {
    return _backed_initialised;
}

// next shit

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

fn removeFromSelection(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const w = db.writeObj(selection).?;
    try public.ObjSelection.removeFromRefSet(db, w, .Selection, obj);
    try db.writeCommit(w);
}

fn handleSelection(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId, multiselect_enabled: bool) !void {
    if (multiselect_enabled and api.isKeyDown(.mod_super) or api.isKeyDown(.mod_ctrl)) {
        if (api.isSelected(db, selection, obj)) {
            try api.removeFromSelection(db, selection, obj);
        } else {
            try api.addToSelection(db, selection, obj);
        }
    } else {
        try api.setSelection(allocator, db, selection, obj);
    }
}

fn getSelected(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) ?[]const cetech1.cdb.ObjId {
    const r = db.readObj(selection) orelse return null;
    return public.ObjSelection.readRefSet(db, r, .Selection, allocator);
}

fn isSelected(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) bool {
    return public.ObjSelection.isInSet(db, db.readObj(selection).?, .Selection, obj);
}

fn addToSelection(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const w = db.writeObj(selection).?;

    try public.ObjSelection.addRefToSet(db, w, .Selection, &.{obj});
    try db.writeCommit(w);
}

fn setSelection(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const r = db.readObj(selection).?;

    const w = db.writeObj(selection).?;

    // TODO: clear to cdb
    if (public.ObjSelection.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |ref| {
            try public.ObjSelection.removeFromRefSet(db, w, .Selection, ref);
        }
    }
    try public.ObjSelection.addRefToSet(db, w, .Selection, &.{obj});

    try db.writeCommit(w);
}

fn selectedCount(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) u32 {
    const r = db.readObj(selection) orelse return 0;

    // TODO: count to cdb
    if (public.ObjSelection.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        return @truncate(set.len);
    }
    return 0;
}

fn getFirstSelected(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) cetech1.cdb.ObjId {
    const r = db.readObj(selection) orelse return .{};

    // TODO: count to cdb
    if (public.ObjSelection.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |s| {
            return s;
        }
    }
    return .{};
}

pub fn registerAllTests() void {
    var it = apidb.api.getFirstImpl(public.RegisterTestsI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.RegisterTestsI, node);
        iface.register_tests();
    }
}

const cdb_tests = @import("cdb_test.zig");
const cdb_private = @import("cdb.zig");

test "coreui: should do basic operatino with selection" {
    try cdb_tests.testInit();
    defer cdb_tests.testDeinit();

    try registerToApi();

    var db = try cdb_private.api.createDb("test");
    defer cdb_private.api.destroyDb(db);

    const asset_type_idx = try cetech1.cdb_types.addBigType(&db, "ct_foo_asset", null);
    _ = asset_type_idx;

    const obj1 = try cetech1.assetdb.FooAsset.createObject(&db);
    defer cetech1.assetdb.FooAsset.destroyObject(&db, obj1);

    const obj2 = try cetech1.assetdb.FooAsset.createObject(&db);
    defer cetech1.assetdb.FooAsset.destroyObject(&db, obj2);

    const obj3 = try cetech1.assetdb.FooAsset.createObject(&db);
    defer cetech1.assetdb.FooAsset.destroyObject(&db, obj3);

    const obj4 = try cetech1.assetdb.FooAsset.createObject(&db);
    defer cetech1.assetdb.FooAsset.destroyObject(&db, obj4);

    const selection = try cetech1.coreui.ObjSelection.createObject(&db);
    defer cetech1.assetdb.FooAsset.destroyObject(&db, selection);

    try api.addToSelection(&db, selection, obj1);
    try api.addToSelection(&db, selection, obj2);
    try api.addToSelection(&db, selection, obj3);

    // count
    {
        const count = api.selectedCount(std.testing.allocator, &db, selection);
        try std.testing.expectEqual(3, count);
    }

    // is selected
    {
        try std.testing.expect(api.isSelected(&db, selection, obj1));
        try std.testing.expect(api.isSelected(&db, selection, obj2));
        try std.testing.expect(api.isSelected(&db, selection, obj3));

        try std.testing.expect(!api.isSelected(&db, selection, obj4));
    }

    // Get selected
    {
        const selected = api.getSelected(std.testing.allocator, &db, selection);
        try std.testing.expect(selected != null);
        defer std.testing.allocator.free(selected.?);
        try std.testing.expectEqualSlices(cetech1.cdb.ObjId, &.{ obj1, obj2, obj3 }, selected.?);
    }

    // Set selection
    {
        try api.setSelection(std.testing.allocator, &db, selection, obj1);

        const selected = api.getSelected(std.testing.allocator, &db, selection);
        try std.testing.expect(selected != null);
        defer std.testing.allocator.free(selected.?);
        try std.testing.expectEqualSlices(cetech1.cdb.ObjId, &.{obj1}, selected.?);
    }

    // Clear selection
    {
        try api.clearSelection(std.testing.allocator, &db, selection);

        const selected = api.getSelected(std.testing.allocator, &db, selection);
        try std.testing.expect(selected != null);
        defer std.testing.allocator.free(selected.?);
        try std.testing.expectEqualSlices(cetech1.cdb.ObjId, &.{}, selected.?);
    }
}

// Assert C api == C api in zig.
comptime {}
