const std = @import("std");
const Allocator = std.mem.Allocator;

const public = cetech1.editor.inspector;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const kernel = cetech1.kernel;
const assetdb = cetech1.assetdb;
const coreui = cetech1.coreui;
const coreui_icons = cetech1.coreui;
const profiler = cetech1.profiler;
const math = cetech1.math;

const editor = cetech1.editor;
const editor_tabs = cetech1.editor.tabs;

const Icons = coreui.CoreIcons;

const module_name = .editor_inspector;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

const INSPECTOR_TAB_NAME = "ct_editor_inspector_tab";
const INSPECTOR_TAB_NAME_HASH = .fromStr(INSPECTOR_TAB_NAME);

const PROP_HEADER_BG_COLOR = .{ 0.2, 0.2, 0.2, 0.65 };

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const uuid = cetech1.uuid;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
const tempalloc = cetech1.tempalloc;

// Global state
const G = struct {
    tab_vt: *editor_tabs.TabTypeI = undefined,
    asset_prop_aspect: *public.UiInspectorObjAspect = undefined,

    vec3f_properties_aspec: *public.UiInspectorPropertyValueAspect = undefined,

    color3f_properties_aspec: *public.UiInspectorPropertyValueAspect = undefined,
    color4f_properties_aspec: *public.UiInspectorPropertyValueAspect = undefined,

    position_properties_aspec: *public.UiInspectorPropertyValueAspect = undefined,
    rotation_properties_aspec: *public.UiInspectorPropertyValueAspect = undefined,
    scale_properties_aspec: *public.UiInspectorPropertyValueAspect = undefined,

    hide_proto_property_config_aspect: *public.UiPropertiesConfigAspect = undefined,
};
var _g: *G = undefined;

const api = public.InspectorAPI{
    .uiProperty = uiProperty,
    .uiPropBegin = uiPropBegin,
    .uiPropEnd = uiPropEnd,
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

fn formatedPropNameToBuff(buf: []u8, prop_name: [:0]const u8) ![]u8 {
    var split = std.mem.splitAny(u8, prop_name, "_");
    const first = split.first();

    var writer = std.Io.Writer.fixed(buf);

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

fn uiAssetInput(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    obj: cdb.ObjId,
    prop_idx: u32,
    read_only: bool,
) !void {
    const obj_r = cdb.readObj(obj) orelse return;
    const db = cdb.getDbFromObjid(obj);

    const defs = cdb.getTypePropDef(db, obj.type_idx).?;
    const prop_def = defs[prop_idx];

    var value_obj: cdb.ObjId = .{};
    switch (prop_def.type) {
        .REFERENCE => {
            if (cdb.readRef(obj_r, prop_idx)) |o| {
                value_obj = o;
            }
        },
        else => {
            return;
        },
    }

    {
        try uiPropInputBegin(obj, prop_idx, !read_only);
        defer uiPropInputEnd(!read_only);
        try uiAssetInputRaw(
            allocator,
            db,
            tab,
            obj,
            value_obj,
            read_only,
            false,
            prop_idx,
        );
    }

    {
        try uiPropButtonsBegin(obj, prop_idx, !read_only);
        defer uiPropButtonEnd();
    }
}

fn uiAssetInputProto(allocator: std.mem.Allocator, db: cdb.DbId, tab: *editor_tabs.TabO, obj: cdb.ObjId, value_obj: cdb.ObjId, read_only: bool) !void {
    coreui.pushObjUUID(obj);
    coreui.pushName("prototype");
    coreui.beginDisabled(.{ .disabled = read_only });

    defer {
        coreui.endDisabled();
        _ = coreui.tableNextColumn();
        coreui.popId();
        coreui.popId();
    }

    try uiAssetInputRaw(
        allocator,
        db,
        tab,
        obj,
        value_obj,
        read_only,
        true,
        0,
    );
}

fn uiAssetInputRaw(
    allocator: std.mem.Allocator,
    db: cdb.DbId,
    tab: *editor_tabs.TabO,
    obj: cdb.ObjId,
    value_obj: cdb.ObjId,
    read_only: bool,
    is_proto: bool,
    prop_idx: u32,
) !void {
    var buff: [128:0]u8 = undefined;
    var buff_asset: [128:0]u8 = undefined;
    var asset_name: [:0]u8 = undefined;
    const value_asset: ?cdb.ObjId = assetdb.getAssetForObj(value_obj);

    if (value_asset) |asset| {
        if (assetdb.isAssetFolder(asset)) {
            const path = try assetdb.getPathForFolder(&buff_asset, asset);
            asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{if (std.fs.path.dirname(path)) |p| p else "/"});
        } else {
            const path = try assetdb.getFilePathForAsset(&buff_asset, asset);
            asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{path});
        }
    } else {
        asset_name = try std.fmt.bufPrintZ(&buff, "", .{});
    }

    const prop_def = cdb.getTypePropDef(db, obj.type_idx).?;
    const allowed_type = if (is_proto) obj.type_idx else cdb.getTypeIdx(db, prop_def[prop_idx].type_hash) orelse cdb.TypeIdx{};

    if (coreui.beginPopup("ui_asset_context_menu", .{})) {
        defer coreui.endPopup();
        if (editor_tabs.selectObjFromMenu(allocator, assetdb.getObjForAsset(obj) orelse obj, allowed_type, !read_only)) |selected| {
            if (is_proto) {
                try cdb.setPrototype(obj, selected);
            } else {
                const w = cdb.writeObj(obj).?;
                try cdb.setRef(w, prop_idx, selected);
                try cdb.writeCommit(w);
            }
        }

        if (!assetdb.isAssetObjTypeOf(obj, assetdb.FolderCdb.typeIdx(db))) {
            if (coreui.menuItem(allocator, coreui.Icons.Clear ++ "  " ++ "Clear" ++ "###Clear", .{ .enabled = !read_only and value_asset != null }, null)) {
                if (is_proto) {
                    try cdb.setPrototype(obj, .{});
                } else {
                    const w = cdb.writeObj(obj).?;
                    try cdb.clearRef(w, prop_idx);
                    try cdb.writeCommit(w);
                }
            }
        }

        if (coreui.beginMenu(allocator, coreui.Icons.ContextMenu ++ "  " ++ "Context", value_asset != null, null)) {
            defer coreui.endMenu();
            try editor.showObjContextMenu(allocator, tab, &.{editor.Contexts.open}, .{ .top_level_obj = value_asset.?, .obj = value_asset.? });
        }
    }
    const item_spacing = coreui.getStyle().cell_padding.x;
    const button_w = coreui.calcTextSize(coreui.Icons.Elispis, .{}).x + item_spacing + (coreui.getStyle().frame_border_size + coreui.getStyle().frame_padding.x) * 2.0;
    coreui.setNextItemWidth(-button_w);
    _ = coreui.inputText("", .{
        .buf = asset_name,
        .flags = .{
            .read_only = true,
            .auto_select_all = true,
        },
    });

    if (coreui.beginDragDropTarget()) {
        if (coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
            var drag_obj: cdb.ObjId = payload.toValue(cdb.ObjId);
            if (drag_obj.type_idx.eql(AssetTypeIdx)) {
                drag_obj = assetdb.AssetCdb.readSubObj(cdb.readObj(drag_obj).?, .Object).?;
            }

            if (is_proto) {
                if (!drag_obj.eql(obj) and drag_obj.type_idx.eql(obj.type_idx)) {
                    try cdb.setPrototype(obj, drag_obj);
                }
            } else {
                const allowed_type_hash = cdb.getTypeIdx(db, cdb.getTypePropDef(db, obj.type_idx).?[prop_idx].type_hash) orelse cdb.TypeIdx{};
                if (allowed_type_hash.isEmpty() or allowed_type_hash.eql(drag_obj.type_idx)) {
                    const w = cdb.writeObj(obj).?;
                    try cdb.setRef(w, prop_idx, drag_obj);
                    try cdb.writeCommit(w);
                }
            }
        }
        defer coreui.endDragDropTarget();
    }

    coreui.sameLine(.{ .spacing = item_spacing });
    if (coreui.button(coreui.Icons.Elispis ++ "###AssetInputMenu", .{})) {
        coreui.openPopup("ui_asset_context_menu", .{});
    }
}

