const std = @import("std");
const strid = @import("strid.zig");
const uuid = @import("uuid.zig");
const c = @import("c.zig").c;

pub const OBJID_ZERO = ObjId{};

/// Object id
pub const ObjId = extern struct {
    id: u32 = 0,
    type_hash: strid.StrId32 = .{},

    pub fn isEmpty(self: *const ObjId) bool {
        return self.id == 0 and self.type_hash.id == 0;
    }

    pub fn eq(a: ObjId, b: ObjId) bool {
        return a.id == b.id and a.type_hash.id == b.type_hash.id;
    }

    pub fn toU64(self: *const ObjId) u64 {
        const ptr: *u64 = @ptrFromInt(@intFromPtr(self));
        return ptr.*;
    }
};

/// Opaqueue Object used for read/write operation
pub const Obj = anyopaque;

/// Opaqueue Db type
pub const Db = anyopaque;

/// Supported types
pub const PropType = enum(u8) {
    /// Invalid
    NONE = 0,

    /// bool
    BOOL = 1,

    /// u64
    U64 = 2,

    /// i64
    I64 = 3,

    /// u32
    U32 = 4,

    /// i32
    I32 = 5,

    /// i32
    F32 = 6,

    /// i32
    F64 = 7,

    /// String. String are copy on set.
    STR = 8,

    /// []u8
    /// Size is defined on createBlob
    BLOB = 9,

    /// Subobject is object owned by object where is property defined
    SUBOBJECT = 10,

    /// Only reference to object
    REFERENCE = 11,

    /// Set of subobjects
    SUBOBJECT_SET = 12,

    /// Set of references
    REFERENCE_SET = 13,
};

/// Definiton of one property.
pub const PropDef = struct {
    /// Property index from enum.
    /// Only for assert enum==idx.
    prop_idx: u64 = 0,

    /// Property name
    name: [:0]const u8,

    /// Property type
    type: PropType,

    /// Force type for ref/subobj base types
    type_hash: strid.StrId32 = .{},
};

pub const CreateTypesI = extern struct {
    pub const c_name = "ct_cdb_create_types_i";
    pub const name_hash = strid.strId64(@This().c_name);

    create_types: *const fn (db: *Db) callconv(.C) void,

    pub inline fn implement(comptime T: type) CreateTypesI {
        if (!std.meta.hasFn(T, "createTypes")) @compileError("implement me");

        return CreateTypesI{
            .create_types = struct {
                pub fn f(main_db: *Db) callconv(.C) void {
                    T.createTypes(main_db) catch undefined;
                }
            }.f,
        };
    }
};

/// Helper for using enum as property.
/// Do not use. Use typed api CdbTypeDecl instead.
pub inline fn propIdx(enum_: anytype) u32 {
    return @intFromEnum(enum_);
}

/// Callback that call in GC phase and give you array of objid that is destoyed.
pub const OnObjIdDestroyed = *const fn (db: *Db, objects: []ObjId) void;

