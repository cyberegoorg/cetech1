const std = @import("std");

const builtin = @import("builtin");

const cetech1 = @import("cetech1");
const apidb = @import("apidb.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");
const profiler_private = @import("profiler.zig");

const assetdb_private = @import("assetdb.zig");
const coreui_private = @import("coreui.zig");
const cdb_private = @import("cdb.zig");

const public = cetech1.ecs;
const cdb_types = cetech1.cdb_types;
const cdb = cetech1.cdb;

const coreui = cetech1.coreui;

const zflecs = @import("zflecs");
const entity_t = zflecs.entity_t;

const module_name = .ecs;
const log = std.log.scoped(module_name);

const SimulatedSystemsList = std.ArrayList(zflecs.entity_t);
const World = struct {
    w: *zflecs.world_t,
    simulate: bool = true,
    simulated_systems: SimulatedSystemsList,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{ .simulated_systems = SimulatedSystemsList.init(allocator) };
    }

    pub fn deinit(self: *World) void {
        _ = ecs_fini(self.w);
        self.simulated_systems.deinit();
    }

    pub fn toPublic(world: *World) public.World {
        return .{ .ptr = world, .vtable = &world_vt };
    }

    pub fn newEntity(self: *World, name: ?[:0]const u8) public.EntityId {
        return zflecs.new_entity(self.w, name orelse "");
    }

    pub fn newEntities(self: *World, allocator: std.mem.Allocator, id: public.Id, count: usize) ?[]public.EntityId {
        const entitites = zflecs.bulk_new_w_id(self.w, id, @intCast(count));

        const result = allocator.alloc(public.EntityId, count) catch return null;
        @memcpy(result, entitites);
        return result;
    }

    pub fn destroyEntities(self: *World, ents: []const public.EntityId) void {
        for (ents) |ent| {
            zflecs.delete(self.w, ent);
        }
    }

    pub fn setId(self: *World, entity: public.EntityId, id: cetech1.strid.StrId32, size: usize, ptr: ?*const anyopaque) public.EntityId {
        return zflecs.set_id(self.w, entity, _id_map.find(id).?, size, ptr);
    }

    pub fn getMutId(self: *World, entity: public.EntityId, id: cetech1.strid.StrId32) ?*anyopaque {
        return zflecs.get_mut_id(self.w, entity, _id_map.find(id).?);
    }

    pub fn progress(self: *World, dt: f32) bool {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "ECS: World progress");
        defer zone_ctx.End();
        return zflecs.progress(self.w, dt);
    }

    pub fn createQuery(self: *World, query: []const public.QueryTerm) !public.Query {
        var qd = zflecs.query_desc_t{};

        for (query, 0..) |term, idx| {
            qd.terms[idx] = .{
                .id = _id_map.find(term.id) orelse continue,
                .inout = @enumFromInt(@intFromEnum(term.inout)),
                .oper = @enumFromInt(@intFromEnum(term.oper)),
            };
        }

        const q = try zflecs.query_init(self.w, &qd);
        return .{
            .ptr = q,
            .vtable = &query_vt,
            .world = self.toPublic(),
        };
    }

    pub fn deferBegin(self: *World) bool {
        return zflecs.defer_begin(self.w);
    }

    pub fn deferEnd(self: *World) bool {
        return zflecs.defer_end(self.w);
    }

    pub fn deferSuspend(self: *World) void {
        return zflecs.defer_suspend(self.w);
    }

    pub fn deferResume(self: *World) void {
        return zflecs.defer_resume(self.w);
    }

    pub fn isRemoteDebugActive(self: *World) bool {
        return zflecs.has_id(self.w, FLECS_IDEcsRestID_, FLECS_IDEcsRestID_);
    }

    pub fn setRemoteDebugActive(self: *World, active: bool) ?u16 {
        if (active) {
            const port = 27750 + _port_counter;
            _port_counter += 1;

            _ = ecs_set_id(
                self.w,
                FLECS_IDEcsRestID_,
                FLECS_IDEcsRestID_,
                @sizeOf(zflecs.EcsRest),
                &std.mem.toBytes(zflecs.EcsRest{ .port = port }),
            );

            return port;
        } else {
            zflecs.remove_id(self.w, FLECS_IDEcsRestID_, FLECS_IDEcsRestID_);
        }
        return null;
    }

    fn uiRemoteDebugMenuItems(self: *World, allocator: std.mem.Allocator, port: ?u16) ?u16 {
        var remote_active = isRemoteDebugActive(self);
        var result: ?u16 = port;

        var buf: [256:0]u8 = undefined;
        const URL = "https://www.flecs.dev/explorer/?page=info&host=localhost:{d}";

        if (coreui_private.api.beginMenu(allocator, coreui.Icons.Entity ++ "  " ++ "ECS", true, null)) {
            defer coreui_private.api.endMenu();

            const debug_label = std.fmt.bufPrintZ(&buf, coreui.Icons.Debug ++ "  " ++ "Remote debug", .{}) catch return null;
            if (coreui_private.api.menuItemPtr(allocator, debug_label, .{ .selected = &remote_active }, null)) {
                if (setRemoteDebugActive(self, remote_active)) |p| {
                    const url = std.fmt.allocPrintZ(allocator, URL, .{p}) catch return null;
                    defer allocator.free(url);

                    coreui_private.api.setClipboardText(url);
                    result = p;
                } else {
                    result = null;
                }
            }

            const copy_label = std.fmt.bufPrintZ(&buf, coreui.Icons.CopyToClipboard ++ "  " ++ "Copy url", .{}) catch return null;
            if (coreui_private.api.menuItem(allocator, copy_label, .{ .enabled = port != null }, null)) {
                const url = std.fmt.allocPrintZ(allocator, URL, .{port.?}) catch return null;
                defer allocator.free(url);
                coreui_private.api.setClipboardText(url);
            }
        }

        return result;
    }

    pub fn setSimulate(self: *World, simulate: bool) void {
        for (self.simulated_systems.items) |value| {
            zflecs.enable(self.w, value, simulate);
        }
        self.simulate = simulate;
    }

    pub fn isSimulate(self: *World) bool {
        return self.simulate;
    }
};

const WorldPool = cetech1.mem.VirtualPool(World);
const WorldSet = std.AutoArrayHashMap(*World, void);

