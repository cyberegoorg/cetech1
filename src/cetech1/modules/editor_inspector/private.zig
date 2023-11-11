const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport(@cInclude("cetech1/modules/editor_properties/editor_properties.h"));

const cetech1 = @import("cetech1");
const public = @import("editor_inspector.zig");
const editorui = cetech1.editorui;
const editorui_icons = cetech1.editorui;
const editor = @import("editor");
const editor_asset_browser = @import("editor_asset_browser");

const Icons = cetech1.editorui.CoreIcons;

const MODULE_NAME = "editor_inspector";
const INSPECTOR_TAB_NAME = "ct_editor_inspector_tab";
const INSPECTOR_TAB_NAME_HASH = cetech1.strid.strId32(INSPECTOR_TAB_NAME);

const COLOR4F_PROPERTY_ASPECT_NAME = "ct_color_4f_properties_aspect";
const FOLDER_NAME_PROPERTY_ASPECT_NAME = "ct_folder_name_property_aspect";
const FOLDER_PROPERTY_CONFIG_ASPECT_NAME = "ct_folder_property_config_aspect";
const ASSET_PROPERTIES_ASPECT_NAME = "ct_asset_properties_aspect";

const PROPERTIES_EDITOR_ICON = Icons.FA_LIST;

const PROP_HEADER_BG_COLOR = .{ 0.2, 0.2, 0.2, 0.65 };
const PROTOTYPE_PROPERTY_OVERIDED_COLOR = .{ 0.0, 0.8, 1.0, 1.0 };
const PROTOTYPE_PROPERTY_COLOR = .{ 0.5, 0.5, 0.5, 1.0 };

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;
var _asset_browser: *editor_asset_browser.AssetBrowserAPI = undefined;

// Global state
const G = struct {
    main_db: cetech1.cdb.CdbDb = undefined,
    tab_vt: *editor.EditorTabTypeI = undefined,
    asset_prop_aspect: *editorui.UiPropertiesAspect = undefined,
    color4f_properties_aspec: *editorui.UiEmbedPropertiesAspect = undefined,
    folder_name_prop_aspect: *editorui.UiPropertyAspect = undefined,
    folder_property_config_aspect: *editorui.UiPropertiesConfigAspect = undefined,
};
var _g: *G = undefined;

var api = public.InspectorAPI{
    .uiPropLabel = uiPropLabel,
    .uiPropInput = uiInputForProperty,
    .uiPropInputBegin = uiPropInputBegin,
    .uiPropInputEnd = uiPropInputEnd,
    .cdbPropertiesView = cdbPropertiesView,
    .cdbPropertiesObj = cdbPropertiesObj,
    .uiAssetInput = uiAssetInput,
    .formatedPropNameToBuff = formatedPropNameToBuff,
    .getPropertyColor = getPropertyColor,

    .beginSection = beginSection,
    .endSection = endSection,
};

