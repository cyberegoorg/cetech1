const std = @import("std");
const cetech1 = @import("cetech1");

pub const UiTreeAspect = extern struct {
    ui_tree: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cetech1.cdb.Db,
        obj: cetech1.cdb.ObjId,
        selected_obj: cetech1.cdb.ObjId,
        args: CdbTreeViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(
        ui_tree: *const fn (
            allocator: std.mem.Allocator,
            db: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
            selected_obj: cetech1.cdb.ObjId,
            args: CdbTreeViewArgs,
        ) anyerror!void,
    ) UiTreeAspect {
        const Wrap = struct {
            pub fn ui_c(
                allocator: *const std.mem.Allocator,
                db: *cetech1.cdb.Db,
                obj: cetech1.cdb.ObjId,
                selected_obj: cetech1.cdb.ObjId,
                args: CdbTreeViewArgs,
            ) callconv(.C) void {
                ui_tree(allocator.*, db, obj, selected_obj, args) catch undefined;
            }
        };

        return UiTreeAspect{
            .ui_tree = Wrap.ui_c,
        };
    }
};

pub const CdbTreeViewArgs = extern struct {
    expand_object: bool = true,
    ignored_object: cetech1.cdb.ObjId = .{},
    only_types: cetech1.strid.StrId32 = .{},
    opened_obj: cetech1.cdb.ObjId = .{},
    filter: ?[*:0]const u8 = null,
    multiselect: bool = false,
};

pub const TreeAPI = struct {
    // Tree view
    cdbTreeView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, selection: cetech1.cdb.ObjId, args: CdbTreeViewArgs) anyerror!void,
    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool,
    cdbTreePop: *const fn () void,
    cdbObjTreeNode: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, default_open: bool, no_push: bool, selected: bool, leaf: bool, args: CdbTreeViewArgs) bool,
};
