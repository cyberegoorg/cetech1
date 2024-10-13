const std = @import("std");

const cetech1_options = @import("cetech1_options");

const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zguite = zgui.te;
const znfde = @import("znfde");
const zf = @import("zf");
const tempalloc = @import("tempalloc.zig");
const kernel = @import("kernel.zig");
const gpu_private = @import("gpu.zig");
const cdb_private = @import("cdb.zig");

const node_editor = zgui.node_editor;

const backend = @import("backend_glfw_bgfx.zig");

const apidb = @import("apidb.zig");

const profiler = @import("profiler.zig");
const assetdb = @import("assetdb.zig");

const cetech1 = @import("cetech1");
const gpu = cetech1.gpu;
const cdb = cetech1.cdb;
const Icons = public.CoreIcons;
const ui_node_editor = cetech1.coreui_node_editor;

const public = cetech1.coreui;

const module_name = .coreui;
const log = std.log.scoped(module_name);

var _cdb = &cdb_private.api;

const _main_font = @embedFile("embed/fonts/Roboto-Medium.ttf");
const _fa_solid_font = @embedFile("embed/fonts/fa-solid-900.ttf");
const _fa_regular_font = @embedFile("embed/fonts/fa-regular-400.ttf");

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

// const KernelTask = struct {
//     pub fn update(kernel_tick: u64, dt: f32) !void {
//         const tmp = try tempalloc.api.create();
//         defer tempalloc.api.destroy(tmp);
//         const ctx = kernel.api.getGpuCtx();
//         if (_enabled_ui and ctx != null) {
//             try coreUI(tmp, kernel_tick, dt);
//         }
//     }
// };
// var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
//     cetech1.kernel.PreStore,
//     "CoreUI",
//     &[_]cetech1.strid.StrId64{},
//     KernelTask.update,
// );

const _kernel_hook_i = cetech1.kernel.KernelLoopHookI.implement(struct {
    pub fn beginLoop(kernel_tick: u64, dt: f32) !void {
        var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "Begin-loop CoreUI");
        defer update_zone_ctx.End();

        const ctx = kernel.api.getGpuCtx();
        _ = ctx; // autofix
        const window = kernel.api.getMainWindow();

        if (!_enabled_ui) {
            try enableWithWindow(window);
            _enabled_ui = true;
        }

        if (_enabled_ui) {
            var size = [2]i32{ 0, 0 };

            if (window) |w| {
                size = w.getFramebufferSize();
            }

            // if (_new_scale_factor) |nsf| {
            //     initFonts(16, nsf);
            //     _scale_factor = nsf;
            //     _new_scale_factor = null;
            //     return;
            // }

            newFrame(@intCast(size[0]), @intCast(size[1]));

            const tmp = try tempalloc.api.create();
            defer tempalloc.api.destroy(tmp);
            try coreUI(tmp, kernel_tick, dt);
        }
    }

    pub fn endLoop() !void {
        afterAll();
    }
});

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db; // autofix

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
    //try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, true);
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
    .showMetricsWindow = showMetricsWindow,
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
    .setCursorPosY = @ptrCast(&zgui.setCursorPosY),
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
    .combo = combo,
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

    .handleSelection = handleSelection,

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
    .getMousePos = @ptrCast(&zgui.getMousePos),
    .getMouseDragDelta = @ptrCast(&zgui.getMouseDragDelta),
    .setMouseCursor = @ptrCast(&zgui.setMouseCursor),
    .popItemWidth = @ptrCast(&zgui.popItemWidth),
    .pushItemWidth = @ptrCast(&zgui.pushItemWidth),
    .beginPlot = @ptrCast(&zgui.plot.beginPlot),
    .endPlot = @ptrCast(&zgui.plot.endPlot),
    .plotLineF64 = plotLineF64,
    .plotLineValuesF64 = plotLineValuesF64,
    .setupAxis = @ptrCast(&zgui.plot.setupAxis),
    .setupFinish = @ptrCast(&zgui.plot.setupFinish),
    .setupLegend = @ptrCast(&zgui.plot.setupLegend),

    .getCursorPos = @ptrCast(&zgui.getCursorPos),
    .getCursorScreenPos = @ptrCast(&zgui.getCursorScreenPos),
    .getWindowDrawList = getWindowDrawList,

    .isItemVisible = @ptrCast(&zgui.isItemVisible),
    .isRectVisible = @ptrCast(&zgui.isRectVisible),

    .beginDisabled = @ptrCast(&zgui.beginDisabled),
    .endDisabled = @ptrCast(&zgui.endDisabled),

    // Gizmo
    .gizmoSetRect = @ptrCast(&zgui.gizmo.setRect),
    .gizmoManipulate = @ptrCast(&zgui.gizmo.manipulate),
    .gizmoSetDrawList = gizmoSetDrawList,
};

