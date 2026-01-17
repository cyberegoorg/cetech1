const std = @import("std");

const zm = @import("zmath");

pub const vectors = @import("math/vectors.zig");
pub const transforms = @import("math/transforms.zig");
pub const geometry = @import("math/geometry.zig");
pub const colors = @import("math/colors.zig");

const log = std.log.scoped(.math);

pub const modAngle = zm.modAngle;

//
// Vectors
//
pub const Vec2f = vectors.Vec2f;
pub const Vec3f = vectors.Vec3f;
pub const Vec4f = vectors.Vec4f;
pub const F32x4 = vectors.F32x4;

//
// Transforms
//
pub const Quatf = transforms.Quatf;
pub const Mat44f = transforms.Mat44f;
pub const Transform = transforms.Transform;

//
// Geometry
//
pub const Rectf = geometry.Rectf;
pub const Spheref = geometry.Spheref;
pub const Plane = geometry.Plane;
pub const FrustumPlanes = geometry.FrustumPlanes;

//
// Colors
//
pub const Color3f = colors.Color3f;
pub const Color4f = colors.Color4f;
pub const SRGBA = colors.SRGBA;
