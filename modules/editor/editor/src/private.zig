const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const cdb = cetech1.cdb;
const math = cetech1.math;
const task = cetech1.task;
const host = cetech1.host;

const kernel = cetech1.kernel;
const editor_tabs = @import("editor_tabs");

const public = @import("editor.zig");

const Icons = coreui.CoreIcons;

const module_name = .editor;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _assetdb: *const assetdb.AssetDBAPI = undefined;
const tempalloc = cetech1.tempalloc;
const profiler = cetech1.profiler;

const TabsSelectedObject = cetech1.AutoArrayHashMap(*public.TabI, coreui.SelectedObj);
const TabsMap = cetech1.AutoArrayHashMap(*anyopaque, *public.TabI);
const TabsIdPool = cetech1.heap.IdPool(u32);
const TabsIds = cetech1.AutoArrayHashMap(cetech1.StrId32, TabsIdPool);

const ContextToLabel = cetech1.AutoArrayHashMap(cetech1.StrId64, [:0]const u8);

// TODO: from config
const REPO_URL = "https://codeberg.org/cyberegoorg/cetech1";
const ONLINE_DOCUMENTATION = "https://cyberegoorg.github.io/cetech1/about.html";

// Global state
const G = struct {
    main_db: cdb.DbId = undefined,
    show_demos: bool = false,
    show_metrics: bool = false,
    show_testing_window: bool = false,
    show_external_credits: bool = false,
    show_authors: bool = false,
    enable_colors: bool = true,

    last_selected_obj: coreui.SelectedObj = undefined,

    context2label: ContextToLabel = undefined,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};
var _g: *G = undefined;

const api = public.EditorAPI{
    .showObjContextMenu = showObjContextMenu,
    .formatObjLabel = formatObjLabel,

    .getAssetColor = getAssetColor,
    .isColorsEnabled = isColorsEnabled,

    .getStateColor = getStateColor,
    .getObjColor = getObjColor,
    .uiAssetDragDropSource = uiAssetDragDropSource,
    .uiAssetDragDropTarget = uiAssetDragDropTarget,
};

fn isColorsEnabled() bool {
    return _g.enable_colors;
}

const PROTOTYPE_PROPERTY_OVERIDED_COLOR: math.Color4f = .{ .g = 0.8, .b = 1.0, .a = 1.0 };
const PROTOTYPE_PROPERTY_COLOR: math.Color4f = .{ .r = 0.83, .g = 0.83, .b = 0.83, .a = 1.0 };
const INSIATED_COLOR: math.Color4f = .{ .r = 1.0, .g = 0.6, .a = 1.0 };
const NOT_OWNED_PROPERTY_COLOR: math.Color4f = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 };

fn getStateColor(state: cdb.ObjRelation) math.Color4f {
    if (!_g.enable_colors) return coreui.getStyle().getColor(.text);

    return switch (state) {
        .Inisiated => INSIATED_COLOR,
        .Overide => PROTOTYPE_PROPERTY_OVERIDED_COLOR,
        .Inheried => PROTOTYPE_PROPERTY_COLOR,
        .Owned => coreui.getStyle().getColor(.text),
        .NotOwned => NOT_OWNED_PROPERTY_COLOR, //TODO: remove
    };
}

fn getObjColor(obj: cdb.ObjId, in_set_obj: ?cdb.ObjId) ?math.Color4f {
    const db = cdb.getDbFromObjid(obj);

    if (in_set_obj) |s_obj| {
        if (cdb.getAspect(public.UiVisualAspect, db, s_obj.type_idx)) |aspect| {
            if (aspect.ui_color) |color| {
                return color(s_obj) catch coreui.getStyle().getColor(.text);
            }
        }
    } else {
        if (cdb.getAspect(public.UiVisualAspect, db, obj.type_idx)) |aspect| {
            if (aspect.ui_color) |color| {
                return color(obj) catch coreui.getStyle().getColor(.text);
            }
        }
    }
    return null;
}

