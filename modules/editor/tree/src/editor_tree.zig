const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const coreui = cetech1.coreui;

const log = std.log.scoped(.editor_tree);

const editor = @import("editor");
const editor_tabs = @import("editor_tabs");

pub const UiTreeAspect = struct {
    pub const c_name = "ct_ui_tree_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_tree: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        context: []const cetech1.StrId64,
        obj: coreui.SelectionItem,
        selected_obj: *coreui.Selection,
        depth: u32,
        args: CdbTreeViewArgs,
    ) anyerror!bool = undefined,

    pub fn implement(comptime T: type) UiTreeAspect {
        if (!std.meta.hasFn(T, "uiTree")) @compileError("implement me");

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

// TODO: need unshit api
pub const TreeAPI = struct {
    // Tree view
    cdbTreeView: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        []const cetech1.StrId64,
        obj: coreui.SelectionItem,
        selection: *coreui.Selection,
        depth: u32,
        args: CdbTreeViewArgs,
    ) anyerror!bool,

    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool,
    cdbTreePop: *const fn () void,

    cdbObjTreeNode: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: []const cetech1.StrId64,
        selection: *coreui.Selection,
        obj: coreui.SelectionItem,
        default_open: bool,
        no_push: bool,
        leaf: bool,
        args: CdbTreeViewArgs,
    ) bool,
};
