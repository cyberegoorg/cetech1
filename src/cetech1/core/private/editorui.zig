const std = @import("std");

const c = @import("c.zig").c;

const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const nfd = @import("nfd");
const zf = @import("zf");

const apidb = @import("apidb.zig");
const log = @import("log.zig");
const profiler = @import("profiler.zig");
const assetdb = @import("assetdb.zig");

const public = @import("../editorui.zig");
const cetech1 = @import("../cetech1.zig");
const Icons = cetech1.editorui.CoreIcons;

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
    .colorPicker4 = @ptrCast(&zgui.colorPicker4),
    .colorEdit4 = @ptrCast(&zgui.colorEdit4),
    .beginMainMenuBar = @ptrCast(&zgui.beginMainMenuBar),
    .endMainMenuBar = @ptrCast(&zgui.endMainMenuBar),
    .beginMenuBar = @ptrCast(&zgui.beginMenuBar),
    .endMenuBar = @ptrCast(&zgui.endMenuBar),
    .beginMenu = @ptrCast(&zgui.beginMenu),
    .endMenu = @ptrCast(&zgui.endMenu),
    .menuItem = @ptrCast(&zgui.menuItem),
    .menuItemPtr = @ptrCast(&zgui.menuItemPtr),
    .beginChild = @ptrCast(&zgui.beginChild),
    .endChild = @ptrCast(&zgui.endChild),
    .separator = @ptrCast(&zgui.separator),
    .separatorText = @ptrCast(&zgui.separatorText),
    .setNextItemWidth = @ptrCast(&zgui.setNextItemWidth),
    .pushPtrId = @ptrCast(&zgui.pushPtrId),
    .pushIntId = @ptrCast(&zgui.pushIntId),
    .pushObjId = pushObjId,
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
    .inputFloat = @ptrCast(&zgui.inputFloat),
    .inputDouble = @ptrCast(&zgui.inputDouble),
    .inputI32 = inputI32,
    .inputU32 = inputU32,
    .inputI64 = inputI64,
    .inputU64 = inputU64,
    .checkbox = @ptrCast(&zgui.checkbox),
    .alignTextToFramePadding = @ptrCast(&zgui.alignTextToFramePadding),
    .isItemToggledOpen = @ptrCast(&zgui.isItemToggledOpen),
    .dummy = @ptrCast(&zgui.dummy),
    .spacing = @ptrCast(&zgui.spacing),
    .getScrollX = @ptrCast(&zgui.getScrollX),
    .openFileDialog = nfd.openFileDialog,
    .saveFileDialog = nfd.saveFileDialog,
    .openFolderDialog = nfd.openFolderDialog,
    .freePath = nfd.freePath,
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
    .buffFormatObjLabel = buffFormatObjLabel,
    .objContextMenu = objContextMenu,
    .getObjColor = getObjColor,

    .isSelected = isSelected,
    .addToSelection = addToSelection,
    .setSelection = setSelection,
    .selectedCount = selectedCount,
    .getFirstSelected = getFirstSelected,
    .getSelected = getSelected,
    .handleSelection = handleSelection,
    .removeFromSelection = removeFromSelection,
    .clearSelection = clearSelection,
};

fn clearSelection(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    selection: cetech1.cdb.ObjId,
) !void {
    const r = db.readObj(selection).?;

    const w = db.writeObj(selection).?;

    // TODO: clear to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |ref| {
            try public.ObjSelectionType.removeFromRefSet(db, w, .Selection, ref);
        }
    }

    try db.writeCommit(w);
}

