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

const SimulatedSystemsList = cetech1.ArrayList(zflecs.entity_t);

const WorldPool = cetech1.heap.VirtualPool(World);
const WorldSet = cetech1.ArraySet(*World);

const Obj2Prefab = cetech1.AutoArrayHashMap(cdb.ObjId, public.EntityId);
const ComponentObj2Entity = cetech1.AutoArrayHashMap(cdb.ObjId, cdb.ObjId);

const StrId2Id = cetech1.AutoArrayHashMap(public.IdStrId, public.Id);
const Id2StrId = cetech1.AutoArrayHashMap(public.Id, public.IdStrId);

const ChangedObjsSet = cetech1.ArraySet(cdb.ObjId);
const ComponentVersionMap = cetech1.AutoArrayHashMap(cdb.TypeIdx, cdb.TypeVersion);

const ObserverMaps = cetech1.AutoArrayHashMap(cetech1.StrId32, public.EntityId);

const World = struct {
    allocator: std.mem.Allocator,

    w: *zflecs.world_t,

    simulate: bool = true,
    simulate_do_step: bool = false,

    id_map: IdMap = .{},
    simulated_systems: SimulatedSystemsList = .{},
    observer_map: ObserverMaps = .{},

    IsFromCdb: zflecs.entity_t = undefined,

    obj2prefab: Obj2Prefab = .{},
    obj2parent_obj: ComponentObj2Entity = .{},

    pub fn init(allocator: std.mem.Allocator, w: *zflecs.world_t) !World {
        var zz = profiler_private.ztracy.ZoneN(@src(), "ECS: init self world");
        defer zz.End();

        var self = World{
            .w = w,
            .IsFromCdb = zflecs.new_entity(w, "IsFromCdb"),
            .allocator = allocator,
        };

        zflecs.add_id(w, self.IsFromCdb, EcsDontFragment);

        try self.id_map.map(self.allocator, public.Wildcard, EcsWildcard);
        try self.id_map.map(self.allocator, public.Any, EcsAny);
        try self.id_map.map(self.allocator, public.Transitive, EcsTransitive);
        try self.id_map.map(self.allocator, public.Reflexive, EcsReflexive);
        try self.id_map.map(self.allocator, public.Final, EcsFinal);
        try self.id_map.map(self.allocator, public.DontInherit, EcsDontInherit);
        try self.id_map.map(self.allocator, public.Exclusive, EcsExclusive);
        try self.id_map.map(self.allocator, public.Acyclic, EcsAcyclic);
        try self.id_map.map(self.allocator, public.Traversable, EcsTraversable);
        try self.id_map.map(self.allocator, public.Symmetric, EcsSymmetric);
        try self.id_map.map(self.allocator, public.With, EcsWith);
        try self.id_map.map(self.allocator, public.OneOf, EcsOneOf);
        try self.id_map.map(self.allocator, public.IsA, EcsIsA);
        try self.id_map.map(self.allocator, public.ChildOf, EcsChildOf);
        try self.id_map.map(self.allocator, public.DependsOn, EcsDependsOn);
        try self.id_map.map(self.allocator, public.SlotOf, EcsSlotOf);
        try self.id_map.map(self.allocator, public.OnDelete, EcsOnDelete);
        try self.id_map.map(self.allocator, public.OnDeleteTarget, EcsOnDeleteTarget);
        try self.id_map.map(self.allocator, public.Remove, EcsRemove);
        try self.id_map.map(self.allocator, public.Delete, EcsDelete);
        try self.id_map.map(self.allocator, public.Panic, EcsPanic);
        try self.id_map.map(self.allocator, public.PredEq, EcsPredEq);
        try self.id_map.map(self.allocator, public.PredMatch, EcsPredMatch);
        try self.id_map.map(self.allocator, public.PredLookup, EcsPredLookup);
        try self.id_map.map(self.allocator, public.Singleton, EcsSingleton);
        try self.id_map.map(self.allocator, public.DontFragment, EcsDontFragment);
        try self.id_map.map(self.allocator, public.Alias, EcsAlias);
        try self.id_map.map(self.allocator, public.Prefab, EcsPrefab);
        try self.id_map.map(self.allocator, public.Disabled, EcsDisabled);
        try self.id_map.map(self.allocator, public.OnStart, EcsOnStart);
        try self.id_map.map(self.allocator, public.PreFrame, EcsPreFrame);
        try self.id_map.map(self.allocator, public.OnLoad, EcsOnLoad);
        try self.id_map.map(self.allocator, public.PostLoad, EcsPostLoad);
        try self.id_map.map(self.allocator, public.PreUpdate, EcsPreUpdate);
        try self.id_map.map(self.allocator, public.OnUpdate, EcsOnUpdate);
        try self.id_map.map(self.allocator, public.OnValidate, EcsOnValidate);
        try self.id_map.map(self.allocator, public.PostUpdate, EcsPostUpdate);
        try self.id_map.map(self.allocator, public.PreStore, EcsPreStore);
        try self.id_map.map(self.allocator, public.OnStore, EcsOnStore);
        try self.id_map.map(self.allocator, public.PostFrame, EcsPostFrame);
        try self.id_map.map(self.allocator, public.Phase, EcsPhase);
        try self.id_map.map(self.allocator, public.OnAdd, EcsOnAdd);
        try self.id_map.map(self.allocator, public.OnRemove, EcsOnRemove);
        try self.id_map.map(self.allocator, public.OnSet, EcsOnSet);
        try self.id_map.map(self.allocator, public.Monitor, EcsMonitor);
        try self.id_map.map(self.allocator, public.OnTableCreate, EcsOnTableCreate);
        try self.id_map.map(self.allocator, public.OnTableDelete, EcsOnTableDelete);

        try self.id_map.map(self.allocator, public.Parent, zflecs.FLECS_IDEcsParentID_);

        return self;
    }

    pub fn deinit(self: *World) void {
        for (_component_by_id.values()) |iface| {
            if (iface.destroyManager) |destroyManager| {
                const info = zflecs.get_type_info(self.w, self.id_map.find(iface.id).?);
                destroyManager(self.toPublic(), info.hooks.ctx.?);
            }
        }

        _ = ecs_fini(self.w);

        self.simulated_systems.deinit(self.allocator);
        self.observer_map.deinit(self.allocator);
        self.id_map.deinit(self.allocator);
        self.obj2parent_obj.deinit(self.allocator);
        self.obj2prefab.deinit(self.allocator);
    }

    pub fn toPublic(world: *World) public.World {
        return .{ .ptr = world, .vtable = &world_vt };
    }

    pub fn cloneForFakeWorld(world: *World, fake_world: *zflecs.world_t) World {
        var w = world.*;
        w.w = fake_world;
        return w;
    }

    pub fn newEntity(self: *World, desc: public.EntityDecs) public.EntityId {
        return zflecs.entity_init(self.w, &.{
            .name = desc.name orelse null,
        });
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

    pub fn setComponent(self: *World, entity: public.EntityId, id: public.IdStrId, size: usize, ptr: ?*const anyopaque) public.EntityId {
        return zflecs.set_id(self.w, entity, self.id_map.find(id).?, size, ptr);
    }

    pub fn getMutComponent(self: *World, entity: public.EntityId, id: public.IdStrId) ?*anyopaque {
        return zflecs.get_mut_id(self.w, entity, self.id_map.find(id).?);
    }

    pub fn getComponent(self: *World, entity: public.EntityId, id: public.IdStrId) ?*const anyopaque {
        return zflecs.get_id(self.w, entity, self.id_map.find(id).?);
    }

    pub fn setSingletonComponent(self: *World, id: public.IdStrId, size: usize, ptr: ?*const anyopaque) void {
        _ = zflecs.set_id(self.w, self.id_map.find(id).?, self.id_map.find(id).?, size, ptr);
    }

    pub fn getSingletonComponent(self: *World, id: public.IdStrId) ?*const anyopaque {
        return zflecs.get_id(self.w, self.id_map.find(id).?, self.id_map.find(id).?);
    }

    pub fn getComponentManager(self: *World, id: public.IdStrId) ?*anyopaque {
        const ti = zflecs.get_type_info(self.w, self.id_map.find(id).?);
        return ti.hooks.ctx;
    }

    pub fn removeComponent(self: *World, entity: public.EntityId, id: public.IdStrId) void {
        return zflecs.remove_id(self.w, entity, self.id_map.find(id).?);
    }

    pub fn modified(self: *World, entity: public.EntityId, id: public.IdStrId) void {
        zflecs.modified_id(self.w, entity, self.id_map.find(id).?);
    }

    pub fn parent(self: *World, entity: public.EntityId) ?public.EntityId {
        const p = zflecs.get_parent(self.w, entity);
        return if (p == 0) return null else p;
    }

    pub fn children(self: *World, entity: public.EntityId) public.Iter {
        var it = zflecs.children(self.w, entity);
        return toIter(@ptrCast(&it));
    }

    pub fn progress(self: *World, dt: f32) bool {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "ECS: World progress");
        defer zone_ctx.End();

        const do_step = !self.simulate and self.simulate_do_step;
        self.simulate_do_step = false;

        if (do_step) {
            for (self.simulated_systems.items) |value| {
                zflecs.enable(self.w, value, true);
            }
        }

        const ret = zflecs.progress(self.w, dt);

        if (do_step) {
            for (self.simulated_systems.items) |value| {
                zflecs.enable(self.w, value, false);
            }
        }

        return ret;
    }

    pub fn createQuery(self: *World, query: public.QueryDesc) !public.Query {
        var qd = zflecs.query_desc_t{};

        if (query.orderByComponent) |c| {
            qd.order_by = self.id_map.find(c).?;
            qd.order_by_callback = query.orderByCallback;
        }

        for (query.query, 0..) |term, idx| {
            qd.terms[idx] = .{
                .id = self.id_map.find(term.id) orelse continue,
                .inout = @enumFromInt(@intFromEnum(term.inout)),
                .oper = @enumFromInt(@intFromEnum(term.oper)),
            };
        }

        const q = try zflecs.query_init(self.w, &qd);
        return .{
            .ptr = q,
            .vtable = &query_vt,
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

            _ = zflecs.set_id(
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

    pub fn setSimulate(self: *World, simulate: bool) void {
        for (self.simulated_systems.items) |value| {
            zflecs.enable(self.w, value, simulate);
        }
        self.simulate = simulate;
    }

    pub fn enableObserver(self: *World, id: cetech1.StrId32, enable: bool) void {
        zflecs.enable(self.w, self.observer_map.get(id).?, enable);
    }

    pub fn doStep(self: *World) void {
        if (self.simulate) return;
        self.simulate_do_step = true;
    }

    pub fn isSimulate(self: *World) bool {
        return self.simulate;
    }

    pub fn clear(self: *World) void {
        self.obj2prefab.clearRetainingCapacity();
        self.obj2parent_obj.clearRetainingCapacity();
    }

    pub fn debuguiMenuItems(self: *World, allocator: std.mem.Allocator) void {
        const is_simulate = self.isSimulate();

        if (coreui_private.api.menuItem(allocator, if (!is_simulate) coreui.Icons.Play else coreui.Icons.Pause, .{}, null)) {
            self.setSimulate(!is_simulate);
        }

        {
            coreui_private.api.beginDisabled(.{ .disabled = is_simulate });
            defer coreui_private.api.endDisabled();

            if (coreui_private.api.menuItem(allocator, coreui.Icons.ForwardStep, .{}, null)) {
                self.doStep();
            }
        }
    }

    pub fn uiRemoteDebugMenuItems(self: *World, allocator: std.mem.Allocator, port: ?u16) ?u16 {
        var remote_active = self.isRemoteDebugActive();
        var result: ?u16 = port;

        var buf: [256:0]u8 = undefined;
        const URL = "https://www.flecs.dev/explorer/?page=info&host=localhost:{d}";

        if (coreui_private.api.beginMenu(allocator, coreui.Icons.Entity ++ "  " ++ "ECS", true, null)) {
            defer coreui_private.api.endMenu();

            if (coreui_private.api.menuItemPtr(
                allocator,
                coreui.Icons.Debug ++ "  " ++ "Remote debug",
                .{ .selected = &remote_active },
                null,
            )) {
                if (self.setRemoteDebugActive(remote_active)) |p| {
                    const url = std.fmt.allocPrintSentinel(allocator, URL, .{p}, 0) catch return null;
                    defer allocator.free(url);

                    coreui_private.api.setClipboardText(url);
                    result = p;
                } else {
                    result = null;
                }
            }

            const copy_label = std.fmt.bufPrintZ(&buf, coreui.Icons.CopyToClipboard ++ "  " ++ "Copy url", .{}) catch return null;
            if (coreui_private.api.menuItem(allocator, copy_label, .{ .enabled = port != null }, null)) {
                const url = std.fmt.allocPrintSentinel(allocator, URL, .{port.?}, 0) catch return null;
                defer allocator.free(url);
                coreui_private.api.setClipboardText(url);
            }
        }

        return result;
    }

    pub fn findEntityByCdbObj(self: World, ent_obj: cdb.ObjId) !?public.EntityId {
        const prefab_ent = self.obj2prefab.get(ent_obj) orelse return null;

        // Query by parent storage.
        {
            var qd = zflecs.query_desc_t{};
            qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(EcsIsA, prefab_ent) };
            const q = try zflecs.query_init(self.w, &qd);
            defer zflecs.query_fini(q);

            var it = zflecs.query_iter(self.w, q);

            while (zflecs.iter_next(&it)) {
                const ents = it.entities();
                defer zflecs.iter_fini(&it);
                return ents[0];
            }
        }

        // Query by childof storage.
        {
            var qd = zflecs.query_desc_t{};
            qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(self.IsFromCdb, prefab_ent) };
            const q = try zflecs.query_init(self.w, &qd);
            defer zflecs.query_fini(q);

            var it = zflecs.query_iter(self.w, q);

            while (zflecs.iter_next(&it)) {
                const ents = it.entities();
                defer zflecs.iter_fini(&it);
                return ents[0];
            }
        }

        return null;
    }
};

var _cdb = &cdb_private.api;

var _world_pool: WorldPool = undefined;

const IdMap = struct {
    strId2id: StrId2Id = .{},
    id2StrId: Id2StrId = .{},

    pub fn deinit(self: *IdMap, allocator: std.mem.Allocator) void {
        self.strId2id.deinit(allocator);
        self.id2StrId.deinit(allocator);
    }

    pub fn map(self: *IdMap, allocator: std.mem.Allocator, strid: public.IdStrId, id: public.Id) !void {
        try self.strId2id.put(allocator, strid, id);
        try self.id2StrId.put(allocator, id, strid);
    }

    pub fn find(self: *IdMap, strid: public.IdStrId) ?public.Id {
        return self.strId2id.get(strid);
    }

    pub fn findById(self: *IdMap, id: public.Id) ?public.IdStrId {
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

pub fn init(allocator: std.mem.Allocator) !void {
    _ = @alignOf(public.TermId);

    _allocator = allocator;
    FlecsAllocator.allocator = allocator;

    _component_version = .{};

    _world_data_lck = .{};

    _world_data = .init();
    try _world_data.ensureTotalCapacity(allocator, 128);

    _world_pool = try WorldPool.init(allocator, 128);

    zflecs.os_init();
    _zflecs_os_impl = std.mem.bytesToValue(os.api_t, std.mem.asBytes(&zflecs.os_get_api()));

    // Memory fce
    if (true) {
        _zflecs_os_impl.malloc_ = &FlecsAllocator.alloc;
        _zflecs_os_impl.free_ = &FlecsAllocator.free;
        _zflecs_os_impl.realloc_ = &FlecsAllocator.realloc;
        _zflecs_os_impl.calloc_ = &FlecsAllocator.calloc;
    }

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

    _component_category_i_version = 0;
    _component_i_version = 0;

    _category_by_id = .{};
    _component_by_id = .{};
    _component_by_cdb_hash = .{};
}

pub fn deinit() void {
    for (_world_data.unmanaged.keys()) |value| {
        destroyWorld(value.toPublic());
    }

    // _obj2prefab.deinit(_allocator);
    // _obj2parent_obj.deinit(_allocator);
    _component_version.deinit(_allocator);

    _world_data.deinit(_allocator);
    _world_pool.deinit();

    _category_by_id.deinit(_allocator);
    _component_by_id.deinit(_allocator);
    _component_by_cdb_hash.deinit(_allocator);
}

fn getPrivateWorldPtr(world: public.World) *World {
    return @ptrCast(@alignCast(world.ptr));
}

var _component_version: ComponentVersionMap = undefined;
var _entity_version: cdb.TypeVersion = 0;

// TODO: SHIT!!!!!!
var sync_changes_from_cdb_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "ECS: sync changes from cdb",
    &[_]cetech1.StrId64{},
    null,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            const alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(alloc);

            var processed_obj = ChangedObjsSet.init();
            defer processed_obj.deinit(alloc);

            var deleted_ent_obj = ChangedObjsSet.init();
            defer deleted_ent_obj.deinit(alloc);

            const db = assetdb_private.getDb();

            //
            // Ents
            //

            // TODO: clean maps on delete components and entities
            {
                const changed = try _cdb.getChangeObjects(alloc, db, public.EntityCdb.typeIdx(_cdb, db), _entity_version);
                defer alloc.free(changed.objects);
                if (!changed.need_fullscan) {
                    for (changed.objects) |entity_obj| {
                        const is_alive = _cdb.isAlive(entity_obj);
                        if (!is_alive) {
                            _ = try deleted_ent_obj.add(alloc, entity_obj);
                            for (_world_data.unmanaged.keys()) |world| {
                                _ = world.obj2prefab.swapRemove(entity_obj);
                            }
                        }
                    }

                    // for (changed.objects) |entity_obj| {
                    //     if (processed_obj.contains(entity_obj)) continue;

                    //     const is_alive = !deleted_ent_obj.contains(entity_obj);

                    //     for (_world_data.unmanaged.keys()) |world| {
                    //         const w = toWorld(world);

                    //         const parent_obj = _cdb.getParent(entity_obj);
                    //         const parent_prefab_ent = world.obj2prefab.get(parent_obj) orelse continue;

                    //         // _ = prefab_ent; // autofix

                    //         if (is_alive) {
                    //             const parent = world.obj2parent_obj.get(entity_obj);
                    //             if (parent == null) {
                    //                 const ent = try getOrCreatePrefab(alloc, w, db, entity_obj);
                    //                 zflecs.add_id(world.w, ent, zflecs.make_pair(EcsChildOf, parent_prefab_ent));

                    //                 // try _obj2parent_obj.put(_allocator, .{ .world = w, .obj = entity_obj }, parent_obj);

                    //                 // Propagate to prefab instances
                    //                 var qd = zflecs.query_desc_t{};
                    //                 qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(world.IsFromCdb, parent_prefab_ent) };
                    //                 const q = try zflecs.query_init(world.w, &qd);
                    //                 defer zflecs.query_fini(q);
                    //                 var it = zflecs.query_iter(world.w, q);
                    //                 while (zflecs.iter_next(&it)) {
                    //                     const ents = it.entities();
                    //                     const eents = zflecs.bulk_new_w_id(world.w, zflecs.make_pair(EcsIsA, ent), @intCast(ents.len));
                    //                     for (ents, 0..) |e, idx| {
                    //                         zflecs.add_id(@ptrCast(world.w), eents[idx], zflecs.make_pair(EcsChildOf, e));
                    //                     }
                    //                 }
                    //             }
                    //         } else {
                    //             const prefab_ent = world.obj2prefab.get(entity_obj).?;
                    //             zflecs.delete_with(world.w, zflecs.make_pair(world.IsFromCdb, prefab_ent));
                    //             zflecs.delete(world.w, prefab_ent);
                    //             _ = world.obj2prefab.swapRemove(entity_obj);
                    //         }
                    //     }

                    //     _ = try processed_obj.add(alloc, entity_obj);
                    // }
                } else {
                    if (_cdb.getAllObjectByType(alloc, db, public.EntityCdb.typeIdx(_cdb, db))) |objs| {
                        for (objs) |graph| {
                            _ = graph; // autofix
                        }
                    }
                }

                _entity_version = changed.last_version;
            }

            //
            // Components
            //
            const impls = try apidb.api.getImpl(_allocator, public.ComponentI);
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
                        if (processed_obj.contains(component_obj)) continue;

                        //if (deleted_ent_obj.contains()) continue;
                        const worlds = _world_data.unmanaged.keys();
                        for (worlds) |world| {
                            const w = toWorld(world);

                            const parent_obj = world.obj2parent_obj.get(component_obj);
                            const new_component = parent_obj == null;

                            //try world.obj2parent_obj.put(_allocator, component_obj, obj);

                            const entity_obj = parent_obj orelse _cdb.getParent(component_obj);
                            const prefab_ent = world.obj2prefab.get(entity_obj) orelse continue;
                            const deleted_entity = !_cdb.isAlive(entity_obj);

                            if (false) {
                                if (!is_alive) {
                                    log.debug("Deleted component {s}", .{iface.name});
                                } else {
                                    if (new_component) {
                                        log.debug("New component {s}", .{iface.name});
                                    } else {
                                        log.debug("Changed component {s}", .{iface.name});
                                    }
                                }
                            }

                            if (is_alive) {
                                if (deleted_entity) continue;

                                if (new_component) {
                                    try world.obj2parent_obj.put(_allocator, component_obj, entity_obj);
                                }

                                const component_data = try alloc.alloc(u8, iface.size);
                                defer alloc.free(component_data);
                                @memset(component_data, 0);

                                if (iface.fromCdb) |fromCdb| {
                                    try fromCdb(alloc, component_obj, component_data);
                                }

                                // Propagate to prefab
                                _ = w.setComponentRaw(prefab_ent, iface.id, iface.size, component_data.ptr);
                                // w.modifiedRaw(prefab_ent, iface.id);

                                // Propagate to prefab instances
                                {
                                    var qd = zflecs.query_desc_t{};
                                    qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(EcsIsA, prefab_ent) };
                                    const q = try zflecs.query_init(world.w, &qd);
                                    defer zflecs.query_fini(q);
                                    var it = zflecs.query_iter(world.w, q);
                                    while (zflecs.iter_next(&it)) {
                                        const ents = it.entities();
                                        for (ents) |ent| {
                                            _ = w.setComponentRaw(ent, iface.id, iface.size, component_data.ptr);
                                            w.modifiedRaw(ent, iface.id);
                                        }
                                    }
                                }

                                {
                                    // Propagate to prefab instances
                                    var qd = zflecs.query_desc_t{};
                                    qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(world.IsFromCdb, prefab_ent) };
                                    const q = try zflecs.query_init(world.w, &qd);
                                    defer zflecs.query_fini(q);
                                    var it = zflecs.query_iter(world.w, q);
                                    while (zflecs.iter_next(&it)) {
                                        const ents = it.entities();
                                        for (ents) |ent| {
                                            _ = w.setComponentRaw(ent, iface.id, iface.size, component_data.ptr);
                                            w.modifiedRaw(ent, iface.id);
                                        }
                                    }
                                }
                            } else {
                                if (!deleted_entity) {

                                    // Propagate to prefab instances
                                    var qd = zflecs.query_desc_t{};
                                    qd.terms[0] = .{ .inout = .In, .id = zflecs.make_pair(EcsIsA, prefab_ent) };
                                    const q = try zflecs.query_init(world.w, &qd);
                                    defer zflecs.query_fini(q);
                                    var it = zflecs.query_iter(world.w, q);
                                    while (zflecs.iter_next(&it)) {
                                        const ents = it.entities();
                                        for (ents) |ent| {
                                            zflecs.remove_id(world.w, ent, world.id_map.find(iface.id).?);
                                        }
                                    }

                                    zflecs.remove_id(world.w, prefab_ent, world.id_map.find(iface.id).?);
                                }

                                _ = world.obj2parent_obj.swapRemove(component_obj);
                            }
                        }

                        _ = try processed_obj.add(alloc, component_obj);
                    }
                } else {
                    if (_cdb.getAllObjectByType(alloc, db, type_idx)) |objs| {
                        for (objs) |graph| {
                            _ = graph; // autofix
                        }
                    }
                }

                try _component_version.put(_allocator, type_idx, changed.last_version);
            }
        }
    },
);