fn getAssetColor(obj: cdb.ObjId) math.Color4f {
    if (!_g.enable_colors) return coreui.getStyle().getColor(.text);

    if (obj.type_idx.eql(AssetTypeIdx)) {
        const is_modified = assetdb.isAssetModified(obj);
        const is_deleted = assetdb.isToDeleted(obj);

        if (is_modified) {
            return coreui.Colors.Modified;
        } else if (is_deleted) {
            return coreui.Colors.Deleted;
        }
        const r = cdb.readObj(obj).?;

        if (assetdb.AssetCdb.readSubObj(r, .Object)) |asset_obj| {
            return getObjColor(asset_obj, null) orelse coreui.getStyle().getColor(.text);
        }
    }

    return coreui.getStyle().getColor(.text);
}

fn formatObjLabel(allocator: std.mem.Allocator, obj: cdb.ObjId, in_set_idx: ?usize, cfg: public.FormatObjLabelConfig) ![:0]u8 {
    var name_buff: [128:0]u8 = undefined;

    const db = cdb.getDbFromObjid(obj);
    if (cdb.getAspect(public.UiVisualAspect, db, obj.type_idx)) |aspect| {
        var name: []const u8 = undefined;

        if (aspect.ui_name) |ui_name| {
            name = ui_name(&name_buff, allocator, obj) catch "ERROR";
        } else {
            const asset_obj = assetdb.getAssetForObj(obj).?;
            const obj_r = cdb.readObj(asset_obj).?;

            if (assetdb.isAssetFolder(obj)) {
                const asset_name = assetdb.AssetCdb.readStr(obj_r, .Name) orelse "ROOT";
                name = std.fmt.bufPrintZ(&name_buff, "{s}", .{asset_name}) catch "";
            } else {
                const asset_name = assetdb.AssetCdb.readStr(obj_r, .Name) orelse "No NAME =()";
                const type_name = cdb.getTypeName(db, asset_obj.type_idx).?;
                name = std.fmt.bufPrintZ(&name_buff, "{s}.{s}", .{ asset_name, type_name }) catch "";
            }
        }

        var status_icon_buf: [16:0]u8 = undefined;
        const status_icons = blk: {
            if (cfg.with_status_icons) {
                if (aspect.ui_status_icons) |ui_status_icons| {
                    break :blk ui_status_icons(&status_icon_buf, allocator, obj) catch "";
                }
            }
            break :blk null;
        };

        var icon_buf: [16:0]u8 = undefined;
        const icon = blk: {
            if (cfg.with_icon) {
                if (aspect.ui_icons) |icons| {
                    break :blk icons(&icon_buf, allocator, obj) catch "";
                }
            }
            break :blk null;
        };

        if (cfg.with_id) {
            if (cfg.uuid_id) {
                return std.fmt.allocPrintSentinel(allocator, "{s}{s}" ++ "{s}" ++ "{s}###{f}", .{
                    icon orelse "",
                    status_icons orelse "",
                    if (cfg.with_icon) "  " else "",
                    if (cfg.with_txt) name else "",
                    assetdb.getOrCreateUuid(obj) catch return allocator.dupeZ(u8, "Not implemented"),
                }, 0) catch return try allocator.dupeZ(u8, "Not implemented");
            } else {
                return std.fmt.allocPrintSentinel(allocator, "{s}{s}" ++ "{s}" ++ "{s}###{s}", .{
                    icon orelse "",
                    status_icons orelse "",
                    if (cfg.with_icon) "  " else "",
                    if (cfg.with_txt) name else "",
                    name,
                }, 0) catch return allocator.dupeZ(u8, "Not implemented");
            }
        } else {
            return std.fmt.allocPrintSentinel(allocator, "{s}{s}" ++ "{s}" ++ "{s}", .{
                icon orelse "",
                status_icons orelse "",
                if (cfg.with_icon) "  " else "",
                if (cfg.with_txt) name else "",
            }, 0) catch return allocator.dupeZ(u8, "Not implemented");
        }
    }

    if (in_set_idx) |idx| {
        return std.fmt.allocPrintSentinel(allocator, "{d}", .{idx}, 0) catch return allocator.dupeZ(u8, "Not implemented");
    }

    return allocator.dupeZ(u8, "Not implemented");
}