fn beginPropTable(name: [:0]const u8) bool {
    // _ = name;
    // return true;
    return coreui.beginTable(name, .{
        .column = 3,
        .flags = .{
            .sizing = .stretch_prop,
            .no_saved_settings = true,
            // .borders = .outer,
            // .row_bg = tru
            //
            // e,
            //.resizable = true,
        },
    });
}

fn endPropTabel() void {
    coreui.endTable();
}

fn beginSection(label: [:0]const u8, framed: bool, leaf: bool, default_open: bool, flat: bool) bool {
    if (flat) return true;
    const open = coreui.treeNodeFlags(label, .{
        .framed = framed,
        .leaf = leaf,
        .default_open = default_open,
        .no_auto_open_on_log = !leaf,
        // .span_avail_width = true,
        // .no_tree_push_on_open = true,
    });
    return open;
}

fn beginObjSection(allocator: std.mem.Allocator, label: [:0]const u8, tab: *editor_tabs.TabO, selected_obj: coreui.SelectedObj, framed: bool, leaf: bool, default_open: bool, flat: bool) !bool {
    if (flat) return true;

    try objContextMenuBtn(allocator, tab, selected_obj);
    coreui.sameLine(.{});

    return beginSection(label, framed, leaf, default_open, flat);
}

fn endSection(open: bool, flat: bool) void {
    if (flat) return;

    if (open) {
        coreui.treePop();
    }
}

fn cdbPropertiesView(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: public.InspectorViewArgs) !void {
    coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = coreui.getFontSize() / 2.0 });
    defer coreui.popStyleVar(.{});

    // const open = beginObjSection(allocator, "dasdas", tab, .{ .top_level_obj = top_level_obj, .obj = obj }, true, true, true, args.flat);
    // defer endSection(open, args.flat);

    try cdbPropertiesObj(allocator, tab, top_level_obj, obj, depth, args);
}
const REMOVED_COLOR = .{ 0.7, 0.0, 0.0, 1.0 };

fn objContextMenuBtn(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, selected_obj: coreui.SelectedObj) !void {
    if (coreui.beginPopup("property_obj_menu", .{})) {
        defer coreui.endPopup();
        try editor.showObjContextMenu(allocator, tab, &.{editor.Contexts.open}, selected_obj);
    }

    if (coreui.button(coreui.Icons.Elispis ++ "###PropertyCtxMenu", .{})) {
        coreui.openPopup("property_obj_menu", .{});
    }
}

fn uiProperty(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    top_level_obj: cdb.ObjId,
    obj: cdb.ObjId,
    prop_idx: u32,
    prop_label: ?[:0]const u8,
    args: public.InspectorViewArgs,
) !void {
    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    const obj_r = cdb.readObj(obj) orelse return;

    const db = cdb.getDbFromObjid(obj);
    const prop_defs = cdb.getTypePropDef(db, obj.type_idx).?;
    const prop_def = prop_defs[prop_idx];

    const prop_name = prop_label orelse try formatedPropNameToBuff(&prop_name_buff, prop_def.name);
    const prop_state = cdb.getRelation(top_level_obj, obj, prop_idx, null);
    const prop_color = editor.getStateColor(prop_state);

    const enabled = if (args.parent_disabled) false else cdb.isChildOff(top_level_obj, obj);

    switch (prop_def.type) {
        .REFERENCE_SET, .SUBOBJECT_SET => {
            if (cdb.getPropertyAspect(public.UiInspectorPropertyValueAspect, db, obj.type_idx, prop_idx)) |aspect| {
                const lbl = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                if (uiPropBegin(allocator, lbl, prop_color, enabled, args)) {
                    defer uiPropEnd(enabled, args);
                    try aspect.ui(allocator, obj, prop_idx, args);
                    return;
                }
            }
        },

        // If subobject type implement UiInspectorPropertyValueAspect show it in table
        .SUBOBJECT => {
            //if (prop_def.type_hash.id == 0) continue;
            const subobj = cdb.readSubObj(obj_r, prop_idx);
            const type_idx = if (subobj) |s| s.type_idx else cdb.getTypeIdx(db, prop_def.type_hash) orelse return;

            if (cdb.getAspect(public.UiInspectorPropertyValueAspect, db, type_idx)) |aspect| {
                const lbl = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});

                if (uiPropBegin(allocator, lbl, prop_color, enabled, args)) {
                    defer uiPropEnd(enabled, args);
                    {
                        try uiPropInputBegin(obj, prop_idx, enabled);
                        defer uiPropInputEnd(enabled);

                        if (subobj == null) {
                            try objContextMenuBtn(
                                allocator,
                                tab,
                                .{ .top_level_obj = top_level_obj, .obj = obj, .prop_idx = prop_idx },
                            );
                        } else {
                            try aspect.ui(allocator, subobj.?, prop_idx, args);
                        }
                    }

                    {
                        try uiPropButtonsBegin(obj, prop_idx, enabled);
                        defer uiPropButtonEnd();
                    }
                }
            }
        },

        .REFERENCE => {
            var ref: ?cdb.ObjId = null;

            if (args.filter) |filter| {
                if (coreui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                    return;
                }
            }

            ref = cdb.readRef(obj_r, prop_idx);

            const label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});

            if (uiPropBegin(allocator, label, prop_color, enabled, args)) {
                defer uiPropEnd(enabled, args);
                try uiAssetInput(allocator, tab, obj, prop_idx, !enabled);
            }
        },
        else => {
            if (args.filter) |filter| {
                if (coreui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                    return;
                }
            }

            const label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
            if (uiPropBegin(allocator, label, prop_color, enabled, args)) {
                defer uiPropEnd(enabled, args);
                if (cdb.getPropertyAspect(public.UiInspectorPropertyValueAspect, db, obj.type_idx, prop_idx)) |aspect| {
                    try uiPropInputBegin(obj, prop_idx, enabled);
                    defer uiPropInputEnd(enabled);
                    try aspect.ui(allocator, obj, prop_idx, args);
                } else {
                    try uiPropInput(obj, prop_idx, enabled, args);
                }
            }
        },
    }
}