/// Helper that create CDB type info and TypedAPI when you can use prop enum.
/// This make typed helper for read/write operation where you can use property enum and not idx.
/// For method without docs see docs in CdbDb object.
/// This not register type cdb. For type register use addType function on DB.
pub fn CdbTypeDecl(comptime type_name: [:0]const u8, comptime props_enum: type) type {
    return struct {
        const Self = @This();

        pub const name = type_name;
        pub const type_hash = strid.strId32(type_name);
        pub const PropsEnum = props_enum;

        pub fn isSameType(obj: ObjId) bool {
            return obj.type_hash.id == type_hash.id;
        }

        pub fn propIdx(prop: PropsEnum) u32 {
            return @intFromEnum(prop);
        }

        pub fn addAspect(db: *CdbDb, comptime T: type, aspect_ptr: *T) !void {
            try db.addAspect(T, type_hash, aspect_ptr);
        }

        pub fn getAspect(db: *CdbDb, comptime T: type) ?*T {
            return db.getAspect(T, type_hash);
        }

        pub fn addPropertyAspect(db: *CdbDb, comptime T: type, prop: PropsEnum, aspect_ptr: *T) !void {
            try db.addPropertyAspect(T, type_hash, Self.propIdx(prop), aspect_ptr);
        }

        pub fn getPropertyAspect(db: *CdbDb, comptime T: type, prop: PropsEnum) ?*T {
            try db.getPropertyAspect(T, type_hash, Self.propIdx(prop));
        }

        pub fn createObject(db: *CdbDb) !ObjId {
            return db.createObject(type_hash);
        }

        pub fn read(db: *CdbDb, obj: ObjId) ?*Obj {
            return db.readObj(obj);
        }

        pub fn write(db: *CdbDb, obj: ObjId) ?*Obj {
            return db.writeObj(obj);
        }

        pub fn commit(db: *CdbDb, writer: *Obj) !void {
            return db.writeCommit(writer);
        }

        pub fn readValue(db: *CdbDb, comptime T: type, reader: *Obj, prop: PropsEnum) T {
            return db.readValue(T, reader, Self.propIdx(prop));
        }

        pub fn setValue(db: *CdbDb, comptime T: type, writer: *Obj, prop: PropsEnum, value: T) void {
            db.setValue(T, writer, Self.propIdx(prop), value);
        }

        pub fn setStr(db: *CdbDb, writer: *Obj, prop: PropsEnum, value: [:0]const u8) !void {
            return db.setStr(writer, Self.propIdx(prop), value);
        }

        pub fn readStr(db: *CdbDb, reader: *Obj, prop: PropsEnum) ?[:0]const u8 {
            return db.readStr(reader, Self.propIdx(prop));
        }
        pub fn setSubObj(db: *CdbDb, writer: *Obj, prop: PropsEnum, subobj_writer: *Obj) !void {
            try db.setSubObj(writer, Self.propIdx(prop), subobj_writer);
        }

        pub fn readSubObj(db: *CdbDb, reader: *Obj, prop: PropsEnum) ?ObjId {
            return db.readSubObj(reader, Self.propIdx(prop));
        }

        pub fn setRef(db: *CdbDb, writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            return db.setRef(writer, Self.propIdx(prop), value);
        }

        pub fn readRef(db: *CdbDb, reader: *Obj, prop: PropsEnum) ?ObjId {
            return db.readRef(reader, Self.propIdx(prop));
        }

        pub fn readRefSet(db: *CdbDb, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return db.readRefSet(reader, Self.propIdx(prop), allocator);
        }

        pub fn readRefSetAdded(db: *CdbDb, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return db.readRefSetAdded(reader, Self.propIdx(prop), allocator);
        }

        pub fn readRefSetRemoved(db: *CdbDb, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return db.readRefSetRemoved(reader, Self.propIdx(prop), allocator);
        }

        pub fn readSubObjSetAdded(db: *CdbDb, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) !?[]const ObjId {
            return db.readSubObjSetAdded(reader, Self.propIdx(prop), allocator);
        }

        pub fn readSubObjSetRemoved(db: *CdbDb, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return db.readSubObjSetRemoved(reader, Self.propIdx(prop), allocator);
        }

        pub fn addRefToSet(db: *CdbDb, writer: *Obj, prop: PropsEnum, values: []const ObjId) !void {
            try db.addRefToSet(writer, Self.propIdx(prop), values);
        }

        pub fn removeFromRefSet(db: *CdbDb, writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            try db.removeFromRefSet(writer, Self.propIdx(prop), value);
        }

        pub fn addSubObjToSet(db: *CdbDb, writer: *Obj, prop: PropsEnum, subobj_writers: []const *Obj) !void {
            try db.addSubObjToSet(writer, Self.propIdx(prop), subobj_writers);
        }

        pub fn readSubObjSet(db: *CdbDb, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) !?[]const ObjId {
            return db.readSubObjSet(reader, Self.propIdx(prop), allocator);
        }

        pub fn removeFromSubObjSet(db: *CdbDb, writer: *Obj, prop: PropsEnum, sub_writer: *Obj) !void {
            try db.removeFromSubObjSet(writer, Self.propIdx(prop), sub_writer);
        }

        pub fn createBlob(db: *CdbDb, writer: *Obj, prop: PropsEnum, size: usize) anyerror!?[]u8 {
            return try db.createBlob(writer, Self.propIdx(prop), size);
        }
        pub fn readBlob(db: *CdbDb, reader: *Obj, prop: PropsEnum) []u8 {
            return db.readBlob(reader, Self.propIdx(prop));
        }

        pub fn isInSet(db: *CdbDb, reader: *Obj, prop: PropsEnum, item_ibj: ObjId) bool {
            return db.isInSet(reader, Self.propIdx(prop), item_ibj);
        }
    };
}