fn openNewInspectorForObj(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void {
    _editor.openTabWithPinnedObj(db, INSPECTOR_TAB_NAME_HASH, obj);
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

fn onSetProperty(selected_data: ?*anyopaque, data: editor.UiModalI.Data) callconv(.C) void {
    const selection: *cetech1.cdb.ObjId = @alignCast(@ptrCast(selected_data orelse return));

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    const params = std.mem.bytesToValue(editor.SelectAssetParams, data.data[0..@sizeOf(editor.SelectAssetParams)]);
    var obj: ?cetech1.cdb.ObjId = null;

    const asset = _editor.getFirstSelected(allocator, &_g.main_db, selection.*);

    if (cetech1.assetdb.FolderType.isSameType(asset)) {
        obj = asset;
    } else if (cetech1.assetdb.AssetType.isSameType(asset)) {
        obj = cetech1.assetdb.AssetType.readSubObj(&_g.main_db, _g.main_db.readObj(asset).?, .Object);
    } else {
        return;
    }

    const w = _g.main_db.writeObj(params.obj).?;
    defer _g.main_db.writeCommit(w);
    _g.main_db.setRef(w, params.prop_idx, obj.?) catch |err| {
        _log.err(MODULE_NAME, "Could not set reference {} prop_idx {} : {}", .{ params.obj, params.prop_idx, err });
    };
}

fn onSetNewPrototype(selected_data: ?*anyopaque, data: editor.UiModalI.Data) callconv(.C) void {
    const params = std.mem.bytesToValue(editor.SelectAssetParams, data.data[0..@sizeOf(editor.SelectAssetParams)]);

    const selection: *cetech1.cdb.ObjId = @alignCast(@ptrCast(selected_data orelse return));

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    const selected_obj = _editor.getFirstSelected(allocator, &_g.main_db, selection.*);

    var proto_obj: cetech1.cdb.ObjId = selected_obj;
    if (cetech1.assetdb.AssetType.isSameType(selected_obj)) {
        proto_obj = cetech1.assetdb.AssetType.readSubObj(&_g.main_db, _g.main_db.readObj(selected_obj).?, .Object).?;
    }

    _g.main_db.setPrototype(params.obj, proto_obj) catch |err| {
        _log.err(MODULE_NAME, "Could not set prototype {} for {} : {}", .{ selected_obj, params.obj, err });
    };
}

fn uiAssetInput(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    prop_idx: u32,
    read_only: bool,
    in_table: bool,
) !void {
    const obj_r = db.readObj(obj) orelse return;

    const defs = db.getTypePropDef(obj.type_hash).?;
    const prop_def = defs[prop_idx];

    var value_obj: cetech1.cdb.ObjId = .{};
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
    _editorui.pushIntId(prop_idx);
    defer _editorui.popId();

    return uiAssetInputGeneric(
        allocator,
        db,
        obj,
        value_obj,
        read_only,
        false,
        prop_idx,
        in_table,
    );
}

fn uiAssetInputProto(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, value_obj: cetech1.cdb.ObjId, read_only: bool) !void {
    return uiAssetInputGeneric(
        allocator,
        db,
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
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    value_obj: cetech1.cdb.ObjId,
    read_only: bool,
    is_proto: bool,
    prop_idx: u32,
    in_table: bool,
) !void {
    var buff: [128:0]u8 = undefined;
    var asset_name: []u8 = undefined;
    const value_asset: ?cetech1.cdb.ObjId = _assetdb.getAssetForObj(value_obj);

    if (value_asset) |asset| {
        const path = try _assetdb.getFilePathForAsset(asset, allocator);
        defer allocator.free(path);
        asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{path});
    } else {
        if (cetech1.assetdb.FolderType.isSameType(value_obj)) {
            const path = try _assetdb.getPathForFolder(value_obj, allocator);
            defer allocator.free(path);
            asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{if (std.fs.path.dirname(path)) |p| p else "/"});
        } else {
            asset_name = try std.fmt.bufPrintZ(&buff, "", .{});
        }
    }

    _editorui.pushObjId(obj);
    defer _editorui.popId();

    if (in_table) {
        _editorui.tableNextColumn();
    }

    if (!is_proto) {
        try uiInputProtoBtns(db, obj, prop_idx);
    }

    if (_editorui.beginPopup("ui_asset_context_menu", .{})) {
        if (_asset_browser.selectObjFromBrowserMenu(allocator, db, obj, obj.type_hash)) |selected| {
            if (is_proto) {
                try db.setPrototype(obj, selected);
            } else {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                try db.setRef(w, prop_idx, selected);
            }
        }

        _editorui.separator();

        if (value_asset) |asset| {
            _editor.openObjInCtxMenu(allocator, db, asset);
        }

        if (_editorui.menuItem("Clear", .{ .enabled = !read_only and value_asset != null })) {
            if (is_proto) {
                try db.setPrototype(obj, cetech1.cdb.OBJID_ZERO);
            } else {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                try db.clearRef(w, prop_idx);
            }
        }

        _editorui.endPopup();
    }

    if (_editorui.button(Icons.FA_ELLIPSIS, .{})) {
        _editorui.openPopup("ui_asset_context_menu", .{});
    }

    _editorui.sameLine(.{});
    _editorui.setNextItemWidth(-std.math.floatMin(f32));
    _ = _editorui.inputText("", .{
        .buf = asset_name,
        .flags = .{
            .read_only = true,
            .auto_select_all = true,
        },
    });

    if (_editorui.beginDragDropTarget()) {
        if (_editorui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
            var drag_obj: cetech1.cdb.ObjId = std.mem.bytesToValue(cetech1.cdb.ObjId, payload.data);
            if (cetech1.assetdb.AssetType.isSameType(drag_obj)) {
                drag_obj = cetech1.assetdb.AssetType.readSubObj(&_g.main_db, _g.main_db.readObj(drag_obj).?, .Object).?;
            }

            if (is_proto) {
                if (!drag_obj.eq(obj) and drag_obj.type_hash.id == obj.type_hash.id) {
                    try db.setPrototype(obj, drag_obj);
                }
            } else {
                const allowed_type_hash = db.getTypePropDef(obj.type_hash).?[prop_idx].type_hash;
                if (allowed_type_hash.id == 0 or allowed_type_hash.id == drag_obj.type_hash.id) {
                    const w = db.writeObj(obj).?;
                    defer db.writeCommit(w);
                    try db.setRef(w, prop_idx, drag_obj);
                }
            }
        }
        defer _editorui.endDragDropTarget();
    }
}

fn beginPropTable(name: [:0]const u8) bool {
    return _editorui.beginTable(name, .{
        .column = 2,
        .flags = .{
            .sizing = .stretch_prop,
            .no_saved_settings = true,
            //.borders = cetech1.editorui.TableBorderFlags.outer,
            //.row_bg = true,
            //.resizable = true,
        },
    });
}

fn endPropTabel() void {
    _editorui.endTable();
}

fn beginSection(label: [:0]const u8, leaf: bool, default_open: bool) bool {
    const open = _editorui.treeNodeFlags(label, .{
        .framed = true,
        .leaf = leaf,
        .default_open = default_open,
        .no_auto_open_on_log = !leaf,
        //.span_full_width = true,
        .span_avail_width = true,
    });

    return open;
}

fn endSection(open: bool) void {
    // if (open) _editorui.endChild();
    if (open) _editorui.treePop();
}

fn cdbPropertiesView(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: editorui.cdbPropertiesViewArgs) !void {
    _editorui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 10 });
    defer _editorui.popStyleVar(.{});
    try cdbPropertiesObj(allocator, db, obj, args);
}
const REMOVED_COLOR = .{ 0.7, 0.0, 0.0, 1.0 };