fn uiAssetDragDropSource(allocator: std.mem.Allocator, obj: cdb.ObjId) !void {
    var is_project = false;
    if (assetdb.getObjForAsset(obj)) |o| {
        is_project = o.type_idx.eql(ProjectTypeIdx);
    }

    if (!is_project and !assetdb.isRootFolder(obj) and coreui.beginDragDropSource(.{})) {
        defer coreui.endDragDropSource();

        // try uiAssetCard(allocator, tab, item_obj, state, selections, coreui.getWindowDrawList(), .{});
        const aasset_label = try formatObjLabel(allocator, obj, null, .{ .with_txt = true, .with_status_icons = true });
        defer allocator.free(aasset_label);

        const aasset_color = getAssetColor(obj);
        coreui.textColored(aasset_color, aasset_label);

        //if (selections.count() == 1) {
        _ = coreui.setDragDropPayload("obj", &std.mem.toBytes(obj), .once);
        // } else {
        //     _ = coreui.setDragDropPayload("objs", &std.mem.toBytes(selections), .once);
        // }
    }
}

fn uiAssetDragDropTarget(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, obj: cdb.ObjId, prop_idx: ?u32) !void {
    const db = cdb.getDbFromObjid(obj);
    if (coreui.beginDragDropTarget()) {
        defer coreui.endDragDropTarget();
        if (coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
            const drag_obj: cdb.ObjId = std.mem.bytesToValue(cdb.ObjId, payload.data.?);

            if (!drag_obj.eql(obj)) {
                if (cdb.getAspect(public.UiDropObj, db, obj.type_idx)) |aspect| {
                    try aspect.ui_drop_obj(allocator, tab, obj, prop_idx, drag_obj);
                }
            }
        }
    }
}

