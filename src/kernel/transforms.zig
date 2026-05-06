const std = @import("std");

const zm = @import("zmath");
const vectors = @import("vectors.zig");

const F32x4 = vectors.F32x4;
const Vec3f = vectors.Vec3f;

pub const Quatf = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 1,

    const Self = @This();

    pub fn toF32x4(self: Self) F32x4 {
        return @bitCast(self);
    }

    pub fn fromF32x4(value: F32x4) Self {
        return @bitCast(value);
    }

    pub fn toMat(self: Self) Mat44f {
        return .fromF32x4x4(zm.quatToMat(self.toF32x4()));
    }

    pub fn fromMat(mat: Mat44f) Self {
        return .fromF32x4(zm.quatFromMat(mat.toF32x4x4()));
    }

    pub fn toArray(self: Self) [4]f32 {
        return @bitCast(self);
    }

    pub fn fromArray(v: [4]f32) Self {
        return @bitCast(v);
    }

    pub fn fromRollPitchYaw(pitch: f32, yaw: f32, roll: f32) Self {
        return .fromF32x4(zm.quatFromRollPitchYaw(pitch, yaw, roll));
    }

    pub fn toRollPitchYaw(self: Self) Vec3f {
        return .fromArray(zm.quatToRollPitchYaw(self.toF32x4()));
    }

    pub fn fromAxisAngle(axis: Vec3f, angle: f32) Self {
        return .fromF32x4(zm.quatFromAxisAngle(axis.toF32x4(), angle));
    }

    pub fn mul(self: Self, b: Self) Self {
        return .fromF32x4(zm.qmul(self.toF32x4(), b.toF32x4()));
    }

    pub fn rotateVec3(self: Self, v: Vec3f) Vec3f {
        return .fromF32x4(zm.rotate(self.toF32x4(), v.toF32x4()));
    }

    pub fn getAxisX(self: Self) Vec3f {
        return self.rotateVec3(.right).normalized();
    }

    pub fn getAxisY(self: Self) Vec3f {
        return self.rotateVec3(.up).normalized();
    }

    pub fn getAxisZ(self: Self) Vec3f {
        return self.rotateVec3(.forward).normalized();
    }

    pub fn slerp(self: Self, b: Self, t: f32) Self {
        return .fromF32x4(zm.slerp(self.toF32x4(), b.toF32x4(), t));
    }

    pub fn inverse(self: Self) Self {
        return .fromF32x4(zm.inverse(self.toF32x4()));
    }

    pub fn lookAt(origin: Vec3f, focus_point: Vec3f, up: Vec3f) Self {
        const front = focus_point.sub(origin).normalized();
        const right = up.cross(front).normalized();
        const upp = front.cross(right).normalized();

        return .fromMat(Mat44f{
            .xx = right.x,
            .xy = right.y,
            .xz = right.z,

            .yx = upp.x,
            .yy = upp.y,
            .yz = upp.z,

            .zx = front.x,
            .zy = front.y,
            .zz = front.z,
        });
    }
};