const Flecs2World = std.AutoArrayHashMap(*zflecs.world_t, *World);

const PrefabObjPair = struct { world: public.World, obj: cdb.ObjId };
const Obj2Prefab = std.AutoArrayHashMap(PrefabObjPair, public.EntityId);

const ComponentObjPair = struct { world: public.World, obj: cdb.ObjId };
const ComponentObj2Entity = std.AutoArrayHashMap(ComponentObjPair, cdb.ObjId);

const StrId2Id = std.AutoArrayHashMap(cetech1.strid.StrId32, public.Id);
const Id2StrId = std.AutoArrayHashMap(public.Id, cetech1.strid.StrId32);

var _cdb = &cdb_private.api;

var _world_pool: WorldPool = undefined;
var _flecs2world: Flecs2World = undefined;

// TODO: Remove maping
const IdMap = struct {
    strId2id: StrId2Id,
    id2StrId: Id2StrId,

    pub fn init(allocator: std.mem.Allocator) IdMap {
        return IdMap{
            .strId2id = StrId2Id.init(allocator),
            .id2StrId = Id2StrId.init(allocator),
        };
    }

    pub fn deinit(self: *IdMap) void {
        self.strId2id.deinit();
        self.id2StrId.deinit();
    }

    pub fn map(self: *IdMap, strid: cetech1.strid.StrId32, id: public.Id) !void {
        try self.strId2id.put(strid, id);
        try self.id2StrId.put(id, strid);
    }

    pub fn find(self: *IdMap, strid: cetech1.strid.StrId32) ?public.Id {
        return self.strId2id.get(strid);
    }

    pub fn findById(self: *IdMap, id: public.Id) ?cetech1.strid.StrId32 {
        return self.id2StrId.get(id);
    }
};

var _port_counter: u16 = 0;

extern fn ecs_run_worker(
    world: *zflecs.world_t,
    system: zflecs.entity_t,
    stage_index: i32,
    stage_count: i32,
    delta_time: zflecs.ftime_t,
    param: ?*const anyopaque,
) zflecs.entity_t;

var _allocator: std.mem.Allocator = undefined;
var _zflecs_os_impl: os.api_t = undefined;

var _world_data: WorldSet = undefined;
var _world_data_lck: std.Thread.Mutex = .{};

var _obj2prefab: Obj2Prefab = undefined;
var _obj2parent_obj: ComponentObj2Entity = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _ = @alignOf(public.TermId);

    _allocator = allocator;
    FlecsAllocator.allocator = allocator;

    _obj2prefab = Obj2Prefab.init(allocator);
    _obj2parent_obj = ComponentObj2Entity.init(allocator);
    _component_version = ComponentVersionMap.init(allocator);

    _world_data_lck = .{};

    _world_data = WorldSet.init(allocator);
    try _world_data.ensureTotalCapacity(128);

    _world_pool = try WorldPool.init(allocator, 128);
    _flecs2world = Flecs2World.init(allocator);

    zflecs.os_init();
    _zflecs_os_impl = std.mem.bytesToValue(os.api_t, std.mem.asBytes(&zflecs.os_get_api()));

    // Memory fce
    _zflecs_os_impl.malloc_ = &FlecsAllocator.alloc;
    _zflecs_os_impl.free_ = &FlecsAllocator.free;
    _zflecs_os_impl.realloc_ = &FlecsAllocator.realloc;
    _zflecs_os_impl.calloc_ = &FlecsAllocator.calloc;

    // Task fce
    _zflecs_os_impl.task_new_ = api_task_new;
    _zflecs_os_impl.task_join_ = api_task_join;

    // Log fce
    // TODO: from args on/off in debug?
    if (builtin.mode == .Debug) {
        //_zflecs_os_impl.log_level_ = 0;
    }
    _zflecs_os_impl.log_ = api_log;

    zflecs.os_set_api(@ptrCast(&_zflecs_os_impl));

    try initIds();
}

pub fn deinit() void {
    for (_world_data.keys()) |value| {
        destroyWorld(value.toPublic());
    }

    _obj2prefab.deinit();
    _obj2parent_obj.deinit();
    _component_version.deinit();

    deInitIds();
    _world_data.deinit();
    _world_pool.deinit();
    _flecs2world.deinit();
}

fn getWorldPtr(world: public.World) *World {
    return @alignCast(@ptrCast(world.ptr));
}

const ChangedObjsSet = std.AutoArrayHashMap(cdb.ObjId, void);
const ComponentVersionMap = std.AutoArrayHashMap(cdb.TypeIdx, cdb.TypeVersion);

