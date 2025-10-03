const std = @import("std");
const builtin = @import("builtin");
const cetech1 = @import("root.zig");

const cdb = @import("cdb.zig");
const gpu = @import("gpu.zig");

const log = std.log.scoped(.ecs);

pub const Id = u64;
pub const EntityId = Id;
pub const ComponentId = EntityId;
pub const SystemId = EntityId;

pub const PinTypes = struct {
    pub const Entity = cetech1.strId32("entity");
    pub const World = cetech1.strId32("world");
};

pub const Entity = cdb.CdbTypeDecl(
    "ct_entity",
    enum(u32) {
        name = 0,
        components,
        childrens,
    },
    struct {},
);

pub const Wildcard = cetech1.strId32("Wildcard");
pub const Any = cetech1.strId32("Any");
pub const Transitive = cetech1.strId32("Transitive");
pub const Reflexive = cetech1.strId32("Reflexive");
pub const Final = cetech1.strId32("Final");
pub const DontInherit = cetech1.strId32("DontInherit");
pub const Exclusive = cetech1.strId32("Exclusive");
pub const Acyclic = cetech1.strId32("Acyclic");
pub const Traversable = cetech1.strId32("Traversable");
pub const Symmetric = cetech1.strId32("Symmetric");
pub const With = cetech1.strId32("With");
pub const OneOf = cetech1.strId32("OneOf");
pub const IsA = cetech1.strId32("IsA");
pub const ChildOf = cetech1.strId32("ChildOf");
pub const DependsOn = cetech1.strId32("DependsOn");
pub const SlotOf = cetech1.strId32("SlotOf");
pub const OnDelete = cetech1.strId32("OnDelete");
pub const OnDeleteTarget = cetech1.strId32("OnDeleteTarget");
pub const Remove = cetech1.strId32("Remove");
pub const Delete = cetech1.strId32("Delete");
pub const Panic = cetech1.strId32("Panic");

pub const PredEq = cetech1.strId32("PredEq");
pub const PredMatch = cetech1.strId32("PredMatch");
pub const PredLookup = cetech1.strId32("PredLookup");
pub const Union = cetech1.strId32("Union");
pub const Alias = cetech1.strId32("Alias");
pub const Prefab = cetech1.strId32("Prefab");
pub const Disabled = cetech1.strId32("Disabled");

pub const OnStart = cetech1.strId32("OnStart");
pub const PreFrame = cetech1.strId32("PreFrame");
pub const OnLoad = cetech1.strId32("OnLoad");
pub const PostLoad = cetech1.strId32("PostLoad");
pub const PreUpdate = cetech1.strId32("PreUpdate");
pub const OnUpdate = cetech1.strId32("OnUpdate");
pub const OnValidate = cetech1.strId32("OnValidate");
pub const PostUpdate = cetech1.strId32("PostUpdate");
pub const PreStore = cetech1.strId32("PreStore");
pub const OnStore = cetech1.strId32("OnStore");
pub const PostFrame = cetech1.strId32("PostFrame");

pub const Phase = cetech1.strId32("Phase");
pub const OnAdd = cetech1.strId32("OnAdd");
pub const OnRemove = cetech1.strId32("OnRemove");
pub const OnSet = cetech1.strId32("OnSet");
pub const Monitor = cetech1.strId32("Monitor");
pub const OnTableCreate = cetech1.strId32("OnTableCreate");
pub const OnTableDelete = cetech1.strId32("OnTableDelete");
pub const OnTableEmpty = cetech1.strId32("OnTableEmpty");
pub const OnTableFill = cetech1.strId32("OnTableFill");

pub fn id(comptime T: type) cetech1.StrId32 {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
    const name = name_iter.first();
    return cetech1.strId32(name);
}

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

pub const InOutKind = enum(i32) {
    InOutDefault,
    InOutNone,
    EcsInOutFilter,
    InOut,
    In,
    Out,
};

pub const OperatorKind = enum(i32) {
    And,
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
    //trav: EntityId = 0,
};

pub const QueryTerm = struct {
    id: cetech1.StrId32,
    inout: InOutKind = .InOutDefault,
    oper: OperatorKind = .And,
    src: TermId = .{},
    first: TermId = .{},
    second: TermId = .{},
    cache_kind: QueryCacheKind = .QueryCacheDefault,
};

pub const IterO = opaque {};