pub const Mat44f = extern struct {
    xx: f32 = 1,
    xy: f32 = 0,
    xz: f32 = 0,
    xw: f32 = 0,

    yx: f32 = 0,
    yy: f32 = 1,
    yz: f32 = 0,
    yw: f32 = 0,

    zx: f32 = 0,
    zy: f32 = 0,
    zz: f32 = 1,
    zw: f32 = 0,

    wx: f32 = 0,
    wy: f32 = 0,
    wz: f32 = 0,
    ww: f32 = 1,

    const Self = @This();

    pub const identity: Self = .{};

    pub fn toArray(self: Self) [16]f32 {
        return @bitCast(self);
    }

    pub fn fromArray(v: [16]f32) Self {
        return @bitCast(v);
    }

    pub fn toF32x4x4(self: Self) [4]F32x4 {
        return @bitCast(self);
    }

    pub fn fromF32x4x4(value: [4]F32x4) Self {
        return @bitCast(value);
    }

    pub fn perspectiveFovLh(fovy: f32, aspect: f32, near: f32, far: f32, homogenous_depth: bool) Self {
        return .fromF32x4x4(
            if (homogenous_depth) zm.perspectiveFovLhGl(
                fovy,
                aspect,
                near,
                far,
            ) else zm.perspectiveFovLh(
                fovy,
                aspect,
                near,
                far,
            ),
        );
    }

    pub fn orthographicLh(w: f32, h: f32, near: f32, far: f32, homogenous_depth: bool) Self {
        return .fromF32x4x4(
            if (homogenous_depth) zm.orthographicLhGl(
                w,
                h,
                near,
                far,
            ) else zm.orthographicLh(
                w,
                h,
                near,
                far,
            ),
        );
    }

    pub fn orthographicOffCenterLh(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32, homogenous_depth: bool) Self {
        return .fromF32x4x4(
            if (homogenous_depth) zm.orthographicOffCenterLhGl(
                left,
                right,
                top,
                bottom,
                near,
                far,
            ) else zm.orthographicOffCenterLh(
                left,
                right,
                top,
                bottom,
                near,
                far,
            ),
        );
    }

    pub fn orthographicOffCenterRh(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32, homogenous_depth: bool) Self {
        return .fromF32x4x4(
            if (homogenous_depth) zm.orthographicOffCenterRhGl(
                left,
                right,
                top,
                bottom,
                near,
                far,
            ) else zm.orthographicOffCenterRh(
                left,
                right,
                top,
                bottom,
                near,
                far,
            ),
        );
    }

    pub fn rotationX(angle: f32) Self {
        return .fromF32x4x4(zm.rotationX(angle));
    }

    pub fn rotationY(angle: f32) Self {
        return .fromF32x4x4(zm.rotationX(angle));
    }

    pub fn rotationZ(angle: f32) Self {
        return .fromF32x4x4(zm.rotationX(angle));
    }

    pub fn mul(self: Self, b: Self) Self {
        return .fromF32x4x4(zm.mul(self.toF32x4x4(), b.toF32x4x4()));
    }

    pub fn getTranslation(self: Self) Vec3f {
        return .fromF32x4(zm.util.getTranslationVec(self.toF32x4x4()));
    }

    pub fn getScale(self: Self) Vec3f {
        return .fromF32x4(zm.util.getScaleVec(self.toF32x4x4()));
    }

    pub fn getRotation(self: Self) Quatf {
        return .fromF32x4(zm.util.getRotationQuat(self.toF32x4x4()));
    }
};

pub const Transform = extern struct {
    const Self = @This();

    position: Vec3f = .{},
    _pad0: f32 = 0,
    rotation: Quatf = .{},
    scale: Vec3f = .{ .x = 1, .y = 1, .z = 1 },
    _pad1: f32 = 0,

    pub fn fromPosRot(position: Vec3f, rotation: Vec3f) Self {
        return .{
            .position = position,
            .rotation = .fromRollPitchYaw(rotation.x, rotation.y, rotation.z),
        };
    }

    pub fn toMat(self: Self) Mat44f {
        const translate_model_mat = zm.translation(self.position.x, self.position.y, self.position.z);
        const rot_model_mat = self.rotation.toMat().toF32x4x4();
        const scl_model_mat = zm.scaling(self.scale.x, self.scale.y, self.scale.z);

        var m = translate_model_mat;
        m = zm.mul(rot_model_mat, m);
        m = zm.mul(scl_model_mat, m);
        return .fromF32x4x4(m);
    }

    pub fn mulTransform(self: Self, other: Self) Self {
        return .{
            .position = other.rotation.rotateVec3(other.scale.mul(self.position)).add(other.position),
            .rotation = self.rotation.mul(other.rotation),
            .scale = other.scale.mul(self.scale),
        };
    }

    pub fn mulVec(self: Self, other: Vec3f) Vec3f {
        return self.rotation.rotateVec3(self.scale.mul(other));
    }

    pub fn blendTransform(self: *const Self, b: Self, t: f32) Self {
        if (t <= 0.0001) {
            return self.*;
        } else if (t > 1.0 - 0.0001) {
            return b;
        }

        return .{
            .position = self.position.lerp(b.position, t),
            .rotation = self.rotation.slerp(b.rotation, t),
            .scale = self.scale.lerp(b.scale, t),
        };
    }

    pub fn inverse(self: Self) Self {
        const inv_rot = self.rotation.inverse();
        const inv_scale = self.scale.inverse();

        return .{
            .position = inv_rot.rotateVec3(inv_scale.mul(self.position.negative())),
            .rotation = inv_rot,
            .scale = inv_scale,
        };
    }

    pub fn getAxisX(self: Self) Vec3f {
        return self.rotation.rotateVec3(.right).normalized();
    }

    pub fn getAxisY(self: Self) Vec3f {
        return self.rotation.rotateVec3(.up).normalized();
    }

    pub fn getAxisZ(self: Self) Vec3f {
        return self.rotation.rotateVec3(.forward).normalized();
    }
};
