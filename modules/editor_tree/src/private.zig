const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_tree.zig");

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const strid = cetech1.strid;
const cdb = cetech1.cdb;

const editor = @import("editor");
const editor_inspector = @import("editor_inspector");

const Icons = coreui.CoreIcons;

const module_name = .editor_tree;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const PROTOTYPE_PROPERTY_COLOR = .{ 0.5, 0.5, 0.5, 1.0 };
const PROTOTYPE_PROPERTY_OVERIDED_COLOR = .{ 0.0, 0.8, 1.0, 1.0 };
const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };
const REMOVED_COLOR = .{ 0.7, 0.0, 0.0, 1.0 };

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _assetdb: *const cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

// Global state
const G = struct {};
var _g: *G = undefined;

var api = public.TreeAPI{
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
    return _coreui.treeNodeFlags(label, .{
        .open_on_arrow = true,
        .open_on_double_click = false,
        .default_open = default_open,
        .no_tree_push_on_open = no_push,
        .selected = selected,
        .leaf = leaf,
    });
}

fn cdbObjTreeNode(
    allocator: std.mem.Allocator,
    db: cdb.Db,
    tab: *editor.TabO,
    contexts: []const strid.StrId64,
    selection: cdb.ObjId,
    obj: cdb.ObjId,
    default_open: bool,
    no_push: bool,
    leaf: bool,
    args: public.CdbTreeViewArgs,
) bool {
    _ = args;
    var buff: [128:0]u8 = undefined;
    const asset_label = _editor.buffFormatObjLabel(allocator, &buff, db, obj, true) orelse "Not implemented";
    const asset_color = _editor.getAssetColor(db, obj);
    _coreui.pushStyleColor4f(.{ .idx = .text, .c = asset_color });

    const open = _coreui.treeNodeFlags(asset_label, .{
        .open_on_arrow = true,
        .open_on_double_click = false,
        .default_open = default_open,
        .no_tree_push_on_open = no_push,
        .selected = _coreui.isSelected(db, selection, obj),
        .leaf = leaf,
    });
    _coreui.popStyleColor(.{});

    if (db.getAspect(editor.UiVisualAspect, obj.type_idx)) |aspect| {
        if (aspect.ui_tooltip) |tooltip| {
            if (_coreui.isItemHovered(.{})) {
                _coreui.beginTooltip();
                defer _coreui.endTooltip();
                tooltip(allocator, db, obj) catch undefined;
            }
        }
    }

    if (_coreui.beginPopupContextItem()) {
        defer _coreui.endPopup();
        _editor.showObjContextMenu(allocator, db, tab, contexts, selection, null, null) catch undefined;
    }

    var is_project = false;
    if (_assetdb.getObjForAsset(obj)) |o| {
        is_project = cetech1.assetdb.Project.isSameType(db, o);
    }

    if (!is_project and !_assetdb.isRootFolder(db, obj) and _coreui.beginDragDropSource(.{})) {
        defer _coreui.endDragDropSource();

        const aasset_label = _editor.buffFormatObjLabel(allocator, &buff, db, obj, false) orelse "Not implemented";
        const aasset_color = _editor.getAssetColor(db, obj);
        _coreui.textColored(aasset_color, aasset_label);

        if (_coreui.selectedCount(allocator, db, selection) == 1) {
            _ = _coreui.setDragDropPayload("obj", &std.mem.toBytes(obj), .once);
        } else {
            _ = _coreui.setDragDropPayload("objs", &std.mem.toBytes(selection), .once);
        }
    }

    if (_coreui.beginDragDropTarget()) {
        defer _coreui.endDragDropTarget();
        if (_coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
            const drag_obj: cdb.ObjId = std.mem.bytesToValue(cdb.ObjId, payload.data.?);

            if (db.getAspect(public.UiTreeAspect, obj.type_idx)) |aspect| {
                if (aspect.ui_drop_obj) |ui_drop_obj| {
                    ui_drop_obj(allocator, db, tab, obj, drag_obj) catch undefined;
                }
            }
        }
    }

    return open;
}

fn cdbTreePop() void {
    return _coreui.treePop();
}
fn formatedPropNameToBuff(buf: []u8, prop_name: [:0]const u8) ![]u8 {
    var split = std.mem.split(u8, prop_name, "_");
    const first = split.first();

    var buff_stream = std.io.fixedBufferStream(buf);
    var writer = buff_stream.writer();

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

    var writen = buff_stream.getWritten();
    return writen[0 .. writen.len - 1];
}