pub const ComponentI = struct {
    const Self = @This();
    pub const c_name = "ct_ecs_component_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8 = undefined,
    id: cetech1.StrId32 = undefined,
    size: usize = undefined,
    aligment: usize = undefined,

    category: ?[:0]const u8 = null,
    category_order: f32 = 0,

    cdb_type_hash: cdb.TypeHash = .{},

    with: ?[]const cetech1.StrId32 = null,

    onAdd: ?*const fn (iter: *IterO) callconv(.c) void = null,
    onSet: ?*const fn (iter: *IterO) callconv(.c) void = null,
    onRemove: ?*const fn (iter: *IterO) callconv(.c) void = null,

    onCreate: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    onDestroy: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    onCopy: ?*const fn (dst_ptr: *anyopaque, src_ptr: *const anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,
    onMove: ?*const fn (dst_ptr: *anyopaque, src_ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void = null,

    uiIcons: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    fromCdb: ?*const fn (
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        data: []u8,
    ) anyerror!void = null,

    debugdraw: ?*const fn (
        dd: gpu.DDEncoder,
        world: World,
        entites: []const EntityId,
        data: []const u8,
        size: [2]f32,
    ) anyerror!void = null,

    pub fn nameFromType(
        comptime T: type,
    ) [:0]const u8 {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        const name = name_iter.first();
        const cname = name[0..name.len :0];
        return cname;
    }

    pub fn implement(comptime T: type, args: ComponentI, comptime Hooks: type) Self {
        return Self{
            .name = nameFromType(T),
            .id = id(T),
            .cdb_type_hash = args.cdb_type_hash,

            .size = @sizeOf(T),
            .aligment = @alignOf(T),

            .category = args.category,
            .category_order = args.category_order,
            .with = args.with,

            .onAdd = if (std.meta.hasFn(Hooks, "onAdd")) struct {
                fn f(iter: *IterO) callconv(.c) void {
                    Hooks.onAdd(iter) catch undefined;
                }
            }.f else null,

            .onSet = if (std.meta.hasFn(Hooks, "onSet")) struct {
                fn f(iter: *IterO) callconv(.c) void {
                    Hooks.onSet(iter) catch undefined;
                }
            }.f else null,

            .onRemove = if (std.meta.hasFn(Hooks, "onRemove")) struct {
                fn f(iter: *IterO) callconv(.c) void {
                    Hooks.onRemove(iter) catch undefined;
                }
            }.f else null,

            .onCreate = if (std.meta.hasFn(Hooks, "onCreate")) struct {
                fn f(ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void {
                    _ = type_info;
                    var tptr: []T = undefined;
                    tptr.len = @intCast(count);
                    tptr.ptr = @ptrCast(@alignCast(ptr));

                    Hooks.onCreate(tptr) catch undefined;
                }
            }.f else null,

            .onDestroy = if (std.meta.hasFn(Hooks, "onDestroy")) struct {
                fn f(ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.c) void {
                    _ = type_info;
                    var tptr: []T = undefined;
                    tptr.len = @intCast(count);
                    tptr.ptr = @ptrCast(@alignCast(ptr));

                    Hooks.onDestroy(tptr) catch undefined;
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
                        log.err("OnCopy erro {}", .{err});
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

                    Hooks.onMove(dst_tptr, src_tptr) catch undefined;
                }
            }.f else null,

            .uiIcons = if (std.meta.hasFn(Hooks, "uiIcons")) Hooks.uiIcons else null,

            .fromCdb = if (std.meta.hasFn(Hooks, "fromCdb")) Hooks.fromCdb else null,
            .debugdraw = if (std.meta.hasFn(Hooks, "debugdraw")) Hooks.debugdraw else null,
        };
    }
};

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

pub const SystemI = struct {
    pub const c_name = "ct_ecs_system_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8 = undefined,
    phase: cetech1.StrId32 = undefined,
    query: []const QueryTerm,
    multi_threaded: bool = false,
    immediate: bool = false,
    cache_kind: QueryCacheKind = .QueryCacheDefault,

    simulation: bool = false,

    update: ?*const fn (world: World, iter: *Iter) anyerror!void = undefined,
    iterate: ?*const fn (world: World, iter: *Iter) anyerror!void = undefined,

    pub fn implement(args: SystemI, comptime T: type) SystemI {
        return SystemI{
            .name = args.name,
            .phase = args.phase,
            .query = args.query,
            .multi_threaded = args.multi_threaded,
            .immediate = args.immediate,
            .cache_kind = args.cache_kind,
            .simulation = args.simulation,

            .update = if (std.meta.hasFn(T, "update")) T.update else null,
            .iterate = if (std.meta.hasFn(T, "iterate")) T.iterate else null,
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
    world: World,
    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn destroy(self: *Query) void {
        self.vtable.destroy(self.ptr);
    }

    pub inline fn count(self: *Query) QueryCount {
        return self.vtable.count(self.ptr);
    }

    pub inline fn iter(self: *Query) !Iter {
        return self.vtable.iter(self.ptr, self.world);
    }

    pub inline fn next(self: *Query, it: *Iter) bool {
        return self.vtable.next(self.ptr, it);
    }

    pub const VTable = struct {
        destroy: *const fn (query: *anyopaque) void,
        count: *const fn (query: *anyopaque) QueryCount,
        iter: *const fn (query: *anyopaque, world: World) anyerror!Iter,
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

pub const World = struct {
    pub inline fn newEntity(self: World, name: ?[:0]const u8) EntityId {
        return self.vtable.newEntity(self.ptr, name);
    }

    pub inline fn newEntities(self: World, allocator: std.mem.Allocator, eid: EntityId, count: usize) ?[]EntityId {
        return self.vtable.newEntities(self.ptr, allocator, eid, count);
    }

    pub inline fn destroyEntities(self: World, ents: []const EntityId) void {
        return self.vtable.destroyEntities(self.ptr, ents);
    }

    pub inline fn setId(self: World, comptime T: type, entity: EntityId, ptr: ?*const T) EntityId {
        return self.vtable.setComponent(self.ptr, entity, id(T), @sizeOf(T), ptr);
    }

    pub inline fn getMutComponent(self: World, comptime T: type, entity: EntityId) ?*T {
        const ptr = self.vtable.getMutComponent(self.ptr, entity, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn getComponent(self: World, comptime T: type, entity: EntityId) ?*const T {
        const ptr = self.vtable.getComponent(self.ptr, entity, id(T));
        return @ptrCast(@alignCast(ptr));
    }

    pub inline fn setIdRaw(self: World, entity: EntityId, cid: cetech1.StrId32, size: usize, ptr: ?*const anyopaque) EntityId {
        return self.vtable.setComponent(self.ptr, entity, cid, size, ptr);
    }

    pub inline fn progress(self: World, dt: f32) bool {
        return self.vtable.progress(self.ptr, dt);
    }

    pub inline fn createQuery(self: World, query: []const QueryTerm) !Query {
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

    pub fn clear(self: World) void {
        return self.vtable.clear(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        newEntity: *const fn (world: *anyopaque, name: ?[:0]const u8) EntityId,
        newEntities: *const fn (world: *anyopaque, allocator: std.mem.Allocator, id: EntityId, count: usize) ?[]EntityId,
        destroyEntities: *const fn (self: *anyopaque, ents: []const EntityId) void,

        setComponent: *const fn (world: *anyopaque, entity: EntityId, id: cetech1.StrId32, size: usize, ptr: ?*const anyopaque) EntityId,
        getMutComponent: *const fn (world: *anyopaque, entity: EntityId, id: cetech1.StrId32) ?*anyopaque,
        getComponent: *const fn (world: *anyopaque, entity: EntityId, id: cetech1.StrId32) ?*const anyopaque,

        createQuery: *const fn (world: *anyopaque, query: []const QueryTerm) anyerror!Query,

        progress: *const fn (world: *anyopaque, dt: f32) bool,

        deferBegin: *const fn (world: *anyopaque) bool,
        deferEnd: *const fn (world: *anyopaque) bool,
        deferSuspend: *const fn (world: *anyopaque) void,
        deferResume: *const fn (world: *anyopaque) void,

        isRemoteDebugActive: *const fn (world: *anyopaque) bool,
        setRemoteDebugActive: *const fn (world: *anyopaque, active: bool) ?u16,

        setSimulate: *const fn (world: *anyopaque, simulate: bool) void,
        isSimulate: *const fn (world: *anyopaque) bool,

        clear: *const fn (world: *anyopaque) void,
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

    pub inline fn getSystem(self: *Iter) *const SystemI {
        return self.vtable.getSystem();
    }

    data: [384]u8,
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
                .getSystem = T.getSystem,
            };
        }
    };
};

pub const ECS_WORLD_CONTEXT = cetech1.strId32("ecs_world_context");
pub const ECS_ENTITY_CONTEXT = cetech1.strId32("ecs_entity_context");

pub const EcsAPI = struct {
    createWorld: *const fn () anyerror!World,
    destroyWorld: *const fn (world: World) void,

    toWorld: *const fn (world: *anyopaque) World,
    toIter: *const fn (iter: *IterO) Iter,

    findComponentIById: *const fn (name: cetech1.StrId32) ?*const ComponentI,
    findComponentIByCdbHash: *const fn (cdb_hash: cdb.TypeHash) ?*const ComponentI,
    findCategoryById: *const fn (name: cetech1.StrId32) ?*const ComponentCategoryI,

    spawnManyFromCDB: *const fn (allocator: std.mem.Allocator, world: World, obj: cdb.ObjId, count: usize) anyerror![]EntityId,
};
