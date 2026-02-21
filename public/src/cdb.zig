/// Main CDB API
/// CDB is in-memory oriented typed-object-with-props based DB.
/// Object id defined as type with properties.
/// Write clone object and swap it on commit.
/// Reader is not disturbed if object is changed because reader are valid until GC phase.
/// You should create object from another object as prototype and overide some properties.
/// Change on prototypes are visible in instances on not overided properties.
/// Type and properties should have named aspect interface as generic way to do some crazy shit like custom UI etc..
const std = @import("std");
const cetech1 = @import("root.zig");
const uuid = @import("uuid.zig");
const apidb = cetech1.apidb;

const log = std.log.scoped(.assetdb);

const M = @This();

pub const ObjVersion = u64;
pub const TypeHash = cetech1.StrId32;

pub const ObjIdList = cetech1.ArrayList(ObjId);

/// Type idx
pub const TypeIdx = packed struct(u16) {
    idx: u16 = 0,

    pub fn isEmpty(self: *const TypeIdx) bool {
        return self.idx == 0;
    }

    pub fn eql(a: TypeIdx, b: TypeIdx) bool {
        return a.idx == b.idx;
    }
};

/// DB id
pub const DbId = packed struct(u16) {
    idx: u16 = 0,

    pub fn isEmpty(self: *const DbId) bool {
        return self.idx == 0;
    }

    pub fn eql(a: DbId, b: DbId) bool {
        return a.idx == b.idx;
    }
};

pub const ObjIdGen = u8;

/// Object id
pub const ObjId = packed struct(u64) {
    id: u24 = 0,
    gen: ObjIdGen = 0,
    type_idx: TypeIdx = .{},
    db: DbId = .{},

    pub fn isEmpty(self: *const ObjId) bool {
        return self.id == 0 and self.gen == 0 and self.type_idx.isEmpty();
    }

    pub fn eql(a: ObjId, b: ObjId) bool {
        return a.id == b.id and a.gen == b.gen and a.type_idx.eql(b.type_idx) and a.db.eql(b.db);
    }

    pub fn format(self: ObjId, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) (@TypeOf(writer).Error)!void {
        try std.fmt.format(writer, "{d}:{d}-{d}-{d}", .{ self.id, self.gen, self.type_idx.idx, self.db.idx });
    }

    pub fn toU64(self: ObjId) u64 {
        return @bitCast(self);
    }

    pub fn toI64(self: ObjId) i64 {
        return @bitCast(self);
    }

    pub fn fromU64(value: u64) ObjId {
        return @bitCast(value);
    }
};

/// Object type version
pub const TypeVersion = u32;

/// Change object result
pub const ChangedObjects = struct {
    need_fullscan: bool,
    last_version: TypeVersion,
    objects: []ObjId,
};

/// Opaqueue Object used for read/write operation
pub const Obj = anyopaque;

/// Supported types
pub const PropType = enum(u8) {
    /// Invalid
    invalid = 0,

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
    type_hash: TypeHash = .{},
};

pub const ObjRelation = enum {
    Owned,
    NotOwned, //TODO: remove with explicit isChild call
    Inheried,
    Overide,
    Inisiated,
};

pub const CreateTypesI = struct {
    pub const c_name = "ct_cdb_create_cdbtypes_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    create_types: *const fn (db: DbId) void,

    pub inline fn implement(comptime T: type) CreateTypesI {
        return CreateTypesI{
            .create_types = struct {
                pub fn f(main_db: DbId) void {
                    T.createTypes(main_db) catch |err| {
                        log.err("CreateTypesI.createTypes failed with error {}", .{err});
                    };
                }
            }.f,
        };
    }
};

pub const PostCreateTypesI = struct {
    pub const c_name = "ct_cdb_post_create_cdbtypes_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    post_create_types: *const fn (db: DbId) anyerror!void,

    pub inline fn implement(comptime T: type) PostCreateTypesI {
        return PostCreateTypesI{
            .post_create_types = T.postCreateTypes,
        };
    }
};

