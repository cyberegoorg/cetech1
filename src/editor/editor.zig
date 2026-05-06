const std = @import("std");

pub const tabs = @import("tabs.zig");
pub const asset_preview = @import("asset_preview.zig");
pub const assetdb = @import("assetdb.zig");
pub const gizmo = @import("gizmo.zig");
pub const inspector = @import("inspector.zig");
pub const obj_buffer = @import("obj_buffer.zig");
pub const tree = @import("tree.zig");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const math = cetech1.math;
const ecs = cetech1.ecs;
const apidb = cetech1.apidb;

const editor_tabs = cetech1.editor.tabs;

const log = std.log.scoped(.editor);

pub const Contexts = struct {
    pub const edit = cetech1.strId64("ct_edit_context");
    pub const create = cetech1.strId64("ct_create_context");
    pub const delete = cetech1.strId64("ct_delete_context");
    pub const open = cetech1.strId64("ct_open_context");
    pub const debug = cetech1.strId64("ct_debug_context");
};

pub const UiSetMenusAspect = struct {
    pub const c_name = "ct_ui_set_menus_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    add_menu: *const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiSetMenusAspect {
        return UiSetMenusAspect{
            .add_menu = &T.addMenu,
        };
    }
};

pub const UiSetSortPropertyAspect = struct {
    pub const c_name = "ct_ui_set_sort_property_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    sort: *const fn (allocator: std.mem.Allocator, objs: []cdb.ObjId) anyerror!void = undefined,

    pub fn implement(comptime T: type) UiSetSortPropertyAspect {
        return UiSetSortPropertyAspect{
            .sort = &T.sort,
        };
    }
};

pub const UiVisualAspect = struct {
    pub const c_name = "ct_ui_visual_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_name: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    ui_icons: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    ui_status_icons: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    ui_color: ?*const fn (
        obj: cdb.ObjId,
    ) anyerror!math.Color4f = null,

    ui_tooltip: ?*const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror!void = null,

    pub fn implement(comptime T: type) UiVisualAspect {
        return UiVisualAspect{
            .ui_name = if (std.meta.hasFn(T, "uiName")) T.uiName else null,
            .ui_icons = if (std.meta.hasFn(T, "uiIcons")) T.uiIcons else null,
            .ui_status_icons = if (std.meta.hasFn(T, "uiStatusIcons")) T.uiStatusIcons else null,
            .ui_color = if (std.meta.hasFn(T, "uiColor")) T.uiColor else null,
            .ui_tooltip = if (std.meta.hasFn(T, "uiTooltip")) T.uiTooltip else null,
        };
    }
};

pub const UiDropObj = struct {
    pub const c_name = "ct_ui_drop_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_drop_obj: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        obj: cdb.ObjId,
        prop_idx: ?u32,
        drag_obj: cdb.ObjId,
    ) anyerror!void,

    pub fn implement(comptime T: type) UiDropObj {
        return UiDropObj{
            .ui_drop_obj = T.uiDropObj,
        };
    }
};

pub const ObjContextMenuI = struct {
    pub const c_name = "ct_editor_obj_context_menu_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    is_valid: ?*const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        obj: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) anyerror!bool,

    menu: ?*const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: cetech1.StrId64,
        obj: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) anyerror!void,

    pub fn implement(comptime T: type) ObjContextMenuI {
        return ObjContextMenuI{
            .is_valid = T.isValid,
            .menu = T.menu,
        };
    }
};

pub const GizmoOptions = struct {
    translate_x: bool = false,
    translate_y: bool = false,
    translate_z: bool = false,
    rotate_x: bool = false,
    rotate_y: bool = false,
    rotate_z: bool = false,
    rotate_screen: bool = false,
    scale_x: bool = false,
    scale_y: bool = false,
    scale_z: bool = false,
    bounds: bool = false,
    scale_xu: bool = false,
    scale_yu: bool = false,
    scale_zu: bool = false,

    mode: coreui.GizmoMode = .World,
    snap_enabled: bool = false,
    snap: math.Vec3f = .{ .x = 1, .y = 1, .z = 1 },

    pub const translate: GizmoOptions = .{ .translate_x = true, .translate_y = true, .translate_z = true };
    pub const rotate: GizmoOptions = .{ .rotate_x = true, .rotate_y = true, .rotate_z = true };
    pub const scale: GizmoOptions = .{ .scale_x = true, .scale_y = true, .scale_z = true };
    pub const scaleU: GizmoOptions = .{ .scale_xu = true, .scale_yu = true, .scale_zu = true };
    pub const universal: GizmoOptions = .{
        .translate_x = true,
        .translate_y = true,
        .translate_z = true,
        .rotate_x = true,
        .rotate_y = true,
        .rotate_z = true,
        .scale_xu = true,
        .scale_yu = true,
        .scale_zu = true,
    };

    pub fn empty(self: GizmoOptions) bool {
        return !(self.translate_x or
            self.translate_y or
            self.translate_z or
            self.rotate_x or
            self.rotate_y or
            self.rotate_z or
            self.rotate_screen or
            self.scale_x or
            self.scale_y or
            self.scale_z or
            self.bounds or
            self.scale_xu or
            self.scale_yu or
            self.scale_zu);
    }
};

