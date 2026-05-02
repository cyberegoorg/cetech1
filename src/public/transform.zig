const std = @import("std");

const cetech1 = @import("cetech1.zig");
const cdb = cetech1.cdb;
const math = cetech1.math;
const ecs = cetech1.ecs;
const apidb = cetech1.apidb;

pub const LocalTransformComponent = extern struct {
    local: math.Transform = .{},
};

pub const WorldTransformComponent = extern struct {
    world: math.Transform = .{},
};

pub const LocalTransformComponentCdb = cdb.CdbTypeDecl(
    "ct_transform",
    enum(u32) {
        Position = 0,
        Rotation,
        Scale,
    },
    struct {},
);

pub fn transform(world: *ecs.World, entity: ecs.EntityId) void {
    return api.transform(world, entity);
}
pub fn transformOnlyChilds(world: *ecs.World, entity: ecs.EntityId) void {
    return api.transformOnlyChilds(world, entity);
}

pub const TransformApi = struct {
    transform: *const fn (world: *ecs.World, entity: ecs.EntityId) void,
    transformOnlyChilds: *const fn (world: *ecs.World, entity: ecs.EntityId) void,
};

pub var api: *const TransformApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, TransformApi).?;
}
