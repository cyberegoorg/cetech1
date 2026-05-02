const std = @import("std");
const builtin = @import("builtin");
const cetech1 = @import("cetech1.zig");
const zm = cetech1.math.zm;
const coreui = cetech1.coreui;
const math = cetech1.math;
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const gpu_dd = cetech1.gpu_dd;

const apidb = cetech1.apidb;
const log = std.log.scoped(.ecs);

pub const Id = u64;
pub const EntityId = Id;
pub const ComponentId = EntityId;
pub const SystemId = EntityId;

pub const IdStrId = cetech1.StrId64;

pub const ECS_WORLD_CONTEXT = cetech1.strId32("ecs_world_context"); // TODO: This is bad as context because it can change. we need something like exxecuteargs.
pub const ECS_ENTITY_CONTEXT = cetech1.strId32("ecs_entity_context");

pub const PinTypes = struct {
    pub const Entity = cetech1.strId32("entity");
    pub const World = cetech1.strId32("world");
};

pub const Wildcard: IdStrId = .fromStr("Wildcard");
pub const Any: IdStrId = .fromStr("Any");
pub const Transitive: IdStrId = .fromStr("Transitive");
pub const Reflexive: IdStrId = .fromStr("Reflexive");
pub const Final: IdStrId = .fromStr("Final");
pub const DontInherit: IdStrId = .fromStr("DontInherit");
pub const Exclusive: IdStrId = .fromStr("Exclusive");
pub const Acyclic: IdStrId = .fromStr("Acyclic");
pub const Traversable: IdStrId = .fromStr("Traversable");
pub const Symmetric: IdStrId = .fromStr("Symmetric");
pub const With: IdStrId = .fromStr("With");
pub const OneOf: IdStrId = .fromStr("OneOf");
pub const IsA: IdStrId = .fromStr("IsA");
pub const ChildOf: IdStrId = .fromStr("ChildOf");
pub const DependsOn: IdStrId = .fromStr("DependsOn");
pub const SlotOf: IdStrId = .fromStr("SlotOf");
pub const OnDelete: IdStrId = .fromStr("OnDelete");
pub const OnDeleteTarget: IdStrId = .fromStr("OnDeleteTarget");
pub const Remove: IdStrId = .fromStr("Remove");
pub const Delete: IdStrId = .fromStr("Delete");
pub const Panic: IdStrId = .fromStr("Panic");
pub const PredEq: IdStrId = .fromStr("PredEq");
pub const PredMatch: IdStrId = .fromStr("PredMatch");
pub const PredLookup: IdStrId = .fromStr("PredLookup");
pub const Singleton: IdStrId = .fromStr("Singleton");
pub const DontFragment: IdStrId = .fromStr("DontFragment");
pub const Alias: IdStrId = .fromStr("Alias");
pub const Prefab: IdStrId = .fromStr("Prefab");
pub const Disabled: IdStrId = .fromStr("Disabled");
pub const OnStart: IdStrId = .fromStr("OnStart");
pub const PreFrame: IdStrId = .fromStr("PreFrame");
pub const OnLoad: IdStrId = .fromStr("OnLoad");
pub const PostLoad: IdStrId = .fromStr("PostLoad");
pub const PreUpdate: IdStrId = .fromStr("PreUpdate");
pub const OnUpdate: IdStrId = .fromStr("OnUpdate");
pub const OnValidate: IdStrId = .fromStr("OnValidate");
pub const PostUpdate: IdStrId = .fromStr("PostUpdate");
pub const PreStore: IdStrId = .fromStr("PreStore");
pub const OnStore: IdStrId = .fromStr("OnStore");
pub const PostFrame: IdStrId = .fromStr("PostFrame");
pub const Phase: IdStrId = .fromStr("Phase");
pub const OnAdd: IdStrId = .fromStr("OnAdd");
pub const OnRemove: IdStrId = .fromStr("OnRemove");
pub const OnSet: IdStrId = .fromStr("OnSet");
pub const Monitor: IdStrId = .fromStr("Monitor");
pub const OnTableCreate: IdStrId = .fromStr("OnTableCreate");
pub const OnTableDelete: IdStrId = .fromStr("OnTableDelete");
pub const OnTableEmpty: IdStrId = .fromStr("OnTableEmpty");
pub const OnTableFill: IdStrId = .fromStr("OnTableFill");
pub const Parent: IdStrId = .fromStr("Parent");