var _component_version: ComponentVersionMap = undefined;
var _entity_version: cdb.TypeVersion = 0;

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(cetech1.kernel.OnLoad, "ECS", &[_]cetech1.strid.StrId64{}, struct {
    pub fn update(kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);

        var processed_obj = ChangedObjsSet.init(alloc);
        defer processed_obj.deinit();

        var deleted_ent_obj = ChangedObjsSet.init(alloc);
        defer deleted_ent_obj.deinit();

        const db = assetdb_private.getDb();

        // Components
        const impls = apidb.api.getImpl(_allocator, public.ComponentI) catch undefined;
        defer _allocator.free(impls);
        for (impls) |iface| {
            if (iface.cdb_type_hash.isEmpty()) continue;
            const type_idx = _cdb.getTypeIdx(db, iface.cdb_type_hash).?;

            const last_check = _component_version.get(type_idx) orelse 0;

            const changed = try _cdb.getChangeObjects(alloc, db, type_idx, last_check);
            defer alloc.free(changed.objects);
            if (!changed.need_fullscan) {
                for (changed.objects) |component_obj| {
                    const is_alive = _cdb.isAlive(component_obj);
                    const entity_obj = _cdb.getParent(component_obj);
                    const deleted_entity = !_cdb.isAlive(entity_obj);

                    //if (deleted_ent_obj.contains()) continue;

                    for (_world_data.keys()) |world| {
                        const w = toWorld(world);

                        const prefab_ent = _obj2prefab.get(.{ .world = w, .obj = entity_obj }) orelse continue;

                        if (is_alive) {
                            if (deleted_entity) continue;
                            if (processed_obj.contains(component_obj)) continue;

                            try _obj2parent_obj.put(.{ .world = w, .obj = component_obj }, entity_obj);

                            const component_data = try alloc.alloc(u8, iface.size);
                            defer alloc.free(component_data);
                            @memset(component_data, 0);

                            if (iface.fromCdb) |fromCdb| {
                                try fromCdb(alloc, component_obj, component_data);
                            }

                            // Propagate to prefab
                            _ = w.setIdRaw(prefab_ent, iface.id, iface.size, component_data.ptr);

                            // Propagate to prefab instances
                            var qd = zflecs.query_desc_t{};
                            qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(IsFromCdb, prefab_ent) };
                            const q = try zflecs.query_init(world.w, &qd);
                            defer zflecs.query_fini(q);
                            var it = zflecs.query_iter(world.w, q);
                            while (zflecs.iter_next(&it)) {
                                const ents = it.entities();
                                for (ents) |ent| {
                                    _ = w.setIdRaw(ent, iface.id, iface.size, component_data.ptr);
                                }
                            }
                        } else {
                            if (!deleted_entity) {

                                // Propagate to prefab instances
                                var qd = zflecs.query_desc_t{};
                                qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(IsFromCdb, prefab_ent) };
                                const q = try zflecs.query_init(world.w, &qd);
                                defer zflecs.query_fini(q);
                                var it = zflecs.query_iter(world.w, q);
                                while (zflecs.iter_next(&it)) {
                                    const ents = it.entities();
                                    for (ents) |ent| {
                                        zflecs.remove_id(world.w, ent, _id_map.find(iface.id).?);
                                    }
                                }

                                zflecs.remove_id(world.w, prefab_ent, _id_map.find(iface.id).?);
                            }

                            _ = _obj2parent_obj.swapRemove(.{ .world = w, .obj = component_obj });
                        }
                    }

                    try processed_obj.put(component_obj, {});
                }
            } else {
                if (_cdb.getAllObjectByType(alloc, db, type_idx)) |objs| {
                    for (objs) |graph| {
                        _ = graph; // autofix
                    }
                }
            }

            try _component_version.put(type_idx, changed.last_version);
        }

        // TODO: clean maps on delete components and entities
        {
            const changed = try _cdb.getChangeObjects(alloc, db, public.Entity.typeIdx(_cdb, db), _entity_version);
            defer alloc.free(changed.objects);
            if (!changed.need_fullscan) {
                for (changed.objects) |entity_obj| {
                    const is_alive = _cdb.isAlive(entity_obj);
                    if (!is_alive) {
                        try deleted_ent_obj.put(entity_obj, {});
                    }
                }

                for (changed.objects) |entity_obj| {
                    if (processed_obj.contains(entity_obj)) continue;

                    const is_alive = !deleted_ent_obj.contains(entity_obj);

                    for (_world_data.keys()) |world| {
                        const w = toWorld(world);

                        const parent_obj = _cdb.getParent(entity_obj);
                        const parent_prefab_ent = _obj2prefab.get(.{ .world = w, .obj = parent_obj }) orelse continue;

                        // _ = prefab_ent; // autofix

                        if (is_alive) {
                            const parent = _obj2parent_obj.get(.{ .world = w, .obj = entity_obj });
                            if (parent == null) {
                                const ent = try getOrCreatePrefab(alloc, w, db, entity_obj);
                                zflecs.add_id(world.w, ent, zflecs.make_pair(EcsChildOf, parent_prefab_ent));

                                try _obj2parent_obj.put(.{ .world = w, .obj = entity_obj }, parent_obj);

                                // Propagate to prefab instances
                                var qd = zflecs.query_desc_t{};
                                qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(IsFromCdb, parent_prefab_ent) };
                                const q = try zflecs.query_init(world.w, &qd);
                                defer zflecs.query_fini(q);
                                var it = zflecs.query_iter(world.w, q);
                                while (zflecs.iter_next(&it)) {
                                    const ents = it.entities();
                                    const eents = zflecs.bulk_new_w_id(world.w, zflecs.make_pair(IsFromCdb, ent), @intCast(ents.len));
                                    for (ents, 0..) |e, idx| {
                                        zflecs.add_id(@ptrCast(world.w), eents[idx], zflecs.make_pair(EcsChildOf, e));
                                    }
                                }
                            }
                        } else {
                            const prefab_ent = _obj2prefab.get(.{ .world = w, .obj = entity_obj }).?;
                            zflecs.delete_with(world.w, zflecs.make_pair(IsFromCdb, prefab_ent));
                            zflecs.delete(world.w, prefab_ent);
                            _ = _obj2prefab.swapRemove(.{ .world = w, .obj = entity_obj });
                        }
                    }

                    try processed_obj.put(entity_obj, {});
                }
            } else {
                if (_cdb.getAllObjectByType(alloc, db, public.Entity.typeIdx(_cdb, db))) |objs| {
                    for (objs) |graph| {
                        _ = graph; // autofix
                    }
                }
            }

            _entity_version = changed.last_version;
        }
    }
});

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(
    struct {
        pub fn createTypes(db: cdb.DbId) !void {
            // Entity
            {
                _ = try _cdb.addType(
                    db,
                    public.Entity.name,
                    &[_]cdb.PropDef{
                        .{ .prop_idx = public.Entity.propIdx(.name), .name = "name", .type = cdb.PropType.STR },
                        .{ .prop_idx = public.Entity.propIdx(.components), .name = "components", .type = cdb.PropType.SUBOBJECT_SET },
                        .{ .prop_idx = public.Entity.propIdx(.childrens), .name = "childrens", .type = cdb.PropType.SUBOBJECT_SET, .type_hash = public.Entity.type_hash },
                    },
                );
            }
        }
    },
);

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.EcsAPI, &api);

    // try apidb.api.implOrRemove(module_name, graphvm.GraphValueTypeI, &entity_value_type_i, true);
    // try apidb.api.implOrRemove(module_name, graphvm.GraphNodeI, &get_entity_node_i, true);

    try apidb.api.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, true);
    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, true);
}

pub var api = cetech1.ecs.EcsAPI{
    .createWorld = createWorld,
    .destroyWorld = destroyWorld,
    //.toWorld = toWorld,
    .toIter = toIter,
    .findComponentIByCdbHash = findComponentIByCdbHash,
    .spawnManyFromCDB = spawnManyFromCDB,
};

