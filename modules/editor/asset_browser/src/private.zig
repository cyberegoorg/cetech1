const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const math = cetech1.math;
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;

const public = @import("asset_browser.zig");

const editor = @import("editor");
const editor_tree = @import("editor_tree");
const editor_assetdb = @import("editor_assetdb");
const editor_tabs = @import("editor_tabs");
const editor_obj_buffer = @import("editor_obj_buffer");

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_asset_browser;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const ASSET_BROWSER_NAME = "ct_editor_asset_browser_tab";

const ASSET_BROWSER_ICON = Icons.FA_FOLDER_TREE;
const FOLDER_ICON = Icons.FA_FOLDER_CLOSED;
const ASSET_ICON = Icons.FA_FILE;

const MAIN_CONTEXTS = &.{
    editor.Contexts.open,
    editor.Contexts.edit,
    editor.Contexts.create,
    editor.Contexts.delete,
    editor.Contexts.debug,
};

const TypeFilter = cetech1.ArraySet(cdb.TypeIdx);

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _uuid: *const cetech1.uuid.UuidAPI = undefined;

var _editor: *const editor.EditorAPI = undefined;
var _tabs: *const editor_tabs.TabsAPI = undefined;

var _editor_tree: *const editor_tree.TreeAPI = undefined;
var _editor_asset: *const editor_assetdb.EditorAssetDBAPI = undefined;
var _editor_obj_buffer: *const editor_obj_buffer.EditorObjBufferAPI = undefined;

const G = struct {
    tab_vt: *editor_tabs.TabTypeI = undefined,
};
var _g: *G = undefined;

var api = public.AssetBrowserAPI{};

const BrowserType = enum {
    Vertical,
    Horizontal,
};

const AssetBrowserTab = struct {
    tab_i: editor_tabs.TabI,
    selection_obj: coreui.Selection,
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
    tags: cdb.ObjId,
    type_filter: TypeFilter = .init(),
    type: BrowserType = .Horizontal,
    horizontal_state: AssetBrowserHorizontal,
};

