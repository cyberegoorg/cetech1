const std = @import("std");

const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const cetech1 = @import("root.zig");

const host = @import("host.zig");

const coreui = @import("coreui.zig");
const math = cetech1.math;

const apidb = cetech1.apidb;
const log = std.log.scoped(.coreui_node_editor);

pub const EditorContext = opaque {};

pub const PinKind = enum(u32) {
    Input = 0,
    Output,
};

pub const NodeId = u64;
pub const LinkId = u64;
pub const PinId = u64;

const Style = extern struct {
    node_padding: [4]f32 = .{ 8, 8, 8, 8 },
    node_rounding: f32 = 12,
    node_border_width: f32 = 1.5,
    hovered_node_border_width: f32 = 3.5,
    hover_node_border_offset: f32 = 0,
    selected_node_border_width: f32 = 3.5,
    selected_node_border_offset: f32 = 0,
    pin_rounding: f32 = 4,
    pin_border_width: f32 = 0,
    link_strength: f32 = 100,
    source_direction: math.Vec2f = .{ .x = 1 },
    target_direction: math.Vec2f = .{ .x = -1 },
    scroll_duration: f32 = 0.35,
    flow_marker_distance: f32 = 30,
    flow_speed: f32 = 150.0,
    flow_duration: f32 = 2.0,
    pivot_alignment: math.Vec2f = .{ .x = 0.5, .y = 0.5 },
    pivot_size: math.Vec2f = .{},
    pivot_scale: math.Vec2f = .{ .x = 1, .y = 1 },
    pin_corners: f32 = 240,
    pin_radius: f32 = 0,
    pin_arrow_size: f32 = 0,
    pin_arrow_width: f32 = 0,
    group_rounding: f32 = 6,
    group_border_width: f32 = 1,
    highlight_connected_links: f32 = 0,
    snap_link_to_pin_dir: f32 = 0,

    colors: [@typeInfo(StyleColor).@"enum".fields.len]math.Color4f,

    pub fn getColor(style: Style, idx: StyleColor) math.Color4f {
        return style.colors[@intCast(@intFromEnum(idx))];
    }
    pub fn setColor(style: *Style, idx: StyleColor, color: math.Color4f) void {
        style.colors[@intCast(@intFromEnum(idx))] = color;
    }
};

const StyleColor = enum(c_int) {
    bg,
    grid,
    node_bg,
    node_border,
    hov_node_border,
    sel_node_border,
    node_sel_rect,
    node_sel_rect_border,
    hov_link_border,
    sel_link_border,
    highlight_link_border,
    link_sel_rect,
    link_sel_rect_border,
    pin_rect,
    pin_rect_border,
    flow,
    flow_marker,
    group_bg,
    group_border,
    count,
};

const StyleVar = enum(c_int) {
    node_padding,
    node_rounding,
    node_border_width,
    hovered_node_border_width,
    selected_node_border_width,
    pin_rounding,
    pin_border_width,
    link_strength,
    source_direction,
    target_direction,
    scroll_duration,
    flow_marker_distance,
    flow_speed,
    flow_duration,
    pivot_alignment,
    pivot_size,
    pivot_scale,
    pin_corners,
    pin_radius,
    pin_arrow_size,
    pin_arrow_width,
    group_rounding,
    group_border_width,
    highlight_connected_links,
    snap_link_to_pin_dir,
    hovered_node_border_offset,
    selected_node_border_offset,
    count,
};

pub const CanvasSizeMode = enum(c_int) {
    FitVerticalView, // Previous view will be scaled to fit new view on Y axis
    FitHorizontalView, // Previous view will be scaled to fit new view on X axis
    CenterOnly, // Previous view will be centered on new view
};

pub const SaveReasonFlags = packed struct(u32) {
    navigation: bool,
    position: bool,
    size: bool,
    selection: bool,
    add_node: bool,
    remove_node: bool,
    user: bool,
    _pad: u25,
};