pub fn gizmoSetDrawList(draw_list: ?public.DrawList) void {
    zgui.gizmo.setDrawList(if (draw_list) |dl| @ptrCast(dl.ptr) else null);
}

fn getWindowDrawList() public.DrawList {
    return public.DrawList{
        .ptr = zgui.getWindowDrawList(),
        .vtable = &drawlist_vtable,
    };
}

const node_editor_api = ui_node_editor.NodeEditorApi{
    .createEditor = createEditor,
    .destroyEditor = @ptrCast(&node_editor.EditorContext.destroy),
    .setCurrentEditor = @ptrCast(&node_editor.setCurrentEditor),
    .begin = @ptrCast(&node_editor.begin),
    .end = @ptrCast(&node_editor.end),
    .beginCreate = @ptrCast(&node_editor.beginCreate),
    .endCreate = @ptrCast(&node_editor.endCreate),
    .showBackgroundContextMenu = @ptrCast(&node_editor.showBackgroundContextMenu),
    .suspend_ = @ptrCast(&node_editor.suspend_),
    .resume_ = @ptrCast(&node_editor.resume_),
    .beginNode = @ptrCast(&node_editor.beginNode),
    .endNode = @ptrCast(&node_editor.endNode),
    .deleteNode = @ptrCast(&node_editor.deleteNode),
    .beginPin = @ptrCast(&node_editor.beginPin),
    .endPin = @ptrCast(&node_editor.endPin),
    .setNodePosition = @ptrCast(&node_editor.setNodePosition),
    .getNodePosition = @ptrCast(&node_editor.getNodePosition),
    .link = @ptrCast(&node_editor.link),
    .queryNewLink = @ptrCast(&node_editor.queryNewLink),
    .acceptNewItem = @ptrCast(&node_editor.acceptNewItem),
    .rejectNewItem = @ptrCast(&node_editor.rejectNewItem),

    .deleteLink = @ptrCast(&node_editor.deleteLink),
    .beginDelete = @ptrCast(&node_editor.beginDelete),
    .endDelete = @ptrCast(&node_editor.endDelete),
    .queryDeletedLink = @ptrCast(&node_editor.queryDeletedLink),
    .queryDeletedNode = @ptrCast(&node_editor.queryDeletedNode),
    .acceptDeletedItem = @ptrCast(&node_editor.acceptDeletedItem),
    .rejectDeletedItem = @ptrCast(&node_editor.rejectDeletedItem),

    .showNodeContextMenu = @ptrCast(&node_editor.showNodeContextMenu),
    .showLinkContextMenu = @ptrCast(&node_editor.showLinkContextMenu),
    .showPinContextMenu = @ptrCast(&node_editor.showPinContextMenu),

    .navigateToContent = @ptrCast(&node_editor.navigateToContent),
    .navigateToSelection = @ptrCast(&node_editor.navigateToSelection),
    .pinHadAnyLinks = @ptrCast(&node_editor.pinHadAnyLinks),
    .breakPinLinks = @ptrCast(&node_editor.breakPinLinks),

    .getStyleColorName = @ptrCast(&node_editor.getStyleColorName),
    .getStyle = @ptrCast(&node_editor.getStyle),
    .pushStyleColor = @ptrCast(&node_editor.pushStyleColor),
    .popStyleColor = @ptrCast(&node_editor.popStyleColor),
    .pushStyleVar1f = @ptrCast(&node_editor.pushStyleVar1f),
    .pushStyleVar2f = @ptrCast(&node_editor.pushStyleVar2f),
    .pushStyleVar4f = @ptrCast(&node_editor.pushStyleVar4f),
    .popStyleVar = @ptrCast(&node_editor.popStyleVar),

    .hasSelectionChanged = @ptrCast(&node_editor.hasSelectionChanged),
    .getSelectedObjectCount = @ptrCast(&node_editor.getSelectedObjectCount),
    .clearSelection = @ptrCast(&node_editor.clearSelection),
    .getSelectedNodes = @ptrCast(&node_editor.getSelectedNodes),
    .getSelectedLinks = @ptrCast(&node_editor.getSelectedLinks),
    .selectNode = @ptrCast(&node_editor.selectNode),
    .selectLink = @ptrCast(&node_editor.selectLink),
    .group = @ptrCast(&node_editor.group),
    .getNodeSize = @ptrCast(&node_editor.getNodeSize),
    .getHintForegroundDrawList = getHintForegroundDrawList,
    .getHintBackgroundDrawList = getHintBackgroundDrawList,
    .getNodeBackgroundDrawList = getNodeBackgroundDrawList,

    .pinRect = @ptrCast(&node_editor.pinRect),
    .pinPivotRect = @ptrCast(&node_editor.pinPivotRect),
    .pinPivotSize = @ptrCast(&node_editor.pinPivotSize),
    .pinPivotScale = @ptrCast(&node_editor.pinPivotScale),
    .pinPivotAlignment = @ptrCast(&node_editor.pinPivotAlignment),
};