fn objContextMenu(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    prop_idx: ?u32,
    in_set_obj: ?cetech1.cdb.ObjId,
) !void {
    const prop_defs = db.getTypePropDef(obj.type_hash).?;

    // Property based context
    if (prop_idx) |pidx| {
        const prop_def = prop_defs[pidx];

        if (in_set_obj) |set_obj| {
            const obj_r = db.readObj(obj) orelse return;

            const can_inisiate = db.canIinisiated(obj_r, db.readObj(set_obj).?);

            if (can_inisiate) {
                if (api.menuItem(public.Icons.Add ++ "  " ++ "Inisiated", .{})) {
                    const w = db.writeObj(obj).?;
                    _ = try db.instantiateSubObjFromSet(w, pidx, set_obj);
                    try db.writeCommit(w);
                }

                api.separator();
            }

            {
                api.pushStyleColor4f(.{ .idx = .text, .c = cetech1.editorui.Colors.Remove });
                defer api.popStyleColor(.{});
                if (api.menuItem(public.Icons.Remove ++ "  " ++ "Remove", .{})) {
                    const w = db.writeObj(obj).?;
                    if (prop_def.type == .REFERENCE_SET) {
                        try db.removeFromRefSet(w, pidx, set_obj);
                    } else {
                        const subobj_w = db.writeObj(set_obj).?;
                        try db.removeFromSubObjSet(w, pidx, subobj_w);
                        try db.writeCommit(subobj_w);
                    }

                    try db.writeCommit(w);
                }
            }
        } else {
            if (prop_def.type == .SUBOBJECT_SET or prop_def.type == .REFERENCE_SET) {
                if (api.beginMenu(public.Icons.Add ++ "  " ++ "Add to set", true)) {
                    defer api.endMenu();

                    const set_menus_aspect = db.getPropertyAspect(public.UiSetMenus, obj.type_hash, pidx);
                    if (set_menus_aspect) |aspect| {
                        if (aspect.add_menu) |add_menu| {
                            add_menu(&allocator, db.db, obj, pidx);
                        }
                    } else {
                        if (prop_def.type == .REFERENCE_SET) {
                            if (api.menuItem(public.Icons.Add ++ "  " ++ "Add Reference", .{})) {
                                //TODO
                            }
                        } else {
                            if (prop_def.type_hash.id != 0) {
                                if (api.menuItem(public.Icons.Add ++ "  " ++ "Add new", .{})) {
                                    const w = db.writeObj(obj).?;

                                    const new_obj = try db.createObject(prop_def.type_hash);
                                    const new_obj_w = db.writeObj(new_obj).?;

                                    try db.addSubObjToSet(w, pidx, &.{new_obj_w});

                                    try db.writeCommit(new_obj_w);
                                    try db.writeCommit(w);
                                }
                            }
                        }
                    }
                }
            } else if (prop_def.type == .SUBOBJECT) {
                const obj_r = db.readObj(obj) orelse return;

                const subobj = db.readSubObj(obj_r, pidx);
                if (subobj == null) {
                    if (prop_def.type_hash.id != 0) {
                        if (api.menuItem(public.Icons.Add ++ "  " ++ "Add new", .{})) {
                            const w = db.writeObj(obj).?;

                            const new_obj = try db.createObject(prop_def.type_hash);
                            const new_obj_w = db.writeObj(new_obj).?;

                            try db.setSubObj(w, pidx, new_obj_w);

                            try db.writeCommit(new_obj_w);
                            try db.writeCommit(w);
                        }
                    }
                }
            }
        }

        // Obj based context
    } else {}
}

const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };

