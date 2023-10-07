// NOTE: Braindump shit, features first for api then optimize internals.

const builtin = @import("builtin");
const std = @import("std");

const c = @import("../c.zig");
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
const IdSetPool = cetech1.mem.VirtualPool(ObjIdSet);
const OverridesSet = std.bit_set.DynamicBitSet;

const AtomicInt = std.atomic.Atomic(u32);
const TypeStorageMap = std.AutoArrayHashMap(StrId32, TypeStorage);
const Uuid2ObjId = std.AutoArrayHashMap(cetech1.uuid.Uuid, public.ObjId);
const ToFreeIdQueue = std.atomic.Queue(*Object);
const FreeIdQueueNodePool = cetech1.mem.PoolWithLock(cetech1.FreeIdQueue.Node);
const ToFreeIdQueueNodePool = cetech1.mem.PoolWithLock(ToFreeIdQueue.Node);

const TypeAspectMap = std.AutoArrayHashMap(StrId32, *anyopaque);
const PropertyAspectPair = struct { StrId32, u32 };
const PropertyTypeAspectMap = std.AutoArrayHashMap(PropertyAspectPair, *anyopaque);

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
        public.PropType.REFERENCE_SET => makeTypeTuple(*ObjIdSet),
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
        else => unreachable,
    };
}

//TODO: Optimize memory footprint
pub const Object = struct {
    const Self = @This();

    // ObjId associated with this Object.
    // ObjId can have multiple object because write clone entire obj.
    objid: public.ObjId = .{}, // TODO

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

    pub fn getItems(self: *Self, allocator: std.mem.Allocator) ![]public.ObjId {
        var new = try allocator.alloc(public.ObjId, self.added.count());
        @memcpy(new, self.added.keys());
        return new;
    }
};