fn showObjContextMenu(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    contexts: []const cetech1.StrId64,
    selection: coreui.SelectedObj,
) !void {
    const obj = selection.parent_obj orelse selection.obj;

    if (selection.isEmpty()) return;

    _g.filter = coreui.uiFilter(&_g.filter_buff, _g.filter);

    const db = cdb.getDbFromObjid(obj);

    const is_child = cdb.isChildOff(selection.top_level_obj, selection.in_set_obj orelse selection.obj);
    const enabled = is_child;

    // Property based context
    if (selection.prop_idx) |pidx| {
        const prop_defs = cdb.getTypePropDef(db, obj.type_idx).?;
        const prop_def = prop_defs[pidx];

        if (selection.in_set_obj) |in_set_obj| {
            const obj_r = cdb.readObj(obj) orelse return;

            const in_set_obj_r = cdb.readObj(in_set_obj) orelse return;
            if (cdb.canIinisiated(obj_r, in_set_obj_r)) {
                if (coreui.menuItem(allocator, coreui.Icons.Instansiate ++ "  " ++ "Instansiate" ++ "###Inisiate", .{}, null)) {
                    const w = cdb.writeObj(obj).?;
                    _ = try cdb.instantiateSubObjFromSet(w, pidx, in_set_obj);
                    try cdb.writeCommit(w);
                }

                coreui.separator();
            }

            {
                const has_prototype = !cdb.getPrototype(obj_r).isEmpty();
                _ = has_prototype;

                coreui.pushStyleColor4f(.{ .idx = .text, .c = coreui.Colors.Remove });
                defer coreui.popStyleColor(.{});
                if (coreui.menuItem(allocator, coreui.Icons.Remove ++ "  " ++ "Remove" ++ "###Remove", .{
                    .enabled = true, //has_prototype or cdb.canIinisiated(obj_r, in_set_obj_r),
                }, null)) {
                    const w = cdb.writeObj(obj).?;
                    if (prop_def.type == .REFERENCE_SET) {
                        try cdb.removeFromRefSet(w, pidx, in_set_obj);
                    } else {
                        const subobj_w = cdb.writeObj(in_set_obj).?;
                        try cdb.removeFromSubObjSet(w, pidx, subobj_w);
                        try cdb.writeCommit(subobj_w);
                    }

                    try cdb.writeCommit(w);
                }
            }
        } else {
            if (prop_def.type == .SUBOBJECT_SET or prop_def.type == .REFERENCE_SET) {
                var menu_open = true;

                if (_g.filter == null) {
                    menu_open = coreui.beginMenu(allocator, coreui.Icons.Add ++ "  " ++ "Add to set" ++ "###AddToSet", enabled, null);
                }

                if (menu_open) {
                    defer if (_g.filter == null) coreui.endMenu();

                    const set_menus_aspect = cdb.getPropertyAspect(public.UiSetMenusAspect, db, obj.type_idx, pidx);
                    if (set_menus_aspect) |aspect| {
                        try aspect.add_menu(allocator, obj, pidx, _g.filter);
                    } else {
                        if (prop_def.type == .REFERENCE_SET) {
                            if (editor_tabs.selectObjFromMenu(
                                allocator,
                                assetdb.getObjForAsset(obj) orelse obj,
                                cdb.getTypeIdx(db, prop_def.type_hash) orelse .{},
                                enabled,
                            )) |selected| {
                                const w = cdb.writeObj(obj).?;
                                try cdb.addRefToSet(w, pidx, &.{selected});
                                try cdb.writeCommit(w);
                            }
                        } else {
                            if (prop_def.type_hash.id != 0) {
                                if (coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Add new" ++ "###AddNew", .{ .enabled = enabled }, null)) {
                                    const w = cdb.writeObj(obj).?;

                                    const new_obj = try cdb.createObject(db, cdb.getTypeIdx(db, prop_def.type_hash).?);
                                    const new_obj_w = cdb.writeObj(new_obj).?;

                                    try cdb.addSubObjToSet(w, pidx, &.{new_obj_w});

                                    try cdb.writeCommit(new_obj_w);
                                    try cdb.writeCommit(w);
                                }
                            }
                        }
                    }
                }
            } else if (prop_def.type == .SUBOBJECT) {
                const obj_r = cdb.readObj(obj) orelse return;

                const set_menus_aspect = cdb.getPropertyAspect(public.UiSetMenusAspect, db, obj.type_idx, pidx);
                if (set_menus_aspect) |aspect| {
                    try aspect.add_menu(allocator, obj, pidx, _g.filter);
                } else if (cdb.readSubObj(obj_r, pidx)) |subobj| {
                    const subobj_r = cdb.readObj(subobj).?;

                    if (cdb.canIinisiated(obj_r, subobj_r)) {
                        if (coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Inisiate" ++ "###Inisiate", .{}, null)) {
                            const w = cdb.writeObj(obj).?;
                            _ = try cdb.instantiateSubObj(w, pidx);
                            try cdb.writeCommit(w);
                        }
                    }
                } else {
                    if (prop_def.type_hash.id != 0) {
                        if (coreui.menuItem(allocator, coreui.Icons.Add ++ "  " ++ "Add new", .{ .enabled = enabled }, null)) {
                            const w = cdb.writeObj(obj).?;

                            const new_obj = try cdb.createObject(db, cdb.getTypeIdx(db, prop_def.type_hash).?);
                            const new_obj_w = cdb.writeObj(new_obj).?;

                            try cdb.setSubObj(w, pidx, new_obj_w);

                            try cdb.writeCommit(new_obj_w);
                            try cdb.writeCommit(w);
                        }
                    }
                }
            }
        }

        // Obj based context
    } else {
        var context_counter = cetech1.AutoArrayHashMap(cetech1.StrId64, cetech1.ArrayList(*const public.ObjContextMenuI)){};
        defer {
            for (context_counter.values()) |*v| {
                v.deinit(allocator);
            }
            context_counter.deinit(allocator);
        }

        const impls = try apidb.getImpl(allocator, public.ObjContextMenuI);
        defer allocator.free(impls);
        for (impls) |iface| {
            if (iface.is_valid) |is_valid| {
                for (contexts) |context| {
                    if (is_valid(
                        allocator,
                        tab,
                        context,
                        &.{selection},
                        _g.filter,
                    ) catch false) {
                        if (!context_counter.contains(context)) {
                            try context_counter.put(allocator, context, .{});
                        }
                        var array = context_counter.getPtr(context).?;
                        try array.append(allocator, iface);
                    }
                }
            }
        }

        for (contexts) |context| {
            if (context_counter.get(context)) |iface_list| {
                if (iface_list.items.len == 0) continue;

                const label = _g.context2label.get(context) orelse "";
                if (label.len != 0) {
                    coreui.separatorText(label);
                }

                for (iface_list.items) |iface| {
                    if (iface.*.menu) |menu| {
                        try menu(
                            allocator,
                            tab,
                            context,
                            &.{selection},
                            _g.filter,
                        );
                    }
                }
            }
        }
    }
}

