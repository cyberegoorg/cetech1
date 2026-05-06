const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const math = cetech1.math;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;

const log = std.log.scoped(.editor_inspector);

const editor = cetech1.editor;
const editor_tabs = cetech1.editor.tabs;

pub const UiPropertiesConfigAspect = struct {
    pub const c_name = "ct_properties_config_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);
    hide_prototype: bool = false,
};

pub const UiPropertyConfigAspect = struct {
    pub const c_name = "ct_ui_property_config_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    hide_prototype: bool = false,
};

pub const UiVisualPropertyConfigAspect = struct {
    pub const c_name = "ct_ui_visual_property_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    no_subtree: bool = false,
};

pub const InspectorViewArgs = struct {
    filter: ?[:0]const u8 = null,
    max_autopen_depth: u32 = 2,
    hide_proto: bool = false,
    flat: bool = false,
    no_prop_label: bool = false,
    parent_disabled: bool = false,
};

/// This bypass all inspector logic for object
pub const UiInspectorObjAspect = struct {
    pub const c_name = "ct_ui_inspector_obj_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_properties: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: InspectorViewArgs,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiInspectorObjAspect {
        return UiInspectorObjAspect{
            .ui_properties = T.ui,
        };
    }
};

pub const UiInspectorPropertyValueAspect = struct {
    pub const c_name = "ct_ui_inspetor_property_value_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui: *const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: InspectorViewArgs,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiInspectorPropertyValueAspect {
        return UiInspectorPropertyValueAspect{
            .ui = T.ui,
        };
    }
};

pub fn uiProperty(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, prop_idx: u32, prop_label: ?[:0]const u8, args: InspectorViewArgs) anyerror!void {
    return api.uiProperty(allocator, tab, top_level_obj, obj, prop_idx, prop_label, args);
}
pub fn uiPropBegin(allocator: std.mem.Allocator, name: [:0]const u8, color: ?math.Color4f, enabled: bool, args: InspectorViewArgs) bool {
    return api.uiPropBegin(allocator, name, color, enabled, args);
}
pub fn uiPropEnd(enabled: bool, args: InspectorViewArgs) void {
    return api.uiPropEnd(enabled, args);
}
pub fn uiPropInput(obj: cdb.ObjId, prop_idx: u32, enabled: bool, args: InspectorViewArgs) anyerror!void {
    return api.uiPropInput(obj, prop_idx, enabled, args);
}
pub fn uiPropInputRaw(obj: cdb.ObjId, prop_idx: u32, args: InspectorViewArgs) anyerror!void {
    return api.uiPropInputRaw(obj, prop_idx, args);
}
pub fn uiPropInputBegin(obj: cdb.ObjId, prop_idx: u32, enabled: bool) anyerror!void {
    return api.uiPropInputBegin(obj, prop_idx, enabled);
}
pub fn uiPropInputEnd(enabled: bool) void {
    return api.uiPropInputEnd(enabled);
}
pub fn uiAssetInput(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, obj: cdb.ObjId, prop_idx: u32, read_only: bool) anyerror!void {
    return api.uiAssetInput(allocator, tab, obj, prop_idx, read_only);
}
pub fn formatedPropNameToBuff(buf: []u8, prop_name: [:0]const u8) anyerror![]u8 {
    return api.formatedPropNameToBuff(buf, prop_name);
}
pub fn cdbPropertiesView(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: InspectorViewArgs) anyerror!void {
    return api.cdbPropertiesView(allocator, tab, top_level_obj, obj, depth, args);
}
pub fn cdbPropertiesObj(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: InspectorViewArgs) anyerror!void {
    return api.cdbPropertiesObj(allocator, tab, top_level_obj, obj, depth, args);
}
pub fn beginSection(label: [:0]const u8, framed: bool, leaf: bool, default_open: bool, flat: bool) bool {
    return api.beginSection(label, framed, leaf, default_open, flat);
}
pub fn endSection(open: bool, flat: bool) void {
    return api.endSection(open, flat);
}
pub fn beginPropTable(name: [:0]const u8) bool {
    return api.beginPropTable(name);
}
pub fn endPropTabel() void {
    return api.endPropTabel();
}

pub const InspectorAPI = struct {
    uiProperty: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, prop_idx: u32, prop_label: ?[:0]const u8, args: InspectorViewArgs) anyerror!void,
    uiPropBegin: *const fn (allocator: std.mem.Allocator, name: [:0]const u8, color: ?math.Color4f, enabled: bool, args: InspectorViewArgs) bool,
    uiPropEnd: *const fn (enabled: bool, args: InspectorViewArgs) void,
    uiPropInput: *const fn (obj: cdb.ObjId, prop_idx: u32, enabled: bool, args: InspectorViewArgs) anyerror!void,
    uiPropInputRaw: *const fn (obj: cdb.ObjId, prop_idx: u32, args: InspectorViewArgs) anyerror!void,
    uiPropInputBegin: *const fn (obj: cdb.ObjId, prop_idx: u32, enabled: bool) anyerror!void,
    uiPropInputEnd: *const fn (enabled: bool) void,
    uiAssetInput: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, obj: cdb.ObjId, prop_idx: u32, read_only: bool) anyerror!void,
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: InspectorViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, top_level_obj: cdb.ObjId, obj: cdb.ObjId, depth: u32, args: InspectorViewArgs) anyerror!void,
    beginSection: *const fn (label: [:0]const u8, framed: bool, leaf: bool, default_open: bool, flat: bool) bool,
    endSection: *const fn (open: bool, flat: bool) void,
    beginPropTable: *const fn (name: [:0]const u8) bool,
    endPropTabel: *const fn () void,
};

pub var api: *const InspectorAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, InspectorAPI).?;
}
