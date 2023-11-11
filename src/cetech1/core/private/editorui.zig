const std = @import("std");

const c = @import("c.zig").c;

const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const nfd = @import("nfd");

const apidb = @import("apidb.zig");
const log = @import("log.zig");
const profiler = @import("profiler.zig");
const assetdb = @import("assetdb.zig");

const public = @import("../editorui.zig");
const cetech1 = @import("../cetech1.zig");
const Icons = cetech1.editorui.Icons;

const _main_font = @embedFile("./fonts/Roboto-Medium.ttf");
const _fa_solid_font = @embedFile("./fonts/fa-solid-900.ttf");
const _fa_regular_font = @embedFile("./fonts/fa-regular-400.ttf");

const MODULE_NAME = "editorui";

pub var api = public.EditorUIApi{
    .enableWithWindow = useWithWindow,
    .newFrame = newFrame,
    .showDemoWindow = showDemoWindow,

    .begin = @ptrCast(&zgui.begin),
    .end = @ptrCast(&zgui.end),
    .beginPopup = @ptrCast(&zgui.beginPopup),

    .pushStyleColor4f = @ptrCast(&zgui.pushStyleColor4f),
    .popStyleColor = @ptrCast(&zgui.popStyleColor),
    .tableSetBgColor = @ptrCast(&zgui.tableSetBgColor),
    .colorConvertFloat4ToU32 = @ptrCast(&zgui.colorConvertFloat4ToU32),

    .textUnformatted = @ptrCast(&zgui.textUnformatted),
    .textUnformattedColored = @ptrCast(&zgui.textUnformattedColored),

    .beginMainMenuBar = @ptrCast(&zgui.beginMainMenuBar),
    .endMainMenuBar = @ptrCast(&zgui.endMainMenuBar),
    .beginMenuBar = @ptrCast(&zgui.beginMenuBar),
    .endMenuBar = @ptrCast(&zgui.endMenuBar),
    .beginMenu = @ptrCast(&zgui.beginMenu),
    .endMenu = @ptrCast(&zgui.endMenu),
    .menuItem = @ptrCast(&zgui.menuItem),
    .menuItemPtr = @ptrCast(&zgui.menuItemPtr),

    .separator = @ptrCast(&zgui.separator),
    .separatorText = @ptrCast(&zgui.separatorText),
    .setNextItemWidth = @ptrCast(&zgui.setNextItemWidth),

    .pushPtrId = @ptrCast(&zgui.pushPtrId),
    .pushIntId = @ptrCast(&zgui.pushIntId),
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

    .labelText = labelText,

    .sameLine = @ptrCast(&zgui.sameLine),

    .button = @ptrCast(&zgui.button),

    .inputText = @ptrCast(&zgui.inputText),
    .inputFloat = @ptrCast(&zgui.inputFloat),
    .inputDouble = @ptrCast(&zgui.inputDouble),
    .inputI32 = inputI32,
    .inputU32 = inputU32,
    .inputI64 = inputI64,
    .inputU64 = inputU64,
    .checkbox = @ptrCast(&zgui.checkbox),

    .alignTextToFramePadding = @ptrCast(&zgui.alignTextToFramePadding),

    .isItemToggledOpen = @ptrCast(&zgui.isItemToggledOpen),

    .openFileDialog = nfd.openFileDialog,
    .saveFileDialog = nfd.saveFileDialog,
    .openFolderDialog = nfd.openFolderDialog,
    .freePath = nfd.freePath,
};

pub fn labelText(label: [:0]const u8, text: [:0]const u8) void {
    zgui.labelText(label, "{s}", .{text});
}

var _allocator: std.mem.Allocator = undefined;
var _backed_initialised = false;
var _true_gpuctx: ?*zgpu.GraphicsContext = null;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    zgui.init(_allocator);
    zgui.plot.init();
}

pub fn deinit() void {
    if (_backed_initialised) zgui.backend.deinit();
    zgui.plot.deinit();
    zgui.deinit();
}

pub fn editorUI(tmp_allocator: std.mem.Allocator, main_db: *cetech1.cdb.Db, kernel_tick: u64, dt: f32) !void {
    _ = kernel_tick;
    _ = dt;
    _ = main_db;

    var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "EditorUI");
    defer update_zone_ctx.End();

    // Headless mode
    if (_true_gpuctx == null) return;

    var it = apidb.api.getFirstImpl(cetech1.editorui.EditorUII);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(cetech1.editorui.EditorUII, node);
        iface.*.ui(&tmp_allocator);
    }
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.EditorUIApi, &api);
}

pub fn useWithWindow(window: *cetech1.system.Window, gpuctx: *cetech1.gpu.GpuContext) void {
    var true_window: *zglfw.Window = @ptrCast(window);
    _true_gpuctx = @alignCast(@ptrCast(gpuctx));

    const scale_factor = scale_factor: {
        const scale = true_window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    // Load main font
    _ = zgui.io.addFontFromMemory(_main_font, std.math.floor(16.0 * scale_factor));

    // Merge Font Awesome
    var fa_cfg = zgui.FontConfig.init();
    fa_cfg.merge_mode = true;
    _ = zgui.io.addFontFromMemoryWithConfig(
        if (false) _fa_regular_font else _fa_solid_font,
        std.math.floor(16.0 * scale_factor),
        fa_cfg,
        &[_]u16{ c.ICON_MIN_FA, c.ICON_MAX_FA, 0 },
    );

    zgui.io.setConfigFlags(zgui.ConfigFlags{ .nav_enable_keyboard = true, .nav_enable_gamepad = true });

    zgui.backend.init(
        true_window,
        _true_gpuctx.?.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
    );

    zgui.getStyle().scaleAllSizes(scale_factor);

    _backed_initialised = true;
}

fn newFrame() void {
    zgui.backend.newFrame(
        _true_gpuctx.?.swapchain_descriptor.width,
        _true_gpuctx.?.swapchain_descriptor.height,
    );
}

fn showDemoWindow() void {
    if (!isEditorUIActive()) return;
    zgui.showDemoWindow(null);
    zgui.plot.showDemoWindow(null);
}

fn isEditorUIActive() bool {
    return _true_gpuctx != null;
}

fn getPropertyColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32 {
    const prototype_obj = db.getPrototype(db.readObj(obj).?);
    const has_prototype = !prototype_obj.isEmpty();

    var color: ?[4]f32 = null;
    if (has_prototype) {
        color = .{ 0.5, 0.5, 0.5, 1.0 };
        if (db.isPropertyOverrided(db.readObj(obj).?, prop_idx)) {
            color = .{ 0.0, 0.8, 1.0, 1.0 };
        }
    }
    return color;
}

// next shit

fn inputI32(label: [:0]const u8, args: public.InputScalarGen(i32)) bool {
    var flags = zgui.InputTextFlags{
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
    var flags = zgui.InputTextFlags{
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
    var flags = zgui.InputTextFlags{
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
    var flags = zgui.InputTextFlags{
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

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_editorui_ui_i) == @sizeOf(public.EditorUII));
}
