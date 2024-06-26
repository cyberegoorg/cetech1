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
    }
});

pub fn registerToApi() !void {
    try apidb.api.implOrRemove(.cdb_types, cetech1.cdb.CreateTypesI, &create_cdb_types_i, true);
}
