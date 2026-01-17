const std = @import("std");

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

const camera = @import("camera");

const CameraControlerTypr = enum(u8) {
    FreeFlight = 0,
    Orbital,
};

pub const CameraController = struct {
    type: CameraControlerTypr = .FreeFlight,
    input_enabled: bool = false,

    move_speed: f32 = 5.0,
    look_speed: f32 = 0.4,

    position: math.Vec3f = .{},
    rotation: math.Vec3f = .{},

    focus_point: math.Vec3f = .{},
    zoom: f32 = 12,

    camera_look_activated: bool = false,
};

pub const CameraControllerAPI = struct {};