// TODO: as strid
pub const Self_ = 1 << 63;
pub const Up: u64 = 1 << 62;
pub const Trav = 1 << 61;
pub const Cascade: u64 = 1 << 60;
pub const Desc = 1 << 59;
pub const IsVariable = 1 << 58;
pub const IsEntity = 1 << 57;
pub const IsName = 1 << 56;
pub const TraverseFlags = Self_ | Up | Trav | Cascade | Desc;
pub const TermRefFlags = TraverseFlags | IsVariable | IsEntity | IsName;

pub const ChildrenStorageType = enum(u8) {
    ChildOf = 0,
    Parent,
};

pub const EntityCdb = cdb.CdbTypeDecl(
    "ct_entity",
    enum(u32) {
        Name = 0,
        Storage,
        Components,
        Childrens,
    },
    struct {},
);

pub const InOutKind = enum(i32) {
    InOutDefault = 0,
    InOutNone,
    InOutFilter,
    InOut,
    In,
    Out,
};

pub const OperatorKind = enum(i32) {
    And = 0,
    Or,
    Not,
    Optional,
    AndFrom,
    OrFrom,
    NotFrom,
};

pub const TermId = extern struct {
    id: EntityId = 0,
    name: ?[*:0]const u8 = null,
    trav: EntityId = 0,
};

pub const QueryTerm = struct {
    id: IdStrId,
    inout: InOutKind = .InOutDefault,
    oper: OperatorKind = .And,
    src: TermId = .{},
    first: TermId = .{},
    second: TermId = .{},
    cache_kind: QueryCacheKind = .QueryCacheDefault,
};

pub const IterO = opaque {};

pub const ComponentCategoryI = struct {
    pub const c_name = "ct_ecs_component_category_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8 = undefined,
    order: f32 = std.math.inf(f32),

    pub fn implement(args: ComponentCategoryI) ComponentCategoryI {
        return ComponentCategoryI{
            .name = args.name,
            .order = args.order,
        };
    }
};

pub const EntityDecs = struct {
    id: ?EntityId = null,
    name: ?[:0]const u8 = null,
    add: ?[]const cetech1.StrId32 = null,
};

const OnInstantiateType = enum(u8) {
    Override = 0,
    Inherit,
    DontInherit,
};

