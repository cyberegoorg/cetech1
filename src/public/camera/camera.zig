const std = @import("std");

const cetech1 = @import("../cetech1.zig");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;
const apidb = cetech1.apidb;

pub const CameraType = enum(u8) {
    Perspective = 0,
    Ortho,
};

pub const Camera = extern struct {
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

pub fn projectionMatrixFromCamera(camera: Camera, w: f32, h: f32, homogenous_depth: bool) math.Mat44f {
    return api.projectionMatrixFromCamera(camera, w, h, homogenous_depth);
}
pub fn cameraSetingsMenu(world: *ecs.World, camera_ent: ecs.EntityId) void {
    return api.cameraSetingsMenu(world, camera_ent);
}
pub fn selectMainCameraMenu(allocator: std.mem.Allocator, world: *ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId {
    return api.selectMainCameraMenu(allocator, world, camera_ent, current_main_camera);
}
pub fn cameraMenu(allocator: std.mem.Allocator, world: *ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId {
    return api.cameraMenu(allocator, world, camera_ent, current_main_camera);
}

pub const CameraAPI = struct {
    projectionMatrixFromCamera: *const fn (camera: Camera, w: f32, h: f32, homogenous_depth: bool) math.Mat44f,
    cameraSetingsMenu: *const fn (world: *ecs.World, camera_ent: ecs.EntityId) void,
    selectMainCameraMenu: *const fn (allocator: std.mem.Allocator, world: *ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,
    cameraMenu: *const fn (allocator: std.mem.Allocator, world: *ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,
};

pub var api: *const CameraAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, CameraAPI).?;
}