const modal_quit = "Quit?###quit_unsaved_modal";
var show_quit_modal = false;
fn quitSaveModal() !void {
    if (coreui.beginPopupModal(
        modal_quit,
        .{ .flags = .{
            .always_auto_resize = true,
            .no_saved_settings = true,
        } },
    )) {
        defer coreui.endPopup();

        coreui.text("Project have unsaved changes.\nWhat do you do?");

        coreui.separator();

        if (coreui.button(coreui.Icons.SaveAll ++ "  " ++ coreui.Icons.Quit ++ "  " ++ "Save and Quit", .{})) {
            show_quit_modal = false;
            coreui.closeCurrentPopup();

            const allocator = tempalloc.create() catch undefined;
            defer tempalloc.destroy(allocator);

            try assetdb.saveAllModifiedAssets(allocator);
            kernel.quit();
        }

        coreui.sameLine(.{});
        if (coreui.button(coreui.Icons.Quit ++ "  " ++ "Quit", .{})) {
            show_quit_modal = false;
            coreui.closeCurrentPopup();
            kernel.quit();
        }

        coreui.sameLine(.{});
        if (coreui.button(coreui.Icons.Nothing ++ "" ++ "Nothing", .{})) {
            show_quit_modal = false;
            if (kernel.getMainWindow()) |w| {
                w.setShouldClose(false);
            }
            coreui.closeCurrentPopup();
        }
    }

    if (show_quit_modal) {
        coreui.openPopup(modal_quit, .{});
    }
}

fn tryQuit() void {
    if (assetdb.isProjectModified()) {
        show_quit_modal = true;
    } else {
        kernel.quit();
    }
}

