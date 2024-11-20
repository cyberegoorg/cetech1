const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;

pub const EditorAssetAPI = struct {
    filerAsset: *const fn (tmp_allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cdb.ObjId) anyerror!assetdb.FilteredAssets,
};