/// Database object.
pub const CdbDb = struct {
    const Self = @This();

    pub fn fromDbT(db: *Db, dbapi: *CdbAPI) Self {
        return Self{ .db = db, .cdbapi = dbapi };
    }

    /// Create new cdb type.
    pub fn addType(self: *Self, name: []const u8, prop_def: []const PropDef) !strid.StrId32 {
        return self.cdbapi.addTypeFn(self.db, name, prop_def);
    }

    /// Get type name from type hash.
    pub fn getTypeName(self: *Self, type_hash: strid.StrId32) ?[]const u8 {
        return self.cdbapi.getTypeNameFn(self.db, type_hash);
    }

    /// Get type definition for type hash.
    pub fn getTypePropDef(self: *Self, type_hash: strid.StrId32) ?[]const PropDef {
        return self.cdbapi.getTypePropDefFn(self.db, type_hash);
    }

    /// Get property definition for type hash and property name.
    pub fn getTypePropDefIdx(self: *Self, type_hash: strid.StrId32, prop_name: []const u8) ?u32 {
        return self.cdbapi.getTypePropDefIdxFn(self.db, type_hash, prop_name);
    }

    /// Add aspect to type.
    pub fn addAspect(self: *Self, comptime T: type, type_hash: strid.StrId32, aspect_ptr: *T) !void {
        try self.cdbapi.addAspectFn(self.db, type_hash, T.c_name, aspect_ptr);
    }

    /// Get type aspect.
    pub fn getAspect(self: *Self, comptime T: type, type_hash: strid.StrId32) ?*T {
        return @alignCast(@ptrCast(self.cdbapi.getAspectFn(self.db, type_hash, T.name_hash)));
    }

    /// Add aspect to property.
    pub fn addPropertyAspect(self: *Self, comptime T: type, type_hash: strid.StrId32, prop_idx: u32, aspect_ptr: *T) !void {
        try self.cdbapi.addPropertyAspectFn(self.db, type_hash, prop_idx, T.c_name, aspect_ptr);
    }

    /// Get aspect for property.
    pub fn getPropertyAspect(self: *Self, comptime T: type, type_hash: strid.StrId32, prop_idx: u32) ?*T {
        return @alignCast(@ptrCast(self.cdbapi.getPropertyAspectFn(self.db, type_hash, prop_idx, T.name_hash)));
    }

    /// Create object for type hash
    pub fn createObject(self: *Self, type_hash: strid.StrId32) anyerror!ObjId {
        return self.cdbapi.createObjectFn(self.db, type_hash);
    }

    /// Create object as instance of prototype obj.
    pub fn createObjectFromPrototype(self: *Self, prototype_obj: ObjId) anyerror!ObjId {
        return self.cdbapi.createObjectFromPrototypeFn(self.db, prototype_obj);
    }

    /// Clone object
    pub fn cloneObject(self: *Self, obj: ObjId) anyerror!ObjId {
        return self.cdbapi.cloneObjectFn(self.db, obj);
    }

    // Destroy object
    pub fn destroyObject(self: *Self, obj: ObjId) void {
        return self.cdbapi.destroyObjectFn(self.db, obj);
    }

    /// Set default object
    pub fn setDefaultObject(self: *Self, obj: ObjId) void {
        return self.cdbapi.setDefaultObjectFn(self.db, obj);
    }

    /// Get object reader.
    /// Reader is valid until GC.
    pub fn readObj(self: *Self, obj: ObjId) ?*Obj {
        return self.cdbapi.readObjFn(self.db, obj);
    }

    /// Get object writer.
    pub fn writeObj(self: *Self, obj: ObjId) ?*Obj {
        return self.cdbapi.writeObjFn(self.db, obj);
    }

    /// Commit writer changes
    pub fn writeCommit(self: *Self, writer: *Obj) !void {
        return self.cdbapi.writeCommitFn(self.db, writer);
    }

    /// Retarget writer to another objid. Still need call commit
    pub fn retargetWrite(self: *Self, writer: *Obj, obj: ObjId) !void {
        return self.cdbapi.retargetWriteFn(self.db, writer, obj);
    }

    /// Read property value for basic types.
    pub fn readValue(self: *Self, comptime T: type, reader: *Obj, prop_idx: u32) T {
        const value_ptr = self.cdbapi.readGenericFn(self.db, reader, prop_idx, getCDBTypeFromT(T));
        const typed_ptr: *const T = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    /// Set property value for basic types.
    pub fn setValue(self: *Self, comptime T: type, writer: *Obj, prop_idx: u32, value: T) void {
        const value_ptr: [*]const u8 = @ptrCast(&value);
        self.cdbapi.setGenericFn(self.db, writer, prop_idx, value_ptr, getCDBTypeFromT(T));
    }

    /// Reset property overide flag.
    /// Valid for object that is instance of another object.
    pub fn resetPropertyOveride(self: *Self, writer: *Obj, prop_idx: u32) void {
        return self.cdbapi.resetPropertyOverideFn(self.db, writer, prop_idx);
    }

    /// Is property overided.
    /// Valid for object that is instance of another object.
    pub fn isPropertyOverrided(self: *Self, obj: *Obj, prop_idx: u32) bool {
        return self.cdbapi.isPropertyOverridedFn(self.db, obj, prop_idx);
    }

    /// Instantiate subobject from prorotype property.
    /// Make new object from subobject protoype, set property.
    /// Valid for object that is instance of another object.
    pub fn instantiateSubObj(self: *Self, writer: *Obj, prop_idx: u32) !void {
        try self.cdbapi.instantiateSubObjFn(self.db, writer, prop_idx);
    }

    /// Instantiate subobject from prorotype property in set.
    /// Make new object from subobject protoype, set property.
    /// Valid for object that is instance of another object.
    pub fn instantiateSubObjFromSet(self: *Self, writer: *Obj, prop_idx: u32, obj_set: ObjId) !ObjId {
        return self.cdbapi.instantiateSubObjFromSetFn(self.db, writer, prop_idx, obj_set);
    }

    /// Get object prototype.
    pub fn getPrototype(self: *Self, obj: *Obj) ObjId {
        return self.cdbapi.getPrototypeFn(self.db, obj);
    }

    /// Set string property
    pub fn setStr(self: *Self, writer: *Obj, prop_idx: u32, value: [:0]const u8) !void {
        return self.cdbapi.setStrFn(self.db, writer, prop_idx, value);
    }

    /// Read string property
    pub fn readStr(self: *Self, reader: *Obj, prop_idx: u32) ?[:0]const u8 {
        const value_ptr = self.cdbapi.readGenericFn(self.db, reader, prop_idx, PropType.STR);
        const typed_ptr: *const [:0]const u8 = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    /// Set sub object property
    pub fn setSubObj(self: *Self, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) !void {
        return self.cdbapi.setSubObjFn(self.db, writer, prop_idx, subobj_writer);
    }

    /// Read sub object property
    pub fn readSubObj(self: *Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.cdbapi.readSubObjFn(self.db, reader, prop_idx);
    }

    /// Set reference  property
    pub fn setRef(self: *Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        return self.cdbapi.setRefFn(self.db, writer, prop_idx, value);
    }

    /// Get reference property
    pub fn readRef(self: *Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.cdbapi.readRefFn(self.db, reader, prop_idx);
    }

    /// Clear reference
    pub fn clearRef(self: *Self, writer: *Obj, prop_idx: u32) !void {
        return self.cdbapi.clearRefFn(self.db, writer, prop_idx);
    }

    /// Clear subobject (This destroy subobject if exist).
    pub fn clearSubObj(self: *Self, writer: *Obj, prop_idx: u32) !void {
        return self.cdbapi.clearSubObjFn(self.db, writer, prop_idx);
    }

    /// Read reference set.
    /// This make new array for result set.
    /// Caller own the memory.
    pub fn readRefSet(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.cdbapi.readRefSetFn(self.db, reader, prop_idx, allocator);
    }

    /// Read reference set but only added to this property and not for all inheret from prototype.
    /// This make new array for result set.
    /// Caller own the memory.
    pub fn readRefSetAdded(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.cdbapi.readRefSetAddedFn(self.db, reader, prop_idx, allocator);
    }

    /// Read reference set but only removed from this property and not for all inheret from prototype.
    /// This make new array for result set.
    /// Caller own the memory.
    pub fn readRefSetRemoved(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.cdbapi.readRefSetRemovedFn(self.db, reader, prop_idx, allocator);
    }

    /// Read subobj set but only added to this property and not for all inheret from prototype.
    /// This make new array for result set.
    /// Caller own the memory.
    pub fn readSubObjSetAdded(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const ObjId {
        return self.cdbapi.readSubObjSetAddedFn(self.db, reader, prop_idx, allocator);
    }

    /// Read subobj set but only removed to this property and not for all inheret from prototype.
    /// This make new array for result set.
    /// Caller own the memory.
    pub fn readSubObjSetRemoved(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.cdbapi.readSubObjSetRemovedFn(self.db, reader, prop_idx, allocator);
    }

    /// Add reference to set..
    pub fn addRefToSet(self: *Self, writer: *Obj, prop_idx: u32, values: []const ObjId) !void {
        try self.cdbapi.addRefToSetFn(self.db, writer, prop_idx, values);
    }

    /// Remove reference from set
    pub fn removeFromRefSet(self: *Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        try self.cdbapi.removeFromRefSetFn(self.db, writer, prop_idx, value);
    }

    /// Add subobj to set
    pub fn addSubObjToSet(self: *Self, writer: *Obj, prop_idx: u32, subobj_writers: []const *Obj) !void {
        try self.cdbapi.addSubObjToSetFn(self.db, writer, prop_idx, subobj_writers);
    }

    /// Read subibj set.
    /// This make new array for result set.
    /// Caller own the memory.
    pub fn readSubObjSet(self: *Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const ObjId {
        return self.cdbapi.readSubObjSetFn(self.db, reader, prop_idx, allocator);
    }

    /// Remove from subobj set
    pub fn removeFromSubObjSet(self: *Self, writer: *Obj, prop_idx: u32, sub_writer: *Obj) !void {
        try self.cdbapi.removeFromSubObjSetFn(self.db, writer, prop_idx, sub_writer);
    }

    /// Create new blob for property.
    pub fn createBlob(self: *Self, writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8 {
        return try self.cdbapi.createBlobFn(self.db, writer, prop_idx, size);
    }

    /// Get blob for property
    pub fn readBlob(self: *Self, reader: *Obj, prop_idx: u32) []u8 {
        return self.cdbapi.readBlobFn(self.db, reader, prop_idx);
    }

    // Do GC work.
    // This destroy object and reader pointer are invalid to use after this.
    pub fn gc(self: *Self, tmp_allocator: std.mem.Allocator) !void {
        return try self.cdbapi.gcFn(self.db, tmp_allocator);
    }

    // Get all object that referenece this obj.
    // Caller own the memory.
    pub fn getReferencerSet(self: *Self, obj: ObjId, tmp_allocator: std.mem.Allocator) ![]ObjId {
        return try self.cdbapi.getReferencerSetFn(self.db, obj, tmp_allocator);
    }

    // Get object parent.
    pub fn getParent(self: *Self, obj: ObjId) ObjId {
        return self.cdbapi.getParentFn(self.db, obj);
    }

    // Add callback that call in GC phase on destroyed objids.
    pub fn addOnObjIdDestroyed(self: *Self, fce: OnObjIdDestroyed) !void {
        try self.cdbapi.addOnObjIdDestroyedFn(self.db, fce);
    }

    // Remove callback.
    pub fn removeOnObjIdDestroyed(self: *Self, fce: OnObjIdDestroyed) void {
        self.cdbapi.removeOnObjIdDestroyedFn(self.db, fce);
    }

    // Get object version.
    // Version is counter increment if obj is changed or any subobj or prototype is changed.
    pub fn getVersion(self: *Self, obj: ObjId) u64 {
        return self.cdbapi.getVersionFn(self.db, obj);
    }

    //TODO: temporary
    pub fn stressIt(self: *Self, type_hash: strid.StrId32, type_hash2: strid.StrId32, ref_obj1: ObjId) anyerror!void {
        try self.cdbapi.stressItFn(self.db, type_hash, type_hash2, ref_obj1);
    }

    pub fn isIinisiated(self: *Self, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool {
        return self.cdbapi.isIinisiatedFn(self.db, obj, set_prop_idx, inisiated_obj);
    }

    pub fn canIinisiated(self: *Self, obj: *Obj, inisiated_obj: *Obj) bool {
        return self.cdbapi.canIinisiateFn(self.db, obj, inisiated_obj);
    }

    pub fn restoreDeletedInSet(self: *Self, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void {
        return self.cdbapi.restoreDeletedInSetFn(self.db, obj, set_prop_idx, inisiated_obj);
    }

    pub fn isInSet(self: *Self, reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool {
        return self.cdbapi.isInSetFn(self.db, reader, prop_idx, item_ibj);
    }

    pub fn setPrototype(self: *Self, obj: ObjId, prototype: ObjId) !void {
        return self.cdbapi.setPrototypeFn(self.db, obj, prototype);
    }

    pub fn getDefaultObject(self: *Self, type_hash: strid.StrId32) ?ObjId {
        return self.cdbapi.getDefaultObjectFn(self.db, type_hash);
    }

    pub fn getFirstObject(self: *Self, type_hash: strid.StrId32) ?ObjId {
        return self.cdbapi.getFirstObjectFn(self.db, type_hash);
    }

    pub fn getAllObjectByType(self: *Self, allocator: std.mem.Allocator, type_hash: strid.StrId32) ?[]ObjId {
        return self.cdbapi.getAllObjectByTypeFn(self.db, allocator, type_hash);
    }

    pub fn hasTypeSet(self: *Self, type_hash: strid.StrId32) bool {
        return self.cdbapi.hasTypeSetFn(self.db, type_hash);
    }

    pub fn hasTypeSubobject(self: *Self, type_hash: strid.StrId32) bool {
        return self.cdbapi.hasTypeSubobjectFn(self.db, type_hash);
    }

    db: *Db,
    cdbapi: *CdbAPI,
};

/// Main CDB API
/// CDB is in-memory oriented typed-object-with-props based DB.
/// Object id defined as type with properties.
/// Write clone object and swap it on commit.
/// Reader is not disturbed if object is changed because reader are valid until GC phase.
/// You should create object from another object as prototype and overide some properties.
/// Change on prototypes are visible in instances on not overided properties.
/// Type and properties should have named aspect interface as generic way to do some crazy shit like custom UI etc..
pub const CdbAPI = struct {
    const Self = @This();

    /// Create new database.
    pub fn createDb(self: *Self, name: [:0]const u8) !CdbDb {
        return CdbDb.fromDbT(try self.createDbFn(name), self);
    }

    /// Destroy and free database.
    pub fn destroyDb(self: *Self, db: CdbDb) void {
        return self.destroyDbFn(db.db);
    }

    //#region Pointers to implementation.
    // DB
    createDbFn: *const fn (name: [:0]const u8) anyerror!*Db,
    destroyDbFn: *const fn (db: *Db) void,

    // Type operation
    addTypeFn: *const fn (db: *Db, name: []const u8, prop_def: []const PropDef) anyerror!strid.StrId32,
    getTypeNameFn: *const fn (db: *Db, type_hash: strid.StrId32) ?[]const u8,
    getTypePropDefFn: *const fn (db: *Db, type_hash: strid.StrId32) ?[]const PropDef,
    getTypePropDefIdxFn: *const fn (db: *Db, type_hash: strid.StrId32, prop_name: []const u8) ?u32,

    // Aspects
    addAspectFn: *const fn (db: *Db, type_hash: strid.StrId32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getAspectFn: *const fn (db: *Db, type_hash: strid.StrId32, aspect_hash: strid.StrId32) ?*anyopaque,

    addPropertyAspectFn: *const fn (db: *Db, type_hash: strid.StrId32, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getPropertyAspectFn: *const fn (db: *Db, type_hash: strid.StrId32, prop_idx: u32, aspect_hash: strid.StrId32) ?*anyopaque,

    addOnObjIdDestroyedFn: *const fn (db: *Db, fce: OnObjIdDestroyed) anyerror!void,
    removeOnObjIdDestroyedFn: *const fn (db: *Db, fce: OnObjIdDestroyed) void,

    // Object operation
    createObjectFn: *const fn (db: *Db, type_hash: strid.StrId32) anyerror!ObjId,
    createObjectFromPrototypeFn: *const fn (db: *Db, prototype: ObjId) anyerror!ObjId,
    cloneObjectFn: *const fn (db: *Db, obj: ObjId) anyerror!ObjId,
    setDefaultObjectFn: *const fn (db: *Db, obj: ObjId) void,
    destroyObjectFn: *const fn (db: *Db, obj: ObjId) void,
    readObjFn: *const fn (db: *Db, obj: ObjId) ?*Obj,
    writeObjFn: *const fn (db: *Db, obj: ObjId) ?*Obj,
    writeCommitFn: *const fn (db: *Db, writer: *Obj) anyerror!void,
    retargetWriteFn: *const fn (db_: *Db, writer: *Obj, obj: ObjId) anyerror!void,
    getPrototypeFn: *const fn (db_: *Db, obj: *Obj) ObjId,
    getParentFn: *const fn (db_: *Db, obj: ObjId) ObjId,
    getVersionFn: *const fn (db_: *Db, obj: ObjId) u64,
    getReferencerSetFn: *const fn (db_: *Db, obj: ObjId, allocator: std.mem.Allocator) anyerror![]ObjId,
    getDefaultObjectFn: *const fn (db: *Db, type_hash: strid.StrId32) ?ObjId,
    setPrototypeFn: *const fn (db: *Db, obj: ObjId, prototype: ObjId) anyerror!void,
    getFirstObjectFn: *const fn (db_: *Db, type_hash: strid.StrId32) ObjId,
    getAllObjectByTypeFn: *const fn (db_: *Db, tmp_allocator: std.mem.Allocator, type_hash: strid.StrId32) ?[]ObjId,

    // Object property operation
    resetPropertyOverideFn: *const fn (db_: *Db, writer: *Obj, prop_idx: u32) void,
    isPropertyOverridedFn: *const fn (db_: *Db, obj: *Obj, prop_idx: u32) bool,
    isIinisiatedFn: *const fn (db_: *Db, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool,
    canIinisiateFn: *const fn (db_: *Db, obj: *Obj, inisiated_obj: *Obj) bool,
    restoreDeletedInSetFn: *const fn (db_: *Db, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void,

    readGenericFn: *const fn (self: *Db, obj: *Obj, prop_idx: u32, prop_type: PropType) []const u8,
    setGenericFn: *const fn (self: *Db, obj: *Obj, prop_idx: u32, value: [*]const u8, prop_type: PropType) void,
    setStrFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, value: [:0]const u8) anyerror!void,

    readSubObjFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32) ?ObjId,
    setSubObjFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    clearSubObjFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32) anyerror!void,
    instantiateSubObjFn: *const fn (db_: *Db, writer: *Obj, prop_idx: u32) anyerror!void,
    instantiateSubObjFromSetFn: *const fn (db_: *Db, writer: *Obj, prop_idx: u32, obj_set: ObjId) anyerror!ObjId,
    isInSetFn: *const fn (db_: *Db, reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool,

    readRefFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32) ?ObjId,
    setRefFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    clearRefFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32) anyerror!void,

    addRefToSetFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, values: []const ObjId) anyerror!void,
    removeFromRefSetFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    readRefSetFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,
    readRefSetAddedFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,
    readRefSetRemovedFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,

    addSubObjToSetFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, subobjs_writer: []const *Obj) anyerror!void,
    removeFromSubObjSetFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    readSubObjSetFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,
    readSubObjSetAddedFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,
    readSubObjSetRemovedFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,

    createBlobFn: *const fn (db: *Db, writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8,
    readBlobFn: *const fn (db: *Db, reader: *Obj, prop_idx: u32) []u8,

    stressItFn: *const fn (db: *Db, type_hash: strid.StrId32, type_hash2: strid.StrId32, ref_obj1: ObjId) anyerror!void,

    gcFn: *const fn (db: *Db, tmp_allocator: std.mem.Allocator) anyerror!void,
    dump: *const fn (db: *Db) anyerror!void,

    hasTypeSetFn: *const fn (db: *Db, type_hash: strid.StrId32) bool,
    hasTypeSubobjectFn: *const fn (db: *Db, type_hash: strid.StrId32) bool,
    //#endregion
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

/// Return CDB prop type from native type.
pub fn getCDBTypeFromT(comptime T: type) PropType {
    return switch (T) {
        bool => PropType.BOOL,
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
