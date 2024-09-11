const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_inspector.zig");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const strid = cetech1.strid;
const assetdb = cetech1.assetdb;
const coreui = cetech1.coreui;
const coreui_icons = cetech1.coreui;
const profiler = cetech1.profiler;

const editor = @import("editor");

const Icons = coreui.CoreIcons;

const module_name = .editor_inspector;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const INSPECTOR_TAB_NAME = "ct_editor_inspector_tab";
const INSPECTOR_TAB_NAME_HASH = strid.strId32(INSPECTOR_TAB_NAME);

const COLOR4F_PROPERTY_ASPECT_NAME = "ct_color_4f_properties_aspect";
const FOLDER_NAME_PROPERTY_ASPECT_NAME = "ct_folder_name_property_aspect";
const FOLDER_PROPERTY_CONFIG_ASPECT_NAME = "ct_folder_property_config_aspect";
const ASSET_PROPERTIES_ASPECT_NAME = "ct_asset_properties_aspect";

const PROP_HEADER_BG_COLOR = .{ 0.2, 0.2, 0.2, 0.65 };

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _uuid: *const cetech1.uuid.UuidAPI = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const profiler.ProfilerAPI = undefined;

// Global state
const G = struct {
    tab_vt: *editor.TabTypeI = undefined,
    asset_prop_aspect: *public.UiPropertiesAspect = undefined,
    color4f_properties_aspec: *public.UiEmbedPropertiesAspect = undefined,
    hide_proto_property_config_aspect: *public.UiPropertiesConfigAspect = undefined,
};
var _g: *G = undefined;

var api = public.InspectorAPI{
    .uiPropLabel = uiPropLabel,
    .uiPropInput = uiPropInput,
    .uiPropInputRaw = uiPropInputRaw,
    .uiPropInputBegin = uiPropInputBegin,
    .uiPropInputEnd = uiPropInputEnd,
    .cdbPropertiesView = cdbPropertiesView,
    .cdbPropertiesObj = cdbPropertiesObj,
    .uiAssetInput = uiAssetInput,
    .formatedPropNameToBuff = formatedPropNameToBuff,

    .beginSection = beginSection,
    .endSection = endSection,
    .beginPropTable = beginPropTable,
    .endPropTabel = endPropTabel,
};

fn openNewInspectorForObj(db: cdb.Db, obj: cdb.ObjId) void {
    _editor.openTabWithPinnedObj(db, INSPECTOR_TAB_NAME_HASH, obj);
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

fn uiAssetInput(
    allocator: std.mem.Allocator,
    db: cdb.Db,
    tab: *editor.TabO,
    obj: cdb.ObjId,
    prop_idx: u32,
    read_only: bool,
    in_table: bool,
) !void {
    const obj_r = db.readObj(obj) orelse return;

    const defs = db.getTypePropDef(obj.type_idx).?;
    const prop_def = defs[prop_idx];

    var value_obj: cdb.ObjId = .{};
    switch (prop_def.type) {
        .REFERENCE => {
            if (db.readRef(obj_r, prop_idx)) |o| {
                value_obj = o;
            }
        },
        else => {
            return;
        },
    }

    return uiAssetInputGeneric(
        allocator,
        db,
        tab,
        obj,
        value_obj,
        read_only,
        false,
        prop_idx,
        in_table,
    );
}

fn uiAssetInputProto(allocator: std.mem.Allocator, db: cdb.Db, tab: *editor.TabO, obj: cdb.ObjId, value_obj: cdb.ObjId, read_only: bool) !void {
    return uiAssetInputGeneric(
        allocator,
        db,
        tab,
        obj,
        value_obj,
        read_only,
        true,
        0,
        true,
    );
}

fn uiAssetInputGeneric(
    allocator: std.mem.Allocator,
    db: cdb.Db,
    tab: *editor.TabO,
    obj: cdb.ObjId,
    value_obj: cdb.ObjId,
    read_only: bool,
    is_proto: bool,
    prop_idx: u32,
    in_table: bool,
) !void {
    var buff: [128:0]u8 = undefined;
    var buff_asset: [128:0]u8 = undefined;
    var asset_name: [:0]u8 = undefined;
    const value_asset: ?cdb.ObjId = _assetdb.getAssetForObj(value_obj);

    if (value_asset) |asset| {
        if (_assetdb.isAssetFolder(asset)) {
            const path = try _assetdb.getPathForFolder(&buff_asset, asset);
            asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{if (std.fs.path.dirname(path)) |p| p else "/"});
        } else {
            const path = try _assetdb.getFilePathForAsset(&buff_asset, asset);
            asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{path});
        }
    } else {
        asset_name = try std.fmt.bufPrintZ(&buff, "", .{});
    }

    const prop_def = db.getTypePropDef(obj.type_idx).?;
    const allowed_type = if (is_proto) obj.type_idx else db.getTypeIdx(prop_def[prop_idx].type_hash) orelse cdb.TypeIdx{};

    _coreui.pushObjUUID(obj);
    defer _coreui.popId();

    if (!is_proto) _coreui.pushPropName(db, obj, prop_idx);
    defer if (!is_proto) _coreui.popId();

    if (in_table) {
        _coreui.tableNextColumn();
    }

    if (!is_proto) {
        try uiInputProtoBtns(db, obj, prop_idx);
    }

    if (_coreui.beginPopup("ui_asset_context_menu", .{})) {
        defer _coreui.endPopup();
        if (_editor.selectObjFromMenu(allocator, db, _assetdb.getObjForAsset(obj) orelse obj, allowed_type)) |selected| {
            if (is_proto) {
                try db.setPrototype(obj, selected);
            } else {
                const w = db.writeObj(obj).?;
                try db.setRef(w, prop_idx, selected);
                try db.writeCommit(w);
            }
        }

        if (!_assetdb.isAssetObjTypeOf(obj, assetdb.Folder.typeIdx(db))) {
            if (_coreui.menuItem(allocator, coreui.Icons.Clear ++ "  " ++ "Clear" ++ "###Clear", .{ .enabled = !read_only and value_asset != null }, null)) {
                if (is_proto) {
                    try db.setPrototype(obj, cdb.OBJID_ZERO);
                } else {
                    const w = db.writeObj(obj).?;
                    try db.clearRef(w, prop_idx);
                    try db.writeCommit(w);
                }
            }
        }

        if (_coreui.beginMenu(allocator, coreui.Icons.ContextMenu ++ "  " ++ "Context", value_asset != null, null)) {
            defer _coreui.endMenu();
            try _editor.showObjContextMenu(allocator, db, tab, &.{editor.Contexts.open}, .{ .top_level_obj = value_asset.?, .obj = value_asset.? });
        }
    }

    if (_coreui.button(Icons.FA_ELLIPSIS ++ "###AssetInputMenu", .{})) {
        _coreui.openPopup("ui_asset_context_menu", .{});
    }

    _coreui.sameLine(.{});
    _coreui.setNextItemWidth(-std.math.floatMin(f32));
    _ = _coreui.inputText("", .{
        .buf = asset_name,
        .flags = .{
            .read_only = true,
            .auto_select_all = true,
        },
    });

    if (_coreui.beginDragDropTarget()) {
        if (_coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
            var drag_obj: cdb.ObjId = std.mem.bytesToValue(cdb.ObjId, payload.data.?);
            if (drag_obj.type_idx.eql(AssetTypeIdx)) {
                drag_obj = assetdb.Asset.readSubObj(db, db.readObj(drag_obj).?, .Object).?;
            }

            if (is_proto) {
                if (!drag_obj.eql(obj)) {
                    try db.setPrototype(obj, drag_obj);
                }
            } else {
                const allowed_type_hash = db.getTypeIdx(db.getTypePropDef(obj.type_idx).?[prop_idx].type_hash) orelse cdb.TypeIdx{};
                if (allowed_type_hash.isEmpty() or allowed_type_hash.eql(drag_obj.type_idx)) {
                    const w = db.writeObj(obj).?;
                    try db.setRef(w, prop_idx, drag_obj);
                    try db.writeCommit(w);
                }
            }
        }
        defer _coreui.endDragDropTarget();
    }
}

