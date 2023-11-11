const std = @import("std");
const cetech1 = @import("cetech1");

pub const EditorTagsApi = struct {
    tagsInput: *const fn (
        allocator: std.mem.Allocator,
        db: *cetech1.cdb.CdbDb,
        obj: cetech1.cdb.ObjId,
        prop_idx: u32,
        in_table: bool,
        filter: ?[*:0]const u8,
    ) anyerror!bool,
};
