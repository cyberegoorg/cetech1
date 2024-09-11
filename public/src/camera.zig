const std = @import("std");
const zm = @import("math.zig");

pub const SimpleFPSCamera = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    forward: [3]f32 = .{ 0.0, 0.0, 0.0 },
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    move_speed: f32 = 5.0,
    look_speed: f32 = 0.0025,

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
            self.pitch += self.look_speed * mouse_delta[1] * -1;
            self.yaw += self.look_speed * mouse_delta[0] * -1;
            self.pitch = @min(self.pitch, 0.48 * std.math.pi);
            self.pitch = @max(self.pitch, -0.48 * std.math.pi);
            self.yaw = zm.modAngle(self.yaw);

            self.calcForward();
        }

        // Move handle
        {
            var forward = zm.loadArr3(self.forward);
            const right = speed * delta_time * -zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 1.0), forward));
            forward = speed * delta_time * forward;

            var cam_pos = zm.loadArr3(self.position);
            cam_pos += forward * zm.f32x4s(move[1]);
            cam_pos += right * zm.f32x4s(move[0]);
            zm.storeArr3(&self.position, cam_pos);
        }
    }

    pub fn calcViewMtx(self: SimpleFPSCamera) [16]f32 {
        const viewMtx = zm.lookAtRh(
            zm.loadArr3(self.position),
            zm.loadArr3(self.position) + zm.loadArr3(self.forward),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );
        return zm.matToArr(viewMtx);
    }

    inline fn calcForward(self: *SimpleFPSCamera) void {
        const t = zm.mul(zm.rotationX(self.pitch), zm.rotationY(self.yaw));
        const forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 1.0), t));
        zm.storeArr3(&self.forward, forward);
    }
};
