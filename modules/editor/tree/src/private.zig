const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_tree.zig");

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const math = cetech1.math;
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;

const editor = @import("editor");
const editor_inspector = @import("editor_inspector");
const editor_tabs = @import("editor_tabs");

const Icons = coreui.CoreIcons;

const module_name = .editor_tree;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

const PROTOTYPE_PROPERTY_COLOR: math.Color4f = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 };
const PROTOTYPE_PROPERTY_OVERIDED_COLOR: math.Color4f = .{ .g = 0.8, .b = 1.0, .a = 1.0 };
const INSIATED_COLOR: math.Color4f = .{ .r = 1.0, .g = 0.6, .a = 1.0 };
const REMOVED_COLOR: math.Color4f = .{ .r = 0.7, .a = 1.0 };

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;
const profiler = cetech1.profiler;

// Global state
const G = struct {};
var _g: *G = undefined;

const api = public.TreeAPI{
    .cdbObjTree = cdbObjTree,
    .cdbTreeView = cdbTreeView,
    .cdbTreeNode = cdbTreeNode,
    .cdbObjTreeNode = cdbObjTreeNode,
    .cdbTreePop = cdbTreePop,
};

fn cdbTreeNode(
    label: [:0]const u8,
    default_open: bool,
    no_push: bool,
    selected: bool,
    leaf: bool,
    args: public.CdbTreeViewArgs,
) bool {
    _ = args;
    return coreui.treeNodeFlags(label, .{
        .open_on_arrow = true,
        .open_on_double_click = false,
        .default_open = default_open,
        .no_tree_push_on_open = no_push,
        .selected = selected,
        .leaf = leaf,
        .draw_lines_full = true,
    });
}

fn cdbObjTreeNode(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    contexts: []const cetech1.StrId64,
    selection: *coreui.Selection,
    obj: coreui.SelectedObj,
    default_open: bool,
    no_push: bool,
    leaf: bool,
    args: public.CdbTreeViewArgs,
) bool {
    // _ = args;
    const asset_label = editor.formatObjLabel(allocator, obj.obj, null, .{
        .with_txt = true,
        .with_icon = true,
        .with_id = true,
        .with_status_icons = args.show_status_icons,
    }) catch undefined;
    defer allocator.free(asset_label);

    const asset_color = editor.getAssetColor(obj.obj);
    coreui.pushStyleColor4f(.{ .idx = .text, .c = asset_color });

    const open = coreui.treeNodeFlags(asset_label, .{
        .open_on_arrow = true,
        .open_on_double_click = false,
        .default_open = default_open,
        .no_tree_push_on_open = no_push,
        .selected = selection.isSelected(obj),
        .leaf = leaf,
        .draw_lines_full = true,
    });
    coreui.popStyleColor(.{});

    const db = cdb.getDbFromObjid(obj.obj);
    if (cdb.getAspect(editor.UiVisualAspect, db, obj.obj.type_idx)) |aspect| {
        if (aspect.ui_tooltip) |tooltip| {
            if (coreui.isItemHovered(.{})) {
                if (coreui.beginTooltip()) {
                    defer coreui.endTooltip();
                    tooltip(allocator, obj.obj) catch undefined;
                }
            }
        }
    }

    if (coreui.beginPopupContextItem()) {
        defer coreui.endPopup();
        editor.showObjContextMenu(allocator, tab, contexts, selection.first()) catch undefined;
    }

    editor.uiAssetDragDropSource(allocator, obj.obj) catch undefined;
    editor.uiAssetDragDropTarget(allocator, tab, obj.obj, null) catch undefined;

    return open;
}

fn cdbTreePop() void {
    return coreui.treePop();
}
fn formatedPropNameToBuff(buf: []u8, prop_name: [:0]const u8) ![]u8 {
    var split = std.mem.splitAny(u8, prop_name, "_");
    const first = split.first();

    var writer: std.Io.Writer = .fixed(buf);

    var tmp_buf: [128]u8 = undefined;

    var it: ?[]const u8 = first;
    while (it) |word| : (it = split.next()) {
        var word_formated = try std.fmt.bufPrint(&tmp_buf, "{s}", .{word});

        if (word.ptr == first.ptr) {
            word_formated[0] = std.ascii.toUpper(word_formated[0]);
        }

        _ = try writer.write(word_formated);
        _ = try writer.write(" ");
    }

    const writen = writer.end;
    return buf[0 .. writen - 1];
}