// Fill editor tab interface
var asset_browser_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = ASSET_BROWSER_NAME,
    .tab_hash = .fromStr(ASSET_BROWSER_NAME),
    .create_on_init = true,
}, struct {
    pub fn menuName() ![:0]const u8 {
        return ASSET_BROWSER_ICON ++ "  " ++ "Asset browser";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return ASSET_BROWSER_ICON ++ "  " ++ "Asset browser";
    }

    // Create new FooTab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        _ = tab_id;
        var tab_inst = try _allocator.create(AssetBrowserTab);

        tab_inst.* = AssetBrowserTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },

            .tags = try assetdb.TagsCdb.createObject(_cdb, _assetdb.getDb()),
            .selection_obj = coreui.Selection.init(_allocator),
            .horizontal_state = .{
                .selected_folder = _assetdb.getRootFolder(),
            },
        };
        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        var tab_o: *AssetBrowserTab = @ptrCast(@alignCast(tab_inst.inst));
        _cdb.destroyObject(tab_o.tags);
        tab_o.selection_obj.deinit();
        tab_o.type_filter.deinit(_allocator);
        _allocator.destroy(tab_o);
    }

    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *AssetBrowserTab = @ptrCast(@alignCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        const selected_count = tab_o.selection_obj.count();
        const first_selected_obj = tab_o.selection_obj.first();

        if (_coreui.beginMenu(allocator, coreui.Icons.ContextMenu ++ "###ObjContextMenu", selected_count != 0, null)) {
            defer _coreui.endMenu();
            _editor.showObjContextMenu(
                allocator,
                tab_o,
                MAIN_CONTEXTS,
                first_selected_obj,
            ) catch undefined;
        }

        if (_coreui.beginMenu(allocator, ASSET_BROWSER_ICON ++ "###AssetBrowserMenu", true, null)) {
            defer _coreui.endMenu();

            _coreui.separatorText("Browser type");

            inline for (@typeInfo(BrowserType).@"enum".fields) |f| {
                const value: BrowserType = @enumFromInt(f.value);
                var checked = tab_o.type == value;
                if (_coreui.checkbox(f.name ++ "###" ++ f.name, .{ .v = &checked })) {
                    tab_o.type = value;
                }
            }
        }

        if (_coreui.beginMenu(allocator, coreui.Icons.AddAsset ++ "###AddAsset", selected_count != 0, null)) {
            defer _coreui.endMenu();

            try _editor.showObjContextMenu(
                allocator,
                tab_o,
                &.{editor.Contexts.create},
                first_selected_obj,
            );
        }
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;
        var tab_o: *AssetBrowserTab = @ptrCast(@alignCast(inst));

        const root_folder = _assetdb.getRootFolder();
        if (root_folder.isEmpty()) {
            _coreui.text("No root folder");
            return;
        }

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);
        switch (tab_o.type) {
            .Vertical => {
                const r = try uiAssetBrowserVertical(
                    allocator,
                    tab_o,
                    MAIN_CONTEXTS,
                    root_folder,
                    &tab_o.selection_obj,
                    &tab_o.filter_buff,
                    tab_o.tags,
                    .{
                        .filter = tab_o.filter,
                        .multiselect = true,
                        .expand_object = false,
                        .only_types = tab_o.type_filter.unmanaged.keys(),
                        .show_status_icons = true,
                    },
                );
                tab_o.filter = r.filter;
            },
            .Horizontal => {
                const r = try uiAssetBrowserHorizontal(
                    allocator,
                    tab_o,
                    MAIN_CONTEXTS,
                    root_folder,
                    &tab_o.selection_obj,
                    &tab_o.filter_buff,
                    tab_o.tags,
                    .{
                        .filter = tab_o.filter,
                        .multiselect = true,
                        .expand_object = false,
                        .only_types = tab_o.type_filter.unmanaged.keys(),
                    },
                    &tab_o.horizontal_state,
                );
                tab_o.filter = r.filter;
            },
        }
    }

    pub fn focused(inst: *editor_tabs.TabO) !void {
        const tab_o: *AssetBrowserTab = @ptrCast(@alignCast(inst));
        _ = tab_o;
    }

    pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
        const tab_o: *AssetBrowserTab = @ptrCast(@alignCast(inst));
        tab_o.filter = null;
        tab_o.selection_obj.clear();
        tab_o.horizontal_state = AssetBrowserHorizontal{
            .selected_folder = _assetdb.getRootFolder(),
        };
    }

    pub fn selectObjFromMenu(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, ignored_obj: cdb.ObjId, allowed_type: cdb.TypeIdx) !cdb.ObjId {
        var label_buff: [1024]u8 = undefined;

        const tab_o: *AssetBrowserTab = @ptrCast(@alignCast(tab));

        const selected_n = tab_o.selection_obj.count();
        const selected_obj = tab_o.selection_obj.first();

        var valid = false;
        var label: [:0]u8 = undefined;

        var real_obj = selected_obj.obj;
        if (_cdb.readObj(selected_obj.obj)) |r| {
            if (selected_obj.obj.type_idx.eql(AssetTypeIdx)) {
                real_obj = assetdb.AssetCdb.readSubObj(_cdb, r, .Object).?;

                var buff: [1024]u8 = undefined;
                const path = _assetdb.getFilePathForAsset(&buff, selected_obj.obj) catch undefined;

                label = std.fmt.bufPrintZ(&label_buff, "browser {d} - {s}" ++ "###{d}", .{ tab_o.tab_i.tabid, path, tab_o.tab_i.tabid }) catch return .{};
            } else {
                label = std.fmt.bufPrintZ(&label_buff, "browser {d}" ++ "###{d}", .{ tab_o.tab_i.tabid, tab_o.tab_i.tabid }) catch return .{};
            }
        } else {
            label = std.fmt.bufPrintZ(&label_buff, "browser {d}" ++ "###{d}", .{ tab_o.tab_i.tabid, tab_o.tab_i.tabid }) catch return .{};
        }
        valid = selected_n == 1 and !real_obj.eql(ignored_obj) and (allowed_type.isEmpty() or real_obj.type_idx.eql(allowed_type));

        if (_coreui.beginMenu(allocator, coreui.Icons.Select ++ "  " ++ "From" ++ "###SelectFrom", true, null)) {
            defer _coreui.endMenu();

            if (_coreui.menuItem(allocator, label, .{ .enabled = valid }, null)) {
                return real_obj;
            }
        }

        return .{};
    }
});

fn isUuid(str: [:0]const u8) bool {
    return (str.len == 36 and str[8] == '-' and str[13] == '-' and str[18] == '-' and str[23] == '-');
}

const UiAssetBrowserResult = struct {
    filter: ?[:0]const u8 = null,
};