fn doMainMenu(allocator: std.mem.Allocator) !void {
    if (coreui.beginMainMenuBar()) {
        defer coreui.endMainMenuBar();
        if (coreui.beginMenu(allocator, coreui.Icons.Editor, true, null)) {
            defer coreui.endMenu();

            if (coreui.menuItem(allocator, coreui.Icons.OpenProject ++ "  " ++ "Open project", .{ .enabled = host.supportFileDialog() }, null)) {
                const Task = struct {
                    pub fn exec(_: *@This()) !void {
                        var buf: [256:0]u8 = undefined;
                        const str = try std.fs.cwd().realpath(".", &buf);
                        buf[str.len] = 0;

                        const a = tempalloc.create() catch undefined;
                        defer tempalloc.destroy(a);

                        if (try host.openFileDialog(
                            a,
                            &.{
                                .{ .name = "Project file", .spec = assetdb.ProjectCdb.name ++ ".json" },
                            },
                            @ptrCast(&buf),
                        )) |path| {
                            defer a.free(path);

                            const dir = std.fs.path.dirname(path).?;
                            kernel.openAssetRoot(dir);
                        }
                    }
                };
                const t = try task.schedule(
                    .none,
                    Task{},
                    .{ .affinity = 0 },
                );
                task.wait(t);
            }

            if (coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Save all", .{ .enabled = assetdb.isProjectOpened() and assetdb.isProjectModified() }, null)) {
                try assetdb.saveAllModifiedAssets(allocator);
            }

            if (coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Save project as", .{ .enabled = host.supportFileDialog() }, null)) {
                var buf: [256:0]u8 = undefined;
                const str = try std.fs.cwd().realpath(".", &buf);
                buf[str.len] = 0;
                if (try host.openFolderDialog(allocator, @ptrCast(&buf))) |path| {
                    defer allocator.free(path);
                    try assetdb.saveAsAllAssets(allocator, path);
                    kernel.openAssetRoot(path);
                }
            }

            coreui.separator();

            if (coreui.menuItem(allocator, coreui.Icons.Restart ++ "  " ++ "Restart", .{ .enabled = true }, null)) {
                kernel.restart();
            }

            coreui.separator();

            if (coreui.menuItem(allocator, coreui.Icons.Quit ++ "  " ++ "Quit", .{}, null)) tryQuit();
        }

        try editor_tabs.doTabMainMenu(allocator);

        if (coreui.beginMenu(allocator, coreui.Icons.Settings, true, null)) {
            defer coreui.endMenu();

            if (coreui.beginMenu(allocator, coreui.Icons.FontScale ++ "  " ++ "Scale", true, null)) {
                defer coreui.endMenu();
                var font_scale_main = coreui.getScaleFactor();

                if (coreui.inputF32("###scale", .{ .v = &font_scale_main, .flags = .{ .enter_returns_true = true } })) {
                    coreui.setScaleFactor(font_scale_main);
                }
            }

            if (coreui.beginMenu(allocator, coreui.Icons.TickRate ++ "  " ++ "Kernel tick rate", true, null)) {
                defer coreui.endMenu();

                var rate = kernel.getKernelTickRate();
                if (coreui.inputU32("###kernel_tick_rate", .{ .v = &rate, .flags = .{ .enter_returns_true = true } })) {
                    kernel.setKernelTickRate(rate);
                }
            }

            _ = coreui.menuItemPtr(allocator, coreui.Icons.Colors ++ "  " ++ "Colors", .{ .selected = &_g.enable_colors }, null);
        }

        if (coreui.beginMenu(allocator, coreui.Icons.Debug, true, null)) {
            defer coreui.endMenu();

            _ = coreui.menuItemPtr(allocator, coreui.Icons.UITest ++ "  " ++ "Test UI", .{ .selected = &_g.show_testing_window }, null);

            coreui.separator();

            _ = coreui.menuItemPtr(allocator, "ImGUI demos", .{ .selected = &_g.show_demos }, null);
            _ = coreui.menuItemPtr(allocator, "ImGUI metrics", .{ .selected = &_g.show_metrics }, null);

            coreui.separator();
            if (coreui.menuItem(allocator, coreui.Icons.SaveAll ++ "  " ++ "Force save all", .{ .enabled = assetdb.isProjectOpened() }, null)) {
                try assetdb.saveAllAssets(allocator);
            }
        }

        if (coreui.beginMenu(allocator, coreui.Icons.Help, true, null)) {
            defer coreui.endMenu();

            if (coreui.menuItem(allocator, coreui.Icons.Link ++ "  " ++ "Repository", .{}, null)) {
                try host.openIn(allocator, .OpenURL, REPO_URL);
            }

            if (coreui.menuItem(allocator, coreui.Icons.Link ++ "  " ++ "Docs (online)", .{}, null)) {
                try host.openIn(allocator, .OpenURL, ONLINE_DOCUMENTATION);
            }

            coreui.separator();

            _ = coreui.menuItemPtr(allocator, coreui.Icons.Authors ++ "  " ++ "Authors", .{ .selected = &_g.show_authors }, null);
            _ = coreui.menuItemPtr(allocator, coreui.Icons.Externals ++ "  " ++ "Externals", .{ .selected = &_g.show_external_credits }, null);
        }
    }
}

