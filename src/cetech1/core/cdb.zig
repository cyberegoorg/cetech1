const std = @import("std");
const strid = @import("strid.zig");
const uuid = @import("uuid.zig");

pub const OBJID_ZERO = ObjId{};
pub const ObjId = struct {
    id: u32 = 0,
    type_hash: strid.StrId32 = .{},

    pub fn isEmpty(self: *const ObjId) bool {
        return self.id == 0 and self.type_hash.id == 0;
    }
};

pub const Obj = anyopaque;
pub const Db = anyopaque;

pub const PropType = enum(u8) {
    NONE = 0,
    U64 = 1,
    I64 = 2,
    U32 = 3,
    I32 = 4,
    F32 = 5,
    F64 = 6,
    STR = 7,
    BLOB = 8,
    SUBOBJECT = 9,
    REFERENCE = 10,
    SUBOBJECT_SET = 11,
    REFERENCE_SET = 12,
};

pub const PropDef = struct {
    // Property name
    name: [:0]const u8,

    // Property type
    type: PropType,

    // Force type for ref/subobj base types
    type_hash: strid.StrId32 = .{},
};

pub inline fn propIdx(enum_: anytype) u32 {
    return @intFromEnum(enum_);
}

pub const CdbDb = struct {
    const Self = @This();

    pub fn fromDbT(db: *Db, dbapi: *CdbAPI) Self {
        return .{ .db = db, .dbapi = dbapi };
    }

    pub fn addType(self: *Self, name: []const u8, prop_def: []const PropDef) !strid.StrId32 {
        return self.dbapi.addTypeFn.?(self.db, name, prop_def);
    }

    pub fn getTypeName(self: *Self, type_hash: strid.StrId32) ?[]const u8 {
        return self.dbapi.getTypeNameFn.?(self.db, type_hash);
    }

    pub fn getTypePropDef(self: *Self, type_hash: strid.StrId32) ?[]const PropDef {
        return self.dbapi.getTypePropDefFn.?(self.db, type_hash);
    }

    pub fn addAspect(self: *Self, comptime T: type, type_hash: strid.StrId32, aspect_ptr: *T) !void {
        try self.dbapi.addAspectFn.?(self.db, type_hash, sanitizeApiName(T), aspect_ptr);
    }

    pub fn getAspect(self: *Self, comptime T: type, type_hash: strid.StrId32) ?*T {
        return @alignCast(@ptrCast(self.dbapi.getAspectFn.?(self.db, type_hash, strid.strId32(sanitizeApiName(T)))));
    }

    pub fn addPropertyAspect(self: *Self, comptime T: type, type_hash: strid.StrId32, prop_idx: u32, aspect_ptr: *T) !void {
        try self.dbapi.addPropertyAspectFn.?(self.db, type_hash, prop_idx, sanitizeApiName(T), aspect_ptr);
    }

    pub fn getPropertyAspect(self: *Self, comptime T: type, type_hash: strid.StrId32, prop_idx: u32) ?*T {
        return @alignCast(@ptrCast(self.dbapi.getPropertyAspectFn.?(self.db, type_hash, prop_idx, strid.strId32(sanitizeApiName(T)))));
    }

    pub fn getObjIdFromUuid(self: *Self, obj_uuid: uuid.Uuid) ?ObjId {
        return self.dbapi.getObjIdFromUuidFn.?(self.db, obj_uuid);
    }

    pub fn createObject(self: *Self, type_hash: strid.StrId32) anyerror!ObjId {
        return self.dbapi.createObjectFn.?(self.db, type_hash);
    }

    pub fn createObjectWithUuid(self: *Self, type_hash: strid.StrId32, with_uuid: uuid.Uuid) anyerror!ObjId {
        return self.dbapi.createObjectWithUuidFn.?(self.db, type_hash, with_uuid);
    }

    pub fn createObjectFromPrototype(self: *Self, prototype_obj: ObjId) anyerror!ObjId {
        return self.dbapi.createObjectFromPrototypeFn.?(self.db, prototype_obj);
    }

    pub fn cloneObject(self: *Self, obj: ObjId) anyerror!ObjId {
        return self.dbapi.createObjectFromPrototypeFn.?(self.db, obj);
    }

    pub fn getObjUuid(self: *Self, objid: ObjId) uuid.Uuid {
        return self.dbapi.getUuidFn.?(self.db, objid);
    }

    pub fn setDefaultObject(self: *Self, obj: ObjId) void {
        return self.dbapi.setDefaultObjectFn.?(self.db, obj);
    }

    pub fn destroyObject(self: *Self, obj: ObjId) void {
        return self.dbapi.destroyObjectFn.?(self.db, obj);
    }

    pub fn readObj(self: *Self, obj: ObjId) ?*Obj {
        return self.dbapi.readObjFn.?(self.db, obj);
    }

    pub fn writeObj(self: *Self, obj: ObjId) ?*Obj {
        return self.dbapi.writeObjFn.?(self.db, obj);
    }

    pub fn writeCommit(self: *Self, writer: *Obj) void {
        return self.dbapi.writeCommitFn.?(self.db, writer);
    }

    pub fn retargetWrite(self: *Self, writer: *Obj, obj: ObjId) void {
        return self.dbapi.retargetWriteFn.?(self.db, writer, obj);
    }

    pub fn readValue(self: *Self, comptime T: type, reader: *Obj, prop_idx: u32) T {
        var value_ptr = self.dbapi.readGenericFn.?(self.db, reader, prop_idx, getCDBTypeFromT(T));
        var typed_ptr: *const T = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    pub fn setValue(self: *Self, comptime T: type, writer: *Obj, prop_idx: u32, value: T) void {
        var value_ptr: [*]const u8 = @ptrCast(&value);
        self.dbapi.setGenericFn.?(self.db, writer, prop_idx, value_ptr, getCDBTypeFromT(T));
    }

    pub fn resetPropertyOveride(self: *Self, writer: *Obj, prop_idx: u32) void {
        return self.dbapi.resetPropertyOverideFn.?(self.db, writer, prop_idx);
    }

    pub fn isPropertyOverrided(self: *Self, obj: *Obj, prop_idx: u32) bool {
        return self.dbapi.isPropertyOverridedFn.?(self.db, obj, prop_idx);
    }

    pub fn instantiateSubObj(self: *Self, writer: *Obj, prop_idx: u32) !void {
        try self.dbapi.instantiateSubObjFn.?(self.db, writer, prop_idx);
    }

    pub fn getPrototype(self: *Self, obj: *Obj) ObjId {
        return self.dbapi.getPrototypeFn.?(self.db, obj);
    }

    pub fn setStr(self: *Self, writer: *Obj, prop_idx: u32, value: [:0]const u8) !void {
        return self.dbapi.setStrFn.?(self.db, writer, prop_idx, value);
    }

    pub fn readStr(self: *Self, reader: *Obj, prop_idx: u32) ?[:0]const u8 {
        var value_ptr = self.dbapi.readGenericFn.?(self.db, reader, prop_idx, PropType.STR);
        var typed_ptr: *const [:0]const u8 = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    pub fn setSubObj(self: *Self, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) !void {
        return self.dbapi.setSubObjFn.?(self.db, writer, prop_idx, subobj_writer);
    }

    pub fn readSubObj(self: *Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.dbapi.readSubObjFn.?(self.db, reader, prop_idx);
    }

    pub fn setRef(self: *Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        return self.dbapi.setRefFn.?(self.db, writer, prop_idx, value);
    }

    pub fn readRef(self: *Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.dbapi.readRefFn.?(self.db, reader, prop_idx);
    }

    pub fn readRefSet(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.dbapi.readRefSetFn.?(self.db, reader, prop_idx, allocator);
    }

    pub fn addRefToSet(self: *Self, writer: *Obj, prop_idx: u32, values: []const ObjId) !void {
        try self.dbapi.addRefToSetFn.?(self.db, writer, prop_idx, values);
    }

    pub fn removeFromRefSet(self: *Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        try self.dbapi.removeFromRefSetFn.?(self.db, writer, prop_idx, value);
    }

    pub fn addSubObjToSet(self: *Self, writer: *Obj, prop_idx: u32, subobj_writers: []const *Obj) !void {
        try self.dbapi.addSubObjToSetFn.?(self.db, writer, prop_idx, subobj_writers);
    }

    pub fn readSubObjSet(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const ObjId {
        return self.dbapi.readSubObjSetFn.?(self.db, reader, prop_idx, allocator);
    }

    pub fn removeFromSubObjSet(self: *Self, writer: *Obj, prop_idx: u32, sub_writer: *Obj) !void {
        try self.dbapi.removeFromSubObjSetFn.?(self.db, writer, prop_idx, sub_writer);
    }

    pub fn createBlob(self: *Self, writer: *Obj, prop_idx: u32, size: u8) anyerror!?[]u8 {
        return try self.dbapi.createBlobFn.?(self.db, writer, prop_idx, size);
    }
    pub fn readBlob(self: *Self, reader: *Obj, prop_idx: u32) []u8 {
        return self.dbapi.readBlobFn.?(self.db, reader, prop_idx);
    }

    pub fn gc(self: *Self, tmp_allocator: std.mem.Allocator) !void {
        return try self.dbapi.gcFn.?(self.db, tmp_allocator);
    }

    //TODO: temporary
    pub fn stressIt(self: *Self, type_hash: strid.StrId32, type_hash2: strid.StrId32, ref_obj1: ObjId) anyerror!void {
        try self.dbapi.stressItFn.?(self.db, type_hash, type_hash2, ref_obj1);
    }

    db: *Db,
    dbapi: *CdbAPI,
};

pub const CdbAPI = struct {
    const Self = @This();

    pub fn createDb(self: *Self, name: [:0]const u8) !CdbDb {
        return CdbDb.fromDbT(try self.createDbFn.?(name), self);
    }

    pub fn destroyDb(self: *Self, db: CdbDb) void {
        return self.destroyDbFn.?(db.db);
    }

    createDbFn: ?*const fn (name: [:0]const u8) anyerror!*Db,
    destroyDbFn: ?*const fn (db: *Db) void,

    // DB
    // Type operation
    addTypeFn: ?*const fn (db: *Db, name: []const u8, prop_def: []const PropDef) anyerror!strid.StrId32,
    getTypeNameFn: ?*const fn (db: *Db, type_hash: strid.StrId32) ?[]const u8,
    getTypePropDefFn: ?*const fn (db: *Db, type_hash: strid.StrId32) ?[]const PropDef,

    // Aspects
    addAspectFn: ?*const fn (db: *Db, type_hash: strid.StrId32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getAspectFn: ?*const fn (db: *Db, type_hash: strid.StrId32, aspect_hash: strid.StrId32) ?*anyopaque,

    addPropertyAspectFn: ?*const fn (db: *Db, type_hash: strid.StrId32, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getPropertyAspectFn: ?*const fn (db: *Db, type_hash: strid.StrId32, prop_idx: u32, aspect_hash: strid.StrId32) ?*anyopaque,

    getObjIdFromUuidFn: ?*const fn (db_: *Db, obj_uuid: uuid.Uuid) ?ObjId,

    // Object operation
    createObjectFn: ?*const fn (db: *Db, type_hash: strid.StrId32) anyerror!ObjId,
    createObjectWithUuidFn: ?*const fn (db: *Db, type_hash: strid.StrId32, with_uuid: uuid.Uuid) anyerror!ObjId,
    createObjectFromPrototypeFn: ?*const fn (db: *Db, prototype: ObjId) anyerror!ObjId,
    cloneObjectFn: ?*const fn (db: *Db, obj: ObjId) anyerror!ObjId,
    setDefaultObjectFn: ?*const fn (db: *Db, obj: ObjId) void,
    destroyObjectFn: ?*const fn (db: *Db, obj: ObjId) void,
    readObjFn: ?*const fn (db: *Db, obj: ObjId) ?*Obj,
    writeObjFn: ?*const fn (db: *Db, obj: ObjId) ?*Obj,
    writeCommitFn: ?*const fn (db: *Db, writer: *Obj) void,
    retargetWriteFn: ?*const fn (db_: *Db, writer: *Obj, obj: ObjId) void,
    getPrototypeFn: ?*const fn (db_: *Db, obj: *Obj) ObjId,
    getUuidFn: ?*const fn (db_: *Db, objid: ObjId) uuid.Uuid,

    // Object property operation
    resetPropertyOverideFn: ?*const fn (db_: *Db, writer: *Obj, prop_idx: u32) void,
    isPropertyOverridedFn: ?*const fn (db_: *Db, obj: *Obj, prop_idx: u32) bool,

    readGenericFn: ?*const fn (self: *Db, obj: *Obj, prop_idx: u32, prop_type: PropType) []const u8,
    setGenericFn: ?*const fn (self: *Db, obj: *Obj, prop_idx: u32, value: [*]const u8, prop_type: PropType) void,
    setStrFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, value: [:0]const u8) anyerror!void,

    readSubObjFn: ?*const fn (db: *Db, reader: *Obj, prop_idx: u32) ?ObjId,
    setSubObjFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    clearSubObjFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32) anyerror!void,
    instantiateSubObjFn: ?*const fn (db_: *Db, writer: *Obj, prop_idx: u32) anyerror!void,

    readRefFn: ?*const fn (db: *Db, reader: *Obj, prop_idx: u32) ?ObjId,
    setRefFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    clearRefFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32) anyerror!void,

    addRefToSetFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, values: []const ObjId) anyerror!void,
    removeFromRefSetFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    readRefSetFn: ?*const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,

    addSubObjToSetFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, subobjs_writer: []const *Obj) anyerror!void,
    removeFromSubObjSetFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    readSubObjSetFn: ?*const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,

    createBlobFn: ?*const fn (db: *Db, writer: *Obj, prop_idx: u32, size: u8) anyerror!?[]u8,
    readBlobFn: ?*const fn (db: *Db, reader: *Obj, prop_idx: u32) []u8,

    stressItFn: ?*const fn (db: *Db, type_hash: strid.StrId32, type_hash2: strid.StrId32, ref_obj1: ObjId) anyerror!void,

    gcFn: ?*const fn (db: *Db, tmp_allocator: std.mem.Allocator) anyerror!void,
};

