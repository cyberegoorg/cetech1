// NOTE: Braindump shit, features first for api then optimize internals.
// TODO: remove typestorage lookup, use typhe_hash => type_idx fce,  storages[objid.type_idx]
// TODO: linkedlist for objects to delete, *Object.next to Object

const builtin = @import("builtin");
const std = @import("std");

const c = @import("c.zig").c;
const public = @import("../cdb.zig");
const cetech1 = @import("../cetech1.zig");
const strid = @import("../strid.zig");

const log = @import("log.zig");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const uuid = @import("uuid.zig");

const cdb_test = @import("cdb_test.zig");

const StrId32 = strid.StrId32;
const strId32 = strid.strId32;

const MODULE_NAME = "cdb";

const Blob = []u8;
const IdSet = std.AutoArrayHashMap(public.ObjId, void);
const ReferencerIdSet = std.AutoArrayHashMap(public.ObjId, u32);
const PrototypeInstanceSet = std.AutoArrayHashMap(public.ObjId, void);
const IdSetPool = cetech1.mem.VirtualPool(ObjIdSet);
const OverridesSet = std.bit_set.DynamicBitSet;

const AtomicInt32 = std.atomic.Atomic(u32);
const AtomicInt64 = std.atomic.Atomic(u64);
const TypeStorageMap = std.AutoArrayHashMap(StrId32, TypeStorage);
const ToFreeIdQueue = std.atomic.Queue(*Object);
const FreeIdQueueNodePool = cetech1.mem.PoolWithLock(cetech1.FreeIdQueue.Node);
const ToFreeIdQueueNodePool = cetech1.mem.PoolWithLock(ToFreeIdQueue.Node);

const TypeAspectMap = std.AutoArrayHashMap(StrId32, *anyopaque);
const PropertyAspectPair = struct { StrId32, u32 };
const PropertyTypeAspectMap = std.AutoArrayHashMap(PropertyAspectPair, *anyopaque);

const OnObjIdDestroyMap = std.AutoArrayHashMap(public.OnObjIdDestroyed, void);

inline fn toObjFromObjO(obj: *public.Obj) *Object {
    return @alignCast(@ptrCast(obj));
}

// Type info + padding
const TypeInfoTuple = struct { usize, u8 };
inline fn alignPadding(addr: i64, align_: i64) u64 {
    return @bitCast((-(addr) & ((align_) - 1))); // i dont know where im steel this =D
    //return @bitCast((addr + (align_ - 1)) & ~(align_ - 1));
}
inline fn makeTypeTuple(comptime T: type) TypeInfoTuple {
    return .{ @sizeOf(T), @alignOf(T) };
}
inline fn getCdbTypeInfo(cdb_type: public.PropType) TypeInfoTuple {
    return switch (cdb_type) {
        public.PropType.BOOL => makeTypeTuple(bool),
        public.PropType.U64 => makeTypeTuple(u64),
        public.PropType.I64 => makeTypeTuple(i64),
        public.PropType.U32 => makeTypeTuple(u32),
        public.PropType.I32 => makeTypeTuple(i32),
        public.PropType.F64 => makeTypeTuple(f64),
        public.PropType.F32 => makeTypeTuple(f32),
        public.PropType.STR => makeTypeTuple([:0]u8),
        public.PropType.BLOB => makeTypeTuple(Blob),
        public.PropType.SUBOBJECT => makeTypeTuple(public.ObjId),
        public.PropType.REFERENCE => makeTypeTuple(public.ObjId),
        public.PropType.SUBOBJECT_SET => makeTypeTuple(*ObjIdSet),
        public.PropType.REFERENCE_SET => makeTypeTuple(*ObjIdSet),
        else => unreachable,
    };
}

//TODO: Optimize memory footprint
pub const Object = struct {
    const Self = @This();

    // ObjId associated with this Object.
    // ObjId can have multiple object because write clone entire object.
    objid: public.ObjId = .{},

    // Property memory.
    props_mem: []u8 = undefined,
    prop_offset: []usize = undefined,

    // Parent id and prop idx.
    parent: public.ObjId = .{},
    parent_prop_idx: u32 = 0,

    // Protypes
    prototype_id: u32 = 0,
    // Set of overided properties.
    overrides_set: OverridesSet,

    pub fn getPropPtr(self: *Self, comptime T: type, prop_idx: usize) *T {
        var ptr = self.props_mem.ptr + self.prop_offset[prop_idx];
        std.debug.assert(std.mem.isAligned(@intFromPtr(ptr), @alignOf(T)));
        return @alignCast(@ptrCast(ptr));
    }

    pub fn getPrototypeObjId(self: *Self) public.ObjId {
        return .{
            .id = self.prototype_id,
            .type_hash = if (self.prototype_id != 0) self.objid.type_hash else .{ .id = 0 },
        };
    }
};

pub const ObjIdSet = struct {
    const Self = @This();

    added: IdSet,
    removed: IdSet,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .added = IdSet.init(allocator),
            .removed = IdSet.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.added.deinit();
        self.removed.deinit();
    }

    pub fn appendIdSet(self: *Self, other: *Self) !void {
        for (other.added.keys()) |value| {
            _ = try self.add(value);
        }
        for (other.removed.keys()) |value| {
            _ = try self.remove(value);
        }
    }

    pub fn add(self: *Self, item: public.ObjId) !bool {
        var added = !self.added.contains(item);
        try self.added.put(item, {});
        _ = self.removed.swapRemove(item);
        return added;
    }

    pub fn remove(self: *Self, item: public.ObjId) !bool {
        var removed = self.added.swapRemove(item);

        if (!removed) {
            try self.removed.put(item, {});
        }

        return removed;
    }

    pub fn getAddedItems(self: *Self, allocator: std.mem.Allocator) ![]public.ObjId {
        var new = try allocator.alloc(public.ObjId, self.added.count());
        @memcpy(new, self.added.keys());
        return new;
    }

    pub fn getRemovedItems(self: *Self, allocator: std.mem.Allocator) ![]public.ObjId {
        var new = try allocator.alloc(public.ObjId, self.removed.count());
        @memcpy(new, self.removed.keys());
        return new;
    }
};

const limit_max = true;
const force_max = 10_000;