fn isLeaf(db: cdb.DbId, obj: cdb.ObjId) bool {
    if (cdb.getTypePropDef(db, obj.type_idx)) |prop_defs| {
        for (prop_defs) |prop| {
            switch (prop.type) {
                .SUBOBJECT_SET => {
                    return false;
                },
                .REFERENCE_SET => {
                    return false;
                },
                .SUBOBJECT => {
                    return false;
                },
                else => {},
            }
        }
    }

    return true;
}

pub fn filterOnlyTypes(only_types: ?[]const cdb.TypeIdx, obj: cdb.ObjId) bool {
    if (only_types) |ot| {
        if (ot.len != 0) {
            for (ot) |o| {
                if (obj.type_idx.eql(o)) return true;
            }
            return false;
        }
    }

    return true;
}

fn cdbTreeView(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    context: []const cetech1.StrId64,
    obj: coreui.SelectedObj,
    selection: *coreui.Selection,
    depth: u32,
    args: public.CdbTreeViewArgs,
) !bool {
    if (args.filter) |filter| {
        _ = filter;
    } else {
        return cdbObjTree(allocator, tab, context, obj, selection, depth, args);
    }

    return false;
}

fn cdbObjTree(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    context: []const cetech1.StrId64,
    obj: coreui.SelectedObj,
    selection: *coreui.Selection,
    depth: u32,
    args: public.CdbTreeViewArgs,
) !bool {
    var zone_ctx = profiler.ZoneN(@src(), "cdbTreeView");
    defer zone_ctx.End();

    const db = cdb.getDbFromObjid(obj.obj);

    // if exist aspect use it
    const ui_aspect = cdb.getAspect(public.UiTreeAspect, db, obj.obj.type_idx);

    var result = false;

    if (ui_aspect) |aspect| {
        return aspect.ui_tree(allocator, tab, context, obj, selection, depth, args);
    }

    if (!args.ignored_object.isEmpty() and args.ignored_object.eql(obj.obj)) {
        return result;
    }

    if (!args.expand_object and !filterOnlyTypes(args.only_types, obj.obj)) {
        return result;
    }

    const obj_r = cdb.readObj(obj.obj) orelse return false;

    var root_open = true;
    if (args.show_root) {
        root_open = cdbObjTreeNode(
            allocator,
            tab,
            context,
            selection,
            obj,
            false,
            false,
            false,
            args,
        );
        if (coreui.isItemActivated()) {
            try coreui.handleSelection(allocator, selection, obj, args.multiselect);
            result = true;
        }
    }

    defer {
        if (args.show_root and root_open) {
            cdbTreePop();
        }
    }

    if (!root_open) return result;

    if (!args.expand_object) return result;

    // Do generic tree walk
    const prop_defs = cdb.getTypePropDef(db, obj.obj.type_idx).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    for (prop_defs, 0..) |prop_def, idx| {
        const visible = coreui.isRectVisible(.{ .x = coreui.getContentRegionAvail().x, .y = coreui.getFontSize() });

        const prop_idx: u32 = @truncate(idx);
        const prop_name = if (visible) try formatedPropNameToBuff(&prop_name_buff, prop_def.name) else "";

        switch (prop_def.type) {
            .SUBOBJECT => {
                var zz = profiler.ZoneN(@src(), "cdbTreeView - subobject");
                defer zz.End();

                var subobj: cdb.ObjId = undefined;

                subobj = cdb.readSubObj(cdb.readObj(obj.obj).?, prop_idx) orelse continue;

                const label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}###{s}",
                    .{ prop_name, prop_def.name },
                );

                const set_state = if (visible) cdb.getRelation(obj.top_level_obj, obj.obj, prop_idx, null) else .NotOwned;
                const set_color = editor.getStateColor(set_state);

                const o = coreui.SelectedObj{ .top_level_obj = obj.top_level_obj, .obj = subobj, .prop_idx = prop_idx, .parent_obj = obj.obj };
                coreui.pushStyleColor4f(.{ .idx = .text, .c = set_color });
                const open = api.cdbTreeNode(
                    label,
                    depth < args.max_autopen_depth,
                    false,
                    selection.isSelected(o), // or (args.sr.prop_idx == prop_idx and args.sr.in_set_obj.isEmpty()),
                    isLeaf(db, subobj),
                    args,
                );
                coreui.popStyleColor(.{});

                if (coreui.beginPopupContextItem()) {
                    defer coreui.endPopup();
                    try editor.showObjContextMenu(allocator, tab, &.{editor.Contexts.create}, o);
                }

                if (coreui.isItemActivated()) {
                    try coreui.handleSelection(allocator, selection, o, args.multiselect);
                    result = true;
                }

                if (open) {
                    defer api.cdbTreePop();
                    const r = try cdbObjTree(allocator, tab, context, o, selection, depth + 1, args);
                    if (r) result = r;
                }
            },
            .SUBOBJECT_SET => {
                var zz = profiler.ZoneN(@src(), "cdbTreeView - subobject set");
                defer zz.End();

                const prop_label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}  {s}###{s}",
                    .{ prop_name, coreui.Icons.List, prop_def.name },
                );

                const prop_state = if (visible) cdb.getRelation(obj.top_level_obj, obj.obj, prop_idx, null) else .NotOwned;
                const prop_color = editor.getStateColor(prop_state);

                coreui.pushStyleColor4f(.{
                    .idx = .text,
                    .c = prop_color,
                });

                const o = coreui.SelectedObj{ .top_level_obj = obj.top_level_obj, .obj = obj.obj, .prop_idx = prop_idx };

                const flaten_child = cdb.getPropertyAspect(public.UiTreeFlatenPropertyAspect, db, obj.obj.type_idx, prop_idx) != null;

                const open = if (!flaten_child) api.cdbTreeNode(prop_label, depth < args.max_autopen_depth, false, selection.isSelected(o), false, args) else true;
                coreui.popStyleColor(.{});

                if (!flaten_child) {
                    if (coreui.isItemActivated()) {
                        try coreui.handleSelection(allocator, selection, o, args.multiselect);
                        result = true;
                    }

                    if (coreui.beginPopupContextItem()) {
                        defer coreui.endPopup();
                        try editor.showObjContextMenu(allocator, tab, &.{editor.Contexts.create}, o);
                    }
                }

                if (open) {
                    defer if (!flaten_child) api.cdbTreePop();

                    // added
                    var set: ?[]cdb.ObjId = undefined;
                    set = try cdb.readSubObjSet(obj_r, prop_idx, allocator);

                    var inisiated_prototypes = std.AutoHashMap(cdb.ObjId, void).init(allocator);
                    defer inisiated_prototypes.deinit();

                    if (!flaten_child) {
                        try editor.uiAssetDragDropTarget(allocator, tab, obj.obj, prop_idx);
                    }

                    if (set) |s| {
                        defer allocator.free(set.?);

                        const ui_sort_aspect = cdb.getPropertyAspect(editor.UiSetSortPropertyAspect, db, obj.obj.type_idx, prop_idx);
                        if (ui_sort_aspect) |aspect| {
                            var zzz = profiler.ZoneN(@src(), "cdbTreeView - subobject set sort");
                            defer zzz.End();
                            try aspect.sort(allocator, s);
                        }

                        for (s, 0..) |subobj, set_idx| {
                            var zzz = profiler.ZoneN(@src(), "cdbTreeView - subobject set item");
                            defer zzz.End();

                            const label = try editor.formatObjLabel(allocator, subobj, set_idx, .{
                                .with_txt = true,
                                .with_icon = true,
                                .with_id = true,
                                .uuid_id = true,
                                .with_status_icons = args.show_status_icons,
                            });
                            defer allocator.free(label);

                            const is_inisiated = cdb.isIinisiated(obj_r, prop_idx, cdb.readObj(subobj).?);
                            if (is_inisiated) {
                                try inisiated_prototypes.put(cdb.getPrototype(cdb.readObj(subobj).?), {});
                            }

                            const visible_item = coreui.isRectVisible(.{
                                .x = coreui.getContentRegionAvail().x,
                                .y = coreui.getFontSize(),
                            });

                            const set_state = if (visible_item) cdb.getRelation(obj.top_level_obj, obj.obj, prop_idx, subobj) else .NotOwned;
                            const set_color = editor.getStateColor(set_state);

                            coreui.pushStyleColor4f(.{ .idx = .text, .c = set_color });
                            const oo = coreui.SelectedObj{
                                .top_level_obj = obj.top_level_obj,
                                .obj = subobj,
                                .in_set_obj = subobj,
                                .prop_idx = prop_idx,
                                .parent_obj = obj.obj,
                            };
                            const open_inset = api.cdbTreeNode(
                                label,
                                depth < args.max_autopen_depth,
                                false,
                                selection.isSelected(oo),
                                isLeaf(db, subobj),
                                args,
                            );
                            coreui.popStyleColor(.{});

                            if (coreui.isItemActivated()) {
                                try coreui.handleSelection(allocator, selection, oo, args.multiselect);
                                result = true;
                            }

                            if (coreui.beginPopupContextItem()) {
                                defer coreui.endPopup();
                                try editor.showObjContextMenu(allocator, tab, &.{editor.Contexts.create}, oo);
                            }

                            if (open_inset) {
                                const r = try cdbObjTree(allocator, tab, context, oo, selection, depth + 1, args);
                                if (r) result = r;
                                api.cdbTreePop();
                            }
                        }
                    }

                    // removed
                    var removed_set: ?[]const cdb.ObjId = undefined;
                    removed_set = cdb.readSubObjSetRemoved(cdb.readObj(obj.obj).?, prop_idx);

                    if (removed_set) |s| {
                        for (s, 0..) |subobj, set_idx| {
                            _ = set_idx;
                            if (inisiated_prototypes.contains(subobj)) continue;

                            var label: ?[:0]u8 = null;
                            if (assetdb.getUuid(subobj)) |uuid| {
                                label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Deleted ++ "  " ++ "{f}###{f}", .{ uuid, uuid });
                            } else {
                                label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Deleted ++ "  " ++ "{d}:{d}###{d}{d}", .{ subobj.id, subobj.type_idx.idx, subobj.id, subobj.type_idx.idx });
                            }

                            const oo = coreui.SelectedObj{ .top_level_obj = obj.top_level_obj, .obj = subobj };

                            if (editor.isColorsEnabled()) coreui.pushStyleColor4f(.{ .idx = .text, .c = REMOVED_COLOR });
                            const open_inset = coreui.treeNodeFlags(
                                label.?,
                                .{
                                    .leaf = true,
                                    .selected = selection.isSelected(oo),
                                },
                            );
                            if (editor.isColorsEnabled()) coreui.popStyleColor(.{});

                            if (open_inset) {
                                defer coreui.treePop();

                                if (coreui.isItemActivated()) {
                                    try coreui.handleSelection(allocator, selection, oo, args.multiselect);
                                }

                                if (coreui.beginPopupContextItem()) {
                                    defer coreui.endPopup();
                                    if (coreui.menuItem(allocator, coreui.Icons.Revive ++ "  " ++ "Restore deleted", .{}, null)) {
                                        cdb.restoreDeletedInSet(obj_r, prop_idx, cdb.readObj(subobj).?);
                                    }
                                }
                            }
                        }
                    }
                }
            },

            else => {},
        }
    }

    return result;
}

var ProjectTypeIdx: cdb.TypeIdx = undefined;

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: cdb.DbId) !void {
        ProjectTypeIdx = cetech1.assetdb.ProjectCdb.typeIdx(db_);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try editor.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try profiler.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.setOrRemoveZigApi(module_name, public.TreeAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_tree(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}

// Assert C api == C api in zig.
comptime {}
