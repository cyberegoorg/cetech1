const std = @import("std");

const log = std.log.scoped(.zine);

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
    source_direction: [2]f32 = .{ 1, 0 },
    target_direction: [2]f32 = .{ -1, 0 },
    scroll_duration: f32 = 0.35,
    flow_marker_distance: f32 = 30,
    flow_speed: f32 = 150.0,
    flow_duration: f32 = 2.0,
    pivot_alignment: [2]f32 = .{ 0.5, 0.5 },
    pivot_size: [2]f32 = .{ 0, 0 },
    pivot_scale: [2]f32 = .{ 1, 1 },
    pin_corners: f32 = 240,
    pin_radius: f32 = 0,
    pin_arrow_size: f32 = 0,
    pin_arrow_width: f32 = 0,
    group_rounding: f32 = 6,
    group_border_width: f32 = 1,
    highlight_connected_links: f32 = 0,
    snap_link_to_pin_dir: f32 = 0,

    colors: [@typeInfo(StyleColor).Enum.fields.len][4]f32,

    pub fn getColor(style: Style, idx: StyleColor) [4]f32 {
        return style.colors[@intCast(@intFromEnum(idx))];
    }
    pub fn setColor(style: *Style, idx: StyleColor, color: [4]f32) void {
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

pub const EditorContext = opaque {
    pub fn create(config: Config) *EditorContext {
        return zine_CreateEditor(&config);
    }
    extern fn zine_CreateEditor(config: *const Config) *EditorContext;

    pub fn destroy(self: *EditorContext) void {
        return zine_DestroyEditor(self);
    }
    extern fn zine_DestroyEditor(editor: *EditorContext) void;
};

const CanvasSizeMode = enum(c_int) {
    FitVerticalView, // Previous view will be scaled to fit new view on Y axis
    FitHorizontalView, // Previous view will be scaled to fit new view on X axis
    CenterOnly, // Previous view will be centered on new view
};

const SaveNodeSettings = fn (nodeId: NodeId, data: [*]const u8, size: usize, reason: SaveReasonFlags, userPointer: *anyopaque) callconv(.C) bool;
const LoadNodeSettings = fn (nodeId: NodeId, data: [*]u8, userPointer: *anyopaque) callconv(.C) usize;
const SaveSettings = fn (data: [*]const u8, size: usize, reason: SaveReasonFlags, userPointer: *anyopaque) callconv(.C) bool;
const LoadSettings = fn (data: [*]u8, userPointer: *anyopaque) callconv(.C) usize;
const ConfigSession = fn (userPointer: *anyopaque) callconv(.C) void;

const _ImVector = extern struct {
    Size: c_int = 0,
    Capacity: c_int = 0,
    Data: ?*anyopaque = null,
};

pub const Config = extern struct {
    SettingsFile: ?*const u8 = null,
    BeginSaveSession: ?*const ConfigSession = null,
    EndSaveSession: ?*const ConfigSession = null,
    SaveSettings: ?*const SaveSettings = null,
    LoadSettings: ?*const LoadSettings = null,
    SaveNodeSettings: ?*const SaveNodeSettings = null,
    LoadNodeSettings: ?*const LoadNodeSettings = null,
    UserPointer: ?*anyopaque = null,
    CustomZoomLevels: _ImVector = .{},
    CanvasSizeMode: CanvasSizeMode = .FitVerticalView,
    DragButtonIndex: c_int = 0,
    SelectButtonIndex: c_int = 0,
    NavigateButtonIndex: c_int = 1,
    ContextMenuButtonIndex: c_int = 1,
    EnableSmoothZoom: bool = false,
    SmoothZoomPower: f32 = 1.1,
};

//
// Editor
//
const SaveReasonFlags = packed struct(u32) {
    Navigation: bool,
    Position: bool,
    Size: bool,
    Selection: bool,
    AddNode: bool,
    RemoveNode: bool,
    User: bool,
    _pad: u25,
};

pub fn setCurrentEditor(editor: ?*EditorContext) void {
    zine_SetCurrentEditor(editor);
}
extern fn zine_SetCurrentEditor(editor: ?*EditorContext) void;

pub fn begin(id: [:0]const u8, size: [2]f32) void {
    zine_Begin(id, &size);
}
extern fn zine_Begin(id: [*c]const u8, size: [*]const f32) void;

pub fn end() void {
    zine_End();
}
extern fn zine_End() void;

pub fn showBackgroundContextMenu() bool {
    return zine_ShowBackgroundContextMenu();
}
extern fn zine_ShowBackgroundContextMenu() bool;

pub fn showNodeContextMenu(id: *NodeId) bool {
    return zine_ShowNodeContextMenu(id);
}
extern fn zine_ShowNodeContextMenu(id: *NodeId) bool;

pub fn showLinkContextMenu(id: *LinkId) bool {
    return zine_ShowLinkContextMenu(id);
}
extern fn zine_ShowLinkContextMenu(id: *LinkId) bool;

pub fn showPinContextMenu(id: *PinId) bool {
    return zine_ShowPinContextMenu(id);
}
extern fn zine_ShowPinContextMenu(id: *PinId) bool;

pub fn suspend_() void {
    return zine_Suspend();
}
extern fn zine_Suspend() void;

pub fn resume_() void {
    return zine_Resume();
}
extern fn zine_Resume() void;

pub fn navigateToContent(duration: f32) void {
    zine_NavigateToContent(duration);
}
extern fn zine_NavigateToContent(duration: f32) void;

pub fn navigateToSelection(zoomIn: bool, duration: f32) void {
    zine_NavigateToSelection(zoomIn, duration);
}
extern fn zine_NavigateToSelection(zoomIn: bool, duration: f32) void;

pub fn selectNode(nodeId: NodeId, append: bool) void {
    zine_SelectNode(nodeId, append);
}
extern fn zine_SelectNode(nodeId: NodeId, append: bool) void;

pub fn selectLink(linkId: LinkId, append: bool) void {
    zine_SelectLink(linkId, append);
}
extern fn zine_SelectLink(linkId: LinkId, append: bool) void;

//
// Node
//
const NodeId = u64;

pub fn beginNode(id: NodeId) void {
    zine_BeginNode(id);
}
extern fn zine_BeginNode(id: NodeId) void;

pub fn endNode() void {
    zine_EndNode();
}
extern fn zine_EndNode() void;

pub fn setNodePosition(id: NodeId, pos: [2]f32) void {
    zine_SetNodePosition(id, &pos);
}
extern fn zine_SetNodePosition(id: NodeId, pos: [*]const f32) void;

pub fn getNodePosition(id: NodeId) [2]f32 {
    var pos: [2]f32 = .{ 0, 0 };
    zine_getNodePosition(id, &pos);
    return pos;
}
extern fn zine_getNodePosition(id: NodeId, pos: [*]f32) void;

pub fn getNodeSize(id: NodeId) [2]f32 {
    var size: [2]f32 = .{ 0, 0 };
    zine_getNodeSize(id, &size);
    return size;
}
extern fn zine_getNodeSize(id: NodeId, size: [*]f32) void;

pub fn deleteNode(id: NodeId) bool {
    return zine_DeleteNode(id);
}
extern fn zine_DeleteNode(id: NodeId) bool;

//
// Pin
//
const PinId = u64;

const PinKind = enum(u32) {
    Input = 0,
    Output,
};

pub fn beginPin(id: PinId, kind: PinKind) void {
    zine_BeginPin(id, kind);
}
extern fn zine_BeginPin(id: PinId, kind: PinKind) void;

pub fn endPin() void {
    zine_EndPin();
}
extern fn zine_EndPin() void;

pub fn pinHadAnyLinks(pinId: PinId) bool {
    return zine_PinHadAnyLinks(pinId);
}
extern fn zine_PinHadAnyLinks(pinId: PinId) bool;

//
// Link
//
const LinkId = u64;

pub fn link(id: LinkId, startPinId: PinId, endPinId: PinId, color: [4]f32, thickness: f32) bool {
    return zine_Link(id, startPinId, endPinId, &color, thickness);
}
extern fn zine_Link(id: LinkId, startPinId: PinId, endPinId: PinId, color: [*]const f32, thickness: f32) bool;

pub fn deleteLink(id: LinkId) bool {
    return zine_DeleteLink(id);
}
extern fn zine_DeleteLink(id: LinkId) bool;

pub fn breakPinLinks(id: PinId) i32 {
    return zine_BreakPinLinks(id);
}
extern fn zine_BreakPinLinks(id: PinId) c_int;

//
// Created
//

pub fn beginCreate() bool {
    return zine_BeginCreate();
}
extern fn zine_BeginCreate() bool;

pub fn endCreate() void {
    zine_EndCreate();
}
extern fn zine_EndCreate() void;

pub fn queryNewLink(startId: *?PinId, endId: *?PinId) bool {
    var sid: PinId = 0;
    var eid: PinId = 0;
    const result = zine_QueryNewLink(&sid, &eid);

    startId.* = if (sid == 0) null else sid;
    endId.* = if (eid == 0) null else eid;

    return result;
}
extern fn zine_QueryNewLink(startId: *PinId, endId: *PinId) bool;

pub fn acceptNewItem(color: [4]f32, thickness: f32) bool {
    return zine_AcceptNewItem(&color, thickness);
}
extern fn zine_AcceptNewItem(color: [*]const f32, thickness: f32) bool;

pub fn rejectNewItem(color: [4]f32, thickness: f32) void {
    zine_RejectNewItem(&color, thickness);
}
extern fn zine_RejectNewItem(color: [*]const f32, thickness: f32) void;

//
// Deleted
//
pub fn beginDelete() bool {
    return zine_BeginDelete();
}
extern fn zine_BeginDelete() bool;

pub fn endDelete() void {
    zine_EndDelete();
}
extern fn zine_EndDelete() void;

pub fn queryDeletedLink(linkId: *LinkId, startId: ?*PinId, endId: ?*PinId) bool {
    const result = zine_QueryDeletedLink(linkId, startId, endId);
    return result;
}
extern fn zine_QueryDeletedLink(linkId: *LinkId, startId: ?*PinId, endId: ?*PinId) bool;

pub fn queryDeletedNode(nodeId: *NodeId) bool {
    var nid: LinkId = 0;
    const result = zine_QueryDeletedNode(&nid);

    nodeId.* = nid;

    return result;
}
extern fn zine_QueryDeletedNode(nodeId: *NodeId) bool;

pub fn acceptDeletedItem(deleteDependencies: bool) bool {
    return zine_AcceptDeletedItem(deleteDependencies);
}
extern fn zine_AcceptDeletedItem(deleteDependencies: bool) bool;

pub fn rejectDeletedItem() void {
    zine_RejectDeletedItem();
}
extern fn zine_RejectDeletedItem() void;

// Style
pub fn getStyle() Style {
    return zine_GetStyle();
}
extern fn zine_GetStyle() Style;

pub fn getStyleColorName(colorIndex: StyleColor) [*c]const u8 {
    return zine_GetStyleColorName(colorIndex);
}
extern fn zine_GetStyleColorName(colorIndex: StyleColor) [*c]const u8;

pub fn pushStyleColor(colorIndex: StyleColor, color: [4]f32) void {
    zine_PushStyleColor(colorIndex, &color);
}
extern fn zine_PushStyleColor(colorIndex: StyleColor, color: [*]const f32) void;

pub fn popStyleColor(count: c_int) void {
    zine_PopStyleColor(count);
}
extern fn zine_PopStyleColor(count: c_int) void;

pub fn pushStyleColorushStyleVarF(varIndex: StyleVar, value: f32) void {
    zine_PushStyleVarF(varIndex, value);
}
extern fn zine_PushStyleVarF(varIndex: StyleVar, value: f32) void;

pub fn pushStyleVar2f(varIndex: StyleVar, value: [2]f32) void {
    zine_PushStyleVar2f(varIndex, &value);
}
extern fn zine_PushStyleVar2f(varIndex: StyleVar, value: [*]const f32) void;

pub fn pushStyleVar4f(varIndex: StyleVar, value: [4]f32) void {
    zine_PushStyleVar4f(varIndex, &value);
}
extern fn zine_PushStyleVar4f(varIndex: StyleVar, value: [*]const f32) void;

pub fn popStyleVar(count: c_int) void {
    zine_PopStyleVar(count);
}
extern fn zine_PopStyleVar(count: c_int) void;

// Selection
pub fn hasSelectionChanged() bool {
    return zine_HasSelectionChanged();
}
extern fn zine_HasSelectionChanged() bool;

pub fn getSelectedObjectCount() c_int {
    return zine_GetSelectedObjectCount();
}
extern fn zine_GetSelectedObjectCount() c_int;

pub fn clearSelection() void {
    zine_ClearSelection();
}
extern fn zine_ClearSelection() void;

pub fn getSelectedNodes(nodes: []NodeId) c_int {
    return zine_GetSelectedNodes(nodes.ptr, @intCast(nodes.len));
}
extern fn zine_GetSelectedNodes(nodes: [*]NodeId, size: c_int) c_int;

pub fn getSelectedLinks(links: []LinkId) c_int {
    return zine_GetSelectedLinks(links.ptr, @intCast(links.len));
}
extern fn zine_GetSelectedLinks(links: [*]LinkId, size: c_int) c_int;

pub fn group(size: [2]f32) void {
    zine_Group(&size);
}
extern fn zine_Group(size: [*]const f32) void;
