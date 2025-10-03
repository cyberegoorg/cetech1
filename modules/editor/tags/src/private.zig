const std = @import("std");
const Allocator = std.mem.Allocator;

const public = @import("editor_tags.zig");

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;
const Tag = assetdb.Tag;

const editor = @import("editor");
const Icons = cetech1.coreui.Icons;

const editor_inspector = @import("editor_inspector");

const module_name = .editor_tags;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

const FOLDER_PROPERTY_CONFIG_ASPECT_NAME = "ct_project_setings_properties_config_aspect";
const TAGS_ASPECT_NAME = "ct_tags_property_aspect";
const TAG_VISUAL_ASPECT_NAME = "ct_tag_visual_aspect";

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

// Global state
const G = struct {
    tag_prop_aspect: *editor_inspector.UiEmbedPropertyAspect = undefined,
    tag_visual_aspect: *editor.UiVisualAspect = undefined,
    noproto_config_aspect: *editor_inspector.UiPropertiesConfigAspect = undefined,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};
var _g: *G = undefined;

var api = public.EditorTagsApi{
    .tagsInput = tagsInput,
};

fn tagButton(db: cdb.DbId, filter: ?[:0]const u8, tag: cdb.ObjId, wrap: bool) bool {
    var buff: [128:0]u8 = undefined;
    const tag_r = _cdb.readObj(tag) orelse return false;
    const tag_name = Tag.readStr(_cdb, tag_r, .Name) orelse "NO NAME =(";
    const tag_color = getTagColor(db, tag_r);

    const color_scale = 0.80;
    const tag_color_normal = .{ tag_color[0] * color_scale, tag_color[1] * color_scale, tag_color[2] * color_scale, 1.0 };

    _coreui.pushObjUUID(tag);
    defer _coreui.popId();

    const label = std.fmt.bufPrintZ(&buff, coreui.Icons.Tag ++ "  " ++ "{s}###Tag", .{tag_name}) catch return false;

    if (filter) |f| {
        if (_coreui.uiFilterPass(_allocator, f, label, false) == null) return false;
    }

    if (wrap) {
        const style = _coreui.getStyle();
        const pos_a = _coreui.getItemRectMax()[0];
        const text_size = _coreui.calcTextSize(label, .{})[0] + 2 * style.frame_padding[0];

        if (pos_a + text_size + style.item_spacing[0] < _coreui.getWindowPos()[0] + _coreui.getContentRegionAvail()[0]) {
            _coreui.sameLine(.{});
        }
    }

    _coreui.pushStyleColor4f(.{ .c = tag_color_normal, .idx = .button });
    _coreui.pushStyleColor4f(.{ .c = tag_color, .idx = .button_active });
    _coreui.pushStyleColor4f(.{ .c = tag_color, .idx = .button_hovered });
    defer _coreui.popStyleColor(.{ .count = 3 });

    _coreui.pushStyleVar1f(.{ .idx = .frame_rounding, .v = 10 });
    _coreui.pushStyleVar2f(.{ .idx = .frame_padding, .v = .{ 6, 3 } });
    defer _coreui.popStyleVar(.{ .count = 2 });

    const button = (_coreui.button(label, .{}));

    return button;
}

fn tagsInput(
    allocator: std.mem.Allocator,
    obj: cdb.ObjId,
    prop_idx: u32,
    in_table: bool,
    filter: ?[:0]const u8,
) !bool {
    _ = filter;
    const obj_r = _cdb.readObj(obj) orelse return false;
    const db = _cdb.getDbFromObjid(obj);

    if (in_table) {
        _coreui.tableNextColumn();
    }

    if (_coreui.button(coreui.Icons.Tag ++ "  " ++ coreui.Icons.Add ++ "###AddTags", .{})) {
        _coreui.openPopup("ui_tag_add_popup", .{});
    }

    var any_tag_set = false;
    if (_cdb.readRefSet(obj_r, prop_idx, allocator)) |tags| {
        for (tags) |tag| {
            any_tag_set = true;
            if (tagButton(db, null, tag, true)) {
                const obj_w = _cdb.writeObj(obj).?;
                try _cdb.removeFromRefSet(obj_w, prop_idx, tag);
                try _cdb.writeCommit(obj_w);
            }
        }
    }

    if (_coreui.beginPopup("ui_tag_add_popup", .{})) {
        defer _coreui.endPopup();

        _g.filter = _coreui.uiFilter(&_g.filter_buff, _g.filter);

        if (_cdb.getAllObjectByType(allocator, db, assetdb.Tag.typeIdx(_cdb, db))) |tags| {
            for (tags) |tag| {
                if (_cdb.isInSet(obj_r, prop_idx, tag)) continue;
                if (tagButton(db, _g.filter, tag, true)) {
                    const obj_w = _cdb.writeObj(obj).?;
                    try _cdb.addRefToSet(obj_w, prop_idx, &.{tag});
                    _coreui.closeCurrentPopup();
                    try _cdb.writeCommit(obj_w);
                }
            }
        }
    }

    return any_tag_set;
}

