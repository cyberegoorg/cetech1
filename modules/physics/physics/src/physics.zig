const std = @import("std");

const cetech1 = @import("cetech1");
const zm = cetech1.math.zmath;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

pub const Velocity = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const VelocityCdb = cdb.CdbTypeDecl(
    "ct_velocity",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {},
);

pub const PhysicsSystem = struct {
    _: u8 = 0,
};

pub const PhysicsSystemCdb = cdb.CdbTypeDecl(
    "ct_physics_world",
    enum(u32) {},
    struct {},
);

pub const PhysicsShapeType = enum(u8) {
    box = 0,
    sphere = 1,
};

pub const PhysicsShape = struct {
    type: PhysicsShapeType = .box,
    size: zm.Vec = .{ 1, 1, 1, 0 },
};

pub const PhysicsShapeCdb = cdb.CdbTypeDecl(
    "ct_physics_shape",
    enum(u32) {
        type,
        size,
    },
    struct {},
);

pub const PhysicsBody = struct {
    type: PhysicsBodyType = .static,
    mass: f32 = 0,
};

pub const PhysicsBodyType = enum(u8) {
    static = 0,
    dynamic = 1,
    kinematic = 2,
};

pub const PhysicsBodyCdb = cdb.CdbTypeDecl(
    "ct_physics_body",
    enum(u32) {
        type,
        mass,
    },
    struct {},
);
