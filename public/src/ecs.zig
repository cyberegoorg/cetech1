const std = @import("std");
const builtin = @import("builtin");
const strid = @import("strid.zig");

pub const Id = u64;
pub const EntityId = Id;
pub const ComponentId = EntityId;
pub const SystemId = EntityId;

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
pub const DefaultChildComponent = strid.strId32("DefaultChildComponent");
pub const PredEq = strid.strId32("PredEq");
pub const PredMatch = strid.strId32("PredMatch");
pub const PredLookup = strid.strId32("PredLookup");
pub const Tag = strid.strId32("Tag");
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
pub const UnSet = strid.strId32("UnSet");
pub const Monitor = strid.strId32("Monitor");
pub const OnTableCreate = strid.strId32("OnTableCreate");
pub const OnTableDelete = strid.strId32("OnTableDelete");
pub const OnTableEmpty = strid.strId32("OnTableEmpty");
pub const OnTableFill = strid.strId32("OnTableFill");

pub fn id(comptime T: type) strid.StrId32 {
    return strid.strId32(@typeName(T));
}

pub const InOutKind = enum(i32) {
    InOutDefault,
    InOutNone,
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

pub const Term = struct {
    id: strid.StrId32,
    inout: InOutKind = .InOutDefault,
    oper: OperatorKind = .And,
};

pub const IterO = opaque {};

pub const ComponentI = struct {
    pub const c_name = "ct_ecs_component_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8,
    id: strid.StrId32,
    size: usize,
    aligment: usize,

    pub fn implement(comptime T: type) @This() {
        return @This(){
            .name = @typeName(T),
            .id = strid.strId32(@typeName(T)),
            .size = @sizeOf(T),
            .aligment = @alignOf(T),
        };
    }
};

pub const SystemI = struct {
    pub const c_name = "ct_ecs_system_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8 = undefined,
    phase: strid.StrId32 = undefined,
    query: []const Term,
    multi_threaded: bool = true,

    update: *const fn (iter: *IterO) callconv(.C) void = undefined,

    pub fn implement(args: SystemI, comptime T: type) SystemI {
        if (!std.meta.hasFn(T, "update")) @compileError("implement me");

        return SystemI{
            .name = args.name,
            .phase = args.phase,
            .query = args.query,
            .multi_threaded = args.multi_threaded,

            .update = struct {
                pub fn f(iter: *IterO) callconv(.C) void {
                    T.update(iter) catch undefined;
                }
            }.f,
        };
    }
};

pub const Query = struct {
    world: World,
    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn destroy(self: *Query) void {
        self.vtable.destroy(self.ptr);
    }

    pub fn iter(self: *Query) !Iter {
        return self.vtable.iter(self.ptr, self.world);
    }

    pub fn next(self: *Query, it: Iter) bool {
        return self.vtable.next(self.ptr, it);
    }

    pub const VTable = struct {
        destroy: *const fn (query: *anyopaque) void,
        iter: *const fn (query: *anyopaque, world: World) anyerror!Iter,
        next: *const fn (query: *anyopaque, it: Iter) bool,

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
    pub fn newEntity(self: World, name: ?[:0]const u8) EntityId {
        return self.vtable.newEntity(self.ptr, name);
    }

    pub fn newEntities(self: World, allocator: std.mem.Allocator, count: usize) ?[]EntityId {
        return self.vtable.newEntities(self.ptr, allocator, count);
    }

    pub fn setId(self: World, comptime T: type, entity: EntityId, ptr: ?*const T) EntityId {
        return self.vtable.setId(self.ptr, entity, id(T), @sizeOf(T), ptr);
    }

    pub fn progress(self: World, dt: f32) bool {
        return self.vtable.progress(self.ptr, dt);
    }

    pub fn createQuery(self: World, query: []const Term) !Query {
        return self.vtable.createQuery(self.ptr, query);
    }

    pub fn createSystem(self: World, name: [:0]const u8, query: []const Term, comptime T: type) !SystemId {
        return self.vtable.createSystem(
            self.ptr,
            name,
            query,
            struct {
                pub fn f(iter: *IterO) callconv(.C) void {
                    T.update(iter) catch undefined;
                }
            }.f,
        );
    }

    pub fn runSystem(self: World, system_id: strid.StrId32, param: ?*const anyopaque) void {
        return self.vtable.runSystem(self.ptr, system_id, param);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        newEntity: *const fn (world: *anyopaque, name: ?[:0]const u8) EntityId,
        newEntities: *const fn (world: *anyopaque, allocator: std.mem.Allocator, count: usize) ?[]EntityId,

        setId: *const fn (world: *anyopaque, entity: EntityId, id: strid.StrId32, size: usize, ptr: ?*const anyopaque) EntityId,

        createQuery: *const fn (world: *anyopaque, query: []const Term) anyerror!Query,
        createSystem: *const fn (world: *anyopaque, name: [:0]const u8, query: []const Term, update: *const fn (iter: *IterO) callconv(.C) void) anyerror!SystemId,
        runSystem: *const fn (world: *anyopaque, system_id: strid.StrId32, param: ?*const anyopaque) void,

        progress: *const fn (world: *anyopaque, dt: f32) bool,
    };
};

pub const Iter = struct {
    pub fn getWorld(self: Iter) World {
        return self.vtable.getWorld(self.ptr);
    }

    pub fn count(self: Iter) usize {
        return self.vtable.count(self.ptr);
    }

    pub fn field(self: Iter, comptime T: type, index: i32) ?[]T {
        if (self.vtable.field(self.ptr, @sizeOf(T), index)) |anyptr| {
            const ptr = @as([*]T, @ptrCast(@alignCast(anyptr)));
            return ptr[0..self.count()];
        }
        return null;
    }

    pub fn destroy(self: Iter) void {
        self.vtable.destroy(self.ptr);
    }

    pub fn getParam(self: Iter, comptime T: type) ?*T {
        const p: *T = @alignCast(@ptrCast(self.vtable.getParam(self.ptr) orelse return null));
        return p;
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getWorld: *const fn (self: *anyopaque) World,
        count: *const fn (self: *anyopaque) usize,
        field: *const fn (self: *anyopaque, size: usize, index: i32) ?*anyopaque,
        destroy: *const fn (self: *anyopaque) void,
        getParam: *const fn (self: *anyopaque) ?*anyopaque,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "getWorld")) @compileError("implement me");
            if (!std.meta.hasFn(T, "count")) @compileError("implement me");
            if (!std.meta.hasFn(T, "field")) @compileError("implement me");
            if (!std.meta.hasFn(T, "destroy")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getParam")) @compileError("implement me");

            return VTable{
                .getWorld = T.getWorld,
                .count = T.count,
                .field = T.field,
                .destroy = T.destroy,
                .getParam = T.getParam,
            };
        }
    };
};

pub const EcsAPI = struct {
    createWorld: *const fn () anyerror!World,
    destroyWorld: *const fn (world: World) void,

    toIter: *const fn (iter: *IterO) Iter,
};
