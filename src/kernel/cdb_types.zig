const std = @import("std");

const apidb = cetech1.apidb;
const cdb_private = @import("cdb.zig");

const cetech1 = @import("cetech1");
const public = cetech1.cdb_types;
const cdb = cetech1.cdb;

var _cdb = &cdb;

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // Color4f
        {
            const color_idx = try cdb.addType(
                db,
                public.Color4fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Color4fCdb.propIdx(.R), .name = "r", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4fCdb.propIdx(.G), .name = "g", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4fCdb.propIdx(.B), .name = "b", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4fCdb.propIdx(.A), .name = "a", .type = cdb.PropType.F32 },
                },
            );

            const default_color = try cdb.createObject(db, color_idx);
            const default_color_w = cdb.writeObj(default_color).?;
            public.Color4fCdb.setValue(f32, default_color_w, .R, 1.0);
            public.Color4fCdb.setValue(f32, default_color_w, .G, 1.0);
            public.Color4fCdb.setValue(f32, default_color_w, .B, 1.0);
            public.Color4fCdb.setValue(f32, default_color_w, .A, 1.0);
            try cdb.writeCommit(default_color_w);
            cdb.setDefaultObject(default_color);
        }

        // Color3f
        {
            const color_idx = try cdb.addType(
                db,
                public.Color3fCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Color3fCdb.propIdx(.R), .name = "r", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color3fCdb.propIdx(.G), .name = "g", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Color3fCdb.propIdx(.B), .name = "b", .type = cdb.PropType.F32 },
                },
            );

            const default_color = try cdb.createObject(db, color_idx);
            const default_color_w = cdb.writeObj(default_color).?;
            public.Color3fCdb.setValue(f32, default_color_w, .R, 1.0);
            public.Color3fCdb.setValue(f32, default_color_w, .G, 1.0);
            public.Color3fCdb.setValue(f32, default_color_w, .B, 1.0);
            try cdb.writeCommit(default_color_w);
            cdb.setDefaultObject(default_color);
        }

        // Vec2f
        {
            _ = try cdb.addType(
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
            _ = try cdb.addType(
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
            _ = try cdb.addType(
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
            const quatf_idx = try cdb.addType(
                db,
                public.QuatfCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.QuatfCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.QuatfCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.QuatfCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.QuatfCdb.propIdx(.W), .name = "w", .type = cdb.PropType.F32 },
                },
            );

            const default_quat = try cdb.createObject(db, quatf_idx);
            const default_quat_w = cdb.writeObj(default_quat).?;
            public.QuatfCdb.setValue(f32, default_quat_w, .X, 0.0);
            public.QuatfCdb.setValue(f32, default_quat_w, .Y, 0.0);
            public.QuatfCdb.setValue(f32, default_quat_w, .Z, 0.0);
            public.QuatfCdb.setValue(f32, default_quat_w, .W, 1.0);
            try cdb.writeCommit(default_quat_w);
            cdb.setDefaultObject(default_quat);
        }

        // Position
        {
            _ = try cdb.addType(
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
            const scale_idx = try cdb.addType(
                db,
                public.ScaleCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.ScaleCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.ScaleCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.ScaleCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            const default_scale = try cdb.createObject(db, scale_idx);
            const default_scale_w = cdb.writeObj(default_scale).?;
            public.ScaleCdb.setValue(f32, default_scale_w, .X, 1.0);
            public.ScaleCdb.setValue(f32, default_scale_w, .Y, 1.0);
            public.ScaleCdb.setValue(f32, default_scale_w, .Z, 1.0);
            try cdb.writeCommit(default_scale_w);
            cdb.setDefaultObject(default_scale);
        }

        // Rotation
        {
            const rot_idx = try cdb.addType(
                db,
                public.RotationCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.RotationCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.RotationCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.RotationCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            const default_quat = try cdb.createObject(db, rot_idx);
            const default_quat_w = cdb.writeObj(default_quat).?;
            public.RotationCdb.setValue(f32, default_quat_w, .X, 0.0);
            public.RotationCdb.setValue(f32, default_quat_w, .Y, 0.0);
            public.RotationCdb.setValue(f32, default_quat_w, .Z, 0.0);
            try cdb.writeCommit(default_quat_w);
            cdb.setDefaultObject(default_quat);
        }

        // value i32
        {
            _ = try cdb.addType(
                db,
                public.I32TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.I32TypeCdb.propIdx(.Value), .name = "value", .type = .I32 },
                },
            );
        }

        // value u32
        {
            _ = try cdb.addType(
                db,
                public.U32TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.U32TypeCdb.propIdx(.Value), .name = "value", .type = .U32 },
                },
            );
        }

        // value f32
        {
            _ = try cdb.addType(
                db,
                public.F32TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.F32TypeCdb.propIdx(.Value), .name = "value", .type = .F32 },
                },
            );
        }

        // value i64
        {
            _ = try cdb.addType(
                db,
                public.I64TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.I64TypeCdb.propIdx(.Value), .name = "value", .type = .I64 },
                },
            );
        }

        // value u64
        {
            _ = try cdb.addType(
                db,
                public.U64TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.U64TypeCdb.propIdx(.Value), .name = "value", .type = .U64 },
                },
            );
        }

        // value f64
        {
            _ = try cdb.addType(
                db,
                public.F64TypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.F64TypeCdb.propIdx(.Value), .name = "value", .type = .F64 },
                },
            );
        }

        // value bool
        {
            _ = try cdb.addType(
                db,
                public.BoolTypeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.BoolTypeCdb.propIdx(.Value), .name = "value", .type = .BOOL },
                },
            );
        }

        // string bool
        {
            _ = try cdb.addType(
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
    try apidb.implOrRemove(.cdb_types, cdb.CreateTypesI, &create_cdb_types_i, true);
}