fn getHintForegroundDrawList() public.DrawList {
    return public.DrawList{
        .ptr = node_editor.getHintForegroundDrawList(),
        .vtable = &drawlist_vtable,
    };
}
fn getHintBackgroundDrawList() public.DrawList {
    return public.DrawList{
        .ptr = node_editor.getHintBackgroundDrawLis(),
        .vtable = &drawlist_vtable,
    };
}
fn getNodeBackgroundDrawList(node_id: ui_node_editor.NodeId) public.DrawList {
    return public.DrawList{
        .ptr = node_editor.getNodeBackgroundDrawList(node_id),
        .vtable = &drawlist_vtable,
    };
}

fn createEditor(cfg: ui_node_editor.Config) *ui_node_editor.EditorContext {
    const node_editor_cfg = node_editor.Config{
        .settings_file = cfg.SettingsFile,
        .begin_save_session = @ptrCast(cfg.BeginSaveSession),
        .end_save_session = @ptrCast(cfg.EndSaveSession),
        .save_settings = @ptrCast(cfg.SaveSettings),
        .load_settings = @ptrCast(cfg.LoadSettings),
        .save_node_settings = @ptrCast(cfg.SaveNodeSettings),
        .load_node_settings = cfg.LoadNodeSettings,
        .user_pointer = cfg.UserPointer,
        .canvas_size_mode = @enumFromInt(@intFromEnum(cfg.CanvasSizeMode)),
        .drag_button_index = cfg.DragButtonIndex,
        .select_button_index = cfg.SelectButtonIndex,
        .navigate_button_index = cfg.NavigateButtonIndex,
        .context_menu_button_index = cfg.ContextMenuButtonIndex,
        .enable_smooth_zoom = cfg.EnableSmoothZoom,
        .smooth_zoom_power = cfg.SmoothZoomPower,
    };

    return @ptrCast(node_editor.EditorContext.create(node_editor_cfg));
}

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
            .pmin = args.pmin,
            .pmax = args.pmax,
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
        return dl.pushTextureId(@ptrFromInt(texture_id.idx));
    }
    pub fn popTextureId(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.popTextureId();
    }
    pub fn getClipRectMin(draw_list: *anyopaque) [2]f32 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getClipRectMin();
    }
    pub fn getClipRectMax(draw_list: *anyopaque) [2]f32 {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        return dl.getClipRectMax();
    }
    pub fn addLine(draw_list: *anyopaque, args: struct { p1: [2]f32, p2: [2]f32, col: u32, thickness: f32 }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addLine(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub fn addRect(draw_list: *anyopaque, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col: u32,
        rounding: f32 = 0.0,
        flags: public.DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addRect(.{
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
    pub fn addRectFilled(draw_list: *anyopaque, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col: u32,
        rounding: f32 = 0.0,
        flags: public.DrawFlags = .{},
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addRectFilled(.{
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
    pub fn addRectFilledMultiColor(draw_list: *anyopaque, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col_upr_left: u32,
        col_upr_right: u32,
        col_bot_right: u32,
        col_bot_left: u32,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addRectFilledMultiColor(.{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .col_upr_left = args.col_upr_left,
            .col_upr_right = args.col_upr_right,
            .col_bot_right = args.col_bot_right,
            .col_bot_left = args.col_bot_left,
        });
    }
    pub fn addQuad(draw_list: *anyopaque, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addQuad(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
            .thickness = args.thickness,
        });
    }

    pub fn addQuadFilled(draw_list: *anyopaque, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addQuadFilled(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
        });
    }
    pub fn addTriangle(draw_list: *anyopaque, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addTriangle(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
            .thickness = args.thickness,
        });
    }
    pub fn addTriangleFilled(draw_list: *anyopaque, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addTriangleFilled(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
        });
    }
    pub fn addCircle(draw_list: *anyopaque, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: i32 = 0,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addCircle(.{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub fn addCircleFilled(draw_list: *anyopaque, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);

        dl.addCircleFilled(.{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
        });
    }
    pub fn addNgon(draw_list: *anyopaque, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u32,
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addNgon(.{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
            .thickness = args.thickness,
        });
    }
    pub fn addNgonFilled(draw_list: *anyopaque, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u32,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addNgonFilled(.{
            .p = args.p,
            .r = args.r,
            .col = args.col,
            .num_segments = args.num_segments,
        });
    }
    pub fn addTextUnformatted(draw_list: *anyopaque, pos: [2]f32, col: u32, txt: []const u8) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addTextUnformatted(pos, col, txt);
    }
    pub fn addPolyline(draw_list: *anyopaque, points: []const [2]f32, args: struct {
        col: u32,
        flags: public.DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addPolyline(points, .{
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
    pub fn addConvexPolyFilled(draw_list: *anyopaque, points: []const [2]f32, col: u32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addConvexPolyFilled(points, col);
    }
    pub fn addBezierCubic(draw_list: *anyopaque, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addBezierCubic(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .col = args.col,
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub fn addBezierQuadratic(draw_list: *anyopaque, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addBezierQuadratic(.{
            .p1 = args.p1,
            .p2 = args.p2,
            .p3 = args.p3,
            .col = args.col,
            .thickness = args.thickness,
            .num_segments = args.num_segments,
        });
    }
    pub fn addImage(draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        uvmin: [2]f32 = .{ 0, 0 },
        uvmax: [2]f32 = .{ 1, 1 },
        col: u32 = 0xff_ff_ff_ff,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.addImage(@ptrFromInt(user_texture_id.idx), .{
            .pmin = args.pmin,
            .pmax = args.pmax,
            .uvmin = args.uvmin,
            .uvmax = args.uvmax,
            .col = args.col,
        });
    }
    pub fn addImageQuad(draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
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
        const dl: zgui.DrawList = @ptrCast(draw_list);

        dl.addImageQuad(@ptrFromInt(user_texture_id.idx), .{
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
    pub fn addImageRounded(draw_list: *anyopaque, user_texture_id: gpu.TextureHandle, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        uvmin: [2]f32 = .{ 0, 0 },
        uvmax: [2]f32 = .{ 1, 1 },
        col: u32 = 0xff_ff_ff_ff,
        rounding: f32 = 4.0,
        flags: public.DrawFlags = .{},
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);

        dl.addImageRounded(@ptrFromInt(user_texture_id.idx), .{
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
    pub fn pathClear(draw_list: *anyopaque) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathClear();
    }
    pub fn pathLineTo(draw_list: *anyopaque, pos: [2]f32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathLineTo(pos);
    }
    pub fn pathLineToMergeDuplicate(draw_list: *anyopaque, pos: [2]f32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathLineToMergeDuplicate(pos);
    }
    pub fn pathFillConvex(draw_list: *anyopaque, col: u32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathFillConvex(col);
    }
    pub fn pathStroke(draw_list: *anyopaque, args: struct {
        col: u32,
        flags: public.DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathStroke(.{
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
    pub fn pathArcTo(draw_list: *anyopaque, args: struct {
        p: [2]f32,
        r: f32,
        amin: f32,
        amax: f32,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathArcTo(.{
            .p = args.p,
            .r = args.r,
            .amin = args.amin,
            .amax = args.amax,
            .num_segments = args.num_segments,
        });
    }
    pub fn pathArcToFast(draw_list: *anyopaque, args: struct {
        p: [2]f32,
        r: f32,
        amin_of_12: u16,
        amax_of_12: u16,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathArcToFast(.{
            .p = args.p,
            .r = args.r,
            .amin_of_12 = args.amin_of_12,
            .amax_of_12 = args.amax_of_12,
        });
    }
    pub fn pathBezierCubicCurveTo(draw_list: *anyopaque, args: struct {
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathBezierCubicCurveTo(.{
            .p2 = args.p2,
            .p3 = args.p3,
            .p4 = args.p4,
            .num_segments = args.num_segments,
        });
    }
    pub fn pathBezierQuadraticCurveTo(draw_list: *anyopaque, args: struct {
        p2: [2]f32,
        p3: [2]f32,
        num_segments: u16 = 0,
    }) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathBezierQuadraticCurveTo(.{
            .p2 = args.p2,
            .p3 = args.p3,
            .num_segments = args.num_segments,
        });
    }
    pub fn pathRect(draw_list: *anyopaque, args: public.PathRect) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.pathRect(.{
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
    pub fn primReserve(draw_list: *anyopaque, idx_count: i32, vtx_count: i32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primReserve(idx_count, vtx_count);
    }
    pub fn primUnreserve(draw_list: *anyopaque, idx_count: i32, vtx_count: i32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primUnreserve(idx_count, vtx_count);
    }
    pub fn primRect(draw_list: *anyopaque, a: [2]f32, b: [2]f32, col: u32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primRect(a, b, col);
    }
    pub fn primRectUV(draw_list: *anyopaque, a: [2]f32, b: [2]f32, uv_a: [2]f32, uv_b: [2]f32, col: u32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primRectUV(
            a,
            b,
            uv_a,
            uv_b,
            col,
        );
    }
    pub fn primQuadUV(draw_list: *anyopaque, a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32, uv_a: [2]f32, uv_b: [2]f32, uv_c: [2]f32, uv_d: [2]f32, col: u32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primQuadUV(
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
    pub fn primWriteVtx(draw_list: *anyopaque, pos: [2]f32, uv: [2]f32, col: u32) void {
        const dl: zgui.DrawList = @ptrCast(draw_list);
        dl.primWriteVtx(pos, uv, col);
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

const BgfxImage = struct {
    handle: gpu.TextureHandle,
    flags: u8,
    mip: u8,

    pub fn toTextureIdent(self: *const BgfxImage) zgui.TextureIdent {
        return std.mem.bytesToValue(zgui.TextureIdent, std.mem.asBytes(self));
    }
};

fn image(texture: gpu.TextureHandle, args: public.Image) void {
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
    return zgui.DockSpaceOverViewport(0, zgui.getMainViewport(), f.*);
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

fn pushPropName(obj: cdb.ObjId, prop_idx: u32) void {
    const db = _cdb.getDbFromObjid(obj);
    const props_def = _cdb.getTypePropDef(db, obj.type_idx).?;
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

fn pushObjUUID(obj: cdb.ObjId) void {
    const uuid = assetdb.api.getOrCreateUuid(obj) catch undefined;
    var buff: [128]u8 = undefined;
    const uuid_str = std.fmt.bufPrintZ(&buff, "{s}", .{uuid}) catch undefined;

    zgui.pushStrIdZ(uuid_str);
}

fn uiFilterPass(allocator: std.mem.Allocator, filter: [:0]const u8, value: [:0]const u8, is_path: bool) ?f64 {
    // Collect token for filter
    var tokens = std.ArrayList([]const u8).init(allocator);
    defer tokens.deinit();

    var split = std.mem.splitAny(u8, filter, " ");
    const first = split.first();
    var it: ?[]const u8 = first;
    while (it) |word| : (it = split.next()) {
        if (word.len == 0) continue;

        var buff: [128]u8 = undefined;
        const lower_token = std.ascii.lowerString(&buff, word);

        tokens.append(lower_token) catch return null;
    }
    //return 0;

    return zf.rank(value, tokens.items, .{ .to_lower = false, .plain = !is_path });
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
    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "CoreUI");
    defer update_zone_ctx.End();

    const impls = try apidb.api.getImpl(tmp_allocator, cetech1.coreui.CoreUII);
    defer tmp_allocator.free(impls);

    for (impls) |iface| {
        try iface.ui(tmp_allocator, kernel_tick, dt);
    }

    backend.draw();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.CoreUIApi, &api);
    try apidb.api.setZigApi(module_name, ui_node_editor.NodeEditorApi, &node_editor_api);
    try apidb.api.implOrRemove(.cdb_types, cdb.CreateTypesI, &create_cdb_types_i, true);
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
        &[_]u16{ public.CoreIcons.ICON_MIN_FA, public.CoreIcons.ICON_MAX_FA, 0 },
    );

    var style = zgui.getStyle();
    //style.frame_border_size = 1.0;
    style.indent_spacing = 30;
    style.scaleAllSizes(scale_factor);
}

pub fn enableWithWindow(window: ?cetech1.platform.Window) !void {
    _scale_factor = _scale_factor orelse scale_factor: {
        const scale = if (window) |w| w.getContentScale() else .{ 1, 1 };
        break :scale_factor @max(scale[0], scale[1]);
    };
    //_scale_factor = 2;

    //zgui.getStyle().frame_rounding = 8;

    zgui.io.setConfigFlags(zgui.ConfigFlags{
        .nav_enable_keyboard = true,
        .nav_enable_gamepad = true,
        .nav_enable_set_mouse_pos = true,
        .dock_enable = true,
    });
    zgui.io.setConfigWindowsMoveFromTitleBarOnly(true);

    _backed_initialised = true;

    initFonts(16, _scale_factor.?);
    backend.init(if (window) |w| w.getInternal(anyopaque) else null);

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
    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "CoreUI new frame");
    defer update_zone_ctx.End();
    backend.newFrame(fb_width, fb_height);
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
    const w = _cdb.writeObj(selection).?;
    try public.ObjSelection.removeFromRefSet(db, w, .Selection, obj);
    try _cdb.writeCommit(w);
}

fn handleSelection(allocator: std.mem.Allocator, selection: *public.Selection, obj: cetech1.coreui.SelectionItem, multiselect_enabled: bool) !void {
    _ = allocator; // autofix

    if (multiselect_enabled and api.isKeyDown(.mod_ctrl)) {
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
    const impls = try apidb.api.getImpl(_allocator, public.RegisterTestsI);
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

const cdb_tests = @import("cdb_test.zig");

// test "coreui: should do basic operatino with selection" {
//     try cdb_tests.testInit();
//     defer cdb_tests.testDeinit();

//     try registerToApi();

//     const db = try cdb_private.api.createDb("test");
//     defer cdb_private.api.destroyDb(db);

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
comptime {}
