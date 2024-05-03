const std = @import("std");

const gpu = @import("gpu.zig");

pub const Axis = enum(c_int) {
    X,
    Y,
    Z,
    Count,
};

pub const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

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
    pub inline fn begin(dde: Encoder, _viewId: u16, _depthTestLess: bool, _encoder: gpu.Encoder) void {
        dde.vtable.encoderBegin(dde.ptr, _viewId, _depthTestLess, _encoder.ptr);
    }

    //
    pub inline fn end(dde: Encoder) void {
        dde.vtable.encoderEnd(dde.ptr);
    }

    //
    pub inline fn push(dde: Encoder) void {
        dde.vtable.encoderPush(dde.ptr);
    }

    //
    pub inline fn pop(dde: Encoder) void {
        dde.vtable.encoderPop(dde.ptr);
    }

    //
    pub inline fn setDepthTestLess(dde: Encoder, _depthTestLess: bool) void {
        dde.vtable.encoderSetDepthTestLess(dde.ptr, _depthTestLess);
    }

    //
    pub inline fn setState(dde: Encoder, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void {
        dde.vtable.encoderSetState(dde.ptr, _depthTest, _depthWrite, _clockwise);
    }

    //
    pub inline fn setColor(dde: Encoder, _abgr: u32) void {
        dde.vtable.encoderSetColor(dde.ptr, _abgr);
    }

    //
    pub inline fn setLod(dde: Encoder, _lod: u8) void {
        dde.vtable.encoderSetLod(dde.ptr, _lod);
    }

    //
    pub inline fn setWireframe(dde: Encoder, _wireframe: bool) void {
        dde.vtable.encoderSetWireframe(dde.ptr, _wireframe);
    }

    //
    pub inline fn setStipple(dde: Encoder, _stipple: bool, _scale: f32, _offset: f32) void {
        dde.vtable.encoderSetStipple(dde.ptr, _stipple, _scale, _offset);
    }

    //
    pub inline fn setSpin(dde: Encoder, _spin: f32) void {
        dde.vtable.encoderSetSpin(dde, _spin);
    }

    //
    pub inline fn setTransform(dde: Encoder, _mtx: ?*const anyopaque) void {
        dde.vtable.encoderSetTransform(dde.ptr, _mtx);
    }

    //
    pub inline fn setTranslate(dde: Encoder, _xyz: [3]f32) void {
        dde.vtable.encoderSetTranslate(dde.ptr, _xyz[0], _xyz[1], _xyz[2]);
    }

    //
    pub inline fn pushTransform(dde: Encoder, _mtx: *const anyopaque) void {
        dde.vtable.encoderPushTransform(dde.ptr, _mtx);
    }

    //
    pub inline fn popTransform(dde: Encoder) void {
        dde.vtable.encoderPopTransform(dde.ptr);
    }

    //
    pub inline fn moveTo(dde: Encoder, _xyz: [3]f32) void {
        dde.vtable.encoderMoveTo(dde.ptr, _xyz[0], _xyz[1], _xyz[2]);
    }

    //
    pub inline fn lineTo(dde: Encoder, _xyz: [3]f32) void {
        dde.vtable.encoderLineTo(dde.ptr, _xyz[0], _xyz[1], _xyz[2]);
    }

    //
    pub inline fn close(dde: Encoder) void {
        dde.vtable.encoderClose(dde.ptr);
    }

    ///
    pub inline fn drawAABB(dde: Encoder, min: [3]f32, max: [3]f32) void {
        dde.vtable.encoderDrawAABB(dde.ptr, min, max);
    }

    ///
    pub inline fn drawCylinder(dde: Encoder, pos: [3]f32, _end: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawCylinder(dde.ptr, pos, _end, radius);
    }

    ///
    pub inline fn drawCapsule(dde: Encoder, pos: [3]f32, _end: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawCapsule(dde.ptr, pos, _end, radius);
    }

    ///
    pub inline fn drawDisk(dde: Encoder, center: [3]f32, normal: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawDisk(dde.ptr, center, normal, radius);
    }

    ///
    pub inline fn drawObb(dde: Encoder, _obb: [3]f32) void {
        dde.vtable.encoderDrawObb(dde.ptr, _obb);
    }

    ///
    pub inline fn drawSphere(dde: Encoder, center: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawSphere(dde.ptr, center, radius);
    }

    ///
    pub inline fn drawTriangle(dde: Encoder, v0: [3]f32, v1: [3]f32, v2: [3]f32) void {
        dde.vtable.encoderDrawTriangle(dde.ptr, &v0, &v1, &v2);
    }

    ///
    pub inline fn drawCone(dde: Encoder, pos: [3]f32, _end: [3]f32, radius: f32) void {
        dde.vtable.encoderDrawCone(dde.ptr, pos, _end, radius);
    }

    //
    pub inline fn drawGeometry(dde: Encoder, _handle: GeometryHandle) void {
        dde.vtable.encoderDrawGeometry(dde.ptr, _handle);
    }

    ///
    pub inline fn drawLineList(dde: Encoder, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void {
        dde.vtable.encoderDrawLineList(dde.ptr, _numVertices, _vertices.ptr, _numIndices, _indices);
    }

    ///
    pub inline fn drawTriList(dde: Encoder, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void {
        dde.vtable.encoderDrawTriList(dde.ptr, _numVertices, _vertices.ptr, _numIndices, _indices.?);
    }

    ///
    pub inline fn drawFrustum(dde: Encoder, _viewProj: []f32) void {
        dde.vtable.encoderDrawFrustum(dde.ptr, _viewProj.ptr);
    }

    ///
    pub inline fn drawArc(dde: Encoder, _axis: Axis, _xyz: [3]f32, _radius: f32, _degrees: f32) void {
        dde.vtable.encoderDrawArc(dde.ptr, _axis, _xyz[0], _xyz[1], _xyz[2], _radius, _degrees);
    }

    ///
    pub inline fn drawCircle(dde: Encoder, _normal: [3]f32, _center: [3]f32, _radius: f32, _weight: f32) void {
        dde.vtable.encoderDrawCircle(dde.ptr, _normal, _center, _radius, _weight);
    }

    ///
    pub inline fn drawCircleAxis(dde: Encoder, _axis: Axis, _xyz: [3]f32, _radius: f32, _weight: f32) void {
        dde.vtable.encoderDrawCircleAxis(dde.ptr, _axis, _xyz, _radius, _weight);
    }

    ///
    pub inline fn drawQuad(dde: Encoder, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        dde.vtable.encoderDrawQuad(dde.ptr, _normal, _center, _size);
    }

    ///
    pub inline fn drawQuadSprite(dde: Encoder, _handle: SpriteHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        dde.vtable.encoderDrawQuadSprite(dde.ptr, _handle, _normal, _center, _size);
    }

    ///
    pub inline fn drawQuadTexture(dde: Encoder, _handle: gpu.TextureHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        dde.vtable.encoderDrawQuadTexture(dde.ptr, _handle, _normal, _center, _size);
    }

    ///
    pub inline fn drawAxis(dde: Encoder, _xyz: [3]f32, _len: f32, _highlight: Axis, _thickness: f32) void {
        dde.vtable.encoderDrawAxis(dde.ptr, _xyz, _len, _highlight, _thickness);
    }

    ///
    pub inline fn drawGrid(dde: Encoder, _normal: [3]f32, _center: [3]f32, _size: u32, _step: f32) void {
        dde.vtable.encoderDrawGrid(dde.ptr, _normal, _center, _size, _step);
    }

    ///
    pub inline fn drawGridAxis(dde: Encoder, _axis: Axis, _center: [3]f32, _size: u32, _step: f32) void {
        dde.vtable.encoderDrawGridAxis(dde.ptr, _axis, _center, _size, _step);
    }

    ///
    pub inline fn drawOrb(dde: Encoder, _xyz: [3]f32, _radius: f32, _highlight: Axis) void {
        dde.vtable.encoderDrawOrb(dde.ptr, _xyz, _radius, _highlight);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        encoderBegin: *const fn (dde: *anyopaque, _viewId: u16, _depthTestLess: bool, _encoder: *anyopaque) void,
        encoderEnd: *const fn (dde: *anyopaque) void,
        encoderPush: *const fn (dde: *anyopaque) void,
        encoderPop: *const fn (dde: *anyopaque) void,
        encoderSetDepthTestLess: *const fn (dde: *anyopaque, _depthTestLess: bool) void,
        encoderSetState: *const fn (dde: *anyopaque, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void,
        encoderSetColor: *const fn (dde: *anyopaque, _abgr: u32) void,
        encoderSetLod: *const fn (dde: *anyopaque, _lod: u8) void,
        encoderSetWireframe: *const fn (dde: *anyopaque, _wireframe: bool) void,
        encoderSetStipple: *const fn (dde: *anyopaque, _stipple: bool, _scale: f32, _offset: f32) void,
        encoderSetSpin: *const fn (dde: *anyopaque, _spin: f32) void,
        encoderSetTransform: *const fn (dde: *anyopaque, _mtx: ?*const anyopaque) void,
        encoderSetTranslate: *const fn (dde: *anyopaque, _xyz: [3]f32) void,
        encoderPushTransform: *const fn (dde: *anyopaque, _mtx: *const anyopaque) void,
        encoderPopTransform: *const fn (dde: *anyopaque) void,
        encoderMoveTo: *const fn (dde: *anyopaque, _xyz: [3]f32) void,
        encoderLineTo: *const fn (dde: *anyopaque, _xyz: [3]f32) void,
        encoderClose: *const fn (dde: *anyopaque) void,
        encoderDrawAABB: *const fn (dde: *anyopaque, min: [3]f32, max: [3]f32) void,
        encoderDrawCylinder: *const fn (dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void,
        encoderDrawCapsule: *const fn (dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void,
        encoderDrawDisk: *const fn (dde: *anyopaque, center: [3]f32, normal: [3]f32, radius: f32) void,
        encoderDrawObb: *const fn (dde: *anyopaque, _obb: [3]f32) void,
        encoderDrawSphere: *const fn (dde: *anyopaque, center: [3]f32, radius: f32) void,
        encoderDrawTriangle: *const fn (dde: *anyopaque, v0: [3]f32, v1: [3]f32, v2: [3]f32) void,
        encoderDrawCone: *const fn (dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void,
        encoderDrawGeometry: *const fn (dde: *anyopaque, _handle: GeometryHandle) void,
        encoderDrawLineList: *const fn (dde: *anyopaque, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void,
        encoderDrawTriList: *const fn (dde: *anyopaque, _numVertices: u32, _vertices: []const Vertex, _numIndices: u32, _indices: ?[*]const u16) void,
        encoderDrawFrustum: *const fn (dde: *anyopaque, _viewProj: []f32) void,
        encoderDrawArc: *const fn (dde: *anyopaque, _axis: Axis, _xyz: [3]f32, _radius: f32, _degrees: f32) void,
        encoderDrawCircle: *const fn (dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _radius: f32, _weight: f32) void,
        encoderDrawCircleAxis: *const fn (dde: *anyopaque, _axis: Axis, _xyz: [3]f32, _radius: f32, _weight: f32) void,
        encoderDrawQuad: *const fn (dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _size: f32) void,
        encoderDrawQuadSprite: *const fn (dde: *anyopaque, _handle: SpriteHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void,
        encoderDrawQuadTexture: *const fn (dde: *anyopaque, _handle: gpu.TextureHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void,
        encoderDrawAxis: *const fn (dde: *anyopaque, _xyz: [3]f32, _len: f32, _highlight: Axis, _thickness: f32) void,
        encoderDrawGrid: *const fn (dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _size: u32, _step: f32) void,
        encoderDrawGridAxis: *const fn (dde: *anyopaque, _axis: Axis, _center: [3]f32, _size: u32, _step: f32) void,
        encoderDrawOrb: *const fn (dde: *anyopaque, _xyz: [3]f32, _radius: f32, _highlight: Axis) void,
    };
};

pub const GfxDDApi = struct {
    createSprite: *const fn (width: u16, height: u16, _data: []const u8) SpriteHandle,
    destroySprite: *const fn (handle: SpriteHandle) void,
    createGeometry: *const fn (numVertices: u32, vertices: []const Vertex, numIndices: u32, indices: ?[*]const u8, index32: bool) GeometryHandle,
    destroyGeometry: *const fn (handle: GeometryHandle) void,

    encoderCreate: *const fn () Encoder,
    encoderDestroy: *const fn (encoder: Encoder) void,
};
