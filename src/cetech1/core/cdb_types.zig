const std = @import("std");

const cdb = @import("cdb.zig");
const strid = @import("strid.zig");

pub const Color4fType = cdb.CdbTypeDecl(
    "ct_color_4f",
    enum(u32) {
        R = 0,
        G,
        B,
        A,
    },
);

pub fn color4fToSlice(db: *cdb.CdbDb, color_obj: cdb.ObjId) [4]f32 {
    const r = db.readObj(color_obj) orelse return .{ 1.0, 1.0, 1.0, 1.0 };
    return .{
        Color4fType.readValue(db, f32, r, .R),
        Color4fType.readValue(db, f32, r, .G),
        Color4fType.readValue(db, f32, r, .B),
        Color4fType.readValue(db, f32, r, .A),
    };
}

pub fn color4fFromSlice(db: *cdb.CdbDb, color_obj_w: *cdb.Obj, color: [4]f32) void {
    Color4fType.setValue(db, f32, color_obj_w, .R, color[0]);
    Color4fType.setValue(db, f32, color_obj_w, .G, color[1]);
    Color4fType.setValue(db, f32, color_obj_w, .B, color[2]);
    Color4fType.setValue(db, f32, color_obj_w, .A, color[3]);
}

//#region BigType
/// Properties enum fro BigType
pub const BigTypeProps = enum(u32) {
    Bool = 0,
    U64,
    I64,
    U32,
    I32,
    F32,
    F64,
    Str,
    Blob,
    Subobject,
    Reference,
    SubobjectSet,
    ReferenceSet,
};

/// BigType Decl
pub fn BigTypeDecl(comptime type_name: [:0]const u8) type {
    return cdb.CdbTypeDecl(type_name, BigTypeProps);
}

/// Add BigType db
pub fn addBigType(db: *cdb.CdbDb, name: []const u8) !strid.StrId32 {
    return db.addType(
        name,
        &.{
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Bool), .name = "bool", .type = cdb.PropType.BOOL },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.U64), .name = "u64", .type = cdb.PropType.U64 },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.I64), .name = "i64", .type = cdb.PropType.I64 },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.U32), .name = "u32", .type = cdb.PropType.U32 },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.I32), .name = "i32", .type = cdb.PropType.I32 },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.F32), .name = "f32", .type = cdb.PropType.F32 },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.F64), .name = "f64", .type = cdb.PropType.F64 },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Str), .name = "str", .type = cdb.PropType.STR },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Blob), .name = "blob", .type = cdb.PropType.BLOB },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Subobject), .name = "subobject", .type = cdb.PropType.SUBOBJECT },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Reference), .name = "reference", .type = cdb.PropType.REFERENCE },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.SubobjectSet), .name = "subobject_set", .type = cdb.PropType.SUBOBJECT_SET },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.ReferenceSet), .name = "reference_set", .type = cdb.PropType.REFERENCE_SET },
        },
    );
}
//#endregion
