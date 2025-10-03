const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const render_viewport = @import("render_viewport");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const public = @import("camera.zig");
const editor_inspector = @import("editor_inspector");
const transform = @import("transform");

const module_name = .camera;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _gpu: *const cetech1.gpu.GpuApi = undefined;

var _inspector: *const editor_inspector.InspectorAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    camera_type_properties_aspec: *editor_inspector.UiPropertyAspect = undefined,
};
var _g: *G = undefined;

const camera_c = ecs.ComponentI.implement(
    public.Camera,
    .{
        .cdb_type_hash = public.CameraCdb.type_hash,
        .category = "Renderer",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Camera});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Camera, data);
            const type_str = public.CameraCdb.readStr(_cdb, r, .Type) orelse "perspective";

            position.* = public.Camera{
                .type = if (std.mem.eql(u8, type_str, "perspective")) .perspective else .ortho,
                .fov = public.CameraCdb.readValue(f32, _cdb, r, .Fov),
                .near = public.CameraCdb.readValue(f32, _cdb, r, .Near),
                .far = public.CameraCdb.readValue(f32, _cdb, r, .Far),
            };
        }

        pub fn debugdraw(dd: gpu.DDEncoder, world: ecs.World, entites: []const ecs.EntityId, data: []const u8, size: [2]f32) !void {
            const aspect_ratio = size[0] / size[1];

            var cameras: []const public.Camera = undefined;
            cameras.ptr = @ptrCast(@alignCast(data.ptr));
            cameras.len = data.len / @sizeOf(public.Camera);

            for (entites, cameras) |ent, camera| {
                const wt = world.getComponent(transform.WorldTransform, ent) orelse continue;

                const pmtx = switch (camera.type) {
                    .perspective => perspectiveFov(
                        std.math.degreesToRadians(camera.fov),
                        aspect_ratio,
                        camera.near,
                        camera.far,
                    ),
                    .ortho => orthographic(
                        size[0],
                        size[1],
                        camera.near,
                        camera.far,
                    ),
                };

                const m = zm.mul(zm.inverse(wt.mtx), pmtx);
                const mm = zm.matToArr(m);
                dd.drawFrustum(mm);
            }
        }
    },
);

var camera_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = public.CameraCdb.read(_cdb, obj).?;
        const type_str = public.CameraCdb.readStr(_cdb, r, .Type) orelse "perspective";
        const type_enum: public.CameraType = if (std.mem.eql(u8, type_str, "perspective")) .perspective else .ortho;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        var cur_idx: i32 = @intFromEnum(type_enum);
        if (_coreui.combo("", .{
            .current_item = &cur_idx,
            .items_separated_by_zeros = "perspective\x00" ++ "ortho\x00",
        })) {
            const w = public.CameraCdb.write(_cdb, obj).?;
            const enum_v: public.CameraType = @enumFromInt(cur_idx);
            try public.CameraCdb.setStr(_cdb, w, .Type, @tagName(enum_v));
            try public.CameraCdb.commit(_cdb, w);
        }
    }
});

fn cameraSetingsMenu(world: ecs.World, camera_ent: ecs.EntityId) void {
    var c = world.getMutComponent(public.Camera, camera_ent);
    var cur_idx: i32 = @intFromEnum(c.?.type);
    if (_coreui.combo("type", .{ .current_item = &cur_idx, .items_separated_by_zeros = "perspective\x00" ++ "ortho\x00" })) {
        c.?.type = @enumFromInt(cur_idx);
    }

    _ = _coreui.dragF32("fov", .{ .v = &c.?.fov, .min = 1, .max = std.math.floatMax(f32) });
    _ = _coreui.dragF32("near", .{ .v = &c.?.near, .max = std.math.floatMax(f32) });
    _ = _coreui.dragF32("far", .{ .v = &c.?.far, .max = std.math.floatMax(f32) });
}

fn selectMainCameraMenu(allocator: std.mem.Allocator, world: ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) !?ecs.EntityId {
    var q = try world.createQuery(&.{
        .{ .id = ecs.id(public.Camera), .inout = .In },
    });
    var it = try q.iter();
    defer q.destroy();

    while (q.next(&it)) {
        const entities = it.entities();
        const cameras = it.field(public.Camera, 0).?;
        for (0..cameras.len) |idx| {
            const ent = entities[idx];
            const is_main_camera = ent == current_main_camera;

            const label = if (ent == camera_ent) try std.fmt.allocPrintSentinel(allocator, "{s}", .{"Editor camera"}, 0) else try std.fmt.allocPrintSentinel(allocator, "{d}", .{entities[idx]}, 0);
            defer allocator.free(label);

            if (_coreui.menuItem(_allocator, label, .{ .selected = is_main_camera }, null)) {
                if (!is_main_camera) return ent;
            }
        }
    }

    return null;
}

fn perspectiveFov(fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    return if (_gpu.isHomogenousDepth()) zm.perspectiveFovLhGl(
        fovy,
        aspect,
        near,
        far,
    ) else zm.perspectiveFovLh(
        fovy,
        aspect,
        near,
        far,
    );
}

fn orthographic(w: f32, h: f32, near: f32, far: f32) zm.Mat {
    return if (_gpu.isHomogenousDepth()) zm.orthographicLh(
        w,
        h,
        near,
        far,
    ) else zm.orthographicLhGl(
        w,
        h,
        near,
        far,
    );
}

const api = public.CameraAPI{
    .cameraSetingsMenu = cameraSetingsMenu,
    .selectMainCameraMenu = selectMainCameraMenu,
    .perspectiveFov = perspectiveFov,
    .orthographic = orthographic,
};

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // Camera
        {
            const scale_idx = try _cdb.addType(
                db,
                public.CameraCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.CameraCdb.propIdx(.Type), .name = "type", .type = cdb.PropType.STR },
                    .{ .prop_idx = public.CameraCdb.propIdx(.Fov), .name = "fov", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.CameraCdb.propIdx(.Near), .name = "near", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.CameraCdb.propIdx(.Far), .name = "far", .type = cdb.PropType.F32 },
                },
            );

            const camera = public.Camera{};

            const default_camera = try _cdb.createObject(db, scale_idx);
            const default_camera_w = _cdb.writeObj(default_camera).?;
            try public.CameraCdb.setStr(_cdb, default_camera_w, .Type, "perspective");
            public.CameraCdb.setValue(f32, _cdb, default_camera_w, .Fov, camera.fov);
            public.CameraCdb.setValue(f32, _cdb, default_camera_w, .Near, camera.near);
            public.CameraCdb.setValue(f32, _cdb, default_camera_w, .Far, camera.far);
            try _cdb.writeCommit(default_camera_w);
            _cdb.setDefaultObject(default_camera);

            try public.CameraCdb.addPropertyAspect(
                editor_inspector.UiPropertyAspect,
                _cdb,
                db,
                .Type,
                _g.camera_type_properties_aspec,
            );
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _gpu = apidb.getZigApi(module_name, cetech1.gpu.GpuApi).?;

    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    try apidb.setOrRemoveZigApi(module_name, public.CameraAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &camera_c, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.camera_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_camera_type_embed_prop_aspect", camera_type_aspec);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_camera(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
