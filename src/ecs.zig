const std = @import("std");

const builtin = @import("builtin");

const cetech1 = @import("cetech1");
const apidb = @import("apidb.zig");
const profiler_private = @import("profiler.zig");
const task = @import("task.zig");
const graph_private = @import("graphvm.zig");
const tempalloc = @import("tempalloc.zig");
const assetdb_private = @import("assetdb.zig");

const public = cetech1.ecs;

const zflecs = @import("zflecs");
const entity_t = zflecs.entity_t;

const module_name = .ecs;
const log = std.log.scoped(module_name);

const WorldPool = cetech1.mem.PoolWithLock(WorldImpl);
const WorldSet = std.AutoArrayHashMap(*zflecs.world_t, void);

const StrId2Id = std.AutoArrayHashMap(cetech1.strid.StrId32, public.Id);
const Id2StrId = std.AutoArrayHashMap(public.Id, cetech1.strid.StrId32);

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

const WorldImpl = struct {
    pub fn init(world: *zflecs.world_t) public.World {
        return .{ .ptr = world, .vtable = &world_vt };
    }

    pub fn deinit(self: *zflecs.world_t) void {
        _ = ecs_fini(self);
    }

    pub fn newEntity(self: *zflecs.world_t, name: ?[:0]const u8) public.EntityId {
        return zflecs.new_entity(self, name orelse "");
    }

    pub fn newEntities(self: *zflecs.world_t, allocator: std.mem.Allocator, count: usize) ?[]public.EntityId {
        const entitites = zflecs.bulk_new_w_id(self, 0, @intCast(count));
        const result = allocator.alloc(public.EntityId, count) catch return null;
        @memcpy(result, entitites);
        return result;
    }

    pub fn setId(self: *zflecs.world_t, entity: public.EntityId, id: cetech1.strid.StrId32, size: usize, ptr: ?*const anyopaque) public.EntityId {
        return zflecs.set_id(self, entity, _id_map.find(id).?, size, ptr);
    }

    pub fn progress(self: *zflecs.world_t, dt: f32) bool {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "ECS: World progress");
        defer zone_ctx.End();
        return zflecs.progress(self, dt);
    }

    pub fn createQuery(self: *zflecs.world_t, query: []const public.QueryTerm) !public.Query {
        var qd = zflecs.query_desc_t{};

        for (query, 0..) |term, idx| {
            qd.filter.terms[idx] = .{
                .id = _id_map.find(term.id) orelse continue,
                .inout = @enumFromInt(@intFromEnum(term.inout)),
                .oper = @enumFromInt(@intFromEnum(term.oper)),
            };
        }

        const q = try zflecs.query_init(self, &qd);
        return .{
            .ptr = q,
            .vtable = &query_vt,
            .world = WorldImpl.init(self),
        };
    }
};
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

var _iter_pool: cetech1.mem.PoolWithLock(zflecs.iter_t) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    FlecsAllocator.allocator = allocator;

    _world_data_lck = .{};

    _world_data = WorldSet.init(allocator);
    try _world_data.ensureTotalCapacity(128);

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
    if (builtin.mode == .Debug) {
        //_zflecs_os_impl.log_level_ = 0;
    }
    _zflecs_os_impl.log_ = api_log;

    zflecs.os_set_api(@ptrCast(&_zflecs_os_impl));

    _iter_pool = cetech1.mem.PoolWithLock(zflecs.iter_t).init(allocator);

    try initIds();
}

pub fn deinit() void {
    for (_world_data.keys()) |value| {
        destroyWorld(WorldImpl.init(value));
    }
    _iter_pool.deinit();
    deInitIds();
    _world_data.deinit();
}