fn findComponentIByCdbHash(cdb_hash: cdb.TypeHash) ?*const public.ComponentI {
    // TODO: Cache it
    const impls = apidb.api.getImpl(_allocator, public.ComponentI) catch undefined;
    defer _allocator.free(impls);

    for (impls) |iface| {
        if (iface.cdb_type_hash.isEmpty()) continue;
        if (iface.cdb_type_hash.eql(cdb_hash)) return iface;
    }

    return null;
}

fn getOrCreatePrefab(allocator: std.mem.Allocator, world: public.World, db: cdb.DbId, obj: cdb.ObjId) !public.EntityId {
    const get_or_put = try _obj2prefab.getOrPut(.{ .world = world, .obj = obj });
    if (get_or_put.found_existing) return get_or_put.value_ptr.*;

    const w = getWorldPtr(world);

    const top_level_obj_r = public.Entity.read(_cdb, obj).?;
    const name = public.Entity.readStr(_cdb, top_level_obj_r, .name);

    const prefab_ent = world.newEntity(name);
    zflecs.add_id(w.w, prefab_ent, EcsPrefab);
    zflecs.add_id(w.w, prefab_ent, zflecs.make_pair(IsFromCdb, prefab_ent));
    get_or_put.value_ptr.* = prefab_ent;

    // try _obj2parent_obj.put(.{ .world = world, .obj = obj }, .{});

    // Create components
    if (try public.Entity.readSubObjSet(_cdb, top_level_obj_r, .components, allocator)) |components| {
        defer allocator.free(components);

        for (components) |component_obj| {
            const component_hash = _cdb.getTypeHash(db, component_obj.type_idx).?;

            try _obj2parent_obj.put(.{ .world = world, .obj = component_obj }, obj);

            const iface = findComponentIByCdbHash(component_hash).?;

            const component_data = try allocator.alloc(u8, iface.size);
            defer allocator.free(component_data);
            @memset(component_data, 0);

            if (iface.fromCdb) |fromCdb| {
                try fromCdb(allocator, component_obj, component_data);
            }

            _ = world.setIdRaw(prefab_ent, iface.id, iface.size, component_data.ptr);
        }
    }

    if (try public.Entity.readSubObjSet(_cdb, top_level_obj_r, .childrens, allocator)) |childrens| {
        defer allocator.free(childrens);
        for (childrens) |child| {
            try _obj2parent_obj.put(.{ .world = world, .obj = child }, obj);

            const ent = try getOrCreatePrefab(allocator, world, db, child);
            zflecs.add_id(w.w, ent, zflecs.make_pair(EcsChildOf, prefab_ent));
        }
    }

    return prefab_ent;
}

fn spawnManyFromCDB(allocator: std.mem.Allocator, world: public.World, obj: cdb.ObjId, count: usize) anyerror![]public.EntityId {
    const db = _cdb.getDbFromObjid(obj);
    const prefab = try getOrCreatePrefab(allocator, world, db, obj);
    const top_level_entities = world.newEntities(allocator, zflecs.make_pair(EcsIsA, prefab), count).?;
    return top_level_entities;
}

const world_vt = public.World.VTable{
    .newEntity = @ptrCast(&World.newEntity),
    .newEntities = @ptrCast(&World.newEntities),
    .destroyEntities = @ptrCast(&World.destroyEntities),
    .setId = @ptrCast(&World.setId),
    .getMutId = @ptrCast(&World.getMutId),
    .progress = @ptrCast(&World.progress),
    .createQuery = @ptrCast(&World.createQuery),
    .deferBegin = @ptrCast(&World.deferBegin),
    .deferEnd = @ptrCast(&World.deferEnd),
    .deferSuspend = @ptrCast(&World.deferSuspend),
    .deferResume = @ptrCast(&World.deferResume),
    .isRemoteDebugActive = @ptrCast(&World.isRemoteDebugActive),
    .setRemoteDebugActive = @ptrCast(&World.setRemoteDebugActive),
    .uiRemoteDebugMenuItems = @ptrCast(&World.uiRemoteDebugMenuItems),
    .setSimulate = @ptrCast(&World.setSimulate),
    .isSimulate = @ptrCast(&World.isSimulate),
};

const iter_vt = public.Iter.VTable.implement(struct {
    pub fn getWorld(self: *anyopaque) public.World {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        // TODO: world vs. real world
        return World.toPublic(_flecs2world.get(@ptrCast(it.real_world)).?);
    }

    pub fn count(self: *anyopaque) usize {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return it.count();
    }

    pub fn field(self: *anyopaque, size: usize, index: i8) ?*anyopaque {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.field_w_size(it, size, index);
    }

    pub fn isSelf(self: *anyopaque, index: i8) bool {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.field_is_self(it, index);
    }

    pub fn getParam(self: *anyopaque) ?*anyopaque {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return it.param;
    }

    pub fn entites(self: *anyopaque) []const public.EntityId {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return it.entities();
    }

    pub fn next(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.iter_next(it);
    }

    pub fn changed(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.query_changed(@constCast(it.query));
        //return ecs_iter_changed(it);
    }

    pub fn skip(self: *anyopaque) void {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.iter_skip(it);
    }
});

const query_vt = public.Query.VTable.implement(struct {
    pub fn destroy(self: *anyopaque) void {
        zflecs.query_fini(@alignCast(@ptrCast(self)));
    }

    pub fn iter(self: *anyopaque, world: public.World) !public.Iter {
        const q: *zflecs.query_t = @alignCast(@ptrCast(self));
        const w = getWorldPtr(world);
        const it = zflecs.query_iter(w.w, q);

        return .{ .data = std.mem.toBytes(it), .vtable = &iter_vt };
    }

    pub fn next(self: *anyopaque, iter_: *public.Iter) bool {
        _ = self;
        const it: *zflecs.iter_t = @alignCast(@ptrCast(&iter_.data));
        return zflecs.query_next(it);
    }
});

pub fn progressAll(dt: f32) !void {
    // TODO: Problem with parallel
    for (_world_data.keys()) |world| {
        _ = World.progress(world, dt);
    }
}

extern fn ecs_mini() *zflecs.world_t;
extern fn FlecsPipelineImport(w: *zflecs.world_t) void;
extern fn FlecsRestImport(w: *zflecs.world_t) void;
extern fn FlecsStatsImport(w: *zflecs.world_t) void;