const SaveNodeSettings = fn (nodeId: NodeId, data: [*]const u8, size: usize, reason: SaveReasonFlags, userPointer: *anyopaque) callconv(.c) bool;
const LoadNodeSettings = fn (nodeId: NodeId, data: [*]u8, userPointer: *anyopaque) callconv(.c) usize;
const SaveSettings = fn (data: [*]const u8, size: usize, reason: SaveReasonFlags, userPointer: *anyopaque) callconv(.c) bool;
const LoadSettings = fn (data: [*]u8, userPointer: *anyopaque) callconv(.c) usize;
const ConfigSession = fn (userPointer: *anyopaque) callconv(.c) void;

pub const Config = extern struct {
    settings_file: ?*const u8 = null,
    begin_save_session: ?*const ConfigSession = null,
    end_save_session: ?*const ConfigSession = null,
    save_settings: ?*const SaveSettings = null,
    load_settings: ?*const LoadSettings = null,
    save_node_settings: ?*const SaveNodeSettings = null,
    load_node_settings: ?*const LoadNodeSettings = null,
    user_pointer: ?*anyopaque = null,
    canvas_size_mode: CanvasSizeMode = .FitVerticalView,
    drag_button_index: c_int = 0,
    select_button_index: c_int = 0,
    navigate_button_index: c_int = 1,
    context_menu_button_index: c_int = 1,
    enable_smooth_zoom: bool = false,
    smooth_zoom_power: f32 = 1.1,
};

