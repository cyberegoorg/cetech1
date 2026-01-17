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
                public.Color4fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Color4fCdb.propIdx(.R), .name = "r", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4fCdb.propIdx(.G), .name = "g", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4fCdb.propIdx(.B), .name = "b", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4fCdb.propIdx(.A), .name = "a", .type = cdb.PropType.F32 },
                },
            );

            const default_color = try _cdb.createObject(db, color_idx);
            const default_color_w = _cdb.writeObj(default_color).?;
            public.Color4fCdb.setValue(f32, _cdb, default_color_w, .R, 1.0);
            public.Color4fCdb.setValue(f32, _cdb, default_color_w, .G, 1.0);
            public.Color4fCdb.setValue(f32, _cdb, default_color_w, .B, 1.0);
            public.Color4fCdb.setValue(f32, _cdb, default_color_w, .A, 1.0);
            try _cdb.writeCommit(default_color_w);
            _cdb.setDefaultObject(default_color);
        }

        // Color3f
        {
            const color_idx = try _cdb.addType(
                db,
                public.Color3fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Color3fCdb.propIdx(.R), .name = "r", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color3fCdb.propIdx(.G), .name = "g", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color3fCdb.propIdx(.B), .name = "b", .type = cdb.PropType.F32 },
                },
            );

            const default_color = try _cdb.createObject(db, color_idx);
            const default_color_w = _cdb.writeObj(default_color).?;
            public.Color3fCdb.setValue(f32, _cdb, default_color_w, .R, 1.0);
            public.Color3fCdb.setValue(f32, _cdb, default_color_w, .G, 1.0);
            public.Color3fCdb.setValue(f32, _cdb, default_color_w, .B, 1.0);
            try _cdb.writeCommit(default_color_w);
            _cdb.setDefaultObject(default_color);
        }

        // Vec2f
        {
            _ = try _cdb.addType(
                db,
                public.Vec2fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec2fCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec2fCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                },
            );
        }

        // Vec3f
        {
            _ = try _cdb.addType(
                db,
                public.Vec3fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec3fCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3fCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3fCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }

        // Vec4f
        {
            _ = try _cdb.addType(
                db,
                public.Vec4fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec4fCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4fCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4fCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4fCdb.propIdx(.W), .name = "w", .type = cdb.PropType.F32 },
                },
            );
        }

        // Quatf
        {
            const quatf_idx = try _cdb.addType(
                db,
                public.QuatfCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.QuatfCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.QuatfCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.QuatfCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.QuatfCdb.propIdx(.W), .name = "w", .type = cdb.PropType.F32 },
                },
            );

            const default_quat = try _cdb.createObject(db, quatf_idx);
            const default_quat_w = _cdb.writeObj(default_quat).?;
            public.QuatfCdb.setValue(f32, _cdb, default_quat_w, .X, 0.0);
            public.QuatfCdb.setValue(f32, _cdb, default_quat_w, .Y, 0.0);
            public.QuatfCdb.setValue(f32, _cdb, default_quat_w, .Z, 0.0);
            public.QuatfCdb.setValue(f32, _cdb, default_quat_w, .W, 1.0);
            try _cdb.writeCommit(default_quat_w);
            _cdb.setDefaultObject(default_quat);
        }

        // Position
        {
            _ = try _cdb.addType(
                db,
                public.PositionCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.PositionCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.PositionCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.PositionCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }

        // Scale
        {
            const scale_idx = try _cdb.addType(
                db,
                public.ScaleCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.ScaleCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.ScaleCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.ScaleCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            const default_scale = try _cdb.createObject(db, scale_idx);
            const default_scale_w = _cdb.writeObj(default_scale).?;
            public.ScaleCdb.setValue(f32, _cdb, default_scale_w, .X, 1.0);
            public.ScaleCdb.setValue(f32, _cdb, default_scale_w, .Y, 1.0);
            public.ScaleCdb.setValue(f32, _cdb, default_scale_w, .Z, 1.0);
            try _cdb.writeCommit(default_scale_w);
            _cdb.setDefaultObject(default_scale);
        }

        // Rotation
        {
            const rot_idx = try _cdb.addType(
                db,
                public.RotationCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.RotationCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.RotationCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.RotationCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            const default_quat = try _cdb.createObject(db, rot_idx);
            const default_quat_w = _cdb.writeObj(default_quat).?;
            public.RotationCdb.setValue(f32, _cdb, default_quat_w, .X, 0.0);
            public.RotationCdb.setValue(f32, _cdb, default_quat_w, .Y, 0.0);
            public.RotationCdb.setValue(f32, _cdb, default_quat_w, .Z, 0.0);
            try _cdb.writeCommit(default_quat_w);
            _cdb.setDefaultObject(default_quat);
        }

        // value i32
        {
            _ = try _cdb.addType(
                db,
                public.i32TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.i32TypeCdb.propIdx(.Value), .name = "value", .type = .I32 },
                },
            );
        }

        // value u32
        {
            _ = try _cdb.addType(
                db,
                public.u32TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.u32TypeCdb.propIdx(.Value), .name = "value", .type = .U32 },
                },
            );
        }

        // value f32
        {
            _ = try _cdb.addType(
                db,
                public.f32TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.f32TypeCdb.propIdx(.Value), .name = "value", .type = .F32 },
                },
            );
        }

        // value i64
        {
            _ = try _cdb.addType(
                db,
                public.i64TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.i64TypeCdb.propIdx(.Value), .name = "value", .type = .I64 },
                },
            );
        }

        // value u64
        {
            _ = try _cdb.addType(
                db,
                public.u64TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.u64TypeCdb.propIdx(.Value), .name = "value", .type = .U64 },
                },
            );
        }

        // value f64
        {
            _ = try _cdb.addType(
                db,
                public.f64TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.f64TypeCdb.propIdx(.Value), .name = "value", .type = .F64 },
                },
            );
        }

        // value bool
        {
            _ = try _cdb.addType(
                db,
                public.BoolTypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.BoolTypeCdb.propIdx(.Value), .name = "value", .type = .BOOL },
                },
            );
        }

        // string bool
        {
            _ = try _cdb.addType(
                db,
                public.StringTypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.StringTypeCdb.propIdx(.Value), .name = "value", .type = .STR },
                },
            );
        }
    }
});

pub fn registerToApi() !void {
    try apidb.api.implOrRemove(.cdb_types, cdb.CreateTypesI, &create_cdb_types_i, true);
}