pub const TypeStorage = struct {
    const Self = @This();

    // TODO: For now allocate minimal object count, need better sage of vram on windows.
    const MAX_OBJECTS = if (limit_max) force_max else 1_000_000; // TODO: From max ID
    const MAX_OBJIDSETS = if (limit_max) force_max else 1_000_000;

    allocator: std.mem.Allocator,
    db: *Db,

    // Type data
    name: []const u8,
    type_hash: StrId32,
    props_def: []public.PropDef,
    props_size: usize,
    prop_offset: std.ArrayList(usize),

    default_obj: public.ObjId = public.OBJID_ZERO,

    // Per ObjectId data
    objid_pool: cetech1.mem.IdPool(u32),
    objid2obj: cetech1.mem.VirtualArray(?*Object),
    objid_ref_count: cetech1.mem.VirtualArray(AtomicInt32),
    objid_version: cetech1.mem.VirtualArray(AtomicInt64),

    objid2refs: cetech1.mem.VirtualArray(ReferencerIdSet),
    objid2refs_lock: cetech1.mem.VirtualArray(std.Thread.Mutex), //TODO: without lock?

    prototype2instances: cetech1.mem.VirtualArray(PrototypeInstanceSet),
    prototype2instances_lock: cetech1.mem.VirtualArray(std.Thread.Mutex), //TODO: without lock?

    // Per Object data
    object_pool: cetech1.mem.VirtualPool(Object),
    // Memory fro object property memory (properties memory)
    objs_mem: cetech1.mem.VirtualArray(u8), // NOTE: move memory after object? . [[Object1][padding][props_mem1]]...[[ObjectN][props_memN]]

    // Queue for objects to delete in GC phase
    to_free_queue: ToFreeIdQueue,
    to_free_obj_node_pool: ToFreeIdQueueNodePool,

    // Pool for set based properies.
    idset_pool: IdSetPool,

    // Aspects
    aspect_map: TypeAspectMap,
    property_aspect_map: PropertyTypeAspectMap,

    gc_name: [64:0]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, db: *Db, name: []const u8, props_def: []const public.PropDef) !Self {
        var props_size: usize = 0;
        var prop_offset = std.ArrayList(usize).init(allocator);
        for (props_def) |prop| {
            var ti = getCdbTypeInfo(prop.type);
            const size = ti[0];
            const type_align = ti[1];

            const padding = alignPadding(@bitCast(props_size), type_align);

            try prop_offset.append(props_size + padding);

            props_size += size + padding;
        }

        var copy_def = try std.ArrayList(public.PropDef).initCapacity(_allocator, props_def.len);
        try copy_def.appendSlice(props_def);

        return TypeStorage{
            .db = db,
            .name = name,
            .type_hash = strId32(name),
            .props_def = try copy_def.toOwnedSlice(),
            .allocator = allocator,
            .object_pool = try cetech1.mem.VirtualPool(Object).init(allocator, MAX_OBJECTS),

            .objid2obj = try cetech1.mem.VirtualArray(?*Object).init(MAX_OBJECTS),
            .objid_pool = cetech1.mem.IdPool(u32).init(allocator),
            .objid_ref_count = try cetech1.mem.VirtualArray(AtomicInt32).init(MAX_OBJECTS),
            .objid_version = try cetech1.mem.VirtualArray(AtomicInt64).init(MAX_OBJECTS),

            .objid2refs = try cetech1.mem.VirtualArray(ReferencerIdSet).init(MAX_OBJECTS),
            .objid2refs_lock = try cetech1.mem.VirtualArray(std.Thread.Mutex).init(MAX_OBJECTS),

            .prototype2instances = try cetech1.mem.VirtualArray(PrototypeInstanceSet).init(MAX_OBJECTS),
            .prototype2instances_lock = try cetech1.mem.VirtualArray(std.Thread.Mutex).init(MAX_OBJECTS),

            .objs_mem = try cetech1.mem.VirtualArray(u8).init(MAX_OBJECTS * props_size),

            .to_free_queue = ToFreeIdQueue.init(),
            .to_free_obj_node_pool = ToFreeIdQueueNodePool.init(allocator),

            .idset_pool = try IdSetPool.init(allocator, MAX_OBJIDSETS),

            .props_size = props_size,
            .prop_offset = prop_offset,
            .aspect_map = TypeAspectMap.init(allocator),
            .property_aspect_map = PropertyTypeAspectMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // idx 0 is null element
        for (self.object_pool.mem.items[1..self.object_pool.alocated_items.value]) |*obj| {
            obj.overrides_set.deinit();
        }

        // idx 0 is null element
        for (self.idset_pool.mem.items[1..self.idset_pool.alocated_items.value]) |*obj| {
            obj.deinit();
        }

        // idx 0 is null element
        for (self.objid2refs.items[1..self.objid_pool.count.value]) |*obj| {
            obj.deinit();
        }

        // idx 0 is null element
        for (self.prototype2instances.items[1..self.objid_pool.count.value]) |*obj| {
            obj.deinit();
        }

        self.prop_offset.deinit();
        self.object_pool.deinit();
        self.objid_pool.deinit();
        self.to_free_obj_node_pool.deinit();
        self.idset_pool.deinit();
        self.objid2obj.deinit();
        self.objs_mem.deinit();
        self.aspect_map.deinit();
        self.property_aspect_map.deinit();

        self.objid2refs.deinit();
        self.objid2refs_lock.deinit();
        self.prototype2instances.deinit();
        self.prototype2instances_lock.deinit();

        _allocator.free(self.props_def);
    }

    pub fn isTypeHashValidForProperty(self: *Self, prop_idx: u32, type_hash: StrId32) bool {
        if (self.props_def[prop_idx].type_hash.id == 0) return true;
        return std.meta.eql(self.props_def[prop_idx].type_hash, type_hash);
    }

    fn allocateObjId(self: *Self) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var is_new = false;
        var id = self.objid_pool.create(&is_new);
        self.objid_ref_count.items[id] = AtomicInt32.init(1);
        self.objid_version.items[id] = AtomicInt64.init(1);

        if (is_new) {
            self.objid2refs.items[id] = ReferencerIdSet.init(_allocator);
            self.prototype2instances.items[id] = PrototypeInstanceSet.init(_allocator);
        } else {
            self.objid2refs.items[id].clearRetainingCapacity();
            self.prototype2instances.items[id].clearRetainingCapacity();
        }
        self.objid2refs_lock.items[id] = std.Thread.Mutex{};
        self.prototype2instances_lock.items[id] = std.Thread.Mutex{};

        const objid = .{ .id = id, .type_hash = self.type_hash };

        return objid;
    }

    pub fn increaseVersion(self: *Self, obj: public.ObjId) void {
        _ = self.objid_version.items[obj.id].fetchAdd(1, .Monotonic);
    }

    pub fn increaseReference(self: *Self, obj: public.ObjId) void {
        _ = self.objid_ref_count.items[obj.id].fetchAdd(1, .Release);
    }

    pub fn decreaseReferenceToFree(self: *Self, object: *Object) !void {
        var ref_count = &self.objid_ref_count.items[object.objid.id];

        if (ref_count.value == 0) return; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        if (1 == ref_count.fetchSub(1, .Release)) {
            ref_count.fence(.Acquire);
            try self.addToFreeQueue(object);
        }
    }

    fn decreaseReferenceFree(self: *Self, object: *Object, destroyed_objid: *std.ArrayList(public.ObjId), tmp_allocator: std.mem.Allocator) anyerror!u32 {
        var ref_count = &self.objid_ref_count.items[object.objid.id];

        if (ref_count.value == 0) return 0; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        if (1 == ref_count.fetchSub(1, .Release)) {
            ref_count.fence(.Acquire);
            return try self.freeObject(object, destroyed_objid, tmp_allocator);
        }
        return 0;
    }

    pub fn setDefaultObject(self: *Self, obj: public.ObjId) void {
        self.default_obj = obj;
    }

    pub fn addToFreeQueue(self: *Self, object: *Object) !void {
        var new_node = try self.to_free_obj_node_pool.create();

        new_node.* = ToFreeIdQueue.Node{ .data = object };
        self.to_free_queue.put(new_node);
    }

    fn freeObjId(self: *Self, objid: public.ObjId) !void {
        //try self.db.unmapUuid(self.db.getUuid(objid));
        try self.objid_pool.destroy(objid.id);
    }

    fn allocateObject(self: *Self, id: ?public.ObjId, init_props: bool) !*Object {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var new = false;
        var obj = self.object_pool.create(&new);

        var obj_mem = self.objs_mem.items + (self.props_size * self.object_pool.index(obj));

        obj.* = Object{
            .objid = id orelse public.OBJID_ZERO,
            .props_mem = obj_mem[0..self.props_size],
            .prop_offset = self.prop_offset.items,
            .parent_prop_idx = 0,
            .overrides_set = if (new) try OverridesSet.initEmpty(self.allocator, self.props_def.len) else obj.*.overrides_set,
        };

        @memset(obj.props_mem, 0);

        // init sets
        if (init_props) {
            for (self.props_def, 0..) |prop_def, idx| {
                switch (prop_def.type) {
                    public.PropType.REFERENCE_SET, public.PropType.SUBOBJECT_SET => {
                        var true_ptr = obj.getPropPtr(*ObjIdSet, idx);
                        true_ptr.* = try self.allocateObjIdSet();
                    },
                    else => continue,
                }
            }
        }
        return obj;
    }

    pub fn addAspect(self: *Self, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        try self.aspect_map.put(strId32(apect_name), aspect_ptr);
    }
    pub fn getAspect(self: *Self, aspect_hash: StrId32) ?*anyopaque {
        return self.aspect_map.get(aspect_hash);
    }

    pub fn addPropertyAspect(self: *Self, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        try self.property_aspect_map.put(.{ strId32(apect_name), prop_idx }, aspect_ptr);
    }
    pub fn getPropertyAspect(self: *Self, prop_idx: u32, aspect_hash: StrId32) ?*anyopaque {
        return self.property_aspect_map.get(.{ aspect_hash, prop_idx });
    }

    pub fn allocateObjIdSet(self: *Self) !*ObjIdSet {
        var is_new = false;
        var array = self.idset_pool.create(&is_new);

        if (is_new) array.* = ObjIdSet.init(self.allocator);

        return array;
    }

    pub fn cloneIdSet(self: *Self, set: *ObjIdSet, empty: bool) !*ObjIdSet {
        var new_set = try self.allocateObjIdSet();
        if (!empty) try new_set.appendIdSet(set);
        return new_set;
    }

    pub fn destroyObjIdSet(self: *Self, list: *ObjIdSet) !void {
        list.added.clearRetainingCapacity();
        list.removed.clearRetainingCapacity();

        try self.idset_pool.destroy(list);
    }

    pub fn allocateBlob(self: *Self, size: usize) !Blob {
        return self.allocator.alloc(u8, size);
    }

    pub fn destroyBlob(self: *Self, blob: Blob) void {
        self.allocator.free(blob);
    }

    pub fn cloneBlob(self: *Self, blob: Blob) !Blob {
        var new_blob = try self.allocateBlob(blob.len);
        @memcpy(new_blob, blob);
        return new_blob;
    }

    pub fn createObj(self: *Self) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (!self.default_obj.isEmpty()) {
            return self.cloneObject(self.default_obj);
        }

        var id = try self.allocateObjId();
        var obj = try self.allocateObject(id, true);

        self.objid2obj.items[id.id] = obj;
        obj.parent = .{};

        return .{ .id = id.id, .type_hash = self.type_hash };
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var prototype_obj = self.db.getObjectPtr(prototype).?;
        var new_object = try self.cloneObjectRaw(prototype_obj, true, false);
        new_object.prototype_id = prototype_obj.objid.id;

        try self.addPrototypeInstance(prototype, new_object.objid);

        return new_object.objid;
    }

    pub fn cloneObject(self: *Self, obj: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = self.db.getObjectPtr(obj).?;
        var new_object = try self.cloneObjectRaw(true_obj, true, true);
        return new_object.objid;
    }

    pub fn destroyObj(self: *Self, obj: public.ObjId) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = self.objid2obj.items[obj.id];
        if (true_obj == null) return;
        try self.decreaseReferenceToFree(true_obj.?);
    }

    pub fn cloneObjectRaw(self: *Self, obj: *Object, create_new: bool, clone_subobject: bool) !*Object {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var obj_id = if (!create_new) obj.objid else try self.allocateObjId();
        var new_obj = try self.allocateObject(obj_id, false);

        if (!create_new) {
            new_obj.prototype_id = obj.prototype_id;
            new_obj.parent = obj.parent;
            new_obj.parent_prop_idx = obj.parent_prop_idx;
        }

        var it = obj.overrides_set.iterator(.{});
        while (it.next()) |value| {
            new_obj.overrides_set.setValue(value, obj.overrides_set.isSet(value));
        }

        @memcpy(new_obj.props_mem, obj.props_mem);

        // Patch old nonsimple value to new location
        for (self.props_def, 0..) |prop_def, idx| {
            switch (prop_def.type) {
                // Duplicate
                public.PropType.STR => {
                    var true_ptr = new_obj.getPropPtr([:0]u8, idx);
                    if (true_ptr.len != 0) {
                        true_ptr.* = try self.allocator.dupeZ(u8, true_ptr.*);
                    }
                },

                // Clone subobject if alocate new
                public.PropType.SUBOBJECT => {
                    var true_ptr = new_obj.getPropPtr(public.ObjId, idx);
                    if (true_ptr.*.id == 0) continue;
                    //var storage = self.db.getTypeStorage(true_ptr.*.type_hash).?;
                    if (clone_subobject) {
                        const clone_subobj = try self.db.cloneObject(true_ptr.*);
                        true_ptr.* = clone_subobj;
                        //try self.db.setSubObj(new_obj, @truncate(idx), self.db.getObjectPtr(clone_subobj).?);
                        self.db.setParent(self.db.getObjectPtr(clone_subobj).?, new_obj.objid, @truncate(idx));
                        //storage.increaseReference(true_ptr.*);
                    } else {
                        //storage.increaseReference(true_ptr.*);
                    }
                },

                // Increase ref
                public.PropType.REFERENCE => {
                    var true_ptr = new_obj.getPropPtr(public.ObjId, idx);
                    if (true_ptr.*.id == 0) continue;
                    var storage = self.db.getTypeStorage(true_ptr.*.type_hash).?;
                    storage.increaseReference(true_ptr.*);
                },

                public.PropType.SUBOBJECT_SET => {
                    var true_ptr = new_obj.getPropPtr(*ObjIdSet, idx);

                    if (clone_subobject) {
                        var new_set = try self.allocateObjIdSet();

                        var set = try true_ptr.*.getAddedItems(self.allocator);
                        defer self.allocator.free(set);
                        for (set) |subobj| {
                            const clone_subobj = try self.db.cloneObject(subobj);

                            //try self.db.addToSubObjSet(new_obj, @truncate(idx), &.{self.db.getObjectPtr(clone_subobj).?});

                            //var storage = self.db.getTypeStorage(subobj.type_hash).?;
                            self.db.setParent(self.db.getObjectPtr(clone_subobj).?, new_obj.objid, @truncate(idx));
                            _ = try new_set.add(clone_subobj);
                            //storage.increaseReference(clone_subobj);
                        }
                        true_ptr.* = new_set;
                    } else {
                        true_ptr.* = try self.cloneIdSet(true_ptr.*, create_new);
                        var set = try true_ptr.*.getAddedItems(self.allocator);
                        defer self.allocator.free(set);
                        for (set) |ref| {
                            var storage = self.db.getTypeStorage(ref.type_hash).?;
                            _ = storage;
                            //storage.increaseReference(ref);
                        }
                    }
                },

                // Duplicate set and increase ref
                public.PropType.REFERENCE_SET => {
                    var true_ptr = new_obj.getPropPtr(*ObjIdSet, idx);

                    true_ptr.* = try self.cloneIdSet(true_ptr.*, create_new);
                    var set = try true_ptr.*.getAddedItems(self.allocator);
                    defer self.allocator.free(set);
                    for (set) |ref| {
                        var storage = self.db.getTypeStorage(ref.type_hash).?;
                        //_ = storage;
                        storage.increaseReference(ref);
                    }
                },

                // Duplicate
                public.PropType.BLOB => {
                    var true_ptr = new_obj.getPropPtr(Blob, idx);
                    true_ptr.* = try self.cloneBlob(true_ptr.*);
                },

                else => continue,
            }
        }

        if (create_new) {
            self.objid2obj.items[new_obj.objid.id] = new_obj;
        }

        return new_obj;
    }

    pub fn freeObject(self: *Self, obj: *Object, destroyed_objid: *std.ArrayList(public.ObjId), tmp_allocator: std.mem.Allocator) !u32 {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const is_writer = self.objid2obj.items[obj.objid.id] != obj;

        var free_objects: u32 = 1;
        for (self.props_def, 0..) |prop_def, idx| {
            switch (prop_def.type) {
                .STR => {
                    var true_ptr = obj.getPropPtr([:0]u8, idx);
                    if (true_ptr.len != 0) {
                        self.allocator.free(true_ptr.*);
                    }
                },
                .BLOB => {
                    var true_ptr = obj.getPropPtr(Blob, idx);
                    self.destroyBlob(true_ptr.*);
                },
                .SUBOBJECT => {
                    var subobj = obj.getPropPtr(public.ObjId, idx);
                    var subobj_ptr = self.db.getObjectPtr(subobj.*) orelse continue;
                    var storage = self.db.getTypeStorage(subobj_ptr.objid.type_hash).?;

                    if (!is_writer) {
                        free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                        //free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                    }
                },
                .SUBOBJECT_SET => {
                    var true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    var set = try true_ptr.*.getAddedItems(tmp_allocator);
                    defer tmp_allocator.free(set);

                    for (set) |subobj| {
                        var subobj_ptr = self.db.getObjectPtr(subobj) orelse continue;
                        var storage = self.db.getTypeStorage(subobj.type_hash).?;
                        if (!is_writer) {
                            free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                            //free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                        }
                    }
                    try self.destroyObjIdSet(true_ptr.*);
                },
                .REFERENCE => {
                    var ref = obj.getPropPtr(public.ObjId, idx);
                    var ref_ptr = self.db.getObjectPtr(ref.*) orelse continue;
                    var storage = self.db.getTypeStorage(ref_ptr.objid.type_hash).?;
                    if (!is_writer) {
                        storage.removeObjIdReferencer(ref.*, obj.objid);
                    }
                    free_objects += try storage.decreaseReferenceFree(ref_ptr, destroyed_objid, tmp_allocator);
                },
                .REFERENCE_SET => {
                    var true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    var set = try true_ptr.*.getAddedItems(tmp_allocator);
                    defer tmp_allocator.free(set);
                    for (set) |ref_id| {
                        var ref_ptr = self.db.getObjectPtr(ref_id) orelse continue;
                        var storage = self.db.getTypeStorage(ref_ptr.objid.type_hash).?;
                        if (!is_writer) {
                            storage.removeObjIdReferencer(ref_id, obj.objid);
                        }
                        free_objects += try storage.decreaseReferenceFree(ref_ptr, destroyed_objid, tmp_allocator);
                    }
                    try self.destroyObjIdSet(true_ptr.*);
                },

                else => continue,
            }
        }

        // Destroy objid
        if (!is_writer) {
            // Has parent? (subobj || in subobjset)
            if (!obj.parent.isEmpty()) {
                var parent_obj = self.db.getObjectPtr(obj.parent);
                var storage = self.db.getTypeStorage(obj.parent.type_hash).?;
                var ref_count = &storage.objid_ref_count.items[obj.parent.id];
                if (ref_count.value != 0) {
                    switch (storage.props_def[obj.parent_prop_idx].type) {
                        public.PropType.SUBOBJECT => try self.db.clearSubObj(@ptrCast(parent_obj.?), obj.parent_prop_idx),
                        public.PropType.SUBOBJECT_SET => try self.db.removeFromSubObjSet(@ptrCast(parent_obj.?), obj.parent_prop_idx, @ptrCast(obj)),
                        else => undefined,
                    }
                }
                obj.parent = .{};
            }

            const referencers = self.objid2refs.items[obj.objid.id].keys();
            const referencers_prop_idx = self.objid2refs.items[obj.objid.id].values();
            for (referencers, referencers_prop_idx) |referencer, prop_idx| {
                // TODO: why need  orelse continue
                var storage = self.db.getTypeStorage(referencer.type_hash) orelse continue;
                var parent_obj = self.db.getObjectPtr(referencer) orelse continue;
                switch (storage.props_def[prop_idx].type) {
                    public.PropType.REFERENCE => try self.db.clearRef(@ptrCast(parent_obj), prop_idx),
                    public.PropType.REFERENCE_SET => try self.db.removeFromRefSet(@ptrCast(parent_obj), prop_idx, obj.objid),
                    else => undefined,
                }
            }

            if (obj.prototype_id != 0) {
                self.removePrototypeInstance(.{ .id = obj.prototype_id, .type_hash = obj.objid.type_hash }, obj.objid);
            }

            //std.debug.assert(obj.objid.id == 6 and obj.objid.type_hash.id == 2358001782);

            try self.freeObjId(obj.objid);
            self.objid2obj.items[obj.objid.id] = null;
            try destroyed_objid.append(obj.objid);
        }

        obj.overrides_set.setRangeValue(std.bit_set.Range{ .start = 0, .end = self.props_def.len }, false);
        try self.object_pool.destroy(obj);

        return free_objects;
    }

    pub fn gc(self: *Self, tmp_allocator: std.mem.Allocator) !u32 {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (profiler.profiler_enabled) {
            _ = try std.fmt.bufPrintZ(&self.gc_name, "CDB:GC: {s}", .{self.name});
            zone_ctx.Name(&self.gc_name);
        }

        var destroyed_ids = std.ArrayList(public.ObjId).init(tmp_allocator);
        defer destroyed_ids.deinit();

        var free_objects: u32 = 0;
        while (self.to_free_queue.get()) |node| {
            free_objects += try self.freeObject(node.data, &destroyed_ids, tmp_allocator);
            self.to_free_obj_node_pool.destroy(node);
        }

        self.db.callOnObjIdDestroyed(destroyed_ids.items);

        return free_objects;
    }

    pub fn readGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, prop_type: public.PropType) []const u8 {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(obj);

        if (builtin.mode == .Debug) {
            const real_type = self.props_def[prop_idx].type;
            std.debug.assert(real_type == prop_type);
        } // else: just belive

        // If exist prototype and prop is not override read from prototype.
        if (true_obj.prototype_id != 0 and !true_obj.overrides_set.isSet(prop_idx)) {
            var prototype_obj = self.db.getObjectPtr(true_obj.getPrototypeObjId());
            return readGeneric(self, @ptrCast(prototype_obj), prop_idx, prop_type);
        }

        var true_ptr = true_obj.getPropPtr(u8, prop_idx);
        var ptr: [*]const u8 = @ptrCast(true_ptr);
        return ptr[0..getCdbTypeInfo(prop_type)[0]];
    }

    pub fn readTT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32, prop_type: public.PropType) T {
        var value_ptr = self.readGeneric(obj, prop_idx, prop_type);
        var typed_ptr: *const T = @alignCast(@ptrCast(value_ptr.ptr));
        return typed_ptr.*;
    }

    pub fn readT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32) T {
        return self.readTT(T, obj, prop_idx, public.getCDBTypeFromT(T));
    }

    pub fn setGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, value: [*]const u8, prop_type: public.PropType) void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(obj);

        if (builtin.mode == .Debug) {
            const real_type = self.props_def[prop_idx].type;
            std.debug.assert(real_type == prop_type);
        } // else: just belive

        // If exist prototype set override flag to prop.
        if (true_obj.prototype_id != 0) {
            true_obj.overrides_set.set(prop_idx);
        }

        var true_ptr = true_obj.getPropPtr(u8, prop_idx);
        var ptr: [*]u8 = @ptrCast(true_ptr);
        var ptr2 = ptr[0..getCdbTypeInfo(prop_type)[0]];
        @memcpy(ptr2, value);
    }

    pub fn setTT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32, value: T, prop_type: public.PropType) void {
        var value_ptr: [*]const u8 = @ptrCast(&value);
        self.setGeneric(obj, prop_idx, value_ptr, prop_type);
    }

    pub fn setT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32, value: T) void {
        return self.setTT(T, obj, prop_idx, value, public.getCDBTypeFromT(T));
    }

    pub fn isPropertyOverrided(self: *Self, obj: *public.Obj, prop_idx: u32) bool {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        return true_obj.overrides_set.isSet(prop_idx);
    }

    pub fn instantiateSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const value = self.readTT(public.ObjId, writer, prop_idx, public.PropType.SUBOBJECT);
        if (value.isEmpty()) return;

        var storage = self.db.getTypeStorage(value.type_hash).?;
        var new_subobj = try storage.createObjectFromPrototype(value);
        //self.setTT(public.CdbObjIdT, writer, prop_idx, c.CT_CDB_OBJID_ZERO, public.PropertyType.SUBOBJECT);
        try self.db.setSubObj(writer, prop_idx, @ptrCast(self.db.getObjectPtr(new_subobj).?));
    }

    pub fn instantiateSubObjFromSet(self: *Self, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var storage = self.db.getTypeStorage(set_obj.type_hash).?;
        var new_subobj = try storage.createObjectFromPrototype(set_obj);
        var true_ptr = self.db.getObjectPtr(new_subobj).?;

        try self.db.addToSubObjSet(writer, prop_idx, &.{@ptrCast(true_ptr)});

        var set_obj_w = self.db.getObjectPtr(set_obj).?;
        try self.db.removeFromSubObjSet(writer, prop_idx, @ptrCast(set_obj_w));

        return new_subobj;
    }

    pub fn addPrototypeInstance(self: *Self, prototype: public.ObjId, instance: public.ObjId) !void {
        var lock = &self.prototype2instances_lock.items[prototype.id];
        lock.lock();
        defer lock.unlock();

        try self.prototype2instances.items[prototype.id].put(instance, {});
    }

    pub fn removePrototypeInstance(self: *Self, prototype: public.ObjId, instance: public.ObjId) void {
        var lock = &self.prototype2instances_lock.items[prototype.id];
        lock.lock();
        defer lock.unlock();

        _ = self.prototype2instances.items[prototype.id].swapRemove(instance);
    }

    pub fn addObjIdReferencer(self: *Self, objid: public.ObjId, referencer: public.ObjId, referencer_prop_idx: u32) !void {
        var lock = &self.objid2refs_lock.items[objid.id];
        lock.lock();
        defer lock.unlock();

        try self.objid2refs.items[objid.id].put(referencer, referencer_prop_idx);
    }

    pub fn removeObjIdReferencer(self: *Self, objid: public.ObjId, referencer: public.ObjId) void {
        var lock = &self.objid2refs_lock.items[objid.id];
        lock.lock();
        defer lock.unlock();

        _ = self.objid2refs.items[objid.id].swapRemove(referencer);
    }

    pub fn tranferObjIdReferencer(self: *Self, from_objid: public.ObjId, to_objid: public.ObjId) !void {
        var lock_from = &self.objid2refs_lock.items[from_objid.id];
        var lock_to = &self.objid2refs_lock.items[to_objid.id];
        lock_from.lock();
        lock_to.lock();
        defer lock_from.unlock();
        defer lock_to.unlock();

        var it = self.objid2refs.items[from_objid.id].iterator();
        while (it.next()) |kv| {
            try self.objid2refs.items[to_objid.id].put(kv.key_ptr.*, kv.value_ptr.*);
        }
    }
};