fn cdbPropertiesObj(
    allocator: std.mem.Allocator,
    tab: *editor_tabs.TabO,
    top_level_obj: cdb.ObjId,
    obj: cdb.ObjId,
    depth: u32,
    args: public.InspectorViewArgs,
) !void {
    var zone_ctx = profiler.Zone(@src());
    defer zone_ctx.End();

    const enabled = if (args.parent_disabled) false else cdb.isChildOff(top_level_obj, obj);

    const db = cdb.getDbFromObjid(obj);

    // Find properties asspect for obj type.
    const ui_aspect = cdb.getAspect(public.UiInspectorObjAspect, db, obj.type_idx);
    if (ui_aspect) |aspect| {
        try aspect.ui_properties(allocator, tab, top_level_obj, obj, depth, args);
        return;
    }

    coreui.pushObjUUID(obj);
    defer coreui.popId();

    const obj_r = cdb.readObj(obj) orelse return;

    // Find properties config asspect for obj type.
    const config_aspect = cdb.getAspect(public.UiPropertiesConfigAspect, db, obj.type_idx);

    const prototype_obj = cdb.getPrototype(obj_r);
    //const has_prototype = !prototype_obj.isEmpty();

    const prop_defs = cdb.getTypePropDef(db, obj.type_idx).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    var show_proto = true;

    // Exist config aspect?
    if (config_aspect) |aspect| {
        show_proto = !aspect.hide_prototype;
    }
    // Force hide
    if (args.hide_proto) {
        show_proto = false;
    }

    //
    // Scalars valus (they are in table one prop per table row)
    //
    if (beginPropTable("Inspector")) {
        defer endPropTabel();

        if (show_proto) {
            if (uiPropBegin(allocator, "Prototype", null, enabled, args)) {
                defer uiPropEnd(enabled, args);
                try uiAssetInputProto(allocator, db, tab, obj, prototype_obj, !enabled);
            }
        }
        // const visible = coreui.isRectVisible(.{ coreui.getContentRegionMax()[0], coreui.getFontSize() * coreui.getScaleFactor() });
        for (0..prop_defs.len) |idx| {
            const prop_idx: u32 = @truncate(idx);
            try uiProperty(allocator, tab, top_level_obj, obj, prop_idx, null, args);
        }
    }

    //
    // Compound values (Seperated by colapsing header)
    //
    for (prop_defs, 0..) |prop_def, idx| {
        switch (prop_def.type) {
            .SUBOBJECT, .REFERENCE_SET, .SUBOBJECT_SET => {},
            else => continue,
        }

        const prop_idx: u32 = @truncate(idx);

        coreui.pushPropName(obj, @truncate(idx));
        defer coreui.popId();

        //const visible = coreui.isRectVisible(.{ coreui.getContentRegionMax()[0], coreui.getFontSize() * coreui.getScaleFactor() });

        const prop_name = try formatedPropNameToBuff(&prop_name_buff, prop_def.name);
        const prop_state = cdb.getRelation(top_level_obj, obj, prop_idx, null);
        const prop_color = editor.getStateColor(prop_state);

        switch (prop_def.type) {
            .SUBOBJECT => {
                if (args.filter) |filter| {
                    if (coreui.uiFilterPass(allocator, std.mem.sliceTo(filter, 0), prop_def.name, false) == null) {
                        continue;
                    }
                }

                const subobj = cdb.readSubObj(obj_r, prop_idx);
                const type_idx = if (subobj) |s| s.type_idx else cdb.getTypeIdx(db, prop_def.type_hash);

                // SKip if subobject has embed aspect
                if (type_idx) |tidx| if (cdb.getAspect(public.UiInspectorPropertyValueAspect, db, tidx) != null) continue;

                const label = try std.fmt.bufPrintZ(&buff, "{s}  {s}", .{ prop_name, if (prop_def.type == .REFERENCE) "  " ++ coreui.Icons.Link else "" });
                {
                    coreui.pushStyleColor4f(.{ .idx = .text, .c = prop_color });
                    const open = try beginObjSection(
                        allocator,
                        label,
                        tab,
                        .{ .top_level_obj = top_level_obj, .obj = obj, .prop_idx = prop_idx },
                        true,
                        subobj == null,
                        depth < args.max_autopen_depth,
                        args.flat,
                    );
                    coreui.popStyleColor(.{});
                    defer endSection(open, args.flat);

                    if (open) {
                        if (subobj != null) {
                            var a = args;
                            a.parent_disabled = !enabled;

                            try cdbPropertiesObj(allocator, tab, top_level_obj, subobj.?, depth + 1, a);
                        }
                    }
                }
            },

            .SUBOBJECT_SET, .REFERENCE_SET => {
                if (cdb.getPropertyAspect(public.UiInspectorPropertyValueAspect, db, obj.type_idx, prop_idx) != null) {
                    continue;
                }

                const prop_label = try std.fmt.bufPrintZ(&buff, "{s}  {s} {s}", .{
                    prop_name,
                    coreui.Icons.List,
                    if (prop_def.type == .REFERENCE_SET) "  " ++ coreui.Icons.Link else "",
                });

                var set: ?[]cdb.ObjId = undefined;
                if (prop_def.type == .REFERENCE_SET) {
                    set = cdb.readRefSet(obj_r, prop_idx, allocator);
                } else {
                    set = try cdb.readSubObjSet(obj_r, prop_idx, allocator);
                }

                defer {
                    if (set) |s| {
                        allocator.free(s);
                    }
                }
                const is_empty = if (set) |s| s.len == 0 else true;
                coreui.pushStyleColor4f(.{ .idx = .text, .c = prop_color });

                const open = try beginObjSection(
                    allocator,
                    prop_label,
                    tab,
                    .{ .top_level_obj = top_level_obj, .obj = obj, .prop_idx = prop_idx },
                    true,
                    false,
                    !is_empty and depth < args.max_autopen_depth,
                    args.flat,
                );
                defer endSection(open, args.flat);
                coreui.popStyleColor(.{});

                if (open) {
                    if (set) |s| {
                        defer allocator.free(s);

                        const ui_sort_aspect = cdb.getPropertyAspect(editor.UiSetSortPropertyAspect, db, obj.type_idx, prop_idx);
                        if (ui_sort_aspect) |aspect| {
                            try aspect.sort(allocator, s);
                        }

                        for (s, 0..) |subobj, set_idx| {
                            coreui.pushIntId(@truncate(set_idx));
                            defer coreui.popId();

                            //const visible_item = coreui.isRectVisible(.{ coreui.getContentRegionMax()[0], coreui.getFontSize() * coreui.getScaleFactor() });

                            const label = try editor.formatObjLabel(
                                allocator,
                                subobj,
                                set_idx,
                                .{ .with_txt = true, .with_id = true, .with_icon = true, .with_status_icons = true },
                            );
                            defer allocator.free(label);

                            const set_state = cdb.getRelation(top_level_obj, obj, prop_idx, subobj);
                            const set_color = editor.getStateColor(set_state);

                            coreui.pushStyleColor4f(.{ .idx = .text, .c = set_color });

                            const open_inset = try beginObjSection(
                                allocator,
                                label,
                                tab,
                                .{ .top_level_obj = top_level_obj, .obj = obj, .prop_idx = prop_idx, .in_set_obj = subobj },
                                true,
                                false,
                                depth < args.max_autopen_depth,
                                args.flat,
                            );
                            coreui.popStyleColor(.{});

                            //coreui.sameLine(.{});
                            defer endSection(open_inset, args.flat);

                            if (open_inset) {
                                var a = args;
                                a.parent_disabled = !enabled;

                                try cdbPropertiesObj(allocator, tab, top_level_obj, subobj, depth + 1, a);
                            }
                        }
                    }
                }
            },

            else => {},
        }
    }
}