fn filterType(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, db: cdb.DbId, allways_folder: bool) !void {
    const tab_o: *AssetBrowserTab = @ptrCast(@alignCast(tab));

    if (_coreui.beginPopup("asset_browser_filter_popup", .{})) {
        defer _coreui.endPopup();
        const impls = try _apidb.getImpl(allocator, editor_assetdb.CreateAssetI);
        defer allocator.free(impls);

        const folder_type_idx = assetdb.FolderCdb.typeIdx(_cdb, db);

        for (impls) |iface| {
            const menu_name = try iface.menu_item();
            var buff: [256:0]u8 = undefined;
            const type_idx = _cdb.getTypeIdx(db, iface.cdb_type).?;
            const type_name = _cdb.getTypeName(db, type_idx).?;
            const label = try std.fmt.bufPrintZ(&buff, "{s}###{s}", .{ menu_name, type_name });

            var selected = tab_o.type_filter.contains(type_idx);

            if (_coreui.menuItemPtr(allocator, label, .{ .selected = &selected }, null)) {
                if (selected) {
                    _ = try tab_o.type_filter.add(_allocator, type_idx);
                    if (allways_folder) _ = try tab_o.type_filter.add(_allocator, folder_type_idx);
                } else {
                    _ = tab_o.type_filter.remove(type_idx);
                    if (allways_folder) {
                        if (tab_o.type_filter.cardinality() == 1) {
                            _ = tab_o.type_filter.remove(folder_type_idx);
                        }
                    }
                }
            }
        }
    }

    if (_coreui.button(coreui.Icons.Filter ++ "###FilterAssetByType", .{})) {
        _coreui.openPopup("asset_browser_filter_popup", .{});
    }
}

fn uiAssetBrowserVertical(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    context: []const cetech1.StrId64,
    root_folder: cdb.ObjId,
    selectection: *coreui.Selection,
    filter_buff: [:0]u8,
    tags_filter: cdb.ObjId,
    args: editor_tree.CdbTreeViewArgs,
) !UiAssetBrowserResult {
    var result = UiAssetBrowserResult{};
    const new_args = args;

    const filter = args.filter;

    const new_filter = _coreui.uiFilter(filter_buff, filter);
    try filterType(allocator, tab, root_folder.db, true);
    _coreui.sameLine(.{});
    const tag_filter_used = try _editor_asset.tagsInput(allocator, tags_filter, assetdb.TagsCdb.propIdx(.Tags), false, null);

    var buff: [128]u8 = undefined;

    const final_label = try std.fmt.bufPrintZ(
        &buff,
        "AssetBrowser",
        .{},
    );

    defer _coreui.endChild();
    if (_coreui.beginChild(final_label, .{ .child_flags = .{ .border = true } })) {
        // Filter
        if (new_filter != null or tag_filter_used) {
            if (new_filter) |f| {
                result.filter = f;
            }

            if (new_filter != null and isUuid(new_filter.?)) {
                if (_uuid.fromStr(new_filter.?)) |uuid| {
                    if (_assetdb.getObjId(uuid)) |asset| {
                        _ = try _editor_tree.cdbTreeView(
                            allocator,
                            tab,
                            context,
                            .{ .top_level_obj = asset, .obj = asset },
                            selectection,
                            0,
                            .{ .expand_object = args.expand_object, .multiselect = args.multiselect, .opened_obj = args.opened_obj },
                        );
                    }
                }
            } else {
                const assets_filtered = _assetdb.filerAsset(allocator, if (args.filter) |f| f else "", tags_filter) catch undefined;
                defer allocator.free(assets_filtered);

                std.sort.insertion(assetdb.FilteredAsset, assets_filtered, {}, assetdb.FilteredAsset.lessThan);
                for (assets_filtered) |asset| {
                    const new_selected = try _editor_tree.cdbTreeView(
                        allocator,
                        tab,
                        context,
                        .{ .top_level_obj = asset.obj, .obj = asset.obj },
                        selectection,
                        0,
                        new_args,
                    );

                    if (new_selected) {
                        const s = selectection.toSlice(allocator).?;
                        defer allocator.free(s);

                        _tabs.propagateSelection(tab, s);
                    }
                }
            }

            // Show clasic tree view
        } else {
            //_coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
            //defer _coreui.popStyleVar(.{});
            const new_selected = try _editor_tree.cdbTreeView(
                allocator,
                tab,
                context,
                .{ .top_level_obj = root_folder, .obj = root_folder },
                selectection,
                0,
                args,
            );
            if (new_selected) {
                const s = selectection.toSlice(allocator).?;
                defer allocator.free(s);

                _tabs.propagateSelection(tab, s);
            }
        }
    }

    return result;
}