var _component_category_i_version: cetech1.apidb.InterfaceVersion = 0;
var _component_i_version: cetech1.apidb.InterfaceVersion = 0;

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "ECS: progress worlds",
    &[_]cetech1.StrId64{},
    null,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;

            const allocator = try tempalloc.api.create();
            defer tempalloc.api.destroy(allocator);

            const component_category_i_version = apidb.api.getInterafcesVersion(public.ComponentCategoryI);
            if (component_category_i_version != _component_category_i_version) {
                log.debug("Supported components categories:", .{});
                const impls = try apidb.api.getImpl(allocator, public.ComponentCategoryI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    log.debug("\t - {s}", .{iface.name});
                    try _category_by_id.put(_allocator, .fromStr(iface.name), iface);
                }
                _component_category_i_version = component_category_i_version;
            }

            const component_i_version = apidb.api.getInterafcesVersion(public.ComponentI);
            if (component_i_version != _component_i_version) {
                log.debug("Supported components:", .{});
                const impls = try apidb.api.getImpl(allocator, public.ComponentI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    log.debug("\t - {s} ({s})", .{ iface.display_name, iface.type_name });
                    try _component_by_id.put(_allocator, iface.id, iface);
                    try _component_by_cdb_hash.put(_allocator, iface.cdb_type_hash, iface);
                }
                _component_i_version = component_i_version;
            }

            try progressAll(allocator, dt);
        }
    },
);

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(
    struct {
        pub fn createTypes(db: cdb.DbId) !void {
            // Entity
            {
                _ = try _cdb.addType(
                    db,
                    public.EntityCdb.name,
                    &[_]cdb.PropDef{
                        .{ .prop_idx = public.EntityCdb.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                        .{ .prop_idx = public.EntityCdb.propIdx(.ChildrenStorage), .name = "children_storage", .type = cdb.PropType.STR },
                        .{ .prop_idx = public.EntityCdb.propIdx(.Components), .name = "components", .type = cdb.PropType.SUBOBJECT_SET },
                        .{
                            .prop_idx = public.EntityCdb.propIdx(.Childrens),
                            .name = "childrens",
                            .type = cdb.PropType.SUBOBJECT_SET,
                            .type_hash = public.EntityCdb.type_hash,
                        },
                    },
                );
            }
        }
    },
);

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.EcsAPI, &api);

    try apidb.api.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, true);
    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &sync_changes_from_cdb_task, true);
    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, true);
}