var coreui_ui_i = coreui.CoreUII.implement(struct {
    pub fn ui(allocator: std.mem.Allocator, kernel_tick: u64, dt: f32) !void {
        _ = coreui.mainDockSpace(coreui.DockNodeFlags{ .passthru_central_node = false });

        try doMainMenu(allocator);
        try quitSaveModal();
        try editor_tabs.doTabs(allocator, kernel_tick, dt);

        if (_g.show_demos) coreui.showDemoWindow();
        if (_g.show_metrics) coreui.showMetricsWindow();

        coreui.showTestingWindow(&_g.show_testing_window);
        coreui.showExternalCredits(&_g.show_external_credits);
        coreui.showAuthors(&_g.show_authors);
    }
});

var editor_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Editor",
    &[_]cetech1.StrId64{
        .fromStr("RenderViewport"),
        .fromStr("GraphVMInit"),
    }, // TODO: =(
    struct {
        pub fn init() !void {
            _g.main_db = kernel.getDb();
            _g.context2label = .{};

            try _g.context2label.put(_allocator, public.Contexts.edit, "Edit");
            try _g.context2label.put(_allocator, public.Contexts.create, "Create");
            try _g.context2label.put(_allocator, public.Contexts.delete, "Delete");
            try _g.context2label.put(_allocator, public.Contexts.open, "Open");
            try _g.context2label.put(_allocator, public.Contexts.debug, "Debug");
        }

        pub fn shutdown() !void {
            _g.context2label.deinit(_allocator);
        }
    },
);

fn kernelQuitHandler() bool {
    tryQuit();
    return true;
}

var open_in_context_menu_i = public.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;

        if (context.id != public.Contexts.open.id) return false;
        var pass = true;

        if (filter) |f| {
            pass = false;
            const impls = apidb.getImpl(allocator, editor_tabs.TabTypeI) catch undefined;
            defer allocator.free(impls);
            for (impls) |iface| {
                if (iface.can_open) |can_open| {
                    if (try can_open(allocator, selection)) {
                        const name = try iface.menu_name();
                        if (coreui.uiFilterPass(allocator, f, name, false) != null) {
                            pass = true;
                        }
                    }
                }
            }
        }

        return pass;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = context;
        _ = tab;

        const impls = apidb.getImpl(allocator, editor_tabs.TabTypeI) catch undefined;
        defer allocator.free(impls);
        for (impls) |iface| {
            if (iface.can_open) |can_open| {
                if (try can_open(allocator, selection)) {
                    const name = try iface.menu_name();

                    var buff: [128]u8 = undefined;
                    const label = std.fmt.bufPrintZ(&buff, "{s}###OpenIn_{s}", .{ name, iface.tab_name }) catch undefined;

                    if (coreui.menuItem(allocator, label, .{}, filter)) {
                        for (selection) |obj| {
                            editor_tabs.openTabWithPinnedObj(iface.tab_hash, obj);
                        }
                    }
                }
            }
        }
    }
});

// Cdb
var AssetTypeIdx: cdb.TypeIdx = undefined;
var ProjectTypeIdx: cdb.TypeIdx = undefined;

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        AssetTypeIdx = assetdb.AssetCdb.typeIdx(db);
        ProjectTypeIdx = assetdb.ProjectCdb.typeIdx(db);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    try host.loadAPI(module_name);
    try kernel.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try profiler.loadAPI(module_name);
    try task.loadAPI(module_name);
    try editor_tabs.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.setOrRemoveZigApi(module_name, public.EditorAPI, &api, load);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &editor_kernel_task, load);
    try apidb.implOrRemove(module_name, coreui.CoreUII, &coreui_ui_i, load);
    try apidb.implOrRemove(module_name, public.ObjContextMenuI, &open_in_context_menu_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    kernel.setCanQuit(kernelQuitHandler);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor(__apidb: *const cetech1.apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {}