const AssetBrowserHorizontal = struct {
    selected_folder: ?cdb.ObjId = null,
    filter: ?[:0]const u8 = null,

    // config
    card_bottom_row_count: u32 = 4,
    card_width: f32 = 128,
    icon_spacing: u32 = 10,
    icon_hit_spacing: u32 = 4,
    text_boreder_spacing: f32 = 4,
    stretch_spacing: bool = true,

    // computed
    card_bottom_height: f32 = 0,
    icon_size: math.Vec2f = .{},
    layout_item_size: math.Vec2f = .{},
    layout_item_step: math.Vec2f = .{},
    layout_item_spacing: f32 = 0.0,
    layout_selectable_spacing: f32 = 0.0,
    layout_outer_padding: f32 = 0.0,
    layout_column_count: u32 = 0,
    layout_line_count: u32 = 0,

    pub fn updateLayoutSizes(self: *AssetBrowserHorizontal, count: u32, avail_width: f32) void {
        // Layout: when not stretching: allow extending into right-most spacing.
        self.layout_item_spacing = @floatFromInt(self.icon_spacing);

        self.card_bottom_height = @as(f32, @floatFromInt(self.card_bottom_row_count)) * _coreui.getFontSize() * _coreui.getScaleFactor();
        self.icon_size = .splat(self.card_width);

        var avail_width_final = avail_width;
        if (self.stretch_spacing == false) avail_width_final += @floor(self.layout_item_spacing * 0.5);

        // Layout: calculate number of icon per line and number of lines
        self.layout_item_size = .{ .x = @floor(self.icon_size.x), .y = @floor(self.icon_size.y) + self.card_bottom_height };
        self.layout_column_count = @intFromFloat(@max((avail_width_final / (self.layout_item_size.x + self.layout_item_spacing)), 1.0));
        self.layout_line_count = (count + self.layout_column_count - 1) / self.layout_column_count;

        // Layout: when stretching: allocate remaining space to more spacing. Round before division, so item_spacing may be non-integer.
        if (self.stretch_spacing and self.layout_column_count > 1)
            self.layout_item_spacing = @floor(avail_width_final - self.layout_item_size.x * @as(f32, @floatFromInt(self.layout_column_count))) / @as(f32, @floatFromInt(self.layout_column_count));

        self.layout_item_step = .{
            .x = self.layout_item_size.x + self.layout_item_spacing,
            .y = self.layout_item_size.y + self.layout_item_spacing,
        };
        self.layout_selectable_spacing = @max(@floor(self.layout_item_spacing) - @as(f32, @floatFromInt(self.icon_hit_spacing)), 0.0);
        self.layout_outer_padding = @floor(self.layout_item_spacing * 0.5);
    }
};

// Asset tree aspect
fn lessThanAsset(_: void, lhs: cdb.ObjId, rhs: cdb.ObjId) bool {
    const l_name = _cdb.readStr(_cdb.readObj(lhs).?, assetdb.AssetCdb.propIdx(.Name)) orelse return false;
    const r_name = _cdb.readStr(_cdb.readObj(rhs).?, assetdb.AssetCdb.propIdx(.Name)) orelse return false;
    return std.ascii.lessThanIgnoreCase(l_name, r_name);
}