fn objContextMenuBtn(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: ?u32, in_set_obj: ?cetech1.cdb.ObjId) !void {
    if (_editorui.beginPopup("property_obj_menu", .{})) {
        try _editorui.objContextMenu(allocator, db, obj, prop_idx, in_set_obj);
        _editorui.endPopup();
    }

    if (_editorui.button(Icons.FA_ELLIPSIS, .{})) {
        _editorui.openPopup("property_obj_menu", .{});
    }
}

fn cdbPropertiesObj(
    allocator: std.mem.Allocator,
    db: *cetech1.cdb.CdbDb,
    obj: cetech1.cdb.ObjId,
    args: editorui.cdbPropertiesViewArgs,
) !void {
    // Find properties asspect for obj type.
    const ui_aspect = db.getAspect(editorui.UiPropertiesAspect, obj.type_hash);
    if (ui_aspect) |aspect| {
        aspect.ui_properties.?(&allocator, db.db, obj, args);
        return;
    }

    _editorui.pushObjId(obj);
    defer _editorui.popId();

    const obj_r = db.readObj(obj) orelse return;

    // Find properties config asspect for obj type.
    const config_aspect = db.getAspect(editorui.UiPropertiesConfigAspect, obj.type_hash);

    const prototype_obj = db.getPrototype(obj_r);
    //const has_prototype = !prototype_obj.isEmpty();

    const prop_defs = db.getTypePropDef(obj.type_hash).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    var show_proto = true;

    // Exist config aspect?
    if (config_aspect) |aspect| {
        show_proto = !aspect.hide_prototype;
    }

    // Scalars valus
    if (beginPropTable("prop2")) {
        defer endPropTabel();

        if (show_proto) {
            if (api.uiPropLabel(allocator, "Prototype", null, args)) {
                try uiAssetInputProto(allocator, db, obj, prototype_obj, false);
            }
        }

        for (prop_defs, 0..) |prop_def, idx| {
            const prop_idx: u32 = @truncate(idx);

            const prop_name = try api.formatedPropNameToBuff(&prop_name_buff, prop_def.name);
            const prop_color = api.getPropertyColor(db, obj, prop_idx);

            switch (prop_def.type) {
                else => {},
            }
            var ui_prop_aspect: ?*editorui.UiPropertyAspect = null;
            if (prop_def.type != .REFERENCE_SET and prop_def.type != .SUBOBJECT_SET) {
                ui_prop_aspect = db.getPropertyAspect(editorui.UiPropertyAspect, obj.type_hash, prop_idx);
                // If exist aspect and is empty hide property.
                if (ui_prop_aspect) |aspect| {
                    if (aspect.ui_property == null) continue;
                    if (aspect.ui_property) |ui| {
                        ui(&allocator, @ptrCast(db.db), obj, prop_idx, args);
                        continue;
                    } else {
                        continue;
                    }
                }
            }

            switch (prop_def.type) {
                .REFERENCE_SET, .SUBOBJECT_SET => {
                    const ui_embed_prop_aspect = db.getPropertyAspect(editorui.UiEmbedPropertyAspect, obj.type_hash, prop_idx);
                    if (ui_embed_prop_aspect) |aspect| {
                        const lbl = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                        if (uiPropLabel(allocator, lbl, prop_color, args)) {
                            aspect.ui_properties.?(&allocator, db.db, obj, prop_idx, args);
                        }
                    }
                },

                // If subobject type implement UiEmbedPropertiesAspect show it in table
                .SUBOBJECT => {
                    const subobj = db.readSubObj(obj_r, prop_idx);
                    const ui_embed_prop_aspect = db.getAspect(editorui.UiEmbedPropertiesAspect, prop_def.type_hash);
                    const lbl = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                    if (ui_embed_prop_aspect) |aspect| {
                        if (uiPropLabel(allocator, lbl, prop_color, args)) {
                            _editorui.tableNextColumn();
                            if (subobj == null) {
                                try objContextMenuBtn(allocator, db, obj, prop_idx, null);
                            } else {
                                aspect.ui_properties.?(&allocator, db.db, subobj.?, args);
                            }
                        }
                    }
                    continue;
                },

                .REFERENCE => {
                    var subobj: ?cetech1.cdb.ObjId = null;

                    if (args.filter) |filter| {
                        if (_editorui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                            continue;
                        }
                    }

                    subobj = db.readRef(obj_r, prop_idx);

                    const label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});

                    if (uiPropLabel(allocator, label, prop_color, args)) {
                        try uiAssetInput(allocator, db, obj, prop_idx, false, true);
                    }
                },
                else => {
                    if (args.filter) |filter| {
                        if (_editorui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                            continue;
                        }
                    }

                    const label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                    if (api.uiPropLabel(allocator, label, prop_color, args)) {
                        if (ui_prop_aspect) |aspect| {
                            if (aspect.ui_property) |ui| {
                                ui(&allocator, @ptrCast(db.db), obj, prop_idx, args);
                            }
                        } else {
                            try api.uiPropInput(db, obj, prop_idx);
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

        const prop_name = try api.formatedPropNameToBuff(&prop_name_buff, prop_def.name);
        const prop_color = api.getPropertyColor(db, obj, prop_idx);

        const ui_prop_aspect = db.getPropertyAspect(editorui.UiPropertyAspect, obj.type_hash, prop_idx);
        // If exist aspect and is empty hide property.
        if (ui_prop_aspect) |aspect| {
            if (aspect.ui_property == null) continue;

            if (aspect.ui_property) |ui| {
                ui(&allocator, @ptrCast(db.db), obj, prop_idx, args);
                continue;
            } else {
                continue;
            }
        }

        _editorui.pushIntId(prop_idx);
        defer _editorui.popId();

        switch (prop_def.type) {
            .SUBOBJECT => {
                var subobj: ?cetech1.cdb.ObjId = null;

                if (args.filter) |filter| {
                    if (_editorui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                        continue;
                    }
                }

                subobj = db.readSubObj(obj_r, prop_idx);

                if (db.getAspect(editorui.UiEmbedPropertiesAspect, prop_def.type_hash) != null) continue;

                const label = try std.fmt.bufPrintZ(&buff, "{s}{s}", .{ prop_name, if (prop_def.type == .REFERENCE) " " ++ Icons.FA_LINK else "" });

                try objContextMenuBtn(allocator, db, obj, prop_idx, null);
                _editorui.sameLine(.{});

                if (prop_color) |color| {
                    _editorui.pushStyleColor4f(.{ .idx = .text, .c = color });
                }
                const open = beginSection(label, subobj == null, true);
                defer endSection(open);

                if (prop_color != null) {
                    _editorui.popStyleColor(.{});
                }

                if (open) {
                    if (subobj != null) {
                        try cdbPropertiesObj(allocator, db, subobj.?, args);
                    }
                }
            },

            .SUBOBJECT_SET, .REFERENCE_SET => {
                if (db.getPropertyAspect(editorui.UiEmbedPropertyAspect, obj.type_hash, prop_idx) != null) {
                    continue;
                }

                const prop_label = try std.fmt.bufPrintZ(&buff, "{s}{s}", .{ prop_name, if (prop_def.type == .REFERENCE_SET) " " ++ Icons.FA_LINK else "" });

                try objContextMenuBtn(allocator, db, obj, prop_idx, null);
                _editorui.sameLine(.{});

                const open = beginSection(prop_label, false, true);
                defer endSection(open);

                if (open) {
                    var set: ?[]const cetech1.cdb.ObjId = undefined;
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSet(obj_r, prop_idx, allocator);
                    } else {
                        set = try db.readSubObjSet(obj_r, prop_idx, allocator);
                    }

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            const label = _editorui.buffFormatObjLabel(allocator, &buff, db, subobj) orelse try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});

                            _editorui.pushIntId(@truncate(set_idx));
                            defer _editorui.popId();

                            try objContextMenuBtn(allocator, db, obj, prop_idx, subobj);
                            _editorui.sameLine(.{});

                            _editorui.pushStyleColor4f(.{ .idx = .text, .c = _editorui.getObjColor(db, obj, prop_idx, subobj) });
                            const open_inset = beginSection(label, false, true);

                            //_editorui.sameLine(.{});
                            defer endSection(open_inset);
                            _editorui.popStyleColor(.{});

                            if (open_inset) {
                                try cdbPropertiesObj(allocator, db, subobj, args);
                            }
                        }
                    }
                }
            },

            else => {},
        }
    }
}

