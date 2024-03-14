// NOTE: Braindump shit, features first for api then optimize internals.
// TODO: remove typestorage lookup, use typhe_hash => type_idx fce,  storages[objid.type_idx]
// TODO: linkedlist for objects to delete, *Object.next to Object

const builtin = @import("builtin");
const std = @import("std");

const c = @import("c.zig").c;
const public = @import("../cdb.zig");
const cetech1 = @import("../cetech1.zig");
const strid = @import("../strid.zig");
const assetdb = @import("assetdb.zig");

//const log = @import("log.zig");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const uuid = @import("uuid.zig");

const cdb_test = @import("cdb_test.zig");

const StrId32 = strid.StrId32;
const strId32 = strid.strId32;

const MODULE_NAME = "cdb";
const log = std.log.scoped(.cdb);

const Blob = []u8;
const IdSet = std.AutoArrayHashMap(public.ObjId, void);
const ReferencerIdSet = std.AutoArrayHashMap(public.ObjId, u32);
const PrototypeInstanceSet = std.AutoArrayHashMap(public.ObjId, void);
const IdSetPool = cetech1.mem.VirtualPool(ObjIdSet);
const OverridesSet = std.bit_set.DynamicBitSet;

const AtomicInt32 = std.atomic.Value(u32);
const AtomicInt64 = std.atomic.Value(u64);
const TypeStorageMap = std.AutoArrayHashMap(StrId32, TypeStorage);
const ToFreeIdQueue = cetech1.mem.QueueWithLock(*Object);
const FreeIdQueueNodePool = cetech1.mem.PoolWithLock(cetech1.FreeIdQueue.Node);
const ToFreeIdQueueNodePool = cetech1.mem.PoolWithLock(ToFreeIdQueue.Node);

const TypeAspectMap = std.AutoArrayHashMap(StrId32, *anyopaque);
const StrId2TypeAspectName = std.AutoArrayHashMap(StrId32, []const u8);
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
        const ptr = self.props_mem.ptr + self.prop_offset[prop_idx];
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
            try self.removed.put(value, {});
        }
    }

    pub fn add(self: *Self, item: public.ObjId) !bool {
        const added = !self.added.contains(item);
        try self.added.put(item, {});
        _ = self.removed.swapRemove(item);
        return added;
    }

    pub fn remove(self: *Self, item: public.ObjId) !bool {
        const removed = self.added.swapRemove(item);

        if (!removed) {
            try self.removed.put(item, {});
        }

        return removed;
    }

    pub fn removeFromRemoved(self: *Self, item: public.ObjId) void {
        _ = self.removed.swapRemove(item);
    }

    pub fn getAddedItems(self: *Self, allocator: std.mem.Allocator) ![]public.ObjId {
        const new = try allocator.alloc(public.ObjId, self.added.count());
        @memcpy(new, self.added.keys());
        return new;
    }

    pub fn getRemovedItems(self: *Self, allocator: std.mem.Allocator) ![]public.ObjId {
        const new = try allocator.alloc(public.ObjId, self.removed.count());
        @memcpy(new, self.removed.keys());
        return new;
    }
};