pub var api = cetech1.ecs.EcsAPI{
    .createWorld = createWorld,
    .destroyWorld = destroyWorld,
    .toWorld = @ptrCast(&toWorld),
    .findCategoryById = findCategoryById,
    .findComponentIByCdbHash = findComponentIByCdbHash,
    .findComponentIById = findComponentIById,
    .spawnManyFromCDB = spawnManyFromCDB,
};

const CategoryByIdMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.ComponentCategoryI);
const ComponentByCdbHashMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.ComponentI);
const ComponentByIdMap = cetech1.AutoArrayHashMap(public.IdStrId, *const public.ComponentI);

var _category_by_id: CategoryByIdMap = undefined;
var _component_by_id: ComponentByIdMap = undefined;
var _component_by_cdb_hash: ComponentByCdbHashMap = undefined;

fn findCategoryById(name: cetech1.StrId32) ?*const public.ComponentCategoryI {
    return _category_by_id.get(name);
}

fn findComponentIByCdbHash(cdb_hash: cdb.TypeHash) ?*const public.ComponentI {
    return _component_by_cdb_hash.get(cdb_hash);
}

fn findComponentIById(name: public.IdStrId) ?*const public.ComponentI {
    return _component_by_id.get(name);
}

fn getOrCreatePrefab(
    allocator: std.mem.Allocator,
    world: public.World,
    db: cdb.DbId,
    obj: cdb.ObjId,
    parent: ?public.EntityId,
    children_storage: ?public.ChildrenStorageType,
) !public.EntityId {
    const w = getPrivateWorldPtr(world);

    const get_or_put = try w.obj2prefab.getOrPut(_allocator, obj);
    if (get_or_put.found_existing) return get_or_put.value_ptr.*;

    const top_level_obj_r = public.EntityCdb.read(_cdb, obj).?;
    const name = public.EntityCdb.readStr(_cdb, top_level_obj_r, .Name);

    const prefab_ent = w.newEntity(.{ .name = name });
    get_or_put.value_ptr.* = prefab_ent;
    zflecs.add_id(w.w, prefab_ent, EcsPrefab);

    if (children_storage) |cs| {
        if (parent) |p| {
            switch (cs) {
                .Parent => {
                    _ = zflecs.set_id(
                        w.w,
                        prefab_ent,
                        zflecs.FLECS_IDEcsParentID_,
                        @sizeOf(zflecs.EcsParent),
                        &zflecs.EcsParent{ .value = p },
                    );
                },
                .ChildOf => {
                    zflecs.add_id(w.w, prefab_ent, zflecs.make_pair(EcsChildOf, p));
                },
            }
        }

        if (cs == .ChildOf) {
            zflecs.add_id(w.w, prefab_ent, zflecs.make_pair(w.IsFromCdb, prefab_ent));
        }
    }

    // Create components
    if (try public.EntityCdb.readSubObjSet(_cdb, top_level_obj_r, .Components, allocator)) |components| {
        defer allocator.free(components);

        for (components) |component_obj| {
            const component_hash = _cdb.getTypeHash(db, component_obj.type_idx).?;

            try w.obj2parent_obj.put(_allocator, component_obj, obj);

            //log.debug("Create component {s}", .{_cdb.getTypeName(db, component_obj.type_idx).?});
            const iface = findComponentIByCdbHash(component_hash).?;

            const component_data = try allocator.alloc(u8, iface.size);
            defer allocator.free(component_data);

            @memset(component_data, 0);

            if (iface.fromCdb) |fromCdb| {
                try fromCdb(allocator, component_obj, component_data);
            }

            _ = world.setComponentRaw(prefab_ent, iface.id, iface.size, component_data.ptr);
        }
    }

    if (try public.EntityCdb.readSubObjSet(_cdb, top_level_obj_r, .Childrens, allocator)) |childrens| {
        defer allocator.free(childrens);

        const parent_type_str = public.EntityCdb.readStr(_cdb, top_level_obj_r, .ChildrenStorage) orelse "";
        const parent_type = std.meta.stringToEnum(public.ChildrenStorageType, parent_type_str) orelse .Parent;

        for (childrens) |child| {
            try w.obj2parent_obj.put(_allocator, child, obj);

            const ent = try getOrCreatePrefab(allocator, world, db, child, prefab_ent, parent_type);
            _ = ent;
        }
    }

    return prefab_ent;
}