pub const TypeStorage = struct {
    const Self = @This();

    const MAX_OBJECTS = 1_000_000; // TODO: From max ID
    const MAX_OBJIDSETS = 1_000_000;

    allocator: std.mem.Allocator,
    db: *Db,

    // Type data
    name: []const u8,
    type_hash: StrId32,
    props_def: []const public.PropDef,
    props_size: usize,
    prop_offset: std.ArrayList(usize),

    default_obj: public.ObjId = public.OBJID_ZERO,

    // Per ObjectId data
    objid_pool: cetech1.mem.IdPool(u32),
    objid2obj: cetech1.mem.VirtualArray(?*Object),
    objid_ref_count: cetech1.mem.VirtualArray(AtomicInt),
    objid2uuid: cetech1.mem.VirtualArray(cetech1.uuid.Uuid),

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

        return .{
            .db = db,
            .name = name,
            .type_hash = strId32(name),
            .props_def = props_def,
            .allocator = allocator,
            .object_pool = cetech1.mem.VirtualPool(Object).init(allocator, MAX_OBJECTS),

            .objid2obj = cetech1.mem.VirtualArray(?*Object).init(MAX_OBJECTS),
            .objid_pool = cetech1.mem.IdPool(u32).init(allocator),
            .objid_ref_count = cetech1.mem.VirtualArray(AtomicInt).init(MAX_OBJECTS),
            .objid2uuid = cetech1.mem.VirtualArray(cetech1.uuid.Uuid).init(MAX_OBJECTS),
            .objs_mem = cetech1.mem.VirtualArray(u8).init(MAX_OBJECTS * props_size),

            .to_free_queue = ToFreeIdQueue.init(),
            .to_free_obj_node_pool = ToFreeIdQueueNodePool.init(allocator),

            .idset_pool = IdSetPool.init(allocator, MAX_OBJIDSETS),

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

        self.prop_offset.deinit();
        self.object_pool.deinit();
        self.objid_pool.deinit();
        self.to_free_obj_node_pool.deinit();
        self.idset_pool.deinit();
        self.objid2obj.deinit();
        self.objs_mem.deinit();
        self.aspect_map.deinit();
        self.property_aspect_map.deinit();
        self.objid2uuid.deinit();
    }

    pub fn isTypeHashValidForProperty(self: *Self, prop_idx: u32, type_hash: StrId32) bool {
        if (self.props_def[prop_idx].type_hash.id == 0) return true;
        return std.meta.eql(self.props_def[prop_idx].type_hash, type_hash);
    }

    fn allocateObjId(self: *Self, with_uuid: ?cetech1.uuid.Uuid) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var id = self.objid_pool.create(null);
        self.objid_ref_count.items[id] = AtomicInt.init(1);
        self.objid2uuid.items[id] = with_uuid orelse uuid.api.newUUID7();

        const objid = .{ .id = id, .type_hash = self.type_hash };

        try self.db.mapUuidToObjid(self.objid2uuid.items[id], objid);

        return objid;
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

    fn decreaseReferenceFree(self: *Self, object: *Object, tmp_allocator: std.mem.Allocator) anyerror!u32 {
        var ref_count = &self.objid_ref_count.items[object.objid.id];

        if (ref_count.value == 0) return 0; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        if (1 == ref_count.fetchSub(1, .Release)) {
            ref_count.fence(.Acquire);
            return try self.freeObject(object, tmp_allocator);
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
        try self.db.unmapUuid(self.db.getUuid(objid));
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

    pub fn createObj(self: *Self, with_uuid: ?cetech1.uuid.Uuid) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (!self.default_obj.isEmpty()) {
            return self.cloneObject(self.default_obj, with_uuid);
        }

        var id = try self.allocateObjId(with_uuid);
        var obj = try self.allocateObject(id, true);

        self.objid2obj.items[id.id] = obj;
        obj.parent = .{};

        return .{ .id = id.id, .type_hash = self.type_hash };
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var prototype_obj = self.db.getObjectPtr(prototype).?;
        var new_object = try self.cloneObjectRaw(prototype_obj, true, null);
        new_object.prototype_id = prototype_obj.objid.id;
        return new_object.objid;
    }

    pub fn cloneObject(self: *Self, boj: public.ObjId, with_uuid: ?cetech1.uuid.Uuid) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var prototype_obj = self.db.getObjectPtr(boj).?;
        var new_object = try self.cloneObjectRaw(prototype_obj, true, with_uuid);
        return new_object.objid;
    }

    pub fn destroyObj(self: *Self, obj: public.ObjId) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = self.objid2obj.items[obj.id];
        if (true_obj == null) return;
        try self.decreaseReferenceToFree(true_obj.?);
    }

    pub fn cloneObjectRaw(self: *Self, obj: *Object, create_new: bool, with_uuid: ?cetech1.uuid.Uuid) !*Object {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var obj_id = if (!create_new) obj.objid else try self.allocateObjId(with_uuid);
        var new_obj = try self.allocateObject(obj_id, false);

        if (!create_new) {
            new_obj.prototype_id = obj.prototype_id;
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

                // Increase ref
                public.PropType.SUBOBJECT, public.PropType.REFERENCE => {
                    var true_ptr = new_obj.getPropPtr(public.ObjId, idx);
                    if (true_ptr.*.id == 0) continue;
                    var storage = self.db.getTypeStorage(true_ptr.*.type_hash).?;
                    storage.increaseReference(true_ptr.*);
                },

                // Duplicate set and increase ref
                public.PropType.REFERENCE_SET, public.PropType.SUBOBJECT_SET => {
                    var true_ptr = new_obj.getPropPtr(*ObjIdSet, idx);
                    true_ptr.* = try self.cloneIdSet(true_ptr.*, create_new);

                    var set = try true_ptr.*.getItems(self.allocator);
                    defer self.allocator.free(set);
                    for (set) |ref| {
                        var storage = self.db.getTypeStorage(ref.type_hash).?;
                        _ = storage;
                        //storage.increaseReference(ref);
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

    pub fn freeObject(self: *Self, obj: *Object, tmp_allocator: std.mem.Allocator) !u32 {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var free_objects: u32 = 1;
        for (self.props_def, 0..) |prop_def, idx| {
            switch (prop_def.type) {
                public.PropType.STR => {
                    var true_ptr = obj.getPropPtr([:0]u8, idx);
                    if (true_ptr.len != 0) {
                        self.allocator.free(true_ptr.*);
                    }
                },
                public.PropType.SUBOBJECT => {
                    var subobj = obj.getPropPtr(public.ObjId, idx);
                    var subobj_ptr = self.db.getObjectPtr(subobj.*) orelse continue;
                    var storage = self.db.getTypeStorage(subobj_ptr.objid.type_hash).?;
                    free_objects += try storage.decreaseReferenceFree(subobj_ptr, tmp_allocator);
                },
                public.PropType.REFERENCE => {
                    var ref = obj.getPropPtr(public.ObjId, idx);
                    var ref_ptr = self.db.getObjectPtr(ref.*) orelse continue;
                    var storage = self.db.getTypeStorage(ref_ptr.objid.type_hash).?;
                    free_objects += try storage.decreaseReferenceFree(ref_ptr, tmp_allocator);
                },
                public.PropType.REFERENCE_SET => {
                    var true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    var set = try true_ptr.*.getItems(tmp_allocator);
                    defer tmp_allocator.free(set);
                    for (set) |ref_id| {
                        var ref_ptr = self.db.getObjectPtr(ref_id) orelse continue;
                        var storage = self.db.getTypeStorage(ref_ptr.objid.type_hash).?;
                        free_objects += try storage.decreaseReferenceFree(ref_ptr, tmp_allocator);
                    }
                    try self.destroyObjIdSet(true_ptr.*);
                },
                public.PropType.SUBOBJECT_SET => {
                    var true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    var set = try true_ptr.*.getItems(tmp_allocator);
                    defer tmp_allocator.free(set);

                    for (set) |subobj| {
                        var subobj_ptr = self.db.getObjectPtr(subobj) orelse continue;
                        var storage = self.db.getTypeStorage(subobj.type_hash).?;
                        free_objects += try storage.decreaseReferenceFree(subobj_ptr, tmp_allocator);
                    }
                    try self.destroyObjIdSet(true_ptr.*);
                },
                public.PropType.BLOB => {
                    var true_ptr = obj.getPropPtr(Blob, idx);
                    self.destroyBlob(true_ptr.*);
                },
                else => continue,
            }
        }

        if (!obj.parent.isEmpty()) {
            var parent_obj = self.db.getObjectPtr(obj.parent);
            var storage = self.db.getTypeStorage(obj.parent.type_hash).?;
            var ref_count = &storage.objid_ref_count.items[obj.parent.id];

            if (ref_count.value != 0) {
                switch (self.props_def[obj.parent_prop_idx].type) {
                    public.PropType.SUBOBJECT => try self.db.clearSubObj(@ptrCast(parent_obj.?), obj.parent_prop_idx),
                    public.PropType.SUBOBJECT_SET => try self.db.removeFromSubObjSet(@ptrCast(parent_obj.?), obj.parent_prop_idx, @ptrCast(obj)),
                    else => undefined,
                }
            }
            obj.parent = .{};
        }

        if (self.objid2obj.items[obj.objid.id] == obj) {
            try self.freeObjId(obj.objid);
            self.objid2obj.items[obj.objid.id] = null;
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

        var free_objects: u32 = 0;
        while (self.to_free_queue.get()) |node| {
            free_objects += try self.freeObject(node.data, tmp_allocator);
            self.to_free_obj_node_pool.destroy(node);
        }
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
        return (true_obj.prototype_id != 0 and true_obj.overrides_set.isSet(prop_idx));
    }

    pub fn instantiateSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const value = self.readTT(public.ObjId, writer, prop_idx, public.PropType.SUBOBJECT);
        if (value.isEmpty()) return;

        var storage = self.db.getTypeStorage(value.type_hash).?;
        var new_subobj = try storage.createObjectFromPrototype(value);
        //self.setTT(public.CdbObjIdT, writer, prop_idx, c.c.CT_CDB_OBJID_ZERO, public.PropertyType.SUBOBJECT);
        try self.db.setSubObj(writer, prop_idx, @ptrCast(self.db.getObjectPtr(new_subobj).?));
    }
};

pub const Db = struct {
    const Self = @This();

    name: [:0]const u8,

    allocator: std.mem.Allocator,
    typestorage_map: TypeStorageMap,
    prev: ?*Db = null,
    next: ?*Db = null,

    uuid2objid: Uuid2ObjId,
    uuid2objid_lock: std.Thread.Mutex,

    // Stats
    write_commit_count: AtomicInt,
    writers_count: AtomicInt,
    read_count: AtomicInt,
    free_objects: u32,
    obj_alocated: u32,

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

            .uuid2objid = Uuid2ObjId.init(allocator),
            .uuid2objid_lock = std.Thread.Mutex{},
            .write_commit_count = AtomicInt.init(0),
            .writers_count = AtomicInt.init(0),
            .read_count = AtomicInt.init(0),
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

        self.typestorage_map.deinit();
        self.uuid2objid.deinit();
    }

    pub fn mapUuidToObjid(self: *Self, obj_uuid: cetech1.uuid.Uuid, objid: public.ObjId) !void {
        self.uuid2objid_lock.lock();
        defer self.uuid2objid_lock.unlock();
        try self.uuid2objid.put(obj_uuid, objid);
    }

    pub fn unmapUuid(self: *Self, obj_uuid: cetech1.uuid.Uuid) !void {
        self.uuid2objid_lock.lock();
        defer self.uuid2objid_lock.unlock();
        _ = self.uuid2objid.swapRemove(obj_uuid);
    }

    pub fn getObjIdFromUuid(self: *Self, obj_uuid: cetech1.uuid.Uuid) ?public.ObjId {
        self.uuid2objid_lock.lock();
        defer self.uuid2objid_lock.unlock();
        return self.uuid2objid.get(obj_uuid);
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

        self.write_commit_count = AtomicInt.init(0);
        self.writers_count = AtomicInt.init(0);
        self.read_count = AtomicInt.init(0);
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

    pub fn getOrCreateTypeStorage(self: *Self, type_hash: StrId32, name: []const u8, prop_def: []const public.PropDef) !*TypeStorage {
        var result = try self.typestorage_map.getOrPut(type_hash);
        if (!result.found_existing) {
            result.value_ptr.* = try TypeStorage.init(_allocator, self, name, prop_def);
        }
        return result.value_ptr;
    }

    pub fn getTypePropDef(self: *Self, type_hash: StrId32) ?[]const public.PropDef {
        var storage = self.getTypeStorage(type_hash) orelse return null;
        return storage.props_def;
    }

    pub fn addType(self: *Self, name: []const u8, prop_def: []const public.PropDef) !StrId32 {
        const type_hash = strId32(name);
        log.api.debug(MODULE_NAME, "Register type {s}:{d}", .{ name, type_hash.id });
        var storage = try self.getOrCreateTypeStorage(type_hash, name, prop_def);
        storage.props_def = prop_def;

        return type_hash;
    }

    pub fn registerAllTypes(self: *Self) void {
        var it = apidb.api.getFirstImpl(c.c.ct_cdb_create_types_i);
        while (it) |node| : (it = node.next) {
            var iface = cetech1.apidb.ApiDbAPI.toInterface(c.c.ct_cdb_create_types_i, node);
            iface.create_types.?(@ptrCast(self));
        }
    }

    pub fn createObject(self: *Self, type_hash: StrId32) !public.ObjId {
        var storage = self.getTypeStorage(type_hash).?;
        return try storage.createObj(null);
    }

    pub fn createObjectWithUuid(self: *Self, type_hash: StrId32, with_uuid: cetech1.uuid.Uuid) !public.ObjId {
        var storage = self.getTypeStorage(type_hash).?;
        return try storage.createObj(with_uuid);
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var storage = self.getTypeStorage(prototype.type_hash).?;
        return try storage.createObjectFromPrototype(prototype);
    }

    pub fn setDefaultObject(self: *Self, default: public.ObjId) void {
        var storage = self.getTypeStorage(default.type_hash).?;
        storage.setDefaultObject(default);
    }

    pub fn cloneObject(self: *Self, obj: public.ObjId) !public.ObjId {
        var storage = self.getTypeStorage(obj.type_hash).?;
        return try storage.createObjectFromPrototype(obj);
    }

    pub fn destroyObject(self: *Self, obj: public.ObjId) void {
        var storage = self.getTypeStorage(obj.type_hash) orelse return;
        storage.destroyObj(obj) catch |err| {
            log.api.warn(MODULE_NAME, "Error while destroing object: {}", .{err});
        };
    }

    pub fn getUuid(self: *Self, objid: public.ObjId) cetech1.uuid.Uuid {
        var storage = self.getTypeStorage(objid.type_hash) orelse return .{};
        return storage.objid2uuid.items[objid.id];
    }

    pub fn writerObj(self: *Self, obj: public.ObjId) ?*public.Obj {
        _ = self.writers_count.fetchAdd(1, .Monotonic);

        var true_obj = self.getObjectPtr(obj);
        var storage = self.getTypeStorage(obj.type_hash) orelse return null;
        storage.increaseReference(obj);
        var new_obj = storage.cloneObjectRaw(true_obj.?, false, null) catch |err| {
            log.api.err(MODULE_NAME, "Could not crate writer {}", .{err});
            return null;
        };
        return @ptrCast(new_obj);
    }

    pub fn retargetWriter(self: *Self, writer: *public.Obj, obj: public.ObjId) void {
        var true_obj = toObjFromObjO(writer);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        _ = storage.decreaseReferenceToFree(true_obj) catch undefined; // we increse this on creating writer.
        storage.increaseReference(obj);

        true_obj.objid = obj;
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
    }

    pub fn setSubObj(self: *Self, writer: *public.Obj, prop_idx: u32, subobj_writer: *public.Obj) !void {
        var true_obj = toObjFromObjO(writer);
        var true_sub_obj = toObjFromObjO(subobj_writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_hash)) {
            log.api.warn(MODULE_NAME, "Invalid type_hash for set sub obj", .{});
            return;
        }

        self.setParent(true_sub_obj, true_obj.objid, prop_idx);

        if (self.readSubObj(writer, prop_idx)) |old_subobj| {
            var old_subobj_ptr = self.getObjectPtr(old_subobj).?;
            var old_subobj_storage = self.getTypeStorage(old_subobj.type_hash).?;
            _ = try old_subobj_storage.decreaseReferenceToFree(old_subobj_ptr);
        }

        obj_storage.setTT(public.ObjId, writer, prop_idx, true_sub_obj.objid, public.PropType.SUBOBJECT);
    }

    pub fn clearSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.SUBOBJECT);
    }

    pub fn clearRef(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        var true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_ptr = self.getObjectPtr(ref).?;
            var old_ref_storage = self.getTypeStorage(ref.type_hash).?;
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

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_ptr = self.getObjectPtr(ref).?;
            var old_ref_storage = self.getTypeStorage(ref.type_hash).?;
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
        }
    }

    pub fn removeFromRefSet(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(value)) {
            var ref_obj_storage = self.getTypeStorage(value.type_hash).?;
            var ref_obj = self.getObjectPtr(value);
            _ = try ref_obj_storage.decreaseReferenceToFree(ref_obj.?);
        }
    }

    pub fn removeFromSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, sub_writer: *public.Obj) !void {
        var true_obj = toObjFromObjO(writer);
        var true_sub_obj = toObjFromObjO(sub_writer);

        var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(true_sub_obj.objid)) {
            var ref_obj_storage = self.getTypeStorage(true_sub_obj.objid.type_hash).?;
            _ = try ref_obj_storage.decreaseReferenceToFree(true_sub_obj);
        }
    }

    pub fn createBlob(self: *Self, writer: *public.Obj, prop_idx: u32, size: u8) !?[]u8 {
        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        var prev_blob = self.readBlob(writer, prop_idx);
        obj_storage.destroyBlob(prev_blob);

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

    pub fn readReferenceSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSet(writer, prop_idx, allocator) catch |err| {
            log.api.err(MODULE_NAME, "Could not read ref set {}", .{err});
            return null;
        };
    }

    fn readSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);

        // Fast path for non prototype
        if (true_obj.prototype_id == 0) {
            var array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            return try array.*.getItems(allocator);
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

            var storage = self.getTypeStorage(true_sub_obj.objid.type_hash).?;
            storage.increaseReference(true_sub_obj.objid);
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

    pub fn stressIt(self: *Self, type_hash: cetech1.strid.StrId32, type_hash2: cetech1.strid.StrId32, ref_obj1: cetech1.cdb.ObjId) !void {
        var obj1 = try self.createObject(type_hash);

        var obj2 = try self.createObject(type_hash2);
        var obj3 = try self.createObject(type_hash2);

        var writer = self.writerObj(obj1).?;

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

        self.destroyObject(obj1);
        self.destroyObject(obj2);
        self.destroyObject(obj3);
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
    try apidb.api.setOrRemoveZigApi(public.CdbAPI, &api, true, false);
}

pub fn registerAllTypes() void {
    var it = apidb.api.getFirstImpl(c.c.ct_cdb_create_types_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(c.c.ct_cdb_create_types_i, node);

        var db_it = _first_db;
        while (db_it) |db_node| : (db_it = db_node.next) {
            iface.create_types.?(@ptrCast(db_node));
        }
    }
}

pub var api = public.CdbAPI{
    .createDbFn = createDb,
    .destroyDbFn = destroyDb,
    .addTypeFn = addType,
    .getTypePropDefFn = getTypePropDef,
    .getTypeNameFn = getTypeName,

    .addAspectFn = addAspect,
    .getAspectFn = getAspect,

    .addPropertyAspectFn = addPropertyAspect,
    .getPropertyAspectFn = getPropertyAspect,

    .getObjIdFromUuidFn = getObjIdFromUuid,

    .createObjectFn = createObject,
    .createObjectWithUuidFn = createObjectWithUuid,
    .createObjectFromPrototypeFn = createObjectFromPrototype,
    .cloneObjectFn = cloneObject,
    .destroyObjectFn = destroyObject,
    .setDefaultObjectFn = setDefaultObject,
    .getUuidFn = getUuid,
    .readObjFn = readObj,

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
    .removeFromRefSetFn = removeFromRefSet,

    .addSubObjToSetFn = addSubObjToSet,
    .readSubObjSetFn = readSubObjSet,
    .removeFromSubObjSetFn = removeFromSubObjSet,

    .createBlobFn = createBlob,
    .readBlobFn = readBlob,

    .resetPropertyOverideFn = resetPropertyOverride,
    .isPropertyOverridedFn = isPropertyOverrided,
    .getPrototypeFn = getPrototype,
    .instantiateSubObjFn = instantiateSubObj,

    .stressItFn = @ptrCast(&Db.stressIt),

    .gcFn = gc,
};

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

fn createObject(db_: *public.Db, type_hash: StrId32) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.createObject(type_hash);
}

