const std = @import("std");

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

pub const LightType = enum(u8) {
    Point = 0,
    Spot = 1,
    Direction = 2,
};

pub const Light = struct {
    type: LightType = .Point,
    color: math.Color3f = .white,
    power: f32 = 1000,
    radius: f32 = 1.0, // For spotlight is radius == lenght
    angle_inner: f32 = 80,
    angle_outer: f32 = 90,
};

pub const LightCdb = cdb.CdbTypeDecl(
    "ct_light_component",
    enum(u32) {
        Type = 0,
        Radius,
        Color,
        Power,
        AngleInner,
        AngleOuter,
    },
    struct {},
);

pub const LightAPI = struct {};