fn spawnManyFromCDB(allocator: std.mem.Allocator, world: public.World, obj: cdb.ObjId, count: usize) anyerror![]public.EntityId {
    var zone = profiler_private.ztracy.ZoneN(@src(), "ECS - spawn many from cdb");
    defer zone.End();

    const db = _cdb.getDbFromObjid(obj);
    const prefab = try getOrCreatePrefab(allocator, world, db, obj, null, null);
    const top_level_entities = world.newEntities(allocator, zflecs.make_pair(EcsIsA, prefab), count).?;
    return top_level_entities;
}

const world_vt = public.World.VTable{
    .newEntity = @ptrCast(&World.newEntity),
    .newEntities = @ptrCast(&World.newEntities),
    .destroyEntities = @ptrCast(&World.destroyEntities),

    .setComponent = @ptrCast(&World.setComponent),
    .getMutComponent = @ptrCast(&World.getMutComponent),
    .getComponent = @ptrCast(&World.getComponent),

    .removeComponent = @ptrCast(&World.removeComponent),
    .setSingletonComponent = @ptrCast(&World.setSingletonComponent),
    .getSingletonComponent = @ptrCast(&World.getSingletonComponent),

    .getComponentManager = @ptrCast(&World.getComponentManager),
    .modified = @ptrCast(&World.modified),

    .parent = @ptrCast(&World.parent),
    .children = @ptrCast(&World.children),

    .progress = @ptrCast(&World.progress),

    .createQuery = @ptrCast(&World.createQuery),

    .deferBegin = @ptrCast(&World.deferBegin),
    .deferEnd = @ptrCast(&World.deferEnd),
    .deferSuspend = @ptrCast(&World.deferSuspend),
    .deferResume = @ptrCast(&World.deferResume),
    .isRemoteDebugActive = @ptrCast(&World.isRemoteDebugActive),
    .setRemoteDebugActive = @ptrCast(&World.setRemoteDebugActive),
    .setSimulate = @ptrCast(&World.setSimulate),
    .enableObserver = @ptrCast(&World.enableObserver),
    .isSimulate = @ptrCast(&World.isSimulate),
    .doStep = @ptrCast(&World.doStep),
    .clear = @ptrCast(&World.clear),
    .debuguiMenuItems = @ptrCast(&World.debuguiMenuItems),
    .uiRemoteDebugMenuItems = @ptrCast(&World.uiRemoteDebugMenuItems),
    .findEntityByCdbObj = @ptrCast(&World.findEntityByCdbObj),
};