fn uiAssetCard(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    item_obj: cdb.ObjId,
    state: *AssetBrowserHorizontal,
    selections: *coreui.Selection,
    draw_list: coreui.DrawList,
    pos: math.Vec2f,
) !void {
    const db = _cdb.getDbFromObjid(item_obj);
    const is_folder = _assetdb.isAssetFolder(item_obj);

    const asset_r = _cdb.readObj(item_obj).?;
    const asset_name = assetdb.AssetCdb.readStr(_cdb, asset_r, .Name) orelse "empty name";
    const obj = _assetdb.getObjForAsset(item_obj).?;
    const type_name = _cdb.getTypeName(db, obj.type_idx).?;

    const asset_color = _editor.getAssetColor(item_obj);

    const selected_item = coreui.SelectionItem{ .top_level_obj = item_obj, .obj = item_obj };
    const item_is_selected = selections.isSelected(.{ .top_level_obj = item_obj, .obj = item_obj });

    _coreui.pushStyleVar2f(.{
        .idx = .item_spacing,
        .v = .{ .x = state.layout_selectable_spacing, .y = state.layout_selectable_spacing },
    });
    {
        defer _coreui.popStyleVar(.{});

        var buff: [128:0]u8 = undefined;
        const asset_label = _editor.buffFormatObjLabel(allocator, &buff, item_obj, .{ .with_id = true }) orelse "Not implemented";

        if (_coreui.selectable(asset_label, .{
            .selected = item_is_selected,
            .flags = .{},
            .w = state.layout_item_size.x,
            .h = state.layout_item_size.y,
        })) {
            try _coreui.handleSelection(allocator, selections, selected_item, false);
            _tabs.propagateSelection(tab, &.{selected_item});
        }
    }
    const item_is_visible = _coreui.isItemVisible(); //_coreui.isRectVisible(state.layout_item_size);

    if (_coreui.beginPopupContextItem()) {
        defer _coreui.endPopup();
        try _editor.showObjContextMenu(allocator, tab, MAIN_CONTEXTS, selected_item);
    }

    if (_coreui.isItemHovered(.{}) and _coreui.isMouseDoubleClicked(.left)) {
        try _editor_obj_buffer.addToFirst(allocator, db, selected_item);
        if (is_folder) {
            state.selected_folder = item_obj;
        }
    }

    try _editor.uiAssetDragDropSource(allocator, item_obj);
    try _editor.uiAssetDragDropTarget(allocator, tab, item_obj, null);

    const visual_aspect = _cdb.getAspect(editor.UiVisualAspect, db, item_obj.type_idx);

    if (item_is_visible) {
        const card_min: math.Vec2f = .{ .x = pos.x - 1, .y = pos.y - 1 };
        const card_max: math.Vec2f = .{ .x = card_min.x + state.layout_item_size.x + 2, .y = card_min.y + state.layout_item_size.y + 2 };
        const card_size: math.Vec2f = state.layout_item_size;
        const card_size_half: math.Vec2f = card_size.div(.splat(2));

        const icon_bg_color = math.SRGBA{ .r = 35, .g = 35, .b = 35, .a = 220 };
        const bottom_bg_color = math.SRGBA{ .r = 35, .g = 35, .b = 35, .a = 150 };

        if (!is_folder) {
            draw_list.addRectFilled(.{
                .pmin = card_min,
                .pmax = card_min.add(.{ .x = state.layout_item_size.x, .y = state.icon_size.y }),
                .col = icon_bg_color,
            }); // Background color

            draw_list.addRectFilled(.{
                .pmin = card_min.add(.{ .x = 0, .y = state.icon_size.y }),
                .pmax = card_min.add(.{ .x = state.layout_item_size.x, .y = state.icon_size.y + state.card_bottom_height }),
                .col = bottom_bg_color,
            }); // Background color
        }

        // Icons
        if (visual_aspect) |aspect| {

            // Status icon
            if (aspect.ui_status_icons) |icons| {
                var icon_buf: [16:0]u8 = undefined;
                const icon = try icons(&icon_buf, allocator, item_obj);

                _coreui.pushFontSize(8);
                defer _coreui.popFontSize();

                draw_list.addTextUnformatted(
                    .{ .x = card_min.x + state.text_boreder_spacing, .y = card_min.y },
                    .fromColor4f(asset_color),
                    icon,
                );
            }

            if (aspect.ui_icons) |icons| {
                var icon_buf: [16:0]u8 = undefined;
                const icon = try icons(&icon_buf, allocator, item_obj);
                const icon_size = @max(state.icon_size.x, state.icon_size.y) / 1.5;
                _coreui.pushFontSize(icon_size);
                defer _coreui.popFontSize();

                const font_size = _coreui.calcTextSize(icon, .{});
                const half_font = font_size.div(.splat(2));

                draw_list.addTextUnformatted(
                    .{ .x = card_min.x + state.icon_size.x / 2 - half_font.x, .y = card_min.y + state.icon_size.y / 2 - half_font.y },
                    .fromColor4f(asset_color),
                    icon,
                );
            }
        }

        const display_label = true;
        if (display_label) {
            // Asset name
            const max_char_in_line: usize = @intFromFloat(@floor(state.layout_item_size.x / (_coreui.getFontSize() / 2)));
            const line_count = @min(@divFloor(asset_name.len, max_char_in_line) + 1, 2);

            var begin: usize = 0;
            for (0..line_count) |line_idx| {
                const len = if (asset_name[begin..].len > max_char_in_line) max_char_in_line else asset_name[begin..].len;
                const txt = asset_name[begin .. begin + len];

                if (!is_folder) {
                    draw_list.addTextUnformatted(
                        .{
                            .x = card_min.x + state.text_boreder_spacing,
                            .y = (card_min.y + state.icon_size.y) + (_coreui.getFontSize() * @as(f32, @floatFromInt(line_idx))),
                        },
                        .fromColor4f(asset_color),
                        txt,
                    );
                } else {
                    const t_size = _coreui.calcTextSize(txt, .{});
                    draw_list.addTextUnformatted(
                        .{
                            .x = card_min.x + card_size_half.x - t_size.x / 2,
                            .y = (card_min.y + state.icon_size.y) + (_coreui.getFontSize() * @as(f32, @floatFromInt(line_idx))),
                        },
                        .fromColor4f(asset_color),
                        txt,
                    );
                }

                begin += len;
            }

            if (!is_folder) {
                try uiDrawTags(
                    allocator,
                    item_obj,
                    .{
                        .x = card_min.x + state.text_boreder_spacing,
                        .y = card_max.y - _coreui.getFontSize() * 2,
                    },
                    draw_list,
                    assetdb.AssetCdb.propIdx(.Tags),
                );

                // Asset type
                draw_list.addTextUnformatted(
                    .{
                        .x = card_min.x + state.text_boreder_spacing,
                        .y = (card_max.y - _coreui.getFontSize() * _coreui.getScaleFactor()),
                    },
                    .fromColor4f(asset_color),
                    type_name,
                );
            } else {
                try uiDrawTags(
                    allocator,
                    item_obj,
                    .{
                        .x = card_min.x + state.text_boreder_spacing,
                        .y = (card_min.y + state.icon_size.y) - _coreui.getFontSize() * 1,
                    },
                    draw_list,
                    assetdb.AssetCdb.propIdx(.Tags),
                );
            }
        }
    }
}

