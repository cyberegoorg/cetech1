// NOTE: Braindump shit, features first for api then optimize internals.
// TODO: remove typestorage lookup, use typhe_hash => type_idx fce,  storages[objid.type_idx]
// TODO: linkedlist for objects to delete, *Object.next to Object
// TODO: BLOB is currentlu uber shit. pointer to slice to data make sort of interning with id

const builtin = @import("builtin");
const std = @import("std");

const assetdb = @import("assetdb.zig");
const cetech1 = @import("cetech1");
const public = cetech1.cdb;
const strid = cetech1.strid;

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const metrics = @import("metrics.zig");

const cdb_test = @import("cdb_test.zig");

const StrId32 = strid.StrId32;
const strId32 = strid.strId32;

const module_name = .cdb;

const MAX_PROPERIES_IN_OBJECT = 64;

const log = std.log.scoped(module_name);

const Blob = struct { b: []u8 };
const IdSet = std.AutoArrayHashMap(public.ObjId, void);
const ReferencerIdSet = std.AutoArrayHashMap(public.ObjId, u32);
const PrototypeInstanceSet = std.AutoArrayHashMap(public.ObjId, void);
const IdSetPool = cetech1.mem.VirtualPool(ObjIdSet);
const OverridesSet = std.bit_set.IntegerBitSet(MAX_PROPERIES_IN_OBJECT);

const AtomicInt32 = std.atomic.Value(u32);
const AtomicInt64 = std.atomic.Value(u64);
const TypeStorageMap = std.AutoArrayHashMap(StrId32, public.TypeIdx);
const ToFreeIdQueue = cetech1.mem.QueueWithLock(*Object);
const ToFreeIdQueueNodePool = cetech1.mem.PoolWithLock(ToFreeIdQueue.Node);

const TypeAspectMap = std.AutoArrayHashMap(StrId32, *anyopaque);
const StrId2TypeAspectName = std.AutoArrayHashMap(StrId32, []const u8);
const PropertyAspectPair = struct { StrId32, u32 };
const PropertyTypeAspectMap = std.AutoArrayHashMap(PropertyAspectPair, *anyopaque);

const OnObjIdDestroyed = *const fn (db: public.DbId, objects: []public.ObjId) void;

const OnObjIdDestroyMap = std.AutoArrayHashMap(OnObjIdDestroyed, void);

const ChangedObjectsSet = std.AutoArrayHashMap(public.ObjId, void);
const ChangedObjectMap = std.AutoArrayHashMap(public.TypeVersion, ChangedObjectsSet);

const ChangedObjects = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: ChangedObjectMap,
    max_version: u32 = 0,
    lck: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .map = ChangedObjectMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.map.values()) |*values| {
            values.deinit();
        }

        self.map.deinit();
    }

    pub fn addChangedObjects(self: *Self, version: public.TypeVersion, objects: []const public.ObjId) !void {
        self.lck.lock();
        defer self.lck.unlock();

        const result = try self.map.getOrPut(version);
        if (!result.found_existing) {
            result.value_ptr.* = ChangedObjectsSet.init(self.allocator);
        }

        for (objects) |obj| {
            try result.value_ptr.put(obj, {});
        }

        self.max_version = @max(self.max_version, version);
    }

    pub fn getSince(self: *Self, allocator: std.mem.Allocator, since_version: public.TypeVersion, last_version: public.TypeVersion) ![]public.ObjId {
        self.lck.lock();
        defer self.lck.unlock();

        var output = std.ArrayList(public.ObjId).init(allocator);

        for (since_version..last_version) |version| {
            const objects = self.map.get(@intCast(version)) orelse continue;
            try output.appendSlice(objects.keys());
        }

        return output.toOwnedSlice();
    }
};

fn toObjFromObjO(obj: *public.Obj) *Object {
    return @alignCast(@ptrCast(obj));
}

const PropertyValue = usize;

// fn getCdbTypeInfo(cdb_type: public.PropType) TypeInfoTuple {
//     return switch (cdb_type) {
//         public.PropType.BOOL => makeTypeTuple(bool),
//         public.PropType.U64 => makeTypeTuple(u64),
//         public.PropType.I64 => makeTypeTuple(i64),
//         public.PropType.U32 => makeTypeTuple(u32),
//         public.PropType.I32 => makeTypeTuple(i32),
//         public.PropType.F64 => makeTypeTuple(f64),
//         public.PropType.F32 => makeTypeTuple(f32),
//         public.PropType.STR => makeTypeTuple(cetech1.mem.StringInternWithLock.InternId),
//         public.PropType.BLOB => makeTypeTuple(Blob),
//         public.PropType.SUBOBJECT => makeTypeTuple(public.ObjId),
//         public.PropType.REFERENCE => makeTypeTuple(public.ObjId),
//         public.PropType.SUBOBJECT_SET => makeTypeTuple(*ObjIdSet),
//         public.PropType.REFERENCE_SET => makeTypeTuple(*ObjIdSet),
//         else => unreachable,
//     };
// }

