const std = @import("std");
const cetech1 = @import("cetech1");
const editor = @import("editor");

pub const InspectorAPI = struct {
    uiPropLabel: *const fn (allocator: std.mem.Allocator, name: [:0]const u8, color: ?[4]f32, args: cetech1.editorui.cdbPropertiesViewArgs) bool,
    uiPropInput: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputBegin: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputEnd: *const fn () void,
    uiAssetInput: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32, read_only: bool, in_table: bool) anyerror!void,

    // Property utils
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,
    getPropertyColor: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32,

    // Property view
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, tab: *editor.TabO, obj: cetech1.cdb.ObjId, args: cetech1.editorui.cdbPropertiesViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, tab: *editor.TabO, obj: cetech1.cdb.ObjId, args: cetech1.editorui.cdbPropertiesViewArgs) anyerror!void,

    beginSection: *const fn (label: [:0]const u8, leaf: bool, default_open: bool) bool,
    endSection: *const fn (open: bool) void,
};
