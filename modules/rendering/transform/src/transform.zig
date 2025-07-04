const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const math = cetech1.math.zmath;

pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const Rotation = struct {
    q: math.Quat = math.qidentity(),
};

pub const Scale = struct {
    x: f32 = 1,
    y: f32 = 1,
    z: f32 = 1,
};

pub const WorldTransform = struct {
    mtx: math.Mat = math.identity(),
};

pub const PositionCdb = cdb.CdbTypeDecl(
    "ct_position",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {},
);

pub const ScaleCdb = cdb.CdbTypeDecl(
    "ct_scale",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {},
);

pub const RotationCdb = cdb.CdbTypeDecl(
    "ct_rotation",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {},
);
