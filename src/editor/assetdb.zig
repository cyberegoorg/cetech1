const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;
const apidb = cetech1.apidb;

pub const CreateAssetI = struct {
    pub const c_name = "ct_assetbrowser_create_asset_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    cdb_type: cetech1.StrId32,

    menu_item: *const fn () anyerror![:0]const u8,

    create: *const fn (
        allocator: std.mem.Allocator,
        db: cdb.DbId,
        folder: cdb.ObjId,
    ) anyerror!void,

    pub fn implement(cdb_type: cetech1.StrId32, comptime T: type) CreateAssetI {
        return CreateAssetI{
            .cdb_type = cdb_type,

            .create = T.create,
            .menu_item = T.menuItem,
        };
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

pub fn tagsInput(
    allocator: std.mem.Allocator,
    obj: cdb.ObjId,
    prop_idx: u32,
    in_table: bool,
    filter: ?[:0]const u8,
) anyerror!bool {
    return api.tagsInput(allocator, obj, prop_idx, in_table, filter);
}

pub const EditorAssetDBAPI = struct {
    tagsInput: *const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        in_table: bool,
        filter: ?[:0]const u8,
    ) anyerror!bool,
};

pub var api: *const EditorAssetDBAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, EditorAssetDBAPI).?;
}
