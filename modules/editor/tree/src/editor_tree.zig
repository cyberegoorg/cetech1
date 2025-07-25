const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const coreui = cetech1.coreui;

const log = std.log.scoped(.editor_tree);

const editor = @import("editor");

pub const UiTreeAspect = struct {
    pub const c_name = "ct_ui_tree_aspect";
    pub const name_hash = cetech1.strId32(@This().c_name);

    ui_tree: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        context: []const cetech1.StrId64,
        obj: coreui.SelectionItem,
        selected_obj: *coreui.Selection,
        depth: u32,
        args: CdbTreeViewArgs,
    ) anyerror!bool = undefined,

    ui_drop_obj: ?*const fn (
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
        obj: cdb.ObjId,
        drag_obj: cdb.ObjId,
    ) anyerror!void = null,

    pub fn implement(comptime T: type) UiTreeAspect {
        if (!std.meta.hasFn(T, "uiTree")) @compileError("implement me");

        return UiTreeAspect{
            .ui_tree = T.uiTree,
            .ui_drop_obj = if (std.meta.hasFn(T, "uiDropObj")) T.uiDropObj else null,
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

pub fn filterOnlyTypes(only_types: ?[]const cdb.TypeIdx, obj: cdb.ObjId) bool {
    if (only_types) |ot| {
        if (ot.len != 0) {
            for (ot) |o| {
                if (obj.type_idx.eql(o)) return true;
            }
            return false;
        }
    }

    return true;
}

pub const CdbTreeViewArgs = struct {
    expand_object: bool = true,
    ignored_object: cdb.ObjId = .{},
    only_types: ?[]const cdb.TypeIdx = null,
    opened_obj: cdb.ObjId = .{},
    filter: ?[:0]const u8 = null,
    multiselect: bool = false,
    max_autopen_depth: u32 = 2,
    show_root: bool = false,
};

// TODO: need unshit api
pub const TreeAPI = struct {
    // Tree view
    cdbTreeView: *const fn (
        allocator: std.mem.Allocator,
        tab: *editor.TabO,
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
        tab: *editor.TabO,
        contexts: []const cetech1.StrId64,
        selection: *coreui.Selection,
        obj: coreui.SelectionItem,
        default_open: bool,
        no_push: bool,
        leaf: bool,
        args: CdbTreeViewArgs,
    ) bool,
};