fn isLeaf(db: cdb.Db, obj: cdb.ObjId) bool {
    if (db.getTypePropDef(obj.type_idx)) |prop_defs| {
        for (prop_defs) |prop| {
            switch (prop.type) {
                .SUBOBJECT_SET => {
                    return false;
                },
                .REFERENCE_SET => {
                    return false;
                },
                else => {},
            }
        }
    }

    return true;
}

fn cdbTreeView(
    allocator: std.mem.Allocator,
    db: cdb.Db,
    tab: *editor.TabO,
    context: []const strid.StrId64,
    obj: cdb.ObjId,
    selection: cdb.ObjId,
    depth: u32,
    args: public.CdbTreeViewArgs,
) !public.SelectInTreeResult {
    // if exist aspect use it
    const ui_aspect = db.getAspect(public.UiTreeAspect, obj.type_idx);

    var result: public.SelectInTreeResult = .{ .is_changed = false };

    if (ui_aspect) |aspect| {
        //_ = aspect;
        return aspect.ui_tree(allocator, db, tab, context, obj, selection, depth, args);
    }

    if (!args.ignored_object.isEmpty() and args.ignored_object.eql(obj)) {
        return result;
    }

    if (!args.expand_object and args.only_types.idx != 0 and obj.type_idx.idx != args.only_types.idx) {
        return result;
    }

    const obj_r = db.readObj(obj) orelse return .{ .is_changed = false };

    _coreui.pushObjUUID(obj);
    defer _coreui.popId();

    // Do generic tree walk
    const prop_defs = db.getTypePropDef(obj.type_idx).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);
        const prop_name = try formatedPropNameToBuff(&prop_name_buff, prop_def.name);

        // _coreui.pushPropName(db, obj, prop_idx);
        // defer _coreui.popId();

        switch (prop_def.type) {
            //.SUBOBJECT, .REFERENCE => {
            .SUBOBJECT => {
                var subobj: cdb.ObjId = undefined;

                // if (prop_def.type == .REFERENCE) {
                //     subobj = db.readRef(db.readObj(obj).?, prop_idx) orelse continue;
                // } else {
                subobj = db.readSubObj(db.readObj(obj).?, prop_idx) orelse continue;
                // }

                if (db.getAspect(editor_inspector.UiEmbedPropertiesAspect, subobj.type_idx) != null) {
                    continue;
                }

                const label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}{s}",
                    .{ prop_name, if (prop_def.type == .REFERENCE) "  " ++ Icons.FA_LINK else "" },
                );

                const color = _editor.getPropertyColor(db, obj, prop_idx);
                if (color) |colorr| {
                    _coreui.pushStyleColor4f(.{ .idx = .text, .c = colorr });
                }

                const open = api.cdbTreeNode(
                    label,
                    depth < args.max_autopen_depth,
                    false,
                    _coreui.isSelected(db, selection, subobj) or (args.sr.prop_idx == prop_idx and args.sr.in_set_obj.isEmpty()),
                    isLeaf(db, subobj),
                    args,
                );

                if (color != null) {
                    _coreui.popStyleColor(.{});
                }

                if (_coreui.isItemActivated()) {
                    try _coreui.handleSelection(allocator, db, selection, obj, args.multiselect);
                    result = .{ .is_changed = true, .is_prop = true, .prop_idx = prop_idx };
                }

                if (open) {
                    defer api.cdbTreePop();
                    const r = try cdbTreeView(allocator, db, tab, context, subobj, selection, depth + 1, args);
                    if (r.isChanged()) result = r;
                }
            },
            //.SUBOBJECT_SET, .REFERENCE_SET => {
            .SUBOBJECT_SET => {
                const prop_label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}{s}",
                    .{ prop_name, if (prop_def.type == .REFERENCE_SET) "  " ++ Icons.FA_LINK else "" },
                );

                const open = api.cdbTreeNode(prop_label, depth < args.max_autopen_depth, false, false, false, args);
                if (_coreui.isItemActivated()) {
                    try _coreui.handleSelection(allocator, db, selection, obj, args.multiselect);
                    result.is_changed = true;
                    result.is_prop = true;
                    result.prop_idx = prop_idx;
                }

                if (_coreui.beginPopupContextItem()) {
                    defer _coreui.endPopup();
                    try _editor.showObjContextMenu(allocator, db, tab, &.{}, obj, prop_idx, null);
                }

                if (open) {
                    defer api.cdbTreePop();

                    // added
                    var set: ?[]const cdb.ObjId = undefined;
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSet(obj_r, prop_idx, allocator);
                    } else {
                        set = try db.readSubObjSet(obj_r, prop_idx, allocator);
                    }

                    var inisiated_prototypes = std.AutoHashMap(cdb.ObjId, void).init(allocator);
                    defer inisiated_prototypes.deinit();

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            // _coreui.pushIntId(@truncate(set_idx));
                            // defer _coreui.popId();

                            // const label = _coreui.buffFormatObjLabel(allocator, &buff, db, subobj) orelse try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});
                            const label = try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});

                            const is_inisiated = db.isIinisiated(obj_r, prop_idx, db.readObj(subobj).?);

                            if (is_inisiated) {
                                try inisiated_prototypes.put(db.getPrototype(db.readObj(subobj).?), {});
                            }

                            _coreui.pushStyleColor4f(.{ .idx = .text, .c = _editor.getObjColor(db, obj, prop_idx, subobj) });

                            const open_inset = api.cdbTreeNode(
                                label,
                                depth < args.max_autopen_depth,
                                false,
                                _coreui.isSelected(db, selection, subobj) or (args.sr.prop_idx == prop_idx and args.sr.in_set_obj.eql(subobj)),
                                isLeaf(db, subobj),
                                args,
                            );

                            _coreui.popStyleColor(.{});

                            if (_coreui.isItemActivated()) {
                                try _coreui.handleSelection(allocator, db, selection, obj, args.multiselect);
                                result.is_changed = true;
                                result.is_prop = true;
                                result.prop_idx = prop_idx;
                                result.in_set_obj = subobj;
                            }

                            if (_coreui.beginPopupContextItem()) {
                                defer _coreui.endPopup();
                                try _editor.showObjContextMenu(allocator, db, tab, &.{}, obj, prop_idx, subobj);
                            }

                            if (open_inset) {
                                const r = try cdbTreeView(allocator, db, tab, context, subobj, selection, depth + 1, args);
                                if (r.isChanged()) result = r;
                                api.cdbTreePop();
                            }
                        }
                    }

                    // removed
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSetRemoved(db.readObj(obj).?, prop_idx, allocator);
                    } else {
                        set = db.readSubObjSetRemoved(db.readObj(obj).?, prop_idx, allocator);
                    }

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            _ = set_idx;
                            // _coreui.pushIntId(@truncate(set_idx));
                            // defer _coreui.popId();
                            if (inisiated_prototypes.contains(subobj)) continue;

                            var label: ?[:0]u8 = null;
                            if (_assetdb.getUuid(subobj)) |uuid| {
                                label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Deleted ++ "  " ++ "{s}###{}", .{ uuid, uuid });
                            } else {
                                label = try std.fmt.bufPrintZ(&buff, coreui.Icons.Deleted ++ "  " ++ "{d}:{d}###{d}{d}", .{ subobj.id, subobj.type_idx.idx, subobj.id, subobj.type_idx.idx });
                            }

                            if (_editor.isColorsEnabled()) _coreui.pushStyleColor4f(.{ .idx = .text, .c = REMOVED_COLOR });
                            const open_inset = _coreui.treeNodeFlags(label.?, .{ .leaf = true, .selected = _coreui.isSelected(db, selection, subobj) });
                            if (_editor.isColorsEnabled()) _coreui.popStyleColor(.{});

                            if (open_inset) {
                                defer _coreui.treePop();

                                if (_coreui.isItemActivated()) {
                                    try _coreui.handleSelection(allocator, db, selection, subobj, args.multiselect);
                                }

                                if (_coreui.beginPopupContextItem()) {
                                    defer _coreui.endPopup();
                                    if (_coreui.menuItem(allocator, coreui.Icons.Revive ++ "  " ++ "Restore deleted", .{}, null)) {
                                        db.restoreDeletedInSet(obj_r, prop_idx, db.readObj(subobj).?);
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

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: cdb.Db) !void {
        _ = db_;
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
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(module_name, cetech1.assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.setOrRemoveZigApi(module_name, public.TreeAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_tree(__apidb: *const cetech1.apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {}
