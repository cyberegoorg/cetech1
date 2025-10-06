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
