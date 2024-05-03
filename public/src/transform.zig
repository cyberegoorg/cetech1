const std = @import("std");

const strid = @import("strid.zig");
const math = @import("math.zig");

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