//
// Create tag asset
//

var create_tag_asset_i = editor.CreateAssetI.implement(
    assetdb.Tag.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try _assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                _cdb.getTypeIdx(db, assetdb.Tag.type_hash).?,
                "NewTag",
            );
            const new_obj = try assetdb.Tag.createObject(_cdb, db);
            {
                const w = _cdb.writeObj(new_obj).?;
                try assetdb.Tag.setStr(_cdb, w, .Name, name);
                try _cdb.writeCommit(w);
            }

            _ = _assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Tag ++ "  " ++ "Tag";
        }
    },
);

// Tag property  aspect
var tag_prop_aspect = editor_inspector.UiEmbedPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = try tagsInput(allocator, obj, prop_idx, true, args.filter);
    }
});

//

fn getTagColor(db: cdb.DbId, tag_r: *cdb.Obj) [4]f32 {
    _ = db; // autofix
    if (!_editor.isColorsEnabled()) return .{ 1.0, 1.0, 1.0, 1.0 };

    const tag_color_obj = Tag.readSubObj(_cdb, tag_r, .Color);
    var color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    if (tag_color_obj) |color_obj| {
        color = cetech1.cdb_types.Color4f.f.toSlice(_cdb, color_obj);
    }
    return color;
}

// Tag visual aspect
var tag_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = _cdb.readObj(obj).?;
        return std.fmt.bufPrintZ(buff, "{s}", .{
            Tag.readStr(_cdb, obj_r, .Name) orelse "No NAME =()",
        });
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix

        _ = obj;
        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Tag});
    }

    pub fn uiColor(
        obj: cdb.ObjId,
    ) ![4]f32 {
        if (Tag.readSubObj(_cdb, _cdb.readObj(obj).?, .Color)) |color_obj| {
            return cetech1.cdb_types.Color4f.f.toSlice(_cdb, color_obj);
        }
        return .{ 1.0, 1.0, 1.0, 1.0 };
    }
});

//

// Create cdb types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        try assetdb.Tag.addAspect(
            editor_inspector.UiPropertiesConfigAspect,
            _cdb,
            db,
            _g.noproto_config_aspect,
        );

        try assetdb.Tag.addAspect(
            editor.UiVisualAspect,
            _cdb,
            db,
            _g.tag_visual_aspect,
        );

        try assetdb.Asset.addPropertyAspect(
            editor_inspector.UiEmbedPropertyAspect,
            _cdb,
            db,
            .Tags,
            _g.tag_prop_aspect,
        );
    }
});

//
var folder_properties_config_aspect = editor_inspector.UiPropertiesConfigAspect{
    .hide_prototype = true,
};

var settings_visual_config_aspect = editor_inspector.UiVisualPropertyConfigAspect{
    .no_subtree = true,
};

// Tests
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {}
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

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.noproto_config_aspect = try apidb.setGlobalVarValue(editor_inspector.UiPropertiesConfigAspect, module_name, FOLDER_PROPERTY_CONFIG_ASPECT_NAME, folder_properties_config_aspect);
    _g.tag_prop_aspect = try apidb.setGlobalVarValue(editor_inspector.UiEmbedPropertyAspect, module_name, TAGS_ASPECT_NAME, tag_prop_aspect);
    _g.tag_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, TAG_VISUAL_ASPECT_NAME, tag_visual_aspect);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, editor.CreateAssetI, &create_tag_asset_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.EditorTagsApi, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_tags(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