pub fn createEditor(cfg: Config) *EditorContext {
    return api.createEditor(cfg);
}
pub fn destroyEditor(editor: *EditorContext) void {
    return api.destroyEditor(editor);
}
pub fn setCurrentEditor(editor: ?*EditorContext) void {
    return api.setCurrentEditor(editor);
}
pub fn begin(id: [:0]const u8, size: math.Vec2f) void {
    return api.begin(id, size);
}
pub fn end() void {
    return api.end();
}
pub fn suspend_() void {
    return api.ssuspend();
}
pub fn resume_() void {
    return api.rresume();
}
pub fn showBackgroundContextMenu() bool {
    return api.showBackgroundContextMenu();
}
pub fn showNodeContextMenu(id: *NodeId) bool {
    return api.showNodeContextMenu(id);
}
pub fn showLinkContextMenu(id: *LinkId) bool {
    return api.showLinkContextMenu(id);
}
pub fn showPinContextMenu(id: *PinId) bool {
    return api.showPinContextMenu(id);
}
pub fn beginNode(id: NodeId) void {
    return api.beginNode(id);
}
pub fn endNode() void {
    return api.endNode();
}
pub fn deleteNode(id: NodeId) bool {
    return api.deleteNode(id);
}
pub fn setNodePosition(id: NodeId, pos: math.Vec2f) void {
    return api.setNodePosition(id, pos);
}
pub fn getNodePosition(id: NodeId) math.Vec2f {
    return api.getNodePosition(id);
}
pub fn getNodeSize(id: NodeId) math.Vec2f {
    return api.getNodeSize(id);
}
pub fn beginPin(id: PinId, kind: PinKind) void {
    return api.beginPin(id, kind);
}
pub fn endPin() void {
    return api.endPin();
}
pub fn pinHadAnyLinks(pinId: PinId) bool {
    return api.pinHadAnyLinks(pinId);
}
pub fn link(id: LinkId, startPinId: PinId, endPinId: PinId, color: math.Color4f, thickness: f32) void {
    return api.link(id, startPinId, endPinId, color, thickness);
}
pub fn deleteLink(id: LinkId) bool {
    return api.deleteLink(id);
}
pub fn beginCreate() bool {
    return api.beginCreate();
}
pub fn endCreate() void {
    return api.endCreate();
}
pub fn queryNewLink(startId: *?PinId, endId: *?PinId) bool {
    return api.queryNewLink(startId, endId);
}
pub fn acceptNewItem(color: math.Color4f, thickness: f32) bool {
    return api.acceptNewItem(color, thickness);
}
pub fn rejectNewItem(color: math.Color4f, thickness: f32) void {
    return api.rejectNewItem(color, thickness);
}
pub fn beginDelete() bool {
    return api.beginDelete();
}
pub fn endDelete() void {
    return api.endDelete();
}
pub fn queryDeletedLink(linkId: *LinkId, startId: ?*PinId, endId: ?*PinId) bool {
    return api.queryDeletedLink(linkId, startId, endId);
}
pub fn queryDeletedNode(nodeId: *NodeId) bool {
    return api.queryDeletedNode(nodeId);
}
pub fn acceptDeletedItem(deleteDependencies: bool) bool {
    return api.acceptDeletedItem(deleteDependencies);
}
pub fn rejectDeletedItem() bool {
    return api.rejectDeletedItem();
}
pub fn navigateToContent(duration: f32) void {
    return api.navigateToContent(duration);
}
pub fn navigateToSelection(zoomIn: bool, duration: f32) void {
    return api.navigateToSelection(zoomIn, duration);
}
pub fn breakPinLinks(id: PinId) i32 {
    return api.breakPinLinks(id);
}
pub fn getStyleColorName(colorIndex: StyleColor) [*c]const u8 {
    return api.getStyleColorName(colorIndex);
}
pub fn getStyle() Style {
    return api.getStyle();
}
pub fn pushStyleColor(colorIndex: StyleColor, color: math.Color4f) void {
    return api.pushStyleColor(colorIndex, color);
}
pub fn popStyleColor(count: c_int) void {
    return api.popStyleColor(count);
}
pub fn pushStyleVar1f(varIndex: StyleVar, value: f32) void {
    return api.pushStyleVar1f(varIndex, value);
}
pub fn pushStyleVar2f(varIndex: StyleVar, value: math.Vec2f) void {
    return api.pushStyleVar2f(varIndex, value);
}
pub fn pushStyleVar4f(varIndex: StyleVar, value: [4]f32) void {
    return api.pushStyleVar4f(varIndex, value);
}
pub fn popStyleVar(count: c_int) void {
    return api.popStyleVar(count);
}
pub fn hasSelectionChanged() bool {
    return api.hasSelectionChanged();
}
pub fn getSelectedObjectCount() c_int {
    return api.getSelectedObjectCount();
}
pub fn clearSelection() void {
    return api.clearSelection();
}
pub fn getSelectedNodes(nodes: []NodeId) c_int {
    return api.getSelectedNodes(nodes);
}
pub fn getSelectedLinks(links: []LinkId) c_int {
    return api.getSelectedLinks(links);
}
pub fn selectNode(nodeId: NodeId, append: bool) void {
    return api.selectNode(nodeId, append);
}
pub fn selectLink(linkId: LinkId, append: bool) void {
    return api.selectLink(linkId, append);
}
pub fn group(size: math.Vec2f) void {
    return api.group(size);
}
pub fn getHintForegroundDrawList() coreui.DrawList {
    return api.getHintForegroundDrawList();
}
pub fn getHintBackgroundDrawList() coreui.DrawList {
    return api.getHintBackgroundDrawList();
}
pub fn getNodeBackgroundDrawList(node_id: NodeId) coreui.DrawList {
    return api.getNodeBackgroundDrawList(node_id);
}
pub fn pinRect(a: math.Vec2f, b: math.Vec2f) void {
    return api.pinRect(a, b);
}
pub fn pinPivotRect(a: math.Vec2f, b: math.Vec2f) void {
    return api.pinPivotRect(a, b);
}
pub fn pinPivotSize(size: math.Vec2f) void {
    return api.pinPivotSize(size);
}
pub fn pinPivotScale(scale: math.Vec2f) void {
    return api.pinPivotScale(scale);
}
pub fn pinPivotAlignment(alignment: math.Vec2f) void {
    return api.pinPivotAlignment(alignment);
}

