const std = @import("std");

const apidb = @import("apidb.zig");
const cdb_private = @import("cdb.zig");

const cetech1 = @import("cetech1");
const public = cetech1.cdb_types;
const cdb = cetech1.cdb;

var _cdb = &cdb_private.api;

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // Color4f
        {
            const color_idx = try _cdb.addType(
                db,
                public.Color4f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Color4f.propIdx(.R), .name = "r", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4f.propIdx(.G), .name = "g", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4f.propIdx(.B), .name = "b", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4f.propIdx(.A), .name = "a", .type = cdb.PropType.F32 },
                },
            );

            const default_color = try _cdb.createObject(db, color_idx);
            const default_color_w = _cdb.writeObj(default_color).?;
            public.Color4f.setValue(f32, _cdb, default_color_w, .R, 1.0);
            public.Color4f.setValue(f32, _cdb, default_color_w, .G, 1.0);
            public.Color4f.setValue(f32, _cdb, default_color_w, .B, 1.0);
            public.Color4f.setValue(f32, _cdb, default_color_w, .A, 1.0);
            try _cdb.writeCommit(default_color_w);
            _cdb.setDefaultObject(default_color);
        }

        // value vec2
        {
            _ = try _cdb.addType(
                db,
                public.Vec2f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec2f.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec2f.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                },
            );
        }

        // value vec3
        {
            _ = try _cdb.addType(
                db,
                public.Vec3f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec3f.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3f.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3f.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }

        // value vec4
        {
            _ = try _cdb.addType(
                db,
                public.Vec4f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec4f.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.W), .name = "w", .type = cdb.PropType.F32 },
                },
            );
        }

        // Quatf
        {
            const quatf_idx = try _cdb.addType(
                db,
                public.Quatf.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Quatf.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Quatf.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Quatf.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Quatf.propIdx(.W), .name = "w", .type = cdb.PropType.F32 },
                },
            );

            const default_quat = try _cdb.createObject(db, quatf_idx);
            const default_quat_w = _cdb.writeObj(default_quat).?;
            public.Quatf.setValue(f32, _cdb, default_quat_w, .X, 0.0);
            public.Quatf.setValue(f32, _cdb, default_quat_w, .Y, 0.0);
            public.Quatf.setValue(f32, _cdb, default_quat_w, .Z, 0.0);
            public.Quatf.setValue(f32, _cdb, default_quat_w, .W, 1.0);
            try _cdb.writeCommit(default_quat_w);
            _cdb.setDefaultObject(default_quat);
        }

        // value i32
        {
            _ = try _cdb.addType(
                db,
                public.i32Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.i32Type.propIdx(.value), .name = "value", .type = .I32 },
                },
            );
        }

        // value u32
        {
            _ = try _cdb.addType(
                db,
                public.u32Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.u32Type.propIdx(.value), .name = "value", .type = .U32 },
                },
            );
        }

        // value f32
        {
            _ = try _cdb.addType(
                db,
                public.f32Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.f32Type.propIdx(.value), .name = "value", .type = .F32 },
                },
            );
        }

        // value i64
        {
            _ = try _cdb.addType(
                db,
                public.i64Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.i64Type.propIdx(.value), .name = "value", .type = .I64 },
                },
            );
        }

        // value u64
        {
            _ = try _cdb.addType(
                db,
                public.u64Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.u64Type.propIdx(.value), .name = "value", .type = .U64 },
                },
            );
        }

        // value f64
        {
            _ = try _cdb.addType(
                db,
                public.f64Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.f64Type.propIdx(.value), .name = "value", .type = .F64 },
                },
            );
        }

        // value bool
        {
            _ = try _cdb.addType(
                db,
                public.BoolType.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.BoolType.propIdx(.value), .name = "value", .type = .BOOL },
                },
            );
        }

        // string bool
        {
            _ = try _cdb.addType(
                db,
                public.StringType.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.StringType.propIdx(.value), .name = "value", .type = .STR },
                },
            );
        }
    }
});

pub fn registerToApi() !void {
    try apidb.api.implOrRemove(.cdb_types, cdb.CreateTypesI, &create_cdb_types_i, true);
}
