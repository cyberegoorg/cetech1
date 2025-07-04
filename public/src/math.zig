const std = @import("std");

pub const zmath = @import("zmath");
pub const zm = zmath;

pub const Plane = struct {
    normal: [3]f32 = .{ 0, 0, 0 },
    dist: f32 = 0,
};

pub const FrustumPlanes = [6]Plane;

pub fn frustumPlanesVsSphereNaive(planes: FrustumPlanes, center: [3]f32, radius: f32) bool {
    for (0..6) |idx| {
        const world_space_point = zm.loadArr3(center);
        const plane_normal = zm.loadArr3(planes[idx].normal);
        const dot = zm.dot3(world_space_point, plane_normal);
        const dist = dot[0] + planes[idx].dist + radius;
        if (dist < 0) return false;
    }
    return true;
}

pub fn frustumPlanesVsOBBNaive(
    planes: FrustumPlanes,
    transform: zm.Mat,
    min: [3]f32,
    max: [3]f32,
) bool {
    var points: [8]zm.Vec = .{
        zm.loadArr3(.{ min[0], min[1], min[2] }),
        zm.loadArr3(.{ max[0], min[1], min[2] }),
        zm.loadArr3(.{ max[0], max[1], min[2] }),
        zm.loadArr3(.{ min[0], max[1], min[2] }),
        zm.loadArr3(.{ min[0], min[1], max[2] }),
        zm.loadArr3(.{ max[0], min[1], max[2] }),
        zm.loadArr3(.{ max[0], max[1], max[2] }),
        zm.loadArr3(.{ min[0], max[1], max[2] }),
    };

    for (&points) |*p| {
        p.* = zm.mul(transform, p.*);
    }

    for (0..6) |idx| {
        var inside = false;

        const plane_normal = zm.loadArr3(planes[idx].normal);

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

pub fn buildFrustumPlanes(mtx: [16]f32) FrustumPlanes {
    const xw = mtx[3];
    const yw = mtx[7];
    const zw = mtx[11];
    const ww = mtx[15];
    const xz = mtx[2];
    const yz = mtx[6];
    const zz = mtx[10];
    const wz = mtx[14];

    var planes: [6]Plane = undefined;
    var near = &planes[0];
    var far = &planes[1];
    var left = &planes[2];
    var right = &planes[3];
    var top = &planes[4];
    var bottom = &planes[5];

    near.normal[0] = xw - xz;
    near.normal[1] = yw - yz;
    near.normal[2] = zw - zz;
    near.dist = ww - wz;

    far.normal[0] = xw + xz;
    far.normal[1] = yw + yz;
    far.normal[2] = zw + zz;
    far.dist = ww + wz;

    const xx = mtx[0];
    const yx = mtx[4];
    const zx = mtx[8];
    const wx = mtx[12];

    left.normal[0] = xw - xx;
    left.normal[1] = yw - yx;
    left.normal[2] = zw - zx;
    left.dist = ww - wx;

    right.normal[0] = xw + xx;
    right.normal[1] = yw + yx;
    right.normal[2] = zw + zx;
    right.dist = ww + wx;

    const xy = mtx[1];
    const yy = mtx[5];
    const zy = mtx[9];
    const wy = mtx[13];

    top.normal[0] = xw + xy;
    top.normal[1] = yw + yy;
    top.normal[2] = zw + zy;
    top.dist = ww + wy;

    bottom.normal[0] = xw - xy;
    bottom.normal[1] = yw - yy;
    bottom.normal[2] = zw - zy;
    bottom.dist = ww - wy;

    for (0..6) |idx| {
        const invLen = 1.0 / zm.length3(zm.loadArr3(planes[idx].normal))[0];
        planes[idx].normal = zm.vecToArr3(zm.normalize3(zm.loadArr3(planes[idx].normal)));
        planes[idx].dist *= invLen;
    }

    return planes;
}
