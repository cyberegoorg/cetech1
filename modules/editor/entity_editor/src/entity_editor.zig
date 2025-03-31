const std = @import("std");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const strid = cetech1.strid;
const ecs = cetech1.ecs;

const log = std.log.scoped(.editor_entity);

pub const EditorEntityAPI = struct {
    uiRemoteDebugMenuItems: *const fn (world: *ecs.World, allocator: std.mem.Allocator, port: ?u16) ?u16,
};