const iter_vt = public.Iter.VTable.implement(struct {
    pub fn getWorld(self: *anyopaque) public.World {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));

        const w: *World = @ptrCast(@alignCast(zflecs.get_binding_ctx(it.world).?));

        // if (it.world == it.world) {
        //     log.debug("fffffff", .{});
        // } else {
        //     log.debug("dasdasdasdasdas", .{});
        // }

        // TODO: world vs. real world
        return World.toPublic(w);
    }

    pub fn count(self: *anyopaque) usize {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return it.count();
    }

    pub fn field(self: *anyopaque, size: usize, index: i8) ?*anyopaque {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return zflecs.field_w_size(it, size, index);
    }

    pub fn isSelf(self: *anyopaque, index: i8) bool {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return zflecs.field_is_self(it, index);
    }

    pub fn getParam(self: *anyopaque) ?*anyopaque {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return it.param;
    }

    pub fn entites(self: *anyopaque) []const public.EntityId {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return it.entities();
    }

    pub fn next(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return zflecs.iter_next(it);
    }

    pub fn nextChildren(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return zflecs.children_next(it);
    }

    pub fn changed(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return zflecs.query_changed(@constCast(it.query));
    }

    pub fn skip(self: *anyopaque) void {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return zflecs.iter_skip(it);
    }

    pub fn getSystem(self: *anyopaque) *const public.SystemI {
        const it: *zflecs.iter_t = @ptrCast(@alignCast(self));
        return @ptrCast(@alignCast(it.ctx));
    }
});

