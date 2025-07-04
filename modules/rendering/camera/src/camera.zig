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

pub const SimpleFPSCamera = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    forward: [3]f32 = .{ 0.0, 0.0, 0.0 },
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    move_speed: f32 = 5.0,
    look_speed: f32 = 0.4,

    pub fn init(params: SimpleFPSCamera) SimpleFPSCamera {
        var camera = params;
        camera.calcForward();
        return camera;
    }

    pub fn update(self: *SimpleFPSCamera, move: [2]f32, mouse_delta: [2]f32, dt: f32) void {
        const speed = zm.f32x4s(self.move_speed);
        const delta_time = zm.f32x4s(dt);

        // Look handle
        {
            self.pitch += self.look_speed * dt * mouse_delta[1] * -1;
            self.yaw += self.look_speed * dt * mouse_delta[0];
            self.pitch = @min(self.pitch, 0.48 * std.math.pi);
            self.pitch = @max(self.pitch, -0.48 * std.math.pi);
            self.yaw = zm.modAngle(self.yaw);

            self.calcForward();
        }

        // Move handle
        {
            var forward = zm.loadArr3(self.forward);
            const right = speed * delta_time * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 1.0), forward));
            forward = speed * delta_time * forward;

            var cam_pos = zm.loadArr3(self.position);
            cam_pos += forward * zm.f32x4s(move[1]);
            cam_pos += right * zm.f32x4s(move[0]);
            zm.storeArr3(&self.position, cam_pos);
        }
    }

    inline fn calcForward(self: *SimpleFPSCamera) void {
        const t = zm.mul(zm.rotationX(self.pitch), zm.rotationY(self.yaw));
        const forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 1.0), t));
        zm.storeArr3(&self.forward, forward);
    }
};

pub const CameraAPI = struct {
    cameraSetingsMenu: *const fn (world: ecs.World, camera_ent: ecs.EntityId) void,
    selectMainCameraMenu: *const fn (allocator: std.mem.Allocator, world: ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) anyerror!?ecs.EntityId,

    perspectiveFov: *const fn (fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat,
    orthographic: *const fn (w: f32, h: f32, near: f32, far: f32) zm.Mat,
};
