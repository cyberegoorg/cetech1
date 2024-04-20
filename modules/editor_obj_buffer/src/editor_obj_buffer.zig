const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

pub const objectBufferContext = cetech1.strid.strId64("ct_object_buffer_context");

pub const EditorObjBufferAPI = struct {
    addToFirst: *const fn (allocator: std.mem.Allocator, db: cdb.Db, obj: cdb.ObjId) anyerror!void,
};
