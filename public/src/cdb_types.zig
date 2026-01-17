const std = @import("std");

const cdb = @import("cdb.zig");
const cetech1 = @import("root.zig");
const math = cetech1.math;

pub const Color3fCdb = cdb.CdbTypeDecl(
    "ct_color_3f",
    enum(u32) {
        R = 0,
        G,
        B,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Color3f {
            const r = api.readObj(obj) orelse return .{ .r = 1, .g = 1, .b = 1 };
            return .{
                .r = Color3fCdb.readValue(f32, api, r, .R),
                .g = Color3fCdb.readValue(f32, api, r, .G),
                .b = Color3fCdb.readValue(f32, api, r, .B),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Color3f) void {
            Color3fCdb.setValue(f32, api, obj_w, .R, value.r);
            Color3fCdb.setValue(f32, api, obj_w, .G, value.g);
            Color3fCdb.setValue(f32, api, obj_w, .B, value.b);
        }
    },
);

pub const Color4fCdb = cdb.CdbTypeDecl(
    "ct_color_4f",
    enum(u32) {
        R = 0,
        G,
        B,
        A,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Color4f {
            const r = api.readObj(obj) orelse return .{ .r = 1, .g = 1, .b = 1, .a = 1 };
            return .{
                .r = Color4fCdb.readValue(f32, api, r, .R),
                .g = Color4fCdb.readValue(f32, api, r, .G),
                .b = Color4fCdb.readValue(f32, api, r, .B),
                .a = Color4fCdb.readValue(f32, api, r, .A),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Color4f) void {
            Color4fCdb.setValue(f32, api, obj_w, .R, value.r);
            Color4fCdb.setValue(f32, api, obj_w, .G, value.g);
            Color4fCdb.setValue(f32, api, obj_w, .B, value.b);
            Color4fCdb.setValue(f32, api, obj_w, .A, value.a);
        }
    },
);

pub const Vec2fCdb = cdb.CdbTypeDecl(
    "ct_vec_2f",
    enum(u32) {
        X = 0,
        Y,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Vec2f {
            const r = api.readObj(obj) orelse return .{};
            return .{
                .x = Vec2fCdb.readValue(f32, api, r, .X),
                .y = Vec2fCdb.readValue(f32, api, r, .Y),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Vec2f) void {
            Vec2fCdb.setValue(f32, api, obj_w, .X, value.x);
            Vec2fCdb.setValue(f32, api, obj_w, .Y, value.y);
        }
    },
);

pub const Vec3fCdb = cdb.CdbTypeDecl(
    "ct_vec_3f",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Vec3f {
            const r = api.readObj(obj) orelse return .{};
            return .{
                .x = Vec3fCdb.readValue(f32, api, r, .X),
                .y = Vec3fCdb.readValue(f32, api, r, .Y),
                .z = Vec3fCdb.readValue(f32, api, r, .Z),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Vec3f) void {
            Vec3fCdb.setValue(f32, api, obj_w, .X, value.x);
            Vec3fCdb.setValue(f32, api, obj_w, .Y, value.y);
            Vec3fCdb.setValue(f32, api, obj_w, .Z, value.z);
        }
    },
);

pub const Vec4fCdb = cdb.CdbTypeDecl(
    "ct_vec_4f",
    enum(u32) {
        X = 0,
        Y,
        Z,
        W,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Vec4f {
            const r = api.readObj(obj) orelse return .{};
            return .{
                .x = Vec4fCdb.readValue(f32, api, r, .X),
                .y = Vec4fCdb.readValue(f32, api, r, .Y),
                .z = Vec4fCdb.readValue(f32, api, r, .Z),
                .w = Vec4fCdb.readValue(f32, api, r, .W),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Vec4f) void {
            Vec4fCdb.setValue(f32, api, obj_w, .X, value[0]);
            Vec4fCdb.setValue(f32, api, obj_w, .Y, value[1]);
            Vec4fCdb.setValue(f32, api, obj_w, .Z, value[2]);
            Vec4fCdb.setValue(f32, api, obj_w, .W, value[3]);
        }
    },
);

pub const QuatfCdb = cdb.CdbTypeDecl(
    "ct_quat_f",
    enum(u32) {
        X = 0,
        Y,
        Z,
        W,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Quatf {
            const r = api.readObj(obj) orelse return .{};
            return .{
                .x = QuatfCdb.readValue(f32, api, r, .X),
                .y = QuatfCdb.readValue(f32, api, r, .Y),
                .z = QuatfCdb.readValue(f32, api, r, .Z),
                .w = QuatfCdb.readValue(f32, api, r, .W),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Quatf) void {
            QuatfCdb.setValue(f32, api, obj_w, .X, value.x);
            QuatfCdb.setValue(f32, api, obj_w, .Y, value.y);
            QuatfCdb.setValue(f32, api, obj_w, .Z, value.z);
            QuatfCdb.setValue(f32, api, obj_w, .W, value.w);
        }
    },
);

pub const PositionCdb = cdb.CdbTypeDecl(
    "ct_position",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Vec3f {
            const r = api.readObj(obj) orelse return .{};
            return .{
                .x = PositionCdb.readValue(f32, api, r, .X),
                .y = PositionCdb.readValue(f32, api, r, .Y),
                .z = PositionCdb.readValue(f32, api, r, .Z),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Vec3f) void {
            PositionCdb.setValue(f32, api, obj_w, .X, value.x);
            PositionCdb.setValue(f32, api, obj_w, .Y, value.y);
            PositionCdb.setValue(f32, api, obj_w, .Z, value.z);
        }
    },
);

pub const ScaleCdb = cdb.CdbTypeDecl(
    "ct_scale",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Vec3f {
            const r = api.readObj(obj) orelse return .{ .x = 1.0, .y = 1.0, .z = 1.0 };
            return .{
                ScaleCdb.readValue(f32, api, r, .X),
                ScaleCdb.readValue(f32, api, r, .Y),
                ScaleCdb.readValue(f32, api, r, .Z),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Vec3f) void {
            ScaleCdb.setValue(f32, api, obj_w, .X, value.x);
            ScaleCdb.setValue(f32, api, obj_w, .Y, value.y);
            ScaleCdb.setValue(f32, api, obj_w, .Z, value.z);
        }
    },
);

pub const RotationCdb = cdb.CdbTypeDecl(
    "ct_rotation",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn to(api: *const cdb.CdbAPI, obj: cdb.ObjId) math.Vec3f {
            const r = api.readObj(obj) orelse return .{};
            return .{
                RotationCdb.readValue(f32, api, r, .X),
                RotationCdb.readValue(f32, api, r, .Y),
                RotationCdb.readValue(f32, api, r, .Z),
            };
        }

        pub fn from(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: math.Vec3f) void {
            ScaleCdb.setValue(f32, api, obj_w, .X, value.x);
            ScaleCdb.setValue(f32, api, obj_w, .Y, value.y);
            ScaleCdb.setValue(f32, api, obj_w, .Z, value.z);
        }
    },
);

pub const BoolTypeCdb = cdb.CdbTypeDecl(
    "ct_bool",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const StringTypeCdb = cdb.CdbTypeDecl(
    "ct_string",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const i32TypeCdb = cdb.CdbTypeDecl(
    "ct_i32",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const u32TypeCdb = cdb.CdbTypeDecl(
    "ct_u32",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const i64TypeCdb = cdb.CdbTypeDecl(
    "ct_i64",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const u64TypeCdb = cdb.CdbTypeDecl(
    "ct_u64",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const f32TypeCdb = cdb.CdbTypeDecl(
    "ct_f32",
    enum(u32) {
        Value = 0,
    },
    struct {},
);

pub const f64TypeCdb = cdb.CdbTypeDecl(
    "ct_f64",
    enum(u32) {
        Value = 0,
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
pub fn addBigType(db: *const cdb.CdbAPI, dbidx: cdb.DbId, name: []const u8, force_subobj_type: ?cetech1.StrId32) !cdb.TypeIdx {
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