fn uiDrawTags(allocator: std.mem.Allocator, obj: cdb.ObjId, pos: math.Vec2f, draw_list: coreui.DrawList, tag_prop_idx: u32) !void {
    const obj_r = _cdb.readObj(obj) orelse return;

    if (_cdb.readRefSet(obj_r, tag_prop_idx, allocator)) |tags| {
        var tag_buf: [128:0]u8 = undefined;
        const tag_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag, .{});
        const icon_size = _coreui.calcTextSize(tag_lbl, .{});

        for (tags, 0..) |tag, idx| {
            const tag_r = _cdb.readObj(tag) orelse continue;

            var tag_color: math.Color4f = .white;
            if (_editor.isColorsEnabled()) {
                if (assetdb.TagCdb.readSubObj(_cdb, tag_r, .Color)) |c| {
                    tag_color = cetech1.cdb_types.Color4fCdb.f.to(_cdb, c);
                }
            }

            const icon_pos = math.Vec2f{
                .x = pos.x + (icon_size.x) * @as(f32, @floatFromInt(idx)),
                .y = pos.y,
            };

            const mouse_pos = _coreui.getMousePos();
            const tag_rect = math.Rectf{
                .x = icon_pos.x,
                .y = icon_pos.y,
                .w = icon_size.x,
                .h = icon_size.y,
            };

            if (tag_rect.isPointIn(mouse_pos)) {
                _coreui.beginTooltip();
                defer _coreui.endTooltip();

                const tag_name = assetdb.TagCdb.readStr(_cdb, tag_r, .Name) orelse "No name =/";

                const name_lbl = try std.fmt.bufPrintZ(&tag_buf, coreui.Icons.Tag ++ "  " ++ "{s}", .{tag_name});
                _coreui.text(name_lbl);

                const tag_asset = _assetdb.getAssetForObj(tag).?;
                const desription = assetdb.AssetCdb.readStr(_cdb, _cdb.readObj(tag_asset).?, .Description);
                if (desription) |d| {
                    _coreui.text(d);
                }
            }

            draw_list.addTextUnformatted(icon_pos, .fromColor4f(tag_color), tag_lbl);
        }
    }
}

fn uiAssetBrowserCards(
    allocator: std.mem.Allocator,
    assets: []const cdb.ObjId,
    tab: *editor_tabs.TabO,
    selections: *coreui.Selection,
    state: *AssetBrowserHorizontal,
    avail_width: f32,
) !void {
    state.updateLayoutSizes(@intCast(assets.len), avail_width);

    if (assets.len == 0) return;

    // Calculate and store start position.
    var start_pos = _coreui.getCursorScreenPos();
    start_pos = .{
        .x = start_pos.x + state.layout_outer_padding,
        .y = start_pos.y + state.layout_outer_padding,
    };
    _coreui.setCursorScreenPos(start_pos);

    const column_count = state.layout_column_count;
    const draw_list = _coreui.getWindowDrawList();

    var clipper = _coreui.createClipper();
    clipper.begin(@intCast(state.layout_line_count), state.layout_item_step.y);
    defer clipper.end();

    while (clipper.step()) {
        for (@intCast(clipper.DisplayStart)..@intCast(clipper.DisplayEnd)) |line_idx| {
            const item_min_idx_for_current_line = line_idx * column_count;
            const item_max_idx_for_current_line = @min((line_idx + 1) * column_count, assets.len);
            for (item_min_idx_for_current_line..item_max_idx_for_current_line) |item_idx| {
                const item_obj = assets[item_idx];
                // _coreui.pushObjUUID(item_obj);
                // defer _coreui.popId();

                const pos: math.Vec2f = .{
                    .x = start_pos.x + @as(f32, @floatFromInt(item_idx % column_count)) * state.layout_item_step.x,
                    .y = start_pos.y + @as(f32, @floatFromInt(line_idx)) * state.layout_item_step.y,
                };
                _coreui.setCursorScreenPos(pos);

                try uiAssetCard(
                    allocator,
                    tab,
                    item_obj,
                    state,
                    selections,
                    draw_list,
                    pos,
                );
            }
        }
    }
}