extern const FLECS_IDEcsRestID_: zflecs.entity_t;
extern fn ecs_set_id(world: *zflecs.world_t, entity: zflecs.entity_t, id: zflecs.id_t, size: usize, ptr: ?*const anyopaque) zflecs.entity_t;
extern fn ecs_iter_changed(it: *zflecs.iter_t) bool;

var _fake_world: *zflecs.world_t = undefined;
var _id_map: IdMap = undefined;

pub fn deInitIds() void {
    _ = ecs_fini(_fake_world);
    _id_map.deinit();
}

var IsFromCdb: zflecs.entity_t = undefined;

pub fn initIds() !void {
    _fake_world = ecs_mini();

    imports(_fake_world);

    _id_map = IdMap.init(_allocator);

    try _id_map.map(public.Wildcard, EcsWildcard);
    try _id_map.map(public.Any, EcsAny);
    try _id_map.map(public.Transitive, EcsTransitive);
    try _id_map.map(public.Reflexive, EcsReflexive);
    try _id_map.map(public.Final, EcsFinal);
    try _id_map.map(public.DontInherit, EcsDontInherit);
    try _id_map.map(public.Exclusive, EcsExclusive);
    try _id_map.map(public.Acyclic, EcsAcyclic);
    try _id_map.map(public.Traversable, EcsTraversable);
    try _id_map.map(public.Symmetric, EcsSymmetric);
    try _id_map.map(public.With, EcsWith);
    try _id_map.map(public.OneOf, EcsOneOf);
    try _id_map.map(public.IsA, EcsIsA);
    try _id_map.map(public.ChildOf, EcsChildOf);
    try _id_map.map(public.DependsOn, EcsDependsOn);
    try _id_map.map(public.SlotOf, EcsSlotOf);
    try _id_map.map(public.OnDelete, EcsOnDelete);
    try _id_map.map(public.OnDeleteTarget, EcsOnDeleteTarget);
    try _id_map.map(public.Remove, EcsRemove);
    try _id_map.map(public.Delete, EcsDelete);
    try _id_map.map(public.Panic, EcsPanic);

    try _id_map.map(public.PredEq, EcsPredEq);
    try _id_map.map(public.PredMatch, EcsPredMatch);
    try _id_map.map(public.PredLookup, EcsPredLookup);

    try _id_map.map(public.Union, EcsUnion);
    try _id_map.map(public.Alias, EcsAlias);
    try _id_map.map(public.Prefab, EcsPrefab);
    try _id_map.map(public.Disabled, EcsDisabled);
    try _id_map.map(public.OnStart, EcsOnStart);
    try _id_map.map(public.PreFrame, EcsPreFrame);
    try _id_map.map(public.OnLoad, EcsOnLoad);
    try _id_map.map(public.PostLoad, EcsPostLoad);
    try _id_map.map(public.PreUpdate, EcsPreUpdate);
    try _id_map.map(public.OnUpdate, EcsOnUpdate);
    try _id_map.map(public.OnValidate, EcsOnValidate);
    try _id_map.map(public.PostUpdate, EcsPostUpdate);
    try _id_map.map(public.PreStore, EcsPreStore);
    try _id_map.map(public.OnStore, EcsOnStore);
    try _id_map.map(public.PostFrame, EcsPostFrame);
    try _id_map.map(public.Phase, EcsPhase);
    try _id_map.map(public.OnAdd, EcsOnAdd);
    try _id_map.map(public.OnRemove, EcsOnRemove);
    try _id_map.map(public.OnSet, EcsOnSet);

    try _id_map.map(public.Monitor, EcsMonitor);
    try _id_map.map(public.OnTableCreate, EcsOnTableCreate);
    try _id_map.map(public.OnTableDelete, EcsOnTableDelete);
    try _id_map.map(public.OnTableEmpty, EcsOnTableEmpty);
    try _id_map.map(public.OnTableFill, EcsOnTableFill);

    // Register components
    const impls = apidb.api.getImpl(_allocator, public.ComponentI) catch undefined;
    defer _allocator.free(impls);
    for (impls) |iface| {
        if (iface.size != 0) {
            const component_id = zflecs.component_init(_fake_world, &.{
                .entity = zflecs.entity_init(_fake_world, &.{
                    .use_low_id = true,
                    .name = iface.name,
                    .symbol = iface.name,
                }),
                .type = .{
                    .name = iface.name,
                    .alignment = @intCast(iface.aligment),
                    .size = @intCast(iface.size),
                    .hooks = .{
                        .on_add = if (iface.onAdd) |onAdd| @ptrCast(onAdd) else null,
                        .on_set = if (iface.onSet) |onSet| @ptrCast(onSet) else null,
                        .on_remove = if (iface.onRemove) |onRemove| @ptrCast(onRemove) else null,
                        .ctor = if (iface.onCreate) |onCreate| @ptrCast(onCreate) else null,
                        .dtor = if (iface.onDestroy) |onDestroy| @ptrCast(onDestroy) else null,
                        .copy = if (iface.onCopy) |onCopy| @ptrCast(onCopy) else null,
                        .move = if (iface.onMove) |onMove| @ptrCast(onMove) else null,
                    },
                },
            });

            //zflecs.add_id(_fake_world, component_id, zflecs.make_pair(EcsOnInstantiate, EcsInherit));

            try _id_map.map(iface.id, component_id);
        } else {
            const component_id = zflecs.entity_init(_fake_world, &.{
                .name = iface.name,
            });
            try _id_map.map(iface.id, component_id);
        }
    }

    IsFromCdb = zflecs.new_entity(_fake_world, "IsFromCdb");
}

const EcsQueryMatchPrefab = (1 << 1);
const EcsQueryMatchDisabled = (1 << 2);
const EcsQueryMatchEmptyTables = (1 << 3);
const EcsQueryNoData = (1 << 4);
const EcsQueryIsInstanced = (1 << 5);
const EcsQueryAllowUnresolvedByName = (1 << 6);
const EcsQueryTableOnly = (1 << 7);

fn imports(w: *zflecs.world_t) void {
    FlecsPipelineImport(w);
    FlecsStatsImport(w);
    FlecsRestImport(w);
}

