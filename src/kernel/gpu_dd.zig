const std = @import("std");
const cetech1 = @import("../cetech1.zig");
const math = cetech1.math;
const gpu = cetech1.gpu;

const apidb = cetech1.apidb;
pub const Axis = enum(c_int) {
    X,
    Y,
    Z,
    Count,
};

pub const Vertex = cetech1.math.Vec3f;

pub const SpriteHandle = extern struct {
    idx: u16,

    fn isValid(sprite: SpriteHandle) bool {
        return sprite.idx != std.math.maxInt(u16);
    }
};

pub const GeometryHandle = extern struct {
    idx: u16,

    fn isValid(geometry: GeometryHandle) bool {
        return geometry.idx != std.math.maxInt(u16);
    }
};

pub const Encoder = struct {
    //
    pub inline fn begin(dde: Encoder, _viewId: u16, _depthTestLess: bool, _encoder: gpu.GpuEncoder) void {
        dde.vtable.begin(dde.ptr, _viewId, _depthTestLess, _encoder.ptr);
    }

    //
    pub inline fn end(dde: Encoder) void {
        dde.vtable.end(dde.ptr);
    }

    //
    pub inline fn push(dde: Encoder) void {
        dde.vtable.push(dde.ptr);
    }

    //
    pub inline fn pop(dde: Encoder) void {
        dde.vtable.pop(dde.ptr);
    }

    //
    pub inline fn setDepthTestLess(dde: Encoder, _depthTestLess: bool) void {
        dde.vtable.set_depth_test_less(dde.ptr, _depthTestLess);
    }

    //
    pub inline fn setState(dde: Encoder, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void {
        dde.vtable.set_state(dde.ptr, _depthTest, _depthWrite, _clockwise);
    }

    //
    pub inline fn setColor(dde: Encoder, _abgr: math.SRGBA) void {
        dde.vtable.set_color(dde.ptr, _abgr);
    }

    //
    pub inline fn setLod(dde: Encoder, _lod: u8) void {
        dde.vtable.set_lod(dde.ptr, _lod);
    }

    //
    pub inline fn setWireframe(dde: Encoder, _wireframe: bool) void {
        dde.vtable.set_wireframe(dde.ptr, _wireframe);
    }

    //
    pub inline fn setStipple(dde: Encoder, _stipple: bool, _scale: f32, _offset: f32) void {
        dde.vtable.set_stipple(dde.ptr, _stipple, _scale, _offset);
    }

    //
    pub inline fn setSpin(dde: Encoder, _spin: f32) void {
        dde.vtable.set_spin(dde.ptr, _spin);
    }

    //
    pub inline fn setTransform(dde: Encoder, _mtx: math.Mat44f) void {
        dde.vtable.set_transform(dde.ptr, _mtx);
    }

    //
    pub inline fn setTranslate(dde: Encoder, _xyz: math.Vec3f) void {
        dde.vtable.set_translate(dde.ptr, _xyz);
    }

    //
    pub inline fn pushTransform(dde: Encoder, _mtx: math.Mat44f) void {
        dde.vtable.push_transform(dde.ptr, _mtx);
    }

    //
    pub inline fn popTransform(dde: Encoder) void {
        dde.vtable.pop_transform(dde.ptr);
    }

    //
    pub inline fn moveTo(dde: Encoder, _xyz: math.Vec3f) void {
        dde.vtable.move_to(dde.ptr, _xyz);
    }

    //
    pub inline fn lineTo(dde: Encoder, _xyz: math.Vec3f) void {
        dde.vtable.line_to(dde.ptr, _xyz);
    }

    //
    pub inline fn close(dde: Encoder) void {
        dde.vtable.close(dde.ptr);
    }

    ///
    pub inline fn drawAABB(dde: Encoder, min: math.Vec3f, max: math.Vec3f) void {
        dde.vtable.draw_aabb(dde.ptr, min, max);
    }

    ///
    pub inline fn drawCylinder(dde: Encoder, pos: math.Vec3f, _end: math.Vec3f, radius: f32) void {
        dde.vtable.draw_cylinder(dde.ptr, pos, _end, radius);
    }

    ///
    pub inline fn drawCapsule(dde: Encoder, pos: math.Vec3f, _end: math.Vec3f, radius: f32) void {
        dde.vtable.draw_capsule(dde.ptr, pos, _end, radius);
    }

    ///
    pub inline fn drawDisk(dde: Encoder, center: math.Vec3f, normal: math.Vec3f, radius: f32) void {
        dde.vtable.draw_disk(dde.ptr, center, normal, radius);
    }

    ///
    pub inline fn drawObb(dde: Encoder, _obb: math.Vec3f) void {
        dde.vtable.draw_obb(dde.ptr, _obb);
    }

    ///
    pub inline fn drawSphere(dde: Encoder, center: math.Vec3f, radius: f32) void {
        dde.vtable.draw_sphere(dde.ptr, center, radius);
    }

    ///
    pub inline fn drawTriangle(dde: Encoder, v0: math.Vec3f, v1: math.Vec3f, v2: math.Vec3f) void {
        dde.vtable.draw_triangle(dde.ptr, &v0, &v1, &v2);
    }

    ///
    pub inline fn drawCone(dde: Encoder, pos: math.Vec3f, _end: math.Vec3f, radius: f32) void {
        dde.vtable.draw_cone(dde.ptr, pos, _end, radius);
    }

    //
    pub inline fn drawGeometry(dde: Encoder, _handle: GeometryHandle) void {
        dde.vtable.draw_geometry(dde.ptr, _handle);
    }

    ///
    pub inline fn drawLineList(dde: Encoder, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void {
        dde.vtable.draw_line_list(dde.ptr, _numVertices, _vertices.ptr, _numIndices, _indices);
    }

    ///
    pub inline fn drawTriList(dde: Encoder, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void {
        dde.vtable.draw_tri_list(dde.ptr, _numVertices, _vertices.ptr, _numIndices, _indices.?);
    }

    ///
    pub inline fn drawFrustum(dde: Encoder, _viewProj: math.Mat44f) void {
        dde.vtable.draw_frustum(dde.ptr, _viewProj);
    }

    ///
    pub inline fn drawArc(dde: Encoder, _axis: Axis, _xyz: math.Vec3f, _radius: f32, _degrees: f32) void {
        dde.vtable.draw_arc(dde.ptr, _axis, _xyz, _radius, _degrees);
    }

    ///
    pub inline fn drawCircle(dde: Encoder, _normal: math.Vec3f, _center: math.Vec3f, _radius: f32, _weight: f32) void {
        dde.vtable.draw_circle(dde.ptr, _normal, _center, _radius, _weight);
    }

    ///
    pub inline fn drawCircleAxis(dde: Encoder, _axis: Axis, _xyz: math.Vec3f, _radius: f32, _weight: f32) void {
        dde.vtable.draw_circle_axis(dde.ptr, _axis, _xyz, _radius, _weight);
    }

    ///
    pub inline fn drawQuad(dde: Encoder, _normal: math.Vec3f, _center: math.Vec3f, _size: f32) void {
        dde.vtable.draw_quad(dde.ptr, _normal, _center, _size);
    }

    ///
    pub inline fn drawQuadSprite(dde: Encoder, _handle: SpriteHandle, _normal: math.Vec3f, _center: math.Vec3f, _size: f32) void {
        dde.vtable.draw_quad_sprite(dde.ptr, _handle, _normal, _center, _size);
    }

    ///
    pub inline fn drawQuadTexture(dde: Encoder, _handle: gpu.TextureHandle, _normal: math.Vec3f, _center: math.Vec3f, _size: f32) void {
        dde.vtable.draw_quad_texture(dde.ptr, _handle, _normal, _center, _size);
    }

    ///
    pub inline fn drawAxis(dde: Encoder, _xyz: math.Vec3f, _len: f32, _highlight: Axis, _thickness: f32) void {
        dde.vtable.draw_axis(dde.ptr, _xyz, _len, _highlight, _thickness);
    }

    ///
    pub inline fn drawGrid(dde: Encoder, _normal: math.Vec3f, _center: math.Vec3f, _size: u32, _step: f32) void {
        dde.vtable.draw_grid(dde.ptr, _normal, _center, _size, _step);
    }

    ///
    pub inline fn drawGridAxis(dde: Encoder, _axis: Axis, _center: math.Vec3f, _size: u32, _step: f32) void {
        dde.vtable.draw_grid_axis(dde.ptr, _axis, _center, _size, _step);
    }

    ///
    pub inline fn drawOrb(dde: Encoder, _xyz: math.Vec3f, _radius: f32, _highlight: Axis) void {
        dde.vtable.draw_orb(dde.ptr, _xyz, _radius, _highlight);
    }

    pub fn implement(comptime T: type) VTable {
        return VTable{
            .begin = T.begin,
            .end = T.end,
            .push = T.push,
            .pop = T.pop,
            .set_depth_test_less = T.setDepthTestLess,
            .set_state = T.setState,
            .set_color = T.setColor,
            .set_lod = T.setLod,
            .set_wireframe = T.setWireframe,
            .set_stipple = T.setStipple,
            .set_spin = T.setSpin,
            .set_transform = T.setTransform,
            .set_translate = T.setTranslate,
            .push_transform = T.pushTransform,
            .pop_transform = T.popTransform,
            .move_to = T.moveTo,
            .line_to = T.lineTo,
            .close = T.close,
            .draw_aabb = T.drawAABB,
            .draw_cylinder = T.drawCylinder,
            .draw_capsule = T.drawCapsule,
            .draw_disk = T.drawDisk,
            .draw_obb = T.drawObb,
            .draw_sphere = T.drawSphere,
            .draw_triangle = T.drawTriangle,
            .draw_cone = T.drawCone,
            .draw_geometry = T.drawGeometry,
            .draw_line_list = T.drawLineList,
            .draw_tri_list = T.drawTriList,
            .draw_frustum = T.drawFrustum,
            .draw_arc = T.drawArc,
            .draw_circle = T.drawCircle,
            .draw_circle_axis = T.drawCircleAxis,
            .draw_quad = T.drawQuad,
            .draw_quad_sprite = T.drawQuadSprite,
            .draw_quad_texture = T.drawQuadTexture,
            .draw_axis = T.drawAxis,
            .draw_grid = T.drawGrid,
            .draw_grid_axis = T.drawGridAxis,
            .draw_orb = T.drawOrb,
        };
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        begin: *const fn (dde: *anyopaque, _viewId: u16, _depthTestLess: bool, _encoder: *anyopaque) void,
        end: *const fn (dde: *anyopaque) void,
        push: *const fn (dde: *anyopaque) void,
        pop: *const fn (dde: *anyopaque) void,
        set_depth_test_less: *const fn (dde: *anyopaque, _depthTestLess: bool) void,
        set_state: *const fn (dde: *anyopaque, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void,
        set_color: *const fn (dde: *anyopaque, _abgr: math.SRGBA) void,
        set_lod: *const fn (dde: *anyopaque, _lod: u8) void,
        set_wireframe: *const fn (dde: *anyopaque, _wireframe: bool) void,
        set_stipple: *const fn (dde: *anyopaque, _stipple: bool, _scale: f32, _offset: f32) void,
        set_spin: *const fn (dde: *anyopaque, _spin: f32) void,
        set_transform: *const fn (dde: *anyopaque, _mtx: math.Mat44f) void,
        set_translate: *const fn (dde: *anyopaque, _xyz: math.Vec3f) void,
        push_transform: *const fn (dde: *anyopaque, _mtx: math.Mat44f) void,
        pop_transform: *const fn (dde: *anyopaque) void,
        move_to: *const fn (dde: *anyopaque, _xyz: math.Vec3f) void,
        line_to: *const fn (dde: *anyopaque, _xyz: math.Vec3f) void,
        close: *const fn (dde: *anyopaque) void,
        draw_aabb: *const fn (dde: *anyopaque, min: math.Vec3f, max: math.Vec3f) void,
        draw_cylinder: *const fn (dde: *anyopaque, pos: math.Vec3f, _end: math.Vec3f, radius: f32) void,
        draw_capsule: *const fn (dde: *anyopaque, pos: math.Vec3f, _end: math.Vec3f, radius: f32) void,
        draw_disk: *const fn (dde: *anyopaque, center: math.Vec3f, normal: math.Vec3f, radius: f32) void,
        draw_obb: *const fn (dde: *anyopaque, _obb: math.Vec3f) void,
        draw_sphere: *const fn (dde: *anyopaque, center: math.Vec3f, radius: f32) void,
        draw_triangle: *const fn (dde: *anyopaque, v0: math.Vec3f, v1: math.Vec3f, v2: math.Vec3f) void,
        draw_cone: *const fn (dde: *anyopaque, pos: math.Vec3f, _end: math.Vec3f, radius: f32) void,
        draw_geometry: *const fn (dde: *anyopaque, _handle: GeometryHandle) void,
        draw_line_list: *const fn (dde: *anyopaque, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void,
        draw_tri_list: *const fn (dde: *anyopaque, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void,
        draw_frustum: *const fn (dde: *anyopaque, _viewProj: math.Mat44f) void,
        draw_arc: *const fn (dde: *anyopaque, _axis: Axis, _xyz: math.Vec3f, _radius: f32, _degrees: f32) void,
        draw_circle: *const fn (dde: *anyopaque, _normal: math.Vec3f, _center: math.Vec3f, _radius: f32, _weight: f32) void,
        draw_circle_axis: *const fn (dde: *anyopaque, _axis: Axis, _xyz: math.Vec3f, _radius: f32, _weight: f32) void,
        draw_quad: *const fn (dde: *anyopaque, _normal: math.Vec3f, _center: math.Vec3f, _size: f32) void,
        draw_quad_sprite: *const fn (dde: *anyopaque, _handle: SpriteHandle, _normal: math.Vec3f, _center: math.Vec3f, _size: f32) void,
        draw_quad_texture: *const fn (dde: *anyopaque, _handle: gpu.TextureHandle, _normal: math.Vec3f, _center: math.Vec3f, _size: f32) void,
        draw_axis: *const fn (dde: *anyopaque, _xyz: math.Vec3f, _len: f32, _highlight: Axis, _thickness: f32) void,
        draw_grid: *const fn (dde: *anyopaque, _normal: math.Vec3f, _center: math.Vec3f, _size: u32, _step: f32) void,
        draw_grid_axis: *const fn (dde: *anyopaque, _axis: Axis, _center: math.Vec3f, _size: u32, _step: f32) void,
        draw_orb: *const fn (dde: *anyopaque, _xyz: math.Vec3f, _radius: f32, _highlight: Axis) void,
    };
};

pub fn createSprite(width: u16, height: u16, _data: []const u8) SpriteHandle {
    return api.create_sprite(width, height, _data);
}
pub fn destroySprite(handle: SpriteHandle) void {
    return api.destroy_sprite(handle);
}
pub fn createGeometry(numVertices: u32, vertices: []const Vertex, numIndices: u32, indices: ?[*]const u8, index32: bool) GeometryHandle {
    return api.create_geometry(numVertices, vertices, numIndices, indices, index32);
}
pub fn destroyGeometry(handle: GeometryHandle) void {
    return api.destroy_geometry(handle);
}
pub fn encoderCreate() Encoder {
    return api.encoder_create();
}
pub fn encoderDestroy(encoder: Encoder) void {
    return api.encoder_destroy(encoder);
}

pub const GpuDDApi = struct {
    create_sprite: *const fn (width: u16, height: u16, _data: []const u8) SpriteHandle,
    destroy_sprite: *const fn (handle: SpriteHandle) void,
    create_geometry: *const fn (numVertices: u32, vertices: []const Vertex, numIndices: u32, indices: ?[*]const u8, index32: bool) GeometryHandle,
    destroy_geometry: *const fn (handle: GeometryHandle) void,
    encoder_create: *const fn () Encoder,
    encoder_destroy: *const fn (encoder: Encoder) void,
};

pub var api: *const GpuDDApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, GpuDDApi).?;
}