fn beginPropTable(name: [:0]const u8) bool {
    return _coreui.beginTable(name, .{
        .column = 2,
        .flags = .{
            .sizing = .stretch_prop,
            .no_saved_settings = true,
            //.borders = cetech1.coreui.TableBorderFlags.outer,
            .row_bg = true,
            //.resizable = true,
        },
    });
}

fn endPropTabel() void {
    _coreui.endTable();
}

fn beginSection(label: [:0]const u8, leaf: bool, default_open: bool, flat: bool) bool {
    if (flat) return true;
    const open = _coreui.treeNodeFlags(label, .{
        .framed = true,
        .leaf = leaf,
        .default_open = default_open,
        .no_auto_open_on_log = !leaf,
        .span_avail_width = true,
        //.no_tree_push_on_open = true,
    });
    if (open) {
        // _coreui.pushStyleColor4f(.{ .idx = .frame_bg, .c = .{ 0, 0, 0, 0 } });
        // defer _coreui.popStyleColor(.{});
        // _ = _coreui.beginChild(
        //     label,
        //     .{
        //         .child_flags = .{
        //             .border = false,
        //             .frame_style = true,
        //             .auto_resize_y = true,
        //             .always_auto_resize = true,
        //             .nav_flattened = true,
        //         },
        //     },
        // );
    }
    return open;
}

fn endSection(open: bool, flat: bool) void {
    if (flat) return;

    if (open) {
        // _coreui.endChild();
        _coreui.treePop();
    }
}

fn cdbPropertiesView(allocator: std.mem.Allocator, db: cdb.Db, tab: *editor.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: public.cdbPropertiesViewArgs) !void {
    _coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 10 });
    defer _coreui.popStyleVar(.{});
    try cdbPropertiesObj(allocator, db, tab, top_level_obj, obj, depth, args);
}
const REMOVED_COLOR = .{ 0.7, 0.0, 0.0, 1.0 };

fn objContextMenuBtn(allocator: std.mem.Allocator, db: cdb.Db, tab: *editor.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cdb.ObjId) !void {
    if (_coreui.beginPopup("property_obj_menu", .{})) {
        defer _coreui.endPopup();
        try _editor.showObjContextMenu(allocator, db, tab, &.{editor.Contexts.open}, .{
            .top_level_obj = top_level_obj,
            .obj = obj,
            .prop_idx = prop_idx,
            .in_set_obj = in_set_obj,
        });
    }

    if (_coreui.button(Icons.FA_ELLIPSIS ++ "###PropertyCtxMenu", .{})) {
        _coreui.openPopup("property_obj_menu", .{});
    }
}