pub fn createWorld() !public.World {
    const world = ecs_mini();

    imports(world);

    if (false) {
        _ = ecs_set_id(world, FLECS_IDEcsRestID_, FLECS_IDEcsRestID_, @sizeOf(zflecs.EcsRest), &std.mem.toBytes(zflecs.EcsRest{}));
    }

    //zflecs.set_task_threads(world, @intCast(task.api.getThreadNum()));

    _world_data_lck.lock();
    defer _world_data_lck.unlock();

    var w = _world_pool.create(null);
    w.* = .{
        .w = world,
        .simulated_systems = SimulatedSystemsList.init(_allocator),
    };
    try _flecs2world.put(world, w);

    const wd = World.toPublic(w);
    try _world_data.put(w, {});

    // Register components
    const impls = apidb.api.getImpl(_allocator, public.ComponentI) catch undefined;
    defer _allocator.free(impls);
    for (impls) |iface| {
        if (iface.size != 0) {
            const component_id = zflecs.component_init(world, &.{
                .entity = zflecs.entity_init(world, &.{
                    .use_low_id = true,
                    .id = _id_map.find(iface.id).?,
                    .name = iface.name,
                    .symbol = iface.name,
                }),
                .type = .{
                    .name = iface.name,
                    .alignment = @intCast(iface.aligment),
                    .size = @intCast(iface.size),
                    .hooks = .{
                        .on_add = if (iface.onAdd) |onAdd| @ptrCast(onAdd) else null,
                        .on_set = if (iface.onSet) |onSet| @ptrCast(onSet) else null,
                        .on_remove = if (iface.onRemove) |onRemove| @ptrCast(onRemove) else null,
                        .ctor = if (iface.onCreate) |onCreate| @ptrCast(onCreate) else null,
                        .dtor = if (iface.onDestroy) |onDestroy| @ptrCast(onDestroy) else null,
                        .copy = if (iface.onCopy) |onCopy| @ptrCast(onCopy) else null,
                        .move = if (iface.onMove) |onMove| @ptrCast(onMove) else null,
                    },
                },
            });
            _ = component_id; // autofix

            //zflecs.add_id(world, component_id, zflecs.make_pair(EcsOnInstantiate, EcsInherit));
        } else {
            const component_id = zflecs.entity_init(world, &.{
                .use_low_id = true,
                .id = _id_map.find(iface.id).?,
                .name = iface.name,
            });
            _ = component_id; // autofix
        }
    }

    // Register systems
    const simpls = apidb.api.getImpl(_allocator, public.SystemI) catch undefined;
    defer _allocator.free(simpls);
    for (simpls) |iface| {
        var system_desc = zflecs.system_desc_t{
            .multi_threaded = iface.multi_threaded,
            .callback = @ptrCast(iface.update),
            .run = @ptrCast(iface.iterate),
            .immediate = iface.immediate,
        };

        // TODO:
        system_desc.query.flags = if (iface.instanced) EcsQueryIsInstanced else 0;
        system_desc.query.cache_kind = @enumFromInt(@intFromEnum(iface.cache_kind));

        for (iface.query, 0..) |term, idx| {
            system_desc.query.terms[idx] = .{
                .id = _id_map.find(term.id) orelse continue,
                .inout = @enumFromInt(@intFromEnum(term.inout)),
                .oper = @enumFromInt(@intFromEnum(term.oper)),
                .src = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.src)),
                .first = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.first)),
                .second = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.second)),
            };
        }

        zflecs.SYSTEM(world, iface.name, _id_map.find(iface.phase).?, &system_desc);

        if (iface.simulation) {
            try w.simulated_systems.append(system_desc.entity);
        }
    }

    _ = zflecs.new_entity(world, "IsFromCdb");

    // Notify
    const onworld_impls = apidb.api.getImpl(_allocator, public.OnWorldI) catch undefined;
    defer _allocator.free(onworld_impls);
    for (onworld_impls) |iface| {
        try iface.onCreate(wd);
    }

    return wd;
}

pub fn destroyWorld(world: public.World) void {
    const onworld_impls = apidb.api.getImpl(_allocator, public.OnWorldI) catch undefined;
    defer _allocator.free(onworld_impls);
    for (onworld_impls) |iface| {
        iface.onDestroy(world) catch undefined;
    }

    const w: *World = @alignCast(@ptrCast(world.ptr));
    w.deinit();

    _world_data_lck.lock();
    defer _world_data_lck.unlock();
    _ = _world_data.swapRemove(@alignCast(@ptrCast(world.ptr)));

    _ = _flecs2world.swapRemove(w.w);
}

fn toIter(iter: *public.IterO) public.Iter {
    const it: *zflecs.iter_t = @alignCast(@ptrCast(iter));

    return public.Iter{
        .data = std.mem.toBytes(it.*),
        .vtable = &iter_vt,
    };
}

fn toWorld(world: *World) public.World {
    return public.World{
        .ptr = world,
        .vtable = &world_vt,
    };
}

pub fn typeName(comptime T: type) @TypeOf(@typeName(T)) {
    return switch (T) {
        u8 => return "U8",
        u16 => return "U16",
        u32 => return "U32",
        u64 => return "U64",
        i8 => return "I8",
        i16 => return "I16",
        i32 => return "I32",
        i64 => return "I64",
        f32 => return "F32",
        f64 => return "F64",
        else => return @typeName(T),
    };
}

fn api_task_new(clb: zflecs.os.thread_callback_t, data: ?*anyopaque) callconv(.C) zflecs.os.thread_t {
    const Task = struct {
        clb: zflecs.os.thread_callback_t,
        data: ?*anyopaque,
        pub fn exec(s: *@This()) !void {
            var zone = profiler_private.ztracy.ZoneN(@src(), "ECS Task");
            defer zone.End();
            _ = s.clb(s.data);
        }
    };
    const task_id = task.api.schedule(
        cetech1.task.TaskID.none,
        Task{
            .clb = clb,
            .data = data,
        },
    ) catch undefined;
    return @intFromEnum(task_id);
}

fn api_task_join(thread: zflecs.os.thread_t) callconv(.C) ?*anyopaque {
    task.api.wait(@enumFromInt(thread));
    return null;
}

fn api_log(level: i32, file: [*:0]const u8, line: i32, msg: [*:0]const u8) callconv(.C) void {
    _ = file; // autofix
    _ = line; // autofix

    // Debug/Trace
    if (level >= 0) {
        log.debug("{s}", .{msg});

        // Warning
    } else if (level == -2) {
        log.warn("{s}", .{msg});

        // Error
    } else if (level == -3) {
        log.err("{s}", .{msg});

        // Fatal
    } else if (level == -4) {
        log.err("{s}", .{msg});
        return undefined;
    }
}

