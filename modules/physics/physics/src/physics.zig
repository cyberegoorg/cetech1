const std = @import("std");

const cetech1 = @import("cetech1");
const math = cetech1.math;

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
    gravity: math.Vec3f = .{},
};

pub const PhysicsSystemCdb = cdb.CdbTypeDecl(
    "ct_physics_world",
    enum(u32) {
        Gravity,
    },
    struct {},
);

pub const PhysicsShapeType = enum(u8) {
    Box = 0,
    Sphere = 1,
};

pub const PhysicsShape = struct {
    type: PhysicsShapeType = .Box,
    size: math.Vec3f = .{ .x = 1, .y = 1, .z = 1 },
};

pub const PhysicsShapeCdb = cdb.CdbTypeDecl(
    "ct_physics_shape",
    enum(u32) {
        Type,
        Size,
    },
    struct {},
);

pub const PhysicsBody = struct {
    type: PhysicsBodyType = .Static,
    mass: f32 = 0,
};

pub const PhysicsBodyType = enum(u8) {
    Static = 0,
    Dynamic = 1,
    Kinematic = 2,
};

pub const PhysicsBodyCdb = cdb.CdbTypeDecl(
    "ct_physics_body",
    enum(u32) {
        Type,
        Mass,
    },
    struct {},
);
