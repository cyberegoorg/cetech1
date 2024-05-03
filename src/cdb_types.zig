const std = @import("std");

const apidb = @import("apidb.zig");
const cdb = @import("cdb.zig");

const cetech1 = @import("cetech1");
const public = cetech1.cdb_types;

// CDB
var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cetech1.cdb.Db) !void {

        // Color4f
        {
            const color_idx = try db.addType(
                public.Color4f.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.Color4f.propIdx(.R), .name = "r", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4f.propIdx(.G), .name = "g", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4f.propIdx(.B), .name = "b", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Color4f.propIdx(.A), .name = "a", .type = cetech1.cdb.PropType.F32 },
                },
            );

            const default_color = try db.createObject(color_idx);
            const default_color_w = db.writeObj(default_color).?;
            public.Color4f.setValue(db, f32, default_color_w, .R, 1.0);
            public.Color4f.setValue(db, f32, default_color_w, .G, 1.0);
            public.Color4f.setValue(db, f32, default_color_w, .B, 1.0);
            public.Color4f.setValue(db, f32, default_color_w, .A, 1.0);
            try db.writeCommit(default_color_w);
            db.setDefaultObject(default_color);
        }

        // value vec2
        {
            _ = try db.addType(
                public.Vec2f.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.Vec2f.propIdx(.X), .name = "x", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec2f.propIdx(.Y), .name = "y", .type = cetech1.cdb.PropType.F32 },
                },
            );
        }

        // value vec3
        {
            _ = try db.addType(
                public.Vec3f.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.Vec3f.propIdx(.X), .name = "x", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3f.propIdx(.Y), .name = "y", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3f.propIdx(.Z), .name = "z", .type = cetech1.cdb.PropType.F32 },
                },
            );
        }

        // value vec4
        {
            _ = try db.addType(
                public.Vec4f.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.Vec4f.propIdx(.X), .name = "x", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.Y), .name = "y", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.Z), .name = "z", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.W), .name = "w", .type = cetech1.cdb.PropType.F32 },
                },
            );
        }

        // Quatf
        {
            const quatf_idx = try db.addType(
                public.Quatf.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.Quatf.propIdx(.X), .name = "x", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Quatf.propIdx(.Y), .name = "y", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Quatf.propIdx(.Z), .name = "z", .type = cetech1.cdb.PropType.F32 },
                    .{ .prop_idx = public.Quatf.propIdx(.W), .name = "w", .type = cetech1.cdb.PropType.F32 },
                },
            );

            const default_quat = try db.createObject(quatf_idx);
            const default_quat_w = db.writeObj(default_quat).?;
            public.Quatf.setValue(db, f32, default_quat_w, .X, 0.0);
            public.Quatf.setValue(db, f32, default_quat_w, .Y, 0.0);
            public.Quatf.setValue(db, f32, default_quat_w, .Z, 0.0);
            public.Quatf.setValue(db, f32, default_quat_w, .W, 1.0);
            try db.writeCommit(default_quat_w);
            db.setDefaultObject(default_quat);
        }

        // value i32
        {
            _ = try db.addType(
                public.i32Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.i32Type.propIdx(.value), .name = "value", .type = .I32 },
                },
            );
        }

        // value u32
        {
            _ = try db.addType(
                public.u32Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.u32Type.propIdx(.value), .name = "value", .type = .U32 },
                },
            );
        }

        // value f32
        {
            _ = try db.addType(
                public.f32Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.f32Type.propIdx(.value), .name = "value", .type = .F32 },
                },
            );
        }

        // value i64
        {
            _ = try db.addType(
                public.i64Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.i64Type.propIdx(.value), .name = "value", .type = .I64 },
                },
            );
        }

        // value u64
        {
            _ = try db.addType(
                public.u64Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.u64Type.propIdx(.value), .name = "value", .type = .U64 },
                },
            );
        }

        // value f64
        {
            _ = try db.addType(
                public.f64Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.f64Type.propIdx(.value), .name = "value", .type = .F64 },
                },
            );
        }

        // value bool
        {
            _ = try db.addType(
                public.BoolType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.BoolType.propIdx(.value), .name = "value", .type = .BOOL },
                },
            );
        }

        // string bool
        {
            _ = try db.addType(
                public.StringType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.StringType.propIdx(.value), .name = "value", .type = .STR },
                },
            );
        }
    }
});

pub fn registerToApi() !void {
    try apidb.api.implOrRemove(.cdb_types, cetech1.cdb.CreateTypesI, &create_cdb_types_i, true);
}