pub const query_count_t = extern struct {
    results: i32,
    entities: i32,
    tables: i32,
    empty_tables: i32,
};
extern fn ecs_query_count(query: *const zflecs.query_t) query_count_t;

const query_vt = public.Query.VTable.implement(struct {
    pub fn destroy(self: *anyopaque) void {
        zflecs.query_fini(@ptrCast(@alignCast(self)));
    }

    pub fn iter(self: *anyopaque) !public.Iter {
        const q: *zflecs.query_t = @ptrCast(@alignCast(self));
        const it = zflecs.query_iter(q.world.?, q);

        return .{ .data = std.mem.toBytes(it), .vtable = &iter_vt };
    }

    pub fn next(self: *anyopaque, iter_: *public.Iter) bool {
        _ = self;
        const it: *zflecs.iter_t = @ptrCast(@alignCast(&iter_.data));
        return zflecs.query_next(it);
    }

    pub fn count(self: *anyopaque) public.QueryCount {
        const q: *zflecs.query_t = @ptrCast(@alignCast(self));
        const qc = ecs_query_count(q);
        return .{
            .results = qc.results,
            .entities = qc.entities,
            .tables = qc.tables,
            .empty_tables = qc.empty_tables,
        };
    }
});

pub fn progressAll(allocator: std.mem.Allocator, dt: f32) !void {
    var zone = profiler_private.ztracy.ZoneN(@src(), "ECS progress all worlds");
    defer zone.End();

    const parallel = false; // lets make all workers for one world.
    if (parallel) {
        var tasks = try cetech1.task.TaskIdList.initCapacity(allocator, _world_data.count());
        defer tasks.deinit(allocator);

        for (_world_data.keys()) |world| {
            const Task = struct {
                world: *World,
                dt: f32,
                pub fn exec(s: *@This()) !void {
                    _ = s.world.progress(s.dt);
                }
            };
            const task_id = try task.api.schedule(
                cetech1.task.TaskID.none,
                Task{
                    .world = world,
                    .dt = dt,
                },
                .{},
            );
            tasks.appendAssumeCapacity(task_id);
        }

        if (tasks.items.len != 0) {
            task.api.waitMany(tasks.items);
        }
    } else {
        for (_world_data.unmanaged.keys()) |world| {
            _ = World.progress(world, dt);
        }
    }
}

extern fn ecs_mini() *zflecs.world_t;
extern fn FlecsPipelineImport(w: *zflecs.world_t) void;

extern const FLECS_IDEcsRestID_: zflecs.entity_t;

const EcsQueryMatchPrefab = (1 << 1);
const EcsQueryMatchDisabled = (1 << 2);
const EcsQueryMatchEmptyTables = (1 << 3);
const EcsQueryNoData = (1 << 4);
const EcsQueryIsInstanced = (1 << 5);
const EcsQueryAllowUnresolvedByName = (1 << 6);
const EcsQueryTableOnly = (1 << 7);

pub const worker_next = ecs_worker_next;
extern fn ecs_worker_next(it: *zflecs.iter_t) bool;

fn imports(w: *zflecs.world_t) void {
    const root_scope = zflecs.get_scope(w);

    FlecsPipelineImport(w);
    zflecs.FlecsStatsImport(w);
    zflecs.FlecsRestImport(w);

    _ = zflecs.set_scope(w, root_scope);
}

fn free_w(ctx: ?*anyopaque) callconv(.c) void {
    _ = ctx;
}

