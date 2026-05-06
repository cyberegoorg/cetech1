const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;

pub const objectBufferContext = cetech1.strId64("ct_object_buffer_context");

pub fn addToFirst(allocator: std.mem.Allocator, db: cdb.DbId, obj: coreui.SelectedObj) anyerror!void {
    return api.addToFirst(allocator, db, obj);
}

pub const EditorObjBufferAPI = struct {
    addToFirst: *const fn (allocator: std.mem.Allocator, db: cdb.DbId, obj: coreui.SelectedObj) anyerror!void,
};

pub var api: *const EditorObjBufferAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, EditorObjBufferAPI).?;
}
