const std = @import("std");
const cetech1 = @import("cetech1");

pub const objectBufferContext = cetech1.strid.strId64("object_buffer_context");

pub const EditorObjBufferAPI = struct {
    openInBufferMenu: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, selection: cetech1.cdb.ObjId) anyerror!void,
    addToFirst: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) anyerror!void,
};
