const std = @import("std");
const zm = @import("zmath");
const vectors = @import("vectors.zig");
const transforms = @import("transforms.zig");

const F32x4 = vectors.F32x4;
const Vec3f = vectors.Vec3f;
const Vec2f = vectors.Vec2f;
const Mat44f = transforms.Mat44f;
const Transform = transforms.Transform;

//
// Rectangle
//
pub const Rectf = Rect(f32);
pub fn Rect(comptime T: type) type {
    return extern struct {
        x: T = 0,
        y: T = 0,
        w: T = 0,
        h: T = 0,

        const Self = @This();

        pub fn isPointIn(self: Self, point: Vec2f) bool {
            return (point.x >= self.x and point.x <= self.x + self.w) and
                (point.y >= self.y and point.y <= self.y + self.h);
        }
    };
}

//
// Sphere
//
pub const Spheref = Sphere(f32);
pub fn Sphere(comptime T: type) type {
    return extern struct {
        center: Vec3f = .{},
        radius: T = 0,

        const Self = @This();

        // From: https://bartwronski.com/2017/04/13/cull-that-cone/
        pub fn calcBoundingSphereForCone(origin: Vec3f, forward: Vec3f, size: f32, angle: f32) Self {
            var sphere: Self = .{};

            const cos_angle = std.math.cos(angle);

            if (angle > std.math.pi / 4.0) {
                sphere.radius = std.math.sin(angle) * size;
                sphere.center = .mulAdd(forward, .splat(cos_angle * size), origin);
            } else {
                sphere.radius = size / (2.0 * cos_angle);
                sphere.center = .mulAdd(forward, .splat(sphere.radius), origin);
            }

            return sphere;
        }
    };
}

//
// Plane
//
pub const Plane = struct {
    v: zm.Vec = @splat(0),

    pub fn getDistance(self: Plane) f32 {
        return self.v[3];
    }
};

//
// Frustrum
//
pub const FrustumPlanes = struct {
    p: [6]Plane = @splat(.{}),

    const Self = @This();

    pub fn fromMat44(mtxx: Mat44f) Self {
        var planes: [6]Plane = @splat(.{});
        var near = &planes[0];
        var far = &planes[1];
        var left = &planes[2];
        var right = &planes[3];
        var top = &planes[4];
        var bottom = &planes[5];

        const mtx = mtxx.toArray();

        const x = zm.Vec{
            mtx[0],
            mtx[4],
            mtx[8],
            mtx[12],
        };

        const y = zm.Vec{
            mtx[1],
            mtx[5],
            mtx[9],
            mtx[13],
        };

        const z = zm.Vec{
            mtx[2],
            mtx[6],
            mtx[10],
            mtx[14],
        };
        const w = zm.Vec{
            mtx[3],
            mtx[7],
            mtx[11],
            mtx[15],
        };

        near.v = w - z;
        far.v = w + z;

        left.v = w - x;
        right.v = w + x;

        top.v = w + y;
        bottom.v = w - y;

        inline for (0..6) |idx| {
            const dist = planes[idx].getDistance();
            const invLen = 1.0 / zm.length3(planes[idx].v)[0];
            planes[idx].v = zm.normalize3(planes[idx].v);
            planes[idx].v[3] = dist * invLen;
        }

        return .{ .p = planes };
    }

    pub fn vsSphereNaive(self: FrustumPlanes, sphere: Spheref) bool {
        for (0..6) |idx| {
            const world_space_point = sphere.center.toF32x4();
            const dot = zm.dot3(world_space_point, self.p[idx].v);
            const dist = dot[0] + self.p[idx].v[3] + sphere.radius;

            if (dist < 0) return false;
        }
        return true;
    }

    pub fn vsOBBNaive(
        self: FrustumPlanes,
        transform: Transform,
        min: Vec3f,
        max: Vec3f,
    ) bool {
        var points: [8]zm.Vec = .{
            zm.loadArr3(.{ min.x, min.y, min.z }),
            zm.loadArr3(.{ max.x, min.y, min.z }),
            zm.loadArr3(.{ max.x, max.y, min.z }),
            zm.loadArr3(.{ min.x, max.y, min.z }),
            zm.loadArr3(.{ min.x, min.y, max.z }),
            zm.loadArr3(.{ max.x, min.y, max.z }),
            zm.loadArr3(.{ max.x, max.y, max.z }),
            zm.loadArr3(.{ min.x, max.y, max.z }),
        };

        for (&points) |*p| {
            p.* = transform.mulVec(.fromF32x4(p.*)).toF32x4();
        }

        for (0..6) |idx| {
            var inside = false;

            const plane_normal = self.p[idx].v;

            for (points) |point| {
                if (zm.dot3(point, plane_normal)[0] > 0) {
                    inside = true;
                    break;
                }
            }
            if (!inside) return false;
        }

        return true;
    }
};
