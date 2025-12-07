const std = @import("std");

const cetech1 = @import("cetech1");
const zm = cetech1.math.zmath;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

pub const CameraType = enum(u8) {
    perspective = 0,
    ortho,
};

pub const Camera = struct {
    type: CameraType = .perspective,
    fov: f32 = 60,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

pub const CameraCdb = cdb.CdbTypeDecl(
    "ct_camera",
    enum(u32) {
        Type = 0,
        Fov,
        Near,
        Far,
    },
    struct {},
);

pub const CameraAPI = struct {
    perspectiveFov: *const fn (fovy: f32, aspect: f32, near: f32, far: f32, homogenous_depth: bool) zm.Mat,
    orthographic: *const fn (w: f32, h: f32, near: f32, far: f32, homogenous_depth: bool) zm.Mat,

    cameraSetingsMenu: *const fn (world: ecs.World, camera_ent: ecs.EntityId) void,
    selectMainCameraMenu: *const fn (allocator: std.mem.Allocator, world: ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,
    cameraMenu: *const fn (allocator: std.mem.Allocator, world: ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,
};