fn uiInputProtoBtns(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) !void {
    const proto_obj = db.getPrototype(db.readObj(obj).?);
    if (proto_obj.isEmpty()) return;

    const types = db.getTypePropDef(obj.type_hash).?;
    const prop_def = types[prop_idx];

    const is_overided = db.isPropertyOverrided(db.readObj(obj).?, prop_idx);

    if (prop_def.type == .BLOB) return;

    if (_editorui.beginPopup("property_protoypes_menu", .{})) {
        if (_editorui.menuItem(Icons.FA_ARROW_ROTATE_LEFT ++ "  " ++ "Reset to prototype value", .{ .enabled = is_overided })) {
            const w = db.writeObj(obj).?;
            defer db.writeCommit(w);
            db.resetPropertyOveride(w, prop_idx);
        }

        if (_editorui.menuItem(Icons.FA_ARROW_UP ++ "  " ++ "Propagate to prototype", .{ .enabled = is_overided })) {
            // Set value from parent. This is probably not need.
            {
                const w = db.writeObj(proto_obj).?;
                defer db.writeCommit(w);
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
                    .BLOB => {},
                    else => {},
                }
                db.resetPropertyOveride(w, prop_idx);
            }

            // reset value overide
            {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.resetPropertyOveride(w, prop_idx);
            }
        }

        _editorui.endPopup();
    }

    if (_editorui.button(Icons.FA_SWATCHBOOK, .{})) {
        _editorui.openPopup("property_protoypes_menu", .{});
    }

    _editorui.sameLine(.{});
}