pub const ComponentI = struct {
    const Self = @This();
    pub const c_name = "ct_ecs_component_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8 = undefined,
    type_name: [:0]const u8 = undefined,
    display_name: [:0]const u8,
    id: IdStrId = undefined,
    size: usize = undefined,
    aligment: usize = undefined,

    default_data: ?[]const u8 = null,

    category: ?[:0]const u8 = null,
    category_order: f32 = 0,

    cdb_type_hash: cdb.TypeHash = .{},

    with: ?[]const IdStrId = null,
    singleton: bool = false,
    on_instantiate: OnInstantiateType = .Override,

    create_manager: ?*const fn (world: *World) anyerror!*anyopaque = null,
    destroy_manager: ?*const fn (world: *World, manager: *anyopaque) void = null,

    on_add: ?*const fn (manager: ?*anyopaque, iter: *Iter) anyerror!void = null,
    on_set: ?*const fn (manager: ?*anyopaque, iter: *Iter) anyerror!void = null,
    on_remove: ?*const fn (manager: ?*anyopaque, iter: *Iter) anyerror!void = null,

    on_create: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    on_destroy: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    on_copy: ?*const fn (dst_ptr: *anyopaque, src_ptr: *const anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    on_move: ?*const fn (dst_ptr: *anyopaque, src_ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,

    from_cdb: ?*const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        data: []u8,
    ) anyerror!void = null,

    debugdraw: ?*const fn (
        gpu_backend: gpu.GpuBackend,
        dd: gpu_dd.Encoder,
        world: *World,
        entites: []const EntityId,
        data: []const u8,
        size: math.Vec2f,
    ) anyerror!void = null,

    pub fn implement(comptime T: type, args: ComponentI, comptime Hooks: type) Self {
        // Must be extern for C ABI compatibility.
        std.debug.assert(@typeInfo(T).@"struct".layout == .@"extern");

        return Self{
            .name = nameFromType(T),
            .type_name = @typeName(T),
            .display_name = args.display_name,
            .id = id(T),
            .cdb_type_hash = args.cdb_type_hash,

            .size = @sizeOf(T),
            .aligment = @alignOf(T),

            .default_data = args.default_data,

            .category = args.category,
            .category_order = args.category_order,
            .with = args.with,
            .singleton = args.singleton,
            .on_instantiate = args.on_instantiate,

            .from_cdb = if (std.meta.hasFn(Hooks, "fromCdb")) Hooks.fromCdb else null,
            .debugdraw = if (std.meta.hasFn(Hooks, "debugdraw")) Hooks.debugdraw else null,

            .on_add = if (std.meta.hasFn(Hooks, "onAdd")) Hooks.onAdd else null,
            .on_set = if (std.meta.hasFn(Hooks, "onSet")) Hooks.onSet else null,
            .on_remove = if (std.meta.hasFn(Hooks, "onRemove")) Hooks.onRemove else null,

            .create_manager = if (std.meta.hasFn(Hooks, "createManager")) Hooks.createManager else null,
            .destroy_manager = if (std.meta.hasFn(Hooks, "destroyManager")) Hooks.destroyManager else null,

            .on_create = if (std.meta.hasFn(Hooks, "onCreate")) struct {
                fn f(ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void {
                    _ = type_info;
                    var tptr: []T = undefined;
                    tptr.len = @intCast(count);
                    tptr.ptr = @ptrCast(@alignCast(ptr));

                    Hooks.onCreate(tptr) catch |err| {
                        log.err("onCreate error {}", .{err});
                    };
                }
            }.f else null,

            .on_destroy = if (std.meta.hasFn(Hooks, "onDestroy")) struct {
                fn f(ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void {
                    _ = type_info;
                    var tptr: []T = undefined;
                    tptr.len = @intCast(count);
                    tptr.ptr = @ptrCast(@alignCast(ptr));

                    Hooks.onDestroy(tptr) catch |err| {
                        log.err("onDestroy error {}", .{err});
                    };
                }
            }.f else null,

            .on_copy = if (std.meta.hasFn(Hooks, "onCopy")) struct {
                fn f(dst_ptr: *anyopaque, src_ptr: *const anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void {
                    _ = type_info;

                    var dst_tptr: []T = undefined;
                    dst_tptr.len = @intCast(count);
                    dst_tptr.ptr = @ptrCast(@alignCast(dst_ptr));

                    var src_tptr: []const T = undefined;
                    src_tptr.len = @intCast(count);
                    src_tptr.ptr = @ptrCast(@alignCast(src_ptr));

                    Hooks.onCopy(dst_tptr, src_tptr) catch |err| {
                        log.err("OnCopy error {}", .{err});
                    };
                }
            }.f else null,

            .on_move = if (std.meta.hasFn(Hooks, "onMove")) struct {
                fn f(dst_ptr: *anyopaque, src_ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void {
                    _ = type_info;

                    var dst_tptr: []T = undefined;
                    dst_tptr.len = @intCast(count);
                    dst_tptr.ptr = @ptrCast(@alignCast(dst_ptr));

                    var src_tptr: []T = undefined;
                    src_tptr.len = @intCast(count);
                    src_tptr.ptr = @ptrCast(@alignCast(src_ptr));

                    Hooks.onMove(dst_tptr, src_tptr) catch |err| {
                        log.err("onMove error {}", .{err});
                    };
                }
            }.f else null,
        };
    }
};

pub const SystemI = struct {
    pub const c_name = "ct_ecs_system_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8,
    phase: IdStrId,
    query: []const QueryTerm,
    multi_threaded: bool = false,
    immediate: bool = false,
    cache_kind: QueryCacheKind = .QueryCacheDefault,

    simulation: bool = false,

    order_by_component: ?IdStrId = null,
    order_by_callback: ?*const fn (e1: EntityId, c1: *const anyopaque, e2: EntityId, c2: *const anyopaque) callconv(.c) i32 = null, // TODO: how without callconv?

    // Call one per tick.
    tick: ?*const fn (world: *World, iter: *Iter, dt: f32) anyerror!void = null,

    // Call for every table.
    iterate: ?*const fn (world: *World, iter: *Iter, dt: f32) anyerror!void = null,

    pub fn implement(args: SystemI, comptime T: type) SystemI {
        return SystemI{
            .name = args.name,
            .phase = args.phase,
            .query = args.query,
            .multi_threaded = args.multi_threaded,
            .immediate = args.immediate,
            .cache_kind = args.cache_kind,
            .simulation = args.simulation,

            .iterate = if (std.meta.hasFn(T, "iterate")) T.iterate else null,
            .tick = if (std.meta.hasFn(T, "tick")) T.tick else null,
            .order_by_callback = if (std.meta.hasFn(T, "orderByCallback")) T.orderByCallback else null,
        };
    }
};

pub const ObserverI = struct {
    pub const c_name = "ct_ecs_observer_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8,
    id: cetech1.StrId32 = undefined,
    query: []const QueryTerm,
    events: []const IdStrId,

    // Call for every table.
    tick: ?*const fn (world: *World, iter: *Iter, dt: f32) anyerror!void = undefined,

    // Call for every table.
    iterate: ?*const fn (world: *World, iter: *Iter, dt: f32) anyerror!void = undefined,

    pub fn implement(args: ObserverI, comptime T: type) ObserverI {
        return ObserverI{
            .name = args.name,
            .id = .fromStr(args.name),
            .query = args.query,
            .events = args.events,

            .iterate = if (std.meta.hasFn(T, "iterate")) T.iterate else null,
            .tick = if (std.meta.hasFn(T, "tick")) T.tick else null,
        };
    }
};

pub const OnWorldI = struct {
    pub const c_name = "ct_ecs_on_world_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    on_create: *const fn (world: *World) anyerror!void = undefined,
    on_destroy: *const fn (world: *World) anyerror!void = undefined,

    pub fn implement(comptime T: type) OnWorldI {
        return OnWorldI{
            .on_create = T.onCreate,
            .on_destroy = T.onDestroy,
        };
    }
};

pub const QueryCacheKind = enum(i32) {
    QueryCacheDefault,
    QueryCacheAuto,
    QueryCacheAll,
    QueryCacheNone,
};

pub const QueryCount = struct {
    results: i32,
    entities: i32,
    tables: i32,
    empty_tables: i32,
};

pub const Query = opaque {
    pub inline fn destroy(self: *Query) void {
        query_api.destroy(self);
    }

    pub inline fn count(self: *Query) QueryCount {
        return query_api.count(self);
    }

    pub inline fn iter(self: *Query) !Iter {
        return query_api.iter(self);
    }

    pub inline fn next(self: *Query, it: *Iter) bool {
        return query_api.next(self, it);
    }
};

pub const QueryDesc = struct {
    query: []const QueryTerm,
    order_by_component: ?IdStrId = null,
    order_by_callback: ?*const fn (e1: EntityId, c1: *const anyopaque, e2: EntityId, c2: *const anyopaque) callconv(.c) i32 = null, // TODO: how without callconv?
};

pub const World = opaque {
    pub inline fn newEntity(self: *World, desc: EntityDecs) EntityId {
        return world_api.new_entity(self, desc);
    }

    pub inline fn newEntities(self: *World, allocator: std.mem.Allocator, eid: EntityId, count: usize) ?[]EntityId {
        return world_api.new_entities(self, allocator, eid, count);
    }

    pub inline fn destroyEntities(self: *World, ents: []const EntityId) void {
        return world_api.destroy_entities(self, ents);
    }

    pub inline fn setComponent(self: *World, comptime T: type, entity: EntityId, ptr: ?*const T) EntityId {
        return world_api.set_component(self, entity, id(T), @sizeOf(T), ptr);
    }

    pub inline fn setComponentRaw(self: *World, entity: EntityId, cid: IdStrId, size: usize, ptr: ?*const anyopaque) EntityId {
        return world_api.set_component(self, entity, cid, size, ptr);
    }

    pub inline fn getMutComponent(self: *World, comptime T: type, entity: EntityId) ?*T {
        const ptr = world_api.get_mut_component(self, entity, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponent(self: *World, comptime T: type, entity: EntityId) ?*const T {
        const ptr = world_api.get_component(self, entity, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponentRaw(self: *World, comp_id: IdStrId, entity: EntityId) ?*const anyopaque {
        const ptr = world_api.get_component(self, entity, comp_id);
        return ptr;
    }

    pub inline fn setSingletonComponent(self: *World, comptime T: type, ptr: ?*const T) void {
        world_api.set_singleton_component(self, id(T), @sizeOf(T), ptr);
    }

    pub inline fn getSingletonComponent(self: *World, comptime T: type) ?*const T {
        const ptr = world_api.get_singleton_component(self, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponentManager(self: *World, comptime ComponentT: type, comptime ManagerT: type) ?*ManagerT {
        const ptr = world_api.get_component_manager(self, id(ComponentT));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponentManagerRaw(self: *World, component_id: IdStrId) ?*anyopaque {
        return world_api.get_component_manager(self, component_id);
    }

    pub inline fn removeComponent(self: *World, comptime T: type, entity: EntityId) void {
        return world_api.remove_component(self, entity, id(T));
    }

    pub inline fn modified(self: *World, entity: EntityId, comptime T: type) void {
        return world_api.modified(self, entity, id(T));
    }

    pub inline fn modifiedRaw(self: *World, entity: EntityId, component_id: IdStrId) void {
        return world_api.modified(self, entity, component_id);
    }

    pub inline fn parent(self: *World, entity: EntityId) ?EntityId {
        return world_api.parent(self, entity);
    }

    pub inline fn children(self: *World, entity: EntityId) Iter {
        return world_api.children(self, entity);
    }

    pub inline fn progress(self: *World, dt: f32) bool {
        return world_api.progress(self, dt);
    }

    pub inline fn createQuery(self: *World, query: QueryDesc) !*Query {
        return world_api.create_query(self, query);
    }

    pub inline fn deferBegin(self: *World) bool {
        return world_api.defer_begin(self);
    }

    pub inline fn deferEnd(self: *World) bool {
        return world_api.defer_end(self);
    }

    pub inline fn deferResume(self: *World) void {
        world_api.defer_resume(self);
    }

    pub inline fn deferSuspend(self: *World) void {
        world_api.defer_suspend(self);
    }

    pub fn isRemoteDebugActive(self: *World) bool {
        return world_api.is_remote_debug_active(self);
    }

    pub fn setRemoteDebugActive(self: *World, active: bool) ?u16 {
        return world_api.set_remote_debug_active(self, active);
    }

    pub fn setSimulate(self: *World, simulate: bool) void {
        world_api.set_simulate(self, simulate);
    }

    pub fn isSimulate(self: *World) bool {
        return world_api.is_simulate(self);
    }

    pub fn enableObserver(self: *World, observer_id: cetech1.StrId32, enable: bool) void {
        return world_api.enable_observer(self, observer_id, enable);
    }

    pub fn doStep(self: *World) void {
        return world_api.do_step(self);
    }

    pub fn clear(self: *World) void {
        return world_api.clear(self);
    }

    pub fn debuguiMenuItems(self: *World, allocator: std.mem.Allocator) void {
        return world_api.debugui_menu_items(self, allocator);
    }

    pub fn uiRemoteDebugMenuItems(self: *World, allocator: std.mem.Allocator, port: ?u16) ?u16 {
        return world_api.ui_remote_debug_menu_items(self, allocator, port);
    }

    pub fn findEntityByCdbObj(self: *World, ent_obj: cdb.ObjId) !?EntityId {
        return world_api.find_entity_by_cdb_obj(self, ent_obj);
    }
};

pub const Iter = struct {
    pub inline fn getWorld(self: *Iter) *World {
        return self.vtable.get_world(&self.data);
    }

    pub inline fn count(self: *Iter) usize {
        return self.vtable.count(&self.data);
    }

    pub inline fn field(self: *Iter, comptime T: type, index: i8) ?[]T {
        if (self.vtable.field(&self.data, @sizeOf(T), index)) |anyptr| {
            const ptr = @as([*]T, @ptrCast(@alignCast(anyptr)));
            return ptr[0..self.count()];
        }
        return null;
    }

    pub inline fn fieldRaw(self: *Iter, size: usize, ptr_align: usize, index: i8) ?[]u8 {
        _ = ptr_align;
        if (self.vtable.field(&self.data, size, index)) |anyptr| {
            const ptr = @as([*]u8, @ptrCast(@alignCast(anyptr)));
            return ptr[0 .. self.count() * size];
        }
        return null;
    }

    pub inline fn isSelf(self: *Iter, index: i8) bool {
        return self.vtable.is_self(&self.data, index);
    }

    pub inline fn getParam(self: *Iter, comptime T: type) ?*T {
        const p: *T = @ptrCast(@alignCast(self.vtable.get_param(&self.data) orelse return null));
        return p;
    }

    pub inline fn entities(self: *Iter) []const EntityId {
        return self.vtable.entities(&self.data);
    }

    pub inline fn changed(self: *Iter) bool {
        return self.vtable.changed(&self.data);
    }

    pub inline fn skip(self: *Iter) void {
        return self.vtable.skip(&self.data);
    }

    pub inline fn next(self: *Iter) bool {
        return self.vtable.next(&self.data);
    }

    pub inline fn nextChildren(self: *Iter) bool {
        return self.vtable.next_children(&self.data);
    }

    pub inline fn getSystem(self: *Iter) *const SystemI {
        return self.vtable.get_system();
    }

    data: [360]u8, // TODO: SHIT
    vtable: *const VTable,

    pub const VTable = struct {
        get_world: *const fn (self: *anyopaque) *World,
        count: *const fn (self: *anyopaque) usize,
        field: *const fn (self: *anyopaque, size: usize, index: i8) ?*anyopaque,
        get_param: *const fn (self: *anyopaque) ?*anyopaque,
        entities: *const fn (self: *anyopaque) []const EntityId,
        changed: *const fn (self: *anyopaque) bool,
        skip: *const fn (self: *anyopaque) void,
        is_self: *const fn (self: *anyopaque, index: i8) bool,
        next: *const fn (self: *anyopaque) bool,
        next_children: *const fn (self: *anyopaque) bool,
        get_system: *const fn (self: *anyopaque) *const SystemI,

        pub fn implement(comptime T: type) VTable {
            return VTable{
                .get_world = T.getWorld,
                .count = T.count,
                .field = T.field,
                .get_param = T.getParam,
                .entities = T.entites,
                .changed = T.changed,
                .skip = T.skip,
                .is_self = T.isSelf,
                .next = T.next,
                .next_children = T.nextChildren,
                .get_system = T.getSystem,
            };
        }
    };
};

pub fn id(comptime T: type) IdStrId {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
    const name = name_iter.first();
    return .fromStr(name);
}

pub fn createWorld() anyerror!*World {
    return api.createWorld();
}
pub fn destroyWorld(world: *World) void {
    return api.destroyWorld(world);
}
pub fn findComponentIById(name: IdStrId) ?*const ComponentI {
    return api.findComponentIById(name);
}
pub fn findComponentIByCdbHash(cdb_hash: cdb.TypeHash) ?*const ComponentI {
    return api.findComponentIByCdbHash(cdb_hash);
}
pub fn findCategoryById(name: cetech1.StrId32) ?*const ComponentCategoryI {
    return api.findCategoryById(name);
}
pub fn spawnManyFromCDB(allocator: std.mem.Allocator, world: *World, obj: cdb.ObjId, count: usize) anyerror![]EntityId {
    return api.spawnManyFromCdb(allocator, world, obj, count);
}

pub const EcsAPI = struct {
    createWorld: *const fn () anyerror!*World,
    destroyWorld: *const fn (world: *World) void,
    findComponentIById: *const fn (name: IdStrId) ?*const ComponentI,
    findComponentIByCdbHash: *const fn (cdb_hash: cdb.TypeHash) ?*const ComponentI,
    findCategoryById: *const fn (name: cetech1.StrId32) ?*const ComponentCategoryI,
    spawnManyFromCdb: *const fn (allocator: std.mem.Allocator, world: *World, obj: cdb.ObjId, count: usize) anyerror![]EntityId,
};

pub const EcsWorldAPI = struct {
    new_entity: *const fn (world: *World, desc: EntityDecs) EntityId,
    new_entities: *const fn (world: *World, allocator: std.mem.Allocator, id: EntityId, count: usize) ?[]EntityId,
    destroy_entities: *const fn (self: *World, ents: []const EntityId) void,
    set_component: *const fn (world: *World, entity: EntityId, id: IdStrId, size: usize, ptr: ?*const anyopaque) EntityId,
    get_mut_component: *const fn (world: *World, entity: EntityId, id: IdStrId) ?*anyopaque,
    get_component: *const fn (world: *World, entity: EntityId, id: IdStrId) ?*const anyopaque,
    set_singleton_component: *const fn (world: *World, id: IdStrId, size: usize, ptr: ?*const anyopaque) void,
    get_singleton_component: *const fn (world: *World, id: IdStrId) ?*const anyopaque,
    remove_component: *const fn (world: *World, entity: EntityId, id: IdStrId) void,
    get_component_manager: *const fn (world: *World, id: IdStrId) ?*anyopaque,
    parent: *const fn (world: *World, entity: EntityId) ?EntityId,
    children: *const fn (world: *World, entity: EntityId) Iter,
    create_query: *const fn (world: *World, query: QueryDesc) anyerror!*Query,
    modified: *const fn (world: *World, entity: EntityId, id: IdStrId) void,
    progress: *const fn (world: *World, dt: f32) bool,
    defer_begin: *const fn (world: *World) bool,
    defer_end: *const fn (world: *World) bool,
    defer_suspend: *const fn (world: *World) void,
    defer_resume: *const fn (world: *World) void,
    is_remote_debug_active: *const fn (world: *World) bool,
    set_remote_debug_active: *const fn (world: *World, active: bool) ?u16,
    set_simulate: *const fn (world: *World, simulate: bool) void,
    is_simulate: *const fn (world: *World) bool,
    do_step: *const fn (world: *World) void,
    enable_observer: *const fn (world: *World, id: cetech1.StrId32, simulate: bool) void,
    clear: *const fn (world: *World) void,
    find_entity_by_cdb_obj: *const fn (world: *World, ent_obj: cdb.ObjId) anyerror!?EntityId,
    debugui_menu_items: *const fn (world: *World, allocator: std.mem.Allocator) void,
    ui_remote_debug_menu_items: *const fn (world: *World, allocator: std.mem.Allocator, port: ?u16) ?u16,
};

pub const EcsQueryAPI = struct {
    destroy: *const fn (query: *Query) void,
    count: *const fn (query: *Query) QueryCount,
    iter: *const fn (query: *Query) anyerror!Iter,
    next: *const fn (query: *Query, it: *Iter) bool,
};

pub var api: *const EcsAPI = undefined;
pub var world_api: *const EcsWorldAPI = undefined;
pub var query_api: *const EcsQueryAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, EcsAPI).?;
    world_api = apidb.getZigApi(module, EcsWorldAPI).?;
    query_api = apidb.getZigApi(module, EcsQueryAPI).?;
}

fn nameFromType(comptime T: type) [:0]const u8 {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
    const name = name_iter.first();
    const cname = name[0..name.len :0];
    return cname;
}