pub fn createWorld() !public.World {
    var z = profiler_private.ztracy.ZoneN(@src(), "ECS: Create world");
    defer z.End();

    const world = ecs_mini();

    {
        var zz = profiler_private.ztracy.ZoneN(@src(), "ECS: import flecs");
        defer zz.End();

        imports(world);
    }

    const cetech_entity = zflecs.new_entity(world, "cetech1");
    const module = zflecs.module_init(
        world,
        "cetech1",
        &zflecs.component_desc_t{
            .entity = cetech_entity,
            .type = .{
                .size = 0,
                .alignment = 0,
            },
        },
    );

    const last_scope = zflecs.set_scope(world, module);
    defer _ = zflecs.set_scope(world, last_scope);

    if (task.api.getThreadNum() > 1) {
        zflecs.set_task_threads(world, @intCast(task.api.getThreadNum() - 1));
    }

    _world_data_lck.lock();
    defer _world_data_lck.unlock();

    var w = _world_pool.create(null);
    w.* = try World.init(_allocator, world);

    zflecs.set_binding_ctx(world, w, free_w);

    const wd = World.toPublic(w);
    _ = try _world_data.add(_allocator, w);

    // Register components
    {
        var zz = profiler_private.ztracy.ZoneN(@src(), "ECS: register components");
        defer zz.End();

        const components_impl = apidb.api.getImpl(_allocator, public.ComponentI) catch undefined;
        defer _allocator.free(components_impl);
        for (components_impl) |iface| {
            if (iface.size == 0) {
                log.err("Component must have size", .{});
                continue;
            }

            const instansiate_trait_pair: ?zflecs.id_t = switch (iface.on_instantiate) {
                .dont_inherit => zflecs.make_pair(EcsOnInstantiate, EcsDontInherit),
                .inherit => zflecs.make_pair(EcsOnInstantiate, EcsInherit),
                .override => null,
                // .override => zflecs.make_pair(EcsOnInstantiate, EcsOverride),
            };

            const component_id = zflecs.entity_init(world, &.{
                .use_low_id = true,
                .name = iface.name,
                .symbol = iface.type_name,
                .add = if (instansiate_trait_pair) |pair| &.{ pair, 0 } else null,
            });
            try w.id_map.map(w.allocator, iface.id, component_id);

            if (iface.size != 0) {
                _ = zflecs.component_init(world, &.{
                    .entity = component_id,
                    .type = .{
                        .name = iface.name,
                        .alignment = @intCast(iface.aligment),
                        .size = @intCast(iface.size),
                        .hooks = .{
                            .binding_ctx = @constCast(iface),
                            .ctx = if (iface.createManager) |createManager| try createManager(wd) else null,

                            .ctor = if (iface.onCreate) |onCreate| @ptrCast(onCreate) else null,
                            .dtor = if (iface.onDestroy) |onDestroy| @ptrCast(onDestroy) else null,
                            .copy = if (iface.onCopy) |onCopy| @ptrCast(onCopy) else null,
                            .move = if (iface.onMove) |onMove| @ptrCast(onMove) else null,

                            .on_add = if (iface.onAdd != null) struct {
                                pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                                    const manager: ?*anyopaque = @ptrCast(@alignCast(iter.ctx));
                                    const component_i: ?*public.ComponentI = @ptrCast(@alignCast(iter.callback_ctx));

                                    var it = toIter(@ptrCast(iter));

                                    component_i.?.onAdd.?(manager, &it) catch undefined;
                                }
                            }.f else null,

                            .on_set = if (iface.onSet != null) struct {
                                pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                                    const manager: ?*anyopaque = @ptrCast(@alignCast(iter.ctx));
                                    const component_i: ?*public.ComponentI = @ptrCast(@alignCast(iter.callback_ctx));

                                    var it = toIter(@ptrCast(iter));

                                    component_i.?.onSet.?(manager, &it) catch undefined;
                                }
                            }.f else null,

                            .on_remove = if (iface.onRemove != null) struct {
                                pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                                    const manager: ?*anyopaque = @ptrCast(@alignCast(iter.ctx));
                                    const component_i: ?*public.ComponentI = @ptrCast(@alignCast(iter.callback_ctx));

                                    var it = toIter(@ptrCast(iter));

                                    component_i.?.onRemove.?(manager, &it) catch undefined;
                                }
                            }.f else null,
                        },
                    },
                });
            }

            if (iface.singleton) {
                zflecs.add_id(world, w.id_map.find(iface.id).?, EcsSingleton);
            }
        }

        for (components_impl) |iface| {
            if (iface.with) |with| {
                for (with) |value| {
                    if (w.id_map.find(value)) |second| {
                        zflecs.add_pair(world, w.id_map.find(iface.id).?, EcsWith, second);
                    }
                }
            }
        }
    }

    // Register systems
    {
        var zz = profiler_private.ztracy.ZoneN(@src(), "ECS: register systems");
        defer zz.End();

        const systems_impl = apidb.api.getImpl(_allocator, public.SystemI) catch undefined;
        defer _allocator.free(systems_impl);
        for (systems_impl) |iface| {
            var system_desc = zflecs.system_desc_t{
                .phase = w.id_map.find(iface.phase).?,

                .callback = if (iface.iterate != null) struct {
                    pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                        const s: *const public.SystemI = @ptrCast(@alignCast(iter.ctx));

                        var zone_ctx = profiler_private.api.Zone(@src());
                        zone_ctx.Name(s.name);
                        defer zone_ctx.End();

                        var it = toIter(@ptrCast(iter));
                        const it_world: *World = @ptrCast(@alignCast(zflecs.get_binding_ctx(iter.world).?));
                        var ww = it_world.cloneForFakeWorld(iter.world);
                        const pw = ww.toPublic();

                        s.iterate.?(pw, &it, iter.delta_time) catch undefined;
                    }
                }.f else null,
                .run = if (iface.tick != null) struct {
                    pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                        const s: *const public.SystemI = @ptrCast(@alignCast(iter.ctx));

                        var zone_ctx = profiler_private.api.Zone(@src());
                        zone_ctx.Name(s.name);
                        defer zone_ctx.End();

                        var it = toIter(@ptrCast(iter));
                        const it_world: *World = @ptrCast(@alignCast(zflecs.get_binding_ctx(iter.world).?));
                        var ww = it_world.cloneForFakeWorld(iter.world);

                        const pw = ww.toPublic();

                        s.tick.?(pw, &it, iter.delta_time) catch undefined;
                    }
                }.f else null,
                .multi_threaded = iface.multi_threaded,
                .immediate = iface.immediate,

                .ctx = @ptrCast(@constCast(iface)),
            };

            system_desc.query.cache_kind = @enumFromInt(@intFromEnum(iface.cache_kind));

            if (iface.orderByComponent) |c| {
                system_desc.query.order_by = w.id_map.find(c).?;
                system_desc.query.order_by_callback = iface.orderByCallback;
            }

            for (iface.query, 0..) |term, idx| {
                system_desc.query.terms[idx] = .{
                    .id = w.id_map.find(term.id) orelse undefined,
                    .inout = @enumFromInt(@intFromEnum(term.inout)),
                    .oper = @enumFromInt(@intFromEnum(term.oper)),
                    .src = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.src)),
                    .first = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.first)),
                    .second = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.second)),
                };
            }

            _ = zflecs.SYSTEM(world, iface.name, &system_desc);

            if (iface.simulation) {
                try w.simulated_systems.append(w.allocator, system_desc.entity);
            }
        }
    }

    // Register Observers
    {
        var zz = profiler_private.ztracy.ZoneN(@src(), "ECS: register observers");
        defer zz.End();

        const observers_iface = apidb.api.getImpl(_allocator, public.ObserverI) catch undefined;
        defer _allocator.free(observers_iface);
        for (observers_iface) |iface| {
            var system_desc = zflecs.observer_desc_t{
                .callback = if (iface.iterate != null) struct {
                    pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                        const s: *const public.ObserverI = @ptrCast(@alignCast(iter.ctx));

                        var zone_ctx = profiler_private.api.Zone(@src());
                        zone_ctx.Name(s.name);
                        defer zone_ctx.End();

                        var it = toIter(@ptrCast(iter));
                        const it_world: *World = @ptrCast(@alignCast(zflecs.get_binding_ctx(iter.world).?));
                        var ww = it_world.cloneForFakeWorld(iter.world);
                        const pw = ww.toPublic();

                        s.iterate.?(pw, &it, iter.delta_time) catch undefined;
                    }
                }.f else null,
                .run = if (iface.tick != null) struct {
                    pub fn f(iter: *zflecs.iter_t) callconv(.c) void {
                        const s: *const public.ObserverI = @ptrCast(@alignCast(iter.ctx));

                        var zone_ctx = profiler_private.api.Zone(@src());
                        zone_ctx.Name(s.name);
                        defer zone_ctx.End();

                        var it = toIter(@ptrCast(iter));
                        const it_world: *World = @ptrCast(@alignCast(zflecs.get_binding_ctx(iter.world).?));
                        var ww = it_world.cloneForFakeWorld(iter.world);

                        const pw = ww.toPublic();

                        s.tick.?(pw, &it, iter.delta_time) catch undefined;
                    }
                }.f else null,
                .ctx = @ptrCast(@constCast(iface)),
            };

            for (iface.query, 0..) |term, idx| {
                system_desc.query.terms[idx] = .{
                    .id = w.id_map.find(term.id) orelse undefined,
                    .inout = @enumFromInt(@intFromEnum(term.inout)),
                    .oper = @enumFromInt(@intFromEnum(term.oper)),
                    .src = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.src)),
                    .first = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.first)),
                    .second = std.mem.bytesToValue(zflecs.term_ref_t, std.mem.asBytes(&term.second)),
                };
            }

            for (iface.events, 0..) |term, idx| {
                system_desc.events[idx] = w.id_map.find(term) orelse undefined;
            }

            const observer_id = zflecs.OBSERVER(world, iface.name, &system_desc);
            try w.observer_map.put(w.allocator, .fromStr(iface.name), observer_id);
        }
    }

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

    const w: *World = @ptrCast(@alignCast(world.ptr));
    w.deinit();

    _world_data_lck.lock();
    defer _world_data_lck.unlock();
    _ = _world_data.remove(@ptrCast(@alignCast(world.ptr)));
}

