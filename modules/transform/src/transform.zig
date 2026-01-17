const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const math = cetech1.math;
const ecs = cetech1.ecs;

pub const TransformComponent = struct {
    local: math.Transform = .{},
};

pub const WorldTransformComponent = struct {
    world: math.Transform = .{},
};

pub const TransformComponentCdb = cdb.CdbTypeDecl(
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
    transformChilds: *const fn (world: ecs.World, entity: ecs.EntityId) void,
};