pub const TypeStorage = struct {
    const Self = @This();

    // TODO: For now allocate minimal object count, need better sage of vram on windows.
    const MAX_OBJECTS = 100_000; // TODO: From max ID
    const MAX_OBJIDSETS = 100_000;

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
    strid2aspectname: StrId2TypeAspectName,
    property_aspect_map: PropertyTypeAspectMap,

    contain_set: bool,
    contain_subobject: bool,

    // Metrics
    write_commit_count: AtomicInt32,
    writers_created_count: AtomicInt32,
    read_obj_count: AtomicInt32,

    write_commit_count_last: u32 = 0,
    writers_created_count_last: u32 = 0,
    read_obj_count_last: u32 = 0,

    // Buffers for profiler
    gc_name: [256:0]u8 = undefined,
    read_name: [256:0]u8 = undefined,
    write_commit_name: [256:0]u8 = undefined,
    writers_name: [256:0]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, db: *Db, name: []const u8, props_def: []const public.PropDef) !Self {
        var props_size: usize = 0;
        var prop_offset = std.ArrayList(usize).init(allocator);

        var contain_set = false;
        var contain_subobject = false;

        for (props_def) |prop| {
            const ti = getCdbTypeInfo(prop.type);
            const size = ti[0];
            const type_align = ti[1];

            const padding = alignPadding(@bitCast(props_size), type_align);

            try prop_offset.append(props_size + padding);

            props_size += size + padding;

            switch (prop.type) {
                .REFERENCE_SET, .SUBOBJECT_SET => contain_set = true,
                .SUBOBJECT => contain_subobject = true,
                else => {},
            }

            if (prop.type == .REFERENCE_SET or prop.type == .SUBOBJECT_SET) {}
        }

        var copy_def = try std.ArrayList(public.PropDef).initCapacity(_allocator, props_def.len);
        try copy_def.appendSlice(props_def);

        var ts = TypeStorage{
            .db = db,
            .name = name,
            .type_hash = strId32(name),
            .props_def = try copy_def.toOwnedSlice(),
            .allocator = allocator,
            .contain_set = contain_set,
            .contain_subobject = contain_subobject,

            .object_pool = try cetech1.mem.VirtualPool(Object).init(allocator, MAX_OBJECTS),

            .objid_pool = cetech1.mem.IdPool(u32).init(allocator),
            .objid2obj = try cetech1.mem.VirtualArray(?*Object).init(MAX_OBJECTS),
            .objid_ref_count = try cetech1.mem.VirtualArray(AtomicInt32).init(MAX_OBJECTS),
            .objid_version = try cetech1.mem.VirtualArray(AtomicInt64).init(MAX_OBJECTS),
            .objid2refs = try cetech1.mem.VirtualArray(ReferencerIdSet).init(MAX_OBJECTS),
            .objid2refs_lock = try cetech1.mem.VirtualArray(std.Thread.Mutex).init(MAX_OBJECTS),
            .prototype2instances = try cetech1.mem.VirtualArray(PrototypeInstanceSet).init(MAX_OBJECTS),
            .prototype2instances_lock = try cetech1.mem.VirtualArray(std.Thread.Mutex).init(MAX_OBJECTS),

            .objs_mem = try cetech1.mem.VirtualArray(u8).init(MAX_OBJECTS * props_size),

            .to_free_queue = ToFreeIdQueue.init(),
            .to_free_obj_node_pool = ToFreeIdQueueNodePool.init(allocator),

            .idset_pool = if (contain_set) try IdSetPool.init(allocator, MAX_OBJIDSETS) else undefined,

            .props_size = props_size,
            .prop_offset = prop_offset,
            .aspect_map = TypeAspectMap.init(allocator),
            .strid2aspectname = StrId2TypeAspectName.init(allocator),
            .property_aspect_map = PropertyTypeAspectMap.init(allocator),

            .write_commit_count = AtomicInt32.init(0),
            .writers_created_count = AtomicInt32.init(0),
            .read_obj_count = AtomicInt32.init(0),
        };

        _ = try std.fmt.bufPrintZ(&ts.gc_name, "CDB:GC: {s}", .{ts.name});
        _ = std.fmt.bufPrintZ(&ts.read_name, "CDB/{s}/{s}/Readers", .{ db.name, name }) catch undefined;
        _ = std.fmt.bufPrintZ(&ts.writers_name, "CDB/{s}/{s}/Writers", .{ db.name, name }) catch undefined;
        _ = std.fmt.bufPrintZ(&ts.write_commit_name, "CDB/{s}/{s}/Commits", .{ db.name, name }) catch undefined;

        return ts;
    }

    pub fn deinit(self: *Self) void {
        // idx 0 is null element
        for (self.object_pool.mem.items[1..self.object_pool.alocated_items.raw]) |*obj| {
            obj.overrides_set.deinit();
        }

        if (self.contain_set) {
            // idx 0 is null element
            for (self.idset_pool.mem.items[1..self.idset_pool.alocated_items.raw]) |*obj| {
                obj.deinit();
            }
        }

        // idx 0 is null element
        for (self.objid2refs.items[1..self.objid_pool.count.raw]) |*obj| {
            obj.deinit();
        }

        // idx 0 is null element
        for (self.prototype2instances.items[1..self.objid_pool.count.raw]) |*obj| {
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
        self.strid2aspectname.deinit();
        self.property_aspect_map.deinit();

        self.objid2refs.deinit();
        self.objid2refs_lock.deinit();
        self.prototype2instances.deinit();
        self.prototype2instances_lock.deinit();

        _allocator.free(self.props_def);
    }

    fn notifyAlloc(self: *Self) !void {
        try self.objid2obj.notifyAlloc(1);
        try self.objid_ref_count.notifyAlloc(1);
        try self.objid_version.notifyAlloc(1);
        try self.objid2refs.notifyAlloc(1);
        try self.objid2refs_lock.notifyAlloc(1);
        try self.prototype2instances.notifyAlloc(1);
        try self.prototype2instances_lock.notifyAlloc(1);
    }

    pub fn isTypeHashValidForProperty(self: *Self, prop_idx: u32, type_hash: StrId32) bool {
        if (self.props_def[prop_idx].type_hash.id == 0) return true;
        return std.meta.eql(self.props_def[prop_idx].type_hash, type_hash);
    }

    fn allocateObjId(self: *Self) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var is_new = false;
        const id = self.objid_pool.create(&is_new);

        if (is_new) {
            try self.notifyAlloc();
        }

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

        if (ref_count.raw == 0) return; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        if (1 == ref_count.fetchSub(1, .Release)) {
            ref_count.fence(.Acquire);
            try self.addToFreeQueue(object);
        }
    }

    fn decreaseReferenceFree(self: *Self, object: *Object, destroyed_objid: *std.ArrayList(public.ObjId), tmp_allocator: std.mem.Allocator) anyerror!u32 {
        var ref_count = &self.objid_ref_count.items[object.objid.id];

        if (ref_count.raw == 0) return 0; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        // if (!object.parent.isEmpty()) {
        //     return try self.freeObject(object, destroyed_objid, tmp_allocator);
        // }

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
        const new_node = try self.to_free_obj_node_pool.create();

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

        if (self.props_size != 0 and new) {
            try self.objs_mem.notifyAlloc(self.props_size);
        }

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
                        const true_ptr = obj.getPropPtr(*ObjIdSet, idx);
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
        try self.strid2aspectname.put(strId32(apect_name), apect_name);
    }
    pub fn getAspect(self: *Self, aspect_hash: StrId32) ?*anyopaque {
        return self.aspect_map.get(aspect_hash);
    }

    pub fn addPropertyAspect(self: *Self, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        try self.property_aspect_map.put(.{ strId32(apect_name), prop_idx }, aspect_ptr);
        try self.strid2aspectname.put(strId32(apect_name), apect_name);
    }
    pub fn getPropertyAspect(self: *Self, prop_idx: u32, aspect_hash: StrId32) ?*anyopaque {
        return self.property_aspect_map.get(.{ aspect_hash, prop_idx });
    }

    pub fn allocateObjIdSet(self: *Self) !*ObjIdSet {
        var is_new = false;
        const array = self.idset_pool.create(&is_new);

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
        const new_blob = try self.allocateBlob(blob.len);
        @memcpy(new_blob, blob);
        return new_blob;
    }

    pub fn createObj(self: *Self) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (!self.default_obj.isEmpty()) {
            return self.cloneObject(self.default_obj);
        }

        const id = try self.allocateObjId();
        var obj = try self.allocateObject(id, true);

        self.objid2obj.items[id.id] = obj;
        obj.parent = .{};

        return .{ .id = id.id, .type_hash = self.type_hash };
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const prototype_obj = self.db.getObjectPtr(prototype).?;
        var new_object = try self.cloneObjectRaw(prototype_obj, true, false, false);
        new_object.prototype_id = prototype_obj.objid.id;

        try self.addPrototypeInstance(prototype, new_object.objid);

        return new_object.objid;
    }

    pub fn cloneObject(self: *Self, obj: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const true_obj = self.db.getObjectPtr(obj).?;
        const new_object = try self.cloneObjectRaw(true_obj, true, true, true);
        return new_object.objid;
    }

    pub fn destroyObj(self: *Self, obj: public.ObjId) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const true_obj = self.objid2obj.items[obj.id];
        if (true_obj == null) return;
        try self.decreaseReferenceToFree(true_obj.?);
    }

    pub fn cloneObjectRaw(self: *Self, obj: *Object, create_new: bool, clone_subobject: bool, clone_set: bool) !*Object {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const obj_id = if (!create_new) obj.objid else try self.allocateObjId();
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
                    const true_ptr = new_obj.getPropPtr([:0]u8, idx);
                    if (true_ptr.len != 0) {
                        true_ptr.* = try self.allocator.dupeZ(u8, true_ptr.*);
                    }
                },

                // Clone subobject if alocate new
                public.PropType.SUBOBJECT => {
                    const true_ptr = new_obj.getPropPtr(public.ObjId, idx);
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
                    const true_ptr = new_obj.getPropPtr(public.ObjId, idx);
                    if (true_ptr.*.id == 0) continue;
                    //var storage = self.db.getTypeStorage(true_ptr.*.type_hash).?;
                    //storage.increaseReference(true_ptr.*);
                },

                public.PropType.SUBOBJECT_SET => {
                    const true_ptr = new_obj.getPropPtr(*ObjIdSet, idx);

                    if (clone_subobject) {
                        var new_set = try self.allocateObjIdSet();

                        const set = try true_ptr.*.getAddedItems(self.allocator);
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
                        const set = try true_ptr.*.getAddedItems(self.allocator);
                        defer self.allocator.free(set);
                        for (set) |ref| {
                            const storage = self.db.getTypeStorage(ref.type_hash).?;
                            _ = storage;
                            //storage.increaseReference(ref);
                        }
                    }
                },

                // Duplicate set and increase ref
                public.PropType.REFERENCE_SET => {
                    const true_ptr = new_obj.getPropPtr(*ObjIdSet, idx);
                    //_ = clone_set;
                    true_ptr.* = try self.cloneIdSet(true_ptr.*, create_new and !clone_set);
                    const set = try true_ptr.*.getAddedItems(self.allocator);
                    defer self.allocator.free(set);
                    for (set) |ref| {
                        _ = ref;
                        //var storage = self.db.getTypeStorage(ref.type_hash).?;
                        //storage.increaseReference(ref);
                    }
                },

                // Duplicate
                public.PropType.BLOB => {
                    const true_ptr = new_obj.getPropPtr(Blob, idx);
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
                    const true_ptr = obj.getPropPtr([:0]u8, idx);
                    if (true_ptr.len != 0) {
                        self.allocator.free(true_ptr.*);
                    }
                },
                .BLOB => {
                    const true_ptr = obj.getPropPtr(Blob, idx);
                    self.destroyBlob(true_ptr.*);
                },
                .SUBOBJECT => {
                    const subobj = obj.getPropPtr(public.ObjId, idx);
                    const subobj_ptr = self.db.getObjectPtr(subobj.*) orelse continue;
                    var storage = self.db.getTypeStorage(subobj_ptr.objid.type_hash).?;

                    if (!is_writer) {
                        free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                        //free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                    }
                },
                .SUBOBJECT_SET => {
                    const true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    const set = try true_ptr.*.getAddedItems(tmp_allocator);
                    defer tmp_allocator.free(set);

                    for (set) |subobj| {
                        const subobj_ptr = self.db.getObjectPtr(subobj) orelse continue;
                        var storage = self.db.getTypeStorage(subobj.type_hash).?;
                        if (!is_writer) {
                            free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                            //free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                        }
                    }
                    try self.destroyObjIdSet(true_ptr.*);
                },
                .REFERENCE => {
                    const ref = obj.getPropPtr(public.ObjId, idx);
                    const ref_ptr = self.db.getObjectPtr(ref.*) orelse continue;
                    var storage = self.db.getTypeStorage(ref_ptr.objid.type_hash).?;
                    if (!is_writer) {
                        storage.removeObjIdReferencer(ref.*, obj.objid);
                    }
                    //free_objects += try storage.decreaseReferenceFree(ref_ptr, destroyed_objid, tmp_allocator);
                },
                .REFERENCE_SET => {
                    const true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    const set = try true_ptr.*.getAddedItems(tmp_allocator);
                    defer tmp_allocator.free(set);
                    for (set) |ref_id| {
                        const ref_ptr = self.db.getObjectPtr(ref_id) orelse continue;
                        var storage = self.db.getTypeStorage(ref_ptr.objid.type_hash).?;
                        if (!is_writer) {
                            storage.removeObjIdReferencer(ref_id, obj.objid);
                        }
                        //free_objects += try storage.decreaseReferenceFree(ref_ptr, destroyed_objid, tmp_allocator);
                    }
                    try self.destroyObjIdSet(true_ptr.*);
                },

                else => continue,
            }
        }

        // Destroy objid
        if (!is_writer) {
            var ref_set_clone = try self.objid2refs.items[obj.objid.id].cloneWithAllocator(tmp_allocator);
            defer ref_set_clone.deinit();

            const referencers = ref_set_clone.keys();
            const referencers_prop_idx = ref_set_clone.values();

            for (referencers, referencers_prop_idx) |referencer, prop_idx| {
                // TODO: why need  orelse continue
                const storage = self.db.getTypeStorage(referencer.type_hash) orelse continue;
                const reference_obj = self.db.getObjectPtr(referencer) orelse continue;
                switch (storage.props_def[prop_idx].type) {
                    public.PropType.REFERENCE => try self.db.clearRef(@ptrCast(reference_obj), prop_idx),
                    public.PropType.REFERENCE_SET => try self.db.removeFromRefSet(@ptrCast(reference_obj), prop_idx, obj.objid),
                    else => undefined,
                }
            }

            // Has parent? (subobj || in subobjset)
            if (!obj.parent.isEmpty()) {
                const parent_obj = self.db.getObjectPtr(obj.parent);
                var storage = self.db.getTypeStorage(obj.parent.type_hash).?;
                const ref_count = &storage.objid_ref_count.items[obj.parent.id];
                if (ref_count.raw != 0) {
                    switch (storage.props_def[obj.parent_prop_idx].type) {
                        public.PropType.SUBOBJECT => try self.db.clearSubObj(@ptrCast(parent_obj.?), obj.parent_prop_idx),
                        public.PropType.SUBOBJECT_SET => try self.db.removeFromSubObjSet(@ptrCast(parent_obj.?), obj.parent_prop_idx, @ptrCast(obj)),
                        else => undefined,
                    }
                }
                obj.parent = .{};
            }

            if (obj.prototype_id != 0) {
                self.removePrototypeInstance(.{ .id = obj.prototype_id, .type_hash = obj.objid.type_hash }, obj.objid);
            }

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
            zone_ctx.Name(&self.gc_name);
        }

        var destroyed_ids = std.ArrayList(public.ObjId).init(tmp_allocator);
        defer destroyed_ids.deinit();

        var free_objects: u32 = 0;
        while (self.to_free_queue.pop()) |node| {
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
            const prototype_obj = self.db.getObjectPtr(true_obj.getPrototypeObjId());
            if (prototype_obj) |proto_obj| {
                return readGeneric(self, @ptrCast(proto_obj), prop_idx, prop_type);
            }
        }

        const true_ptr = true_obj.getPropPtr(u8, prop_idx);
        var ptr: [*]const u8 = @ptrCast(true_ptr);
        return ptr[0..getCdbTypeInfo(prop_type)[0]];
    }

    pub fn readTT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32, prop_type: public.PropType) T {
        const value_ptr = self.readGeneric(obj, prop_idx, prop_type);
        const typed_ptr: *const T = @alignCast(@ptrCast(value_ptr.ptr));
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

        const true_ptr = true_obj.getPropPtr(u8, prop_idx);
        var ptr: [*]u8 = @ptrCast(true_ptr);
        const ptr2 = ptr[0..getCdbTypeInfo(prop_type)[0]];
        @memcpy(ptr2, value);
    }

    pub fn setTT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32, value: T, prop_type: public.PropType) void {
        const value_ptr: [*]const u8 = @ptrCast(&value);
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
        const new_subobj = try storage.createObjectFromPrototype(value);
        //self.setTT(public.CdbObjIdT, writer, prop_idx, c.CT_CDB_OBJID_ZERO, public.PropertyType.SUBOBJECT);
        try self.db.setSubObj(writer, prop_idx, @ptrCast(self.db.getObjectPtr(new_subobj).?));
    }

    pub fn instantiateSubObjFromSet(self: *Self, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var storage = self.db.getTypeStorage(set_obj.type_hash).?;
        const new_subobj = try storage.createObjectFromPrototype(set_obj);
        const true_ptr = self.db.getObjectPtr(new_subobj).?;

        try self.db.addToSubObjSet(writer, prop_idx, &.{@ptrCast(true_ptr)});

        const set_obj_w = self.db.getObjectPtr(set_obj).?;
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
    free_objects: u32,
    objids_alocated: u32,
    objects_alocated: u32,

    on_obj_destroy_map: OnObjIdDestroyMap,

    // Buffers for profiler
    read_name: [256:0]u8 = undefined,
    write_commit_name: [256:0]u8 = undefined,
    writers_name: [256:0]u8 = undefined,

    alocated_objects_name: [256:0]u8 = undefined,
    alocated_obj_ids_name: [256:0]u8 = undefined,
    gc_free_objects_name: [256:0]u8 = undefined,

    metrics_init: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: [:0]const u8) Db {
        var self: @This() = .{
            .name = name,
            .allocator = allocator,
            .typestorage_map = TypeStorageMap.init(allocator),

            .on_obj_destroy_map = OnObjIdDestroyMap.init(allocator),

            .free_objects = 0,
            .objids_alocated = 0,
            .objects_alocated = 0,
        };

        _ = std.fmt.bufPrintZ(&self.alocated_obj_ids_name, "CDB/{s}/Allocated ids", .{self.name}) catch undefined;
        _ = std.fmt.bufPrintZ(&self.alocated_objects_name, "CDB/{s}/Allocated objects", .{self.name}) catch undefined;
        _ = std.fmt.bufPrintZ(&self.gc_free_objects_name, "CDB/{s}/GC free objects", .{self.name}) catch undefined;
        _ = std.fmt.bufPrintZ(&self.writers_name, "CDB/{s}/Writers", .{self.name}) catch undefined;
        _ = std.fmt.bufPrintZ(&self.write_commit_name, "CDB/{s}/Commits", .{self.name}) catch undefined;
        _ = std.fmt.bufPrintZ(&self.read_name, "CDB/{s}/Readers", .{self.name}) catch undefined;

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.gc(self.allocator) catch |err| {
            log.err("Could not GC db on deinit {}", .{err});
            return;
        };

        for (self.typestorage_map.values()) |*value| {
            value.deinit();
        }

        self.on_obj_destroy_map.deinit();
        self.typestorage_map.deinit();
    }

    pub fn readersCount(self: *Self) usize {
        var i: usize = 0;

        for (self.typestorage_map.values()) |type_map| {
            i += type_map.read_obj_count.raw;
        }

        return i;
    }

    pub fn writersCount(self: *Self) usize {
        var i: usize = 0;

        for (self.typestorage_map.values()) |type_map| {
            i += type_map.writers_created_count.raw;
        }

        return i;
    }

    pub fn commitCount(self: *Self) usize {
        var i: usize = 0;

        for (self.typestorage_map.values()) |type_map| {
            i += type_map.write_commit_count.raw;
        }

        return i;
    }

    pub fn gc(self: *Self, tmp_allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.ZoneN(@src(), "CDB:GC");
        defer zone_ctx.End();

        // if (!self.metrics_init) {
        //     self.metrics_init = true;
        //     for (self.typestorage_map.values()) |*type_map| {
        //         profiler.api.plotU64(&type_map.writers_name, 0);
        //         profiler.api.plotU64(&type_map.write_commit_name, 0);
        //         profiler.api.plotU64(&type_map.read_name, 0);
        //     }
        // }

        self.free_objects = 0;
        for (self.typestorage_map.values()) |*type_storage| {
            //if (type_storage.to_free_queue.isEmpty()) continue;
            self.free_objects += try type_storage.gc(tmp_allocator);
        }

        self.objids_alocated = 0;
        for (self.typestorage_map.values()) |type_map| {
            self.objids_alocated += type_map.objid_pool.count.raw - 1;
        }

        self.objects_alocated = 0;
        for (self.typestorage_map.values()) |type_map| {
            self.objects_alocated += type_map.object_pool.alocated_items.raw - 1;
        }

        if (profiler.profiler_enabled) {
            profiler.api.plotU64(&self.alocated_obj_ids_name, self.objids_alocated);
            profiler.api.plotU64(&self.alocated_objects_name, self.objects_alocated);
            profiler.api.plotU64(&self.gc_free_objects_name, self.free_objects);

            profiler.api.plotU64(&self.writers_name, self.writersCount());
            profiler.api.plotU64(&self.write_commit_name, self.commitCount());
            profiler.api.plotU64(&self.read_name, self.readersCount());

            for (self.typestorage_map.values()) |*type_map| {
                if (type_map.writers_created_count.raw != 0 and type_map.writers_created_count_last != 0) {
                    profiler.api.plotU64(&type_map.writers_name, type_map.writers_created_count.raw);
                }

                if (type_map.write_commit_count.raw != 0 and type_map.write_commit_count_last != 0) {
                    profiler.api.plotU64(&type_map.write_commit_name, type_map.write_commit_count.raw);
                }

                if (type_map.read_obj_count.raw != 0 and type_map.read_obj_count_last != 0) {
                    profiler.api.plotU64(&type_map.read_name, type_map.read_obj_count.raw);
                }
            }
        }

        for (self.typestorage_map.values()) |*type_map| {
            type_map.write_commit_count_last = type_map.write_commit_count.raw;
            type_map.writers_created_count_last = type_map.writers_created_count.raw;
            type_map.read_obj_count_last = type_map.read_obj_count.raw;

            type_map.write_commit_count = AtomicInt32.init(0);
            type_map.writers_created_count = AtomicInt32.init(0);
            type_map.read_obj_count = AtomicInt32.init(0);
        }
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
        const storage = self.getTypeStorage(obj.type_hash) orelse return null;
        return if (obj.isEmpty()) null else storage.objid2obj.items[obj.id];
    }

    fn getParent(self: *Self, obj: public.ObjId) public.ObjId {
        const true_obj = self.getObjectPtr(obj);
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

        const storage = self.getTypeStorage(obj.type_hash).?;
        const true_obj = self.getObjectPtr(obj).?;

        return storage.objid_version.items[true_obj.objid.id].raw;

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
        const storage = self.getTypeStorage(type_hash) orelse return null;
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
        const result = try self.typestorage_map.getOrPut(type_hash);
        if (!result.found_existing) {
            const ts = try TypeStorage.init(_allocator, self, name, prop_def);

            result.value_ptr.* = ts;
        }
        return result.value_ptr;
    }

    pub fn getTypePropDef(self: *Self, type_hash: StrId32) ?[]const public.PropDef {
        const storage = self.getTypeStorage(type_hash) orelse return null;
        return storage.props_def;
    }

    pub fn addType(self: *Self, name: []const u8, prop_defs: []const public.PropDef) !StrId32 {
        for (prop_defs, 0..) |prop_def, real_idx| {
            std.debug.assert(prop_def.prop_idx == real_idx);
        }
        const type_hash = strId32(name);

        const storage = try self.getOrCreateTypeStorage(type_hash, name, prop_defs);

        const all_vm_size = (storage.object_pool.mem.reservation.len +
            storage.idset_pool.mem.reservation.len +
            storage.objs_mem.reservation.len +
            storage.objid2obj.reservation.len +
            storage.objid_ref_count.reservation.len +
            storage.objid_version.reservation.len +
            storage.objid2refs.reservation.len +
            storage.objid2refs_lock.reservation.len +
            storage.prototype2instances.reservation.len +
            storage.prototype2instances_lock.reservation.len);

        log.debug("Register type {s}: {d}|{d}MB", .{ name, type_hash.id, all_vm_size / 1000000 });

        return type_hash;
    }

    pub fn hasTypeSet(self: *Self, type_hash: StrId32) bool {
        const storate = self.getTypeStorage(type_hash) orelse return false;
        return storate.contain_set;
    }

    pub fn hasTypeSubobject(self: *Self, type_hash: StrId32) bool {
        const storate = self.getTypeStorage(type_hash) orelse return false;
        return storate.contain_subobject;
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
            log.warn("Error while destroing object: {}", .{err});
        };
    }

    pub fn writerObj(self: *Self, obj: public.ObjId) ?*public.Obj {
        const true_obj = self.getObjectPtr(obj);
        var storage = self.getTypeStorage(obj.type_hash) orelse return null;
        _ = storage.writers_created_count.fetchAdd(1, .Monotonic);

        storage.increaseReference(obj);
        const new_obj = storage.cloneObjectRaw(true_obj.?, false, false, false) catch |err| {
            log.err("Could not crate writer {}", .{err});
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

        const destination_obj = toObjFromObjO(self.readObj(obj).?);

        // set id from old (commit swap objects*)
        true_obj.objid = obj;

        // maybe we are in subobject relation.
        true_obj.parent = destination_obj.parent;
        true_obj.parent_prop_idx = destination_obj.parent_prop_idx;

        // Patch sub objects
        for (storage.props_def, 0..) |prop_def, idx| {
            switch (prop_def.type) {
                //TODO: CHECK ALL CASE

                public.PropType.SUBOBJECT => {
                    const true_ptr = true_obj.getPropPtr(public.ObjId, idx);
                    if (true_ptr.*.id == 0) continue;
                    const sub_obj_ptr = self.getObjectPtr(true_ptr.*).?;
                    sub_obj_ptr.parent = true_obj.objid;
                },
                public.PropType.SUBOBJECT_SET => {
                    const true_ptr = true_obj.getPropPtr(*ObjIdSet, idx);

                    const set = try true_ptr.*.getAddedItems(self.allocator);
                    defer self.allocator.free(set);
                    for (set) |subobj| {
                        const sub_obj_ptr = self.getObjectPtr(subobj).?;
                        sub_obj_ptr.parent = true_obj.objid;
                    }
                },
                else => continue,
            }
        }
    }

    pub fn writerCommit(self: *Self, writer: *public.Obj) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const new_obj = toObjFromObjO(writer);

        var storage = self.getTypeStorage(new_obj.objid.type_hash).?;
        _ = storage.write_commit_count.fetchAdd(1, .Monotonic);

        _ = try storage.decreaseReferenceToFree(new_obj);

        const old_obj = storage.objid2obj.items[new_obj.objid.id].?;
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
            if (self.getObjectPtr(obj.parent)) |r| {
                self.increaseVersionToAll(r);
            }
        }
    }

    pub fn readObj(self: *Self, obj: public.ObjId) ?*public.Obj {
        const true_obj = self.getObjectPtr(obj);
        const storage = self.getTypeStorage(obj.type_hash) orelse return null;
        _ = storage.read_obj_count.fetchAdd(1, .Monotonic);
        return @ptrCast(true_obj);
    }

    pub fn readGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, prop_type: public.PropType) []const u8 {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return storage.readGeneric(obj, prop_idx, prop_type);
    }

    pub fn readT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32) T {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return storage.readT(T, obj, prop_idx);
    }

    pub fn readSubObj(self: *Self, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        const value = storage.readTT(public.ObjId, obj, prop_idx, public.PropType.SUBOBJECT);
        return if (value.isEmpty()) null else value;
    }

    pub fn readRef(self: *Self, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        const value = storage.readTT(public.ObjId, obj, prop_idx, public.PropType.REFERENCE);
        return if (value.isEmpty()) null else value;
    }

    pub fn readStr(self: *Self, obj: *public.Obj, prop_idx: u32) ?[:0]const u8 {
        return self.readT(?[:0]u8, obj, prop_idx);
    }

    pub fn setGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, value: [*]const u8, prop_type: public.PropType) void {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        storage.setGeneric(obj, prop_idx, value, prop_type);
    }

    pub fn setT(self: *Self, comptime T: type, writer: *public.Obj, prop_idx: u32, value: T) void {
        const true_obj = toObjFromObjO(writer);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return storage.setT(T, writer, prop_idx, value);
    }

    pub fn setStr(self: *Self, writer: *public.Obj, prop_idx: u32, value: [:0]const u8) !void {
        var true_obj = toObjFromObjO(writer);

        const true_ptr = true_obj.getPropPtr([:0]u8, prop_idx);
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
        const true_obj = toObjFromObjO(writer);
        const true_sub_obj = toObjFromObjO(subobj_writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_hash)) {
            log.warn("Invalid type_hash for set sub obj", .{});
            return;
        }

        const has_prototype = !self.getPrototype(writer).isEmpty();
        const is_overided = self.isPropertyOverrided(writer, prop_idx);

        if (!has_prototype and !is_overided) {
            if (self.readSubObj(writer, prop_idx)) |old_subobj| {
                const old_subobj_ptr = self.getObjectPtr(old_subobj).?;
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
        const true_obj = toObjFromObjO(writer);

        const has_prototype = !self.getPrototype(writer).isEmpty();
        const is_overided = self.isPropertyOverrided(writer, prop_idx);

        if (!has_prototype and !is_overided) {
            if (self.readSubObj(writer, prop_idx)) |old_subobj| {
                const old_subobj_ptr = self.getObjectPtr(old_subobj).?;
                var old_subobj_storage = self.getTypeStorage(old_subobj.type_hash).?;
                _ = try old_subobj_storage.decreaseReferenceToFree(old_subobj_ptr);
            }
        }

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.SUBOBJECT);
    }

    pub fn clearRef(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        const true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_storage = self.getTypeStorage(ref.type_hash).?;
            old_ref_storage.removeObjIdReferencer(ref, true_obj.objid);
            //var old_ref_ptr = self.getObjectPtr(ref).?;
            //_ = try old_ref_storage.decreaseReferenceToFree(old_ref_ptr);
        }

        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.REFERENCE);
    }

    pub fn setRef(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        const true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, value.type_hash)) {
            log.warn("Invalid type_hash for set ref", .{});
            return;
        }

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_storage = self.getTypeStorage(ref.type_hash).?;
            old_ref_storage.removeObjIdReferencer(ref, true_obj.objid);

            //var old_ref_ptr = self.getObjectPtr(ref).?;
            //_ = try old_ref_storage.decreaseReferenceToFree(old_ref_ptr);
        }

        var storage = self.getTypeStorage(value.type_hash).?;
        try storage.addObjIdReferencer(value, true_obj.objid, prop_idx);
        //storage.increaseReference(value);

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
                log.warn("Invalid type_hash for add to ref set", .{});
                continue;
            }

            const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            if (!(try array.*.add(value))) {
                continue;
            }

            var storage = self.getTypeStorage(value.type_hash).?;
            //storage.increaseReference(value);
            try storage.addObjIdReferencer(value, true_obj.objid, prop_idx);
        }
    }

    pub fn removeFromRefSet(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        if (!self.isInSet(true_obj, prop_idx, value)) return;

        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(value)) {
            var ref_obj_storage = self.getTypeStorage(value.type_hash).?;
            ref_obj_storage.removeObjIdReferencer(value, true_obj.objid);
            //var ref_obj = self.getObjectPtr(value);
            //_ = try ref_obj_storage.decreaseReferenceToFree(ref_obj.?);
        }
    }

    pub fn removeFromSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, sub_writer: *public.Obj) !void {
        var true_obj = toObjFromObjO(writer);
        const true_sub_obj = toObjFromObjO(sub_writer);

        if (!self.isInSet(true_obj, prop_idx, true_sub_obj.objid)) return;

        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

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
        const prev_blob: *Blob = true_obj.getPropPtr(Blob, prop_idx);
        obj_storage.destroyBlob(prev_blob.*);

        const blob = try obj_storage.allocateBlob(size);
        obj_storage.setTT(Blob, writer, prop_idx, blob, public.PropType.BLOB);
        return blob;
    }

    pub fn readBlob(self: *Self, obj: *public.Obj, prop_idx: u32) []u8 {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid.type_hash).?;

        return storage.readTT([]u8, obj, prop_idx, public.PropType.BLOB);
    }

    pub fn readSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSet(writer, prop_idx, allocator) catch |err| {
            log.err("Could not read suboj set {}", .{err});
            @breakpoint();
            return null;
        };
    }

    pub fn readSubObjSetShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSetAddedShallow(writer, prop_idx, allocator) catch |err| {
            log.err("Could not read suboj set {}", .{err});
            @breakpoint();
            return null;
        };
    }

    pub fn readRefSetShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetAddedShallow(writer, prop_idx, allocator) catch |err| {
            log.err("Could not read ref set {}", .{err});
            @breakpoint();
            return null;
        };
    }

    pub fn readSubObjSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSetRemovedShallow(writer, prop_idx, allocator) catch |err| {
            log.err("Could not read suboj set {}", .{err});
            @breakpoint();
            return null;
        };
    }

    pub fn readRefSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetRemovedShallow(writer, prop_idx, allocator) catch |err| {
            log.err("Could not read ref set {}", .{err});
            @breakpoint();
            return null;
        };
    }

    pub fn readRefSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSet(writer, prop_idx, allocator) catch |err| {
            log.err("Could not read ref set {}", .{err});
            @breakpoint();
            return null;
        };
    }

    fn readSetAddedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        _ = self;
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);
        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
        return try array.*.getAddedItems(allocator);
    }

    fn readSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        _ = self;
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);
        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
        return try array.*.getRemovedItems(allocator);
    }

    fn readSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) !?[]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);

        // Fast path for non prototype
        if (true_obj.prototype_id == 0) {
            const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            return try array.*.getAddedItems(allocator);
        }

        var added = IdSet.init(allocator);
        var removed = IdSet.init(allocator);
        defer added.deinit();
        defer removed.deinit();

        var true_it_obj: ?*Object = true_obj;
        while (true_it_obj) |obj| {
            const set = obj.getPropPtr(*ObjIdSet, prop_idx);

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

    fn countAddedRemoved(self: *Self, obj: *public.Obj, prop_idx: u32, item_obj: public.ObjId) struct { u32, u32 } {
        var true_obj = toObjFromObjO(obj);
        const set = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        var added: u32 = 0;
        var removed: u32 = 0;

        if (set.*.added.contains(item_obj)) {
            added += 1;
        }

        if (set.*.removed.contains(item_obj)) {
            removed += 1;
        }

        if (true_obj.prototype_id != 0) {
            const proto = self.getPrototype(true_obj);
            const true_proto = self.getObjectPtr(proto).?;
            const count = self.countAddedRemoved(true_proto, prop_idx, item_obj);
            added += count[0];
            removed += count[1];
        }

        return .{ added, removed };
    }

    pub fn isInSet(self: *Self, reader: *public.Obj, prop_idx: u32, item_obj: public.ObjId) bool {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const true_obj = toObjFromObjO(reader);
        const count = self.countAddedRemoved(true_obj, prop_idx, item_obj);
        return count[0] > count[1];
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
            const true_sub_obj = toObjFromObjO(sub_obj_writer);
            if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_hash)) {
                log.warn("Invalid type_hash for add to subobj set", .{});
                continue;
            }

            const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
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
        const true_obj = toObjFromObjO(obj);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return obj_storage.isPropertyOverrided(obj, prop_idx);
    }

    pub fn getPrototype(self: *Self, obj: *public.Obj) public.ObjId {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        return true_obj.getPrototypeObjId();
    }

    pub fn instantiateSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        const true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        try obj_storage.instantiateSubObj(writer, prop_idx);
    }

    pub fn instantiateSubObjFromSet(self: *Self, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
        const true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid.type_hash).?;
        return obj_storage.instantiateSubObjFromSet(writer, prop_idx, set_obj);
    }

    fn isIinisiated(self: *Self, obj: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) bool {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        const true_inisiated_obj = toObjFromObjO(inisiated_obj);

        if (true_obj.prototype_id == 0) return false;

        const idset = true_obj.getPropPtr(*ObjIdSet, set_prop_idx);

        const protoype_id = .{
            .id = true_inisiated_obj.prototype_id,
            .type_hash = true_inisiated_obj.objid.type_hash,
        };

        return idset.*.added.contains(true_inisiated_obj.objid) and idset.*.removed.contains(protoype_id);
    }

    fn restoreDeletedInSet(self: *Self, obj: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) void {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        const true_inisiated_obj = toObjFromObjO(inisiated_obj);

        if (true_obj.prototype_id == 0) return;

        const idset = true_obj.getPropPtr(*ObjIdSet, set_prop_idx);
        idset.*.removeFromRemoved(true_inisiated_obj.objid);
    }

    fn canIinisiate(self: *Self, obj: *public.Obj, inisiated_obj: *public.Obj) bool {
        _ = self;
        const true_obj = toObjFromObjO(obj);
        var true_inisiated_obj = toObjFromObjO(inisiated_obj);

        if (true_obj.prototype_id == 0) return false;

        const protoype_id = .{
            .id = true_obj.prototype_id,
            .type_hash = true_obj.objid.type_hash,
        };

        return true_inisiated_obj.parent.eq(protoype_id);
    }

    pub fn setPrototype(self: *Self, obj: public.ObjId, prototype: public.ObjId) !void {
        var obj_r = self.getObjectPtr(obj).?;
        var storage = self.getTypeStorage(obj.type_hash).?;

        if (obj_r.prototype_id != 0) {
            storage.removePrototypeInstance(self.getPrototype(obj_r), obj);
        }

        obj_r.prototype_id = prototype.id;

        if (!prototype.isEmpty()) {
            try storage.addPrototypeInstance(prototype, obj);
        }
        self.increaseVersionToAll(obj_r);
    }

    pub fn getDefaultObject(self: *Self, type_hash: strid.StrId32) ?public.ObjId {
        var storage = self.getTypeStorage(type_hash).?;
        return if (storage.default_obj.isEmpty()) null else storage.default_obj;
    }

    pub fn getFirstObject(self: *Self, type_hash: strid.StrId32) public.ObjId {
        const storage = self.getTypeStorage(type_hash).?;
        for (1..storage.objid_pool.count.raw) |idx| {
            if (storage.objid2obj.items[idx] == null) continue;
            return .{ .id = @intCast(idx), .type_hash = type_hash };
        }

        return public.OBJID_ZERO;
    }

    pub fn getAllObjectByType(self: *Self, allocator: std.mem.Allocator, type_hash: cetech1.strid.StrId32) ?[]public.ObjId {
        const storage = self.getTypeStorage(type_hash).?;
        var result = std.ArrayList(public.ObjId).init(allocator);
        for (1..storage.objid_pool.count.raw) |idx| {
            if (storage.objid2obj.items[idx] == null) continue;

            result.append(.{ .id = @intCast(idx), .type_hash = type_hash }) catch {
                result.deinit();
                return null;
            };
        }

        return result.toOwnedSlice() catch null;
    }

    pub fn stressIt(self: *Self, type_hash: cetech1.strid.StrId32, type_hash2: cetech1.strid.StrId32, ref_obj1: cetech1.cdb.ObjId) !void {
        const obj1 = try self.createObject(type_hash);

        const obj2 = try self.createObject(type_hash2);
        const obj3 = try self.createObject(type_hash2);

        const writer = self.writerObj(obj1).?;

        self.setT(bool, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.Bool), true);
        self.setT(u64, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.U64), 10);
        self.setT(i64, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.I64), 20);
        self.setT(u32, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.U32), 10);
        self.setT(i32, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.I32), 20);
        self.setT(f64, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.F64), 20.10);
        self.setT(f32, writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.F32), 30.20);
        try self.setRef(writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.Reference), ref_obj1);
        try self.addRefToSet(writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.ReferenceSet), &[_]public.ObjId{ref_obj1});

        const writer2 = self.writerObj(obj2).?;
        try self.setSubObj(writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.Subobject), writer2);
        try self.writerCommit(writer2);

        const writer3 = self.writerObj(obj3).?;
        try self.addToSubObjSet(writer, cetech1.cdb.propIdx(cetech1.cdb_types.BigTypeProps.SubobjectSet), &[_]*public.Obj{writer3});
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
        const new_set = try allocator.alloc(public.ObjId, keys.len);
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
    .addTypeFn = @ptrCast(&Db.addType),
    .getTypePropDefFn = @ptrCast(&Db.getTypePropDef),
    .getTypeNameFn = @ptrCast(&Db.getTypeName),
    .getTypePropDefIdxFn = @ptrCast(&Db.getTypePropDefIdx),
    .addAspectFn = @ptrCast(&Db.addAspect),
    .getAspectFn = @ptrCast(&Db.getAspect),

    .addPropertyAspectFn = @ptrCast(&Db.addPropertyAspect),
    .getPropertyAspectFn = @ptrCast(&Db.getPropertyAspect),

    .getReferencerSetFn = @ptrCast(&Db.getReferencerSet),
    .createObjectFn = @ptrCast(&Db.createObject),
    .createObjectFromPrototypeFn = @ptrCast(&Db.createObjectFromPrototype),
    .cloneObjectFn = @ptrCast(&Db.cloneObject),
    .destroyObjectFn = @ptrCast(&Db.destroyObject),
    .setDefaultObjectFn = @ptrCast(&Db.setDefaultObject),
    .readObjFn = @ptrCast(&Db.readObj),
    .getParentFn = @ptrCast(&Db.getParent),
    .getVersionFn = @ptrCast(&Db.getVersion),

    .writeObjFn = @ptrCast(&Db.writerObj),
    .writeCommitFn = @ptrCast(&Db.writerCommit),
    .retargetWriteFn = @ptrCast(&Db.retargetWriter),

    .readGenericFn = @ptrCast(&Db.readGeneric),
    .setGenericFn = @ptrCast(&Db.setGeneric),
    .setStrFn = @ptrCast(&Db.setStr),

    .readSubObjFn = @ptrCast(&Db.readSubObj),
    .setSubObjFn = @ptrCast(&Db.setSubObj),
    .clearSubObjFn = @ptrCast(&Db.clearSubObj),

    .readRefFn = @ptrCast(&Db.readRef),
    .setRefFn = @ptrCast(&Db.setRef),
    .clearRefFn = @ptrCast(&Db.clearRef),

    .addRefToSetFn = @ptrCast(&Db.addRefToSet),
    .readRefSetFn = @ptrCast(&Db.readRefSet),
    .readRefSetAddedFn = @ptrCast(&Db.readRefSetShallow),
    .readRefSetRemovedFn = @ptrCast(&Db.readRefSetRemovedShallow),
    .removeFromRefSetFn = @ptrCast(&Db.removeFromRefSet),

    .addSubObjToSetFn = @ptrCast(&Db.addToSubObjSet),
    .readSubObjSetFn = @ptrCast(&Db.readSubObjSet),
    .readSubObjSetAddedFn = @ptrCast(&Db.readSubObjSetShallow),
    .readSubObjSetRemovedFn = @ptrCast(&Db.readSubObjSetRemovedShallow),
    .removeFromSubObjSetFn = @ptrCast(&Db.removeFromSubObjSet),

    .createBlobFn = @ptrCast(&Db.createBlob),
    .readBlobFn = @ptrCast(&Db.readBlob),

    .resetPropertyOverideFn = @ptrCast(&Db.resetPropertyOveride),
    .isPropertyOverridedFn = @ptrCast(&Db.isPropertyOverrided),
    .getPrototypeFn = @ptrCast(&Db.getPrototype),
    .instantiateSubObjFn = @ptrCast(&Db.instantiateSubObj),
    .instantiateSubObjFromSetFn = @ptrCast(&Db.instantiateSubObjFromSet),
    .isInSetFn = @ptrCast(&Db.isInSet),

    .stressItFn = @ptrCast(&Db.stressIt),

    .addOnObjIdDestroyedFn = @ptrCast(&Db.addOnObjIdDestroyed),
    .removeOnObjIdDestroyedFn = @ptrCast(&Db.removeOnObjIdDestroyed),

    .gcFn = @ptrCast(&Db.gc),

    .isIinisiatedFn = @ptrCast(&Db.isIinisiated),
    .canIinisiateFn = @ptrCast(&Db.canIinisiate),
    .restoreDeletedInSetFn = @ptrCast(&Db.restoreDeletedInSet),

    .setPrototypeFn = @ptrCast(&Db.setPrototype),
    .getDefaultObjectFn = @ptrCast(&Db.getDefaultObject),
    .dump = dump,
    .getFirstObjectFn = @ptrCast(&Db.getFirstObject),
    .getAllObjectByTypeFn = @ptrCast(&Db.getAllObjectByType),

    .hasTypeSetFn = @ptrCast(&Db.hasTypeSet),
    .hasTypeSubobjectFn = @ptrCast(&Db.hasTypeSubobject),
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