fn uiPropInputBegin(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) !void {
    _editorui.tableNextColumn();

    _editorui.pushObjId(obj);
    _editorui.pushIntId(prop_idx);

    try uiInputProtoBtns(db, obj, prop_idx);

    _editorui.setNextItemWidth(-std.math.floatMin(f32));
}

fn uiPropInputEnd() void {
    _editorui.popId();
    _editorui.popId();
}

fn uiInputForProperty(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) !void {
    var buf: [128:0]u8 = undefined;
    @memset(&buf, 0);

    const reader = db.readObj(obj) orelse return;

    try uiPropInputBegin(db, obj, prop_idx);
    defer uiPropInputEnd();

    const prop_defs = db.getTypePropDef(obj.type_hash).?;
    const prop_def = prop_defs[prop_idx];

    switch (prop_def.type) {
        .BOOL => {
            var value = db.readValue(bool, reader, prop_idx);
            if (_editorui.checkbox("", .{
                .v = &value,
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(bool, w, prop_idx, value);
            }
        },
        .F32 => {
            var value = db.readValue(f32, reader, prop_idx);
            if (_editorui.inputFloat("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(f32, w, prop_idx, value);
            }
        },
        .F64 => {
            var value = db.readValue(f64, reader, prop_idx);
            if (_editorui.inputDouble("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(f64, w, prop_idx, value);
            }
        },
        .I32 => {
            var value = db.readValue(i32, reader, prop_idx);
            if (_editorui.inputI32("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(i32, w, prop_idx, value);
            }
        },
        .U32 => {
            var value = db.readValue(u32, reader, prop_idx);
            if (_editorui.inputU32("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(u32, w, prop_idx, value);
            }
        },
        .I64 => {
            var value = db.readValue(i64, reader, prop_idx);
            if (_editorui.inputI64("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(i64, w, prop_idx, value);
            }
        },
        .U64 => {
            var value = db.readValue(u64, reader, prop_idx);
            if (_editorui.inputU64("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(u64, w, prop_idx, value);
            }
        },
        .STR => {
            const name = db.readStr(reader, prop_idx);
            if (name) |str| {
                _ = try std.fmt.bufPrintZ(&buf, "{s}", .{str});
            }
            if (_editorui.inputText("", .{
                .buf = &buf,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                var new_name_buf: [128:0]u8 = undefined;
                const new_name = try std.fmt.bufPrintZ(&new_name_buf, "{s}", .{std.mem.sliceTo(&buf, 0)});
                try db.setStr(w, prop_idx, new_name);
            }
        },
        .BLOB => {
            _editorui.textUnformatted("---");
        },
        else => {
            _editorui.textUnformatted("- !!INVALID TYPE!! -");
            _log.err(MODULE_NAME, "Invalid property type for uiInputForProperty {}", .{prop_def.type});
        },
    }
}

fn uiPropLabel(allocator: std.mem.Allocator, name: [:0]const u8, color: ?[4]f32, args: editorui.cdbPropertiesViewArgs) bool {
    if (args.filter) |filter| {
        if (_editorui.uiFilterPass(allocator, cetech1.fromCstrZ(filter), name, false) == null) return false;
    }
    _editorui.tableNextColumn();

    // const max_x = _editorui.getContentRegionAvail()[0];
    // const style = _editorui.getStyle();
    // const txt_size = _editorui.calcTextSize(name, .{});
    // const space_x = max_x - _editorui.getScrollX() - style.item_spacing[0] * 0.5 - txt_size[0];

    // _editorui.dummy(.{ .w = space_x, .h = txt_size[1] });
    // _editorui.sameLine(.{});

    _editorui.alignTextToFramePadding();
    if (color) |colorr| {
        _editorui.textUnformattedColored(colorr, name);
    } else {
        _editorui.textUnformatted(name);
    }

    return true;
}

// Asset properties aspect
var asset_properties_aspec = editorui.UiPropertiesAspect.implement(assetUiProperiesAspect);
fn assetUiProperiesAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    args: editorui.cdbPropertiesViewArgs,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    const obj_r = db.readObj(obj) orelse return;

    var buf: [128:0]u8 = undefined;

    _editorui.separatorText("Asset");

    if (beginPropTable("prop2")) {
        defer endPropTabel();
        // Asset UUID
        if (_assetdb.getUuid(obj)) |asset_uuid| {
            if (api.uiPropLabel(allocator, "UUID", null, args)) {
                _editorui.tableNextColumn();
                _ = try std.fmt.bufPrintZ(&buf, "{s}", .{asset_uuid});

                _editorui.setNextItemWidth(-std.math.floatMin(f32));
                _ = _editorui.inputText("", .{
                    .buf = &buf,
                    .flags = .{
                        .read_only = true,
                        .auto_select_all = true,
                    },
                });
            }
        }

        // Asset name
        if (api.uiPropLabel(allocator, "Name", null, args)) {
            try api.uiPropInput(&db, obj, cetech1.assetdb.AssetType.propIdx(.Name));
        }

        if (api.uiPropLabel(allocator, "Description", null, args)) {
            try uiInputForProperty(&db, obj, cetech1.assetdb.AssetType.propIdx(.Description));
        }

        // Tags
        // TODO: SHIT HACK
        const ui_prop_aspect = db.getPropertyAspect(editorui.UiEmbedPropertyAspect, obj.type_hash, cetech1.assetdb.AssetType.propIdx(.Tags));
        // If exist aspect and is empty hide property.
        if (ui_prop_aspect) |aspect| {
            if (aspect.ui_properties) |ui| {
                if (api.uiPropLabel(allocator, "Tags", null, args)) {
                    ui(&allocator, @ptrCast(db.db), obj, cetech1.assetdb.AssetType.propIdx(.Tags), args);
                }
            }
        }

        // Folder
        if (api.uiPropLabel(allocator, "Folder", null, args)) {
            try uiAssetInput(allocator, &db, obj, cetech1.assetdb.AssetType.propIdx(.Folder), false, true);
        }
    }

    //_editorui.separator();

    // Asset object
    _editorui.separatorText("Asset object");
    try api.cdbPropertiesObj(allocator, &db, cetech1.assetdb.AssetType.readSubObj(&db, obj_r, .Object).?, args);
}
//

// Folder properties aspect
var folder_name_prop_aspect = editorui.UiPropertyAspect.implement(folderUiNameProperyAspect);
fn folderUiNameProperyAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    prop_idx: u32,
    args: editorui.cdbPropertiesViewArgs,
) !void {
    _ = prop_idx;

    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);

    var buf: [128:0]u8 = undefined;

    // Folder name
    if (uiPropLabel(allocator, "Name", null, args)) {
        try api.uiPropInputBegin(&db, obj, cetech1.assetdb.FolderType.propIdx(.Name));
        defer api.uiPropInputEnd();

        const parent = cetech1.assetdb.FolderType.readRef(&db, db.readObj(obj).?, .Parent);
        const is_root_folder = parent == null;

        const name = cetech1.assetdb.FolderType.readStr(&db, db.readObj(obj).?, .Name);
        if (name) |str| {
            _ = try std.fmt.bufPrintZ(&buf, "{s}", .{str});
        } else {
            _ = try std.fmt.bufPrintZ(&buf, "", .{});
        }

        if (_editorui.inputText("", .{
            .buf = &buf,
            .flags = .{
                .enter_returns_true = !is_root_folder,
                .read_only = is_root_folder,
            },
        })) {
            var new_name_buf: [128:0]u8 = undefined;
            const new_name = try std.fmt.bufPrintZ(&new_name_buf, "{s}", .{std.mem.sliceTo(&buf, 0)});

            if (try _assetdb.isAssetNameValid(allocator, &db, parent.?, cetech1.assetdb.FolderType.type_hash, new_name)) {
                const w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                try cetech1.assetdb.FolderType.setStr(&db, w, .Name, new_name);
            }
        }
    }
}
//

// Asset properties aspect
var color4f_properties_aspec = editorui.UiEmbedPropertiesAspect.implement(color4fUiProperiesAspect);
fn color4fUiProperiesAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
    args: editorui.cdbPropertiesViewArgs,
) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, _cdb);
    _ = allocator;
    _ = args;

    _editorui.pushObjId(obj);
    defer _editorui.popId();

    var color = cetech1.cdb_types.color4fToSlice(&db, obj);

    _editorui.setNextItemWidth(-1);
    if (_editorui.colorEdit4("", .{ .col = &color })) {
        const w = db.writeObj(obj).?;
        defer db.writeCommit(w);
        cetech1.cdb_types.color4fFromSlice(&db, w, color);
    }
}
//

const PropertyTab = struct {
    tab_i: editor.EditorTabI,
    db: cetech1.cdb.CdbDb,
    selected_obj: cetech1.cdb.ObjId,
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};

// Fill editor tab interface
var inspector_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = INSPECTOR_TAB_NAME,
    .tab_hash = cetech1.strid.strId32(INSPECTOR_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,

    .menu_name = tabMenuItem,
    .title = tabTitle,
    .can_open = tabCanOpen,
    .create = tabCreate,
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
    .obj_selected = tabSelectedObject,
});

fn tabMenuItem() [:0]const u8 {
    return PROPERTIES_EDITOR_ICON ++ " " ++ "Inspector";
}

// Return tab title
fn tabTitle(inst: *editor.TabO) [:0]const u8 {
    _ = inst;
    return PROPERTIES_EDITOR_ICON ++ " " ++ "Inspector";
}

// Can open tab
fn tabCanOpen(db: *cetech1.cdb.Db, selection: cetech1.cdb.ObjId) bool {
    _ = db;
    _ = selection;

    return true;
}

// Create new FooTab instantce
fn tabCreate(db: *cetech1.cdb.Db) ?*editor.EditorTabI {
    var tab_inst = _allocator.create(PropertyTab) catch undefined;
    tab_inst.* = PropertyTab{
        .tab_i = .{
            .vt = _g.tab_vt,
            .inst = @ptrCast(tab_inst),
        },
        .db = cetech1.cdb.CdbDb.fromDbT(db, _cdb),
        .selected_obj = .{},
    };

    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: *editor.EditorTabI) void {
    const tab_o: *PropertyTab = @alignCast(@ptrCast(tab_inst.inst));
    _allocator.destroy(tab_o);
}

// Draw tab menu
fn tabMenu(inst: *editor.TabO) void {
    const tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
    _ = tab_o;
}

// Draw tab content
fn tabUi(inst: *editor.TabO) void {
    var tab_o: *PropertyTab = @alignCast(@ptrCast(inst));

    if (tab_o.selected_obj.id == 0 and tab_o.selected_obj.type_hash.id == 0) {
        return;
    }

    var tmp_arena = _tempalloc.createTempArena() catch undefined;
    defer _tempalloc.destroyTempArena(tmp_arena);
    const allocator = tmp_arena.allocator();

    if (_editorui.uiFilter(&tab_o.filter_buff, tab_o.filter)) |filter| {
        tab_o.filter = filter;
    }

    if (_editorui.beginChild("Inspector", .{ .border = false })) {
        defer _editorui.endChild();

        const selectected_count = _editorui.selectedCount(allocator, &tab_o.db, tab_o.selected_obj);
        if (selectected_count == 0) return;

        var obj: cetech1.cdb.ObjId = tab_o.selected_obj;

        if (selectected_count == 1) {
            obj = _editorui.getFirstSelected(allocator, &tab_o.db, tab_o.selected_obj);
        }

        api.cdbPropertiesView(tmp_arena.allocator(), &tab_o.db, obj, .{ .filter = if (tab_o.filter) |f| f.ptr else null }) catch |err| {
            _log.err(MODULE_NAME, "Problem in cdbProperties {}", .{err});
        };
    }
}

// Selected object
fn tabSelectedObject(inst: *editor.TabO, cdb: ?*cetech1.cdb.Db, obj: cetech1.cdb.ObjId) void {
    var tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
    _ = cdb;
    tab_o.selected_obj = obj;
}

var folder_properties_config_aspect = editorui.UiPropertiesConfigAspect{
    .hide_prototype = true,
};

fn cdbCreateTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, _cdb);

    try cetech1.assetdb.FolderType.addPropertyAspect(
        &db,
        editorui.UiPropertyAspect,
        .Name,
        _g.folder_name_prop_aspect,
    );

    try cetech1.assetdb.FolderType.addAspect(
        &db,
        editorui.UiPropertiesConfigAspect,
        _g.folder_property_config_aspect,
    );

    try cetech1.assetdb.AssetType.addAspect(
        &db,
        editorui.UiPropertiesAspect,
        _g.asset_prop_aspect,
    );

    try cetech1.cdb_types.Color4fType.addAspect(
        &db,
        editorui.UiEmbedPropertiesAspect,
        _g.color4f_properties_aspec,
    );
}

var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(cdbCreateTypes);

fn init(main_db: *cetech1.cdb.Db) !void {
    _g.main_db = cetech1.cdb.CdbDb.fromDbT(main_db, _cdb);
}

fn shutdown() !void {}

var editor_kernel_task = cetech1.kernel.KernelTaskI.implement(
    "PropertiesEditor",
    &[_]cetech1.strid.StrId64{},
    init,
    shutdown,
);

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
    _asset_browser = apidb.getZigApi(editor_asset_browser.AssetBrowserAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    _g.tab_vt = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, INSPECTOR_TAB_NAME, .{});
    _g.tab_vt.* = inspector_tab;

    _g.asset_prop_aspect = try apidb.globalVar(editorui.UiPropertiesAspect, MODULE_NAME, ASSET_PROPERTIES_ASPECT_NAME, .{});
    _g.asset_prop_aspect.* = asset_properties_aspec;

    _g.folder_name_prop_aspect = try apidb.globalVar(editorui.UiPropertyAspect, MODULE_NAME, FOLDER_NAME_PROPERTY_ASPECT_NAME, .{});
    _g.folder_name_prop_aspect.* = folder_name_prop_aspect;

    _g.color4f_properties_aspec = try apidb.globalVar(editorui.UiEmbedPropertiesAspect, MODULE_NAME, COLOR4F_PROPERTY_ASPECT_NAME, .{});
    _g.color4f_properties_aspec.* = color4f_properties_aspec;

    _g.folder_property_config_aspect = try apidb.globalVar(editorui.UiPropertiesConfigAspect, MODULE_NAME, FOLDER_PROPERTY_CONFIG_ASPECT_NAME, .{});
    _g.folder_property_config_aspect.* = folder_properties_config_aspect;

    try apidb.implOrRemove(cetech1.kernel.KernelTaskI, &editor_kernel_task, load);
    try apidb.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(editor.EditorTabTypeI, &inspector_tab, load);
    try apidb.setOrRemoveZigApi(public.InspectorAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_inspector(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_editorui_ui_properties_aspect) == @sizeOf(editorui.UiPropertiesAspect));
    std.debug.assert(@sizeOf(c.ct_editorui_ui_property_aspect) == @sizeOf(editorui.UiPropertyAspect));
    std.debug.assert(@sizeOf(c.ct_editor_cdb_proprties_args) == @sizeOf(editorui.cdbPropertiesViewArgs));
}