fn cdbPropertiesObj(
    allocator: std.mem.Allocator,
    db: cdb.Db,
    tab: *editor.TabO,
    top_level_obj: cdb.ObjId,
    obj: cdb.ObjId,
    depth: u32,
    args: public.cdbPropertiesViewArgs,
) !void {
    var zone_ctx = _profiler.Zone(@src());
    defer zone_ctx.End();

    const enabled = if (args.parent_disabled) false else db.isChildOff(top_level_obj, obj);

    // Find properties asspect for obj type.
    const ui_aspect = db.getAspect(public.UiPropertiesAspect, obj.type_idx);
    if (ui_aspect) |aspect| {
        try aspect.ui_properties(allocator, db, tab, top_level_obj, obj, depth, args);
        return;
    }

    _coreui.pushObjUUID(obj);
    defer _coreui.popId();

    const obj_r = db.readObj(obj) orelse return;

    // Find properties config asspect for obj type.
    const config_aspect = db.getAspect(public.UiPropertiesConfigAspect, obj.type_idx);

    const prototype_obj = db.getPrototype(obj_r);
    //const has_prototype = !prototype_obj.isEmpty();

    const prop_defs = db.getTypePropDef(obj.type_idx).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    var show_proto = true;

    // Exist config aspect?
    if (config_aspect) |aspect| {
        show_proto = !aspect.hide_prototype;
    }

    if (args.hide_proto) {
        show_proto = false;
    }

    // Scalars valus
    if (beginPropTable("Inspector")) {
        defer endPropTabel();

        if (show_proto) {
            if (api.uiPropLabel(allocator, "Prototype", null, enabled, args)) {
                _coreui.beginDisabled(.{ .disabled = !enabled });
                defer _coreui.endDisabled();
                try uiAssetInputProto(allocator, db, tab, obj, prototype_obj, false);
            }
        }

        for (prop_defs, 0..) |prop_def, idx| {
            const prop_idx: u32 = @truncate(idx);
            const visible = _coreui.isRectVisible(.{ _coreui.getContentRegionMax()[0], _coreui.getFontSize() * _coreui.getScaleFactor() });

            const prop_name = if (visible) try api.formatedPropNameToBuff(&prop_name_buff, prop_def.name) else "";
            const prop_state = if (visible) db.getRelation(top_level_obj, obj, prop_idx, null) else .not_owned;
            const prop_color = _editor.getStateColor(prop_state);

            switch (prop_def.type) {
                else => {},
            }
            var ui_prop_aspect: ?*public.UiPropertyAspect = null;
            if (prop_def.type != .REFERENCE_SET and prop_def.type != .SUBOBJECT_SET) {
                ui_prop_aspect = db.getPropertyAspect(public.UiPropertyAspect, obj.type_idx, prop_idx);
                // If exist aspect and is empty hide property.
                if (ui_prop_aspect) |aspect| {
                    aspect.ui_property(allocator, db, obj, prop_idx, args) catch continue;
                }
            }

            switch (prop_def.type) {
                .REFERENCE_SET, .SUBOBJECT_SET => {
                    const ui_embed_prop_aspect = db.getPropertyAspect(public.UiEmbedPropertyAspect, obj.type_idx, prop_idx);
                    if (ui_embed_prop_aspect) |aspect| {
                        const lbl = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                        if (uiPropLabel(allocator, lbl, prop_color, enabled, args)) {
                            _coreui.beginDisabled(.{ .disabled = !enabled });
                            defer _coreui.endDisabled();
                            try aspect.ui_properties(allocator, db, obj, prop_idx, args);
                            continue;
                        }
                    }
                },

                // If subobject type implement UiEmbedPropertiesAspect show it in table
                .SUBOBJECT => {
                    if (prop_def.type_hash.id == 0) continue;
                    const subobj = db.readSubObj(obj_r, prop_idx);
                    const ui_embed_prop_aspect = db.getAspect(public.UiEmbedPropertiesAspect, db.getTypeIdx(prop_def.type_hash).?);
                    if (ui_embed_prop_aspect) |aspect| {
                        const lbl = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                        if (visible) {
                            if (uiPropLabel(allocator, lbl, prop_color, enabled, args)) {
                                _coreui.tableNextColumn();
                                if (subobj == null) {
                                    try objContextMenuBtn(allocator, db, tab, top_level_obj, obj, prop_idx, null);
                                } else {
                                    _coreui.beginDisabled(.{ .disabled = !enabled });
                                    defer _coreui.endDisabled();
                                    try aspect.ui_properties(allocator, db, subobj.?, args);
                                }
                            }
                        } else {
                            _coreui.dummy(.{ .w = -1, .h = -1 });
                        }
                    }
                    continue;
                },

                .REFERENCE => {
                    var ref: ?cdb.ObjId = null;

                    if (args.filter) |filter| {
                        if (_coreui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                            continue;
                        }
                    }

                    ref = db.readRef(obj_r, prop_idx);

                    const label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});

                    if (uiPropLabel(allocator, label, prop_color, enabled, args)) {
                        _coreui.beginDisabled(.{ .disabled = !enabled });
                        defer _coreui.endDisabled();
                        try uiAssetInput(allocator, db, tab, obj, prop_idx, false, true);
                    }
                },
                else => {
                    if (args.filter) |filter| {
                        if (_coreui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                            continue;
                        }
                    }

                    const label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                    if (api.uiPropLabel(allocator, label, prop_color, enabled, args)) {
                        _coreui.beginDisabled(.{ .disabled = !enabled });
                        defer _coreui.endDisabled();
                        if (ui_prop_aspect) |aspect| {
                            try aspect.ui_property(allocator, db, obj, prop_idx, args);
                        } else {
                            try api.uiPropInput(db, obj, prop_idx, enabled, args);
                        }
                    }
                },
            }
        }
    }

    // Compound values
    for (prop_defs, 0..) |prop_def, idx| {
        switch (prop_def.type) {
            .SUBOBJECT, .REFERENCE_SET, .SUBOBJECT_SET => {},
            else => continue,
        }

        const prop_idx: u32 = @truncate(idx);

        _coreui.pushPropName(db, obj, @truncate(idx));
        defer _coreui.popId();

        const visible = _coreui.isRectVisible(.{ _coreui.getContentRegionMax()[0], _coreui.getFontSize() * _coreui.getScaleFactor() });

        const prop_name = if (visible) try api.formatedPropNameToBuff(&prop_name_buff, prop_def.name) else "";
        const prop_state = if (visible) db.getRelation(top_level_obj, obj, prop_idx, null) else .not_owned;
        const prop_color = _editor.getStateColor(prop_state);

        const ui_prop_aspect = db.getPropertyAspect(public.UiPropertyAspect, obj.type_idx, prop_idx);
        // If exist aspect and is empty hide property.
        if (ui_prop_aspect) |aspect| {
            var a = args;
            a.parent_disabled = !enabled;

            try aspect.ui_property(allocator, db, obj, prop_idx, a);
            continue;
        }

        switch (prop_def.type) {
            .SUBOBJECT => {
                var subobj: ?cdb.ObjId = null;

                if (args.filter) |filter| {
                    if (_coreui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                        continue;
                    }
                }

                subobj = db.readSubObj(obj_r, prop_idx);

                if (db.getTypeIdx(prop_def.type_hash)) |type_idx| {
                    if (db.getAspect(public.UiEmbedPropertiesAspect, type_idx) != null) continue;
                }

                const label = try std.fmt.bufPrintZ(&buff, "{s}  {s}", .{ prop_name, if (prop_def.type == .REFERENCE) "  " ++ Icons.FA_LINK else "" });

                if (!args.flat) {
                    try objContextMenuBtn(allocator, db, tab, top_level_obj, obj, prop_idx, null);
                    _coreui.sameLine(.{});
                }

                _coreui.pushStyleColor4f(.{ .idx = .text, .c = prop_color });
                const open = beginSection(label, subobj == null, depth < args.max_autopen_depth, args.flat);
                defer endSection(open, args.flat);
                _coreui.popStyleColor(.{});

                if (open) {
                    if (subobj != null) {
                        var a = args;
                        a.parent_disabled = !enabled;

                        try cdbPropertiesObj(allocator, db, tab, top_level_obj, subobj.?, depth + 1, a);
                    }
                }
            },

            .SUBOBJECT_SET, .REFERENCE_SET => {
                if (db.getPropertyAspect(public.UiEmbedPropertyAspect, obj.type_idx, prop_idx) != null) {
                    continue;
                }

                const prop_label = try std.fmt.bufPrintZ(&buff, "{s}  {s} {s}", .{
                    prop_name,
                    Icons.FA_LIST,
                    if (prop_def.type == .REFERENCE_SET) "  " ++ Icons.FA_LINK else "",
                });

                if (!args.flat) {
                    try objContextMenuBtn(allocator, db, tab, top_level_obj, obj, prop_idx, null);
                    _coreui.sameLine(.{});
                }

                var set: ?[]const cdb.ObjId = undefined;
                if (prop_def.type == .REFERENCE_SET) {
                    set = db.readRefSet(obj_r, prop_idx, allocator);
                } else {
                    set = try db.readSubObjSet(obj_r, prop_idx, allocator);
                }

                defer {
                    if (set) |s| {
                        allocator.free(s);
                    }
                }
                const is_empty = if (set) |s| s.len == 0 else true;
                _coreui.pushStyleColor4f(.{ .idx = .text, .c = prop_color });
                const open = beginSection(prop_label, false, !is_empty and depth < args.max_autopen_depth, args.flat);
                defer endSection(open, args.flat);
                _coreui.popStyleColor(.{});

                if (open) {
                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            _coreui.pushIntId(@truncate(set_idx));
                            defer _coreui.popId();

                            try objContextMenuBtn(allocator, db, tab, top_level_obj, obj, prop_idx, subobj);
                            _coreui.sameLine(.{});

                            const visible_item = _coreui.isRectVisible(.{ _coreui.getContentRegionMax()[0], _coreui.getFontSize() * _coreui.getScaleFactor() });
                            const label = if (visible_item) _editor.buffFormatObjLabel(allocator, &buff, db, subobj, true, false) orelse try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx}) else "";
                            const set_state = if (visible_item) db.getRelation(top_level_obj, obj, prop_idx, subobj) else .not_owned;
                            const set_color = _editor.getStateColor(set_state);

                            _coreui.pushStyleColor4f(.{ .idx = .text, .c = set_color });
                            const open_inset = beginSection(label, false, depth < args.max_autopen_depth, args.flat);

                            //_coreui.sameLine(.{});
                            defer endSection(open_inset, args.flat);
                            _coreui.popStyleColor(.{});

                            if (open_inset) {
                                var a = args;
                                a.parent_disabled = !enabled;

                                try cdbPropertiesObj(allocator, db, tab, top_level_obj, subobj, depth + 1, a);
                            }
                        }
                    }
                }
            },

            else => {},
        }
    }
}