fn createObjectWithUuid(db_: *public.Db, type_hash: StrId32, with_uuid: cetech1.uuid.Uuid) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.createObjectWithUuid(type_hash, with_uuid);
}

fn createObjectFromPrototype(db_: *public.Db, prototype: public.ObjId) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.createObjectFromPrototype(prototype);
}

fn cloneObject(db_: *public.Db, obj: public.ObjId) !public.ObjId {
    var db = toDbFromDbT(db_);
    return db.createObjectFromPrototype(obj);
}
fn setDefaultObject(db_: *public.Db, obj: public.ObjId) void {
    var db = toDbFromDbT(db_);
    return db.setDefaultObject(obj);
}

fn destroyObject(db_: *public.Db, obj: public.ObjId) void {
    var db = toDbFromDbT(db_);
    return db.destroyObject(obj);
}

pub fn getUuid(db_: *public.Db, objid: public.ObjId) cetech1.uuid.Uuid {
    var db = toDbFromDbT(db_);
    return db.getUuid(objid);
}

fn readObj(db_: *public.Db, obj: public.ObjId) ?*public.Obj {
    var db = toDbFromDbT(db_);
    return db.readObj(obj);
}

fn writerObj(db_: *public.Db, obj: public.ObjId) ?*public.Obj {
    var db = toDbFromDbT(db_);
    return db.writerObj(obj);
}

