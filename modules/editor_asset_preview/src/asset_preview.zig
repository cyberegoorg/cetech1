const std = @import("std");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const strid = cetech1.strid;
const ecs = cetech1.ecs;

pub const AssetPreviewAspectI = struct {
    pub const c_name = "ct_asset_preview_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    create_preview_entity: ?*const fn (
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        world: ecs.World,
    ) anyerror!ecs.EntityId = null,

    ui_preview: ?*const fn (
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) anyerror!void = null,

    pub fn implement(comptime T: type) AssetPreviewAspectI {
        const has_create_ent = std.meta.hasFn(T, "createPreviewEntity");
        const has_ui = std.meta.hasFn(T, "uiPreview");

        if (!has_create_ent and !has_ui) @compileError("implement me");
        return AssetPreviewAspectI{
            .create_preview_entity = if (has_create_ent) T.createPreviewEntity else null,
            .ui_preview = if (has_ui) T.uiPreview else null,
        };
    }
};