fn uiInputProtoBtns(db: cdb.Db, obj: cdb.ObjId, prop_idx: u32) !void {
    const proto_obj = db.getPrototype(db.readObj(obj).?);
    if (proto_obj.isEmpty()) return;

    const types = db.getTypePropDef(obj.type_idx).?;
    const prop_def = types[prop_idx];
    const is_overided = db.isPropertyOverrided(db.readObj(obj).?, prop_idx);

    if (prop_def.type == .BLOB) return;

    if (_coreui.beginPopup("property_protoypes_menu", .{})) {
        if (_coreui.menuItem(_allocator, Icons.FA_ARROW_ROTATE_LEFT ++ "  " ++ "Reset to prototype value" ++ "###ResetToPrototypeValue", .{ .enabled = is_overided }, null)) {
            const w = db.writeObj(obj).?;
            db.resetPropertyOveride(w, prop_idx);
            try db.writeCommit(w);
        }

        if (_coreui.menuItem(_allocator, Icons.FA_ARROW_UP ++ "  " ++ "Propagate to prototype" ++ "###PropagateToPrototype", .{ .enabled = is_overided }, null)) {
            // TODO: TO CDB!!!
            // Set value from parent. This is probably not need.
            {
                const w = db.writeObj(proto_obj).?;
                const r = db.readObj(obj).?;

                switch (prop_def.type) {
                    .BOOL => {
                        const value = db.readValue(bool, r, prop_idx);
                        db.setValue(bool, w, prop_idx, value);
                    },
                    .F32 => {
                        const value = db.readValue(f32, r, prop_idx);
                        db.setValue(f32, w, prop_idx, value);
                    },
                    .F64 => {
                        const value = db.readValue(f64, r, prop_idx);
                        db.setValue(f64, w, prop_idx, value);
                    },
                    .I32 => {
                        const value = db.readValue(i32, r, prop_idx);
                        db.setValue(i32, w, prop_idx, value);
                    },
                    .U32 => {
                        const value = db.readValue(u32, r, prop_idx);
                        db.setValue(u32, w, prop_idx, value);
                    },
                    .I64 => {
                        const value = db.readValue(i64, r, prop_idx);
                        db.setValue(i64, w, prop_idx, value);
                    },
                    .U64 => {
                        const value = db.readValue(u64, r, prop_idx);
                        db.setValue(u64, w, prop_idx, value);
                    },
                    .STR => {
                        if (db.readStr(r, prop_idx)) |str| {
                            try db.setStr(w, prop_idx, str);
                        }
                    },
                    .REFERENCE => {
                        if (db.readRef(r, prop_idx)) |ref| {
                            try db.setRef(w, prop_idx, ref);
                        }
                    },
                    .BLOB => {},
                    else => {},
                }
                db.resetPropertyOveride(w, prop_idx);
                try db.writeCommit(w);
            }

            // reset value overide
            {
                const w = db.writeObj(obj).?;
                db.resetPropertyOveride(w, prop_idx);
                try db.writeCommit(w);
            }
        }

        _coreui.endPopup();
    }

    if (_coreui.button(Icons.FA_SWATCHBOOK ++ "###PrototypeButtons", .{})) {
        _coreui.openPopup("property_protoypes_menu", .{});
    }

    _coreui.sameLine(.{});
}