pub const Db = struct {
    const Self = @This();

    name: [:0]const u8,

    allocator: std.mem.Allocator,
    typestorage_map: TypeStorageMap,
    prev: ?*Db = null,
    next: ?*Db = null,

    // Stats
    write_commit_count: AtomicInt32,
    writers_count: AtomicInt32,
    read_count: AtomicInt32,
    free_objects: u32,
    obj_alocated: u32,

    on_obj_destroy_map: OnObjIdDestroyMap,

    // Buffers for profiler
    write_commit_name: [64:0]u8 = undefined,
    writers_name: [64:0]u8 = undefined,
    alocated_objects_name: [64:0]u8 = undefined,
    gc_free_objects_name: [64:0]u8 = undefined,
    read_name: [64:0]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, name: [:0]const u8) Db {
        return .{
            .name = name,
            .allocator = allocator,
            .typestorage_map = TypeStorageMap.init(allocator),

            .on_obj_destroy_map = OnObjIdDestroyMap.init(allocator),

            .write_commit_count = AtomicInt32.init(0),
            .writers_count = AtomicInt32.init(0),
            .read_count = AtomicInt32.init(0),
            .free_objects = 0,
            .obj_alocated = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.gc(self.allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not GC db on deinit {}", .{err});
            return;
        };

        for (self.typestorage_map.values()) |*value| {
            value.deinit();
        }

        self.on_obj_destroy_map.deinit();
        self.typestorage_map.deinit();
    }

    pub fn gc(self: *Self, tmp_allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.ZoneN(@src(), "CDB:GC");
        defer zone_ctx.End();

        self.free_objects = 0;

        for (self.typestorage_map.values()) |*type_storage| {
            if (type_storage.to_free_queue.isEmpty()) continue;
            self.free_objects += try type_storage.gc(tmp_allocator);
        }

        self.obj_alocated = 0;
        for (self.typestorage_map.values()) |type_map| {
            self.obj_alocated += type_map.objid_pool.count.value - 1;
        }

        if (profiler.profiler_enabled) {
            if (self.obj_alocated != 0) {
                _ = try std.fmt.bufPrintZ(&self.alocated_objects_name, "CDB allocated: {s}", .{self.name});
                profiler.api.plotU64(&self.alocated_objects_name, self.obj_alocated);
            }

            if (self.free_objects != 0) {
                _ = try std.fmt.bufPrintZ(&self.gc_free_objects_name, "CDB GC free objects: {s}", .{self.name});
                profiler.api.plotU64(&self.gc_free_objects_name, self.free_objects);
            }

            if (self.writers_count.value != 0) {
                _ = try std.fmt.bufPrintZ(&self.writers_name, "CDB writers: {s}", .{self.name});
                profiler.api.plotU64(&self.writers_name, self.writers_count.value);
            }

            if (self.write_commit_count.value != 0) {
                _ = try std.fmt.bufPrintZ(&self.write_commit_name, "CDB commits: {s}", .{self.name});
                profiler.api.plotU64(&self.write_commit_name, self.write_commit_count.value);
            }

            if (self.read_count.value != 0) {
                _ = try std.fmt.bufPrintZ(&self.read_name, "CDB reads: {s}", .{self.name});
                profiler.api.plotU64(&self.read_name, self.read_count.value);
            }
        }

        self.write_commit_count = AtomicInt32.init(0);
        self.writers_count = AtomicInt32.init(0);
        self.read_count = AtomicInt32.init(0);
    }

    pub fn addOnObjIdDestroyed(self: *Self, fce: public.OnObjIdDestroyed) !void {
        try self.on_obj_destroy_map.put(fce, {});
    }
    pub fn removeOnObjIdDestroyed(self: *Self, fce: public.OnObjIdDestroyed) void {
        _ = self.on_obj_destroy_map.swapRemove(fce);
    }

    pub fn callOnObjIdDestroyed(self: *Self, objects: []public.ObjId) void {
        for (self.on_obj_destroy_map.keys()) |fce| {
            fce(@ptrCast(self), objects);
        }
    }

    pub fn getTypeStorage(self: *Self, type_hash: StrId32) ?*TypeStorage {
        return self.typestorage_map.getPtr(type_hash);
    }

    pub fn getObjectPtr(self: *Self, obj: public.ObjId) ?*Object {
        var storage = self.getTypeStorage(obj.type_hash) orelse return null;
        return if (obj.isEmpty()) null else storage.objid2obj.items[obj.id];
    }

    fn getParent(self: *Self, obj: public.ObjId) public.ObjId {
        var true_obj = self.getObjectPtr(obj);
        if (true_obj == null) return public.OBJID_ZERO;
        return true_obj.?.parent;
    }

    fn setParent(self: *Self, obj: *Object, parent: public.ObjId, prop_index: u32) void {
        _ = self;
        obj.parent = parent;
        obj.parent_prop_idx = prop_index;
    }

    fn getVersion(self: *Self, obj: public.ObjId) u64 {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var storage = self.getTypeStorage(obj.type_hash).?;
        var true_obj = self.getObjectPtr(obj) orelse return 0;

        return storage.objid_version.items[true_obj.objid.id].value;

        // var version_hasher = std.hash.Wyhash.init(0);
        // self.fillVersionHaser(@TypeOf(version_hasher), &version_hasher, true_obj);
        // return version_hasher.final();
    }

    // TODO: GetVersionHash
    // fn fillVersionHaser(self: *Self, comptime hasherT: type, hasher: *hasherT, obj: *Object) void {
    //     var zone_ctx = profiler.ztracy.Zone(@src());
    //     defer zone_ctx.End();

    //     std.hash.autoHash(hasher, @intFromPtr(obj));
    //     const props_def = self.getTypePropDef(obj.objid.type_hash).?;

    //     if (obj.prototype_id != 0) {
    //         var proto_obj = self.getObjectPtr(.{ .id = obj.prototype_id, .type_hash = obj.objid.type_hash }).?;
    //         std.hash.autoHash(hasher, @intFromPtr(proto_obj));
    //     }

    //     for (props_def, 0..) |prop_def, idx| {
    //         switch (prop_def.type) {
    //             .SUBOBJECT => {
    //                 var subobj = obj.getPropPtr(public.ObjId, idx);
    //                 var subobj_ptr = self.getObjectPtr(subobj.*) orelse continue;
    //                 self.fillVersionHaser(hasherT, hasher, subobj_ptr);
    //             },
    //             .SUBOBJECT_SET => {
    //                 var true_ptr = obj.getPropPtr(*ObjIdSet, idx);

    //                 var set = true_ptr.*.added.keys();
    //                 for (set) |subobj| {
    //                     var subobj_ptr = self.getObjectPtr(subobj) orelse continue;
    //                     self.fillVersionHaser(hasherT, hasher, subobj_ptr);
    //                 }
    //             },
    //             else => continue,
    //         }
    //     }
    // }

    pub fn addAspect(self: *Self, type_hash: StrId32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        var storage = self.getTypeStorage(type_hash) orelse return;
        try storage.addAspect(apect_name, aspect_ptr);
    }
    pub fn getAspect(self: *Self, type_hash: StrId32, aspect_hash: StrId32) ?*anyopaque {
        var storage = self.getTypeStorage(type_hash) orelse return null;
        return storage.getAspect(aspect_hash);
    }

    pub fn addPropertyAspect(self: *Self, type_hash: StrId32, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        var storage = self.getTypeStorage(type_hash) orelse return;
        try storage.addPropertyAspect(prop_idx, apect_name, aspect_ptr);
    }
    pub fn getPropertyAspect(self: *Self, type_hash: StrId32, prop_idx: u32, aspect_hash: StrId32) ?*anyopaque {
        var storage = self.getTypeStorage(type_hash) orelse return null;
        return storage.getPropertyAspect(prop_idx, aspect_hash);
    }

    pub fn getTypeName(self: *Self, type_hash: StrId32) ?[]const u8 {
        var storage = self.getTypeStorage(type_hash) orelse return null;
        return storage.name;
    }

    pub fn getTypePropDefIdx(self: *Self, type_hash: strid.StrId32, prop_name: []const u8) ?u32 {
        const prop_def = self.getTypePropDef(type_hash) orelse return null;

        for (prop_def, 0..) |def, idx| {
            if (std.mem.eql(u8, def.name, prop_name)) return @truncate(idx);
        }
        return null;
    }
    pub fn getOrCreateTypeStorage(self: *Self, type_hash: StrId32, name: []const u8, prop_def: []const public.PropDef) !*TypeStorage {
        var result = try self.typestorage_map.getOrPut(type_hash);
        if (!result.found_existing) {
            var ts = try TypeStorage.init(_allocator, self, name, prop_def);

            result.value_ptr.* = ts;
        }
        return result.value_ptr;
    }

    pub fn getTypePropDef(self: *Self, type_hash: StrId32) ?[]const public.PropDef {
        var storage = self.getTypeStorage(type_hash) orelse return null;
        return storage.props_def;
    }

    pub fn addType(self: *Self, name: []const u8, prop_defs: []const public.PropDef) !StrId32 {
        for (prop_defs, 0..) |prop_def, real_idx| {
            std.debug.assert(prop_def.prop_idx == real_idx);
        }

        const type_hash = strId32(name);
        log.api.debug(MODULE_NAME, "Register type {s}:{d}", .{ name, type_hash.id });
        var storage = try self.getOrCreateTypeStorage(type_hash, name, prop_defs);
        _ = storage;
        return type_hash;
    }

    pub fn registerAllTypes(self: *Self) void {
        var it = apidb.api.getFirstImpl(public.CreateTypesI);
        while (it) |node| : (it = node.next) {
            var iface = cetech1.apidb.ApiDbAPI.toInterface(public.CreateTypesI, node);
            iface.create_types(@ptrCast(self));
        }
    }

    pub fn createObject(self: *Self, type_hash: StrId32) !public.ObjId {
        var storage = self.getTypeStorage(type_hash).?;
        return try storage.createObj();
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var storage = self.getTypeStorage(prototype.type_hash).?;
        return try storage.createObjectFromPrototype(prototype);
    }

    pub fn setDefaultObject(self: *Self, default: public.ObjId) void {
        var storage = self.getTypeStorage(default.type_hash).?;
        storage.setDefaultObject(default);
    }

    pub fn cloneObject(self: *Self, obj: public.ObjId) anyerror!public.ObjId { // TODO:why anyerorr?
        var storage = self.getTypeStorage(obj.type_hash).?;
        return storage.cloneObject(obj);
    }

    pub fn destroyObject(self: *Self, obj: public.ObjId) void {
        var storage = self.getTypeStorage(obj.type_hash) orelse return;
        storage.destroyObj(obj) catch |err| {
            log.api.warn(MODULE_NAME, "Error while destroing object: {}", .{err});
        };
    }

    pub fn writerObj(self: *Self, obj: public.ObjId) ?*public.Obj {
        _ = self.writers_count.fetchAdd(1, .Monotonic);

        var true_obj = self.getObjectPtr(obj);
        var storage = self.getTypeStorage(obj.type_hash) orelse return null;
        storage.increaseReference(obj);
        var new_obj = storage.cloneObjectRaw(true_obj.?, false, false) catch |err| {
            log.api.err(MODULE_NAME, "Could not crate writer {}", .{err});
            return null;
        };
        return @ptrCast(new_obj);
    }

    pub fn retargetWriter(self: *Self, writer: *public.Obj, obj: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        _ = storage.decreaseReferenceToFree(true_obj) catch undefined; // we increse this on creating writer.
        storage.increaseReference(obj);

        try storage.tranferObjIdReferencer(obj, true_obj.objid);

        var destination_obj = toObjFromObjO(self.readObj(obj).?);

        // set id from old (commit swap objects*)
        true_obj.objid = obj;

        // maybe we are in subobject relation.
        true_obj.parent = destination_obj.parent;
        true_obj.parent_prop_idx = destination_obj.parent_prop_idx;
    }

    pub fn writerCommit(self: *Self, writer: *public.Obj) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var new_obj = toObjFromObjO(writer);
        _ = self.write_commit_count.fetchAdd(1, .Monotonic);

        var storage = self.getTypeStorage(new_obj.objid.type_hash).?;
        _ = try storage.decreaseReferenceToFree(new_obj);

        var old_obj = storage.objid2obj.items[new_obj.objid.id].?;
        storage.objid2obj.items[new_obj.objid.id] = new_obj;
        storage.addToFreeQueue(old_obj) catch undefined;

        self.increaseVersionToAll(new_obj);
    }

    pub fn increaseVersionToAll(self: *Self, obj: *Object) void {
        // TODO: no recursion

        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        std.debug.assert(obj.objid.id != obj.parent.id or obj.objid.type_hash.id != obj.parent.type_hash.id);

        var storage = self.getTypeStorage(obj.objid.type_hash).?;
        storage.increaseVersion(obj.objid);

        // increase version for instances if any
        var instances = storage.prototype2instances.items[obj.objid.id];
        for (instances.keys()) |instance| {
            self.increaseVersionToAll(self.getObjectPtr(instance).?);
        }

        // increase version for parent
        if (obj.parent.id != 0) {
            self.increaseVersionToAll(self.getObjectPtr(obj.parent).?);
        }
    }

    pub fn readObj(self: *Self, obj: public.ObjId) ?*public.Obj {
        var true_obj = self.getObjectPtr(obj);
        _ = self.read_count.fetchAdd(1, .Monotonic);
        return @ptrCast(true_obj);
    }

    pub fn readGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, prop_type: public.PropType) []const u8 {
        var true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return storage.readGeneric(obj, prop_idx, prop_type);
    }

    pub fn readT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32) T {
        var true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return storage.readT(T, obj, prop_idx);
    }

    pub fn readSubObj(self: *Self, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
        var true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        const value = storage.readTT(public.ObjId, obj, prop_idx, public.PropType.SUBOBJECT);
        return if (value.isEmpty()) null else value;
    }

    pub fn readRef(self: *Self, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
        var true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        const value = storage.readTT(public.ObjId, obj, prop_idx, public.PropType.REFERENCE);
        return if (value.isEmpty()) null else value;
    }

    pub fn readStr(self: *Self, obj: *public.Obj, prop_idx: u32) ?[:0]const u8 {
        return self.readT(?[:0]u8, obj, prop_idx);
    }

    pub fn setGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, value: [*]const u8, prop_type: public.PropType) void {
        var true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        storage.setGeneric(obj, prop_idx, value, prop_type);
    }

    pub fn setT(self: *Self, comptime T: type, writer: *public.Obj, prop_idx: u32, value: T) void {
        var true_obj = toObjFromObjO(writer);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return storage.setT(T, writer, prop_idx, value);
    }

    pub fn setStr(self: *Self, writer: *public.Obj, prop_idx: u32, value: [:0]const u8) !void {
        var true_obj = toObjFromObjO(writer);

        var true_ptr = true_obj.getPropPtr([:0]u8, prop_idx);
        if (true_ptr.len != 0) {
            self.allocator.free(true_ptr.*);
        }

        true_ptr.* = (try self.allocator.dupeZ(u8, value));

        // If exist prototype set override flag to prop.
        if (true_obj.prototype_id != 0) {
            true_obj.overrides_set.set(prop_idx);
        }
    }

    pub fn setSubObj(self: *Self, writer: *public.Obj, prop_idx: u32, subobj_writer: *public.Obj) !void {
        var true_obj = toObjFromObjO(writer);
        var true_sub_obj = toObjFromObjO(subobj_writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_hash)) {
            log.api.warn(MODULE_NAME, "Invalid type_hash for set sub obj", .{});
            return;
        }

        const has_prototype = !self.getPrototype(writer).isEmpty();
        const is_overided = self.isPropertyOverrided(writer, prop_idx);

        if (!has_prototype and !is_overided) {
            if (self.readSubObj(writer, prop_idx)) |old_subobj| {
                var old_subobj_ptr = self.getObjectPtr(old_subobj).?;
                var old_subobj_storage = self.getTypeStorage(old_subobj.type_hash).?;
                _ = try old_subobj_storage.decreaseReferenceToFree(old_subobj_ptr);
            }
        }

        self.setParent(true_sub_obj, true_obj.objid, prop_idx);

        // var storage = self.getTypeStorage(true_sub_obj.objid.type_hash).?;
        // storage.increaseReference(true_sub_obj.objid);

        obj_storage.setTT(public.ObjId, writer, prop_idx, true_sub_obj.objid, public.PropType.SUBOBJECT);
    }

    pub fn clearSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var true_obj = toObjFromObjO(writer);

        const has_prototype = !self.getPrototype(writer).isEmpty();
        const is_overided = self.isPropertyOverrided(writer, prop_idx);

        if (!has_prototype and !is_overided) {
            if (self.readSubObj(writer, prop_idx)) |old_subobj| {
                var old_subobj_ptr = self.getObjectPtr(old_subobj).?;
                var old_subobj_storage = self.getTypeStorage(old_subobj.type_hash).?;
                _ = try old_subobj_storage.decreaseReferenceToFree(old_subobj_ptr);
            }
        }

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.SUBOBJECT);
    }

    pub fn clearRef(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_ptr = self.getObjectPtr(ref).?;
            var old_ref_storage = self.getTypeStorage(ref.type_hash).?;
            old_ref_storage.removeObjIdReferencer(ref, true_obj.objid);
            _ = try old_ref_storage.decreaseReferenceToFree(old_ref_ptr);
        }

        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.REFERENCE);
    }

    pub fn setRef(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, value.type_hash)) {
            log.api.warn(MODULE_NAME, "Invalid type_hash for set ref", .{});
            return;
        }

        var storage = self.getTypeStorage(value.type_hash).?;
        storage.increaseReference(value);
        try storage.addObjIdReferencer(value, true_obj.objid, prop_idx);

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_ptr = self.getObjectPtr(ref).?;
            var old_ref_storage = self.getTypeStorage(ref.type_hash).?;
            old_ref_storage.removeObjIdReferencer(ref, true_obj.objid);
            _ = try old_ref_storage.decreaseReferenceToFree(old_ref_ptr);
        }

        obj_storage.setTT(public.ObjId, writer, prop_idx, value, public.PropType.REFERENCE);
    }

    pub fn addRefToSet(self: *Self, writer: *public.Obj, prop_idx: u32, values: []const public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        if (builtin.mode == .Debug) {
            const real_type = obj_storage.props_def[prop_idx].type;
            std.debug.assert(real_type == public.PropType.REFERENCE_SET);
        } // else: just belive

        for (values) |value| {
            if (!obj_storage.isTypeHashValidForProperty(prop_idx, value.type_hash)) {
                log.api.warn(MODULE_NAME, "Invalid type_hash for add to ref set", .{});
                continue;
            }

            var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            if (!(try array.*.add(value))) {
                continue;
            }

            var storage = self.getTypeStorage(value.type_hash).?;
            storage.increaseReference(value);
            try storage.addObjIdReferencer(value, true_obj.objid, prop_idx);
        }
    }

    pub fn removeFromRefSet(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(value)) {
            var ref_obj_storage = self.getTypeStorage(value.type_hash).?;
            var ref_obj = self.getObjectPtr(value);
            ref_obj_storage.removeObjIdReferencer(value, true_obj.objid);
            _ = try ref_obj_storage.decreaseReferenceToFree(ref_obj.?);
        }
    }

    pub fn removeFromSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, sub_writer: *public.Obj) !void {
        //        _ = self;
        var true_obj = toObjFromObjO(writer);
        var true_sub_obj = toObjFromObjO(sub_writer);

        var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(true_sub_obj.objid)) {
            var ref_obj_storage = self.getTypeStorage(true_sub_obj.objid.type_hash).?;
            _ = try ref_obj_storage.decreaseReferenceToFree(true_sub_obj);
        }
    }

    pub fn createBlob(self: *Self, writer: *public.Obj, prop_idx: u32, size: usize) !?[]u8 {
        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        // var prev_blob = self.readBlob(writer, prop_idx);
        // obj_storage.destroyBlob(prev_blob);
        var prev_blob: *Blob = true_obj.getPropPtr(Blob, prop_idx);
        obj_storage.destroyBlob(prev_blob.*);

        var blob = try obj_storage.allocateBlob(size);
        obj_storage.setTT(Blob, writer, prop_idx, blob, public.PropType.BLOB);
        return blob;
    }

    pub fn readBlob(self: *Self, obj: *public.Obj, prop_idx: u32) []u8 {
        var true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        return storage.readTT([]u8, obj, prop_idx, public.PropType.BLOB);
    }

    pub fn readSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSet(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read suboj set {}", .{err});
            return null;
        };
    }

    pub fn readSubObjSetShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSetAddedShallow(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read suboj set {}", .{err});
            return null;
        };
    }

    pub fn readRefSetShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetAddedShallow(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read ref set {}", .{err});
            return null;
        };
    }

    pub fn readSubObjSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSetRemovedShallow(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read suboj set {}", .{err});
            return null;
        };
    }

    pub fn readRefSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetRemovedShallow(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read ref set {}", .{err});
            return null;
        };
    }

    pub fn readRefSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSet(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read ref set {}", .{err});
            return null;
        };
    }

    fn readSetAddedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        _ = self;
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);
        var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
        return try array.*.getAddedItems(allocator);
    }

    fn readSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        _ = self;
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);
        var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
        return try array.*.getRemovedItems(allocator);
    }

    fn readSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);

        // Fast path for non prototype
        if (true_obj.prototype_id == 0) {
            var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            return try array.*.getAddedItems(allocator);
        }

        var added = IdSet.init(allocator);
        var removed = IdSet.init(allocator);
        defer added.deinit();
        defer removed.deinit();

        var true_it_obj: ?*Object = true_obj;
        while (true_it_obj) |obj| {
            var set = obj.getPropPtr(*ObjIdSet, prop_idx);

            for (set.*.added.keys()) |value| {
                _ = try added.put(value, {});
            }
            for (set.*.removed.keys()) |value| {
                _ = try removed.put(value, {});
            }

            true_it_obj = self.getObjectPtr(obj.getPrototypeObjId());
        }

        var result = std.ArrayList(public.ObjId).init(allocator);
        for (added.keys()) |value| {
            if (removed.contains(value)) continue;
            try result.append(value);
        }

        return try result.toOwnedSlice();
    }

    pub fn addToSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, sub_obj_writers: []const *public.Obj) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        if (builtin.mode == .Debug) {
            const real_type = obj_storage.props_def[prop_idx].type;
            std.debug.assert(real_type == public.PropType.SUBOBJECT_SET);
        } // else: just belive

        for (sub_obj_writers) |sub_obj_writer| {
            var true_sub_obj = toObjFromObjO(sub_obj_writer);
            if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_hash)) {
                log.api.warn(MODULE_NAME, "Invalid type_hash for add to subobj set", .{});
                continue;
            }

            var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            if (!try array.*.add(true_sub_obj.objid)) {
                // exist
                continue;
            }

            self.setParent(true_sub_obj, true_obj.objid, prop_idx);

            // var storage = self.getTypeStorage(true_sub_obj.objid.type_hash).?;
            // storage.increaseReference(true_sub_obj.objid);
        }
    }

    fn resetPropertyOveride(self: *Self, writer: *public.Obj, prop_idx: u32) void {
        _ = self;
        var obj_ptr = toObjFromObjO(writer);
        if (obj_ptr.prototype_id == 0) return;
        obj_ptr.overrides_set.unset(prop_idx);
    }

    pub fn isPropertyOverrided(self: *Self, obj: *public.Obj, prop_idx: u32) bool {
        var true_obj = toObjFromObjO(obj);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return obj_storage.isPropertyOverrided(obj, prop_idx);
    }

    pub fn getPrototype(self: *Self, obj: *public.Obj) public.ObjId {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        return true_obj.getPrototypeObjId();
    }

    pub fn instantiateSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        try obj_storage.instantiateSubObj(writer, prop_idx);
    }

    pub fn instantiateSubObjFromSet(self: *Self, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
        var true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return obj_storage.instantiateSubObjFromSet(writer, prop_idx, set_obj);
    }

    fn isIinisiated(self: *Self, obj: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) bool {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        var true_inisiated_obj = toObjFromObjO(inisiated_obj);

        if (true_obj.prototype_id == 0) return false;

        var idset = true_obj.getPropPtr(*ObjIdSet, set_prop_idx);

        const protoype_id = .{
            .id = true_inisiated_obj.prototype_id,
            .type_hash = true_inisiated_obj.objid.type_hash,
        };

        return idset.*.added.contains(true_inisiated_obj.objid) and idset.*.removed.contains(protoype_id);
    }

    pub fn stressIt(self: *Self, type_hash: cetech1.strid.StrId32, type_hash2: cetech1.strid.StrId32, ref_obj1: cetech1.cdb.ObjId) !void {
        var obj1 = try self.createObject(type_hash);

        var obj2 = try self.createObject(type_hash2);
        var obj3 = try self.createObject(type_hash2);

        var writer = self.writerObj(obj1).?;

        self.setT(bool, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.BOOL), true);
        self.setT(u64, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.U64), 10);
        self.setT(i64, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.I64), 20);
        self.setT(u32, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.U32), 10);
        self.setT(i32, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.I32), 20);
        self.setT(f64, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.F64), 20.10);
        self.setT(f32, writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.F32), 30.20);
        try self.setRef(writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.REFERENCE), ref_obj1);
        try self.addRefToSet(writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.REFERENCE_SET), &[_]public.ObjId{ref_obj1});

        var writer2 = self.writerObj(obj2).?;
        try self.setSubObj(writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.SUBOBJECT), writer2);
        try self.writerCommit(writer2);

        var writer3 = self.writerObj(obj3).?;
        try self.addToSubObjSet(writer, cetech1.cdb.propIdx(cetech1.cdb.BigTypeProps.SUBOBJECT_SET), &[_]*public.Obj{writer3});
        try self.writerCommit(writer3);

        try self.writerCommit(writer);

        _ = self.getVersion(obj1);

        self.destroyObject(obj1);
        self.destroyObject(obj2);
        self.destroyObject(obj3);
    }

    pub fn getReferencerSet(self: *Self, obj: public.ObjId, allocator: std.mem.Allocator) ![]public.ObjId {
        var storage = self.getTypeStorage(obj.type_hash).?;
        const keys = storage.objid2refs.items[obj.id].keys();
        var new_set = try allocator.alloc(public.ObjId, keys.len);
        @memcpy(new_set, keys);
        return new_set;
    }
};