fn uiInputProtoBtns(obj: cdb.ObjId, prop_idx: u32, enabled: bool) !void {
    const proto_obj = cdb.getPrototype(cdb.readObj(obj).?);
    if (proto_obj.isEmpty()) return;

    const db = cdb.getDbFromObjid(obj);

    const types = cdb.getTypePropDef(db, obj.type_idx).?;
    const prop_def = types[prop_idx];
    const is_overided = cdb.isPropertyOverrided(cdb.readObj(obj).?, prop_idx);

    if (prop_def.type == .BLOB) return;

    if (coreui.beginPopup("property_protoypes_menu", .{})) {
        defer coreui.endPopup();

        if (coreui.menuItem(_allocator, coreui.Icons.ResetToPrototype ++ "  " ++ "Reset to prototype value" ++ "###ResetToPrototypeValue", .{ .enabled = enabled and is_overided }, null)) {
            const w = cdb.writeObj(obj).?;
            cdb.resetPropertyOveride(w, prop_idx);
            try cdb.writeCommit(w);
        }

        if (coreui.menuItem(_allocator, coreui.Icons.PropagateToProtoype ++ "  " ++ "Propagate to prototype" ++ "###PropagateToPrototype", .{ .enabled = enabled and is_overided }, null)) {
            // TODO: TO CDB!!!
            // Set value from parent. This is probably not need.
            {
                const w = cdb.writeObj(proto_obj).?;
                const r = cdb.readObj(obj).?;

                switch (prop_def.type) {
                    .BOOL => {
                        const value = cdb.readValue(bool, r, prop_idx);
                        cdb.setValue(bool, w, prop_idx, value);
                    },
                    .F32 => {
                        const value = cdb.readValue(f32, r, prop_idx);
                        cdb.setValue(f32, w, prop_idx, value);
                    },
                    .F64 => {
                        const value = cdb.readValue(f64, r, prop_idx);
                        cdb.setValue(f64, w, prop_idx, value);
                    },
                    .I32 => {
                        const value = cdb.readValue(i32, r, prop_idx);
                        cdb.setValue(i32, w, prop_idx, value);
                    },
                    .U32 => {
                        const value = cdb.readValue(u32, r, prop_idx);
                        cdb.setValue(u32, w, prop_idx, value);
                    },
                    .I64 => {
                        const value = cdb.readValue(i64, r, prop_idx);
                        cdb.setValue(i64, w, prop_idx, value);
                    },
                    .U64 => {
                        const value = cdb.readValue(u64, r, prop_idx);
                        cdb.setValue(u64, w, prop_idx, value);
                    },
                    .STR => {
                        if (cdb.readStr(r, prop_idx)) |str| {
                            try cdb.setStr(w, prop_idx, str);
                        }
                    },
                    .REFERENCE => {
                        if (cdb.readRef(r, prop_idx)) |ref| {
                            try cdb.setRef(w, prop_idx, ref);
                        }
                    },
                    .BLOB => {},
                    else => {},
                }
                cdb.resetPropertyOveride(w, prop_idx);
                try cdb.writeCommit(w);
            }

            // reset value overide
            {
                const w = cdb.writeObj(obj).?;
                cdb.resetPropertyOveride(w, prop_idx);
                try cdb.writeCommit(w);
            }
        }
    }

    if (coreui.button(coreui.Icons.PrototypeBtn ++ "###PrototypeButtons", .{})) {
        coreui.openPopup("property_protoypes_menu", .{});
    }

    coreui.sameLine(.{});
}

fn uiPropBegin(allocator: std.mem.Allocator, name: [:0]const u8, color: ?math.Color4f, enabled: bool, args: public.InspectorViewArgs) bool {
    if (args.filter) |filter| {
        if (coreui.uiFilterPass(allocator, filter, name, false) == null) return false;
    }

    _ = coreui.tableNextRow(.{});
    _ = coreui.tableNextColumn();
    defer _ = coreui.tableNextColumn();

    if (args.no_prop_label) return true;

    coreui.alignTextToFramePadding();
    if (enabled) {
        if (color) |colorr| {
            coreui.pushStyleColor4f(.{ .idx = .text, .c = colorr });
        }
        defer if (color != null) coreui.popStyleColor(.{});
        coreui.text(name);
    } else {
        coreui.beginDisabled(.{});
        defer coreui.endDisabled();
        coreui.text(name);
    }
    return true;
}

