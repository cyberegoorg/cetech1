const std = @import("std");
const builtin = @import("builtin");
const strid = @import("strid.zig");

const cdb = @import("cdb.zig");

const log = std.log.scoped(.ecs);

pub const Id = u64;
pub const EntityId = Id;
pub const ComponentId = EntityId;
pub const SystemId = EntityId;

pub const PinTypes = struct {
    pub const Entity = strid.strId32("entity");
    pub const World = strid.strId32("world");
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

pub const Wildcard = strid.strId32("Wildcard");
pub const Any = strid.strId32("Any");
pub const Transitive = strid.strId32("Transitive");
pub const Reflexive = strid.strId32("Reflexive");
pub const Final = strid.strId32("Final");
pub const DontInherit = strid.strId32("DontInherit");
pub const Exclusive = strid.strId32("Exclusive");
pub const Acyclic = strid.strId32("Acyclic");
pub const Traversable = strid.strId32("Traversable");
pub const Symmetric = strid.strId32("Symmetric");
pub const With = strid.strId32("With");
pub const OneOf = strid.strId32("OneOf");
pub const IsA = strid.strId32("IsA");
pub const ChildOf = strid.strId32("ChildOf");
pub const DependsOn = strid.strId32("DependsOn");
pub const SlotOf = strid.strId32("SlotOf");
pub const OnDelete = strid.strId32("OnDelete");
pub const OnDeleteTarget = strid.strId32("OnDeleteTarget");
pub const Remove = strid.strId32("Remove");
pub const Delete = strid.strId32("Delete");
pub const Panic = strid.strId32("Panic");

pub const PredEq = strid.strId32("PredEq");
pub const PredMatch = strid.strId32("PredMatch");
pub const PredLookup = strid.strId32("PredLookup");
pub const Union = strid.strId32("Union");
pub const Alias = strid.strId32("Alias");
pub const Prefab = strid.strId32("Prefab");
pub const Disabled = strid.strId32("Disabled");

pub const OnStart = strid.strId32("OnStart");
pub const PreFrame = strid.strId32("PreFrame");
pub const OnLoad = strid.strId32("OnLoad");
pub const PostLoad = strid.strId32("PostLoad");
pub const PreUpdate = strid.strId32("PreUpdate");
pub const OnUpdate = strid.strId32("OnUpdate");
pub const OnValidate = strid.strId32("OnValidate");
pub const PostUpdate = strid.strId32("PostUpdate");
pub const PreStore = strid.strId32("PreStore");
pub const OnStore = strid.strId32("OnStore");
pub const PostFrame = strid.strId32("PostFrame");

pub const Phase = strid.strId32("Phase");
pub const OnAdd = strid.strId32("OnAdd");
pub const OnRemove = strid.strId32("OnRemove");
pub const OnSet = strid.strId32("OnSet");
pub const Monitor = strid.strId32("Monitor");
pub const OnTableCreate = strid.strId32("OnTableCreate");
pub const OnTableDelete = strid.strId32("OnTableDelete");
pub const OnTableEmpty = strid.strId32("OnTableEmpty");
pub const OnTableFill = strid.strId32("OnTableFill");

pub fn id(comptime T: type) strid.StrId32 {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
    const name = name_iter.first();
    return strid.strId32(name);
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
    id: strid.StrId32,
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
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8,
    id: strid.StrId32,
    size: usize,
    aligment: usize,

    cdb_type_hash: cdb.TypeHash = .{},

    onAdd: ?*const fn (iter: *IterO) callconv(.C) void = null,
    onSet: ?*const fn (iter: *IterO) callconv(.C) void = null,
    onRemove: ?*const fn (iter: *IterO) callconv(.C) void = null,

    onCreate: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void = null,
    onDestroy: ?*const fn (ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void = null,
    onCopy: ?*const fn (dst_ptr: *anyopaque, src_ptr: *const anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void = null,
    onMove: ?*const fn (dst_ptr: *anyopaque, src_ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void = null,

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

    pub fn implement(comptime T: type, cdb_type_hash: ?cdb.TypeHash, comptime Hooks: type) Self {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        const name = name_iter.first();
        const cname = name[0..name.len :0];

        return Self{
            .name = cname,
            .id = strid.strId32(name),

            .size = @sizeOf(T),
            .aligment = @alignOf(T),

            .cdb_type_hash = cdb_type_hash orelse .{},

            .onAdd = if (std.meta.hasFn(Hooks, "onAdd")) struct {
                fn f(iter: *IterO) callconv(.C) void {
                    Hooks.onAdd(iter) catch undefined;
                }
            }.f else null,

            .onSet = if (std.meta.hasFn(Hooks, "onSet")) struct {
                fn f(iter: *IterO) callconv(.C) void {
                    Hooks.onSet(iter) catch undefined;
                }
            }.f else null,

            .onRemove = if (std.meta.hasFn(Hooks, "onRemove")) struct {
                fn f(iter: *IterO) callconv(.C) void {
                    Hooks.onRemove(iter) catch undefined;
                }
            }.f else null,

            .onCreate = if (std.meta.hasFn(Hooks, "onCreate")) struct {
                fn f(ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void {
                    _ = type_info;
                    var tptr: []T = undefined;
                    tptr.len = @intCast(count);
                    tptr.ptr = @alignCast(@ptrCast(ptr));

                    Hooks.onCreate(tptr) catch undefined;
                }
            }.f else null,

            .onDestroy = if (std.meta.hasFn(Hooks, "onDestroy")) struct {
                fn f(ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void {
                    _ = type_info;
                    var tptr: []T = undefined;
                    tptr.len = @intCast(count);
                    tptr.ptr = @alignCast(@ptrCast(ptr));

                    Hooks.onDestroy(tptr) catch undefined;
                }
            }.f else null,

            .onCopy = if (std.meta.hasFn(Hooks, "onCopy")) struct {
                fn f(dst_ptr: *anyopaque, src_ptr: *const anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void {
                    _ = type_info;

                    var dst_tptr: []T = undefined;
                    dst_tptr.len = @intCast(count);
                    dst_tptr.ptr = @alignCast(@ptrCast(dst_ptr));

                    var src_tptr: []const T = undefined;
                    src_tptr.len = @intCast(count);
                    src_tptr.ptr = @alignCast(@ptrCast(src_ptr));

                    Hooks.onCopy(dst_tptr, src_tptr) catch |err| {
                        log.err("OnCopy erro {}", .{err});
                    };
                }
            }.f else null,

            .onMove = if (std.meta.hasFn(Hooks, "onMove")) struct {
                fn f(dst_ptr: *anyopaque, src_ptr: *anyopaque, count: i32, type_info: *anyopaque) callconv(.C) void {
                    _ = type_info;

                    var dst_tptr: []T = undefined;
                    dst_tptr.len = @intCast(count);
                    dst_tptr.ptr = @alignCast(@ptrCast(dst_ptr));

                    var src_tptr: []T = undefined;
                    src_tptr.len = @intCast(count);
                    src_tptr.ptr = @alignCast(@ptrCast(src_ptr));

                    Hooks.onMove(dst_tptr, src_tptr) catch undefined;
                }
            }.f else null,

            .uiIcons = if (std.meta.hasFn(Hooks, "uiIcons")) Hooks.uiIcons else null,

            .fromCdb = if (std.meta.hasFn(Hooks, "fromCdb")) Hooks.fromCdb else null,
        };
    }
};

pub const SystemI = struct {
    pub const c_name = "ct_ecs_system_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8 = undefined,
    phase: strid.StrId32 = undefined,
    query: []const QueryTerm,
    multi_threaded: bool = true,
    instanced: bool = false,
    immediate: bool = false,
    cache_kind: QueryCacheKind = .QueryCacheDefault,

    simulation: bool = false,

    update: ?*const fn (iter: *IterO) callconv(.C) void = undefined,
    iterate: ?*const fn (iter: *IterO) callconv(.C) void = undefined,

    pub fn implement(args: SystemI, comptime T: type) SystemI {
        return SystemI{
            .name = args.name,
            .phase = args.phase,
            .query = args.query,
            .multi_threaded = args.multi_threaded,
            .instanced = args.instanced,
            .simulation = args.simulation,

            .update = if (std.meta.hasFn(T, "update")) struct {
                pub fn f(iter: *IterO) callconv(.C) void {
                    T.update(iter) catch undefined;
                }
            }.f else null,

            .iterate = if (std.meta.hasFn(T, "iterate")) struct {
                pub fn f(iter: *IterO) callconv(.C) void {
                    T.iterate(iter) catch undefined;
                }
            }.f else null,
        };
    }
};

pub const OnWorldI = struct {
    pub const c_name = "ct_ecs_on_world_i";
    pub const name_hash = strid.strId64(@This().c_name);

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

pub const Query = struct {
    world: World,
    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn destroy(self: *Query) void {
        self.vtable.destroy(self.ptr);
    }

    pub inline fn iter(self: *Query) !Iter {
        return self.vtable.iter(self.ptr, self.world);
    }

    pub inline fn next(self: *Query, it: *Iter) bool {
        return self.vtable.next(self.ptr, it);
    }

    pub const VTable = struct {
        destroy: *const fn (query: *anyopaque) void,
        iter: *const fn (query: *anyopaque, world: World) anyerror!Iter,
        next: *const fn (query: *anyopaque, it: *Iter) bool,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");
            if (!std.meta.hasFn(T, "iter")) @compileError("implement me");
            if (!std.meta.hasFn(T, "next")) @compileError("implement me");

            return VTable{
                .destroy = T.destroy,
                .iter = T.iter,
                .next = T.next,
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
        return self.vtable.setId(self.ptr, entity, id(T), @sizeOf(T), ptr);
    }

    pub inline fn getMutId(self: World, comptime T: type, entity: EntityId) ?*T {
        const ptr = self.vtable.getMutId(self.ptr, entity, id(T));
        return @alignCast(@ptrCast(ptr));
    }

    pub inline fn setIdRaw(self: World, entity: EntityId, cid: strid.StrId32, size: usize, ptr: ?*const anyopaque) EntityId {
        return self.vtable.setId(self.ptr, entity, cid, size, ptr);
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

    pub fn uiRemoteDebugMenuItems(self: World, allocator: std.mem.Allocator, port: ?u16) ?u16 {
        return self.vtable.uiRemoteDebugMenuItems(self.ptr, allocator, port);
    }

    pub fn setSimulate(self: World, simulate: bool) void {
        self.vtable.setSimulate(self.ptr, simulate);
    }

    pub fn isSimulate(self: World) bool {
        return self.vtable.isSimulate(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        newEntity: *const fn (world: *anyopaque, name: ?[:0]const u8) EntityId,
        newEntities: *const fn (world: *anyopaque, allocator: std.mem.Allocator, id: EntityId, count: usize) ?[]EntityId,
        destroyEntities: *const fn (self: *anyopaque, ents: []const EntityId) void,

        setId: *const fn (world: *anyopaque, entity: EntityId, id: strid.StrId32, size: usize, ptr: ?*const anyopaque) EntityId,
        getMutId: *const fn (world: *anyopaque, entity: EntityId, id: strid.StrId32) ?*anyopaque,
        createQuery: *const fn (world: *anyopaque, query: []const QueryTerm) anyerror!Query,

        progress: *const fn (world: *anyopaque, dt: f32) bool,

        deferBegin: *const fn (world: *anyopaque) bool,
        deferEnd: *const fn (world: *anyopaque) bool,
        deferSuspend: *const fn (world: *anyopaque) void,
        deferResume: *const fn (world: *anyopaque) void,

        isRemoteDebugActive: *const fn (world: *anyopaque) bool,
        setRemoteDebugActive: *const fn (world: *anyopaque, active: bool) ?u16,
        uiRemoteDebugMenuItems: *const fn (world: *anyopaque, allocator: std.mem.Allocator, port: ?u16) ?u16,

        setSimulate: *const fn (world: *anyopaque, simulate: bool) void,
        isSimulate: *const fn (world: *anyopaque) bool,
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

    pub inline fn isSelf(self: *Iter, index: i8) bool {
        return self.vtable.isSelf(&self.data, index);
    }

    pub inline fn getParam(self: *Iter, comptime T: type) ?*T {
        const p: *T = @alignCast(@ptrCast(self.vtable.getParam(&self.data) orelse return null));
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

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "getWorld")) @compileError("implement me");
            if (!std.meta.hasFn(T, "count")) @compileError("implement me");
            if (!std.meta.hasFn(T, "field")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getParam")) @compileError("implement me");
            if (!std.meta.hasFn(T, "changed")) @compileError("implement me");

            if (!std.meta.hasFn(T, "skip")) @compileError("implement me");
            if (!std.meta.hasFn(T, "isSelf")) @compileError("implement me");
            if (!std.meta.hasFn(T, "next")) @compileError("implement me");

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
            };
        }
    };
};

pub const ECS_WORLD_CONTEXT = strid.strId32("ecs_world_context");
pub const ECS_ENTITY_CONTEXT = strid.strId32("ecs_entity_context");

pub const EcsAPI = struct {
    createWorld: *const fn () anyerror!World,
    destroyWorld: *const fn (world: World) void,

    //toWorld: *const fn (world: *anyopaque) World,
    toIter: *const fn (iter: *IterO) Iter,

    findComponentIByCdbHash: *const fn (cdb_hash: cdb.TypeHash) ?*const ComponentI,

    spawnManyFromCDB: *const fn (allocator: std.mem.Allocator, world: World, obj: cdb.ObjId, count: usize) anyerror![]EntityId,
};