var _allocator: std.mem.Allocator = undefined;
var _first_db: ?*Db = null;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
}

pub fn deinit() void {}

pub inline fn toDbFromDbT(db: *public.Db) *Db {
    return @alignCast(@ptrCast(db));
}

pub fn registerToApi() !void {
    try apidb.api.setOrRemoveZigApi(public.CdbAPI, &api, true);
}

pub fn registerAllTypes() void {
    var it = apidb.api.getFirstImpl(public.CreateTypesI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.CreateTypesI, node);

        var db_it = _first_db;
        while (db_it) |db_node| : (db_it = db_node.next) {
            iface.create_types(@ptrCast(db_node));
        }
    }
}

pub var api = public.CdbAPI{
    .createDbFn = createDb,
    .destroyDbFn = destroyDb,
    .addTypeFn = addType,
    .getTypePropDefFn = getTypePropDef,
    .getTypeNameFn = getTypeName,
    .getTypePropDefIdxFn = getTypePropDefIdx,
    .addAspectFn = addAspect,
    .getAspectFn = getAspect,

    .addPropertyAspectFn = addPropertyAspect,
    .getPropertyAspectFn = getPropertyAspect,

    .getReferencerSetFn = getReferencerSet,
    .createObjectFn = createObject,
    .createObjectFromPrototypeFn = createObjectFromPrototype,
    .cloneObjectFn = cloneObject,
    .destroyObjectFn = destroyObject,
    .setDefaultObjectFn = setDefaultObject,
    .readObjFn = readObj,
    .getParentFn = getParent,
    .getVersionFn = getVersion,

    .writeObjFn = writerObj,
    .writeCommitFn = writerCommit,
    .retargetWriteFn = retargetWrite,

    .readGenericFn = @ptrCast(&Db.readGeneric),
    .setGenericFn = @ptrCast(&Db.setGeneric),
    .setStrFn = @ptrCast(&Db.setStr),

    .readSubObjFn = readSubObj,
    .setSubObjFn = setSubObj,
    .clearSubObjFn = clearSubObj,

    .readRefFn = readRef,
    .setRefFn = setRef,
    .clearRefFn = clearRef,

    .addRefToSetFn = addRefToSet,
    .readRefSetFn = readRefSet,
    .readRefSetAddedFn = readRefSetShallow,
    .readRefSetRemovedFn = readRefSetRemovedShallow,
    .removeFromRefSetFn = removeFromRefSet,

    .addSubObjToSetFn = addSubObjToSet,
    .readSubObjSetFn = readSubObjSet,
    .readSubObjSetAddedFn = readSubObjSetShallow,
    .readSubObjSetRemovedFn = readSubObjSetRemovedShallow,
    .removeFromSubObjSetFn = removeFromSubObjSet,

    .createBlobFn = createBlob,
    .readBlobFn = readBlob,

    .resetPropertyOverideFn = resetPropertyOverride,
    .isPropertyOverridedFn = isPropertyOverrided,
    .getPrototypeFn = getPrototype,
    .instantiateSubObjFn = instantiateSubObj,
    .instantiateSubObjFromSetFn = instantiateSubObjFromSet,

    .stressItFn = @ptrCast(&Db.stressIt),

    .addOnObjIdDestroyedFn = addOnObjIdDestroyed,
    .removeOnObjIdDestroyedFn = removeOnObjIdDestroyed,

    .gcFn = gc,

    .isIinisiatedFn = isIinisiated,
};