fn uiPropEnd(enabled: bool, args: public.InspectorViewArgs) void {
    _ = args;
    _ = enabled;
}

fn uiPropInputBegin(obj: cdb.ObjId, prop_idx: u32, enabled: bool) !void {
    coreui.pushObjUUID(obj);
    coreui.pushPropName(obj, prop_idx);

    coreui.beginDisabled(.{ .disabled = !enabled });
}

fn uiPropInputEnd(enabled: bool) void {
    _ = enabled;
    coreui.endDisabled();
    _ = coreui.tableNextColumn();
    coreui.popId();
    coreui.popId();
}

fn uiPropButtonsBegin(obj: cdb.ObjId, prop_idx: u32, enabled: bool) !void {
    coreui.pushObjUUID(obj);
    coreui.pushPropName(obj, prop_idx);
    coreui.beginDisabled(.{ .disabled = !enabled });
    try uiInputProtoBtns(obj, prop_idx, enabled);
}

fn uiPropButtonEnd() void {
    coreui.endDisabled();
    coreui.popId();
    coreui.popId();
}

fn uiPropInput(obj: cdb.ObjId, prop_idx: u32, enabled: bool, args: public.InspectorViewArgs) !void {
    {
        try uiPropInputBegin(obj, prop_idx, enabled);
        defer uiPropInputEnd(enabled);
        try uiPropInputRaw(obj, prop_idx, args);
    }

    {
        try uiPropButtonsBegin(obj, prop_idx, enabled);
        defer uiPropButtonEnd();
    }
}

