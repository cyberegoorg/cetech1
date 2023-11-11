const std = @import("std");
const cetech1 = @import("cetech1");

pub const AssetBrowserAPI = struct {
    selectObjFromBrowserMenu: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, ignored_obj: cetech1.cdb.ObjId, allowed_type: cetech1.strid.StrId32) ?cetech1.cdb.ObjId,
};