/// Helper for using enum as property.
/// Do not use. Use typed api CdbTypeDecl instead.
pub inline fn propIdx(enum_: anytype) u32 {
    return @intFromEnum(enum_);
}

/// Callback that call in GC phase and give you array of objid that is destoyed.
pub const OnObjIdDestroyed = *const fn (db: DbId, objects: []ObjId) void;

/// Helper that create CDB type info and TypedAPI when you can use prop enum.
/// This make typed helper for read/write operation where you can use property enum and not idx.
/// For method without docs see docs in DbId object.
/// This not register type cdb. For type register use addType function on DB.
pub fn CdbTypeDecl(comptime type_name: [:0]const u8, comptime props_enum: type, comptime extend: type) type {
    return struct {
        const Self = @This();

        pub const f = extend;

        pub const name = type_name;
        pub const type_hash = cetech1.strId32(type_name);
        pub const PropsEnum = props_enum;

        pub inline fn propIdx(prop: PropsEnum) u32 {
            return @intFromEnum(prop);
        }

        pub inline fn typeIdx(db: DbId) TypeIdx {
            return M.getTypeIdx(db, Self.type_hash).?;
        }

        pub inline fn addAspect(comptime T: type, db: DbId, aspect_ptr: *T) !void {
            try M.addAspect(T, db, M.getTypeIdx(db, Self.type_hash).?, aspect_ptr);
        }

        pub inline fn getAspect(comptime T: type, db: DbId) ?*T {
            return M.getAspect(T, db, M.getTypeIdx(db, Self.type_hash).?);
        }

        pub inline fn addPropertyAspect(comptime T: type, db: DbId, prop: PropsEnum, aspect_ptr: *T) !void {
            try M.addPropertyAspect(T, db, M.getTypeIdx(db, Self.type_hash).?, Self.propIdx(prop), aspect_ptr);
        }

        pub inline fn getPropertyAspect(comptime T: type, db: DbId, prop: PropsEnum) ?*T {
            try M.getPropertyAspect(T, db, M.getTypeIdx(db, Self.type_hash).?, Self.propIdx(prop));
        }

        pub inline fn createObject(db: DbId) !ObjId {
            return M.createObject(db, M.getTypeIdx(db, Self.type_hash).?);
        }

        pub inline fn destroyObject(obj: ObjId) void {
            return M.destroyObject(obj);
        }

        pub inline fn write(obj: ObjId) ?*Obj {
            return M.writeObj(obj);
        }

        pub inline fn commit(writer: *Obj) !void {
            return M.writeCommit(writer);
        }

        pub inline fn setValue(comptime T: type, writer: *Obj, prop: PropsEnum, value: T) void {
            M.setValue(T, writer, Self.propIdx(prop), value);
        }

        pub inline fn setStr(writer: *Obj, prop: PropsEnum, value: [:0]const u8) !void {
            return M.setStr(writer, Self.propIdx(prop), value);
        }

        pub inline fn setSubObj(writer: *Obj, prop: PropsEnum, subobj_writer: *Obj) !void {
            try M.setSubObj(writer, Self.propIdx(prop), subobj_writer);
        }

        pub inline fn read(obj: ObjId) ?*Obj {
            return M.readObj(obj);
        }

        pub inline fn readValue(comptime T: type, reader: *Obj, prop: PropsEnum) T {
            return M.readValue(T, reader, Self.propIdx(prop));
        }

        pub inline fn readStr(reader: *Obj, prop: PropsEnum) ?[:0]const u8 {
            return M.readStr(reader, Self.propIdx(prop));
        }

        pub inline fn readStrEnum(comptime T: type, reader: *Obj, prop: PropsEnum, default_value: T) T {
            const type_str = M.readStr(reader, Self.propIdx(prop)) orelse "";
            return std.meta.stringToEnum(T, type_str) orelse default_value;
        }

        pub inline fn readSubObj(reader: *Obj, prop: PropsEnum) ?ObjId {
            return M.readSubObj(reader, Self.propIdx(prop));
        }

        pub inline fn readRef(reader: *Obj, prop: PropsEnum) ?ObjId {
            return M.readRef(reader, Self.propIdx(prop));
        }

        pub inline fn readRefSet(reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return M.readRefSet(reader, Self.propIdx(prop), allocator);
        }

        pub inline fn readRefSetAdded(reader: *Obj, prop: PropsEnum) []const ObjId {
            return M.readRefSetAdded(reader, Self.propIdx(prop));
        }

        pub inline fn readRefSetRemoved(reader: *Obj, prop: PropsEnum) []const ObjId {
            return M.readRefSetRemoved(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSetAdded(reader: *Obj, prop: PropsEnum) []const ObjId {
            return M.readSubObjSetAdded(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSetRemoved(reader: *Obj, prop: PropsEnum) []const ObjId {
            return M.readSubObjSetRemoved(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSet(reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) !?[]ObjId {
            return M.readSubObjSet(reader, Self.propIdx(prop), allocator);
        }

        pub inline fn readBlob(reader: *Obj, prop: PropsEnum) []u8 {
            return M.readBlob(reader, Self.propIdx(prop));
        }

        pub inline fn isInSet(reader: *Obj, prop: PropsEnum, item_ibj: ObjId) bool {
            return M.isInSet(reader, Self.propIdx(prop), item_ibj);
        }

        pub inline fn removeFromSubObjSet(writer: *Obj, prop: PropsEnum, sub_writer: *Obj) !void {
            try M.removeFromSubObjSet(writer, Self.propIdx(prop), sub_writer);
        }

        pub inline fn createBlob(writer: *Obj, prop: PropsEnum, size: usize) anyerror!?[]u8 {
            return try M.createBlob(writer, Self.propIdx(prop), size);
        }

        pub inline fn setRef(writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            return M.setRef(writer, Self.propIdx(prop), value);
        }

        pub inline fn addRefToSet(writer: *Obj, prop: PropsEnum, values: []const ObjId) !void {
            try M.addRefToSet(writer, Self.propIdx(prop), values);
        }

        pub inline fn removeFromRefSet(writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            try M.removeFromRefSet(writer, Self.propIdx(prop), value);
        }

        pub inline fn addSubObjToSet(writer: *Obj, prop: PropsEnum, subobj_writers: []const *Obj) !void {
            try M.addSubObjToSet(writer, Self.propIdx(prop), subobj_writers);
        }
    };
}

/// Create new database.
pub inline fn createDb(name: [:0]const u8) !DbId {
    return try api.createDb(name);
}

/// Destroy and free database.
pub inline fn destroyDb(db: DbId) void {
    return api.destroyDb(db);
}

/// Get object writer.
pub inline fn writeObj(obj: ObjId) ?*Obj {
    return api.writeObj(obj);
}

/// Commit writer changes
pub inline fn writeCommit(writer: *Obj) !void {
    return api.writeCommit(writer);
}

/// Retarget writer to another objid. Still need call commit
pub inline fn retargetWrite(writer: *Obj, obj: ObjId) !void {
    return api.retargetWrite(writer, obj);
}

/// Set property value for basic types.
pub inline fn setValue(comptime T: type, writer: *Obj, prop_idx: u32, value: T) void {
    const value_ptr: [*]const u8 = @ptrCast(&value);
    api.setGeneric(writer, prop_idx, value_ptr, getCDBTypeFromT(T));
}

/// Reset property overide flag.
/// Valid for object that is instance of another object.
pub inline fn resetPropertyOveride(writer: *Obj, prop_idx: u32) void {
    return api.resetPropertyOveride(writer, prop_idx);
}

/// Instantiate subobject from prorotype property.
/// Make new object from subobject protoype, set property.
/// Valid for object that is instance of another object.
pub inline fn instantiateSubObj(writer: *Obj, prop_idx: u32) !ObjId {
    return api.instantiateSubObj(writer, prop_idx);
}

/// Instantiate subobject from prorotype property in set.
/// Make new object from subobject protoype, set property.
/// Valid for object that is instance of another object.
pub inline fn instantiateSubObjFromSet(writer: *Obj, prop_idx: u32, obj_set: ObjId) !ObjId {
    return api.instantiateSubObjFromSet(writer, prop_idx, obj_set);
}

/// Set string property
pub inline fn setStr(writer: *Obj, prop_idx: u32, value: [:0]const u8) !void {
    return api.setStr(writer, prop_idx, value);
}

/// Set sub object property
pub inline fn setSubObj(writer: *Obj, prop_idx: u32, subobj_writer: *Obj) !void {
    return api.setSubObj(writer, prop_idx, subobj_writer);
}

/// Set reference  property
pub inline fn setRef(writer: *Obj, prop_idx: u32, value: ObjId) !void {
    return api.setRef(writer, prop_idx, value);
}

/// Clear reference
pub inline fn clearRef(writer: *Obj, prop_idx: u32) !void {
    return api.clearRef(writer, prop_idx);
}

/// Clear subobject (This destroy subobject if exist).
pub inline fn clearSubObj(writer: *Obj, prop_idx: u32) !void {
    return api.clearSubObj(writer, prop_idx);
}

/// Add reference to set..
pub inline fn addRefToSet(writer: *Obj, prop_idx: u32, values: []const ObjId) !void {
    try api.addRefToSet(writer, prop_idx, values);
}

/// Remove reference from set
pub inline fn removeFromRefSet(writer: *Obj, prop_idx: u32, value: ObjId) !void {
    try api.removeFromRefSet(writer, prop_idx, value);
}

/// Add subobj to set
pub inline fn addSubObjToSet(writer: *Obj, prop_idx: u32, subobj_writers: []const *Obj) !void {
    try api.addSubObjToSet(writer, prop_idx, subobj_writers);
}

/// Remove from subobj set
pub inline fn removeFromSubObjSet(writer: *Obj, prop_idx: u32, sub_writer: *Obj) !void {
    try api.removeFromSubObjSet(writer, prop_idx, sub_writer);
}

/// Create new blob for property.
pub inline fn createBlob(writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8 {
    return try api.createBlob(writer, prop_idx, size);
}

pub inline fn restoreDeletedInSet(obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void {
    return api.restoreDeletedInSet(obj, set_prop_idx, inisiated_obj);
}

pub inline fn setPrototype(obj: ObjId, prototype: ObjId) !void {
    return api.setPrototype(obj, prototype);
}

/// Get object reader.
/// Reader is valid until GC.
pub inline fn readObj(obj: ObjId) ?*Obj {
    return api.readObj(obj);
}

/// Read property value for basic types.
pub inline fn readValue(comptime T: type, reader: *Obj, prop_idx: u32) T {
    const value_ptr = api.readGeneric(reader, prop_idx, getCDBTypeFromT(T));
    const typed_ptr: *const T = @ptrCast(@alignCast(value_ptr.ptr));
    return typed_ptr.*;
}

/// Is property overided.
/// Valid for object that is instance of another object.
pub inline fn isPropertyOverrided(obj: *Obj, prop_idx: u32) bool {
    return api.isPropertyOverrided(obj, prop_idx);
}

/// Get object prototype.
pub inline fn getPrototype(obj: *Obj) ObjId {
    return api.getPrototype(obj);
}

/// Read string property
pub inline fn readStr(reader: *Obj, prop_idx: u32) ?[:0]const u8 {
    return api.readStr(reader, prop_idx);
}

/// Read sub object property
pub inline fn readSubObj(reader: *Obj, prop_idx: u32) ?ObjId {
    return api.readSubObj(reader, prop_idx);
}

/// Get reference property
pub inline fn readRef(reader: *Obj, prop_idx: u32) ?ObjId {
    return api.readRef(reader, prop_idx);
}

/// Read reference set.
/// This make new array for result set.
/// Caller own the memory.
pub inline fn readRefSet(reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]ObjId {
    return api.readRefSet(reader, prop_idx, allocator);
}

/// Read reference set but only added to this property and not for all inheret from prototype.
/// This make new array for result set.
pub inline fn readRefSetAdded(reader: *Obj, prop_idx: u32) []const ObjId {
    return api.readRefSetAdded(reader, prop_idx);
}

/// Read reference set but only removed from this property and not for all inheret from prototype.
/// This make new array for result set.
pub inline fn readRefSetRemoved(reader: *Obj, prop_idx: u32) []const ObjId {
    return api.readRefSetRemoved(reader, prop_idx);
}

/// Read subobj set but only added to this property and not for all inheret from prototype.
/// This make new array for result set.
pub inline fn readSubObjSetAdded(reader: *Obj, prop_idx: u32) []const ObjId {
    return api.readSubObjSetAdded(reader, prop_idx);
}

/// Read subobj set but only removed to this property and not for all inheret from prototype.
/// This make new array for result set.
pub inline fn readSubObjSetRemoved(reader: *Obj, prop_idx: u32) []const ObjId {
    return api.readSubObjSetRemoved(reader, prop_idx);
}

/// Read subibj set.
/// This make new array for result set.
/// Caller own the memory.
pub inline fn readSubObjSet(reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]ObjId {
    return api.readSubObjSet(reader, prop_idx, allocator);
}

/// Get blob for property
pub inline fn readBlob(reader: *Obj, prop_idx: u32) []u8 {
    return api.readBlob(reader, prop_idx);
}

pub inline fn isIinisiated(obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool {
    return api.isIinisiated(obj, set_prop_idx, inisiated_obj);
}

pub inline fn canIinisiated(obj: *Obj, inisiated_obj: *Obj) bool {
    return api.canIinisiate(obj, inisiated_obj);
}

pub inline fn isInSet(reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool {
    return api.isInSet(reader, prop_idx, item_ibj);
}

pub inline fn getDbFromObjid(obj: ObjId) DbId {
    return api.getDbFromObjid(obj);
}

pub inline fn getDbFromObj(obj: *Obj) DbId {
    return api.getDbFromObj(obj);
}

// Get all object that referenece this obj.
// Caller own the memory.
pub inline fn getReferencerSet(allocator: std.mem.Allocator, obj: ObjId) ![]ObjId {
    return try api.getReferencerSet(allocator, obj);
}

// Get object parent.
pub inline fn getParent(obj: ObjId) ObjId {
    return api.getParent(obj);
}

// Get object version.
// Version is counter increment if obj is changed or any subobj or prototype is changed.
pub inline fn getVersion(obj: ObjId) ObjVersion {
    return api.getVersion(obj);
}

pub inline fn isAlive(obj: ObjId) bool {
    return api.isAlive(obj);
}

pub inline fn getRelation(top_level_obj: ObjId, obj: ObjId, prop_idx: u32, in_set_obj: ?ObjId) ObjRelation {
    return api.getRelation(top_level_obj, obj, prop_idx, in_set_obj);
}

pub inline fn inisitateDeep(allocator: std.mem.Allocator, last_parent: ObjId, to_inisiated_obj: ObjId) ?ObjId {
    return api.inisitateDeep(allocator, last_parent, to_inisiated_obj);
}

pub inline fn isChildOff(parent_obj: ObjId, child_obj: ObjId) bool {
    return api.isChildOff(parent_obj, child_obj);
}

/// Create object as instance of prototype obj.
pub inline fn createObjectFromPrototype(prototype_obj: ObjId) anyerror!ObjId {
    return api.createObjectFromPrototype(prototype_obj);
}

/// Clone object
pub inline fn cloneObject(obj: ObjId) anyerror!ObjId {
    return api.cloneObject(obj);
}

// Destroy object
pub inline fn destroyObject(obj: ObjId) void {
    return api.destroyObject(obj);
}

/// Set default object
pub inline fn setDefaultObject(obj: ObjId) void {
    return api.setDefaultObject(obj);
}

pub inline fn dump(db: DbId) !void {
    return api.dump(db);
}

// Do GC work.
// This destroy object and reader pointer are invalid to use after this.
pub inline fn gc(allocator: std.mem.Allocator, db: DbId) !void {
    return try api.gc(db, allocator);
}

/// Create object for type hash (create default object if exist)
pub inline fn createObject(db: DbId, type_idx: TypeIdx) anyerror!ObjId {
    return api.createObject(db, type_idx);
}

/// Create object for type hash (ignore empty object if exist)
pub inline fn createEmptyObject(db: DbId, type_idx: TypeIdx) anyerror!ObjId {
    return api.createEmptyObject(db, type_idx);
}

// For performance reason cache typeidx
pub inline fn getTypeIdx(db: DbId, type_hash: TypeHash) ?TypeIdx {
    return api.getTypeIdx(db, type_hash);
}

/// Add aspect to type.
pub inline fn addAspect(comptime T: type, db: DbId, type_idx: TypeIdx, aspect_ptr: *T) !void {
    try api.addAspect(db, type_idx, T.c_name, aspect_ptr);
}

/// Get type aspect.
pub inline fn getAspect(comptime T: type, db: DbId, type_idx: TypeIdx) ?*T {
    return @ptrCast(@alignCast(api.getAspect(db, type_idx, T.name_hash)));
}

/// Add aspect to property.
pub inline fn addPropertyAspect(comptime T: type, db: DbId, type_idx: TypeIdx, prop_idx: u32, aspect_ptr: *T) !void {
    try api.addPropertyAspect(db, type_idx, prop_idx, T.c_name, aspect_ptr);
}

/// Get aspect for property.
pub inline fn getPropertyAspect(comptime T: type, db: DbId, type_idx: TypeIdx, prop_idx: u32) ?*T {
    return @ptrCast(@alignCast(api.getPropertyAspect(db, type_idx, prop_idx, T.name_hash)));
}

pub inline fn hasTypeSet(db: DbId, type_idx: TypeIdx) bool {
    return api.hasTypeSet(db, type_idx);
}

pub inline fn hasTypeSubobject(db: DbId, type_idx: TypeIdx) bool {
    return api.hasTypeSubobject(db, type_idx);
}

pub inline fn getTypeHash(db: DbId, type_idx: TypeIdx) ?TypeHash {
    return api.getTypeHash(db, type_idx);
}

pub inline fn getChangeObjects(allocator: std.mem.Allocator, db: DbId, type_idx: TypeIdx, since_version: TypeVersion) !ChangedObjects {
    return api.getChangeObjects(db, allocator, type_idx, since_version);
}

pub inline fn getDefaultObject(db: DbId, type_idx: TypeIdx) ?ObjId {
    return api.getDefaultObject(db, type_idx);
}

pub inline fn getFirstObject(db: DbId, type_idx: TypeIdx) ?ObjId {
    return api.getFirstObject(db, type_idx);
}

pub inline fn getAllObjectByType(allocator: std.mem.Allocator, db: DbId, type_idx: TypeIdx) ?[]ObjId {
    return api.getAllObjectByType(db, allocator, type_idx);
}

// Add callback that call in GC phase on destroyed objids.
pub inline fn addOnObjIdDestroyed(db: DbId, fce: OnObjIdDestroyed) !void {
    try api.addOnObjIdDestroyed(db, fce);
}

// Remove callback.
pub inline fn removeOnObjIdDestroyed(db: DbId, fce: OnObjIdDestroyed) void {
    api.removeOnObjIdDestroyed(db, fce);
}

//TODO: temporary
pub inline fn stressIt(db: DbId, type_idx: TypeIdx, type_idx2: TypeIdx, ref_obj1: ObjId) anyerror!void {
    try api.stressIt(db, type_idx, type_idx2, ref_obj1);
}

/// Create new cdb type.
pub inline fn addType(db: DbId, name: []const u8, prop_def: []const PropDef) !TypeIdx {
    return api.addType(db, name, prop_def);
}

/// Get type name from type hash.
pub inline fn getTypeName(db: DbId, type_idx: TypeIdx) ?[]const u8 {
    return api.getTypeName(db, type_idx);
}

/// Get type definition for type hash.
pub inline fn getTypePropDef(db: DbId, type_idx: TypeIdx) ?[]const PropDef {
    return api.getTypePropDef(db, type_idx);
}

/// Get property definition for type hash and property name.
pub inline fn getTypePropDefIdx(db: DbId, type_idx: TypeIdx, prop_name: []const u8) ?u32 {
    return api.getTypePropDefIdx(db, type_idx, prop_name);
}

pub const CdbAPI = struct {
    createDb: *const fn (name: [:0]const u8) anyerror!DbId,
    destroyDb: *const fn (db: DbId) void,
    getDbFromObjid: *const fn (obj: ObjId) DbId,
    getDbFromObj: *const fn (obj: *Obj) DbId,
    setPrototype: *const fn (obj: ObjId, prototype: ObjId) anyerror!void,
    writeObj: *const fn (obj: ObjId) ?*Obj,
    writeCommit: *const fn (writer: *Obj) anyerror!void,
    retargetWrite: *const fn (writer: *Obj, obj: ObjId) anyerror!void,
    resetPropertyOveride: *const fn (writer: *Obj, prop_idx: u32) void,
    restoreDeletedInSet: *const fn (writer: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void,
    setGeneric: *const fn (writer: *Obj, prop_idx: u32, value: [*]const u8, prop_type: PropType) void,
    setStr: *const fn (writer: *Obj, prop_idx: u32, value: [:0]const u8) anyerror!void,
    setSubObj: *const fn (writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    clearSubObj: *const fn (writer: *Obj, prop_idx: u32) anyerror!void,
    instantiateSubObj: *const fn (writer: *Obj, prop_idx: u32) anyerror!ObjId,
    instantiateSubObjFromSet: *const fn (writer: *Obj, prop_idx: u32, obj_set: ObjId) anyerror!ObjId,
    setRef: *const fn (writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    clearRef: *const fn (writer: *Obj, prop_idx: u32) anyerror!void,
    addRefToSet: *const fn (writer: *Obj, prop_idx: u32, values: []const ObjId) anyerror!void,
    removeFromRefSet: *const fn (writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    addSubObjToSet: *const fn (writer: *Obj, prop_idx: u32, subobjs_writer: []const *Obj) anyerror!void,
    removeFromSubObjSet: *const fn (writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    createBlob: *const fn (writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8,
    readObj: *const fn (obj: ObjId) ?*Obj,
    readStr: *const fn (reader: *Obj, prop_idx: u32) ?[:0]const u8,
    readGeneric: *const fn (reader: *Obj, prop_idx: u32, prop_type: PropType) []const u8,
    isPropertyOverrided: *const fn (reader: *Obj, prop_idx: u32) bool,
    isIinisiated: *const fn (reader: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool,
    canIinisiate: *const fn (reader: *Obj, inisiated_obj: *Obj) bool,
    readSubObj: *const fn (reader: *Obj, prop_idx: u32) ?ObjId,
    isInSet: *const fn (reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool,
    readRef: *const fn (reader: *Obj, prop_idx: u32) ?ObjId,
    readRefSet: *const fn (reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]ObjId,
    readRefSetAdded: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readRefSetRemoved: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readSubObjSetAdded: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readSubObjSetRemoved: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readSubObjSet: *const fn (reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]ObjId,
    readBlob: *const fn (reader: *Obj, prop_idx: u32) []u8,
    getPrototype: *const fn (obj: *Obj) ObjId,
    getParent: *const fn (obj: ObjId) ObjId,
    getVersion: *const fn (obj: ObjId) ObjVersion,
    getReferencerSet: *const fn (allocator: std.mem.Allocator, obj: ObjId) anyerror![]ObjId,
    isAlive: *const fn (obj: ObjId) bool,
    getRelation: *const fn (top_level_obj: ObjId, obj: ObjId, prop_idx: u32, in_set_obj: ?ObjId) ObjRelation,
    isChildOff: *const fn (parent_obj: ObjId, child_obj: ObjId) bool,
    inisitateDeep: *const fn (allocator: std.mem.Allocator, last_parent: ObjId, to_inisiated_obj: ObjId) ?ObjId, // TODO: is needed?
    createObjectFromPrototype: *const fn (prototype: ObjId) anyerror!ObjId,
    cloneObject: *const fn (obj: ObjId) anyerror!ObjId,
    setDefaultObject: *const fn (obj: ObjId) void,
    destroyObject: *const fn (obj: ObjId) void,
    createObject: *const fn (db: DbId, type_idx: TypeIdx) anyerror!ObjId,
    createEmptyObject: *const fn (db: DbId, type_idx: TypeIdx) anyerror!ObjId,
    getTypeIdx: *const fn (db: DbId, type_hash: TypeHash) ?TypeIdx,
    addAspect: *const fn (db: DbId, type_idx: TypeIdx, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getAspect: *const fn (db: DbId, type_idx: TypeIdx, aspect_hash: cetech1.StrId32) ?*anyopaque,
    addPropertyAspect: *const fn (db: DbId, type_idx: TypeIdx, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getPropertyAspect: *const fn (db: DbId, type_idx: TypeIdx, prop_idx: u32, aspect_hash: cetech1.StrId32) ?*anyopaque,
    hasTypeSet: *const fn (db: DbId, type_idx: TypeIdx) bool,
    hasTypeSubobject: *const fn (db: DbId, type_idx: TypeIdx) bool,
    getTypeHash: *const fn (db: DbId, type_idx: TypeIdx) ?TypeHash,
    getChangeObjects: *const fn (db: DbId, allocator: std.mem.Allocator, type_idx: TypeIdx, since_version: TypeVersion) anyerror!ChangedObjects,
    getDefaultObject: *const fn (db: DbId, type_idx: TypeIdx) ?ObjId,
    getFirstObject: *const fn (db: DbId, type_idx: TypeIdx) ObjId,
    getAllObjectByType: *const fn (db: DbId, allocator: std.mem.Allocator, type_idx: TypeIdx) ?[]ObjId,
    addOnObjIdDestroyed: *const fn (db: DbId, fce: OnObjIdDestroyed) anyerror!void,
    removeOnObjIdDestroyed: *const fn (db: DbId, fce: OnObjIdDestroyed) void,
    addType: *const fn (db: DbId, name: []const u8, prop_def: []const PropDef) anyerror!TypeIdx,
    getTypeName: *const fn (db: DbId, type_idx: TypeIdx) ?[]const u8,
    getTypePropDef: *const fn (db: DbId, type_idx: TypeIdx) ?[]const PropDef,
    getTypePropDefIdx: *const fn (db: DbId, type_idx: TypeIdx, prop_name: []const u8) ?u32,
    stressIt: *const fn (db: DbId, type_idx: TypeIdx, type_idx2: TypeIdx, ref_obj1: ObjId) anyerror!void,
    gc: *const fn (db: DbId, allocator: std.mem.Allocator) anyerror!void,
    dump: *const fn (db: DbId) anyerror!void,
};

pub var api: *const CdbAPI = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, CdbAPI).?;
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
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    };
}