extern fn ecs_init() *zflecs.world_t;
extern fn ecs_fini(world: *zflecs.world_t) i32;

extern const EcsWildcard: entity_t;
extern const EcsAny: entity_t;
extern const EcsTransitive: entity_t;
extern const EcsReflexive: entity_t;
extern const EcsFinal: entity_t;

extern const EcsOnInstantiate: entity_t;
extern const EcsInherit: entity_t;
extern const EcsOverride: entity_t;
extern const EcsDontInherit: entity_t;

extern const EcsAlwaysOverride: entity_t;
extern const EcsSymmetric: entity_t;
extern const EcsExclusive: entity_t;
extern const EcsAcyclic: entity_t;
extern const EcsTraversable: entity_t;
extern const EcsWith: entity_t;
extern const EcsOneOf: entity_t;
extern const EcsTag: entity_t;
extern const EcsUnion: entity_t;
extern const EcsAlias: entity_t;
extern const EcsChildOf: entity_t;
extern const EcsSlotOf: entity_t;
extern const EcsPrefab: entity_t;
extern const EcsDisabled: entity_t;

extern const EcsOnStart: entity_t;
extern const EcsPreFrame: entity_t;
extern const EcsOnLoad: entity_t;
extern const EcsPostLoad: entity_t;
extern const EcsPreUpdate: entity_t;
extern const EcsOnUpdate: entity_t;
extern const EcsOnValidate: entity_t;
extern const EcsPostUpdate: entity_t;
extern const EcsPreStore: entity_t;
extern const EcsOnStore: entity_t;
extern const EcsPostFrame: entity_t;
extern const EcsPhase: entity_t;

extern const EcsOnAdd: entity_t;
extern const EcsOnRemove: entity_t;
extern const EcsOnSet: entity_t;
extern const EcsUnSet: entity_t;
extern const EcsMonitor: entity_t;
extern const EcsOnTableCreate: entity_t;
extern const EcsOnTableDelete: entity_t;
extern const EcsOnTableEmpty: entity_t;
extern const EcsOnTableFill: entity_t;

extern const EcsOnDelete: entity_t;
extern const EcsOnDeleteTarget: entity_t;
extern const EcsRemove: entity_t;
extern const EcsDelete: entity_t;
extern const EcsPanic: entity_t;

extern const EcsFlatten: entity_t;
extern const EcsDefaultChildComponent: entity_t;

extern const EcsPredEq: entity_t;
extern const EcsPredMatch: entity_t;
extern const EcsPredLookup: entity_t;

extern const EcsIsA: entity_t;
extern const EcsDependsOn: entity_t;
extern const EcsFlecs: entity_t;

pub const os = struct {
    pub const thread_t = usize;
    pub const cond_t = usize;
    pub const mutex_t = usize;
    pub const dl_t = usize;
    pub const sock_t = usize;
    pub const thread_id_t = u64;
    pub const proc_t = *const fn () callconv(.C) void;
    pub const api_init_t = *const fn () callconv(.C) void;
    pub const api_fini_t = *const fn () callconv(.C) void;
    pub const api_malloc_t = *const fn (zflecs.size_t) callconv(.C) ?*anyopaque;
    pub const api_free_t = *const fn (?*anyopaque) callconv(.C) void;
    pub const api_realloc_t = *const fn (?*anyopaque, zflecs.size_t) callconv(.C) ?*anyopaque;
    pub const api_calloc_t = *const fn (zflecs.size_t) callconv(.C) ?*anyopaque;
    pub const api_strdup_t = *const fn ([*:0]const u8) callconv(.C) [*c]u8;
    pub const thread_callback_t = *const fn (?*anyopaque) callconv(.C) ?*anyopaque;
    pub const api_thread_new_t = *const fn (thread_callback_t, ?*anyopaque) callconv(.C) thread_t;
    pub const api_thread_join_t = *const fn (thread_t) callconv(.C) ?*anyopaque;
    pub const api_thread_self_t = *const fn () callconv(.C) thread_id_t;
    pub const api_task_new_t = *const fn (thread_callback_t, ?*anyopaque) callconv(.C) thread_t;
    pub const api_task_join_t = *const fn (thread_t) callconv(.C) ?*anyopaque;
    pub const api_ainc_t = *const fn (*i32) callconv(.C) i32;
    pub const api_lainc_t = *const fn (*i64) callconv(.C) i64;
    pub const api_mutex_new_t = *const fn () callconv(.C) mutex_t;
    pub const api_mutex_lock_t = *const fn (mutex_t) callconv(.C) void;
    pub const api_mutex_unlock_t = *const fn (mutex_t) callconv(.C) void;
    pub const api_mutex_free_t = *const fn (mutex_t) callconv(.C) void;
    pub const api_cond_new_t = *const fn () callconv(.C) cond_t;
    pub const api_cond_free_t = *const fn (cond_t) callconv(.C) void;
    pub const api_cond_signal_t = *const fn (cond_t) callconv(.C) void;
    pub const api_cond_broadcast_t = *const fn (cond_t) callconv(.C) void;
    pub const api_cond_wait_t = *const fn (cond_t, mutex_t) callconv(.C) void;
    pub const api_sleep_t = *const fn (i32, i32) callconv(.C) void;
    pub const api_enable_high_timer_resolution_t = *const fn (bool) callconv(.C) void;
    pub const api_get_time_t = *const fn (*zflecs.time_t) callconv(.C) void;
    pub const api_now_t = *const fn () callconv(.C) u64;
    pub const api_log_t = *const fn (i32, [*:0]const u8, i32, [*:0]const u8) callconv(.C) void;
    pub const api_abort_t = *const fn () callconv(.C) void;
    pub const api_dlopen_t = *const fn ([*:0]const u8) callconv(.C) dl_t;
    pub const api_dlproc_t = *const fn (dl_t, [*:0]const u8) callconv(.C) proc_t;
    pub const api_dlclose_t = *const fn (dl_t) callconv(.C) void;
    pub const api_module_to_path_t = *const fn ([*:0]const u8) callconv(.C) [*:0]u8;

    pub const api_t = extern struct {
        init_: api_init_t,
        fini_: api_fini_t,
        malloc_: api_malloc_t,
        realloc_: api_realloc_t,
        calloc_: api_calloc_t,
        free_: api_free_t,
        strdup_: api_strdup_t,
        thread_new_: api_thread_new_t,
        thread_join_: api_thread_join_t,
        thread_self_: api_thread_self_t,
        task_new_: api_task_new_t,
        task_join_: api_task_join_t,
        ainc_: api_ainc_t,
        adec_: api_ainc_t,
        lainc_: api_lainc_t,
        ladec_: api_lainc_t,
        mutex_new_: api_mutex_new_t,
        mutex_free_: api_mutex_free_t,
        mutex_lock_: api_mutex_lock_t,
        mutex_unlock_: api_mutex_lock_t,
        cond_new_: api_cond_new_t,
        cond_free_: api_cond_free_t,
        cond_signal_: api_cond_signal_t,
        cond_broadcast_: api_cond_broadcast_t,
        cond_wait_: api_cond_wait_t,
        sleep_: api_sleep_t,
        now_: api_now_t,
        get_time_: api_get_time_t,
        log_: api_log_t,
        abort_: api_abort_t,
        dlopen_: api_dlopen_t,
        dlproc_: api_dlproc_t,
        dlclose_: api_dlclose_t,
        module_to_dl_: api_module_to_path_t,
        module_to_etc_: api_module_to_path_t,
        log_level_: i32,
        log_indent_: i32,
        log_last_error_: i32,
        log_last_timestamp_: i64,
        flags_: zflecs.flags32_t,
    };
};