fn uiPropInputRaw(obj: cdb.ObjId, prop_idx: u32, args: public.InspectorViewArgs) !void {
    _ = args;

    const visible = coreui.isRectVisible(.{ .x = coreui.getContentRegionAvail().x, .y = coreui.getFontSize() });
    if (!visible) {
        coreui.dummy(.{ .w = -1, .h = coreui.getFontSize() });
        return;
    }

    var buf: [128:0]u8 = undefined;
    @memset(&buf, 0);

    const db = cdb.getDbFromObjid(obj);
    const prop_defs = cdb.getTypePropDef(db, obj.type_idx).?;
    const prop_def = prop_defs[prop_idx];

    var buf_label: [128:0]u8 = undefined;
    @memset(&buf_label, 0);
    const label = try std.fmt.bufPrintZ(&buf_label, "###edit", .{});

    const reader = cdb.readObj(obj) orelse return;

    coreui.setNextItemWidth(-1.0);
    switch (prop_def.type) {
        .BOOL => {
            var value = cdb.readValue(bool, reader, prop_idx);
            if (coreui.checkbox(label, .{
                .v = &value,
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(bool, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .F32 => {
            var value = cdb.readValue(f32, reader, prop_idx);
            if (coreui.dragF32(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(f32, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .F64 => {
            var value = cdb.readValue(f64, reader, prop_idx);
            if (coreui.dragF64(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(f64, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .I32 => {
            var value = cdb.readValue(i32, reader, prop_idx);
            if (coreui.dragI32(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(i32, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .U32 => {
            var value = cdb.readValue(u32, reader, prop_idx);
            if (coreui.dragU32(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(u32, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .I64 => {
            var value = cdb.readValue(i64, reader, prop_idx);
            if (coreui.dragI64(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(i64, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .U64 => {
            var value = cdb.readValue(u64, reader, prop_idx);
            if (coreui.dragU64(label, .{
                .v = &value,
                .flags = .{
                    //.enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                cdb.setValue(u64, w, prop_idx, value);
                try cdb.writeCommit(w);
            }
        },
        .STR => {
            const name = cdb.readStr(reader, prop_idx);
            if (name) |str| {
                _ = try std.fmt.bufPrintZ(&buf, "{s}", .{str});
            }
            if (coreui.inputText(label, .{
                .buf = &buf,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                const w = cdb.writeObj(obj).?;
                var new_name_buf: [128:0]u8 = undefined;
                const new_name = try std.fmt.bufPrintZ(&new_name_buf, "{s}", .{std.mem.sliceTo(&buf, 0)});
                try cdb.setStr(w, prop_idx, new_name);
                try cdb.writeCommit(w);
            }
        },
        .BLOB => {
            coreui.text("---");
        },
        else => {
            coreui.text("- !!INVALID TYPE!! -");
            log.err("Invalid property type for uiInputForProperty {}", .{prop_def.type});
        },
    }
}

// Asset properties aspect
var asset_properties_aspec = public.UiInspectorObjAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: public.InspectorViewArgs,
    ) !void {
        const obj_r = cdb.readObj(obj) orelse return;

        var buf: [128:0]u8 = undefined;

        if (beginSection(coreui.Icons.Asset ++ " Asset##Asset", true, false, true, false)) {
            defer endSection(true, false);

            if (beginPropTable("Inspector")) {
                defer endPropTabel();

                // Asset UUID
                if (assetdb.getUuid(obj)) |asset_uuid| {
                    if (uiPropBegin(allocator, "UUID", null, true, args)) {
                        defer uiPropEnd(true, args);
                        // coreui.indent(.{});
                        // defer coreui.unindent(.{});

                        _ = try std.fmt.bufPrintZ(&buf, "{f}", .{asset_uuid});

                        coreui.setNextItemWidth(-1.0);
                        _ = coreui.inputText("##UUID", .{
                            .buf = &buf,
                            .flags = .{
                                .read_only = true,
                                .auto_select_all = true,
                            },
                        });
                    }
                }

                var is_project = false;
                if (assetdb.getObjForAsset(obj)) |o| {
                    is_project = o.type_idx.eql(AssetTypeIdx);
                }

                // Asset name
                if (!is_project and !assetdb.isRootFolder(obj) and uiPropBegin(allocator, "Name", null, true, args)) {
                    defer uiPropEnd(true, args);
                    try uiPropInput(obj, assetdb.AssetCdb.propIdx(.Name), true, args);
                }

                // Asset description
                if (!assetdb.isRootFolder(obj) and uiPropBegin(allocator, "Description", null, true, args)) {
                    defer uiPropEnd(true, args);
                    try uiPropInput(obj, assetdb.AssetCdb.propIdx(.Description), true, args);
                }

                // Folder
                if (!is_project and !assetdb.isRootFolder(obj) and uiPropBegin(allocator, "Folder", null, true, args)) {
                    defer uiPropEnd(true, args);
                    try uiAssetInput(allocator, tab, obj, assetdb.AssetCdb.propIdx(.Folder), true);
                }

                // Tags
                if (!is_project and !assetdb.isRootFolder(obj)) {
                    try uiProperty(allocator, tab, top_level_obj, obj, assetdb.AssetCdb.propIdx(.Tags), null, args);
                }
            }
        }

        // Asset object
        if (beginSection("Asset object", true, false, true, false)) {
            defer endSection(true, false);
            try cdbPropertiesObj(allocator, tab, top_level_obj, assetdb.AssetCdb.readSubObj(obj_r, .Object).?, depth + 1, args);
        }
    }
});

//

// Asset properties aspect
var color4f_properties_aspec = public.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: public.InspectorViewArgs,
    ) !void {
        _ = allocator;
        _ = prop_idx;
        _ = args;

        var color = cetech1.cdb_types.Color4fCdb.f.to(obj);

        coreui.setNextItemWidth(-1.0);
        if (coreui.colorEdit4("", .{ .col = &color })) {
            const w = cdb.writeObj(obj).?;
            cetech1.cdb_types.Color4fCdb.f.from(w, color);
            try cdb.writeCommit(w);
        }
    }
});

var color3f_properties_aspec = public.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: public.InspectorViewArgs,
    ) !void {
        _ = allocator;
        _ = prop_idx;
        _ = args;

        const color = cetech1.cdb_types.Color3fCdb.f.to(obj);
        var c: math.Color4f = .fromColor3f(color, 1.0);
        coreui.setNextItemWidth(-1.0);
        if (coreui.colorEdit4("", .{ .col = &c, .flags = .{ .no_alpha = true } })) {
            const w = cdb.writeObj(obj).?;
            cetech1.cdb_types.Color3fCdb.f.from(w, c.toColor3f());
            try cdb.writeCommit(w);
        }
    }
});

var vec3f_properties_aspec = public.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: public.InspectorViewArgs,
    ) !void {
        _ = allocator;
        _ = prop_idx;
        _ = args;

        var rotation = cetech1.cdb_types.Vec3fCdb.f.to(obj);

        coreui.setNextItemWidth(-1.0);
        if (coreui.dragVec3f("", .{ .v = &rotation })) {
            const w = cdb.writeObj(obj).?;
            cetech1.cdb_types.Vec3fCdb.f.from(w, rotation);
            try cdb.writeCommit(w);
        }
    }
});

var position_properties_aspec = public.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: public.InspectorViewArgs,
    ) !void {
        _ = allocator;
        _ = prop_idx;
        _ = args;

        var position = cetech1.cdb_types.Vec3fCdb.f.to(obj);

        coreui.setNextItemWidth(-1.0);
        if (coreui.dragVec3f("", .{ .v = &position })) {
            const w = cdb.writeObj(obj).?;
            cetech1.cdb_types.Vec3fCdb.f.from(w, position);
            try cdb.writeCommit(w);
        }
    }
});

var rotation_properties_aspec = public.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: public.InspectorViewArgs,
    ) !void {
        _ = allocator;
        _ = prop_idx;
        _ = args;

        var rotation = cetech1.cdb_types.Vec3fCdb.f.to(obj);

        coreui.setNextItemWidth(-1.0);
        if (coreui.dragVec3f("", .{ .v = &rotation })) {
            const w = cdb.writeObj(obj).?;
            cetech1.cdb_types.Vec3fCdb.f.from(w, rotation);
            try cdb.writeCommit(w);
        }
    }
});

var scale_properties_aspec = public.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: public.InspectorViewArgs,
    ) !void {
        _ = allocator;
        _ = prop_idx;
        _ = args;

        var rotation = cetech1.cdb_types.Vec3fCdb.f.to(obj);

        coreui.setNextItemWidth(-1.0);
        if (coreui.dragVec3f("", .{ .v = &rotation })) {
            const w = cdb.writeObj(obj).?;
            cetech1.cdb_types.Vec3fCdb.f.from(w, rotation);
            try cdb.writeCommit(w);
        }
    }
});

//

const PropertyTab = struct {
    tab_i: editor_tabs.TabI,

    selected_obj: coreui.SelectedObj,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};

// Fill editor tab interface
var inspector_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = INSPECTOR_TAB_NAME,
    .tab_hash = .fromStr(INSPECTOR_TAB_NAME),

    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
    .ignore_selection_from_tab = &.{.fromStr("ct_editor_asset_browser_tab")},
}, struct {
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Properties ++ "  " ++ "Inspector";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Properties ++ "  " ++ "Inspector";
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectedObj) !bool {
        _ = allocator;
        _ = selection;

        return true;
    }

    // Create new FooTab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        _ = tab_id;
        var tab_inst = try _allocator.create(PropertyTab);
        tab_inst.* = PropertyTab{
            .tab_i = .{
                .vt = _g.tab_vt,
                .inst = @ptrCast(tab_inst),
            },

            .selected_obj = coreui.SelectedObj.empty(),
        };

        return &tab_inst.tab_i;
    }

    // Destroy FooTab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *PropertyTab = @ptrCast(@alignCast(tab_inst.inst));
        _allocator.destroy(tab_o);
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *PropertyTab = @ptrCast(@alignCast(inst));

        if (coreui.beginMenu(_allocator, coreui.Icons.ContextMenu ++ "###ObjContextMenu", !tab_o.selected_obj.isEmpty(), null)) {
            defer coreui.endMenu();

            const allocator = try tempalloc.create();
            defer tempalloc.destroy(allocator);

            const first_selected_obj = tab_o.selected_obj;
            try editor.showObjContextMenu(
                allocator,
                tab_o,
                &.{
                    editor.Contexts.create,
                    editor.Contexts.open,
                    editor.Contexts.debug,
                },
                first_selected_obj,
            );
        }
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;
        var tab_o: *PropertyTab = @ptrCast(@alignCast(inst));

        if (tab_o.selected_obj.isEmpty()) {
            return;
        }

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        tab_o.filter = coreui.uiFilter(&tab_o.filter_buff, tab_o.filter);

        defer coreui.endChild();
        if (coreui.beginChild("Inspector", .{ .child_flags = .{ .border = true } })) {
            const obj: cdb.ObjId = tab_o.selected_obj.obj;
            try cdbPropertiesView(allocator, tab_o, tab_o.selected_obj.top_level_obj, obj, 0, .{ .filter = tab_o.filter });
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, obj: []const coreui.SelectedObj, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash;
        var tab_o: *PropertyTab = @ptrCast(@alignCast(inst));
        tab_o.selected_obj = obj[0];
    }

    // pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
    //     const tab_o: *PropertyTab = @alignCast(@ptrCast(inst));
    //     tab_o.filter = null;
    //     tab_o.selected_obj = coreui.SelectedObj.empty();
    // }
});

var folder_properties_config_aspect = public.UiPropertiesConfigAspect{
    .hide_prototype = true,
};

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;
    }
});

// Cdb
var AssetTypeIdx: cdb.TypeIdx = undefined;
var ProjectTypeIdx: cdb.TypeIdx = undefined;

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        AssetTypeIdx = assetdb.AssetCdb.typeIdx(db);
        ProjectTypeIdx = assetdb.ProjectCdb.typeIdx(db);

        try assetdb.FolderCdb.addAspect(
            public.UiPropertiesConfigAspect,

            db,
            _g.hide_proto_property_config_aspect,
        );

        try assetdb.ProjectCdb.addAspect(
            public.UiPropertiesConfigAspect,

            db,
            _g.hide_proto_property_config_aspect,
        );

        try assetdb.AssetCdb.addAspect(
            public.UiInspectorObjAspect,

            db,
            _g.asset_prop_aspect,
        );

        try cetech1.cdb_types.Color4fCdb.addAspect(
            public.UiInspectorPropertyValueAspect,

            db,
            _g.color4f_properties_aspec,
        );

        try cetech1.cdb_types.Color3fCdb.addAspect(
            public.UiInspectorPropertyValueAspect,

            db,
            _g.color3f_properties_aspec,
        );

        try cetech1.cdb_types.Vec3fCdb.addAspect(
            public.UiInspectorPropertyValueAspect,

            db,
            _g.vec3f_properties_aspec,
        );

        try cetech1.cdb_types.PositionCdb.addAspect(
            public.UiInspectorPropertyValueAspect,

            db,
            _g.position_properties_aspec,
        );
        try cetech1.cdb_types.RotationCdb.addAspect(
            public.UiInspectorPropertyValueAspect,

            db,
            _g.rotation_properties_aspec,
        );
        try cetech1.cdb_types.ScaleCdb.addAspect(
            public.UiInspectorPropertyValueAspect,

            db,
            _g.scale_properties_aspec,
        );
    }
});