pub fn registerToApi() !void {
    _ = @alignOf(public.EntityLogicComponent);
    _ = @alignOf(public.EntityLogicComponentInstance);

    try apidb.api.setZigApi(module_name, public.EcsAPI, &api);

    try apidb.api.implOrRemove(module_name, public.ComponentI, &logic_c, true);
    try apidb.api.implOrRemove(module_name, public.ComponentI, &logic_instance_c, true);

    try apidb.api.implOrRemove(module_name, public.SystemI, &init_logic_system_i, true);
    try apidb.api.implOrRemove(module_name, public.SystemI, &tick_logic_system_i, true);
}

pub var api = cetech1.ecs.EcsAPI{
    .createWorld = createWorld,
    .destroyWorld = destroyWorld,
    .toIter = toIter,
};

const world_vt = public.World.VTable{
    .newEntity = @ptrCast(&WorldImpl.newEntity),
    .newEntities = @ptrCast(&WorldImpl.newEntities),
    .setId = @ptrCast(&WorldImpl.setId),
    .progress = @ptrCast(&WorldImpl.progress),
    .createQuery = @ptrCast(&WorldImpl.createQuery),
};

const iter_vt = public.Iter.VTable.implement(struct {
    pub fn getWorld(self: *anyopaque) public.World {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return WorldImpl.init(it.world);
    }

    pub fn count(self: *anyopaque) usize {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return it.count();
    }

    pub fn field(self: *anyopaque, size: usize, index: i32) ?*anyopaque {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.field_w_size(it, size, index);
    }

    pub fn isSelf(self: *anyopaque, index: i32) bool {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.field_is_self(it, index);
    }

    pub fn destroy(self: *anyopaque) void {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        _iter_pool.destroy(it);
    }

    pub fn getParam(self: *anyopaque) ?*anyopaque {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return it.param;
    }

    pub fn entites(self: *anyopaque) []public.EntityId {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return it.entities();
    }

    pub fn nextTable(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.query_next_table(it);
    }

    pub fn changed(self: *anyopaque) bool {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return ecs_query_changed(null, it);
    }

    pub fn skip(self: *anyopaque) void {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        return zflecs.query_skip(it);
    }

    pub fn populate(self: *anyopaque) void {
        const it: *zflecs.iter_t = @alignCast(@ptrCast(self));
        _ = zflecs.query_populate(it, true);
    }
});
extern fn ecs_query_changed(query: ?*zflecs.query_t, iter: *const zflecs.iter_t) bool;

const query_vt = public.Query.VTable.implement(struct {
    pub fn destroy(self: *anyopaque) void {
        zflecs.query_fini(@alignCast(@ptrCast(self)));
    }

    pub fn iter(self: *anyopaque, world: public.World) !public.Iter {
        const q: *zflecs.query_t = @alignCast(@ptrCast(self));

        const it = zflecs.query_iter(@ptrCast(world.ptr), q);

        const new_it = try _iter_pool.create();
        new_it.* = it;

        return .{ .ptr = new_it, .vtable = &iter_vt };
    }

    pub fn next(self: *anyopaque, iter_: public.Iter) bool {
        _ = self;
        const it: *zflecs.iter_t = @alignCast(@ptrCast(iter_.ptr));
        return zflecs.query_next(it);
    }
});

pub fn progressAll(dt: f32) !void {
    // TODO: Problem with parallel
    for (_world_data.keys()) |world| {
        _ = WorldImpl.progress(world, dt);
    }
}

extern fn ecs_mini() *zflecs.world_t;
extern fn FlecsPipelineImport(w: *zflecs.world_t) void;

var _fake_world: *zflecs.world_t = undefined;
var _id_map: IdMap = undefined;

