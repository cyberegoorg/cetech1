const std = @import("std");

const cdb = @import("cdb.zig");
const strid = @import("strid.zig");

pub const Color4f = cdb.CdbTypeDecl(
    "ct_color_4f",
    enum(u32) {
        R = 0,
        G,
        B,
        A,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [4]f32 {
            const r = api.readObj(obj) orelse return .{ 1.0, 1.0, 1.0, 1.0 };
            return .{
                Color4f.readValue(f32, api, r, .R),
                Color4f.readValue(f32, api, r, .G),
                Color4f.readValue(f32, api, r, .B),
                Color4f.readValue(f32, api, r, .A),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [4]f32) void {
            Color4f.setValue(f32, api, obj_w, .R, value[0]);
            Color4f.setValue(f32, api, obj_w, .G, value[1]);
            Color4f.setValue(f32, api, obj_w, .B, value[2]);
            Color4f.setValue(f32, api, obj_w, .A, value[3]);
        }
    },
);

pub const Vec2f = cdb.CdbTypeDecl(
    "ct_vec_2f",
    enum(u32) {
        X = 0,
        Y,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [2]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0 };
            return .{
                Vec2f.readValue(f32, api, r, .X),
                Vec2f.readValue(f32, api, r, .Y),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [2]f32) void {
            Vec2f.setValue(f32, api, obj_w, .X, value[0]);
            Vec2f.setValue(f32, api, obj_w, .Y, value[1]);
        }
    },
);

pub const Vec3f = cdb.CdbTypeDecl(
    "ct_vec_3f",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [3]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0, 0.0 };
            return .{
                Vec3f.readValue(f32, api, r, .X),
                Vec3f.readValue(f32, api, r, .Y),
                Vec3f.readValue(f32, api, r, .Z),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [3]f32) void {
            Vec3f.setValue(f32, api, obj_w, .X, value[0]);
            Vec3f.setValue(f32, api, obj_w, .Y, value[1]);
            Vec3f.setValue(f32, api, obj_w, .Z, value[2]);
        }
    },
);

pub const Vec4f = cdb.CdbTypeDecl(
    "ct_vec_4f",
    enum(u32) {
        X = 0,
        Y,
        Z,
        W,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [4]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0, 0.0, 0.0 };
            return .{
                Vec4f.readValue(f32, api, r, .X),
                Vec4f.readValue(f32, api, r, .Y),
                Vec4f.readValue(f32, api, r, .Z),
                Vec4f.readValue(f32, api, r, .W),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [3]f32) void {
            Vec4f.setValue(f32, api, obj_w, .X, value[0]);
            Vec4f.setValue(f32, api, obj_w, .Y, value[1]);
            Vec4f.setValue(f32, api, obj_w, .Z, value[2]);
            Vec4f.setValue(f32, api, obj_w, .W, value[3]);
        }
    },
);

pub const Quatf = cdb.CdbTypeDecl(
    "ct_quat_f",
    enum(u32) {
        X = 0,
        Y,
        Z,
        W,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [4]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0, 0.0, 1.0 };
            return .{
                Vec4f.readValue(api, f32, r, .X),
                Vec4f.readValue(api, f32, r, .Y),
                Vec4f.readValue(api, f32, r, .Z),
                Vec4f.readValue(api, f32, r, .W),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [3]f32) void {
            Vec4f.setValue(f32, api, obj_w, .X, value[0]);
            Vec4f.setValue(f32, api, obj_w, .Y, value[1]);
            Vec4f.setValue(f32, api, obj_w, .Z, value[2]);
            Vec4f.setValue(f32, api, obj_w, .W, value[3]);
        }
    },
);

pub const BoolType = cdb.CdbTypeDecl(
    "ct_bool",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const StringType = cdb.CdbTypeDecl(
    "ct_string",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const i32Type = cdb.CdbTypeDecl(
    "ct_i32",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const u32Type = cdb.CdbTypeDecl(
    "ct_u32",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const i64Type = cdb.CdbTypeDecl(
    "ct_i64",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const u64Type = cdb.CdbTypeDecl(
    "ct_u64",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const f32Type = cdb.CdbTypeDecl(
    "ct_f32",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const f64Type = cdb.CdbTypeDecl(
    "ct_f64",
    enum(u32) {
        value = 0,
    },
    struct {},
);

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
    return cdb.CdbTypeDecl(type_name, BigTypeProps, struct {});
}

/// Add BigType db
pub fn addBigType(db: *const cdb.CdbAPI, dbidx: cdb.DbId, name: []const u8, force_subobj_type: ?strid.StrId32) !cdb.TypeIdx {
    return db.addType(
        dbidx,
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
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Subobject), .name = "subobject", .type = cdb.PropType.SUBOBJECT, .type_hash = force_subobj_type orelse .{} },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.Reference), .name = "reference", .type = cdb.PropType.REFERENCE },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.SubobjectSet), .name = "subobject_set", .type = cdb.PropType.SUBOBJECT_SET, .type_hash = force_subobj_type orelse .{} },
            .{ .prop_idx = cdb.propIdx(BigTypeProps.ReferenceSet), .name = "reference_set", .type = cdb.PropType.REFERENCE_SET },
        },
    );
}
//#endregion