pub const NodeEditorApi = struct {
    createEditor: *const fn (cfg: Config) *EditorContext,
    destroyEditor: *const fn (editor: *EditorContext) void,
    setCurrentEditor: *const fn (editor: ?*EditorContext) void,
    begin: *const fn (id: [:0]const u8, size: math.Vec2f) void,
    end: *const fn () void,
    ssuspend: *const fn () void,
    rresume: *const fn () void,
    showBackgroundContextMenu: *const fn () bool,
    showNodeContextMenu: *const fn (id: *NodeId) bool,
    showLinkContextMenu: *const fn (id: *LinkId) bool,
    showPinContextMenu: *const fn (id: *PinId) bool,
    beginNode: *const fn (id: NodeId) void,
    endNode: *const fn () void,
    deleteNode: *const fn (id: NodeId) bool,
    setNodePosition: *const fn (id: NodeId, pos: math.Vec2f) void,
    getNodePosition: *const fn (id: NodeId) math.Vec2f,
    getNodeSize: *const fn (id: NodeId) math.Vec2f,
    beginPin: *const fn (id: PinId, kind: PinKind) void,
    endPin: *const fn () void,
    pinHadAnyLinks: *const fn (pinId: PinId) bool,
    link: *const fn (id: LinkId, startPinId: PinId, endPinId: PinId, color: math.Color4f, thickness: f32) void,
    deleteLink: *const fn (id: LinkId) bool,
    beginCreate: *const fn () bool,
    endCreate: *const fn () void,
    queryNewLink: *const fn (startId: *?PinId, endId: *?PinId) bool,
    acceptNewItem: *const fn (color: math.Color4f, thickness: f32) bool,
    rejectNewItem: *const fn (color: math.Color4f, thickness: f32) void,
    beginDelete: *const fn () bool,
    endDelete: *const fn () void,
    queryDeletedLink: *const fn (linkId: *LinkId, startId: ?*PinId, endId: ?*PinId) bool,
    queryDeletedNode: *const fn (nodeId: *NodeId) bool,
    acceptDeletedItem: *const fn (deleteDependencies: bool) bool,
    rejectDeletedItem: *const fn () bool,
    navigateToContent: *const fn (duration: f32) void,
    navigateToSelection: *const fn (zoomIn: bool, duration: f32) void,
    breakPinLinks: *const fn (id: PinId) i32,
    getStyleColorName: *const fn (colorIndex: StyleColor) [*c]const u8,
    getStyle: *const fn () Style,
    pushStyleColor: *const fn (colorIndex: StyleColor, color: math.Color4f) void,
    popStyleColor: *const fn (count: c_int) void,
    pushStyleVar1f: *const fn (varIndex: StyleVar, value: f32) void,
    pushStyleVar2f: *const fn (varIndex: StyleVar, value: math.Vec2f) void,
    pushStyleVar4f: *const fn (varIndex: StyleVar, value: [4]f32) void,
    popStyleVar: *const fn (count: c_int) void,
    hasSelectionChanged: *const fn () bool,
    getSelectedObjectCount: *const fn () c_int,
    clearSelection: *const fn () void,
    getSelectedNodes: *const fn (nodes: []NodeId) c_int,
    getSelectedLinks: *const fn (links: []LinkId) c_int,
    selectNode: *const fn (nodeId: NodeId, append: bool) void,
    selectLink: *const fn (linkId: LinkId, append: bool) void,
    group: *const fn (size: math.Vec2f) void,
    getHintForegroundDrawList: *const fn () coreui.DrawList,
    getHintBackgroundDrawList: *const fn () coreui.DrawList,
    getNodeBackgroundDrawList: *const fn (node_id: NodeId) coreui.DrawList,
    pinRect: *const fn (a: math.Vec2f, b: math.Vec2f) void,
    pinPivotRect: *const fn (a: math.Vec2f, b: math.Vec2f) void,
    pinPivotSize: *const fn (size: math.Vec2f) void,
    pinPivotScale: *const fn (scale: math.Vec2f) void,
    pinPivotAlignment: *const fn (alignment: math.Vec2f) void,
};

pub var api: *const NodeEditorApi = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, NodeEditorApi).?;
}
