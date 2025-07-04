const std = @import("std");

const cetech1 = @import("cetech1");
const zm = cetech1.math.zmath;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

pub const LightType = enum(u8) {
    point = 0,
    spot = 1,
    direction = 2,
};

pub const Light = struct {
    type: LightType = .point,
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
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
