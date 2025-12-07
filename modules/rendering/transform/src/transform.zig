const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const zm = cetech1.math.zm;

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

pub const Transform = struct {
    position: Position = .{},
    rotation: Rotation = .{},
    scale: Scale = .{},

    pub fn toMat(self: *const Transform) zm.Mat {
        const translate_model_mat = zm.translation(self.position.x, self.position.y, self.position.z);
        const rot_model_mat = zm.quatToMat(self.rotation.q);
        const scl_model_mat = zm.scaling(self.scale.x, self.scale.y, self.scale.z);

        var m = translate_model_mat;
        m = zm.mul(rot_model_mat, m);
        m = zm.mul(scl_model_mat, m);
        return m;
    }
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

pub const TransformCdb = cdb.CdbTypeDecl(
    "ct_transform",
    enum(u32) {
        Position = 0,
        Rotation,
        Scale,
    },
    struct {},
);