fn toIter(iter: *public.IterO) public.Iter {
    const it: *zflecs.iter_t = @ptrCast(@alignCast(iter));

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

fn api_task_new(clb: zflecs.os.thread_callback_t, data: ?*anyopaque) callconv(.c) zflecs.os.thread_t {
    const Task = struct {
        clb: zflecs.os.thread_callback_t,
        data: ?*anyopaque,
        pub fn exec(s: *@This()) !void {
            var zone = profiler_private.ztracy.ZoneN(@src(), "ECS workload");
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
        .{},
    ) catch undefined;
    return @intFromEnum(task_id);
}

fn api_task_join(thread: zflecs.os.thread_t) callconv(.c) ?*anyopaque {
    task.api.wait(@enumFromInt(thread));
    return null;
}

fn api_log(level: i32, file: [*:0]const u8, line: i32, msg: [*:0]const u8) callconv(.c) void {
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
extern const EcsSingleton: entity_t;
extern const EcsDontFragment: entity_t;
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
// extern const EcsOnTableEmpty: entity_t;
// extern const EcsOnTableFill: entity_t;

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
    pub const proc_t = *const fn () callconv(.c) void;
    pub const api_init_t = *const fn () callconv(.c) void;
    pub const api_fini_t = *const fn () callconv(.c) void;
    pub const api_malloc_t = *const fn (zflecs.size_t) callconv(.c) ?*anyopaque;
    pub const api_free_t = *const fn (?*anyopaque) callconv(.c) void;
    pub const api_realloc_t = *const fn (?*anyopaque, zflecs.size_t) callconv(.c) ?*anyopaque;
    pub const api_calloc_t = *const fn (zflecs.size_t) callconv(.c) ?*anyopaque;
    pub const api_strdup_t = *const fn ([*:0]const u8) callconv(.c) [*c]u8;
    pub const thread_callback_t = *const fn (?*anyopaque) callconv(.c) ?*anyopaque;
    pub const api_thread_new_t = *const fn (thread_callback_t, ?*anyopaque) callconv(.c) thread_t;
    pub const api_thread_join_t = *const fn (thread_t) callconv(.c) ?*anyopaque;
    pub const api_thread_self_t = *const fn () callconv(.c) thread_id_t;
    pub const api_task_new_t = *const fn (thread_callback_t, ?*anyopaque) callconv(.c) thread_t;
    pub const api_task_join_t = *const fn (thread_t) callconv(.c) ?*anyopaque;
    pub const api_ainc_t = *const fn (*i32) callconv(.c) i32;
    pub const api_lainc_t = *const fn (*i64) callconv(.c) i64;
    pub const api_mutex_new_t = *const fn () callconv(.c) mutex_t;
    pub const api_mutex_lock_t = *const fn (mutex_t) callconv(.c) void;
    pub const api_mutex_unlock_t = *const fn (mutex_t) callconv(.c) void;
    pub const api_mutex_free_t = *const fn (mutex_t) callconv(.c) void;
    pub const api_cond_new_t = *const fn () callconv(.c) cond_t;
    pub const api_cond_free_t = *const fn (cond_t) callconv(.c) void;
    pub const api_cond_signal_t = *const fn (cond_t) callconv(.c) void;
    pub const api_cond_broadcast_t = *const fn (cond_t) callconv(.c) void;
    pub const api_cond_wait_t = *const fn (cond_t, mutex_t) callconv(.c) void;
    pub const api_sleep_t = *const fn (i32, i32) callconv(.c) void;
    pub const api_enable_high_timer_resolution_t = *const fn (bool) callconv(.c) void;
    pub const api_get_time_t = *const fn (*zflecs.time_t) callconv(.c) void;
    pub const api_now_t = *const fn () callconv(.c) u64;
    pub const api_log_t = *const fn (i32, [*:0]const u8, i32, [*:0]const u8) callconv(.c) void;
    pub const api_abort_t = *const fn () callconv(.c) void;
    pub const api_dlopen_t = *const fn ([*:0]const u8) callconv(.c) dl_t;
    pub const api_dlproc_t = *const fn (dl_t, [*:0]const u8) callconv(.c) proc_t;
    pub const api_dlclose_t = *const fn (dl_t) callconv(.c) void;
    pub const api_module_to_path_t = *const fn ([*:0]const u8) callconv(.c) [*:0]u8;

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

    var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;
    var allocator: ?std.mem.Allocator = null;

    fn alloc(size: i32) callconv(.c) ?*anyopaque {
        if (size < 0) {
            return null;
        }

        const allocation_size = Alignment + @as(usize, @intCast(size));

        const data = allocator.?.alignedAlloc(u8, .fromByteUnits(Alignment), allocation_size) catch {
            return null;
        };

        var allocation_header = @as(
            *align(Alignment) AllocationHeader,
            @ptrCast(@alignCast(data.ptr)),
        );

        allocation_header.size = allocation_size;

        return data.ptr + Alignment;
    }

    fn free(ptr: ?*anyopaque) callconv(.c) void {
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

    fn realloc(old: ?*anyopaque, size: i32) callconv(.c) ?*anyopaque {
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

    fn calloc(size: i32) callconv(.c) ?*anyopaque {
        const data_maybe = alloc(size);
        if (data_maybe) |data| {
            @memset(@as([*]u8, @ptrCast(data))[0..@as(usize, @intCast(size))], 0);
        }

        return data_maybe;
    }
};