// Tests
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = coreui.registerTest(
            "Inspector",
            "should_edit_basic_properties",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(1);

                    const db = kernel.getDb();
                    _ = db;
                    const obj = assetdb.getObjId(uuid.fromStr("018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f").?).?;

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset1.ct_foo_asset", .{}, null);
                    ctx.itemAction(.Click, "**/###asset2.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");

                    // Bool
                    {
                        ctx.itemAction(.Check, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/bool/###edit", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(bool, obj_r, .Bool);
                        std.testing.expect(value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U64
                    {
                        ctx.itemInputIntValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/u64/###edit", 666);
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(u64, obj_r, .U64);
                        std.testing.expectEqual(666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I64
                    {
                        ctx.itemInputIntValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/i64/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value: i64 = assetdb.FooAsset.readValue(i64, obj_r, .I64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U32
                    {
                        ctx.itemInputIntValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/u32/###edit", 666);
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(u32, obj_r, .U32);
                        std.testing.expectEqual(666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I32
                    {
                        ctx.itemInputIntValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/i32/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(i32, obj_r, .I32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F32
                    {
                        ctx.itemInputIntValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/f32/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(f32, obj_r, .F32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F64
                    {
                        ctx.itemInputIntValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/f64/###edit", -666);
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(f64, obj_r, .F64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // String
                    {
                        ctx.itemInputStrValue("**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/str/###edit", "foo");
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const str = assetdb.FooAsset.readStr(obj_r, .Str);
                        std.testing.expect(str != null) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                        std.testing.expectEqualStrings(str.?, "foo") catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // Ref
                    {
                        ctx.itemAction(.Click, "**/018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f/reference/###AssetInputMenu", .{}, null);
                        ctx.yield(1);
                        ctx.menuAction(.Click, "//$FOCUSED/###SelectFrom/###1");

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const ref = assetdb.FooAsset.readRef(obj_r, .Reference);
                        std.testing.expect(ref != null) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return;
                        };
                        std.testing.expect(ref.?.eql(assetdb.getObjId(uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?)) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return;
                        };
                    }
                }
            },
        );

        _ = coreui.registerTest(
            "Inspector",
            "should_reset_value_from_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset1_1.ct_foo_asset", .{}, null);
                    ctx.itemAction(.Click, "**/###asset2.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");

                    const db = kernel.getDb();
                    _ = db;

                    // Bool
                    {
                        ctx.itemAction(.Check, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###edit", .{}, null);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(bool, obj_r, .Bool);
                        std.testing.expect(!value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U64
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###edit", 666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(u64, obj_r, .U64);
                        std.testing.expectEqual(0, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I64
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(i64, obj_r, .I64);
                        std.testing.expectEqual(0, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U32
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###edit", 666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(u32, obj_r, .U32);
                        std.testing.expectEqual(0, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I32
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(i32, obj_r, .I32);
                        std.testing.expectEqual(0, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F32
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(f32, obj_r, .F32);
                        std.testing.expectEqual(0, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F64
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(f64, obj_r, .F64);
                        std.testing.expectEqual(0, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // String
                    {
                        ctx.itemInputStrValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###edit", "foo");

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const str = assetdb.FooAsset.readStr(obj_r, .Str);
                        std.testing.expect(str == null) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // Ref
                    {
                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###AssetInputMenu", .{}, null);
                        ctx.yield(1);
                        ctx.menuAction(.Click, "//$FOCUSED/###SelectFrom/###1");

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###ResetToPrototypeValue", .{}, null);

                        const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const ref = assetdb.FooAsset.readRef(obj_r, .Reference);
                        std.testing.expect(ref == null) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }
                }
            },
        );

        _ = coreui.registerTest(
            "Inspector",
            "should_propagate_value_to_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset1_1.ct_foo_asset", .{}, null);
                    ctx.itemAction(.Click, "**/###asset2.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");

                    const db = kernel.getDb();
                    _ = db;
                    const obj = assetdb.getObjId(uuid.fromStr("018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f").?).?;

                    // Bool
                    {
                        ctx.itemAction(.Check, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###edit", .{}, null);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/bool/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(bool, obj_r, .Bool);
                        std.testing.expect(value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U64
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###edit", 666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(u64, obj_r, .U64);
                        std.testing.expectEqual(666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I64
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(i64, obj_r, .I64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // U32
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###edit", 666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/u32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(u32, obj_r, .U32);
                        std.testing.expectEqual(666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // I32
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/i32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(i32, obj_r, .I32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F32
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f32/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(f32, obj_r, .F32);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // F64
                    {
                        ctx.itemInputIntValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###edit", -666);

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/f64/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const value = assetdb.FooAsset.readValue(f64, obj_r, .F64);
                        std.testing.expectEqual(-666, value) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // String
                    {
                        ctx.itemInputStrValue("**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###edit", "foo");

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/str/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const str = assetdb.FooAsset.readStr(obj_r, .Str);
                        std.testing.expect(str != null) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                        std.testing.expectEqualStrings(str.?, "foo") catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }

                    // Ref
                    {
                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###AssetInputMenu", .{}, null);
                        ctx.yield(1);
                        ctx.menuAction(.Click, "//$FOCUSED/###SelectFrom/###1");

                        ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/reference/###PrototypeButtons", .{}, null);
                        ctx.itemAction(.Click, "**/###PropagateToPrototype", .{}, null);

                        const obj_r = assetdb.FooAsset.read(obj).?;
                        const ref = assetdb.FooAsset.readRef(obj_r, .Reference);
                        std.testing.expect(ref != null) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                        std.testing.expect(ref.?.eql(assetdb.getObjId(uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?)) catch |err| {
                            coreui.checkTestError(@src(), err);
                            return err;
                        };
                    }
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_open_asset_in_inspector",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###foo.ct_foo_asset", .{}, null);

                    ctx.menuAction(.Click, "###ObjContextMenu/###OpenIn_ct_editor_inspector_tab");

                    ctx.yield(1);

                    ctx.setRef("###ct_editor_inspector_tab_2");
                    ctx.windowFocus("");
                    //ctx.itemAction (  .Check, "**/018b5846-c2d5-712f-bb12-9d9d15321ecb/bool/###edit", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "Inspector",
            "should_set_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset2.ct_foo_asset", .{}, null);
                    ctx.itemAction(.Click, "**/###asset1.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");

                    ctx.itemAction(.Click, "**/018e4c98-35a7-7cdb-8538-6c3030bc4fe9/prototype/###AssetInputMenu", .{}, null);
                    ctx.yield(1);
                    ctx.menuAction(.Click, "//$FOCUSED/###SelectFrom/###1");

                    const obj = assetdb.getObjId(uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?;
                    const proto_obj = assetdb.getObjId(uuid.fromStr("018e4b5a-5fe3-7e1a-bf5b-10df8c083e9f").?).?;

                    std.testing.expect(proto_obj.eql(cdb.getPrototype(cdb.readObj(obj).?))) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "Inspector",
            "should_clear_prototype",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset1_1.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");
                    ctx.itemAction(.Click, "**/018e4b5d-01cb-7fc9-8730-7939c945c996/prototype/###AssetInputMenu", .{}, null);
                    ctx.yield(1);
                    ctx.menuAction(.Click, "//$FOCUSED/###Clear");

                    const obj = assetdb.getObjId(uuid.fromStr("018e4b5d-01cb-7fc9-8730-7939c945c996").?).?;
                    std.testing.expect(cdb.getPrototype(cdb.readObj(obj).?).isEmpty()) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );

        _ = coreui.registerTest(
            "Inspector",
            "should_add_remove_tag",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");

                    ctx.itemAction(.DoubleClick, "**/###foo.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");

                    ctx.itemAction(.Click, "**/###AddTags", .{}, null);
                    ctx.itemAction(.Click, "**/018e0348-b358-779f-b40c-7d34d3fca2a7/###Tag", .{}, null);

                    ctx.itemAction(.Click, "**/018e0348-b358-779f-b40c-7d34d3fca2a7/###Tag", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "Inspector",
            "should_add_ref_to_set",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_property");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###asset2.ct_foo_asset", .{}, null);
                    ctx.itemAction(.Click, "**/###asset1.ct_foo_asset", .{}, null);

                    ctx.setRef("###ct_editor_inspector_tab_1");
                    ctx.windowFocus("");

                    ctx.itemAction(.Click, "**/018e4c98-35a7-7cdb-8538-6c3030bc4fe9/reference_set/###PropertyCtxMenu", .{}, null);
                    ctx.yield(1);
                    ctx.menuAction(.Click, "//$FOCUSED/###AddToSet/###SelectFrom/###1");

                    const obj = assetdb.getObjId(uuid.fromStr("018e4c98-35a7-7cdb-8538-6c3030bc4fe9").?).?;

                    const set = try assetdb.FooAsset.readSubObjSet(cdb.readObj(obj).?, .ReferenceSet, _allocator);
                    std.testing.expect(set != null) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };

                    defer _allocator.free(set.?);
                    std.testing.expect(set.?.len == 1) catch |err| {
                        coreui.checkTestError(@src(), err);
                        return err;
                    };
                }
            },
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;
    public.api = &api;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, INSPECTOR_TAB_NAME, inspector_tab);

    // Aspects
    _g.asset_prop_aspect = try apidb.setGlobalVarValue(
        public.UiInspectorObjAspect,
        module_name,
        "ct_asset_properties_aspect",
        asset_properties_aspec,
    );
    _g.hide_proto_property_config_aspect = try apidb.setGlobalVarValue(
        public.UiPropertiesConfigAspect,
        module_name,
        "ct_folder_property_config_aspect",
        folder_properties_config_aspect,
    );

    _g.color3f_properties_aspec = try apidb.setGlobalVarValue(
        public.UiInspectorPropertyValueAspect,
        module_name,
        "ct_color_3f_properties_aspect",
        color3f_properties_aspec,
    );
    _g.color4f_properties_aspec = try apidb.setGlobalVarValue(
        public.UiInspectorPropertyValueAspect,
        module_name,
        "ct_color_4f_properties_aspect",
        color4f_properties_aspec,
    );
    _g.position_properties_aspec = try apidb.setGlobalVarValue(
        public.UiInspectorPropertyValueAspect,
        module_name,
        "ct_position_properties_aspect",
        position_properties_aspec,
    );
    _g.rotation_properties_aspec = try apidb.setGlobalVarValue(
        public.UiInspectorPropertyValueAspect,
        module_name,
        "ct_rotation_properties_aspect",
        rotation_properties_aspec,
    );
    _g.scale_properties_aspec = try apidb.setGlobalVarValue(
        public.UiInspectorPropertyValueAspect,
        module_name,
        "ct_scale_properties_aspect",
        scale_properties_aspec,
    );

    _g.vec3f_properties_aspec = try apidb.setGlobalVarValue(
        public.UiInspectorPropertyValueAspect,
        module_name,
        "ct_vec3f_properties_aspect",
        vec3f_properties_aspec,
    );

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);
    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &inspector_tab, load);

    try apidb.setOrRemoveZigApi(module_name, public.InspectorAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_inspector(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}

// Assert C api == C api in zig.
comptime {}