fn writerCommit(db_: *public.Db, writer: *public.Obj) void {
    var db = toDbFromDbT(db_);
    return db.writerCommit(writer) catch undefined;
}

fn retargetWrite(db_: *public.Db, writer: *public.Obj, obj: public.ObjId) void {
    var db = toDbFromDbT(db_);
    db.retargetWriter(writer, obj);
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

pub fn getObjIdFromUuid(db_: *public.Db, obj_uuid: cetech1.uuid.Uuid) ?public.ObjId {
    var db = toDbFromDbT(db_);
    return db.getObjIdFromUuid(obj_uuid);
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
    return db.readReferenceSet(obj, prop_idx, allocator);
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

fn removeFromSubObjSet(db_: *public.Db, obj: *public.Obj, prop_idx: u32, sub_obj: *public.Obj) !void {
    var db = toDbFromDbT(db_);
    try db.removeFromSubObjSet(obj, prop_idx, sub_obj);
}

fn createBlob(db_: *public.Db, obj: *public.Obj, prop_idx: u32, size: u8) !?[]u8 {
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

// Assert C and Zig Enums
comptime {
    std.debug.assert(c.c.CT_CDB_TYPE_NONE == @intFromEnum(public.PropType.NONE));
    std.debug.assert(c.c.CT_CDB_TYPE_U64 == @intFromEnum(public.PropType.U64));
    std.debug.assert(c.c.CT_CDB_TYPE_I64 == @intFromEnum(public.PropType.I64));
    std.debug.assert(c.c.CT_CDB_TYPE_U32 == @intFromEnum(public.PropType.U32));
    std.debug.assert(c.c.CT_CDB_TYPE_I32 == @intFromEnum(public.PropType.I32));
    std.debug.assert(c.c.CT_CDB_TYPE_F32 == @intFromEnum(public.PropType.F32));
    std.debug.assert(c.c.CT_CDB_TYPE_F64 == @intFromEnum(public.PropType.F64));
    std.debug.assert(c.c.CT_CDB_TYPE_STR == @intFromEnum(public.PropType.STR));
    std.debug.assert(c.c.CT_CDB_TYPE_BLOB == @intFromEnum(public.PropType.BLOB));
    std.debug.assert(c.c.CT_CDB_TYPE_SUBOBJECT == @intFromEnum(public.PropType.SUBOBJECT));
    std.debug.assert(c.c.CT_CDB_TYPE_REFERENCE == @intFromEnum(public.PropType.REFERENCE));
    std.debug.assert(c.c.CT_CDB_TYPE_SUBOBJECT_SET == @intFromEnum(public.PropType.SUBOBJECT_SET));
    std.debug.assert(c.c.CT_CDB_TYPE_REFERENCE_SET == @intFromEnum(public.PropType.REFERENCE_SET));
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
    var obj1 = try storage.allocateObjId(null);
    var obj2 = try storage.allocateObjId(null);
    try std.testing.expect(obj1.id != obj2.id);
    try std.testing.expectEqual(@as(u32, 1), obj1.id);
    try std.testing.expectEqual(@as(u32, 2), obj2.id);

    // Free one and alocate one then has same ID because free pool.
    try storage.freeObjId(obj2);
    var obj3 = try storage.allocateObjId(null);
    try std.testing.expectEqual(@as(u32, obj2.id), obj3.id);

    var obj4 = try storage.allocateObjId(null);
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
