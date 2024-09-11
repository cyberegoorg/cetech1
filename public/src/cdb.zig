const std = @import("std");
const strid = @import("strid.zig");
const uuid = @import("uuid.zig");

const log = std.log.scoped(.assetdb);

pub const OBJID_ZERO = ObjId{};

pub const ObjVersion = u64;

pub const TypeHash = strid.StrId32;

/// Type idx
pub const TypeIdx = packed struct(u32) {
    idx: u32 = 0,

    pub fn isEmpty(self: *const TypeIdx) bool {
        return self.idx == 0;
    }

    pub fn eql(a: TypeIdx, b: TypeIdx) bool {
        return a.idx == b.idx;
    }
};

pub const ObjIdGen = u8;

/// Object id
pub const ObjId = packed struct(u64) {
    id: u24 = 0,
    gen: ObjIdGen = 0,
    type_idx: TypeIdx = .{},

    pub fn isEmpty(self: *const ObjId) bool {
        return self.id == 0 and self.gen == 0 and self.type_idx.isEmpty();
    }

    pub fn eql(a: ObjId, b: ObjId) bool {
        return a.id == b.id and a.gen == b.gen and a.type_idx.eql(b.type_idx);
    }

    pub fn format(self: ObjId, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) (@TypeOf(writer).Error)!void {
        try std.fmt.format(writer, "{d}:{d}-{d}", .{ self.id, self.gen, self.type_idx.idx });
    }

    pub fn toU64(self: *const ObjId) u64 {
        const ptr: *u64 = @ptrFromInt(@intFromPtr(self));
        return ptr.*;
    }

    pub fn fromU64(value: u64) ObjId {
        const ptr: *ObjId = @ptrFromInt(@intFromPtr(&value));
        return ptr.*;
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
    owned,
    not_owned, //TODO: remove with explicit isChild call
    inheried,
    overide,
    inisiated,
};

pub const CreateTypesI = struct {
    pub const c_name = "ct_cdb_create_cdb_types_i";
    pub const name_hash = strid.strId64(@This().c_name);

    create_types: *const fn (db: Db) void,

    pub inline fn implement(comptime T: type) CreateTypesI {
        if (!std.meta.hasFn(T, "createTypes")) @compileError("implement me");

        return CreateTypesI{
            .create_types = struct {
                pub fn f(main_db: Db) void {
                    T.createTypes(main_db) catch |err| {
                        log.err("CreateTypesI.createTypes failed with error {}", .{err});
                    };
                }
            }.f,
        };
    }
};

pub const PostCreateTypesI = struct {
    pub const c_name = "ct_cdb_post_create_cdb_types_i";
    pub const name_hash = strid.strId64(@This().c_name);

    post_create_types: *const fn (db: Db) anyerror!void,

    pub inline fn implement(comptime T: type) PostCreateTypesI {
        if (!std.meta.hasFn(T, "postCreateTypes")) @compileError("implement me");

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
pub const OnObjIdDestroyed = *const fn (db: Db, objects: []ObjId) void;

/// Helper that create CDB type info and TypedAPI when you can use prop enum.
/// This make typed helper for read/write operation where you can use property enum and not idx.
/// For method without docs see docs in Db object.
/// This not register type cdb. For type register use addType function on DB.
pub fn CdbTypeDecl(comptime type_name: [:0]const u8, comptime props_enum: type, comptime extend: type) type {
    return struct {
        const Self = @This();

        pub const f = extend;

        pub const name = type_name;
        pub const type_hash = strid.strId32(type_name);
        pub const PropsEnum = props_enum;

        pub inline fn typeIdx(db: Db) TypeIdx {
            return db.getTypeIdx(Self.type_hash).?;
        }

        pub inline fn propIdx(prop: PropsEnum) u32 {
            return @intFromEnum(prop);
        }

        pub inline fn addAspect(db: Db, comptime T: type, aspect_ptr: *T) !void {
            try db.addAspect(T, db.getTypeIdx(Self.type_hash).?, aspect_ptr);
        }

        pub inline fn getAspect(db: Db, comptime T: type) ?*T {
            return db.getAspect(T, db.getTypeIdx(Self.type_hash).?);
        }

        pub inline fn addPropertyAspect(db: Db, comptime T: type, prop: PropsEnum, aspect_ptr: *T) !void {
            try db.addPropertyAspect(T, db.getTypeIdx(Self.type_hash).?, Self.propIdx(prop), aspect_ptr);
        }

        pub inline fn getPropertyAspect(db: Db, comptime T: type, prop: PropsEnum) ?*T {
            try db.getPropertyAspect(T, db.getTypeIdx(Self.type_hash).?, Self.propIdx(prop));
        }

        pub inline fn createObject(db: Db) !ObjId {
            return db.createObject(db.getTypeIdx(Self.type_hash).?);
        }

        pub inline fn destroyObject(db: Db, obj: ObjId) void {
            return db.destroyObject(obj);
        }

        pub inline fn read(db: Db, obj: ObjId) ?*Obj {
            return db.readObj(obj);
        }

        pub inline fn write(db: Db, obj: ObjId) ?*Obj {
            return db.writeObj(obj);
        }

        pub inline fn commit(db: Db, writer: *Obj) !void {
            return db.writeCommit(writer);
        }

        pub inline fn readValue(db: Db, comptime T: type, reader: *Obj, prop: PropsEnum) T {
            return db.readValue(T, reader, Self.propIdx(prop));
        }

        pub inline fn setValue(db: Db, comptime T: type, writer: *Obj, prop: PropsEnum, value: T) void {
            db.setValue(T, writer, Self.propIdx(prop), value);
        }

        pub inline fn setStr(db: Db, writer: *Obj, prop: PropsEnum, value: [:0]const u8) !void {
            return db.setStr(writer, Self.propIdx(prop), value);
        }

        pub inline fn readStr(db: Db, reader: *Obj, prop: PropsEnum) ?[:0]const u8 {
            return db.readStr(reader, Self.propIdx(prop));
        }
        pub inline fn setSubObj(db: Db, writer: *Obj, prop: PropsEnum, subobj_writer: *Obj) !void {
            try db.setSubObj(writer, Self.propIdx(prop), subobj_writer);
        }

        pub inline fn readSubObj(db: Db, reader: *Obj, prop: PropsEnum) ?ObjId {
            return db.readSubObj(reader, Self.propIdx(prop));
        }

        pub inline fn setRef(db: Db, writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            return db.setRef(writer, Self.propIdx(prop), value);
        }

        pub inline fn readRef(db: Db, reader: *Obj, prop: PropsEnum) ?ObjId {
            return db.readRef(reader, Self.propIdx(prop));
        }

        pub inline fn readRefSet(db: Db, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return db.readRefSet(reader, Self.propIdx(prop), allocator);
        }

        pub inline fn readRefSetAdded(db: Db, reader: *Obj, prop: PropsEnum) []const ObjId {
            return db.readRefSetAdded(reader, Self.propIdx(prop));
        }

        pub inline fn readRefSetRemoved(db: Db, reader: *Obj, prop: PropsEnum) []const ObjId {
            return db.readRefSetRemoved(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSetAdded(db: Db, reader: *Obj, prop: PropsEnum) []const ObjId {
            return db.readSubObjSetAdded(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSetRemoved(db: Db, reader: *Obj, prop: PropsEnum) []const ObjId {
            return db.readSubObjSetRemoved(reader, Self.propIdx(prop));
        }

        pub inline fn addRefToSet(db: Db, writer: *Obj, prop: PropsEnum, values: []const ObjId) !void {
            try db.addRefToSet(writer, Self.propIdx(prop), values);
        }

        pub inline fn removeFromRefSet(db: Db, writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            try db.removeFromRefSet(writer, Self.propIdx(prop), value);
        }

        pub inline fn addSubObjToSet(db: Db, writer: *Obj, prop: PropsEnum, subobj_writers: []const *Obj) !void {
            try db.addSubObjToSet(writer, Self.propIdx(prop), subobj_writers);
        }

        pub inline fn readSubObjSet(db: Db, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) !?[]const ObjId {
            return db.readSubObjSet(reader, Self.propIdx(prop), allocator);
        }

        pub inline fn removeFromSubObjSet(db: Db, writer: *Obj, prop: PropsEnum, sub_writer: *Obj) !void {
            try db.removeFromSubObjSet(writer, Self.propIdx(prop), sub_writer);
        }

        pub inline fn createBlob(db: Db, writer: *Obj, prop: PropsEnum, size: usize) anyerror!?[]u8 {
            return try db.createBlob(writer, Self.propIdx(prop), size);
        }
        pub inline fn readBlob(db: Db, reader: *Obj, prop: PropsEnum) []u8 {
            return db.readBlob(reader, Self.propIdx(prop));
        }

        pub inline fn isInSet(db: Db, reader: *Obj, prop: PropsEnum, item_ibj: ObjId) bool {
            return db.isInSet(reader, Self.propIdx(prop), item_ibj);
        }
    };
}

/// Database object.
pub const Db = struct {
    const Self = @This();

    /// Create new cdb type.
    pub inline fn addType(self: Self, name: []const u8, prop_def: []const PropDef) !TypeIdx {
        return self.vtable.addTypeFn(self.ptr, name, prop_def);
    }

    /// Get type name from type hash.
    pub inline fn getTypeName(self: Self, type_idx: TypeIdx) ?[]const u8 {
        return self.vtable.getTypeNameFn(self.ptr, type_idx);
    }

    /// Get type definition for type hash.
    pub inline fn getTypePropDef(self: Self, type_idx: TypeIdx) ?[]const PropDef {
        return self.vtable.getTypePropDefFn(self.ptr, type_idx);
    }

    /// Get property definition for type hash and property name.
    pub inline fn getTypePropDefIdx(self: Self, type_idx: TypeIdx, prop_name: []const u8) ?u32 {
        return self.vtable.getTypePropDefIdxFn(self.ptr, type_idx, prop_name);
    }

    /// Add aspect to type.
    pub inline fn addAspect(self: Self, comptime T: type, type_idx: TypeIdx, aspect_ptr: *T) !void {
        try self.vtable.addAspectFn(self.ptr, type_idx, T.c_name, aspect_ptr);
    }

    /// Get type aspect.
    pub inline fn getAspect(self: Self, comptime T: type, type_idx: TypeIdx) ?*T {
        return @alignCast(@ptrCast(self.vtable.getAspectFn(self.ptr, type_idx, T.name_hash)));
    }

    /// Add aspect to property.
    pub inline fn addPropertyAspect(self: Self, comptime T: type, type_idx: TypeIdx, prop_idx: u32, aspect_ptr: *T) !void {
        try self.vtable.addPropertyAspectFn(self.ptr, type_idx, prop_idx, T.c_name, aspect_ptr);
    }

    /// Get aspect for property.
    pub inline fn getPropertyAspect(self: Self, comptime T: type, type_idx: TypeIdx, prop_idx: u32) ?*T {
        return @alignCast(@ptrCast(self.vtable.getPropertyAspectFn(self.ptr, type_idx, prop_idx, T.name_hash)));
    }

    /// Create object for type hash
    pub inline fn createObject(self: Self, type_idx: TypeIdx) anyerror!ObjId {
        return self.vtable.createObjectFn(self.ptr, type_idx);
    }

    /// Create object as instance of prototype obj.
    pub inline fn createObjectFromPrototype(self: Self, prototype_obj: ObjId) anyerror!ObjId {
        return self.vtable.createObjectFromPrototypeFn(self.ptr, prototype_obj);
    }

    /// Clone object
    pub inline fn cloneObject(self: Self, obj: ObjId) anyerror!ObjId {
        return self.vtable.cloneObjectFn(self.ptr, obj);
    }

    // Destroy object
    pub inline fn destroyObject(self: Self, obj: ObjId) void {
        return self.vtable.destroyObjectFn(self.ptr, obj);
    }

    /// Set default object
    pub inline fn setDefaultObject(self: Self, obj: ObjId) void {
        return self.vtable.setDefaultObjectFn(self.ptr, obj);
    }

    /// Get object reader.
    /// Reader is valid until GC.
    pub inline fn readObj(self: Self, obj: ObjId) ?*Obj {
        return self.vtable.readObjFn(self.ptr, obj);
    }

    /// Get object writer.
    pub inline fn writeObj(self: Self, obj: ObjId) ?*Obj {
        return self.vtable.writeObjFn(self.ptr, obj);
    }

    /// Commit writer changes
    pub inline fn writeCommit(self: Self, writer: *Obj) !void {
        return self.vtable.writeCommitFn(self.ptr, writer);
    }

    /// Retarget writer to another objid. Still need call commit
    pub inline fn retargetWrite(self: Self, writer: *Obj, obj: ObjId) !void {
        return self.vtable.retargetWriteFn(self.ptr, writer, obj);
    }

    /// Read property value for basic types.
    pub inline fn readValue(self: Self, comptime T: type, reader: *Obj, prop_idx: u32) T {
        const value_ptr = self.vtable.readGenericFn(self.ptr, reader, prop_idx, getCDBTypeFromT(T));
        const typed_ptr: *const T = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    /// Set property value for basic types.
    pub inline fn setValue(self: Self, comptime T: type, writer: *Obj, prop_idx: u32, value: T) void {
        const value_ptr: [*]const u8 = @ptrCast(&value);
        self.vtable.setGenericFn(self.ptr, writer, prop_idx, value_ptr, getCDBTypeFromT(T));
    }

    /// Reset property overide flag.
    /// Valid for object that is instance of another object.
    pub inline fn resetPropertyOveride(self: Self, writer: *Obj, prop_idx: u32) void {
        return self.vtable.resetPropertyOverideFn(self.ptr, writer, prop_idx);
    }

    /// Is property overided.
    /// Valid for object that is instance of another object.
    pub inline fn isPropertyOverrided(self: Self, obj: *Obj, prop_idx: u32) bool {
        return self.vtable.isPropertyOverridedFn(self.ptr, obj, prop_idx);
    }

    /// Instantiate subobject from prorotype property.
    /// Make new object from subobject protoype, set property.
    /// Valid for object that is instance of another object.
    pub inline fn instantiateSubObj(self: Self, writer: *Obj, prop_idx: u32) !ObjId {
        return self.vtable.instantiateSubObjFn(self.ptr, writer, prop_idx);
    }

    /// Instantiate subobject from prorotype property in set.
    /// Make new object from subobject protoype, set property.
    /// Valid for object that is instance of another object.
    pub inline fn instantiateSubObjFromSet(self: Self, writer: *Obj, prop_idx: u32, obj_set: ObjId) !ObjId {
        return self.vtable.instantiateSubObjFromSetFn(self.ptr, writer, prop_idx, obj_set);
    }

    /// Get object prototype.
    pub inline fn getPrototype(self: Self, obj: *Obj) ObjId {
        return self.vtable.getPrototypeFn(self.ptr, obj);
    }

    /// Set string property
    pub inline fn setStr(self: Self, writer: *Obj, prop_idx: u32, value: [:0]const u8) !void {
        return self.vtable.setStrFn(self.ptr, writer, prop_idx, value);
    }

    /// Read string property
    pub inline fn readStr(self: Self, reader: *Obj, prop_idx: u32) ?[:0]const u8 {
        return self.vtable.readStrFn(self.ptr, reader, prop_idx);
    }

    /// Set sub object property
    pub inline fn setSubObj(self: Self, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) !void {
        return self.vtable.setSubObjFn(self.ptr, writer, prop_idx, subobj_writer);
    }

    /// Read sub object property
    pub inline fn readSubObj(self: Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.vtable.readSubObjFn(self.ptr, reader, prop_idx);
    }

    /// Set reference  property
    pub inline fn setRef(self: Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        return self.vtable.setRefFn(self.ptr, writer, prop_idx, value);
    }

    /// Get reference property
    pub inline fn readRef(self: Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.vtable.readRefFn(self.ptr, reader, prop_idx);
    }

    /// Clear reference
    pub inline fn clearRef(self: Self, writer: *Obj, prop_idx: u32) !void {
        return self.vtable.clearRefFn(self.ptr, writer, prop_idx);
    }

    /// Clear subobject (This destroy subobject if exist).
    pub inline fn clearSubObj(self: Self, writer: *Obj, prop_idx: u32) !void {
        return self.vtable.clearSubObjFn(self.ptr, writer, prop_idx);
    }

    /// Read reference set.
    /// This make new array for result set.
    /// Caller own the memory.
    pub inline fn readRefSet(self: Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.vtable.readRefSetFn(self.ptr, reader, prop_idx, allocator);
    }

    /// Read reference set but only added to this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readRefSetAdded(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.vtable.readRefSetAddedFn(self.ptr, reader, prop_idx);
    }

    /// Read reference set but only removed from this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readRefSetRemoved(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.vtable.readRefSetRemovedFn(self.ptr, reader, prop_idx);
    }

    /// Read subobj set but only added to this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readSubObjSetAdded(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.vtable.readSubObjSetAddedFn(self.ptr, reader, prop_idx);
    }

    /// Read subobj set but only removed to this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readSubObjSetRemoved(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.vtable.readSubObjSetRemovedFn(self.ptr, reader, prop_idx);
    }

    /// Add reference to set..
    pub inline fn addRefToSet(self: Self, writer: *Obj, prop_idx: u32, values: []const ObjId) !void {
        try self.vtable.addRefToSetFn(self.ptr, writer, prop_idx, values);
    }

    /// Remove reference from set
    pub inline fn removeFromRefSet(self: Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        try self.vtable.removeFromRefSetFn(self.ptr, writer, prop_idx, value);
    }

    /// Add subobj to set
    pub inline fn addSubObjToSet(self: Self, writer: *Obj, prop_idx: u32, subobj_writers: []const *Obj) !void {
        try self.vtable.addSubObjToSetFn(self.ptr, writer, prop_idx, subobj_writers);
    }

    /// Read subibj set.
    /// This make new array for result set.
    /// Caller own the memory.
    pub inline fn readSubObjSet(self: Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const ObjId {
        return self.vtable.readSubObjSetFn(self.ptr, reader, prop_idx, allocator);
    }

    /// Remove from subobj set
    pub inline fn removeFromSubObjSet(self: Self, writer: *Obj, prop_idx: u32, sub_writer: *Obj) !void {
        try self.vtable.removeFromSubObjSetFn(self.ptr, writer, prop_idx, sub_writer);
    }

    /// Create new blob for property.
    pub inline fn createBlob(self: Self, writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8 {
        return try self.vtable.createBlobFn(self.ptr, writer, prop_idx, size);
    }

    /// Get blob for property
    pub inline fn readBlob(self: Self, reader: *Obj, prop_idx: u32) []u8 {
        return self.vtable.readBlobFn(self.ptr, reader, prop_idx);
    }

    // Do GC work.
    // This destroy object and reader pointer are invalid to use after this.
    pub inline fn gc(self: Self, tmp_allocator: std.mem.Allocator) !void {
        return try self.vtable.gcFn(self.ptr, tmp_allocator);
    }

    // Get all object that referenece this obj.
    // Caller own the memory.
    pub inline fn getReferencerSet(self: Self, obj: ObjId, tmp_allocator: std.mem.Allocator) ![]ObjId {
        return try self.vtable.getReferencerSetFn(self.ptr, obj, tmp_allocator);
    }

    // Get object parent.
    pub inline fn getParent(self: Self, obj: ObjId) ObjId {
        return self.vtable.getParentFn(self.ptr, obj);
    }

    // Add callback that call in GC phase on destroyed objids.
    pub inline fn addOnObjIdDestroyed(self: Self, fce: OnObjIdDestroyed) !void {
        try self.vtable.addOnObjIdDestroyedFn(self.ptr, fce);
    }

    // Remove callback.
    pub inline fn removeOnObjIdDestroyed(self: Self, fce: OnObjIdDestroyed) void {
        self.vtable.removeOnObjIdDestroyedFn(self.ptr, fce);
    }

    // Get object version.
    // Version is counter increment if obj is changed or any subobj or prototype is changed.
    pub inline fn getVersion(self: Self, obj: ObjId) ObjVersion {
        return self.vtable.getVersionFn(self.ptr, obj);
    }

    //TODO: temporary
    pub inline fn stressIt(self: Self, type_idx: TypeIdx, type_idx2: TypeIdx, ref_obj1: ObjId) anyerror!void {
        try self.vtable.stressItFn(self.ptr, type_idx, type_idx2, ref_obj1);
    }

    pub inline fn isIinisiated(self: Self, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool {
        return self.vtable.isIinisiatedFn(self.ptr, obj, set_prop_idx, inisiated_obj);
    }

    pub inline fn canIinisiated(self: Self, obj: *Obj, inisiated_obj: *Obj) bool {
        return self.vtable.canIinisiateFn(self.ptr, obj, inisiated_obj);
    }

    pub inline fn restoreDeletedInSet(self: Self, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void {
        return self.vtable.restoreDeletedInSetFn(self.ptr, obj, set_prop_idx, inisiated_obj);
    }

    pub inline fn isInSet(self: Self, reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool {
        return self.vtable.isInSetFn(self.ptr, reader, prop_idx, item_ibj);
    }

    pub inline fn setPrototype(self: Self, obj: ObjId, prototype: ObjId) !void {
        return self.vtable.setPrototypeFn(self.ptr, obj, prototype);
    }

    pub inline fn getDefaultObject(self: Self, type_idx: TypeIdx) ?ObjId {
        return self.vtable.getDefaultObjectFn(self.ptr, type_idx);
    }

    pub inline fn getFirstObject(self: Self, type_idx: TypeIdx) ?ObjId {
        return self.vtable.getFirstObjectFn(self.ptr, type_idx);
    }

    pub inline fn getAllObjectByType(self: Self, allocator: std.mem.Allocator, type_idx: TypeIdx) ?[]ObjId {
        return self.vtable.getAllObjectByTypeFn(self.ptr, allocator, type_idx);
    }

    pub inline fn hasTypeSet(self: Self, type_idx: TypeIdx) bool {
        return self.vtable.hasTypeSetFn(self.ptr, type_idx);
    }

    pub inline fn hasTypeSubobject(self: Self, type_idx: TypeIdx) bool {
        return self.vtable.hasTypeSubobjectFn(self.ptr, type_idx);
    }

    // For performance reason cache typeidx
    pub inline fn getTypeIdx(self: Self, type_hash: TypeHash) ?TypeIdx {
        return self.vtable.getTypeIdxFn(self.ptr, type_hash);
    }

    pub inline fn getTypeHash(self: Self, type_idx: TypeIdx) ?TypeHash {
        return self.vtable.getTypeHashFn(self.ptr, type_idx);
    }

    pub inline fn getChangeObjects(self: Self, allocator: std.mem.Allocator, type_idx: TypeIdx, since_version: TypeVersion) !ChangedObjects {
        return self.vtable.getChangeObjects(self.ptr, allocator, type_idx, since_version);
    }

    pub inline fn isAlive(self: Self, obj: ObjId) bool {
        return self.vtable.isAlive(self.ptr, obj);
    }

    pub inline fn dump(self: Self) !void {
        return self.vtable.dump(self.ptr);
    }

    pub inline fn getRelation(self: Self, top_level_obj: ObjId, obj: ObjId, prop_idx: u32, in_set_obj: ?ObjId) ObjRelation {
        return self.vtable.getRelationFn(self.ptr, top_level_obj, obj, prop_idx, in_set_obj);
    }

    pub inline fn inisitateDeep(self: *Self, allocator: std.mem.Allocator, last_parent: ObjId, to_inisiated_obj: ObjId) ?ObjId {
        return self.vtable.inisitateDeepFn(self.ptr, allocator, last_parent, to_inisiated_obj);
    }

    pub inline fn isChildOff(self: Self, parent_obj: ObjId, child_obj: ObjId) bool {
        return self.vtable.isChildOffFn(self.ptr, parent_obj, child_obj);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // Type operation
        addTypeFn: *const fn (db: *anyopaque, name: []const u8, prop_def: []const PropDef) anyerror!TypeIdx,
        getTypeNameFn: *const fn (db: *anyopaque, type_idx: TypeIdx) ?[]const u8,
        getTypePropDefFn: *const fn (db: *anyopaque, type_idx: TypeIdx) ?[]const PropDef,
        getTypePropDefIdxFn: *const fn (db: *anyopaque, type_idx: TypeIdx, prop_name: []const u8) ?u32,

        // Aspects
        addAspectFn: *const fn (db: *anyopaque, type_idx: TypeIdx, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
        getAspectFn: *const fn (db: *anyopaque, type_idx: TypeIdx, aspect_hash: strid.StrId32) ?*anyopaque,

        addPropertyAspectFn: *const fn (db: *anyopaque, type_idx: TypeIdx, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
        getPropertyAspectFn: *const fn (db: *anyopaque, type_idx: TypeIdx, prop_idx: u32, aspect_hash: strid.StrId32) ?*anyopaque,

        addOnObjIdDestroyedFn: *const fn (db: *anyopaque, fce: OnObjIdDestroyed) anyerror!void,
        removeOnObjIdDestroyedFn: *const fn (db: *anyopaque, fce: OnObjIdDestroyed) void,

        // Object operation
        createObjectFn: *const fn (db: *anyopaque, type_idx: TypeIdx) anyerror!ObjId,
        createObjectFromPrototypeFn: *const fn (db: *anyopaque, prototype: ObjId) anyerror!ObjId,
        cloneObjectFn: *const fn (db: *anyopaque, obj: ObjId) anyerror!ObjId,
        setDefaultObjectFn: *const fn (db: *anyopaque, obj: ObjId) void,
        destroyObjectFn: *const fn (db: *anyopaque, obj: ObjId) void,
        readObjFn: *const fn (db: *anyopaque, obj: ObjId) ?*Obj,
        writeObjFn: *const fn (db: *anyopaque, obj: ObjId) ?*Obj,
        writeCommitFn: *const fn (db: *anyopaque, writer: *Obj) anyerror!void,
        retargetWriteFn: *const fn (db_: *anyopaque, writer: *Obj, obj: ObjId) anyerror!void,
        getPrototypeFn: *const fn (db_: *anyopaque, obj: *Obj) ObjId,
        getParentFn: *const fn (db_: *anyopaque, obj: ObjId) ObjId,
        getVersionFn: *const fn (db_: *anyopaque, obj: ObjId) ObjVersion,
        getReferencerSetFn: *const fn (db_: *anyopaque, obj: ObjId, allocator: std.mem.Allocator) anyerror![]ObjId,
        getDefaultObjectFn: *const fn (db: *anyopaque, type_idx: TypeIdx) ?ObjId,
        setPrototypeFn: *const fn (db: *anyopaque, obj: ObjId, prototype: ObjId) anyerror!void,
        getFirstObjectFn: *const fn (db_: *anyopaque, type_idx: TypeIdx) ObjId,
        getAllObjectByTypeFn: *const fn (db_: *anyopaque, tmp_allocator: std.mem.Allocator, type_idx: TypeIdx) ?[]ObjId,

        // Object property operation
        resetPropertyOverideFn: *const fn (db_: *anyopaque, writer: *Obj, prop_idx: u32) void,
        isPropertyOverridedFn: *const fn (db_: *anyopaque, obj: *Obj, prop_idx: u32) bool,
        isIinisiatedFn: *const fn (db_: *anyopaque, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool,
        canIinisiateFn: *const fn (db_: *anyopaque, obj: *Obj, inisiated_obj: *Obj) bool,
        restoreDeletedInSetFn: *const fn (db_: *anyopaque, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void,

        readGenericFn: *const fn (self: *anyopaque, obj: *Obj, prop_idx: u32, prop_type: PropType) []const u8,
        setGenericFn: *const fn (self: *anyopaque, obj: *Obj, prop_idx: u32, value: [*]const u8, prop_type: PropType) void,

        setStrFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, value: [:0]const u8) anyerror!void,
        readStrFn: *const fn (self: *anyopaque, obj: *Obj, prop_idx: u32) [:0]const u8,

        readSubObjFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) ?ObjId,
        setSubObjFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
        clearSubObjFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32) anyerror!void,
        instantiateSubObjFn: *const fn (db_: *anyopaque, writer: *Obj, prop_idx: u32) anyerror!ObjId,
        instantiateSubObjFromSetFn: *const fn (db_: *anyopaque, writer: *Obj, prop_idx: u32, obj_set: ObjId) anyerror!ObjId,
        isInSetFn: *const fn (db_: *anyopaque, reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool,

        readRefFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) ?ObjId,
        setRefFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
        clearRefFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32) anyerror!void,

        addRefToSetFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, values: []const ObjId) anyerror!void,
        removeFromRefSetFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
        readRefSetFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,

        readRefSetAddedFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) []const ObjId,
        readRefSetRemovedFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) []const ObjId,
        readSubObjSetAddedFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) []const ObjId,
        readSubObjSetRemovedFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) []const ObjId,

        addSubObjToSetFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, subobjs_writer: []const *Obj) anyerror!void,
        removeFromSubObjSetFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
        readSubObjSetFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,

        createBlobFn: *const fn (db: *anyopaque, writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8,
        readBlobFn: *const fn (db: *anyopaque, reader: *Obj, prop_idx: u32) []u8,

        stressItFn: *const fn (db: *anyopaque, type_idx: TypeIdx, type_idx2: TypeIdx, ref_obj1: ObjId) anyerror!void,

        gcFn: *const fn (db: *anyopaque, tmp_allocator: std.mem.Allocator) anyerror!void,
        dump: *const fn (db: *anyopaque) anyerror!void,

        hasTypeSetFn: *const fn (db: *anyopaque, type_idx: TypeIdx) bool,
        hasTypeSubobjectFn: *const fn (db: *anyopaque, type_idx: TypeIdx) bool,

        getTypeIdxFn: *const fn (db: *anyopaque, type_hash: TypeHash) ?TypeIdx,
        getTypeHashFn: *const fn (db: *anyopaque, type_idx: TypeIdx) ?TypeHash,

        getChangeObjects: *const fn (db: *anyopaque, allocator: std.mem.Allocator, type_idx: TypeIdx, since_version: TypeVersion) anyerror!ChangedObjects,
        isAlive: *const fn (db: *anyopaque, obj: ObjId) bool,

        getRelationFn: *const fn (db: *anyopaque, top_level_obj: ObjId, obj: ObjId, prop_idx: u32, in_set_obj: ?ObjId) ObjRelation,

        // TODO: is needed?
        inisitateDeepFn: *const fn (db: *anyopaque, allocator: std.mem.Allocator, last_parent: ObjId, to_inisiated_obj: ObjId) ?ObjId,

        isChildOffFn: *const fn (db: *anyopaque, parent_obj: ObjId, child_obj: ObjId) bool,
    };
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
    pub inline fn createDb(self: *Self, name: [:0]const u8) !Db {
        return try self.createDbFn(name);
    }

    /// Destroy and free database.
    pub inline fn destroyDb(self: *Self, db: Db) void {
        return self.destroyDbFn(db);
    }

    //#region Pointers to implementation.
    // DB
    createDbFn: *const fn (name: [:0]const u8) anyerror!Db,
    destroyDbFn: *const fn (db: Db) void,
    //#endregion
};

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