fn dump(db_: *public.Db) !void {
    var db = toDbFromDbT(db_);

    var path_buff: [1024]u8 = undefined;
    var file_path_buff: [1024]u8 = undefined;
    // only if asset root is set.
    var path = try assetdb.api.getTmpPath(&path_buff);
    if (path == null) return;
    path = try std.fmt.bufPrint(&file_path_buff, "{s}/" ++ "cdb.md", .{path.?});

    var dot_file = try std.fs.createFileAbsolute(path.?, .{});
    defer dot_file.close();

    var writer = dot_file.writer();
    try writer.print("# CDB Types reference\n\n", .{});

    for (db.typestorage_map.values()) |storage| {
        const type_name = storage.name;
        try writer.print("## {s} - {d}\n\n", .{ type_name, storage.type_hash.id });

        try writer.print("```d2\n", .{});
        try writer.print("{s}: {{\n", .{type_name});
        try writer.print("  shape: class\n", .{});

        for (storage.props_def) |prop| {
            const prop_type = std.enums.tagName(cetech1.cdb.PropType, prop.type).?;

            if (prop.type_hash.id != 0) {
                const typed_name = db.getTypeStorage(prop.type_hash).?.name;
                try writer.print("    + {s}: \"{s} of {s}\"\n", .{ prop.name, prop_type, typed_name });
            } else {
                try writer.print("    + {s}: \"{s}\"\n", .{ prop.name, prop_type });
            }
        }

        try writer.print("}}\n", .{});
        try writer.print("```\n", .{});
        try writer.print("\n", .{});

        const implemented_aspects = storage.aspect_map.keys();
        if (implemented_aspects.len != 0) {
            try writer.print("### {s} implemented aspects\n\n", .{storage.name});

            for (implemented_aspects) |aspect| {
                try writer.print("- {s}\n", .{storage.strid2aspectname.get(aspect).?});
            }

            try writer.print("\n", .{});
        }

        const implemented_prop_aspects = storage.property_aspect_map.keys();
        if (implemented_prop_aspects.len != 0) {
            try writer.print("### **{s}** implemented property aspects\n\n", .{storage.name});

            for (implemented_prop_aspects) |aspect| {
                const name = aspect[0];
                const pidx = aspect[1];
                const prop_name = storage.props_def[pidx].name;
                try writer.print("- **{s}** - {s}\n", .{ prop_name, storage.strid2aspectname.get(name).? });
            }

            try writer.print("\n", .{});
        }
    }
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
    const obj1 = try storage.allocateObjId();
    const obj2 = try storage.allocateObjId();
    try std.testing.expect(obj1.id != obj2.id);
    try std.testing.expectEqual(@as(u32, 1), obj1.id);
    try std.testing.expectEqual(@as(u32, 2), obj2.id);

    // Free one and alocate one then has same ID because free pool.
    try storage.freeObjId(obj2);
    const obj3 = try storage.allocateObjId();
    try std.testing.expectEqual(@as(u32, obj2.id), obj3.id);

    const obj4 = try storage.allocateObjId();
    try std.testing.expectEqual(@as(u32, 3), obj4.id);
}

test "cdb: Test alocate/free idset" {
    try cdb_test.testInit();
    defer cdb_test.testDeinit();

    var db = try api.createDb("Test");
    defer api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &[_]cetech1.cdb.PropDef{
            .{ .prop_idx = 0, .name = "foo", .type = .SUBOBJECT_SET },
        },
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