const FlecsAllocator = struct {
    const AllocationHeader = struct {
        size: usize,
    };

    const Alignment = 16;
    var allocator: ?std.mem.Allocator = null;

    fn alloc(size: i32) callconv(.C) ?*anyopaque {
        if (size < 0) {
            return null;
        }

        const allocation_size = Alignment + @as(usize, @intCast(size));

        const data = allocator.?.alignedAlloc(u8, Alignment, allocation_size) catch {
            return null;
        };

        var allocation_header = @as(
            *align(Alignment) AllocationHeader,
            @ptrCast(@alignCast(data.ptr)),
        );

        allocation_header.size = allocation_size;

        return data.ptr + Alignment;
    }

    fn free(ptr: ?*anyopaque) callconv(.C) void {
        if (ptr == null) {
            return;
        }
        var ptr_unwrapped = @as([*]u8, @ptrCast(ptr.?)) - Alignment;
        const allocation_header = @as(
            *align(Alignment) AllocationHeader,
            @ptrCast(@alignCast(ptr_unwrapped)),
        );

        allocator.?.free(
            @as([]align(Alignment) u8, @alignCast(ptr_unwrapped[0..allocation_header.size])),
        );
    }

    fn realloc(old: ?*anyopaque, size: i32) callconv(.C) ?*anyopaque {
        if (old == null) {
            return alloc(size);
        }

        const ptr_unwrapped = @as([*]u8, @ptrCast(old.?)) - Alignment;

        const allocation_header = @as(
            *align(Alignment) AllocationHeader,
            @ptrCast(@alignCast(ptr_unwrapped)),
        );

        const old_allocation_size = allocation_header.size;
        const old_slice = @as([*]u8, @ptrCast(ptr_unwrapped))[0..old_allocation_size];
        const old_slice_aligned = @as([]align(Alignment) u8, @alignCast(old_slice));

        const new_allocation_size = Alignment + @as(usize, @intCast(size));
        const new_data = allocator.?.realloc(old_slice_aligned, new_allocation_size) catch {
            return null;
        };

        var new_allocation_header = @as(*align(Alignment) AllocationHeader, @ptrCast(@alignCast(new_data.ptr)));
        new_allocation_header.size = new_allocation_size;

        return new_data.ptr + Alignment;
    }

    fn calloc(size: i32) callconv(.C) ?*anyopaque {
        const data_maybe = alloc(size);
        if (data_maybe) |data| {
            @memset(@as([*]u8, @ptrCast(data))[0..@as(usize, @intCast(size))], 0);
        }

        return data_maybe;
    }
};

// const entity_value_type_i = graphvm.GraphValueTypeI.implement(
//     public.EntityId,
//     .{
//         .name = "entity",
//         .type_hash = public.PinTypes.Entity,
//         .cdb_type_hash = cdb_types.u64Type.type_hash,
//     },
//     struct {
//         pub fn valueFromCdb(obj: cdb.ObjId, value: []u8) !void {
//             const v = cdb_types.u64Type.readValue(u64, _cdb, _cdb.readObj(obj).?, .value);
//             @memcpy(value, std.mem.asBytes(&v));
//         }

//         pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
//             const v = std.mem.bytesAsValue(u64, value);
//             return @intCast(v.*);
//         }

//         pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
//             return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(u64, value)});
//         }
//     },
// );

// const get_entity_node_i = graphvm.GraphNodeI.implement(
//     .{
//         .name = "Get entity",
//         .type_name = "get_entity",
//         .category = "ECS",
//     },
//     null,
//     struct {
//         pub fn getInputPins(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
//             _ = node_obj; // autofix
//             _ = graph_obj; // autofix
//             return allocator.dupe(graphvm.NodePin, &.{});
//         }

//         pub fn getOutputPins(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
//             _ = node_obj; // autofix
//             _ = graph_obj; // autofix
//             return allocator.dupe(graphvm.NodePin, &.{
//                 graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", true), public.PinTypes.Entity),
//             });
//         }

//         pub fn execute(args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
//             _ = in_pins; // autofix

//             if (graphvm_private.api.getContext(anyopaque, args.instance, public.ECS_ENTITY_CONTEXT)) |ent| {
//                 const ent_id = @intFromPtr(ent);
//                 try out_pins.writeTyped(public.EntityId, 0, ent_id, ent_id);
//             }
//         }

//         // pub fn icon(
//         //     buff: [:0]u8,
//         //     allocator: std.mem.Allocator,
//         //     db: cdb.DbId,
//         //     node_obj: cdb.ObjId,
//         // ) ![:0]u8 {
//         //     _ = allocator; // autofix
//         //     _ = db; // autofix
//         //     _ = node_obj; // autofix

//         //     return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_STOP});
//         // }
//     },
// );
