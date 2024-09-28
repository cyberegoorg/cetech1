const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const strid = cetech1.strid;
const coreui = cetech1.coreui;

const log = std.log.scoped(.editor_inspector);

const editor = @import("editor");

pub const UiPropertiesConfigAspect = struct {
    pub const c_name = "ct_properties_config_aspect";
    pub const name_hash = strid.strId32(@This().c_name);
    hide_prototype: bool = false,
};

pub const UiPropertyConfigAspect = struct {
    pub const c_name = "ct_ui_property_config_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    hide_prototype: bool = false,
};

pub const UiVisualPropertyConfigAspect = struct {
    pub const c_name = "ct_ui_visual_property_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    no_subtree: bool = false,
};

pub const cdbPropertiesViewArgs = struct {
    filter: ?[:0]const u8 = null,
    max_autopen_depth: u32 = 2,
    hide_proto: bool = false,
    flat: bool = false,
    no_prop_label: bool = false,
    parent_disabled: bool = false,
};

pub const UiEmbedPropertyAspect = struct {
    pub const c_name = "ct_ui_embed_property_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_properties: *const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiEmbedPropertyAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiEmbedPropertyAspect{
            .ui_properties = T.ui,
        };
    }
};

pub const UiEmbedPropertiesAspect = struct {
    pub const c_name = "ct_ui_embed_properties_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_properties: *const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiEmbedPropertiesAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiEmbedPropertiesAspect{
            .ui_properties = T.ui,
        };
    }
};

pub const hidePropertyAspect = UiPropertyAspect{};

pub const UiPropertyAspect = struct {
    pub const c_name = "ct_ui_property_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_property: *const fn (
        allocator: std.mem.Allocator,
        cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiPropertyAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiPropertyAspect{
            .ui_property = T.ui,
        };
    }
};

pub const UiPropertiesAspect = struct {
    pub const c_name = "ct_ui_properties_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_properties: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: cdbPropertiesViewArgs,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiPropertiesAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiPropertiesAspect{
            .ui_properties = T.ui,
        };
    }
};

pub const InspectorAPI = struct {
    uiPropLabel: *const fn (allocator: std.mem.Allocator, name: [:0]const u8, color: ?[4]f32, enabled: bool, args: cdbPropertiesViewArgs) bool,
    uiPropInput: *const fn (obj: cdb.ObjId, prop_idx: u32, enabled: bool, args: cdbPropertiesViewArgs) anyerror!void,
    uiPropInputRaw: *const fn (obj: cdb.ObjId, prop_idx: u32, args: cdbPropertiesViewArgs) anyerror!void,
    uiPropInputBegin: *const fn (obj: cdb.ObjId, prop_idx: u32, enabled: bool) anyerror!void,
    uiPropInputEnd: *const fn () void,
    uiAssetInput: *const fn (allocator: std.mem.Allocator, tab: *editor.TabO, obj: cdb.ObjId, prop_idx: u32, read_only: bool, in_table: bool) anyerror!void,

    // Property utils
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,

    // Property view
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, tab: *editor.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: cdbPropertiesViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, tab: *editor.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: cdbPropertiesViewArgs) anyerror!void,

    beginSection: *const fn (label: [:0]const u8, leaf: bool, default_open: bool, flat: bool) bool,
    endSection: *const fn (open: bool, flat: bool) void,

    beginPropTable: *const fn (name: [:0]const u8) bool,
    endPropTabel: *const fn () void,
};
