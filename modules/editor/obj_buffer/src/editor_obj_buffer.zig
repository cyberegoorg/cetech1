const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;

pub const objectBufferContext = cetech1.strid.strId64("ct_object_buffer_context");

pub const EditorObjBufferAPI = struct {
    addToFirst: *const fn (allocator: std.mem.Allocator, db: cdb.DbId, obj: coreui.SelectionItem) anyerror!void,
};
