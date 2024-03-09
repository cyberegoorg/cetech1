const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editorui = cetech1.editorui;
const editor = @import("editor");
const public = @import("editor_tree.zig");

const Icons = cetech1.editorui.CoreIcons;

pub const c = @cImport(@cInclude("cetech1/modules/editor_tree/editor_tree.h"));

const MODULE_NAME = "editor_tree";

const PROTOTYPE_PROPERTY_COLOR = .{ 0.5, 0.5, 0.5, 1.0 };
const PROTOTYPE_PROPERTY_OVERIDED_COLOR = .{ 0.0, 0.8, 1.0, 1.0 };
const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };
const REMOVED_COLOR = .{ 0.7, 0.0, 0.0, 1.0 };

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;

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
    return _editorui.treeNodeFlags(label, .{
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
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    default_open: bool,
    no_push: bool,
    selected: bool,
    leaf: bool,
    args: public.CdbTreeViewArgs,
) bool {
    _ = args;
    var buff: [128:0]u8 = undefined;
    const asset_label = _editorui.buffFormatObjLabel(allocator, &buff, db, obj) orelse "Not implemented";
    const asset_color = _assetdb.getAssetColor(db, obj);
    _editorui.pushStyleColor4f(.{ .idx = .text, .c = asset_color });

    const open = _editorui.treeNodeFlags(asset_label, .{
        .open_on_arrow = true,
        .open_on_double_click = false,
        .default_open = default_open,
        .no_tree_push_on_open = no_push,
        .selected = selected,
        .leaf = leaf,
    });
    _editorui.popStyleColor(.{});

    if (db.getAspect(editorui.UiVisualAspect, obj.type_hash)) |aspect| {
        if (aspect.ui_tooltip) |tooltip| {
            if (_editorui.isItemHovered(.{})) {
                _editorui.beginTooltip();
                defer _editorui.endTooltip();
                tooltip(&allocator, db.db, obj);
            }
        }
    }

    return open;
}

fn cdbTreePop() void {
    return _editorui.treePop();
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

fn getPropertyColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32 {
    const prototype_obj = db.getPrototype(db.readObj(obj).?);
    const has_prototype = !prototype_obj.isEmpty();

    var color: ?[4]f32 = null;
    if (has_prototype) {
        color = PROTOTYPE_PROPERTY_COLOR;
        if (db.isPropertyOverrided(db.readObj(obj).?, prop_idx)) {
            color = PROTOTYPE_PROPERTY_OVERIDED_COLOR;
        }
    }
    return color;
}

fn isLeaf(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) bool {
    if (db.getTypePropDef(obj.type_hash)) |prop_defs| {
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

fn cdbTreeView(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, tab: *editor.TabO, context: []const cetech1.strid.StrId64, obj: cetech1.cdb.ObjId, selection: cetech1.cdb.ObjId, args: public.CdbTreeViewArgs) !void {
    // if exist aspect use it
    const ui_aspect = db.getAspect(public.UiTreeAspect, obj.type_hash);

    if (ui_aspect) |aspect| {
        //_ = aspect;
        aspect.ui_tree.?(&allocator, db.db, tab, context.ptr, context.len, obj, selection, args);
        return;
    }

    if (!args.ignored_object.isEmpty() and args.ignored_object.eq(obj)) {
        return;
    }

    if (!args.expand_object and args.only_types.id != 0 and obj.type_hash.id != args.only_types.id) {
        return;
    }

    const obj_r = db.readObj(obj) orelse return;

    _editorui.pushObjId(obj);
    defer _editorui.popId();

    // Do generic tree walk
    const prop_defs = db.getTypePropDef(obj.type_hash).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);
        const prop_name = try formatedPropNameToBuff(&prop_name_buff, prop_def.name);

        _editorui.pushIntId(prop_idx);
        defer _editorui.popId();

        switch (prop_def.type) {
            //.SUBOBJECT, .REFERENCE => {
            .SUBOBJECT => {
                var subobj: cetech1.cdb.ObjId = undefined;

                if (prop_def.type == .REFERENCE) {
                    subobj = db.readRef(db.readObj(obj).?, prop_idx) orelse continue;
                } else {
                    subobj = db.readSubObj(db.readObj(obj).?, prop_idx) orelse continue;
                }

                if (db.getAspect(editorui.UiEmbedPropertiesAspect, subobj.type_hash) != null) {
                    continue;
                }

                const label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}{s}",
                    .{ prop_name, if (prop_def.type == .REFERENCE) " " ++ Icons.FA_LINK else "" },
                );

                const color = getPropertyColor(db, obj, prop_idx);
                if (color) |colorr| {
                    _editorui.pushStyleColor4f(.{ .idx = .text, .c = colorr });
                }

                const open = api.cdbTreeNode(label, false, false, _editorui.isSelected(db, selection, subobj), isLeaf(db, subobj), args);

                if (color != null) {
                    _editorui.popStyleColor(.{});
                }

                if (_editorui.isItemActivated()) {
                    try _editorui.handleSelection(allocator, db, selection, subobj, args.multiselect);
                }

                if (open) {
                    defer api.cdbTreePop();
                    try cdbTreeView(allocator, db, tab, context, subobj, selection, args);
                }
            },
            //.SUBOBJECT_SET, .REFERENCE_SET => {
            .SUBOBJECT_SET => {
                const prop_label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}{s}",
                    .{ prop_name, if (prop_def.type == .REFERENCE_SET) " " ++ Icons.FA_LINK else "" },
                );

                const open = api.cdbTreeNode(prop_label, true, false, false, false, args);
                if (_editorui.isItemActivated()) {
                    try _editorui.handleSelection(allocator, db, selection, obj, args.multiselect);
                }

                if (_editorui.beginPopupContextItem()) {
                    defer _editorui.endPopup();
                    try _editor.objContextMenu(allocator, db, tab, &.{}, obj, prop_idx, null);
                }

                if (open) {
                    defer api.cdbTreePop();

                    // added
                    var set: ?[]const cetech1.cdb.ObjId = undefined;
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSet(obj_r, prop_idx, allocator);
                    } else {
                        set = try db.readSubObjSet(obj_r, prop_idx, allocator);
                    }

                    var inisiated_prototypes = std.AutoHashMap(cetech1.cdb.ObjId, void).init(allocator);
                    defer inisiated_prototypes.deinit();

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            _editorui.pushIntId(@truncate(set_idx));
                            defer _editorui.popId();

                            // const label = _editorui.buffFormatObjLabel(allocator, &buff, db, subobj) orelse try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});
                            const label = try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});

                            const is_inisiated = db.isIinisiated(obj_r, prop_idx, db.readObj(subobj).?);

                            if (is_inisiated) {
                                try inisiated_prototypes.put(db.getPrototype(db.readObj(subobj).?), {});
                            }

                            _editorui.pushStyleColor4f(.{ .idx = .text, .c = _editorui.getObjColor(db, obj, prop_idx, subobj) });

                            const open_inset = api.cdbTreeNode(label, true, false, _editorui.isSelected(db, selection, subobj), isLeaf(db, subobj), args);

                            _editorui.popStyleColor(.{});

                            if (_editorui.isItemActivated()) {
                                try _editorui.handleSelection(allocator, db, selection, subobj, args.multiselect);
                            }

                            if (_editorui.beginPopupContextItem()) {
                                defer _editorui.endPopup();
                                try _editor.objContextMenu(allocator, db, tab, &.{}, obj, prop_idx, subobj);
                            }

                            if (open_inset) {
                                try cdbTreeView(allocator, db, tab, context, subobj, selection, args);
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
                            _editorui.pushIntId(@truncate(set_idx));
                            defer _editorui.popId();
                            if (inisiated_prototypes.contains(subobj)) continue;

                            var label: ?[:0]u8 = null;
                            if (_assetdb.getUuid(subobj)) |uuid| {
                                label = try std.fmt.bufPrintZ(&buff, editorui.Icons.Deleted ++ " " ++ "{s}###{}", .{ uuid, uuid });
                            } else {
                                label = try std.fmt.bufPrintZ(&buff, editorui.Icons.Deleted ++ " " ++ "{d}:{d}###{d}{d}", .{ subobj.id, subobj.type_hash.id, subobj.id, subobj.type_hash.id });
                            }

                            _editorui.pushStyleColor4f(.{ .idx = .text, .c = REMOVED_COLOR });
                            const open_inset = _editorui.treeNodeFlags(label.?, .{ .leaf = true, .selected = _editorui.isSelected(db, selection, subobj) });
                            _editorui.popStyleColor(.{});
                            if (open_inset) {
                                defer _editorui.treePop();

                                if (_editorui.isItemActivated()) {
                                    try _editorui.handleSelection(allocator, db, selection, subobj, args.multiselect);
                                }

                                if (_editorui.beginPopupContextItem()) {
                                    defer _editorui.endPopup();
                                    if (_editorui.menuItem(editorui.Icons.Revive ++ "  " ++ "Restore deleted", .{})) {
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
}

fn cdbCreateTypes(db_: ?*cetech1.cdb.Db) !void {
    _ = db_;
}

var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log;
    _apidb = apidb;
    _cdb = apidb.getZigApi(cetech1.cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;
    _editor = apidb.getZigApi(editor.EditorAPI).?;
    _assetdb = apidb.getZigApi(cetech1.assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.setOrRemoveZigApi(public.TreeAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_tree(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_editorui_ui_tree_aspect) == @sizeOf(public.UiTreeAspect));
    std.debug.assert(@sizeOf(c.ct_editor_cdb_tree_args) == @sizeOf(public.CdbTreeViewArgs));
}
