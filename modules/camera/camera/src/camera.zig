const std = @import("std");

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

pub const CameraType = enum(u8) {
    Perspective = 0,
    Ortho,
};

pub const Camera = struct {
    type: CameraType = .Perspective,
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
    projectionMatrixFromCamera: *const fn (camera: Camera, w: f32, h: f32, homogenous_depth: bool) math.Mat44f,

    cameraSetingsMenu: *const fn (world: ecs.World, camera_ent: ecs.EntityId) void,
    selectMainCameraMenu: *const fn (allocator: std.mem.Allocator, world: ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,
    cameraMenu: *const fn (allocator: std.mem.Allocator, world: ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,
};