fn isIinisiated(db_: *public.Db, obj: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) bool {
    var db = toDbFromDbT(db_);
    return db.isIinisiated(obj, set_prop_idx, inisiated_obj);
}

fn createDb(name: [:0]const u8) !*public.Db {
    var db = try _allocator.create(Db);
    db.* = Db.init(_allocator, name);

    if (_first_db == null) {
        _first_db = db;
    } else {
        db.next = _first_db;
        _first_db.?.prev = db;
    }

    db.registerAllTypes();

    return @ptrCast(db);
}

fn destroyDb(db_: *public.Db) void {
    var db = toDbFromDbT(db_);

    db.deinit();

    if (db.prev != null) {
        db.prev.?.next = db.next;
    } else {
        _first_db = db.next;
    }

    if (db.next != null) {
        db.next.?.prev = db.prev;
    }

    _allocator.destroy(db);
}

fn gc(db_: *public.Db, tmp_allocator: std.mem.Allocator) !void {
    var db = toDbFromDbT(db_);
    try db.gc(tmp_allocator);
}

fn getTypePropDef(db_: *public.Db, type_hash: StrId32) ?[]const public.PropDef {
    var db = toDbFromDbT(db_);
    return db.getTypePropDef(type_hash);
}

fn addType(db_: *public.Db, name: []const u8, prop_def: []const public.PropDef) !StrId32 {
    var db = toDbFromDbT(db_);
    return db.addType(name, prop_def);
}