pub const EditorComponentAspect = struct {
    const Self = @This();
    pub const c_name = "ct_editor_component_aspect_i";
    pub const name_hash = cetech1.strId32(@This().c_name);

    uiIcons: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    // gizmo
    gizmoPriority: f32 = 0,
    gizmoGetOperation: ?*const fn (
        world: *ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: cdb.ObjId,
    ) anyerror!GizmoOptions = null,
    gizmoGetMatrix: ?*const fn (
        world: *ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: cdb.ObjId,
        world_mtx: *math.Mat44f,
        local_mtx: *math.Mat44f,
    ) anyerror!void = null,
    gizmoSetMatrix: ?*const fn (
        world: *ecs.World,
        entity: ecs.EntityId,
        entity_obj: cdb.ObjId,
        component_obj: cdb.ObjId,
        mat: math.Mat44f,
    ) anyerror!void = null,

    pub fn implement(args: EditorComponentAspect, comptime Hooks: type) Self {
        return Self{
            .uiIcons = if (std.meta.hasFn(Hooks, "uiIcons")) Hooks.uiIcons else null,

            .gizmoPriority = args.gizmoPriority,
            .gizmoGetMatrix = if (std.meta.hasFn(Hooks, "gizmoGetMatrix")) Hooks.gizmoGetMatrix else null,
            .gizmoSetMatrix = if (std.meta.hasFn(Hooks, "gizmoSetMatrix")) Hooks.gizmoSetMatrix else null,
            .gizmoGetOperation = if (std.meta.hasFn(Hooks, "gizmoGetOperation")) Hooks.gizmoGetOperation else null,
        };
    }
};

pub const FormatObjLabelConfig = struct {
    with_txt: bool = false,
    with_icon: bool = false,
    with_id: bool = false,
    uuid_id: bool = false,
    with_status_icons: bool = false,
};

pub fn showObjContextMenu(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, contexts: []const cetech1.StrId64, obj: coreui.SelectedObj) anyerror!void {
    return api.showObjContextMenu(allocator, tab, contexts, obj);
}
pub fn formatObjLabel(allocator: std.mem.Allocator, obj: cdb.ObjId, in_set_idx: ?usize, cfg: FormatObjLabelConfig) anyerror![:0]u8 {
    return api.formatObjLabel(allocator, obj, in_set_idx, cfg);
}
pub fn getStateColor(state: cdb.ObjRelation) math.Color4f {
    return api.getStateColor(state);
}
pub fn getObjColor(obj: cdb.ObjId, in_set_obj: ?cdb.ObjId) ?math.Color4f {
    return api.getObjColor(obj, in_set_obj);
}
pub fn getAssetColor(obj: cdb.ObjId) math.Color4f {
    return api.getAssetColor(obj);
}
pub fn isColorsEnabled() bool {
    return api.isColorsEnabled();
}
pub fn uiAssetDragDropSource(allocator: std.mem.Allocator, obj: cdb.ObjId) anyerror!void {
    return api.uiAssetDragDropSource(allocator, obj);
}
pub fn uiAssetDragDropTarget(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, obj: cdb.ObjId, prop_idx: ?u32) anyerror!void {
    return api.uiAssetDragDropTarget(allocator, tab, obj, prop_idx);
}

pub const EditorAPI = struct {
    showObjContextMenu: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, contexts: []const cetech1.StrId64, obj: coreui.SelectedObj) anyerror!void,
    formatObjLabel: *const fn (allocator: std.mem.Allocator, obj: cdb.ObjId, in_set_idx: ?usize, cfg: FormatObjLabelConfig) anyerror![:0]u8,
    getStateColor: *const fn (state: cdb.ObjRelation) math.Color4f,
    getObjColor: *const fn (obj: cdb.ObjId, in_set_obj: ?cdb.ObjId) ?math.Color4f,
    getAssetColor: *const fn (obj: cdb.ObjId) math.Color4f,
    isColorsEnabled: *const fn () bool,
    uiAssetDragDropSource: *const fn (allocator: std.mem.Allocator, obj: cdb.ObjId) anyerror!void,
    uiAssetDragDropTarget: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, obj: cdb.ObjId, prop_idx: ?u32) anyerror!void,
};

pub var api: *const EditorAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, EditorAPI).?;
}
