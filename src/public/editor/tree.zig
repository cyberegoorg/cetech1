const std = @import("std");
const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;

const log = std.log.scoped(.editor_tree);

const editor = cetech1.editor;
const editor_tabs = cetech1.editor.tabs;

pub const UiTreeAspect = struct {
    pub const c_name = "ct_ui_tree_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_tree: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: []const cetech1.StrId64,
        obj: coreui.SelectedObj,
        selected_obj: *coreui.Selection,
        depth: u32,
        args: CdbTreeViewArgs,
    ) anyerror!bool = undefined,

    pub fn implement(comptime T: type) UiTreeAspect {
        return UiTreeAspect{
            .ui_tree = T.uiTree,
        };
    }
};

pub const UiTreeFlatenPropertyAspect = struct {
    pub const c_name = "ct_ui_tree_flaten_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    pub fn implement() UiTreeFlatenPropertyAspect {
        return UiTreeFlatenPropertyAspect{};
    }
};

pub const CdbTreeViewArgs = struct {
    expand_object: bool = true,
    ignored_object: cdb.ObjId = .{},
    only_types: ?[]const cdb.TypeIdx = null,
    opened_obj: cdb.ObjId = .{},
    filter: ?[:0]const u8 = null,
    multiselect: bool = false,
    max_autopen_depth: u32 = 2,
    show_root: bool = false,
    show_status_icons: bool = false,
};

pub fn cdbTreeView(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, contexts: []const cetech1.StrId64, obj: coreui.SelectedObj, selection: *coreui.Selection, depth: u32, args: CdbTreeViewArgs) anyerror!bool {
    return api.cdbTreeView(allocator, tab, contexts, obj, selection, depth, args);
}
pub fn cdbObjTree(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, contexts: []const cetech1.StrId64, obj: coreui.SelectedObj, selection: *coreui.Selection, depth: u32, args: CdbTreeViewArgs) anyerror!bool {
    return api.cdbObjTree(allocator, tab, contexts, obj, selection, depth, args);
}
pub fn cdbTreeNode(label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool {
    return api.cdbTreeNode(label, default_open, no_push, selected, leaf, args);
}
pub fn cdbTreePop() void {
    return api.cdbTreePop();
}
pub fn cdbObjTreeNode(allocator: std.mem.Allocator, tab: *editor_tabs.TabO, contexts: []const cetech1.StrId64, selection: *coreui.Selection, obj: coreui.SelectedObj, default_open: bool, no_push: bool, leaf: bool, args: CdbTreeViewArgs) bool {
    return api.cdbObjTreeNode(allocator, tab, contexts, selection, obj, default_open, no_push, leaf, args);
}

// TODO: need unshit api
pub const TreeAPI = struct {
    cdbTreeView: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, []const cetech1.StrId64, obj: coreui.SelectedObj, selection: *coreui.Selection, depth: u32, args: CdbTreeViewArgs) anyerror!bool,
    cdbObjTree: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, []const cetech1.StrId64, obj: coreui.SelectedObj, selection: *coreui.Selection, depth: u32, args: CdbTreeViewArgs) anyerror!bool,
    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool,
    cdbTreePop: *const fn () void,
    cdbObjTreeNode: *const fn (allocator: std.mem.Allocator, tab: *editor_tabs.TabO, contexts: []const cetech1.StrId64, selection: *coreui.Selection, obj: coreui.SelectedObj, default_open: bool, no_push: bool, leaf: bool, args: CdbTreeViewArgs) bool,
};

pub var api: *const TreeAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, TreeAPI).?;
}
