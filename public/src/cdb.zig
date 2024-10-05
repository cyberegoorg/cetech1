const std = @import("std");
const strid = @import("strid.zig");
const uuid = @import("uuid.zig");

const log = std.log.scoped(.assetdb);

pub const OBJID_ZERO = ObjId{};

pub const ObjVersion = u64;

pub const TypeHash = strid.StrId32;

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
    pub const c_name = "ct_cdbcreate_cdbtypes_i";
    pub const name_hash = strid.strId64(@This().c_name);

    create_types: *const fn (db: DbId) void,

    pub inline fn implement(comptime T: type) CreateTypesI {
        if (!std.meta.hasFn(T, "createTypes")) @compileError("implement me");

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
    pub const c_name = "ct_cdbpost_create_cdbtypes_i";
    pub const name_hash = strid.strId64(@This().c_name);

    post_create_types: *const fn (db: DbId) anyerror!void,

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
        pub const type_hash = strid.strId32(type_name);
        pub const PropsEnum = props_enum;

        pub inline fn propIdx(prop: PropsEnum) u32 {
            return @intFromEnum(prop);
        }

        pub inline fn typeIdx(api: *const CdbAPI, db: DbId) TypeIdx {
            return api.getTypeIdx(db, Self.type_hash).?;
        }

        pub inline fn addAspect(comptime T: type, api: *const CdbAPI, db: DbId, aspect_ptr: *T) !void {
            try api.addAspect(T, db, api.getTypeIdx(db, Self.type_hash).?, aspect_ptr);
        }

        pub inline fn getAspect(comptime T: type, api: *const CdbAPI, db: DbId) ?*T {
            return api.getAspect(T, db, api.getTypeIdx(db, Self.type_hash).?);
        }

        pub inline fn addPropertyAspect(comptime T: type, api: *const CdbAPI, db: DbId, prop: PropsEnum, aspect_ptr: *T) !void {
            try api.addPropertyAspect(T, db, api.getTypeIdx(db, Self.type_hash).?, Self.propIdx(prop), aspect_ptr);
        }

        pub inline fn getPropertyAspect(comptime T: type, api: *const CdbAPI, db: DbId, prop: PropsEnum) ?*T {
            try api.getPropertyAspect(T, db, api.getTypeIdx(db, Self.type_hash).?, Self.propIdx(prop));
        }

        pub inline fn createObject(api: *const CdbAPI, db: DbId) !ObjId {
            return api.createObject(db, api.getTypeIdx(db, Self.type_hash).?);
        }

        pub inline fn destroyObject(api: *const CdbAPI, obj: ObjId) void {
            return api.destroyObject(obj);
        }

        pub inline fn write(api: *const CdbAPI, obj: ObjId) ?*Obj {
            return api.writeObj(obj);
        }

        pub inline fn commit(api: *const CdbAPI, writer: *Obj) !void {
            return api.writeCommit(writer);
        }

        pub inline fn setValue(comptime T: type, api: *const CdbAPI, writer: *Obj, prop: PropsEnum, value: T) void {
            api.setValue(T, writer, Self.propIdx(prop), value);
        }

        pub inline fn setStr(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, value: [:0]const u8) !void {
            return api.setStr(writer, Self.propIdx(prop), value);
        }

        pub inline fn setSubObj(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, subobj_writer: *Obj) !void {
            try api.setSubObj(writer, Self.propIdx(prop), subobj_writer);
        }

        pub inline fn read(api: *const CdbAPI, obj: ObjId) ?*Obj {
            return api.readObj(obj);
        }

        pub inline fn readValue(comptime T: type, api: *const CdbAPI, reader: *Obj, prop: PropsEnum) T {
            return api.readValue(T, reader, Self.propIdx(prop));
        }

        pub inline fn readStr(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) ?[:0]const u8 {
            return api.readStr(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObj(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) ?ObjId {
            return api.readSubObj(reader, Self.propIdx(prop));
        }

        pub inline fn readRef(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) ?ObjId {
            return api.readRef(reader, Self.propIdx(prop));
        }

        pub inline fn readRefSet(api: *const CdbAPI, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) ?[]const ObjId {
            return api.readRefSet(reader, Self.propIdx(prop), allocator);
        }

        pub inline fn readRefSetAdded(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) []const ObjId {
            return api.readRefSetAdded(reader, Self.propIdx(prop));
        }

        pub inline fn readRefSetRemoved(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) []const ObjId {
            return api.readRefSetRemoved(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSetAdded(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) []const ObjId {
            return api.readSubObjSetAdded(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSetRemoved(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) []const ObjId {
            return api.readSubObjSetRemoved(reader, Self.propIdx(prop));
        }

        pub inline fn readSubObjSet(api: *const CdbAPI, reader: *Obj, prop: PropsEnum, allocator: std.mem.Allocator) !?[]const ObjId {
            return api.readSubObjSet(reader, Self.propIdx(prop), allocator);
        }

        pub inline fn readBlob(api: *const CdbAPI, reader: *Obj, prop: PropsEnum) []u8 {
            return api.readBlob(reader, Self.propIdx(prop));
        }

        pub inline fn isInSet(api: *const CdbAPI, reader: *Obj, prop: PropsEnum, item_ibj: ObjId) bool {
            return api.isInSet(reader, Self.propIdx(prop), item_ibj);
        }

        pub inline fn removeFromSubObjSet(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, sub_writer: *Obj) !void {
            try api.removeFromSubObjSet(writer, Self.propIdx(prop), sub_writer);
        }

        pub inline fn createBlob(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, size: usize) anyerror!?[]u8 {
            return try api.createBlob(writer, Self.propIdx(prop), size);
        }

        pub inline fn setRef(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            return api.setRef(writer, Self.propIdx(prop), value);
        }

        pub inline fn addRefToSet(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, values: []const ObjId) !void {
            try api.addRefToSet(writer, Self.propIdx(prop), values);
        }

        pub inline fn removeFromRefSet(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, value: ObjId) !void {
            try api.removeFromRefSet(writer, Self.propIdx(prop), value);
        }

        pub inline fn addSubObjToSet(api: *const CdbAPI, writer: *Obj, prop: PropsEnum, subobj_writers: []const *Obj) !void {
            try api.addSubObjToSet(writer, Self.propIdx(prop), subobj_writers);
        }
    };
}

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
    pub inline fn createDb(self: *Self, name: [:0]const u8) !DbId {
        return try self.createDbFn(name);
    }

    /// Destroy and free database.
    pub inline fn destroyDb(self: *Self, db: DbId) void {
        return self.destroyDbFn(db);
    }

    /// Get object writer.
    pub inline fn writeObj(self: Self, obj: ObjId) ?*Obj {
        return self.writeObjFn(obj);
    }

    /// Commit writer changes
    pub inline fn writeCommit(self: Self, writer: *Obj) !void {
        return self.writeCommitFn(writer);
    }

    /// Retarget writer to another objid. Still need call commit
    pub inline fn retargetWrite(self: Self, writer: *Obj, obj: ObjId) !void {
        return self.retargetWriteFn(writer, obj);
    }

    /// Set property value for basic types.
    pub inline fn setValue(self: Self, comptime T: type, writer: *Obj, prop_idx: u32, value: T) void {
        const value_ptr: [*]const u8 = @ptrCast(&value);
        self.setGenericFn(writer, prop_idx, value_ptr, getCDBTypeFromT(T));
    }

    /// Reset property overide flag.
    /// Valid for object that is instance of another object.
    pub inline fn resetPropertyOveride(self: Self, writer: *Obj, prop_idx: u32) void {
        return self.resetPropertyOverideFn(writer, prop_idx);
    }

    /// Instantiate subobject from prorotype property.
    /// Make new object from subobject protoype, set property.
    /// Valid for object that is instance of another object.
    pub inline fn instantiateSubObj(self: Self, writer: *Obj, prop_idx: u32) !ObjId {
        return self.instantiateSubObjFn(writer, prop_idx);
    }

    /// Instantiate subobject from prorotype property in set.
    /// Make new object from subobject protoype, set property.
    /// Valid for object that is instance of another object.
    pub inline fn instantiateSubObjFromSet(self: Self, writer: *Obj, prop_idx: u32, obj_set: ObjId) !ObjId {
        return self.instantiateSubObjFromSetFn(writer, prop_idx, obj_set);
    }

    /// Set string property
    pub inline fn setStr(self: Self, writer: *Obj, prop_idx: u32, value: [:0]const u8) !void {
        return self.setStrFn(writer, prop_idx, value);
    }

    /// Set sub object property
    pub inline fn setSubObj(self: Self, writer: *Obj, prop_idx: u32, subobj_writer: *Obj) !void {
        return self.setSubObjFn(writer, prop_idx, subobj_writer);
    }

    /// Set reference  property
    pub inline fn setRef(self: Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        return self.setRefFn(writer, prop_idx, value);
    }

    /// Clear reference
    pub inline fn clearRef(self: Self, writer: *Obj, prop_idx: u32) !void {
        return self.clearRefFn(writer, prop_idx);
    }

    /// Clear subobject (This destroy subobject if exist).
    pub inline fn clearSubObj(self: Self, writer: *Obj, prop_idx: u32) !void {
        return self.clearSubObjFn(writer, prop_idx);
    }

    /// Add reference to set..
    pub inline fn addRefToSet(self: Self, writer: *Obj, prop_idx: u32, values: []const ObjId) !void {
        try self.addRefToSetFn(writer, prop_idx, values);
    }

    /// Remove reference from set
    pub inline fn removeFromRefSet(self: Self, writer: *Obj, prop_idx: u32, value: ObjId) !void {
        try self.removeFromRefSetFn(writer, prop_idx, value);
    }

    /// Add subobj to set
    pub inline fn addSubObjToSet(self: Self, writer: *Obj, prop_idx: u32, subobj_writers: []const *Obj) !void {
        try self.addSubObjToSetFn(writer, prop_idx, subobj_writers);
    }

    /// Remove from subobj set
    pub inline fn removeFromSubObjSet(self: Self, writer: *Obj, prop_idx: u32, sub_writer: *Obj) !void {
        try self.removeFromSubObjSetFn(writer, prop_idx, sub_writer);
    }

    /// Create new blob for property.
    pub inline fn createBlob(self: Self, writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8 {
        return try self.createBlobFn(writer, prop_idx, size);
    }

    pub inline fn restoreDeletedInSet(self: Self, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void {
        return self.restoreDeletedInSetFn(obj, set_prop_idx, inisiated_obj);
    }

    pub inline fn setPrototype(self: Self, obj: ObjId, prototype: ObjId) !void {
        return self.setPrototypeFn(obj, prototype);
    }

    /// Get object reader.
    /// Reader is valid until GC.
    pub inline fn readObj(self: Self, obj: ObjId) ?*Obj {
        return self.readObjFn(obj);
    }

    /// Read property value for basic types.
    pub inline fn readValue(self: Self, comptime T: type, reader: *Obj, prop_idx: u32) T {
        const value_ptr = self.readGenericFn(reader, prop_idx, getCDBTypeFromT(T));
        const typed_ptr: *const T = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    /// Is property overided.
    /// Valid for object that is instance of another object.
    pub inline fn isPropertyOverrided(self: Self, obj: *Obj, prop_idx: u32) bool {
        return self.isPropertyOverridedFn(obj, prop_idx);
    }

    /// Get object prototype.
    pub inline fn getPrototype(self: Self, obj: *Obj) ObjId {
        return self.getPrototypeFn(obj);
    }

    /// Read string property
    pub inline fn readStr(self: Self, reader: *Obj, prop_idx: u32) ?[:0]const u8 {
        return self.readStrFn(reader, prop_idx);
    }

    /// Read sub object property
    pub inline fn readSubObj(self: Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.readSubObjFn(reader, prop_idx);
    }

    /// Get reference property
    pub inline fn readRef(self: Self, reader: *Obj, prop_idx: u32) ?ObjId {
        return self.readRefFn(reader, prop_idx);
    }

    /// Read reference set.
    /// This make new array for result set.
    /// Caller own the memory.
    pub inline fn readRefSet(self: Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId {
        return self.readRefSetFn(reader, prop_idx, allocator);
    }

    /// Read reference set but only added to this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readRefSetAdded(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.readRefSetAddedFn(reader, prop_idx);
    }

    /// Read reference set but only removed from this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readRefSetRemoved(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.readRefSetRemovedFn(reader, prop_idx);
    }

    /// Read subobj set but only added to this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readSubObjSetAdded(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.readSubObjSetAddedFn(reader, prop_idx);
    }

    /// Read subobj set but only removed to this property and not for all inheret from prototype.
    /// This make new array for result set.
    pub inline fn readSubObjSetRemoved(self: Self, reader: *Obj, prop_idx: u32) []const ObjId {
        return self.readSubObjSetRemovedFn(reader, prop_idx);
    }

    /// Read subibj set.
    /// This make new array for result set.
    /// Caller own the memory.
    pub inline fn readSubObjSet(self: Self, reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const ObjId {
        return self.readSubObjSetFn(reader, prop_idx, allocator);
    }

    /// Get blob for property
    pub inline fn readBlob(self: Self, reader: *Obj, prop_idx: u32) []u8 {
        return self.readBlobFn(reader, prop_idx);
    }

    pub inline fn isIinisiated(self: Self, obj: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool {
        return self.isIinisiatedFn(obj, set_prop_idx, inisiated_obj);
    }

    pub inline fn canIinisiated(self: Self, obj: *Obj, inisiated_obj: *Obj) bool {
        return self.canIinisiateFn(obj, inisiated_obj);
    }

    pub inline fn isInSet(self: Self, reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool {
        return self.isInSetFn(reader, prop_idx, item_ibj);
    }

    pub inline fn getDbFromObjid(self: Self, obj: ObjId) DbId {
        return self.getDbFromObjidFn(obj);
    }

    pub inline fn getDbFromObj(self: Self, obj: *Obj) DbId {
        return self.getDbFromObjFn(obj);
    }

    // Get all object that referenece this obj.
    // Caller own the memory.
    pub inline fn getReferencerSet(self: Self, tmp_allocator: std.mem.Allocator, obj: ObjId) ![]ObjId {
        return try self.getReferencerSetFn(tmp_allocator, obj);
    }

    // Get object parent.
    pub inline fn getParent(self: Self, obj: ObjId) ObjId {
        return self.getParentFn(obj);
    }

    // Get object version.
    // Version is counter increment if obj is changed or any subobj or prototype is changed.
    pub inline fn getVersion(self: Self, obj: ObjId) ObjVersion {
        return self.getVersionFn(obj);
    }

    pub inline fn isAlive(self: Self, obj: ObjId) bool {
        return self.isAliveFn(obj);
    }

    pub inline fn getRelation(self: Self, top_level_obj: ObjId, obj: ObjId, prop_idx: u32, in_set_obj: ?ObjId) ObjRelation {
        return self.getRelationFn(top_level_obj, obj, prop_idx, in_set_obj);
    }

    pub inline fn inisitateDeep(self: *Self, allocator: std.mem.Allocator, last_parent: ObjId, to_inisiated_obj: ObjId) ?ObjId {
        return self.inisitateDeepFn(allocator, last_parent, to_inisiated_obj);
    }

    pub inline fn isChildOff(self: Self, parent_obj: ObjId, child_obj: ObjId) bool {
        return self.isChildOffFn(parent_obj, child_obj);
    }

    /// Create object as instance of prototype obj.
    pub inline fn createObjectFromPrototype(self: Self, prototype_obj: ObjId) anyerror!ObjId {
        return self.createObjectFromPrototypeFn(prototype_obj);
    }

    /// Clone object
    pub inline fn cloneObject(self: Self, obj: ObjId) anyerror!ObjId {
        return self.cloneObjectFn(obj);
    }

    // Destroy object
    pub inline fn destroyObject(self: Self, obj: ObjId) void {
        return self.destroyObjectFn(obj);
    }

    /// Set default object
    pub inline fn setDefaultObject(self: Self, obj: ObjId) void {
        return self.setDefaultObjectFn(obj);
    }

    pub inline fn dump(self: Self, db: DbId) !void {
        return self.dumpFn(db);
    }

    // Do GC work.
    // This destroy object and reader pointer are invalid to use after this.
    pub inline fn gc(self: Self, tmp_allocator: std.mem.Allocator, db: DbId) !void {
        return try self.gcFn(db, tmp_allocator);
    }

    /// Create object for type hash
    pub inline fn createObject(self: Self, db: DbId, type_idx: TypeIdx) anyerror!ObjId {
        return self.createObjectFn(db, type_idx);
    }

    // For performance reason cache typeidx
    pub inline fn getTypeIdx(self: Self, db: DbId, type_hash: TypeHash) ?TypeIdx {
        return self.getTypeIdxFn(db, type_hash);
    }

    /// Add aspect to type.
    pub inline fn addAspect(self: Self, comptime T: type, db: DbId, type_idx: TypeIdx, aspect_ptr: *T) !void {
        try self.addAspectFn(db, type_idx, T.c_name, aspect_ptr);
    }

    /// Get type aspect.
    pub inline fn getAspect(self: Self, comptime T: type, db: DbId, type_idx: TypeIdx) ?*T {
        return @alignCast(@ptrCast(self.getAspectFn(db, type_idx, T.name_hash)));
    }

    /// Add aspect to property.
    pub inline fn addPropertyAspect(self: Self, comptime T: type, db: DbId, type_idx: TypeIdx, prop_idx: u32, aspect_ptr: *T) !void {
        try self.addPropertyAspectFn(db, type_idx, prop_idx, T.c_name, aspect_ptr);
    }

    /// Get aspect for property.
    pub inline fn getPropertyAspect(self: Self, comptime T: type, db: DbId, type_idx: TypeIdx, prop_idx: u32) ?*T {
        return @alignCast(@ptrCast(self.getPropertyAspectFn(db, type_idx, prop_idx, T.name_hash)));
    }

    pub inline fn hasTypeSet(self: Self, db: DbId, type_idx: TypeIdx) bool {
        return self.hasTypeSetFn(db, type_idx);
    }

    pub inline fn hasTypeSubobject(self: Self, db: DbId, type_idx: TypeIdx) bool {
        return self.hasTypeSubobjectFn(db, type_idx);
    }

    pub inline fn getTypeHash(self: Self, db: DbId, type_idx: TypeIdx) ?TypeHash {
        return self.getTypeHashFn(db, type_idx);
    }

    pub inline fn getChangeObjects(self: Self, allocator: std.mem.Allocator, db: DbId, type_idx: TypeIdx, since_version: TypeVersion) !ChangedObjects {
        return self.getChangeObjectsFn(db, allocator, type_idx, since_version);
    }

    pub inline fn getDefaultObject(self: Self, db: DbId, type_idx: TypeIdx) ?ObjId {
        return self.getDefaultObjectFn(db, type_idx);
    }

    pub inline fn getFirstObject(self: Self, db: DbId, type_idx: TypeIdx) ?ObjId {
        return self.getFirstObjectFn(db, type_idx);
    }

    pub inline fn getAllObjectByType(self: Self, allocator: std.mem.Allocator, db: DbId, type_idx: TypeIdx) ?[]ObjId {
        return self.getAllObjectByTypeFn(db, allocator, type_idx);
    }

    // Add callback that call in GC phase on destroyed objids.
    pub inline fn addOnObjIdDestroyed(self: Self, db: DbId, fce: OnObjIdDestroyed) !void {
        try self.addOnObjIdDestroyedFn(db, fce);
    }

    // Remove callback.
    pub inline fn removeOnObjIdDestroyed(self: Self, db: DbId, fce: OnObjIdDestroyed) void {
        self.removeOnObjIdDestroyedFn(db, fce);
    }

    //TODO: temporary
    pub inline fn stressIt(self: Self, db: DbId, type_idx: TypeIdx, type_idx2: TypeIdx, ref_obj1: ObjId) anyerror!void {
        try self.stressItFn(db, type_idx, type_idx2, ref_obj1);
    }

    /// Create new cdb type.
    pub inline fn addType(self: Self, db: DbId, name: []const u8, prop_def: []const PropDef) !TypeIdx {
        return self.addTypeFn(db, name, prop_def);
    }

    /// Get type name from type hash.
    pub inline fn getTypeName(self: Self, db: DbId, type_idx: TypeIdx) ?[]const u8 {
        return self.getTypeNameFn(db, type_idx);
    }

    /// Get type definition for type hash.
    pub inline fn getTypePropDef(self: Self, db: DbId, type_idx: TypeIdx) ?[]const PropDef {
        return self.getTypePropDefFn(db, type_idx);
    }

    /// Get property definition for type hash and property name.
    pub inline fn getTypePropDefIdx(self: Self, db: DbId, type_idx: TypeIdx, prop_name: []const u8) ?u32 {
        return self.getTypePropDefIdxFn(db, type_idx, prop_name);
    }

    //#region Pointers to implementation.
    // DB
    createDbFn: *const fn (name: [:0]const u8) anyerror!DbId,
    destroyDbFn: *const fn (db: DbId) void,

    getDbFromObjidFn: *const fn (obj: ObjId) DbId,
    getDbFromObjFn: *const fn (obj: *Obj) DbId,

    setPrototypeFn: *const fn (obj: ObjId, prototype: ObjId) anyerror!void,

    // Writers
    writeObjFn: *const fn (obj: ObjId) ?*Obj,
    writeCommitFn: *const fn (writer: *Obj) anyerror!void,
    retargetWriteFn: *const fn (writer: *Obj, obj: ObjId) anyerror!void,
    resetPropertyOverideFn: *const fn (writer: *Obj, prop_idx: u32) void,
    restoreDeletedInSetFn: *const fn (writer: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) void,
    setGenericFn: *const fn (writer: *Obj, prop_idx: u32, value: [*]const u8, prop_type: PropType) void,
    setStrFn: *const fn (writer: *Obj, prop_idx: u32, value: [:0]const u8) anyerror!void,
    setSubObjFn: *const fn (writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    clearSubObjFn: *const fn (writer: *Obj, prop_idx: u32) anyerror!void,
    instantiateSubObjFn: *const fn (writer: *Obj, prop_idx: u32) anyerror!ObjId,
    instantiateSubObjFromSetFn: *const fn (writer: *Obj, prop_idx: u32, obj_set: ObjId) anyerror!ObjId,
    setRefFn: *const fn (writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    clearRefFn: *const fn (writer: *Obj, prop_idx: u32) anyerror!void,
    addRefToSetFn: *const fn (writer: *Obj, prop_idx: u32, values: []const ObjId) anyerror!void,
    removeFromRefSetFn: *const fn (writer: *Obj, prop_idx: u32, value: ObjId) anyerror!void,
    addSubObjToSetFn: *const fn (writer: *Obj, prop_idx: u32, subobjs_writer: []const *Obj) anyerror!void,
    removeFromSubObjSetFn: *const fn (writer: *Obj, prop_idx: u32, subobj_writer: *Obj) anyerror!void,
    createBlobFn: *const fn (writer: *Obj, prop_idx: u32, size: usize) anyerror!?[]u8,

    // Reads
    readObjFn: *const fn (obj: ObjId) ?*Obj,
    readStrFn: *const fn (reader: *Obj, prop_idx: u32) ?[:0]const u8,
    readGenericFn: *const fn (reader: *Obj, prop_idx: u32, prop_type: PropType) []const u8,
    isPropertyOverridedFn: *const fn (reader: *Obj, prop_idx: u32) bool,
    isIinisiatedFn: *const fn (reader: *Obj, set_prop_idx: u32, inisiated_obj: *Obj) bool,
    canIinisiateFn: *const fn (reader: *Obj, inisiated_obj: *Obj) bool,
    readSubObjFn: *const fn (reader: *Obj, prop_idx: u32) ?ObjId,
    isInSetFn: *const fn (reader: *Obj, prop_idx: u32, item_ibj: ObjId) bool,
    readRefFn: *const fn (reader: *Obj, prop_idx: u32) ?ObjId,
    readRefSetFn: *const fn (reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,
    readRefSetAddedFn: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readRefSetRemovedFn: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readSubObjSetAddedFn: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readSubObjSetRemovedFn: *const fn (reader: *Obj, prop_idx: u32) []const ObjId,
    readSubObjSetFn: *const fn (reader: *Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const ObjId,
    readBlobFn: *const fn (reader: *Obj, prop_idx: u32) []u8,
    getPrototypeFn: *const fn (obj: *Obj) ObjId,

    getParentFn: *const fn (obj: ObjId) ObjId,
    getVersionFn: *const fn (obj: ObjId) ObjVersion,
    getReferencerSetFn: *const fn (allocator: std.mem.Allocator, obj: ObjId) anyerror![]ObjId,

    isAliveFn: *const fn (obj: ObjId) bool,
    getRelationFn: *const fn (top_level_obj: ObjId, obj: ObjId, prop_idx: u32, in_set_obj: ?ObjId) ObjRelation,
    isChildOffFn: *const fn (parent_obj: ObjId, child_obj: ObjId) bool,
    inisitateDeepFn: *const fn (allocator: std.mem.Allocator, last_parent: ObjId, to_inisiated_obj: ObjId) ?ObjId, // TODO: is needed?

    createObjectFromPrototypeFn: *const fn (prototype: ObjId) anyerror!ObjId,
    cloneObjectFn: *const fn (obj: ObjId) anyerror!ObjId,
    setDefaultObjectFn: *const fn (obj: ObjId) void,
    destroyObjectFn: *const fn (obj: ObjId) void,

    createObjectFn: *const fn (db: DbId, type_idx: TypeIdx) anyerror!ObjId,
    getTypeIdxFn: *const fn (db: DbId, type_hash: TypeHash) ?TypeIdx,

    // Aspects
    addAspectFn: *const fn (db: DbId, type_idx: TypeIdx, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getAspectFn: *const fn (db: DbId, type_idx: TypeIdx, aspect_hash: strid.StrId32) ?*anyopaque,
    addPropertyAspectFn: *const fn (db: DbId, type_idx: TypeIdx, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) anyerror!void,
    getPropertyAspectFn: *const fn (db: DbId, type_idx: TypeIdx, prop_idx: u32, aspect_hash: strid.StrId32) ?*anyopaque,

    hasTypeSetFn: *const fn (db: DbId, type_idx: TypeIdx) bool,
    hasTypeSubobjectFn: *const fn (db: DbId, type_idx: TypeIdx) bool,

    getTypeHashFn: *const fn (db: DbId, type_idx: TypeIdx) ?TypeHash,
    getChangeObjectsFn: *const fn (db: DbId, allocator: std.mem.Allocator, type_idx: TypeIdx, since_version: TypeVersion) anyerror!ChangedObjects,

    getDefaultObjectFn: *const fn (db: DbId, type_idx: TypeIdx) ?ObjId,
    getFirstObjectFn: *const fn (db: DbId, type_idx: TypeIdx) ObjId,
    getAllObjectByTypeFn: *const fn (db: DbId, tmp_allocator: std.mem.Allocator, type_idx: TypeIdx) ?[]ObjId,

    addOnObjIdDestroyedFn: *const fn (db: DbId, fce: OnObjIdDestroyed) anyerror!void,
    removeOnObjIdDestroyedFn: *const fn (db: DbId, fce: OnObjIdDestroyed) void,

    addTypeFn: *const fn (db: DbId, name: []const u8, prop_def: []const PropDef) anyerror!TypeIdx,
    getTypeNameFn: *const fn (db: DbId, type_idx: TypeIdx) ?[]const u8,
    getTypePropDefFn: *const fn (db: DbId, type_idx: TypeIdx) ?[]const PropDef,
    getTypePropDefIdxFn: *const fn (db: DbId, type_idx: TypeIdx, prop_name: []const u8) ?u32,

    stressItFn: *const fn (db: DbId, type_idx: TypeIdx, type_idx2: TypeIdx, ref_obj1: ObjId) anyerror!void,
    gcFn: *const fn (db: DbId, allocator: std.mem.Allocator) anyerror!void,
    dumpFn: *const fn (db: DbId) anyerror!void,
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