// get type name and return only last name withou struct_ prefix for c structs.
fn sanitizeApiName(comptime T: type) []const u8 {
    const struct_len = "struct_".len;
    const type_str = @typeName(T);
    var name_iter = std.mem.splitBackwardsAny(u8, type_str, ".");
    const first = name_iter.first();
    const is_struct = std.mem.startsWith(u8, first, "struct_");
    const api_name = if (is_struct) first[struct_len..] else first;
    return api_name;
}

pub fn getCDBTypeFromT(comptime T: type) PropType {
    return switch (T) {
        i64 => PropType.I64,
        u64 => PropType.U64,
        i32 => PropType.I32,
        u32 => PropType.U32,
        f64 => PropType.F64,
        f32 => PropType.F32,
        ?[:0]const u8 => PropType.STR,
        ?[:0]u8 => PropType.STR,
        [:0]const u8 => PropType.STR,
        [:0]u8 => PropType.STR,
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    };
}

pub const BigTypeProps = enum(u32) {
    U64 = 0,
    I64,
    U32,
    I32,
    F32,
    F64,
    STR,
    BLOB,
    SUBOBJECT,
    REFERENCE,
    SUBOBJECT_SET,
    REFERENCE_SET,
};

pub fn addBigType(db: *CdbDb, name: []const u8) !strid.StrId32 {
    return db.addType(
        name,
        &.{
            .{ .name = "U64", .type = PropType.U64 },
            .{ .name = "I64", .type = PropType.I64 },
            .{ .name = "U32", .type = PropType.U32 },
            .{ .name = "I32", .type = PropType.I32 },
            .{ .name = "F32", .type = PropType.F32 },
            .{ .name = "F64", .type = PropType.F64 },
            .{ .name = "STR", .type = PropType.STR },
            .{ .name = "BLOB", .type = PropType.BLOB },
            .{ .name = "SUBOBJECT", .type = PropType.SUBOBJECT },
            .{ .name = "REFERENCE", .type = PropType.REFERENCE },
            .{ .name = "SUBOBJECT_SET", .type = PropType.SUBOBJECT_SET },
            .{ .name = "REFERENCE_SET", .type = PropType.REFERENCE_SET },
        },
    );
}
