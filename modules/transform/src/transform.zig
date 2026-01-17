const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const math = cetech1.math;
const ecs = cetech1.ecs;

pub const LocalTransformComponent = struct {
    local: math.Transform = .{},
};

pub const WorldTransformComponent = struct {
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

pub const TransformApi = struct {
    transform: *const fn (world: ecs.World, entity: ecs.EntityId) void,
    transformOnlyChilds: *const fn (world: ecs.World, entity: ecs.EntityId) void,
};