pub fn deInitIds() void {
    _ = ecs_fini(_fake_world);
    _id_map.deinit();
}
pub fn initIds() !void {
    _fake_world = ecs_mini();

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
    try _id_map.map(public.DefaultChildComponent, EcsDefaultChildComponent);
    try _id_map.map(public.PredEq, EcsPredEq);
    try _id_map.map(public.PredMatch, EcsPredMatch);
    try _id_map.map(public.PredLookup, EcsPredLookup);
    try _id_map.map(public.Tag, EcsTag);
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
    try _id_map.map(public.UnSet, EcsUnSet);
    try _id_map.map(public.Monitor, EcsMonitor);
    try _id_map.map(public.OnTableCreate, EcsOnTableCreate);
    try _id_map.map(public.OnTableDelete, EcsOnTableDelete);
    try _id_map.map(public.OnTableEmpty, EcsOnTableEmpty);
    try _id_map.map(public.OnTableFill, EcsOnTableFill);

    // Register components
    var it = apidb.api.getFirstImpl(public.ComponentI);
    while (it) |node| : (it = node.next) {
        const iface = cetech1.apidb.ApiDbAPI.toInterface(public.ComponentI, node);

        if (iface.size != 0) {
            const component_id = zflecs.component_init(_fake_world, &.{
                .entity = zflecs.entity_init(_fake_world, &.{
                    .use_low_id = true,
                    .name = iface.name,
                    .symbol = iface.name,
                }),
                .type = .{
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

            try _id_map.map(iface.id, component_id);
        } else {
            const component_id = zflecs.entity_init(_fake_world, &.{
                .name = iface.name,
            });
            try _id_map.map(iface.id, component_id);
        }
    }
}

pub fn createWorld() !public.World {
    const world = ecs_mini();
    FlecsPipelineImport(world);

    //zflecs.set_task_threads(world, @intCast(task.api.getThreadNum()));

    _world_data_lck.lock();
    defer _world_data_lck.unlock();

    const wd = WorldImpl.init(world);
    try _world_data.put(world, {});

    // Register components
    var it = apidb.api.getFirstImpl(public.ComponentI);
    while (it) |node| : (it = node.next) {
        const iface = cetech1.apidb.ApiDbAPI.toInterface(public.ComponentI, node);

        if (iface.size != 0) {
            const component_id = zflecs.component_init(world, &.{
                .entity = zflecs.entity_init(world, &.{
                    .use_low_id = true,
                    .id = _id_map.find(iface.id).?,
                    .name = iface.name,
                    .symbol = iface.name,
                }),
                .type = .{
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
    it = apidb.api.getFirstImpl(public.SystemI);
    while (it) |node| : (it = node.next) {
        const iface = cetech1.apidb.ApiDbAPI.toInterface(public.SystemI, node);

        var system_desc = zflecs.system_desc_t{
            .multi_threaded = iface.multi_threaded,
            .callback = @ptrCast(iface.update),
            .run = @ptrCast(iface.iterate),
        };

        system_desc.query.filter.instanced = iface.instanced;

        for (iface.query, 0..) |term, idx| {
            system_desc.query.filter.terms[idx] = .{
                .id = _id_map.find(term.id) orelse continue,
                .inout = @enumFromInt(@intFromEnum(term.inout)),
                .oper = @enumFromInt(@intFromEnum(term.oper)),
                .src = std.mem.bytesToValue(zflecs.term_id_t, std.mem.asBytes(&term.src)),
                .first = std.mem.bytesToValue(zflecs.term_id_t, std.mem.asBytes(&term.first)),
                .second = std.mem.bytesToValue(zflecs.term_id_t, std.mem.asBytes(&term.second)),
            };
        }

        zflecs.SYSTEM(world, iface.name, _id_map.find(iface.phase).?, &system_desc);
    }

    // Notify
    var onworld_it = apidb.api.getFirstImpl(public.OnWorldI);
    while (onworld_it) |node| : (onworld_it = node.next) {
        const iface = cetech1.apidb.ApiDbAPI.toInterface(public.OnWorldI, node);
        try iface.onCreate(wd);
    }

    return wd;
}

pub fn destroyWorld(world: public.World) void {
    var onworld_it = apidb.api.getFirstImpl(public.OnWorldI);
    while (onworld_it) |node| : (onworld_it = node.next) {
        const iface = cetech1.apidb.ApiDbAPI.toInterface(public.OnWorldI, node);
        iface.onDestroy(world) catch undefined;
    }

    _ = ecs_fini(@ptrCast(world.ptr));

    _world_data_lck.lock();
    defer _world_data_lck.unlock();
    _ = _world_data.swapRemove(@ptrCast(world.ptr));
}

fn toIter(iter: *public.IterO) public.Iter {
    return public.Iter{
        .ptr = iter,
        .vtable = &iter_vt,
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

const init_logic_system_i = public.SystemI.implement(
    .{
        .name = "init entity logic component",
        .multi_threaded = false,
        .phase = public.OnLoad,
        .query = &.{
            .{ .id = public.id(public.EntityLogicComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = public.id(public.EntityLogicComponent), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *public.IterO) !void {
            const it = toIter(iter);

            const alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(alloc);

            const world = it.getWorld();
            const ents = it.entities();
            const render_component = it.field(public.EntityLogicComponent, 2).?;

            const instances = try graph_private.api.createInstances(alloc, assetdb_private.getDb(), render_component[0].graph, render_component.len);
            defer alloc.free(instances);
            try graph_private.api.buildInstances(instances);
            try graph_private.api.executeNode(alloc, instances, cetech1.graphvm.EVENT_INIT_NODE_TYPE);

            for (0..it.count()) |idx| {
                _ = world.setId(public.EntityLogicComponentInstance, ents[idx], &public.EntityLogicComponentInstance{ .graph_container = instances[idx] });

                try graph_private.api.setInstanceContext(instances[idx], public.ECS_WORLD_CONTEXT, world.ptr);
                try graph_private.api.setInstanceContext(instances[idx], public.ECS_ENTITY_CONTEXT, @ptrFromInt(ents[idx]));
            }
        }
    },
);

pub fn toContanerSlice(from: anytype) []const cetech1.graphvm.GraphInstance {
    var containers: []const cetech1.graphvm.GraphInstance = undefined;
    containers.ptr = @alignCast(@ptrCast(from.ptr));
    containers.len = from.len;
    return containers;
}

const tick_logic_system_i = public.SystemI.implement(
    .{
        .name = "tick logic component",
        .multi_threaded = false,
        .phase = public.OnLoad,
        .query = &.{
            .{ .id = public.id(public.EntityLogicComponentInstance), .inout = .In },
            .{ .id = public.id(public.EntityLogicComponent), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *public.IterO) !void {
            const it = toIter(iter);

            const alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(alloc);

            const render_component = it.field(public.EntityLogicComponentInstance, 1).?;
            try graph_private.api.executeNode(alloc, toContanerSlice(render_component), cetech1.graphvm.EVENT_TICK_NODE_TYPE);
        }
    },
);

const logic_c = public.ComponentI.implement(public.EntityLogicComponent, struct {});

const logic_instance_c = public.ComponentI.implement(public.EntityLogicComponentInstance, struct {
    pub fn onDestroy(components: []public.EntityLogicComponentInstance) !void {
        for (components) |c| {
            if (c.graph_container.isValid()) {
                graph_private.api.destroyInstance(c.graph_container);
            }
        }
    }

    pub fn onMove(dsts: []public.EntityLogicComponentInstance, srcs: []public.EntityLogicComponentInstance) !void {
        for (dsts, srcs) |*dst, *src| {
            dst.* = src.*;

            // Prevent double delete
            src.graph_container = .{};
        }
    }

    pub fn onRemove(iter: *public.IterO) !void {
        var it = toIter(iter);
        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);
        const components = it.field(public.EntityLogicComponentInstance, 1).?;
        for (components) |component| {
            // TODO: real multi call
            try graph_private.api.executeNode(alloc, &.{component.graph_container}, cetech1.graphvm.EVENT_SHUTDOWN_NODE_TYPE);
        }
    }
});