fn getTypeName(db_: *public.Db, type_hash: StrId32) ?[]const u8 {
    var db = toDbFromDbT(db_);
    return db.getTypeName(type_hash);
}

fn getTypePropDefIdx(db_: *public.Db, type_hash: strid.StrId32, prop_name: []const u8) ?u32 {
    var db = toDbFromDbT(db_);
    return db.getTypePropDefIdx(type_hash, prop_name);
}

fn createObject(db_: *public.Db, type_hash: StrId32) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.createObject(type_hash);
}

fn createObjectFromPrototype(db_: *public.Db, prototype: public.ObjId) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.createObjectFromPrototype(prototype);
}

fn cloneObject(db_: *public.Db, obj: public.ObjId) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.cloneObject(obj);
}
fn setDefaultObject(db_: *public.Db, obj: public.ObjId) void {
    var db = toDbFromDbT(db_);
    return db.setDefaultObject(obj);
}

fn destroyObject(db_: *public.Db, obj: public.ObjId) void {
    var db = toDbFromDbT(db_);
    return db.destroyObject(obj);
}

fn readObj(db_: *public.Db, obj: public.ObjId) ?*public.Obj {
    var db = toDbFromDbT(db_);
    return db.readObj(obj);
}

fn getParent(db_: *public.Db, obj: *public.Obj) public.ObjId {
    var db = toDbFromDbT(db_);
    var true_obj = toObjFromObjO(obj);
    return db.getParent(true_obj.objid);
}

