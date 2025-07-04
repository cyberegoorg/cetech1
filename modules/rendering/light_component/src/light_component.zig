const std = @import("std");

const cetech1 = @import("cetech1");
const zm = cetech1.math.zmath;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

pub const LightType = enum(u8) {
    point = 0,
};

pub const Light = struct {
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    type: LightType = .point,
};

pub const LightCdb = cdb.CdbTypeDecl(
    "ct_light",
    enum(u32) {
        Type = 0,
        Color,
    },
    struct {},
);

pub const LightAPI = struct {};
