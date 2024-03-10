const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const strid = cetech1.strid;

const editor = @import("editor");

pub const UiTreeAspect = extern struct {
    pub const c_name = "ct_ui_tree_aspect";
    pub const name_hash = strid.strId32(UiTreeAspect.c_name);

    ui_tree: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        tab: *editor.TabO,
        context: [*]const strid.StrId64,
        context_n: usize,
        obj: cdb.ObjId,
        selected_obj: cdb.ObjId,
        args: CdbTreeViewArgs,
    ) callconv(.C) void = null,

    ui_drop_obj: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        tab: *editor.TabO,
        obj: cdb.ObjId,
        drag_obj: cdb.ObjId,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiTreeAspect {
        if (!std.meta.hasFn(T, "uiTree")) @compileError("implement me");

        return UiTreeAspect{
            .ui_tree = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    tab: *editor.TabO,
                    context: [*]const strid.StrId64,
                    context_n: usize,
                    obj: cdb.ObjId,
                    selected_obj: cdb.ObjId,
                    args: CdbTreeViewArgs,
                ) callconv(.C) void {
                    T.uiTree(allocator.*, db, tab, context[0..context_n], obj, selected_obj, args) catch undefined;
                }
            }.f,

            .ui_drop_obj = if (std.meta.hasFn(T, "uiDropObj")) struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    tab: *editor.TabO,
                    obj: cdb.ObjId,
                    drag_obj: cdb.ObjId,
                ) callconv(.C) void {
                    T.uiDropObj(allocator.*, db, tab, obj, drag_obj) catch undefined;
                }
            }.f else null,
        };
    }
};

pub const CdbTreeViewArgs = extern struct {
    expand_object: bool = true,
    ignored_object: cdb.ObjId = .{},
    only_types: strid.StrId32 = .{},
    opened_obj: cdb.ObjId = .{},
    filter: ?[*:0]const u8 = null,
    multiselect: bool = false,
};

pub const TreeAPI = struct {
    // Tree view
    cdbTreeView: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, tab: *editor.TabO, []const strid.StrId64, obj: cdb.ObjId, selection: cdb.ObjId, args: CdbTreeViewArgs) anyerror!void,
    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool,
    cdbTreePop: *const fn () void,
    cdbObjTreeNode: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, tab: *editor.TabO, contexts: []const strid.StrId64, selection: cdb.ObjId, obj: cdb.ObjId, default_open: bool, no_push: bool, leaf: bool, args: CdbTreeViewArgs) bool,
};