fn getVersion(db_: *public.Db, obj: public.ObjId) u64 {
    var db = toDbFromDbT(db_);
    return db.getVersion(obj);
}

fn writerObj(db_: *public.Db, obj: public.ObjId) ?*public.Obj {
    var db = toDbFromDbT(db_);
    return db.writerObj(obj);
}

fn writerCommit(db_: *public.Db, writer: *public.Obj) void {
    var db = toDbFromDbT(db_);
    return db.writerCommit(writer) catch undefined;
}

fn retargetWrite(db_: *public.Db, writer: *public.Obj, obj: public.ObjId) !void {
    var db = toDbFromDbT(db_);
    try db.retargetWriter(writer, obj);
}

fn addAspect(db_: *public.Db, type_hash: StrId32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
    var db = toDbFromDbT(db_);
    return db.addAspect(type_hash, apect_name, aspect_ptr);
}

fn getAspect(db_: *public.Db, type_hash: StrId32, aspect_hash: StrId32) ?*anyopaque {
    var db = toDbFromDbT(db_);
    return db.getAspect(type_hash, aspect_hash);
}

fn addPropertyAspect(db_: *public.Db, type_hash: StrId32, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
    var db = toDbFromDbT(db_);
    return db.addPropertyAspect(type_hash, prop_idx, apect_name, aspect_ptr);
}