fn uiAssetBrowserHorizontal(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    contexts: []const cetech1.StrId64,
    root_folder: cdb.ObjId,
    selections: *coreui.Selection,
    filter_buff: [:0]u8,
    tags_filter: cdb.ObjId,
    args: editor_tree.CdbTreeViewArgs,
    state: *AssetBrowserHorizontal,
) !UiAssetBrowserResult {
    var result = UiAssetBrowserResult{};

    var buff: [128]u8 = undefined;

    {
        const folder_child_label = try std.fmt.bufPrintZ(
            &buff,
            "AssetBrowserFolders",
            .{},
        );

        defer _coreui.endChild();
        if (_coreui.beginChild(
            folder_child_label,
            .{
                .w = 170,
                .child_flags = .{
                    .border = true,
                    .resize_x = true,
                },
                .window_flags = .{ .no_saved_settings = true },
            },
        )) {
            var folder_args = args;
            folder_args.only_types = &.{FolderTypeIdx};

            var folder_selection = coreui.Selection.init(allocator);
            defer folder_selection.deinit();
            try folder_selection.add(&.{.{ .obj = state.selected_folder.?, .top_level_obj = state.selected_folder.? }});

            const new_selected = try _editor_tree.cdbTreeView(
                allocator,
                tab,
                contexts,
                .{ .top_level_obj = root_folder, .obj = root_folder },
                &folder_selection,
                0,
                folder_args,
            );
            if (new_selected) {
                const s = folder_selection.toSlice(allocator).?;
                defer allocator.free(s);
                state.selected_folder = s[0].obj;
                try _coreui.handleSelection(allocator, selections, s[0], false);
                // _tabs.propagateSelection(tab, s);
            }
        }
    }

    _coreui.sameLine(.{});

    {
        defer _coreui.endChild();
        if (_coreui.beginChild(
            "AssetBrowserAssets",
            .{
                .child_flags = .{ .border = false },
                .window_flags = .{ .no_saved_settings = true },
            },
        )) {
            var new_filter: ?[:0]const u8 = null;
            var tag_filter_used = false;

            // Filter tab
            {
                defer _coreui.endChild();
                if (_coreui.beginChild(
                    "AssetBrowserAssetsFilterBar",
                    .{
                        .child_flags = .{ .border = false, .auto_resize_y = true },
                        .window_flags = .{ .no_saved_settings = true },
                    },
                )) {
                    try filterType(allocator, tab, root_folder.db, false);

                    _coreui.sameLine(.{});
                    tag_filter_used = try _editor_asset.tagsInput(allocator, tags_filter, assetdb.TagsCdb.propIdx(.Tags), false, null);

                    _coreui.sameLine(.{});
                    const filter = args.filter;
                    new_filter = _coreui.uiFilter(filter_buff, filter);
                }
            }

            // Content tab
            {
                defer _coreui.endChild();
                if (_coreui.beginChild(
                    "AssetBrowserAssetsContent",
                    .{
                        .child_flags = .{ .border = true },
                        .window_flags = .{ .no_saved_settings = true },
                    },
                )) {
                    // Filter
                    if (new_filter != null or tag_filter_used) {
                        if (new_filter) |f| {
                            result.filter = f;
                        }

                        // Filter by uuid
                        if (new_filter != null and isUuid(new_filter.?)) {
                            if (_uuid.fromStr(new_filter.?)) |uuid| {
                                if (_assetdb.getObjId(uuid)) |asset| {
                                    try uiAssetBrowserCards(
                                        allocator,
                                        &.{asset},
                                        tab,
                                        selections,
                                        state,
                                        _coreui.getContentRegionAvail().x,
                                    );
                                }
                            }
                        } else {
                            const assets_filtered = _assetdb.filerAsset(allocator, if (args.filter) |f| f else "", tags_filter) catch undefined;
                            defer allocator.free(assets_filtered);

                            std.sort.insertion(assetdb.FilteredAsset, assets_filtered, {}, assetdb.FilteredAsset.lessThan);

                            var assets = try cetech1.cdb.ObjIdList.initCapacity(allocator, assets_filtered.len);
                            defer assets.deinit(allocator);
                            for (assets_filtered) |asset| {
                                if (!editor_assetdb.filterOnlyTypes(args.only_types, _assetdb.getObjForAsset(asset.obj).?)) continue;

                                assets.appendAssumeCapacity(asset.obj);
                            }

                            try uiAssetBrowserCards(
                                allocator,
                                assets.items,
                                tab,
                                selections,
                                state,
                                _coreui.getContentRegionAvail().x,
                            );
                        }

                        // Show clasic tree view
                    } else {
                        var folders = cetech1.cdb.ObjIdList{};
                        defer folders.deinit(allocator);

                        var assets = cetech1.cdb.ObjIdList{};
                        defer assets.deinit(allocator);

                        const folder_obj = _assetdb.getObjForAsset(state.selected_folder.?).?;
                        const set = try _cdb.getReferencerSet(allocator, folder_obj);
                        defer allocator.free(set);

                        for (set) |ref_obj| {
                            if (ref_obj.type_idx.eql(AssetTypeIdx)) {
                                if (!editor_assetdb.filterOnlyTypes(args.only_types, _assetdb.getObjForAsset(ref_obj).?)) continue;

                                if (_assetdb.isAssetFolder(ref_obj)) {
                                    try folders.append(allocator, ref_obj);
                                } else {
                                    try assets.append(allocator, ref_obj);
                                }
                            }
                        }

                        std.sort.insertion(cdb.ObjId, folders.items, {}, lessThanAsset);
                        std.sort.insertion(cdb.ObjId, assets.items, {}, lessThanAsset);

                        var all_assets = try cetech1.cdb.ObjIdList.initCapacity(allocator, folders.items.len + assets.items.len);
                        defer all_assets.deinit(allocator);

                        all_assets.appendSliceAssumeCapacity(folders.items);
                        all_assets.appendSliceAssumeCapacity(assets.items);
                        if (all_assets.items.len == 0) return .{};

                        try uiAssetBrowserCards(
                            allocator,
                            all_assets.items,
                            tab,
                            selections,
                            state,
                            _coreui.getContentRegionAvail().x,
                        );
                    }
                }
            }
        }
    }

    return result;
}

