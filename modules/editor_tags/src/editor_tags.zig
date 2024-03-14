const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

pub const EditorTagsApi = struct {
    tagsInput: *const fn (
        allocator: std.mem.Allocator,
        db: *cdb.CdbDb,
        obj: cdb.ObjId,
        prop_idx: u32,
        in_table: bool,
        filter: ?[*:0]const u8,
    ) anyerror!bool,
};