fn getPropertyAspect(db_: *public.Db, type_hash: StrId32, prop_idx: u32, aspect_hash: StrId32) ?*anyopaque {
    var db = toDbFromDbT(db_);
    return db.getPropertyAspect(type_hash, prop_idx, aspect_hash);
}

pub fn getReferencerSet(db_: *public.Db, obj: public.ObjId, allocator: std.mem.Allocator) ![]public.ObjId {
    var db = toDbFromDbT(db_);
    return db.getReferencerSet(obj, allocator);
}

fn readSubObj(db_: *public.Db, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readSubObj(obj, prop_idx);
}

fn readRef(db_: *public.Db, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readRef(obj, prop_idx);
}

fn setSubObj(db_: *public.Db, obj: *public.Obj, prop_idx: u32, subobj_writer: *public.Obj) !void {
    var db = toDbFromDbT(db_);
    return db.setSubObj(obj, prop_idx, subobj_writer);
}

fn clearSubObj(db_: *public.Db, obj: *public.Obj, prop_idx: u32) !void {
    var db = toDbFromDbT(db_);
    try db.clearSubObj(obj, prop_idx);
}

fn setRef(db_: *public.Db, obj: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
    var db = toDbFromDbT(db_);
    return db.setRef(obj, prop_idx, value);
}

fn clearRef(db_: *public.Db, obj: *public.Obj, prop_idx: u32) !void {
    var db = toDbFromDbT(db_);
    try db.clearRef(obj, prop_idx);
}

fn addRefToSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, values: []const public.ObjId) !void {
    var db = toDbFromDbT(db_);
    try db.addRefToSet(obj, prop_idx, values);
}

fn readRefSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readRefSet(obj, prop_idx, allocator);
}

fn readRefSetShallow(db_: *public.Db, obj: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readRefSetShallow(obj, prop_idx, allocator);
}

fn readRefSetRemovedShallow(db_: *public.Db, obj: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readRefSetRemovedShallow(obj, prop_idx, allocator);
}

fn removeFromRefSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
    var db = toDbFromDbT(db_);
    try db.removeFromRefSet(obj, prop_idx, value);
}

fn addSubObjToSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, subobj_writers: []const *public.Obj) !void {
    var db = toDbFromDbT(db_);
    try db.addToSubObjSet(obj, prop_idx, subobj_writers);
}

fn readSubObjSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readSubObjSet(obj, prop_idx, allocator);
}

fn readSubObjSetShallow(db_: *public.Db, obj: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readSubObjSetShallow(obj, prop_idx, allocator);
}

fn readSubObjSetRemovedShallow(db_: *public.Db, obj: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = toDbFromDbT(db_);
    return db.readSubObjSetRemovedShallow(obj, prop_idx, allocator);
}

fn removeFromSubObjSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, sub_obj: *public.Obj) !void {
    var db = toDbFromDbT(db_);
    try db.removeFromSubObjSet(obj, prop_idx, sub_obj);
}

fn createBlob(db_: *public.Db, obj: *public.Obj, prop_idx: u32, size: usize) !?[]u8 {
    var db = toDbFromDbT(db_);
    return try db.createBlob(obj, prop_idx, size);
}

fn readBlob(db_: *public.Db, obj: *public.Obj, prop_idx: u32) []u8 {
    var db = toDbFromDbT(db_);
    return db.readBlob(obj, prop_idx);
}

fn resetPropertyOverride(db_: *public.Db, obj: *public.Obj, prop_idx: u32) void {
    var db = toDbFromDbT(db_);
    db.resetPropertyOveride(obj, prop_idx);
}

fn isPropertyOverrided(db_: *public.Db, obj: *public.Obj, prop_idx: u32) bool {
    var db = toDbFromDbT(db_);
    return db.isPropertyOverrided(obj, prop_idx);
}

pub fn getPrototype(db_: *public.Db, obj: *public.Obj) public.ObjId {
    var db = toDbFromDbT(db_);
    return db.getPrototype(obj);
}

pub fn instantiateSubObj(db_: *public.Db, writer: *public.Obj, prop_idx: u32) !void {
    var db = toDbFromDbT(db_);
    return db.instantiateSubObj(writer, prop_idx);
}

pub fn instantiateSubObjFromSet(db_: *public.Db, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.instantiateSubObjFromSet(writer, prop_idx, set_obj);
}

pub fn addOnObjIdDestroyed(db_: *public.Db, fce: public.OnObjIdDestroyed) !void {
    var db = toDbFromDbT(db_);
    try db.addOnObjIdDestroyed(fce);
}
pub fn removeOnObjIdDestroyed(db_: *public.Db, fce: public.OnObjIdDestroyed) void {
    var db = toDbFromDbT(db_);
    db.removeOnObjIdDestroyed(fce);
}

// Assert C and Zig Enums
comptime {
    std.debug.assert(c.CT_CDB_TYPE_NONE == @intFromEnum(public.PropType.NONE));
    std.debug.assert(c.CT_CDB_TYPE_BOOL == @intFromEnum(public.PropType.BOOL));
    std.debug.assert(c.CT_CDB_TYPE_U64 == @intFromEnum(public.PropType.U64));
    std.debug.assert(c.CT_CDB_TYPE_I64 == @intFromEnum(public.PropType.I64));
    std.debug.assert(c.CT_CDB_TYPE_U32 == @intFromEnum(public.PropType.U32));
    std.debug.assert(c.CT_CDB_TYPE_I32 == @intFromEnum(public.PropType.I32));
    std.debug.assert(c.CT_CDB_TYPE_F32 == @intFromEnum(public.PropType.F32));
    std.debug.assert(c.CT_CDB_TYPE_F64 == @intFromEnum(public.PropType.F64));
    std.debug.assert(c.CT_CDB_TYPE_STR == @intFromEnum(public.PropType.STR));
    std.debug.assert(c.CT_CDB_TYPE_BLOB == @intFromEnum(public.PropType.BLOB));
    std.debug.assert(c.CT_CDB_TYPE_SUBOBJECT == @intFromEnum(public.PropType.SUBOBJECT));
    std.debug.assert(c.CT_CDB_TYPE_REFERENCE == @intFromEnum(public.PropType.REFERENCE));
    std.debug.assert(c.CT_CDB_TYPE_SUBOBJECT_SET == @intFromEnum(public.PropType.SUBOBJECT_SET));
    std.debug.assert(c.CT_CDB_TYPE_REFERENCE_SET == @intFromEnum(public.PropType.REFERENCE_SET));
}

test "cdb: Test alocate/free id" {
    try cdb_test.testInit();
    defer cdb_test.testDeinit();

    var db = try api.createDb("Test");
    defer api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &[_]cetech1.cdb.PropDef{},
    );
    _ = type_hash;

    var _db = toDbFromDbT(db.db);
    var storage = _db.getTypeStorage(strId32("foo")).?;

    // Allocate two IDs
    var obj1 = try storage.allocateObjId();
    var obj2 = try storage.allocateObjId();
    try std.testing.expect(obj1.id != obj2.id);
    try std.testing.expectEqual(@as(u32, 1), obj1.id);
    try std.testing.expectEqual(@as(u32, 2), obj2.id);

    // Free one and alocate one then has same ID because free pool.
    try storage.freeObjId(obj2);
    var obj3 = try storage.allocateObjId();
    try std.testing.expectEqual(@as(u32, obj2.id), obj3.id);

    var obj4 = try storage.allocateObjId();
    try std.testing.expectEqual(@as(u32, 3), obj4.id);
}

test "cdb: Test alocate/free idset" {
    try cdb_test.testInit();
    defer cdb_test.testDeinit();

    var db = try api.createDb("Test");
    defer api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &[_]cetech1.cdb.PropDef{},
    );
    _ = type_hash;

    var _db = toDbFromDbT(db.db);
    var storage = _db.getTypeStorage(strId32("foo")).?;

    var array = try storage.allocateObjIdSet();

    // can add items
    try std.testing.expect(try array.add(public.ObjId{ .type_hash = .{ .id = 0 }, .id = 0 }));
    try std.testing.expect(try array.add(public.ObjId{ .type_hash = .{ .id = 0 }, .id = 1 }));
    try std.testing.expect(try array.add(public.ObjId{ .type_hash = .{ .id = 0 }, .id = 2 }));

    //try std.testing.expect(array.list.items.len == 3);

    // can destroy list
    try storage.destroyObjIdSet(array);
}

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_cdb_create_types_i) == @sizeOf(public.CreateTypesI));
}