// Tests
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_filter_assets_and_folders",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    // // ctx.menuAction(_coreui, .Check, "###AssetBrowserMenu/###Vertical");

                    ctx.itemInputStrValue(_coreui, "**/###filter", "foo");

                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_core.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_core2.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_subcore.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###core_subfolder", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_filter_assets_by_uuid",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    // // ctx.menuAction(_coreui, .Check, "###AssetBrowserMenu/###Vertical");

                    ctx.itemInputStrValue(_coreui, "**/###filter", "018b5c74-06f7-740e-be81-d727adec5fb4");

                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_subcore.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_filter_assets_by_tag",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    // // ctx.menuAction(_coreui, .Check, "###AssetBrowserMenu/###Vertical");

                    ctx.itemAction(_coreui, .Click, "**/###AddTags", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/018e0348-b358-779f-b40c-7d34d3fca2a7/###Tag", .{}, null);

                    ctx.itemAction(_coreui, .DoubleClick, "**/###core", .{}, null);
                    ctx.itemAction(_coreui, .DoubleClick, "**/###foo_subcore.ct_foo_asset", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "AssetBrowser",
            "should_move_assets_to_folder_by_drag_and_drop",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_move");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    // // ctx.menuAction(_coreui, .Check, "###AssetBrowserMenu/###Vertical");

                    //ctx.itemAction(_coreui, .Click, "**/###asset_a.ct_foo_asset", .{}, null);
                    ctx.yield(_coreui, 1);

                    ctx.dragAndDrop(
                        _coreui,
                        "**/###asset_a.ct_foo_asset",
                        "**/###folder_b",
                        //"//###ct_editor_asset_browser_tab_1/**/###folder_a",
                        .left,
                    );
                }
            },
        );
    }
});

// Cdb
var AssetTypeIdx: cdb.TypeIdx = undefined;
var FolderTypeIdx: cdb.TypeIdx = undefined;
var ProjectTypeIdx: cdb.TypeIdx = undefined;

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        AssetTypeIdx = assetdb.AssetCdb.typeIdx(_cdb, db);
        FolderTypeIdx = assetdb.FolderCdb.typeIdx(_cdb, db);
        ProjectTypeIdx = assetdb.ProjectCdb.typeIdx(_cdb, db);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;

    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;

    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _tabs = apidb.getZigApi(module_name, editor_tabs.TabsAPI).?;

    _editor_tree = apidb.getZigApi(module_name, editor_tree.TreeAPI).?;
    _editor_asset = apidb.getZigApi(module_name, editor_assetdb.EditorAssetDBAPI).?;
    _editor_obj_buffer = apidb.getZigApi(module_name, editor_obj_buffer.EditorObjBufferAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, ASSET_BROWSER_NAME, asset_browser_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &asset_browser_tab, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.AssetBrowserAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_browser(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
