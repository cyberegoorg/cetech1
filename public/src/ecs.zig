const std = @import("std");
const builtin = @import("builtin");
const cetech1 = @import("root.zig");
const zm = cetech1.math.zm;
const coreui = cetech1.coreui;
const math = cetech1.math;

const cdb = @import("cdb.zig");
const gpu = @import("gpu.zig");

const log = std.log.scoped(.ecs);

pub const Id = u64;
pub const EntityId = Id;
pub const ComponentId = EntityId;
pub const SystemId = EntityId;

pub const IdStrId = cetech1.StrId64;

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
        ChildrenStorage,
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
    override = 0,
    inherit,
    dont_inherit,
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
    on_instantiate: OnInstantiateType = .override,

    createManager: ?*const fn (world: World) anyerror!*anyopaque = null,
    destroyManager: ?*const fn (world: World, manager: *anyopaque) void = null,

    onAdd: ?*const fn (manager: ?*anyopaque, iter: *Iter) anyerror!void = null,
    onSet: ?*const fn (manager: ?*anyopaque, iter: *Iter) anyerror!void = null,
    onRemove: ?*const fn (manager: ?*anyopaque, iter: *Iter) anyerror!void = null,

    onCreate: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    onDestroy: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    onCopy: ?*const fn (dst_ptr: *anyopaque, src_ptr: *const anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    onMove: ?*const fn (dst_ptr: *anyopaque, src_ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,

    fromCdb: ?*const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        data: []u8,
    ) anyerror!void = null,

    debugdraw: ?*const fn (
        gpu_backend: gpu.GpuBackend,
        dd: gpu.DDEncoder,
        world: World,
        entites: []const EntityId,
        data: []const u8,
        size: math.Vec2f,
    ) anyerror!void = null,

    pub fn implement(comptime T: type, args: ComponentI, comptime Hooks: type) Self {
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

            .fromCdb = if (std.meta.hasFn(Hooks, "fromCdb")) Hooks.fromCdb else null,
            .debugdraw = if (std.meta.hasFn(Hooks, "debugdraw")) Hooks.debugdraw else null,

            .onAdd = if (std.meta.hasFn(Hooks, "onAdd")) Hooks.onAdd else null,
            .onSet = if (std.meta.hasFn(Hooks, "onSet")) Hooks.onSet else null,
            .onRemove = if (std.meta.hasFn(Hooks, "onRemove")) Hooks.onRemove else null,

            .createManager = if (std.meta.hasFn(Hooks, "createManager")) Hooks.createManager else null,
            .destroyManager = if (std.meta.hasFn(Hooks, "destroyManager")) Hooks.destroyManager else null,

            .onCreate = if (std.meta.hasFn(Hooks, "onCreate")) struct {
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

            .onDestroy = if (std.meta.hasFn(Hooks, "onDestroy")) struct {
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

            .onCopy = if (std.meta.hasFn(Hooks, "onCopy")) struct {
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

            .onMove = if (std.meta.hasFn(Hooks, "onMove")) struct {
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

    orderByComponent: ?IdStrId = null,
    orderByCallback: ?*const fn (e1: EntityId, c1: *const anyopaque, e2: EntityId, c2: *const anyopaque) callconv(.c) i32 = null, // TODO: how without callconv?

    // Call one per tick.
    tick: ?*const fn (world: World, iter: *Iter, dt: f32) anyerror!void = null,

    // Call for every table.
    iterate: ?*const fn (world: World, iter: *Iter, dt: f32) anyerror!void = null,

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
            .orderByCallback = if (std.meta.hasFn(T, "orderByCallback")) T.orderByCallback else null,
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
    tick: ?*const fn (world: World, iter: *Iter, dt: f32) anyerror!void = undefined,

    // Call for every table.
    iterate: ?*const fn (world: World, iter: *Iter, dt: f32) anyerror!void = undefined,

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

    onCreate: *const fn (world: World) anyerror!void = undefined,
    onDestroy: *const fn (world: World) anyerror!void = undefined,

    pub fn implement(comptime T: type) OnWorldI {
        if (!std.meta.hasFn(T, "onCreate")) @compileError("implement me");
        if (!std.meta.hasFn(T, "onDestroy")) @compileError("implement me");

        return OnWorldI{
            .onCreate = T.onCreate,
            .onDestroy = T.onDestroy,
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

pub const Query = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn destroy(self: *Query) void {
        self.vtable.destroy(self.ptr);
    }

    pub inline fn count(self: *Query) QueryCount {
        return self.vtable.count(self.ptr);
    }

    pub inline fn iter(self: *Query) !Iter {
        return self.vtable.iter(self.ptr);
    }

    pub inline fn next(self: *Query, it: *Iter) bool {
        return self.vtable.next(self.ptr, it);
    }

    pub const VTable = struct {
        destroy: *const fn (query: *anyopaque) void,
        count: *const fn (query: *anyopaque) QueryCount,
        iter: *const fn (query: *anyopaque) anyerror!Iter,
        next: *const fn (query: *anyopaque, it: *Iter) bool,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");
            if (!std.meta.hasFn(T, "iter")) @compileError("implement me");
            if (!std.meta.hasFn(T, "next")) @compileError("implement me");
            if (!std.meta.hasFn(T, "count")) @compileError("implement me");

            return VTable{
                .destroy = T.destroy,
                .iter = T.iter,
                .next = T.next,
                .count = T.count,
            };
        }
    };
};

pub const QueryDesc = struct {
    query: []const QueryTerm,
    orderByComponent: ?IdStrId = null,
    orderByCallback: ?*const fn (e1: EntityId, c1: *const anyopaque, e2: EntityId, c2: *const anyopaque) callconv(.c) i32 = null, // TODO: how without callconv?
};

pub const World = struct {
    pub inline fn newEntity(self: World, desc: EntityDecs) EntityId {
        return self.vtable.newEntity(self.ptr, desc);
    }

    pub inline fn newEntities(self: World, allocator: std.mem.Allocator, eid: EntityId, count: usize) ?[]EntityId {
        return self.vtable.newEntities(self.ptr, allocator, eid, count);
    }

    pub inline fn destroyEntities(self: World, ents: []const EntityId) void {
        return self.vtable.destroyEntities(self.ptr, ents);
    }

    pub inline fn setComponent(self: World, comptime T: type, entity: EntityId, ptr: ?*const T) EntityId {
        return self.vtable.setComponent(self.ptr, entity, id(T), @sizeOf(T), ptr);
    }

    pub inline fn setComponentRaw(self: World, entity: EntityId, cid: IdStrId, size: usize, ptr: ?*const anyopaque) EntityId {
        return self.vtable.setComponent(self.ptr, entity, cid, size, ptr);
    }

    pub inline fn getMutComponent(self: World, comptime T: type, entity: EntityId) ?*T {
        const ptr = self.vtable.getMutComponent(self.ptr, entity, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponent(self: World, comptime T: type, entity: EntityId) ?*const T {
        const ptr = self.vtable.getComponent(self.ptr, entity, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponentRaw(self: World, comp_id: IdStrId, entity: EntityId) ?*const anyopaque {
        const ptr = self.vtable.getComponent(self.ptr, entity, comp_id);
        return ptr;
    }

    pub inline fn setSingletonComponent(self: World, comptime T: type, ptr: ?*const T) void {
        self.vtable.setSingletonComponent(self.ptr, id(T), @sizeOf(T), ptr);
    }

    pub inline fn getSingletonComponent(self: World, comptime T: type) ?*const T {
        const ptr = self.vtable.getSingletonComponent(self.ptr, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponentManager(self: World, comptime ComponentT: type, comptime ManagerT: type) ?*ManagerT {
        const ptr = self.vtable.getComponentManager(self.ptr, id(ComponentT));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponentManagerRaw(self: World, component_id: IdStrId) ?*anyopaque {
        return self.vtable.getComponentManager(self.ptr, component_id);
    }

    pub inline fn removeComponent(self: World, comptime T: type, entity: EntityId) void {
        return self.vtable.removeComponent(self.ptr, entity, id(T));
    }

    pub inline fn modified(self: World, entity: EntityId, comptime T: type) void {
        return self.vtable.modified(self.ptr, entity, id(T));
    }

    pub inline fn modifiedRaw(self: World, entity: EntityId, component_id: IdStrId) void {
        return self.vtable.modified(self.ptr, entity, component_id);
    }

    pub inline fn parent(self: World, entity: EntityId) ?EntityId {
        return self.vtable.parent(self.ptr, entity);
    }

    pub inline fn children(self: World, entity: EntityId) Iter {
        return self.vtable.children(self.ptr, entity);
    }

    pub inline fn progress(self: World, dt: f32) bool {
        return self.vtable.progress(self.ptr, dt);
    }

    pub inline fn createQuery(self: World, query: QueryDesc) !Query {
        return self.vtable.createQuery(self.ptr, query);
    }

    pub inline fn deferBegin(self: World) bool {
        return self.vtable.deferBegin(self.ptr);
    }

    pub inline fn deferEnd(self: World) bool {
        return self.vtable.deferEnd(self.ptr);
    }

    pub inline fn deferResume(self: World) void {
        self.vtable.deferResume(self.ptr);
    }

    pub inline fn deferSuspend(self: World) void {
        self.vtable.deferSuspend(self.ptr);
    }

    pub fn isRemoteDebugActive(self: World) bool {
        return self.vtable.isRemoteDebugActive(self.ptr);
    }

    pub fn setRemoteDebugActive(self: World, active: bool) ?u16 {
        return self.vtable.setRemoteDebugActive(self.ptr, active);
    }

    pub fn setSimulate(self: World, simulate: bool) void {
        self.vtable.setSimulate(self.ptr, simulate);
    }

    pub fn isSimulate(self: World) bool {
        return self.vtable.isSimulate(self.ptr);
    }

    pub fn enableObserver(self: World, observer_id: cetech1.StrId32, enable: bool) void {
        return self.vtable.enableObserver(self.ptr, observer_id, enable);
    }

    pub fn doStep(self: World) void {
        return self.vtable.doStep(self.ptr);
    }

    pub fn clear(self: World) void {
        return self.vtable.clear(self.ptr);
    }

    pub fn debuguiMenuItems(self: World, allocator: std.mem.Allocator) void {
        return self.vtable.debuguiMenuItems(self.ptr, allocator);
    }

    pub fn uiRemoteDebugMenuItems(self: World, allocator: std.mem.Allocator, port: ?u16) ?u16 {
        return self.vtable.uiRemoteDebugMenuItems(self.ptr, allocator, port);
    }

    pub fn findEntityByCdbObj(self: World, ent_obj: cdb.ObjId) !?EntityId {
        return self.vtable.findEntityByCdbObj(self.ptr, ent_obj);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        newEntity: *const fn (world: *anyopaque, desc: EntityDecs) EntityId,
        newEntities: *const fn (world: *anyopaque, allocator: std.mem.Allocator, id: EntityId, count: usize) ?[]EntityId,
        destroyEntities: *const fn (self: *anyopaque, ents: []const EntityId) void,

        setComponent: *const fn (world: *anyopaque, entity: EntityId, id: IdStrId, size: usize, ptr: ?*const anyopaque) EntityId,
        getMutComponent: *const fn (world: *anyopaque, entity: EntityId, id: IdStrId) ?*anyopaque,
        getComponent: *const fn (world: *anyopaque, entity: EntityId, id: IdStrId) ?*const anyopaque,

        setSingletonComponent: *const fn (world: *anyopaque, id: IdStrId, size: usize, ptr: ?*const anyopaque) void,
        getSingletonComponent: *const fn (world: *anyopaque, id: IdStrId) ?*const anyopaque,

        removeComponent: *const fn (world: *anyopaque, entity: EntityId, id: IdStrId) void,

        getComponentManager: *const fn (world: *anyopaque, id: IdStrId) ?*anyopaque,

        parent: *const fn (world: *anyopaque, entity: EntityId) ?EntityId,
        children: *const fn (world: *anyopaque, entity: EntityId) Iter,

        createQuery: *const fn (world: *anyopaque, query: QueryDesc) anyerror!Query,
        modified: *const fn (world: *anyopaque, entity: EntityId, id: IdStrId) void,
        progress: *const fn (world: *anyopaque, dt: f32) bool,

        deferBegin: *const fn (world: *anyopaque) bool,
        deferEnd: *const fn (world: *anyopaque) bool,
        deferSuspend: *const fn (world: *anyopaque) void,
        deferResume: *const fn (world: *anyopaque) void,

        isRemoteDebugActive: *const fn (world: *anyopaque) bool,
        setRemoteDebugActive: *const fn (world: *anyopaque, active: bool) ?u16,

        setSimulate: *const fn (world: *anyopaque, simulate: bool) void,
        isSimulate: *const fn (world: *anyopaque) bool,
        doStep: *const fn (world: *anyopaque) void,

        enableObserver: *const fn (world: *anyopaque, id: cetech1.StrId32, simulate: bool) void,

        clear: *const fn (world: *anyopaque) void,

        findEntityByCdbObj: *const fn (world: *anyopaque, ent_obj: cdb.ObjId) anyerror!?EntityId,

        debuguiMenuItems: *const fn (world: *anyopaque, allocator: std.mem.Allocator) void,
        uiRemoteDebugMenuItems: *const fn (world: *anyopaque, allocator: std.mem.Allocator, port: ?u16) ?u16,
    };
};

pub const Iter = struct {
    pub inline fn getWorld(self: *Iter) World {
        return self.vtable.getWorld(&self.data);
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
        return self.vtable.isSelf(&self.data, index);
    }

    pub inline fn getParam(self: *Iter, comptime T: type) ?*T {
        const p: *T = @ptrCast(@alignCast(self.vtable.getParam(&self.data) orelse return null));
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
        return self.vtable.nextChildren(&self.data);
    }

    pub inline fn getSystem(self: *Iter) *const SystemI {
        return self.vtable.getSystem();
    }

    data: [360]u8, // TODO: SHIT
    vtable: *const VTable,

    pub const VTable = struct {
        getWorld: *const fn (self: *anyopaque) World,
        count: *const fn (self: *anyopaque) usize,
        field: *const fn (self: *anyopaque, size: usize, index: i8) ?*anyopaque,
        getParam: *const fn (self: *anyopaque) ?*anyopaque,
        entities: *const fn (self: *anyopaque) []const EntityId,

        changed: *const fn (self: *anyopaque) bool,

        skip: *const fn (self: *anyopaque) void,

        isSelf: *const fn (self: *anyopaque, index: i8) bool,

        next: *const fn (self: *anyopaque) bool,
        nextChildren: *const fn (self: *anyopaque) bool,
        getSystem: *const fn (self: *anyopaque) *const SystemI,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "getWorld")) @compileError("implement me");
            if (!std.meta.hasFn(T, "count")) @compileError("implement me");
            if (!std.meta.hasFn(T, "field")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getParam")) @compileError("implement me");
            if (!std.meta.hasFn(T, "changed")) @compileError("implement me");

            if (!std.meta.hasFn(T, "skip")) @compileError("implement me");
            if (!std.meta.hasFn(T, "isSelf")) @compileError("implement me");
            if (!std.meta.hasFn(T, "next")) @compileError("implement me");

            if (!std.meta.hasFn(T, "next")) @compileError("implement me");

            if (!std.meta.hasFn(T, "getSystem")) @compileError("implement me");

            return VTable{
                .getWorld = T.getWorld,
                .count = T.count,
                .field = T.field,
                .getParam = T.getParam,
                .entities = T.entites,
                .changed = T.changed,
                .skip = T.skip,
                .isSelf = T.isSelf,
                .next = T.next,
                .nextChildren = T.nextChildren,
                .getSystem = T.getSystem,
            };
        }
    };
};

pub const ECS_WORLD_CONTEXT = cetech1.strId32("ecs_world_context"); // TODO: This is bad as context because it can change. we need something like exxecuteargs.
pub const ECS_ENTITY_CONTEXT = cetech1.strId32("ecs_entity_context");

pub fn id(comptime T: type) IdStrId {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
    const name = name_iter.first();
    return .fromStr(name);
}

pub const EcsAPI = struct {
    createWorld: *const fn () anyerror!World,
    destroyWorld: *const fn (world: World) void,

    // TODO: REMOVE !!!
    toWorld: *const fn (world: *anyopaque) World,

    findComponentIById: *const fn (name: IdStrId) ?*const ComponentI,
    findComponentIByCdbHash: *const fn (cdb_hash: cdb.TypeHash) ?*const ComponentI,
    findCategoryById: *const fn (name: cetech1.StrId32) ?*const ComponentCategoryI,

    spawnManyFromCDB: *const fn (allocator: std.mem.Allocator, world: World, obj: cdb.ObjId, count: usize) anyerror![]EntityId,
};

fn nameFromType(comptime T: type) [:0]const u8 {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
    const name = name_iter.first();
    const cname = name[0..name.len :0];
    return cname;
}
