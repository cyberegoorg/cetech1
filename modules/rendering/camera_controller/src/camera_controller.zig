const std = @import("std");

const cetech1 = @import("cetech1");
const zm = cetech1.math.zmath;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const camera = @import("camera");

pub const CameraController = struct {
    input_enabled: bool = false,
    camera_look_activated: bool = false,
    move_speed: f32 = 5.0,
    look_speed: f32 = 0.4,
};

pub const CameraControllerAPI = struct {};