fn uiPropInputBegin(db: cdb.Db, obj: cdb.ObjId, prop_idx: u32, enabled: bool) !void {
    _ = enabled; // autofix
    _coreui.tableNextColumn();

    _coreui.pushObjUUID(obj);
    _coreui.pushPropName(db, obj, prop_idx);

    try uiInputProtoBtns(db, obj, prop_idx);

    _coreui.setNextItemWidth(-std.math.floatMin(f32));
}

fn uiPropInputEnd() void {
    _coreui.popId();
    _coreui.popId();
}

fn uiPropInput(db: cdb.Db, obj: cdb.ObjId, prop_idx: u32, enabled: bool, args: public.cdbPropertiesViewArgs) !void {
    try uiPropInputBegin(db, obj, prop_idx, enabled);
    defer uiPropInputEnd();
    try uiPropInputRaw(db, obj, prop_idx, args);
}

fn uiPropInputRaw(db: cdb.Db, obj: cdb.ObjId, prop_idx: u32, args: public.cdbPropertiesViewArgs) !void {
    _ = args; // autofix

    const visible = _coreui.isRectVisible(.{ _coreui.getContentRegionMax()[0], _coreui.getFontSize() * _coreui.getScaleFactor() });
    if (!visible) {
        _coreui.dummy(.{ .w = -1, .h = -1 });
        return;
    }

    var buf: [128:0]u8 = undefined;
    @memset(&buf, 0);

    const prop_defs = db.getTypePropDef(obj.type_idx).?;
    const prop_def = prop_defs[prop_idx];

    var buf_label: [128:0]u8 = undefined;
    @memset(&buf_label, 0);
    const label = try std.fmt.bufPrintZ(&buf_label, "###edit", .{});

    const reader = db.readObj(obj) orelse return;

    switch (prop_def.type) {
        .BOOL => {
            var value = if (visible) db.readValue(bool, reader, prop_idx) else false;
            if (_coreui.checkbox(label, .{
                .v = &value,
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(bool, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .F32 => {
            var value = if (visible) db.readValue(f32, reader, prop_idx) else 0;
            if (_coreui.dragF32(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(f32, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .F64 => {
            var value = if (visible) db.readValue(f64, reader, prop_idx) else 0;
            if (_coreui.dragF64(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(f64, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .I32 => {
            var value = if (visible) db.readValue(i32, reader, prop_idx) else 0;
            if (_coreui.dragI32(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(i32, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .U32 => {
            var value = if (visible) db.readValue(u32, reader, prop_idx) else 0;
            if (_coreui.dragU32(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(u32, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .I64 => {
            var value = if (visible) db.readValue(i64, reader, prop_idx) else 0;
            if (_coreui.dragI64(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(i64, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .U64 => {
            var value = if (visible) db.readValue(u64, reader, prop_idx) else 0;
            if (_coreui.dragU64(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                db.setValue(u64, w, prop_idx, value);
                try db.writeCommit(w);
            }
        },
        .STR => {
            const name = if (visible) db.readStr(reader, prop_idx) else "";
            if (name) |str| {
                _ = try std.fmt.bufPrintZ(&buf, "{s}", .{str});
            }
            if (_coreui.inputText(label, .{
                .buf = &buf,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                var new_name_buf: [128:0]u8 = undefined;
                const new_name = try std.fmt.bufPrintZ(&new_name_buf, "{s}", .{std.mem.sliceTo(&buf, 0)});
                try db.setStr(w, prop_idx, new_name);
                try db.writeCommit(w);
            }
        },
        .BLOB => {
            _coreui.text("---");
        },
        else => {
            _coreui.text("- !!INVALID TYPE!! -");
            log.err("Invalid property type for uiInputForProperty {}", .{prop_def.type});
        },
    }
}

fn uiPropLabel(allocator: std.mem.Allocator, name: [:0]const u8, color: ?[4]f32, enabled: bool, args: public.cdbPropertiesViewArgs) bool {
    if (args.filter) |filter| {
        if (_coreui.uiFilterPass(allocator, filter, name, false) == null) return false;
    }
    _coreui.tableNextColumn();

    if (args.no_prop_label) return true;

    // const max_x = _coreui.getContentRegionAvail()[0];
    // const style = _coreui.getStyle();
    // const txt_size = _coreui.calcTextSize(name, .{});
    // const space_x = max_x - _coreui.getScrollX() - style.item_spacing[0] * 0.5 - txt_size[0];

    // _coreui.dummy(.{ .w = space_x, .h = txt_size[1] });
    // _coreui.sameLine(.{});

    _coreui.alignTextToFramePadding();

    if (enabled) {
        if (color) |colorr| {
            _coreui.textColored(colorr, name);
        } else {
            _coreui.text(name);
        }
    } else {
        _coreui.beginDisabled(.{});
        _coreui.text(name);
        _coreui.endDisabled();
    }

    return true;
}

// Asset properties aspect
var asset_properties_aspec = public.UiPropertiesAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        tab: *editor.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: public.cdbPropertiesViewArgs,
    ) !void {
        const obj_r = db.readObj(obj) orelse return;

        var buf: [128:0]u8 = undefined;

        _coreui.separatorText("Asset");

        if (beginPropTable("AssetInspector")) {
            defer endPropTabel();
            // Asset UUID
            if (_assetdb.getUuid(obj)) |asset_uuid| {
                if (api.uiPropLabel(allocator, "UUID", null, true, args)) {
                    _coreui.tableNextColumn();
                    _ = try std.fmt.bufPrintZ(&buf, "{s}", .{asset_uuid});

                    _coreui.setNextItemWidth(-std.math.floatMin(f32));
                    _ = _coreui.inputText("", .{
                        .buf = &buf,
                        .flags = .{
                            .read_only = true,
                            .auto_select_all = true,
                        },
                    });
                }
            }

            var is_project = false;
            if (_assetdb.getObjForAsset(obj)) |o| {
                is_project = o.type_idx.eql(AssetTypeIdx);
            }

            // Asset name
            if (!is_project and !_assetdb.isRootFolder(db, obj) and api.uiPropLabel(allocator, "Name", null, true, args)) {
                try api.uiPropInput(db, obj, assetdb.Asset.propIdx(.Name), true, args);
            }

            // Asset name
            if (!_assetdb.isRootFolder(db, obj) and api.uiPropLabel(allocator, "Description", null, true, args)) {
                try uiPropInput(db, obj, assetdb.Asset.propIdx(.Description), true, args);
            }

            // Folder
            if (!is_project and !_assetdb.isRootFolder(db, obj) and api.uiPropLabel(allocator, "Folder", null, true, args)) {
                try uiAssetInput(allocator, db, tab, obj, assetdb.Asset.propIdx(.Folder), false, true);
            }

            // Tags
            if (!is_project and !_assetdb.isRootFolder(db, obj)) {
                // TODO: SHIT HACK
                const ui_prop_aspect = db.getPropertyAspect(public.UiEmbedPropertyAspect, obj.type_idx, assetdb.Asset.propIdx(.Tags));
                // If exist aspect and is empty hide property.
                if (ui_prop_aspect) |aspect| {
                    if (api.uiPropLabel(allocator, "Tags", null, true, args)) {
                        try aspect.ui_properties(allocator, db, obj, assetdb.Asset.propIdx(.Tags), args);
                    }
                }
            }
        }

        // Asset object
        _coreui.separatorText("Asset object");
        try api.cdbPropertiesObj(allocator, db, tab, top_level_obj, assetdb.Asset.readSubObj(db, obj_r, .Object).?, depth + 1, args);
    }
});

//

// Asset properties aspect
var color4f_properties_aspec = public.UiEmbedPropertiesAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        args: public.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator;
        _ = args;

        _coreui.pushObjUUID(obj);
        defer _coreui.popId();

        var color = cetech1.cdb_types.Color4f.f.toSlice(db, obj);

        _coreui.setNextItemWidth(-1);
        if (_coreui.colorEdit4("", .{ .col = &color })) {
            const w = db.writeObj(obj).?;
            cetech1.cdb_types.Color4f.f.fromSlice(db, w, color);
            try db.writeCommit(w);
        }
    }
});

//

const PropertyTab = struct {
    tab_i: editor.TabI,
    db: cdb.Db,
    selected_obj: coreui.SelectionItem,
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};

// Fill editor tab interface
var inspector_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = INSPECTOR_TAB_NAME,
    .tab_hash = strid.strId32(INSPECTOR_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
    .ignore_selection_from_tab = &.{cetech1.strid.strId32("ct_editor_asset_browser_tab")},
}, struct {
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Properties ++ "  " ++ "Inspector";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Properties ++ "  " ++ "Inspector";
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, db: cdb.Db, selection: []const coreui.SelectionItem) !bool {
        _ = allocator; // autofix
        _ = db;
        _ = selection;

        return true;
    }

    // Create new FooTab instantce
    pub fn create(db: cdb.Db, tab_id: u32) !?*editor.TabI {
        _ = tab_id;
        var tab_inst = try _allocator.create(PropertyTab);
        tab_inst.* = PropertyTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },
            .db = db,
            .selected_obj = coreui.SelectionItem.empty(),
        };

        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *PropertyTab = @alignCast(@ptrCast(tab_inst.inst));
        _allocator.destroy(tab_o);
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
        _ = tab_o;
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick; // autofix
        _ = dt; // autofix
        var tab_o: *PropertyTab = @alignCast(@ptrCast(inst));

        if (tab_o.selected_obj.isEmpty()) {
            return;
        }

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.uiFilter(&tab_o.filter_buff, tab_o.filter)) |filter| {
            tab_o.filter = filter;
        }

        defer _coreui.endChild();
        if (_coreui.beginChild("Inspector", .{ .child_flags = .{ .border = true } })) {
            const obj: cdb.ObjId = tab_o.selected_obj.obj;
            try api.cdbPropertiesView(allocator, tab_o.db, tab_o, tab_o.selected_obj.top_level_obj, obj, 0, .{ .filter = tab_o.filter });
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, db: cdb.Db, obj: []const coreui.SelectionItem, sender_tab_hash: ?strid.StrId32) !void {
        _ = sender_tab_hash; // autofix
        _ = db;
        var tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
        tab_o.selected_obj = obj[0];
    }

    pub fn assetRootOpened(inst: *editor.TabO) !void {
        const tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
        tab_o.filter = null;
        tab_o.selected_obj = coreui.SelectionItem.empty();
    }
});

var folder_properties_config_aspect = public.UiPropertiesConfigAspect{
    .hide_prototype = true,
};

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.Db) !void {
        try assetdb.Folder.addAspect(
            db,
            public.UiPropertiesConfigAspect,
            _g.hide_proto_property_config_aspect,
        );

        try assetdb.Project.addAspect(
            db,
            public.UiPropertiesConfigAspect,
            _g.hide_proto_property_config_aspect,
        );

        try assetdb.Asset.addAspect(
            db,
            public.UiPropertiesAspect,
            _g.asset_prop_aspect,
        );

        try cetech1.cdb_types.Color4f.addAspect(
            db,
            public.UiEmbedPropertiesAspect,
            _g.color4f_properties_aspec,
        );
    }
});

// Tests
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = _coreui.registerTest(
            "Inspector",
            "should_edit_basic_properties",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(_coreui, 1);

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f").?).?;

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset1.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###asset2.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    // Bool
                    {
                        ctx.itemAction(_coreui, .Check, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/bool/###edit", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, bool, obj_r, .Bool);
                        std.testing.expect(value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/u64/###edit", 666);
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, u64, obj_r, .U64);
                        std.testing.expectEqual(666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/i64/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value: i64 = assetdb.FooAsset.readValue(db, i64, obj_r, .I64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/u32/###edit", 666);
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, u32, obj_r, .U32);
                        std.testing.expectEqual(666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/i32/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, i32, obj_r, .I32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/f32/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, f32, obj_r, .F32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/f64/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, f64, obj_r, .F64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // String
                    {
                        ctx.itemInputStrValue(_coreui, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/str/###edit", "foo");
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const str = assetdb.FooAsset.readStr(db, obj_r, .Str);
                        std.testing.expect(str != null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                        std.testing.expectEqualStrings(str.?, "foo") catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // Ref
                    {
                        ctx.itemAction(_coreui, .Click, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/reference/###AssetInputMenu", .{}, null);
                        ctx.yield(_coreui, 1);
                        ctx.menuAction(_coreui, .Click, "//$FOCUSED/###SelectFrom/###1");

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const ref = assetdb.FooAsset.readRef(db, obj_r, .Reference);
                        std.testing.expect(ref != null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return;
                        };
                        std.testing.expect(ref.?.eql(_assetdb.getObjId(_uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?)) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return;
                        };
                    }
                }
            },
        );

        _ = _coreui.registerTest(
            "Inspector",
            "should_reset_value_from_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset1_1.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###asset2.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    const db = _kernel.getDb();

                    // Bool
                    {
                        ctx.itemAction(_coreui, .Check, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###edit", .{}, null);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, bool, obj_r, .Bool);
                        std.testing.expect(!value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###edit", 666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, u64, obj_r, .U64);
                        std.testing.expectEqual(0, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, i64, obj_r, .I64);
                        std.testing.expectEqual(0, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###edit", 666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, u32, obj_r, .U32);
                        std.testing.expectEqual(0, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, i32, obj_r, .I32);
                        std.testing.expectEqual(0, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, f32, obj_r, .F32);
                        std.testing.expectEqual(0, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, f64, obj_r, .F64);
                        std.testing.expectEqual(0, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // String
                    {
                        ctx.itemInputStrValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###edit", "foo");

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const str = assetdb.FooAsset.readStr(db, obj_r, .Str);
                        std.testing.expect(str == null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // Ref
                    {
                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###AssetInputMenu", .{}, null);
                        ctx.yield(_coreui, 1);
                        ctx.menuAction(_coreui, .Click, "//$FOCUSED/###SelectFrom/###1");

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const ref = assetdb.FooAsset.readRef(db, obj_r, .Reference);
                        std.testing.expect(ref == null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }
                }
            },
        );

        _ = _coreui.registerTest(
            "Inspector",
            "should_propagate_value_to_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset1_1.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###asset2.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f").?).?;

                    // Bool
                    {
                        ctx.itemAction(_coreui, .Check, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###edit", .{}, null);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, bool, obj_r, .Bool);
                        std.testing.expect(value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###edit", 666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, u64, obj_r, .U64);
                        std.testing.expectEqual(666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, i64, obj_r, .I64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###edit", 666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, u32, obj_r, .U32);
                        std.testing.expectEqual(666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, i32, obj_r, .I32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F32
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, f32, obj_r, .F32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F64
                    {
                        ctx.itemInputIntValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###edit", -666);

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const value = assetdb.FooAsset.readValue(db, f64, obj_r, .F64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // String
                    {
                        ctx.itemInputStrValue(_coreui, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###edit", "foo");

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const str = assetdb.FooAsset.readStr(db, obj_r, .Str);
                        std.testing.expect(str != null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                        std.testing.expectEqualStrings(str.?, "foo") catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // Ref
                    {
                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###AssetInputMenu", .{}, null);
                        ctx.yield(_coreui, 1);
                        ctx.menuAction(_coreui, .Click, "//$FOCUSED/###SelectFrom/###1");

                        ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###PrototypeButtons", .{}, null);
                        ctx.itemAction(_coreui, .Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(db, obj).?;
                        const ref = assetdb.FooAsset.readRef(db, obj_r, .Reference);
                        std.testing.expect(ref != null) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                        std.testing.expect(ref.?.eql(_assetdb.getObjId(_uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?)) catch |err| {
                            _coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }
                }
            },
        );

        _ = _coreui.registerTest(
            "ContextMenu",
            "should_open_asset_in_inspector",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus(_coreui, "");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###foo.ct_foo_asset", .{}, null);

                    ctx.menuAction(_coreui, .Click, "###ObjContextMenu/###OpenIn_ct_editor_inspector_tab");

                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_2");
                    ctx.windowFocus(_coreui, "");
                    //ctx.itemAction (_coreui, .Check, "**/018b5846-c2d5-712f-bb12-9d9d15321ecb/bool/###edit", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "Inspector",
            "should_set_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset2.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###asset1.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/018e4c98-35a7-7cdb-8538-6c3030bc4fe9/###AssetInputMenu", .{}, null);
                    ctx.yield(_coreui, 1);
                    ctx.menuAction(_coreui, .Click, "//$FOCUSED/###SelectFrom/###1");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?;
                    const proto_obj = _assetdb.getObjId(_uuid.fromStr("018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f").?).?;

                    std.testing.expect(proto_obj.eql(db.getPrototype(db.readObj(obj).?))) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "Inspector",
            "should_clear_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset1_1.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/###AssetInputMenu", .{}, null);
                    ctx.yield(_coreui, 1);
                    ctx.menuAction(_coreui, .Click, "//$FOCUSED/###Clear");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                    std.testing.expect(db.getPrototype(db.readObj(obj).?).isEmpty()) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = _coreui.registerTest(
            "Inspector",
            "should_add_remove_tag",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###foo.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/###AddTags", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/018e0348-b358-779f-b40c-7d34d3fca2a7/###Tag", .{}, null);

                    ctx.itemAction(_coreui, .Click, "**/018e0348-b358-779f-b40c-7d34d3fca2a7/###Tag", .{}, null);
                }
            },
        );

        _ = _coreui.registerTest(
            "Inspector",
            "should_add_ref_to_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    _kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(_coreui, 1);

                    ctx.setRef(_coreui, "###ct_editor_asset_browser_tab_1");
                    ctx.itemAction(_coreui, .DoubleClick, "**/###ROOT/###asset2.ct_foo_asset", .{}, null);
                    ctx.itemAction(_coreui, .Click, "**/###ROOT/###asset1.ct_foo_asset", .{}, null);

                    ctx.setRef(_coreui, "###ct_editor_inspector_tab_1");
                    ctx.windowFocus(_coreui, "");

                    ctx.itemAction(_coreui, .Click, "**/018e4c98-35a7-7cdb-8538-6c3030bc4fe9/reference_set/###PropertyCtxMenu", .{}, null);
                    ctx.yield(_coreui, 1);
                    ctx.menuAction(_coreui, .Click, "//$FOCUSED/###AddToSet/###SelectFrom/###1");

                    const db = _kernel.getDb();
                    const obj = _assetdb.getObjId(_uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(db, db.readObj(obj).?, .ReferenceSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 1) catch |err| {
                        _coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );
    }
});

// Cdb
var AssetTypeIdx: cdb.TypeIdx = undefined;
var ProjectTypeIdx: cdb.TypeIdx = undefined;

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.Db) !void {
        AssetTypeIdx = assetdb.Asset.typeIdx(db);
        ProjectTypeIdx = assetdb.Project.typeIdx(db);
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
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _uuid = apidb.getZigApi(module_name, cetech1.uuid.UuidAPI).?;
    _profiler = apidb.getZigApi(module_name, profiler.ProfilerAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.globalVarValue(editor.TabTypeI, module_name, INSPECTOR_TAB_NAME, inspector_tab);

    _g.asset_prop_aspect = try apidb.globalVarValue(public.UiPropertiesAspect, module_name, ASSET_PROPERTIES_ASPECT_NAME, asset_properties_aspec);
    _g.color4f_properties_aspec = try apidb.globalVarValue(public.UiEmbedPropertiesAspect, module_name, COLOR4F_PROPERTY_ASPECT_NAME, color4f_properties_aspec);
    _g.hide_proto_property_config_aspect = try apidb.globalVarValue(public.UiPropertiesConfigAspect, module_name, FOLDER_PROPERTY_CONFIG_ASPECT_NAME, folder_properties_config_aspect);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &inspector_tab, load);

    try apidb.setOrRemoveZigApi(module_name, public.InspectorAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_inspector(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}

// Assert C api == C api in zig.
comptime {}
