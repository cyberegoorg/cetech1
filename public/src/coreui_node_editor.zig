const std = @import("std");

const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const cetech1 = @import("root.zig");

const platform = @import("platform.zig");

const coreui = @import("coreui.zig");

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

    colors: [@typeInfo(StyleColor).@"enum".fields.len][4]f32,

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

pub const CanvasSizeMode = enum(c_int) {
    FitVerticalView, // Previous view will be scaled to fit new view on Y axis
    FitHorizontalView, // Previous view will be scaled to fit new view on X axis
    CenterOnly, // Previous view will be centered on new view
};

pub const SaveReasonFlags = packed struct(u32) {
    Navigation: bool,
    Position: bool,
    Size: bool,
    Selection: bool,
    AddNode: bool,
    RemoveNode: bool,
    User: bool,
    _pad: u25,
};

const SaveNodeSettings = fn (nodeId: NodeId, data: [*]const u8, size: usize, reason: SaveReasonFlags, userPointer: *anyopaque) callconv(.c) bool;
const LoadNodeSettings = fn (nodeId: NodeId, data: [*]u8, userPointer: *anyopaque) callconv(.c) usize;
const SaveSettings = fn (data: [*]const u8, size: usize, reason: SaveReasonFlags, userPointer: *anyopaque) callconv(.c) bool;
const LoadSettings = fn (data: [*]u8, userPointer: *anyopaque) callconv(.c) usize;
const ConfigSession = fn (userPointer: *anyopaque) callconv(.c) void;

pub const Config = extern struct {
    SettingsFile: ?*const u8 = null,
    BeginSaveSession: ?*const ConfigSession = null,
    EndSaveSession: ?*const ConfigSession = null,
    SaveSettings: ?*const SaveSettings = null,
    LoadSettings: ?*const LoadSettings = null,
    SaveNodeSettings: ?*const SaveNodeSettings = null,
    LoadNodeSettings: ?*const LoadNodeSettings = null,
    UserPointer: ?*anyopaque = null,
    CanvasSizeMode: CanvasSizeMode = .FitVerticalView,
    DragButtonIndex: c_int = 0,
    SelectButtonIndex: c_int = 0,
    NavigateButtonIndex: c_int = 1,
    ContextMenuButtonIndex: c_int = 1,
    EnableSmoothZoom: bool = false,
    SmoothZoomPower: f32 = 1.1,
};

pub const NodeEditorApi = struct {
    createEditor: *const fn (cfg: Config) *EditorContext,
    destroyEditor: *const fn (editor: *EditorContext) void,

    setCurrentEditor: *const fn (editor: ?*EditorContext) void,
    begin: *const fn (id: [:0]const u8, size: [2]f32) void,
    end: *const fn () void,

    suspend_: *const fn () void,
    resume_: *const fn () void,

    showBackgroundContextMenu: *const fn () bool,

    showNodeContextMenu: *const fn (id: *NodeId) bool,
    showLinkContextMenu: *const fn (id: *LinkId) bool,
    showPinContextMenu: *const fn (id: *PinId) bool,

    beginNode: *const fn (id: NodeId) void,
    endNode: *const fn () void,
    deleteNode: *const fn (id: NodeId) bool,

    setNodePosition: *const fn (id: NodeId, pos: [2]f32) void,
    getNodePosition: *const fn (id: NodeId) [2]f32,
    getNodeSize: *const fn (id: NodeId) [2]f32,

    beginPin: *const fn (id: PinId, kind: PinKind) void,
    endPin: *const fn () void,
    pinHadAnyLinks: *const fn (pinId: PinId) bool,

    link: *const fn (id: LinkId, startPinId: PinId, endPinId: PinId, color: [4]f32, thickness: f32) void,
    deleteLink: *const fn (id: LinkId) bool,

    beginCreate: *const fn () bool,
    endCreate: *const fn () void,

    queryNewLink: *const fn (startId: *?PinId, endId: *?PinId) bool,
    acceptNewItem: *const fn (color: [4]f32, thickness: f32) bool,
    rejectNewItem: *const fn (color: [4]f32, thickness: f32) void,

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
    pushStyleColor: *const fn (colorIndex: StyleColor, color: [4]f32) void,
    popStyleColor: *const fn (count: c_int) void,
    pushStyleVar1f: *const fn (varIndex: StyleVar, value: f32) void,
    pushStyleVar2f: *const fn (varIndex: StyleVar, value: [2]f32) void,
    pushStyleVar4f: *const fn (varIndex: StyleVar, value: [4]f32) void,
    popStyleVar: *const fn (count: c_int) void,

    hasSelectionChanged: *const fn () bool,
    getSelectedObjectCount: *const fn () c_int,
    clearSelection: *const fn () void,
    getSelectedNodes: *const fn (nodes: []NodeId) c_int,
    getSelectedLinks: *const fn (links: []LinkId) c_int,
    selectNode: *const fn (nodeId: NodeId, append: bool) void,
    selectLink: *const fn (linkId: LinkId, append: bool) void,

    group: *const fn (size: [2]f32) void,

    getHintForegroundDrawList: *const fn () coreui.DrawList,
    getHintBackgroundDrawList: *const fn () coreui.DrawList,
    getNodeBackgroundDrawList: *const fn (node_id: NodeId) coreui.DrawList,

    pinRect: *const fn (a: [2]f32, b: [2]f32) void,
    pinPivotRect: *const fn (a: [2]f32, b: [2]f32) void,
    pinPivotSize: *const fn (size: [2]f32) void,
    pinPivotScale: *const fn (scale: [2]f32) void,
    pinPivotAlignment: *const fn (alignment: [2]f32) void,
};