fn getObjColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cetech1.cdb.ObjId) [4]f32 {
    if (prop_idx != null and in_set_obj != null) {
        const obj_r = db.readObj(obj).?;
        const is_inisiated = db.isIinisiated(obj_r, prop_idx.?, db.readObj(in_set_obj.?).?);
        if (is_inisiated) return INSIATED_COLOR;
    }

    if (in_set_obj) |s_obj| {
        const ui_visual_aspect = db.getAspect(cetech1.editorui.UiVisualAspect, s_obj.type_hash);
        if (ui_visual_aspect) |aspect| {
            if (aspect.ui_color) |color| {
                return color(db.db, s_obj).c;
            }
        }
    } else {
        const ui_visual_aspect = db.getAspect(cetech1.editorui.UiVisualAspect, obj.type_hash);
        if (ui_visual_aspect) |aspect| {
            if (aspect.ui_color) |color| {
                return color(db.db, obj).c;
            }
        }
    }
    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn buffFormatObjLabel(allocator: std.mem.Allocator, buff: [:0]u8, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) ?[:0]u8 {
    var label: [:0]u8 = undefined;
    const ui_visual_aspect = db.getAspect(public.UiVisualAspect, obj.type_hash);
    if (ui_visual_aspect) |aspect| {
        var name: []const u8 = undefined;
        defer allocator.free(name);

        if (aspect.ui_name) |ui_name| {
            name = std.mem.span(ui_name(&allocator, db.db, obj));
        } else {
            const asset_obj = assetdb.api.getAssetForObj(obj).?;
            const obj_r = db.readObj(asset_obj).?;

            if (assetdb.api.isAssetFolder(obj)) {
                const asset_name = cetech1.assetdb.AssetType.readStr(db, obj_r, .Name) orelse "ROOT";
                name = std.fmt.allocPrintZ(
                    allocator,
                    "{s}",
                    .{
                        asset_name,
                    },
                ) catch "";
            } else {
                const asset_name = cetech1.assetdb.AssetType.readStr(db, obj_r, .Name) orelse "No NAME =()";
                const type_name = db.getTypeName(asset_obj.type_hash).?;
                name = std.fmt.allocPrintZ(
                    allocator,
                    "{s}.{s}",
                    .{
                        asset_name,
                        type_name,
                    },
                ) catch "";
            }
        }

        if (aspect.ui_icons) |icons| {
            const icon = std.mem.span(icons(&allocator, db.db, obj));
            defer allocator.free(icon);
            label = std.fmt.bufPrintZ(buff, "{s}" ++ "  " ++ "{s}", .{ icon, name }) catch return null;
        } else {
            label = std.fmt.bufPrintZ(buff, "{s}", .{name}) catch return null;
        }
    } else {
        return null;
    }

    return label;
}

fn freePath(path: []const u8) void {
    _ = path;
}

fn pushObjId(obj: cetech1.cdb.ObjId) void {
    zgui.pushPtrId(@ptrFromInt(obj.toU64()));
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
    api.textUnformatted(Icons.FA_MAGNIFYING_GLASS);
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
        const iface = cetech1.apidb.ApiDbAPI.toInterface(cetech1.editorui.EditorUII, node);
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
    var main_cfg = zgui.FontConfig.init();
    main_cfg.font_data_owned_by_atlas = false;
    _ = zgui.io.addFontFromMemoryWithConfig(_main_font, std.math.floor(16.0 * scale_factor), main_cfg, null);

    // Merge Font Awesome
    var fa_cfg = zgui.FontConfig.init();
    fa_cfg.font_data_owned_by_atlas = false;
    fa_cfg.merge_mode = true;
    _ = zgui.io.addFontFromMemoryWithConfig(
        if (false) _fa_regular_font else _fa_solid_font,
        std.math.floor(16.0 * scale_factor),
        fa_cfg,
        &[_]u16{ c.ICON_MIN_FA, c.ICON_MAX_FA, 0 },
    );

    zgui.io.setConfigFlags(zgui.ConfigFlags{
        .nav_enable_keyboard = true,
        .nav_enable_gamepad = true,
        .nav_enable_set_mouse_pos = true,
    });

    zgui.backend.init(
        true_window,
        _true_gpuctx.?.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(zgpu.wgpu.TextureFormat.undef),
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
    try public.ObjSelectionType.removeFromRefSet(db, w, .Selection, obj);
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
    return public.ObjSelectionType.readRefSet(db, r, .Selection, allocator);
}

fn isSelected(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) bool {
    return public.ObjSelectionType.isInSet(db, db.readObj(selection).?, .Selection, obj);
}

fn addToSelection(db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const w = db.writeObj(selection).?;

    try public.ObjSelectionType.addRefToSet(db, w, .Selection, &.{obj});
    try db.writeCommit(w);
}

fn setSelection(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId, obj: cetech1.cdb.ObjId) !void {
    const r = db.readObj(selection).?;

    const w = db.writeObj(selection).?;

    // TODO: clear to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |ref| {
            try public.ObjSelectionType.removeFromRefSet(db, w, .Selection, ref);
        }
    }
    try public.ObjSelectionType.addRefToSet(db, w, .Selection, &.{obj});

    try db.writeCommit(w);
}

fn selectedCount(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) u32 {
    const r = db.readObj(selection) orelse return 0;

    // TODO: count to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        return @truncate(set.len);
    }
    return 0;
}

fn getFirstSelected(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) cetech1.cdb.ObjId {
    const r = db.readObj(selection).?;

    // TODO: count to cdb
    if (public.ObjSelectionType.readRefSet(db, r, .Selection, allocator)) |set| {
        defer allocator.free(set);
        for (set) |s| {
            return s;
        }
    }
    return .{};
}
// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_editorui_ui_i) == @sizeOf(public.EditorUII));
}