//TODO: Optimize memory footprint
pub const Object = struct {
    const Self = @This();

    // ObjId associated with this Object.
    // ObjId can have multiple object because write clone entire object.
    objid: public.ObjId = .{},

    // Property memory.
    props_mem: []PropertyValue = undefined,

    // Parent id and prop idx.
    parent: public.ObjId = .{},
    parent_prop_idx: u32 = 0,

    // Protypes
    prototype: public.ObjId = .{},

    // Set of overided properties.
    overrides_set: OverridesSet,

    version: AtomicInt64,

    pub fn getPropPtr(self: *Self, comptime T: type, prop_idx: usize) *T {
        const ptr = &self.props_mem[prop_idx];
        std.debug.assert(std.mem.isAligned(@intFromPtr(ptr), @alignOf(T)));
        return @alignCast(@ptrCast(ptr));
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

    pub fn getAddedItems(self: *Self) []const public.ObjId {
        return self.added.keys();
    }

    pub fn getRemovedItems(self: *Self) []const public.ObjId {
        return self.removed.keys();
    }
};

pub const TypeStorage = struct {
    const Self = @This();

    // TODO: For now allocate minimal object count, need better usage of vram on windows.
    const MAX_OBJECTS = 100_000; // TODO: From max ID
    const MAX_OBJIDSETS = 100_000;

    allocator: std.mem.Allocator,
    db: *DbId,

    // Type data
    name: []const u8,
    type_hash: StrId32,
    type_idx: public.TypeIdx,
    props_def: []public.PropDef,

    //props_size: usize,

    version: public.TypeVersion = 1,
    changed_objs: ChangedObjects,

    default_obj: public.ObjId = public.OBJID_ZERO,

    // Per ObjectId data
    objid_pool: cetech1.mem.IdPool(u32),
    objid2obj: cetech1.mem.VirtualArray(?*Object),
    objid_ref_count: cetech1.mem.VirtualArray(AtomicInt32),
    //objid_version: cetech1.mem.VirtualArray(AtomicInt64),
    objid_gen: cetech1.mem.VirtualArray(public.ObjIdGen),
    objid2refs: cetech1.mem.VirtualArray(ReferencerIdSet),
    objid2refs_lock: cetech1.mem.VirtualArray(std.Thread.Mutex), //TODO: without lock?
    prototype2instances: cetech1.mem.VirtualArray(PrototypeInstanceSet),
    prototype2instances_lock: cetech1.mem.VirtualArray(std.Thread.Mutex), //TODO: without lock?

    // Per Object data
    object_pool: cetech1.mem.VirtualPool(Object),
    // Memory fro object property memory (properties memory)
    objs_mem: cetech1.mem.VirtualArray(PropertyValue), // NOTE: move memory after object? . [[Object1][padding][props_mem1]]...[[ObjectN][props_memN]]

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

    // Buffers for profiler
    gc_name: [256:0]u8 = undefined,

    // New
    read_counter: *f64 = undefined,
    write_commit_counter: *f64 = undefined,
    writers_counter: *f64 = undefined,

    pub fn init(allocator: std.mem.Allocator, db: *DbId, type_idx: public.TypeIdx, name: []const u8, props_def: []const public.PropDef) !Self {
        var contain_set = false;
        var contain_subobject = false;

        for (props_def) |prop| {
            switch (prop.type) {
                .REFERENCE_SET, .SUBOBJECT_SET => contain_set = true,
                .SUBOBJECT => contain_subobject = true,
                else => {},
            }

            if (prop.type == .REFERENCE_SET or prop.type == .SUBOBJECT_SET) {}
        }

        var copy_def = try std.ArrayList(public.PropDef).initCapacity(_allocator, props_def.len);
        copy_def.appendSliceAssumeCapacity(props_def);

        var ts = TypeStorage{
            .db = db,
            .name = name,
            .type_hash = strId32(name),
            .type_idx = type_idx,
            .props_def = try copy_def.toOwnedSlice(),
            .allocator = allocator,
            .contain_set = contain_set,
            .contain_subobject = contain_subobject,
            .changed_objs = ChangedObjects.init(allocator),
            .object_pool = try cetech1.mem.VirtualPool(Object).init(allocator, MAX_OBJECTS),

            .objid_pool = cetech1.mem.IdPool(u32).init(allocator),
            .objid2obj = try cetech1.mem.VirtualArray(?*Object).init(MAX_OBJECTS),
            .objid_gen = try cetech1.mem.VirtualArray(public.ObjIdGen).init(MAX_OBJECTS),
            .objid_ref_count = try cetech1.mem.VirtualArray(AtomicInt32).init(MAX_OBJECTS),
            //.objid_version = try cetech1.mem.VirtualArray(AtomicInt64).init(MAX_OBJECTS),
            .objid2refs = try cetech1.mem.VirtualArray(ReferencerIdSet).init(MAX_OBJECTS),
            .objid2refs_lock = try cetech1.mem.VirtualArray(std.Thread.Mutex).init(MAX_OBJECTS),
            .prototype2instances = try cetech1.mem.VirtualArray(PrototypeInstanceSet).init(MAX_OBJECTS),
            .prototype2instances_lock = try cetech1.mem.VirtualArray(std.Thread.Mutex).init(MAX_OBJECTS),

            .objs_mem = try cetech1.mem.VirtualArray(PropertyValue).init(MAX_OBJECTS * props_def.len),

            .to_free_queue = ToFreeIdQueue.init(),
            .to_free_obj_node_pool = ToFreeIdQueueNodePool.init(allocator),

            .idset_pool = if (contain_set) try IdSetPool.init(allocator, MAX_OBJIDSETS) else undefined,

            .aspect_map = TypeAspectMap.init(allocator),
            .strid2aspectname = StrId2TypeAspectName.init(allocator),
            .property_aspect_map = PropertyTypeAspectMap.init(allocator),

            .write_commit_count = AtomicInt32.init(0),
            .writers_created_count = AtomicInt32.init(0),
            .read_obj_count = AtomicInt32.init(0),
        };

        _ = try std.fmt.bufPrintZ(&ts.gc_name, "CDB:GC: {s}", .{ts.name});

        var buf: [128]u8 = undefined;
        ts.read_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/{s}/readers", .{ db.name, name }));
        ts.write_commit_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/{s}/commits", .{ db.name, name }));
        ts.writers_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/{s}/writers", .{ db.name, name }));

        return ts;
    }

    pub fn deinit(self: *Self) void {
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
        self.objid_gen.deinit();
        self.prototype2instances.deinit();
        self.prototype2instances_lock.deinit();
        self.changed_objs.deinit();

        _allocator.free(self.props_def);
    }

    fn notifyAlloc(self: *Self) !void {
        try self.objid2obj.notifyAlloc(1);
        try self.objid_ref_count.notifyAlloc(1);
        //try self.objid_version.notifyAlloc(1);
        try self.objid2refs.notifyAlloc(1);
        try self.objid2refs_lock.notifyAlloc(1);
        try self.prototype2instances.notifyAlloc(1);
        try self.prototype2instances_lock.notifyAlloc(1);
    }

    pub fn isTypeHashValidForProperty(self: *Self, prop_idx: u32, type_idx: public.TypeIdx) bool {
        if (self.props_def[prop_idx].type_hash.isEmpty()) return true;
        return type_idx.eql(self.db.getTypeIdx(self.props_def[prop_idx].type_hash).?);
    }

    fn allocateObjId(self: *Self) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var is_new = false;
        const id = self.objid_pool.create(&is_new);

        if (is_new) {
            try self.notifyAlloc();
            self.objid_gen.items[id] = 1;
        }

        const gen = self.objid_gen.items[id];

        self.objid_ref_count.items[id] = AtomicInt32.init(1);
        //self.objid_version.items[id] = AtomicInt64.init(1);

        if (is_new) {
            self.objid2refs.items[id] = ReferencerIdSet.init(_allocator);
            self.prototype2instances.items[id] = PrototypeInstanceSet.init(_allocator);
        } else {
            self.objid2refs.items[id].clearRetainingCapacity();
            self.prototype2instances.items[id].clearRetainingCapacity();
        }
        self.objid2refs_lock.items[id] = std.Thread.Mutex{};
        self.prototype2instances_lock.items[id] = std.Thread.Mutex{};

        return .{
            .id = @as(u24, @truncate(id)),
            .gen = gen,
            .type_idx = self.type_idx,
            .db = self.db.idx,
        };
    }

    pub fn increaseVersion(self: *Self, obj: public.ObjId) void {
        var obj_ptr = self.db.getObjectPtr(obj).?;
        _ = obj_ptr.version.fetchAdd(1, .monotonic);
        self.changed_objs.addChangedObjects(self.version, &.{obj}) catch undefined;
        self.version += 1;
    }

    pub fn increaseReference(self: *Self, obj: public.ObjId) void {
        _ = self.objid_ref_count.items[obj.id].fetchAdd(1, .release);
    }

    pub fn decreaseReferenceToFree(self: *Self, object: *Object) !void {
        var ref_count = &self.objid_ref_count.items[object.objid.id];

        if (ref_count.raw == 0) return; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        if (1 == ref_count.fetchSub(1, .release)) {
            ref_count.fence(.acquire);
            try self.addToFreeQueue(object);
            self.objid_gen.items[object.objid.id] = @addWithOverflow(self.objid_gen.items[object.objid.id], 1)[0];
        }
    }

    fn decreaseReferenceFree(self: *Self, object: *Object, destroyed_objid: *std.ArrayList(public.ObjId), tmp_allocator: std.mem.Allocator) anyerror!u32 {
        var ref_count = &self.objid_ref_count.items[object.objid.id];

        if (ref_count.raw == 0) return 0; // TODO: need this?
        //std.debug.assert(ref_count.value != 0);

        // if (!object.parent.isEmpty()) {
        //     return try self.freeObject(object, destroyed_objid, tmp_allocator);
        // }

        if (1 == ref_count.fetchSub(1, .release)) {
            ref_count.fence(.acquire);
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
        try self.objid_pool.destroy(objid.id);
    }

    fn allocateObject(self: *Self, id: ?public.ObjId, init_props: bool) !*Object {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var new = false;
        var obj = self.object_pool.create(&new);

        if (self.props_def.len != 0 and new) {
            try self.objs_mem.notifyAlloc(self.props_def.len);
        }

        var obj_mem: [*]PropertyValue = self.objs_mem.items + (self.props_def.len * self.object_pool.index(obj));

        obj.* = Object{
            .objid = id orelse public.OBJID_ZERO,
            .props_mem = obj_mem[0..self.props_def.len],
            .parent_prop_idx = 0,
            .overrides_set = if (new) OverridesSet.initEmpty() else obj.*.overrides_set,
            .version = AtomicInt64.init(1),
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

    pub fn allocateBlob(self: *Self, size: usize) !*Blob {
        var b = try self.allocator.create(Blob);
        b.b = try self.allocator.alloc(u8, size);
        return b;
    }

    pub fn destroyBlob(self: *Self, blob: *Blob) void {
        self.allocator.free(blob.b);
        self.allocator.destroy(blob);
    }

    pub fn cloneBlob(self: *Self, blob: *const Blob) !*Blob {
        const new_blob = try self.allocateBlob(blob.b.len);
        @memcpy(new_blob.b, blob.b);
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

        return id;
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const prototype_obj = self.db.getObjectPtr(prototype).?;
        var new_object = try self.cloneObjectRaw(prototype_obj, true, false, false);
        new_object.prototype = prototype_obj.objid;

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
            new_obj.prototype = obj.prototype;
            new_obj.parent = obj.parent;
            new_obj.parent_prop_idx = obj.parent_prop_idx;
            new_obj.version = obj.version;
        }

        new_obj.overrides_set = obj.overrides_set;

        // var it = obj.overrides_set.iterator(.{});
        // while (it.next()) |value| {
        //     new_obj.overrides_set.setValue(value, obj.overrides_set.isSet(value));
        // }

        @memcpy(new_obj.props_mem, obj.props_mem);

        // Patch old nonsimple value to new location
        for (self.props_def, 0..) |prop_def, idx| {
            switch (prop_def.type) {
                // Duplicate
                // public.PropType.STR => {
                //     const true_ptr = new_obj.getPropPtr([:0]u8, idx);
                //     if (true_ptr.len != 0) {
                //         true_ptr.* = try self.allocator.dupeZ(u8, true_ptr.*);
                //     }
                // },

                // Clone subobject if alocate new
                public.PropType.SUBOBJECT => {
                    const true_ptr = new_obj.getPropPtr(public.ObjId, idx);
                    if (true_ptr.*.isEmpty()) continue;
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
                    if (true_ptr.*.isEmpty()) continue;
                    //var storage = self.db.getTypeStorage(true_ptr.*.type_hash).?;
                    //storage.increaseReference(true_ptr.*);
                },

                public.PropType.SUBOBJECT_SET => {
                    const true_ptr = new_obj.getPropPtr(*ObjIdSet, idx);

                    if (clone_subobject and clone_set) {
                        var new_set = try self.allocateObjIdSet();

                        const set = true_ptr.*.getAddedItems();
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
                        const set = true_ptr.*.getAddedItems();
                        for (set) |ref| {
                            const storage = self.db.getTypeStorage(ref).?;
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
                    const set = true_ptr.*.getAddedItems();
                    for (set) |ref| {
                        _ = ref;
                        //var storage = self.db.getTypeStorage(ref.type_hash).?;
                        //storage.increaseReference(ref);
                    }
                },

                // Duplicate
                public.PropType.BLOB => {
                    const true_ptr = new_obj.getPropPtr(?*Blob, idx);
                    if (true_ptr.*) |blob| {
                        true_ptr.* = try self.cloneBlob(blob);
                    }
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
                // .STR => {
                //     const true_ptr = obj.getPropPtr([:0]u8, idx);
                //     if (true_ptr.len != 0) {
                //         self.allocator.free(true_ptr.*);
                //     }
                // },
                .BLOB => {
                    const true_ptr = obj.getPropPtr(?*Blob, idx);
                    if (true_ptr.*) |blob| {
                        self.destroyBlob(blob);
                    }
                },
                .SUBOBJECT => {
                    const subobj = obj.getPropPtr(public.ObjId, idx);
                    const subobj_ptr = self.db.getObjectPtr(subobj.*) orelse continue;
                    var storage = self.db.getTypeStorage(subobj_ptr.objid).?;

                    if (!is_writer) {
                        free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                        //free_objects += try storage.decreaseReferenceFree(subobj_ptr, destroyed_objid, tmp_allocator);
                    }
                },
                .SUBOBJECT_SET => {
                    const true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    const set = true_ptr.*.getAddedItems();

                    for (set) |subobj| {
                        const subobj_ptr = self.db.getObjectPtr(subobj) orelse continue;
                        var storage = self.db.getTypeStorage(subobj).?;
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
                    var storage = self.db.getTypeStorage(ref_ptr.objid).?;
                    if (!is_writer) {
                        storage.removeObjIdReferencer(ref.*, obj.objid);
                    }
                    //free_objects += try storage.decreaseReferenceFree(ref_ptr, destroyed_objid, tmp_allocator);
                },
                .REFERENCE_SET => {
                    const true_ptr = obj.getPropPtr(*ObjIdSet, idx);

                    const set = true_ptr.*.getAddedItems();
                    for (set) |ref_id| {
                        const ref_ptr = self.db.getObjectPtr(ref_id) orelse continue;
                        var storage = self.db.getTypeStorage(ref_ptr.objid).?;
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
                const storage = self.db.getTypeStorage(referencer) orelse continue;
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
                var storage = self.db.getTypeStorage(obj.parent).?;
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

            if (!obj.prototype.isEmpty()) {
                self.removePrototypeInstance(obj.prototype, obj.objid);
            }

            //self.objid_gen.items[obj.objid.id] = @addWithOverflow(self.objid_gen.items[obj.objid.id], 1)[0];

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

        var changed_ids = std.ArrayList(public.ObjId).init(tmp_allocator);
        defer changed_ids.deinit();

        var free_objects: u32 = 0;
        while (self.to_free_queue.pop()) |node| {
            try changed_ids.append(node.data.objid);

            free_objects += try self.freeObject(node.data, &destroyed_ids, tmp_allocator);
            self.to_free_obj_node_pool.destroy(node);
        }

        try self.changed_objs.addChangedObjects(self.version, destroyed_ids.items);

        self.db.callOnObjIdDestroyed(destroyed_ids.items);

        if (destroyed_ids.items.len != 0) {
            self.version += 1;
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
        if (!true_obj.prototype.isEmpty() and !true_obj.overrides_set.isSet(prop_idx)) {
            const prototype_obj = self.db.getObjectPtr(true_obj.prototype);
            if (prototype_obj) |proto_obj| {
                return readGeneric(self, @ptrCast(proto_obj), prop_idx, prop_type);
            }
        }

        const true_ptr = true_obj.getPropPtr(u8, prop_idx);
        var ptr: [*]const u8 = @ptrCast(true_ptr);
        return ptr[0..@sizeOf(PropertyValue)];
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
        if (!true_obj.prototype.isEmpty()) {
            true_obj.overrides_set.set(prop_idx);
        }

        const true_ptr = true_obj.getPropPtr(u8, prop_idx);
        var ptr: [*]u8 = @ptrCast(true_ptr);
        const ptr2 = ptr[0..@sizeOf(PropertyValue)];
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

    pub fn instantiateSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        const value = self.readTT(public.ObjId, writer, prop_idx, public.PropType.SUBOBJECT);
        if (value.isEmpty()) return .{};

        var storage = self.db.getTypeStorage(value).?;
        const new_subobj = try storage.createObjectFromPrototype(value);
        //self.setTT(public.CdbObjIdT, writer, prop_idx, c.CT_CDB_OBJID_ZERO, public.PropertyType.SUBOBJECT);
        try self.db.setSubObj(writer, prop_idx, @ptrCast(self.db.getObjectPtr(new_subobj).?));
        return new_subobj;
    }

    pub fn instantiateSubObjFromSet(self: *Self, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var storage = self.db.getTypeStorage(set_obj).?;
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

const StringIntern = cetech1.mem.StringInternWithLock([:0]const u8);

pub const DbId = struct {
    const Self = @This();

    name: [:0]const u8,
    idx: public.DbId,

    allocator: std.mem.Allocator,

    typestorage_pool: cetech1.mem.VirtualPool(TypeStorage),
    typestorage_map: TypeStorageMap,

    str_intern: StringIntern,

    // Stats
    free_objects: u32,
    objids_alocated: u32,
    objects_alocated: u32,

    on_obj_destroy_map: OnObjIdDestroyMap,

    read_counter: *f64 = undefined,
    write_commit_counter: *f64 = undefined,
    writers_counter: *f64 = undefined,

    alocated_objects_counter: *f64 = undefined,
    alocated_obj_ids_counter: *f64 = undefined,
    gc_free_objects_counter: *f64 = undefined,

    metrics_init: bool = false,

    pub fn init(allocator: std.mem.Allocator, idx: public.DbId, name: [:0]const u8) !DbId {
        var self: @This() = .{
            .idx = idx,
            .name = name,
            .allocator = allocator,

            .typestorage_map = TypeStorageMap.init(allocator),
            .typestorage_pool = try cetech1.mem.VirtualPool(TypeStorage).init(allocator, 1024), // TODO form config
            .on_obj_destroy_map = OnObjIdDestroyMap.init(allocator),

            .free_objects = 0,
            .objids_alocated = 0,
            .objects_alocated = 0,
            .str_intern = StringIntern.init(allocator),
        };

        var buf: [128]u8 = undefined;
        self.read_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/readers", .{self.name}));
        self.write_commit_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/commits", .{self.name}));
        self.writers_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/writers", .{self.name}));
        self.alocated_objects_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/allocated_objects", .{self.name}));
        self.alocated_obj_ids_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/allocated_ids", .{self.name}));
        self.gc_free_objects_counter = try metrics.api.getCounter(try std.fmt.bufPrint(&buf, "cdb/{s}/free_objects", .{self.name}));

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.gc(self.allocator) catch |err| {
            log.err("Could not GC db on deinit {}", .{err});
            return;
        };

        for (self.typestorage_map.values()) |idx| {
            var storage = self.getTypeStorageByTypeIdx(idx).?;
            storage.deinit();
        }

        self.on_obj_destroy_map.deinit();
        self.typestorage_map.deinit();
        self.typestorage_pool.deinit();
        self.str_intern.deinit();
    }

    pub fn readersCount(self: *Self) usize {
        var i: usize = 0;

        for (self.typestorage_map.values()) |type_map| {
            i += self.getTypeStorageByTypeIdx(type_map).?.read_obj_count.raw;
        }

        return i;
    }

    pub fn writersCount(self: *Self) usize {
        var i: usize = 0;

        for (self.typestorage_map.values()) |type_map| {
            i += self.getTypeStorageByTypeIdx(type_map).?.writers_created_count.raw;
        }

        return i;
    }

    pub fn commitCount(self: *Self) usize {
        var i: usize = 0;

        for (self.typestorage_map.values()) |type_map| {
            i += self.getTypeStorageByTypeIdx(type_map).?.write_commit_count.raw;
        }

        return i;
    }

    pub fn gc(self: *Self, tmp_allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.ZoneN(@src(), "CDB:GC");
        defer zone_ctx.End();

        self.free_objects = 0;
        for (self.typestorage_map.values()) |type_storage| {
            //if (type_storage.to_free_queue.isEmpty()) continue;
            self.free_objects += try self.getTypeStorageByTypeIdx(type_storage).?.gc(tmp_allocator);
        }

        self.objids_alocated = 0;
        for (self.typestorage_map.values()) |type_map| {
            self.objids_alocated += self.getTypeStorageByTypeIdx(type_map).?.objid_pool.count.raw - 1;
        }

        self.objects_alocated = 0;
        for (self.typestorage_map.values()) |type_map| {
            self.objects_alocated += self.getTypeStorageByTypeIdx(type_map).?.object_pool.alocated_items.raw - 1;
        }

        if (profiler.profiler_enabled) {
            self.alocated_obj_ids_counter.* = @floatFromInt(self.objids_alocated);
            self.alocated_objects_counter.* = @floatFromInt(self.objects_alocated);
            self.gc_free_objects_counter.* = @floatFromInt(self.free_objects);

            self.writers_counter.* = @floatFromInt(self.writersCount());
            self.write_commit_counter.* = @floatFromInt(self.commitCount());
            self.read_counter.* = @floatFromInt(self.readersCount());

            for (self.typestorage_map.values()) |type_map| {
                const storage = self.getTypeStorageByTypeIdx(type_map).?;

                storage.read_counter.* = @floatFromInt(storage.read_obj_count.raw);
                storage.writers_counter.* = @floatFromInt(storage.writers_created_count.raw);
                storage.write_commit_counter.* = @floatFromInt(storage.write_commit_count.raw);
            }
        }

        for (self.typestorage_map.values()) |type_map| {
            var storage = self.getTypeStorageByTypeIdx(type_map).?;

            storage.write_commit_count = AtomicInt32.init(0);
            storage.writers_created_count = AtomicInt32.init(0);
            storage.read_obj_count = AtomicInt32.init(0);
        }
    }

    pub fn addOnObjIdDestroyed(self: *Self, fce: OnObjIdDestroyed) !void {
        try self.on_obj_destroy_map.put(fce, {});
    }
    pub fn removeOnObjIdDestroyed(self: *Self, fce: OnObjIdDestroyed) void {
        _ = self.on_obj_destroy_map.swapRemove(fce);
    }

    pub fn callOnObjIdDestroyed(self: *Self, objects: []public.ObjId) void {
        for (self.on_obj_destroy_map.keys()) |fce| {
            fce(self.idx, objects);
        }
    }

    pub fn getTypeStorage(self: *Self, obj: public.ObjId) ?*TypeStorage {
        return self.getTypeStorageByTypeIdx(obj.type_idx);
    }

    pub fn getTypeStorageByTypeHash(self: *Self, type_hash: StrId32) ?*TypeStorage {
        return self.getTypeStorageByTypeIdx(self.typestorage_map.get(type_hash).?);
    }

    pub fn getTypeStorageByTypeIdx(self: *Self, type_idx: public.TypeIdx) ?*TypeStorage {
        return self.typestorage_pool.get(type_idx.idx);
    }

    pub fn getObjectPtr(self: *Self, obj: public.ObjId) ?*Object {
        if (obj.isEmpty()) return null;

        const storage = self.getTypeStorage(obj) orelse return null;
        return storage.objid2obj.items[obj.id];
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
        // var zone_ctx = profiler.ztracy.Zone(@src());
        // defer zone_ctx.End();
        const true_obj = self.getObjectPtr(obj) orelse return 0;
        return true_obj.version.raw;

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

    //     if (obj.prototype != 0) {
    //         var proto_obj = self.getObjectPtr(.{ .id = obj.prototype, .type_hash = obj.objid.type_hash }).?;
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

    pub fn addAspect(self: *Self, type_idx: public.TypeIdx, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        var storage = self.getTypeStorageByTypeIdx(type_idx) orelse return;
        try storage.addAspect(apect_name, aspect_ptr);
    }
    pub fn getAspect(self: *Self, type_idx: public.TypeIdx, aspect_hash: StrId32) ?*anyopaque {
        var storage = self.getTypeStorageByTypeIdx(type_idx) orelse return null;
        return storage.getAspect(aspect_hash);
    }

    pub fn addPropertyAspect(self: *Self, type_idx: public.TypeIdx, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
        var storage = self.getTypeStorageByTypeIdx(type_idx) orelse return;
        try storage.addPropertyAspect(prop_idx, apect_name, aspect_ptr);
    }
    pub fn getPropertyAspect(self: *Self, type_idx: public.TypeIdx, prop_idx: u32, aspect_hash: StrId32) ?*anyopaque {
        var storage = self.getTypeStorageByTypeIdx(type_idx) orelse return null;
        return storage.getPropertyAspect(prop_idx, aspect_hash);
    }

    pub fn getTypeName(self: *Self, type_idx: public.TypeIdx) ?[]const u8 {
        const storage = self.getTypeStorageByTypeIdx(type_idx) orelse return null;
        return storage.name;
    }

    pub fn getTypePropDefIdx(self: *Self, type_idx: public.TypeIdx, prop_name: []const u8) ?u32 {
        const prop_def = self.getTypePropDef(type_idx) orelse return null;

        for (prop_def, 0..) |def, idx| {
            if (std.mem.eql(u8, def.name, prop_name)) return @truncate(idx);
        }
        return null;
    }

    pub fn getOrCreateTypeStorage(self: *Self, type_hash: StrId32, name: []const u8, prop_def: []const public.PropDef) !*TypeStorage {
        if (self.typestorage_map.get(type_hash)) |type_idx| {
            return self.typestorage_pool.get(type_idx.idx);
        }

        const storage = self.typestorage_pool.create(null);
        const idx = self.typestorage_pool.index(storage);
        try self.typestorage_map.put(type_hash, .{ .idx = @intCast(idx) });

        const new_storage = try TypeStorage.init(_allocator, self, .{ .idx = @intCast(idx) }, name, prop_def);
        storage.* = new_storage;

        return storage;
    }

    pub fn getTypePropDef(self: *Self, type_idx: public.TypeIdx) ?[]const public.PropDef {
        const storage = self.getTypeStorageByTypeIdx(type_idx) orelse return null;
        return storage.props_def;
    }

    pub fn addType(self: *Self, name: []const u8, prop_defs: []const public.PropDef) !public.TypeIdx {
        std.debug.assert(prop_defs.len <= MAX_PROPERIES_IN_OBJECT);

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
            //storage.objid_version.reservation.len +
            storage.objid2refs.reservation.len +
            storage.objid2refs_lock.reservation.len +
            storage.prototype2instances.reservation.len +
            storage.prototype2instances_lock.reservation.len);

        log.debug("Register type {s}: {d}|{d}|{d}MB", .{ name, storage.type_idx.idx, type_hash.id, all_vm_size / 1000000 });

        return storage.type_idx;
    }

    pub fn hasTypeSet(self: *Self, type_idx: public.TypeIdx) bool {
        const storate = self.getTypeStorageByTypeIdx(type_idx) orelse return false;
        return storate.contain_set;
    }

    pub fn hasTypeSubobject(self: *Self, type_idx: public.TypeIdx) bool {
        const storate = self.getTypeStorageByTypeIdx(type_idx) orelse return false;
        return storate.contain_subobject;
    }

    pub fn getTypeIdx(self: *Self, type_hash: StrId32) ?public.TypeIdx {
        return self.typestorage_map.get(type_hash);
    }

    pub fn getTypeHash(self: *Self, type_idx: public.TypeIdx) ?public.TypeHash {
        const storate = self.getTypeStorageByTypeIdx(type_idx) orelse return null;
        return storate.type_hash;
    }

    pub fn getChangeObjects(self: *Self, allocator: std.mem.Allocator, type_idx: public.TypeIdx, since_version: public.TypeVersion) !public.ChangedObjects {
        const type_storage = self.getTypeStorageByTypeIdx(type_idx).?;
        if (since_version == 0) return public.ChangedObjects{
            .need_fullscan = true,
            .last_version = type_storage.version,
            .objects = try allocator.alloc(public.ObjId, 0),
        };

        const objs = try type_storage.changed_objs.getSince(allocator, since_version, type_storage.version);

        return public.ChangedObjects{
            .need_fullscan = false,
            .last_version = type_storage.version,
            .objects = objs,
        };
    }

    pub fn isAlive(self: *Self, obj: public.ObjId) bool {
        if (obj.isEmpty()) return false;
        const type_storage = self.getTypeStorageByTypeIdx(obj.type_idx).?;
        return type_storage.objid_gen.items[obj.id] == obj.gen;
    }

    pub fn getRelation(self: *Self, top_level_obj: public.ObjId, obj: public.ObjId, prop_idx: u32, in_set_obj: ?public.ObjId) public.ObjRelation {
        if (!self.isChildOff(top_level_obj, in_set_obj orelse obj)) return .not_owned; // TODO: remove

        const obj_r = self.readObj(obj).?;
        const prototype_obj = self.getPrototype(self.readObj(obj).?);
        const has_prototype = !prototype_obj.isEmpty();
        const prop_type = self.getTypePropDef(obj.type_idx).?[prop_idx].type;

        if (has_prototype) {
            if (in_set_obj) |iso| {
                const in_set_obj_r = self.readObj(iso).?;
                if (self.isIinisiated(obj_r, prop_idx, in_set_obj_r)) return .inisiated;
            } else {
                if (self.isPropertyOverrided(obj_r, prop_idx)) {
                    if (prop_type == .SUBOBJECT) {
                        const subobj = self.readSubObj(obj_r, prop_idx).?;
                        const subobj_r = self.readObj(subobj).?;

                        if (self.isIinisiated(obj_r, prop_idx, subobj_r)) {
                            return .inisiated;
                        }
                    } else {
                        return .overide;
                    }
                } else {
                    return .inheried;
                }
            }
        }
        return .owned;
    }

    pub fn inisitateDeep(self: *Self, allocator: std.mem.Allocator, last_parent: public.ObjId, to_inisiated_obj: public.ObjId) ?public.ObjId {
        const last_obj_r = self.readObj(last_parent).?;
        const last_obj_proto = self.getPrototype(last_obj_r);

        if (last_obj_proto.isEmpty()) return null;

        const Path = struct {
            obj: public.ObjId,
            parent_prop_idx: u32,
            parent_prop_type: public.PropType,
        };

        // Find path to last_obj_proto
        var paths = std.ArrayList(Path).init(allocator);
        defer paths.deinit();

        var it = to_inisiated_obj;
        while (!it.isEmpty()) {
            if (it.eql(last_obj_proto)) break;

            const true_obj = self.getObjectPtr(it).?;

            const paret_prop_def = self.getTypePropDef(true_obj.parent.type_idx).?;
            const parent_prop_type = paret_prop_def[true_obj.parent_prop_idx].type;

            paths.append(.{
                .obj = it,
                .parent_prop_idx = true_obj.parent_prop_idx,
                .parent_prop_type = parent_prop_type,
            }) catch return null;

            it = true_obj.parent;
        }

        if (paths.items.len == 0) return null;

        var instansited_obj: ?public.ObjId = null;

        var lp = last_parent;
        var it_idx = paths.items.len;
        while (it_idx != 0) {
            const idx = it_idx - 1;
            const p = paths.items[idx];

            if (p.parent_prop_type == .SUBOBJECT) {
                const lp_w = self.writerObj(lp).?;
                instansited_obj = self.instantiateSubObj(lp_w, p.parent_prop_idx) catch undefined;
            } else if (p.parent_prop_type == .SUBOBJECT_SET) {
                const lp_w = self.writerObj(lp).?;
                instansited_obj = self.instantiateSubObjFromSet(lp_w, p.parent_prop_idx, p.obj) catch undefined;
            } else {
                return null;
            }

            lp = p.obj;

            it_idx -= 1;
        }

        return instansited_obj;
    }

    pub fn registerAllTypes(self: *Self) !void {
        {
            const impls = try apidb.api.getImpl(self.allocator, public.CreateTypesI);
            defer self.allocator.free(impls);
            for (impls) |iface| {
                iface.create_types(self.idx);
            }
        }

        {
            const impls = try apidb.api.getImpl(self.allocator, public.PostCreateTypesI);
            defer self.allocator.free(impls);
            for (impls) |iface| {
                iface.post_create_types(self.idx) catch undefined;
            }
        }
    }

    pub fn createObject(self: *Self, type_idx: public.TypeIdx) !public.ObjId {
        var storage = self.getTypeStorageByTypeIdx(type_idx).?;
        return try storage.createObj();
    }

    pub fn createObjectFromPrototype(self: *Self, prototype: public.ObjId) !public.ObjId {
        var storage = self.getTypeStorage(prototype).?;
        return try storage.createObjectFromPrototype(prototype);
    }

    pub fn setDefaultObject(self: *Self, default: public.ObjId) void {
        var storage = self.getTypeStorage(default).?;
        storage.setDefaultObject(default);
    }

    pub fn cloneObject(self: *Self, obj: public.ObjId) anyerror!public.ObjId { // TODO:why anyerorr?
        var storage = self.getTypeStorage(obj).?;
        return storage.cloneObject(obj);
    }

    pub fn destroyObject(self: *Self, obj: public.ObjId) void {
        var storage = self.getTypeStorage(obj) orelse return;
        storage.destroyObj(obj) catch |err| {
            log.warn("Error while destroing object: {}", .{err});
        };
    }

    pub fn writerObj(self: *Self, obj: public.ObjId) ?*public.Obj {
        const true_obj = self.getObjectPtr(obj);
        var storage = self.getTypeStorage(obj) orelse return null;
        _ = storage.writers_created_count.fetchAdd(1, .monotonic);

        storage.increaseReference(obj);
        const new_obj = storage.cloneObjectRaw(true_obj.?, false, false, false) catch |err| {
            log.err("Could not crate writer {}", .{err});
            return null;
        };
        return @ptrCast(new_obj);
    }

    pub fn retargetWriter(self: *Self, writer: *public.Obj, obj: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);
        var storage = self.getTypeStorage(true_obj.objid).?;

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
                    if (true_ptr.*.isEmpty()) continue;
                    const sub_obj_ptr = self.getObjectPtr(true_ptr.*).?;
                    sub_obj_ptr.parent = true_obj.objid;
                },
                public.PropType.SUBOBJECT_SET => {
                    const true_ptr = true_obj.getPropPtr(*ObjIdSet, idx);

                    const set = true_ptr.*.getAddedItems();
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

        var storage = self.getTypeStorage(new_obj.objid).?;
        _ = storage.write_commit_count.fetchAdd(1, .monotonic);

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
        std.debug.assert(obj.objid.id != obj.parent.id or obj.objid.type_idx.idx != obj.parent.type_idx.idx);

        var storage = self.getTypeStorage(obj.objid).?;
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
        const storage = self.getTypeStorage(obj) orelse return null;
        _ = storage.read_obj_count.fetchAdd(1, .monotonic);
        return @ptrCast(true_obj);
    }

    pub fn readGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, prop_type: public.PropType) []const u8 {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid).?;
        return storage.readGeneric(obj, prop_idx, prop_type);
    }

    pub fn readT(self: *Self, comptime T: type, obj: *public.Obj, prop_idx: u32) T {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid).?;
        return storage.readT(T, obj, prop_idx);
    }

    pub fn readSubObj(self: *Self, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid).?;
        const value = storage.readTT(public.ObjId, obj, prop_idx, public.PropType.SUBOBJECT);
        return if (value.isEmpty()) null else value;
    }

    pub fn readRef(self: *Self, obj: *public.Obj, prop_idx: u32) ?public.ObjId {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid).?;

        const value = storage.readTT(public.ObjId, obj, prop_idx, public.PropType.REFERENCE);
        return if (value.isEmpty()) null else value;
    }

    pub fn readStr(self: *Self, obj: *public.Obj, prop_idx: u32) ?[:0]const u8 {
        const id = std.mem.bytesToValue(StringIntern.InternId, self.readGeneric(obj, prop_idx, .STR));
        if (id.isEmpty()) return null;
        return self.str_intern.findById(id);
    }

    pub fn setGeneric(self: *Self, obj: *public.Obj, prop_idx: u32, value: [*]const u8, prop_type: public.PropType) void {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid).?;
        storage.setGeneric(obj, prop_idx, value, prop_type);
    }

    pub fn setT(self: *Self, comptime T: type, writer: *public.Obj, prop_idx: u32, value: T) void {
        const true_obj = toObjFromObjO(writer);
        var storage = self.getTypeStorage(true_obj.objid).?;
        return storage.setT(T, writer, prop_idx, value);
    }

    pub fn setStr(self: *Self, writer: *public.Obj, prop_idx: u32, value: [:0]const u8) !void {
        var true_obj = toObjFromObjO(writer);

        const true_ptr = true_obj.getPropPtr(StringIntern.InternId, prop_idx);
        true_ptr.* = try self.str_intern.internToHash(value);

        // If exist prototype set override flag to prop.
        if (!true_obj.prototype.isEmpty()) {
            true_obj.overrides_set.set(prop_idx);
        }
    }

    pub fn setSubObj(self: *Self, writer: *public.Obj, prop_idx: u32, subobj_writer: *public.Obj) !void {
        const true_obj = toObjFromObjO(writer);
        const true_sub_obj = toObjFromObjO(subobj_writer);

        var obj_storage = self.getTypeStorage(true_obj.objid).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_idx)) {
            log.warn("Invalid type_hash for set sub obj", .{});
            return;
        }

        const has_prototype = !self.getPrototype(writer).isEmpty();
        const is_overided = self.isPropertyOverrided(writer, prop_idx);

        if (!has_prototype and !is_overided) {
            if (self.readSubObj(writer, prop_idx)) |old_subobj| {
                const old_subobj_ptr = self.getObjectPtr(old_subobj).?;
                var old_subobj_storage = self.getTypeStorage(old_subobj).?;
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
                var old_subobj_storage = self.getTypeStorage(old_subobj).?;
                _ = try old_subobj_storage.decreaseReferenceToFree(old_subobj_ptr);
            }
        }

        var obj_storage = self.getTypeStorage(true_obj.objid).?;
        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.SUBOBJECT);
    }

    pub fn clearRef(self: *Self, writer: *public.Obj, prop_idx: u32) !void {
        const true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid).?;

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_storage = self.getTypeStorage(ref).?;
            old_ref_storage.removeObjIdReferencer(ref, true_obj.objid);
            //var old_ref_ptr = self.getObjectPtr(ref).?;
            //_ = try old_ref_storage.decreaseReferenceToFree(old_ref_ptr);
        }

        obj_storage.setTT(public.ObjId, writer, prop_idx, public.OBJID_ZERO, public.PropType.REFERENCE);
    }

    pub fn setRef(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        const true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid).?;
        if (!obj_storage.isTypeHashValidForProperty(prop_idx, value.type_idx)) {
            log.warn("Invalid type_hash for set ref", .{});
            return;
        }

        if (self.readRef(writer, prop_idx)) |ref| {
            var old_ref_storage = self.getTypeStorage(ref).?;
            old_ref_storage.removeObjIdReferencer(ref, true_obj.objid);

            //var old_ref_ptr = self.getObjectPtr(ref).?;
            //_ = try old_ref_storage.decreaseReferenceToFree(old_ref_ptr);
        }

        var storage = self.getTypeStorage(value).?;
        try storage.addObjIdReferencer(value, true_obj.objid, prop_idx);
        //storage.increaseReference(value);

        obj_storage.setTT(public.ObjId, writer, prop_idx, value, public.PropType.REFERENCE);
    }

    pub fn addRefToSet(self: *Self, writer: *public.Obj, prop_idx: u32, values: []const public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid).?;

        if (builtin.mode == .Debug) {
            const real_type = obj_storage.props_def[prop_idx].type;
            std.debug.assert(real_type == public.PropType.REFERENCE_SET);
        } // else: just belive

        for (values) |value| {
            if (!obj_storage.isTypeHashValidForProperty(prop_idx, value.type_idx)) {
                log.warn("Invalid type_hash for add to ref set", .{});
                continue;
            }

            const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            if (!(try array.*.add(value))) {
                continue;
            }

            var storage = self.getTypeStorage(value).?;
            //storage.increaseReference(value);
            try storage.addObjIdReferencer(value, true_obj.objid, prop_idx);
        }
    }

    pub fn removeFromRefSet(self: *Self, writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
        var true_obj = toObjFromObjO(writer);

        if (!self.isInSet(true_obj, prop_idx, value)) return;

        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(value)) {
            var ref_obj_storage = self.getTypeStorage(value).?;
            ref_obj_storage.removeObjIdReferencer(value, true_obj.objid);
            //var ref_obj = self.getObjectPtr(value);
            //_ = try ref_obj_storage.decreaseReferenceToFree(ref_obj.?);
            self.increaseVersionToAll(true_obj);
        }
    }

    pub fn removeFromSubObjSet(self: *Self, writer: *public.Obj, prop_idx: u32, sub_writer: *public.Obj) !void {
        var true_obj = toObjFromObjO(writer);
        const true_sub_obj = toObjFromObjO(sub_writer);

        if (!self.isInSet(true_obj, prop_idx, true_sub_obj.objid)) return;

        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);

        if (try array.*.remove(true_sub_obj.objid)) {
            var ref_obj_storage = self.getTypeStorage(true_sub_obj.objid).?;
            _ = try ref_obj_storage.decreaseReferenceToFree(true_sub_obj);
            self.increaseVersionToAll(true_obj);
        }
    }

    pub fn createBlob(self: *Self, writer: *public.Obj, prop_idx: u32, size: usize) !?[]u8 {
        var true_obj = toObjFromObjO(writer);

        var obj_storage = self.getTypeStorage(true_obj.objid).?;

        // var prev_blob = self.readBlob(writer, prop_idx);
        // obj_storage.destroyBlob(prev_blob);
        const prev_blob = true_obj.getPropPtr(?*Blob, prop_idx);

        if (prev_blob.*) |blob| {
            obj_storage.destroyBlob(blob);
        }

        const blob = try obj_storage.allocateBlob(size);
        obj_storage.setTT(?*Blob, writer, prop_idx, blob, public.PropType.BLOB);
        return blob.b;
    }

    pub fn readBlob(self: *Self, obj: *public.Obj, prop_idx: u32) []u8 {
        const true_obj = toObjFromObjO(obj);
        var storage = self.getTypeStorage(true_obj.objid).?;

        const b = storage.readTT(?*Blob, obj, prop_idx, public.PropType.BLOB) orelse return &.{};
        return b.b;
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

    pub fn readSubObjSetShallow(self: *Self, writer: *public.Obj, prop_idx: u32) []const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetAddedShallow(writer, prop_idx);
    }

    pub fn readRefSetShallow(self: *Self, writer: *public.Obj, prop_idx: u32) []const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetAddedShallow(writer, prop_idx);
    }

    pub fn readSubObjSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32) []const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        return self.readSetRemovedShallow(writer, prop_idx);
    }

    pub fn readRefSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32) []const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();
        return self.readSetRemovedShallow(writer, prop_idx);
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

    fn readSetAddedShallow(self: *Self, writer: *public.Obj, prop_idx: u32) []const public.ObjId {
        _ = self;
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);
        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
        return array.*.getAddedItems();
    }

    fn readSetRemovedShallow(self: *Self, writer: *public.Obj, prop_idx: u32) []const public.ObjId {
        _ = self;
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);
        const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
        return array.*.getRemovedItems();
    }

    fn readSet(self: *Self, writer: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ![]const public.ObjId {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var true_obj = toObjFromObjO(writer);

        // Fast path for non prototype
        if (true_obj.prototype.isEmpty()) {
            const array = true_obj.getPropPtr(*ObjIdSet, prop_idx);
            return try allocator.dupe(public.ObjId, array.*.getAddedItems());
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

            true_it_obj = self.getObjectPtr(obj.prototype);
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

        if (!true_obj.prototype.isEmpty()) {
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

        var obj_storage = self.getTypeStorage(true_obj.objid).?;

        if (builtin.mode == .Debug) {
            const real_type = obj_storage.props_def[prop_idx].type;
            std.debug.assert(real_type == public.PropType.SUBOBJECT_SET);
        } // else: just belive

        for (sub_obj_writers) |sub_obj_writer| {
            const true_sub_obj = toObjFromObjO(sub_obj_writer);
            if (!obj_storage.isTypeHashValidForProperty(prop_idx, true_sub_obj.objid.type_idx)) {
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
        if (obj_ptr.prototype.isEmpty()) return;
        obj_ptr.overrides_set.unset(prop_idx);
    }

    pub fn isPropertyOverrided(self: *Self, obj: *public.Obj, prop_idx: u32) bool {
        const true_obj = toObjFromObjO(obj);
        var obj_storage = self.getTypeStorage(true_obj.objid).?;
        return obj_storage.isPropertyOverrided(obj, prop_idx);
    }

    pub fn getPrototype(self: *Self, obj: *public.Obj) public.ObjId {
        _ = self;
        const true_obj = toObjFromObjO(obj);
        return true_obj.prototype;
    }

    pub fn instantiateSubObj(self: *Self, writer: *public.Obj, prop_idx: u32) !public.ObjId {
        const true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid).?;
        return try obj_storage.instantiateSubObj(writer, prop_idx);
    }

    pub fn instantiateSubObjFromSet(self: *Self, writer: *public.Obj, prop_idx: u32, set_obj: public.ObjId) !public.ObjId {
        const true_obj = toObjFromObjO(writer);
        var obj_storage = self.getTypeStorage(true_obj.objid).?;
        return obj_storage.instantiateSubObjFromSet(writer, prop_idx, set_obj);
    }

    fn canIinisiate(self: *Self, obj: *public.Obj, inisiated_obj: *public.Obj) bool {
        _ = self;
        const true_obj = toObjFromObjO(obj);
        var true_inisiated_obj = toObjFromObjO(inisiated_obj);

        if (true_obj.prototype.isEmpty()) return false;

        const protoype_id = true_obj.prototype;

        return true_inisiated_obj.parent.eql(protoype_id);
    }

    fn isIinisiated(self: *Self, obj: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) bool {
        var true_obj = toObjFromObjO(obj);
        const true_inisiated_obj = toObjFromObjO(inisiated_obj);

        const prototype = true_obj.prototype;
        if (prototype.isEmpty()) return false;

        const type_props = self.getTypePropDef(true_obj.objid.type_idx).?;

        switch (type_props[set_prop_idx].type) {
            .SUBOBJECT => {
                if (self.readSubObj(obj, set_prop_idx)) |subobj| {
                    const proto_r = self.readObj(subobj).?;
                    const pproto_r = self.readObj(prototype).?;
                    if (self.readSubObj(pproto_r, set_prop_idx)) |proto_subobj| {
                        const my_proto = self.getPrototype(proto_r);
                        return my_proto.eql(proto_subobj);
                    }
                }
            },
            .SUBOBJECT_SET, .REFERENCE_SET => {
                const idset = true_obj.getPropPtr(*ObjIdSet, set_prop_idx);

                const protoype_id = true_inisiated_obj.prototype;

                return idset.*.added.contains(true_inisiated_obj.objid) and idset.*.removed.contains(protoype_id);
            },
            else => undefined,
        }

        return false;
    }

    fn restoreDeletedInSet(self: *Self, obj: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) void {
        _ = self;
        var true_obj = toObjFromObjO(obj);
        const true_inisiated_obj = toObjFromObjO(inisiated_obj);

        if (true_obj.prototype.isEmpty()) return;

        const idset = true_obj.getPropPtr(*ObjIdSet, set_prop_idx);
        idset.*.removeFromRemoved(true_inisiated_obj.objid);
    }

    pub fn setPrototype(self: *Self, obj: public.ObjId, prototype: public.ObjId) !void {
        var obj_r = self.getObjectPtr(obj).?;
        var storage = self.getTypeStorage(obj).?;

        if (!obj_r.prototype.isEmpty()) {
            storage.removePrototypeInstance(self.getPrototype(obj_r), obj);
        }

        obj_r.prototype = prototype;

        if (!prototype.isEmpty()) {
            try storage.addPrototypeInstance(prototype, obj);
        }
        self.increaseVersionToAll(obj_r);
    }

    pub fn getDefaultObject(self: *Self, type_idx: public.TypeIdx) ?public.ObjId {
        var storage = self.getTypeStorageByTypeIdx(type_idx).?;
        return if (storage.default_obj.isEmpty()) null else storage.default_obj;
    }

    pub fn getFirstObject(self: *Self, type_idx: public.TypeIdx) public.ObjId {
        const storage = self.getTypeStorageByTypeIdx(type_idx).?;
        for (1..storage.objid_pool.count.raw) |idx| {
            if (storage.objid2obj.items[idx] == null) continue;
            return .{ .id = @intCast(idx), .gen = storage.objid_gen.items[idx], .type_idx = type_idx, .db = self.idx };
        }

        return public.OBJID_ZERO;
    }

    pub fn getAllObjectByType(self: *Self, allocator: std.mem.Allocator, type_idx: public.TypeIdx) ?[]public.ObjId {
        const storage = self.getTypeStorageByTypeIdx(type_idx).?;
        var result = std.ArrayList(public.ObjId).init(allocator);
        for (1..storage.objid_pool.count.raw) |idx| {
            if (storage.objid2obj.items[idx] == null) continue;

            result.append(.{ .id = @intCast(idx), .gen = storage.objid_gen.items[idx], .type_idx = type_idx, .db = self.idx }) catch {
                result.deinit();
                return null;
            };
        }

        return result.toOwnedSlice() catch null;
    }

    pub fn stressIt(self: *Self, type_idx: public.TypeIdx, type_hash2: public.TypeIdx, ref_obj1: cetech1.cdb.ObjId) !void {
        const obj1 = try self.createObject(type_idx);

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

    pub fn getReferencerSet(self: *Self, allocator: std.mem.Allocator, obj: public.ObjId) ![]public.ObjId {
        var storage = self.getTypeStorage(obj).?;
        const keys = storage.objid2refs.items[obj.id].keys();
        const new_set = try allocator.alloc(public.ObjId, keys.len);
        @memcpy(new_set, keys);
        return new_set;
    }

    fn isChildOff(self: *Self, parent_obj: public.ObjId, child_obj: public.ObjId) bool {
        const real_parent_obj = self.getObjectPtr(parent_obj) orelse return false;
        const real_child_obj = self.getObjectPtr(child_obj) orelse return false;

        if (!real_child_obj.parent.isEmpty()) {
            if (real_child_obj.parent.eql(real_parent_obj.objid)) return true;

            var it = real_child_obj.parent;
            while (!it.isEmpty()) {
                const true_obj = self.getObjectPtr(it).?;
                if (it.eql(real_parent_obj.objid)) return true;
                it = true_obj.parent;
            }
        }

        return false;
    }
};

const DbPool = cetech1.mem.VirtualPool(DbId);

var _allocator: std.mem.Allocator = undefined;
var _db_pool: DbPool = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _db_pool = try DbPool.init(allocator, std.math.maxInt(u16));
    _allocator = allocator;
}

pub fn deinit() void {
    _db_pool.deinit();
}

inline fn getDbFromIdx(idx: public.DbId) *DbId {
    std.debug.assert(!idx.isEmpty());
    return _db_pool.get(idx.idx);
}

inline fn getDbFromObj(obj: *public.Obj) *DbId {
    const real_obj: *Object = @alignCast(@ptrCast(obj));
    return getDbFromIdx(real_obj.objid.db);
}

pub fn toDbFromDbT(db: public.DbId) *DbId {
    return getDbFromIdx(db);
}

pub fn registerToApi() !void {
    try apidb.api.setOrRemoveZigApi(module_name, public.CdbAPI, &api, true);
}

pub var api = public.CdbAPI{
    .createDbFn = createDb,
    .destroyDbFn = destroyDb,
    .writeObjFn = writeObjFn,
    .writeCommitFn = writeCommitFn,
    .retargetWriteFn = retargetWriteFn,
    .setSubObjFn = setSubObjFn,
    .clearSubObjFn = clearSubObjFn,
    .setGenericFn = setGenericFn,
    .setStrFn = setStrFn,
    .setRefFn = setRefFn,
    .clearRefFn = clearRefFn,
    .addRefToSetFn = addRefToSetFn,
    .addSubObjToSetFn = addSubObjToSetFn,
    .removeFromRefSetFn = removeFromRefSetFn,
    .resetPropertyOverideFn = resetPropertyOverideFn,
    .removeFromSubObjSetFn = removeFromSubObjSetFn,
    .createBlobFn = createBlobFn,
    .instantiateSubObjFn = instantiateSubObjFn,
    .instantiateSubObjFromSetFn = instantiateSubObjFromSetFn,
    .restoreDeletedInSetFn = restoreDeletedInSetFn,
    .setPrototypeFn = setPrototypeFn,
    .readObjFn = readObjFn,
    .readRefFn = readRefFn,

    .readGenericFn = readGenericFn,
    .readSubObjFn = readSubObjFn,
    .readRefSetFn = readRefSetFn,
    .readRefSetAddedFn = readRefSetAddedFn,
    .readRefSetRemovedFn = readRefSetRemovedFn,
    .readSubObjSetFn = readSubObjSetFn,
    .readSubObjSetAddedFn = readSubObjSetAddedFn,
    .readSubObjSetRemovedFn = readSubObjSetRemovedFn,
    .readBlobFn = readBlobFn,
    .readStrFn = readStrFn,
    .isPropertyOverridedFn = isPropertyOverridedFn,
    .getPrototypeFn = getPrototypeFn,
    .isInSetFn = isInSetFn,
    .isIinisiatedFn = isIinisiatedFn,
    .canIinisiateFn = canIinisiateFn,
    .getDbFromObjidFn = getDbFromObjidFn,
    .getDbFromObjFn = getDbFromObjFn,

    .getVersionFn = getVersionFn,
    .getReferencerSetFn = getReferencerSetFn,
    .getParentFn = getParentFn,
    .isAliveFn = isAliveFn,
    .getRelationFn = getRelationFn,
    .inisitateDeepFn = inisitateDeepFn,
    .isChildOffFn = isChildOffFn,

    .createObjectFromPrototypeFn = createObjectFromPrototypeFn,
    .cloneObjectFn = cloneObjectFn,
    .destroyObjectFn = destroyObjectFn,
    .setDefaultObjectFn = setDefaultObjectFn,

    .createObjectFn = createObjectFn,
    .addAspectFn = addAspectFn,
    .getAspectFn = getAspectFn,
    .addPropertyAspectFn = addPropertyAspectFn,
    .getPropertyAspectFn = getPropertyAspectFn,
    .getTypeIdxFn = getTypeIdxFn,

    .hasTypeSetFn = hasTypeSetFn,
    .hasTypeSubobjectFn = hasTypeSubobjectFn,

    .getTypeHashFn = getTypeHashFn,
    .getChangeObjectsFn = getChangeObjectsFn,

    .getDefaultObjectFn = getDefaultObjectFn,
    .getFirstObjectFn = getFirstObjectFn,
    .getAllObjectByTypeFn = getAllObjectByTypeFn,

    .addOnObjIdDestroyedFn = addOnObjIdDestroyedFn,
    .removeOnObjIdDestroyedFn = removeOnObjIdDestroyedFn,

    .addTypeFn = addTypeFn,
    .getTypePropDefFn = getTypePropDefFn,
    .getTypeNameFn = getTypeNameFn,
    .getTypePropDefIdxFn = getTypePropDefIdxFn,

    .stressItFn = stressItFn,
    .gcFn = gcFn,
    .dumpFn = dumpFn,
};

fn getDbFromObjidFn(obj: public.ObjId) public.DbId {
    const db = getDbFromIdx(obj.db);
    return db.idx;
}

fn getDbFromObjFn(obj: *public.Obj) public.DbId {
    const db = getDbFromObj(obj);
    return db.idx;
}

fn addTypeFn(dbidx: public.DbId, name: []const u8, prop_def: []const public.PropDef) !public.TypeIdx {
    var db = getDbFromIdx(dbidx);
    return db.addType(name, prop_def);
}

fn getTypeNameFn(dbidx: public.DbId, type_idx: public.TypeIdx) ?[]const u8 {
    var db = getDbFromIdx(dbidx);
    return db.getTypeName(type_idx);
}

fn getTypePropDefFn(dbidx: public.DbId, type_idx: public.TypeIdx) ?[]const public.PropDef {
    var db = getDbFromIdx(dbidx);
    return db.getTypePropDef(type_idx);
}
fn getTypePropDefIdxFn(dbidx: public.DbId, type_idx: public.TypeIdx, prop_name: []const u8) ?u32 {
    var db = getDbFromIdx(dbidx);
    return db.getTypePropDefIdx(type_idx, prop_name);
}
fn addAspectFn(dbidx: public.DbId, type_idx: public.TypeIdx, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
    var db = getDbFromIdx(dbidx);
    return db.addAspect(type_idx, apect_name, aspect_ptr);
}
fn getAspectFn(dbidx: public.DbId, type_idx: public.TypeIdx, aspect_hash: strid.StrId32) ?*anyopaque {
    var db = getDbFromIdx(dbidx);
    return db.getAspect(type_idx, aspect_hash);
}
fn addPropertyAspectFn(dbidx: public.DbId, type_idx: public.TypeIdx, prop_idx: u32, apect_name: []const u8, aspect_ptr: *anyopaque) !void {
    var db = getDbFromIdx(dbidx);
    return db.addPropertyAspect(type_idx, prop_idx, apect_name, aspect_ptr);
}
fn getPropertyAspectFn(dbidx: public.DbId, type_idx: public.TypeIdx, prop_idx: u32, aspect_hash: strid.StrId32) ?*anyopaque {
    var db = getDbFromIdx(dbidx);
    return db.getPropertyAspect(type_idx, prop_idx, aspect_hash);
}
fn addOnObjIdDestroyedFn(dbidx: public.DbId, fce: OnObjIdDestroyed) !void {
    var db = getDbFromIdx(dbidx);
    return db.addOnObjIdDestroyed(fce);
}
fn removeOnObjIdDestroyedFn(dbidx: public.DbId, fce: OnObjIdDestroyed) void {
    var db = getDbFromIdx(dbidx);
    return db.removeOnObjIdDestroyed(fce);
}
fn createObjectFn(dbidx: public.DbId, type_idx: public.TypeIdx) !public.ObjId {
    var db = getDbFromIdx(dbidx);
    return db.createObject(type_idx);
}
fn getDefaultObjectFn(dbidx: public.DbId, type_idx: public.TypeIdx) ?public.ObjId {
    var db = getDbFromIdx(dbidx);
    return db.getDefaultObject(type_idx);
}
fn getFirstObjectFn(dbidx: public.DbId, type_idx: public.TypeIdx) public.ObjId {
    var db = getDbFromIdx(dbidx);
    return db.getFirstObject(type_idx);
}
fn getAllObjectByTypeFn(dbidx: public.DbId, tmp_allocator: std.mem.Allocator, type_idx: public.TypeIdx) ?[]public.ObjId {
    var db = getDbFromIdx(dbidx);
    return db.getAllObjectByType(tmp_allocator, type_idx);
}
fn createObjectFromPrototypeFn(prototype: public.ObjId) !public.ObjId {
    var db = getDbFromIdx(prototype.db);
    return db.createObjectFromPrototype(prototype);
}
fn cloneObjectFn(obj: public.ObjId) !public.ObjId {
    var db = getDbFromIdx(obj.db);
    return db.cloneObject(obj);
}
fn setDefaultObjectFn(obj: public.ObjId) void {
    var db = getDbFromIdx(obj.db);
    return db.setDefaultObject(obj);
}
fn destroyObjectFn(obj: public.ObjId) void {
    var db = getDbFromIdx(obj.db);
    return db.destroyObject(obj);
}
fn readObjFn(obj: public.ObjId) ?*public.Obj {
    var db = getDbFromIdx(obj.db);
    return db.readObj(obj);
}
fn writeObjFn(obj: public.ObjId) ?*public.Obj {
    var db = getDbFromIdx(obj.db);
    return db.writerObj(obj);
}
fn writeCommitFn(writer: *public.Obj) !void {
    var db = getDbFromObj(writer);
    return db.writerCommit(writer);
}
fn retargetWriteFn(writer: *public.Obj, obj: public.ObjId) !void {
    var db = getDbFromObj(writer);
    return db.retargetWriter(writer, obj);
}
fn getPrototypeFn(obj: *public.Obj) public.ObjId {
    var db = getDbFromObj(obj);
    return db.getPrototype(obj);
}
fn getParentFn(obj: public.ObjId) public.ObjId {
    var db = getDbFromIdx(obj.db);
    return db.getParent(obj);
}
fn getVersionFn(obj: public.ObjId) public.ObjVersion {
    var db = getDbFromIdx(obj.db);
    return db.getVersion(obj);
}
fn getReferencerSetFn(allocator: std.mem.Allocator, obj: public.ObjId) ![]public.ObjId {
    var db = getDbFromIdx(obj.db);
    return db.getReferencerSet(allocator, obj);
}
fn setPrototypeFn(obj: public.ObjId, prototype: public.ObjId) !void {
    var db = getDbFromIdx(obj.db);
    return db.setPrototype(obj, prototype);
}
fn resetPropertyOverideFn(writer: *public.Obj, prop_idx: u32) void {
    var db = getDbFromObj(writer);
    return db.resetPropertyOveride(writer, prop_idx);
}
fn isPropertyOverridedFn(reader: *public.Obj, prop_idx: u32) bool {
    var db = getDbFromObj(reader);
    return db.isPropertyOverrided(reader, prop_idx);
}
fn isIinisiatedFn(reader: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) bool {
    var db = getDbFromObj(reader);
    return db.isIinisiated(reader, set_prop_idx, inisiated_obj);
}
fn canIinisiateFn(reader: *public.Obj, inisiated_obj: *public.Obj) bool {
    var db = getDbFromObj(reader);
    return db.canIinisiate(reader, inisiated_obj);
}
fn restoreDeletedInSetFn(writer: *public.Obj, set_prop_idx: u32, inisiated_obj: *public.Obj) void {
    var db = getDbFromObj(writer);
    return db.restoreDeletedInSet(writer, set_prop_idx, inisiated_obj);
}
fn readGenericFn(reader: *public.Obj, prop_idx: u32, prop_type: public.PropType) []const u8 {
    var db = getDbFromObj(reader);
    return db.readGeneric(reader, prop_idx, prop_type);
}
fn setGenericFn(obj: *public.Obj, prop_idx: u32, value: [*]const u8, prop_type: public.PropType) void {
    var db = getDbFromObj(obj);
    return db.setGeneric(obj, prop_idx, value, prop_type);
}
fn setStrFn(writer: *public.Obj, prop_idx: u32, value: [:0]const u8) !void {
    var db = getDbFromObj(writer);
    return db.setStr(writer, prop_idx, value);
}
fn readStrFn(reader: *public.Obj, prop_idx: u32) ?[:0]const u8 {
    var db = getDbFromObj(reader);
    return db.readStr(reader, prop_idx);
}
fn readSubObjFn(reader: *public.Obj, prop_idx: u32) ?public.ObjId {
    var db = getDbFromObj(reader);
    return db.readSubObj(reader, prop_idx);
}
fn setSubObjFn(writer: *public.Obj, prop_idx: u32, subobj_writer: *public.Obj) !void {
    var db = getDbFromObj(writer);
    return db.setSubObj(writer, prop_idx, subobj_writer);
}
fn clearSubObjFn(writer: *public.Obj, prop_idx: u32) !void {
    var db = getDbFromObj(writer);
    return db.clearSubObj(writer, prop_idx);
}
fn instantiateSubObjFn(writer: *public.Obj, prop_idx: u32) !public.ObjId {
    var db = getDbFromObj(writer);
    return db.instantiateSubObj(writer, prop_idx);
}
fn instantiateSubObjFromSetFn(writer: *public.Obj, prop_idx: u32, obj_set: public.ObjId) !public.ObjId {
    var db = getDbFromObj(writer);
    return db.instantiateSubObjFromSet(writer, prop_idx, obj_set);
}
fn isInSetFn(reader: *public.Obj, prop_idx: u32, item_ibj: public.ObjId) bool {
    var db = getDbFromObj(reader);
    return db.isInSet(reader, prop_idx, item_ibj);
}
fn readRefFn(reader: *public.Obj, prop_idx: u32) ?public.ObjId {
    var db = getDbFromObj(reader);
    return db.readRef(reader, prop_idx);
}
fn setRefFn(writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
    var db = getDbFromObj(writer);
    return db.setRef(writer, prop_idx, value);
}
fn clearRefFn(writer: *public.Obj, prop_idx: u32) !void {
    var db = getDbFromObj(writer);
    return db.clearRef(writer, prop_idx);
}
fn addRefToSetFn(writer: *public.Obj, prop_idx: u32, values: []const public.ObjId) !void {
    var db = getDbFromObj(writer);
    return db.addRefToSet(writer, prop_idx, values);
}
fn removeFromRefSetFn(writer: *public.Obj, prop_idx: u32, value: public.ObjId) !void {
    var db = getDbFromObj(writer);
    return db.removeFromRefSet(writer, prop_idx, value);
}
fn readRefSetFn(reader: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = getDbFromObj(reader);
    return db.readRefSet(reader, prop_idx, allocator);
}
fn readRefSetAddedFn(reader: *public.Obj, prop_idx: u32) []const public.ObjId {
    var db = getDbFromObj(reader);
    return db.readRefSetShallow(reader, prop_idx);
}
fn readRefSetRemovedFn(reader: *public.Obj, prop_idx: u32) []const public.ObjId {
    var db = getDbFromObj(reader);
    return db.readRefSetRemovedShallow(reader, prop_idx);
}
fn readSubObjSetAddedFn(reader: *public.Obj, prop_idx: u32) []const public.ObjId {
    var db = getDbFromObj(reader);
    return db.readSubObjSetShallow(reader, prop_idx);
}
fn readSubObjSetRemovedFn(reader: *public.Obj, prop_idx: u32) []const public.ObjId {
    var db = getDbFromObj(reader);
    return db.readSubObjSetRemovedShallow(reader, prop_idx);
}
fn addSubObjToSetFn(writer: *public.Obj, prop_idx: u32, subobjs_writer: []const *public.Obj) !void {
    var db = getDbFromObj(writer);
    return db.addToSubObjSet(writer, prop_idx, subobjs_writer);
}
fn removeFromSubObjSetFn(writer: *public.Obj, prop_idx: u32, subobj_writer: *public.Obj) !void {
    var db = getDbFromObj(writer);
    return db.removeFromSubObjSet(writer, prop_idx, subobj_writer);
}
fn readSubObjSetFn(reader: *public.Obj, prop_idx: u32, allocator: std.mem.Allocator) ?[]const public.ObjId {
    var db = getDbFromObj(reader);
    return db.readSubObjSet(reader, prop_idx, allocator);
}
fn createBlobFn(writer: *public.Obj, prop_idx: u32, size: usize) !?[]u8 {
    var db = getDbFromObj(writer);
    return db.createBlob(writer, prop_idx, size);
}
fn readBlobFn(reader: *public.Obj, prop_idx: u32) []u8 {
    var db = getDbFromObj(reader);
    return db.readBlob(reader, prop_idx);
}
fn stressItFn(dbidx: public.DbId, type_idx: public.TypeIdx, type_idx2: public.TypeIdx, ref_obj1: public.ObjId) !void {
    var db = getDbFromIdx(dbidx);
    return db.stressIt(type_idx, type_idx2, ref_obj1);
}
fn gcFn(dbidx: public.DbId, tmp_allocator: std.mem.Allocator) !void {
    var db = getDbFromIdx(dbidx);
    return db.gc(tmp_allocator);
}

fn dumpFn(dbidx: public.DbId) !void {
    var real_db = getDbFromIdx(dbidx);

    var path_buff: [1024]u8 = undefined;
    var file_path_buff: [1024]u8 = undefined;
    // only if asset root is set.
    var path = try assetdb.api.getTmpPath(&path_buff) orelse return;
    path = try std.fmt.bufPrint(&file_path_buff, "{s}/" ++ "cdb.md", .{path});

    var dot_file = try std.fs.createFileAbsolute(path, .{});
    defer dot_file.close();

    var bw = std.io.bufferedWriter(dot_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    try writer.print("# CDB Types reference\n\n", .{});

    for (real_db.typestorage_map.values()) |idx| {
        const storage = real_db.getTypeStorageByTypeIdx(idx).?;

        const type_name = storage.name;
        try writer.print("## {s} - {d}\n\n", .{ type_name, storage.type_hash.id });

        try writer.print("```d2\n", .{});
        try writer.print("{s}: {{\n", .{type_name});
        try writer.print("  shape: class\n", .{});

        for (storage.props_def) |prop| {
            const prop_type = std.enums.tagName(cetech1.cdb.PropType, prop.type).?;

            if (prop.type_hash.id != 0) {
                const typed_name = real_db.getTypeStorageByTypeHash(prop.type_hash).?.name;
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
fn hasTypeSetFn(dbidx: public.DbId, type_idx: public.TypeIdx) bool {
    var db = getDbFromIdx(dbidx);
    return db.hasTypeSet(type_idx);
}
fn hasTypeSubobjectFn(dbidx: public.DbId, type_idx: public.TypeIdx) bool {
    var db = getDbFromIdx(dbidx);
    return db.hasTypeSubobject(type_idx);
}
fn getTypeIdxFn(dbidx: public.DbId, type_hash: public.TypeHash) ?public.TypeIdx {
    var db = getDbFromIdx(dbidx);
    return db.getTypeIdx(type_hash);
}
fn getTypeHashFn(dbidx: public.DbId, type_idx: public.TypeIdx) ?public.TypeHash {
    var db = getDbFromIdx(dbidx);
    return db.getTypeHash(type_idx);
}
fn getChangeObjectsFn(dbidx: public.DbId, allocator: std.mem.Allocator, type_idx: public.TypeIdx, since_version: public.TypeVersion) !public.ChangedObjects {
    var db = getDbFromIdx(dbidx);
    return db.getChangeObjects(allocator, type_idx, since_version);
}
fn isAliveFn(obj: public.ObjId) bool {
    var db = getDbFromIdx(obj.db);
    return db.isAlive(obj);
}
fn getRelationFn(top_level_obj: public.ObjId, obj: public.ObjId, prop_idx: u32, in_set_obj: ?public.ObjId) public.ObjRelation {
    var db = getDbFromIdx(obj.db);
    return db.getRelation(top_level_obj, obj, prop_idx, in_set_obj);
}
fn inisitateDeepFn(allocator: std.mem.Allocator, last_parent: public.ObjId, to_inisiated_obj: public.ObjId) ?public.ObjId {
    var db = getDbFromIdx(last_parent.db);
    return db.inisitateDeep(allocator, last_parent, to_inisiated_obj);
}
fn isChildOffFn(parent_obj: public.ObjId, child_obj: public.ObjId) bool {
    var db = getDbFromIdx(parent_obj.db);
    return db.isChildOff(parent_obj, child_obj);
}
//

fn createDb(name: [:0]const u8) !public.DbId {
    var db = _db_pool.create(null);
    db.* = try DbId.init(_allocator, .{ .idx = @truncate(_db_pool.index(db)) }, name);

    try db.registerAllTypes();

    return db.idx;
}

fn destroyDb(db_: public.DbId) void {
    var db = toDbFromDbT(db_);
    db.deinit();
    _db_pool.destroy(db) catch undefined;
}

// Assert C and Zig Enums
comptime {}

test "cdb: Test alocate/free id" {
    try cdb_test.testInit();
    defer cdb_test.testDeinit();

    const db = try api.createDb("Test");
    defer api.destroyDb(db);

    const type_hash = try api.addType(
        db,
        "foo",
        &[_]cetech1.cdb.PropDef{},
    );
    _ = type_hash;

    var _cdb = toDbFromDbT(db);
    var storage = _cdb.getTypeStorageByTypeHash(strId32("foo")).?;

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

    const db = try api.createDb("Test");
    defer api.destroyDb(db);

    const type_hash = try api.addType(
        db,
        "foo",
        &[_]cetech1.cdb.PropDef{
            .{ .prop_idx = 0, .name = "foo", .type = .SUBOBJECT_SET },
        },
    );
    _ = type_hash;

    var _cdb = toDbFromDbT(db);
    var storage = _cdb.getTypeStorageByTypeHash(strId32("foo")).?;

    var array = try storage.allocateObjIdSet();

    // can add items
    try std.testing.expect(try array.add(public.ObjId{ .type_idx = .{ .idx = 0 }, .id = 0 }));
    try std.testing.expect(try array.add(public.ObjId{ .type_idx = .{ .idx = 0 }, .id = 1 }));
    try std.testing.expect(try array.add(public.ObjId{ .type_idx = .{ .idx = 0 }, .id = 2 }));

    //try std.testing.expect(array.list.items.len == 3);

    // can destroy list
    try storage.destroyObjIdSet(array);
}

// Assert C api == C api in zig.
comptime {}
