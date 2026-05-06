const std = @import("std");

const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;
const gpu_dd = cetech1.gpu_dd;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const editor = cetech1.editor;
const editor_inspector = cetech1.editor.inspector;
const transform = cetech1.transform;

const public = cetech1.camera;

const module_name = .camera;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

const tempalloc = cetech1.tempalloc;
const profiler = cetech1.profiler;
const apidb = cetech1.apidb;

// Global state that can surive hot-reload
const G = struct {
    camera_type_properties_aspec: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
    editor_component_aspect: *editor.EditorComponentAspect = undefined,
};
var _g: *G = undefined;

const camera_c = ecs.ComponentI.implement(
    public.Camera,
    .{
        .display_name = "Camera",
        .cdb_type_hash = public.CameraCdb.type_hash,
        .category = "Renderer",
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Camera, data);

            position.* = public.Camera{
                .type = public.CameraCdb.readStrEnum(public.CameraType, r, .Type, .Perspective),
                .fov = public.CameraCdb.readValue(f32, r, .Fov),
                .near = public.CameraCdb.readValue(f32, r, .Near),
                .far = public.CameraCdb.readValue(f32, r, .Far),
            };
        }

        pub fn debugdraw(gpu_backend: gpu.GpuBackend, dd: gpu_dd.Encoder, world: *ecs.World, entites: []const ecs.EntityId, data: []const u8, size: math.Vec2f) !void {
            var cameras: []const public.Camera = undefined;
            cameras.ptr = @ptrCast(@alignCast(data.ptr));
            cameras.len = data.len / @sizeOf(public.Camera);

            for (entites, cameras) |ent, camera| {
                const wt = world.getComponent(transform.WorldTransformComponent, ent) orelse continue;

                const pmtx = projectionMatrixFromCamera(
                    camera,
                    size.x,
                    size.y,
                    gpu_backend.isHomogenousDepth(),
                );

                dd.drawFrustum(wt.world.inverse().toMat().mul(pmtx));
            }
        }
    },
);

const editor_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator;
            _ = obj;
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Camera});
        }
    },
);

var camera_type_aspec = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = prop_idx;
        _ = allocator;
        _ = args;
        const r = public.CameraCdb.read(obj).?;

        var type_enum = public.CameraCdb.readStrEnum(public.CameraType, r, .Type, .Perspective);

        coreui.setNextItemWidth(-1.0);
        if (coreui.comboFromEnum("", &type_enum)) {
            const w = public.CameraCdb.write(obj).?;
            try public.CameraCdb.setStr(w, .Type, @tagName(type_enum));
            try public.CameraCdb.commit(w);
        }
    }
});

fn cameraSetingsMenu(world: *ecs.World, camera_ent: ecs.EntityId) void {
    var c = world.getMutComponent(public.Camera, camera_ent);

    if (coreui.comboFromEnum("type", &c.?.type)) {}

    _ = coreui.dragF32("fov", .{ .v = &c.?.fov, .min = 1, .max = std.math.floatMax(f32) });
    _ = coreui.dragF32("near", .{ .v = &c.?.near, .max = std.math.floatMax(f32) });
    _ = coreui.dragF32("far", .{ .v = &c.?.far, .max = std.math.floatMax(f32) });
}

fn selectMainCameraMenu(allocator: std.mem.Allocator, world: *ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) !?ecs.EntityId {
    var q = try world.createQuery(.{
        .query = &.{
            .{ .id = ecs.id(public.Camera), .inout = .In },
        },
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

            if (coreui.menuItem(_allocator, label, .{ .selected = is_main_camera }, null)) {
                if (!is_main_camera) return ent;
            }
        }
    }

    return null;
}

fn cameraMenu(allocator: std.mem.Allocator, world: *ecs.World, camera_ent: ecs.EntityId, current_main_camera: ?ecs.EntityId) !?ecs.EntityId {
    if (coreui.beginMenu(allocator, cetech1.coreui.Icons.Camera, true, null)) {
        defer coreui.endMenu();

        if (coreui.beginMenu(allocator, "Active camera", true, null)) {
            defer coreui.endMenu();
            if (try selectMainCameraMenu(allocator, world, camera_ent, current_main_camera)) |c| {
                return c;
            }
        }

        if (coreui.beginMenu(allocator, "Editor camera", true, null)) {
            defer coreui.endMenu();
            cameraSetingsMenu(world, camera_ent);
        }
    }

    return null;
}

fn projectionMatrixFromCamera(camera: public.Camera, w: f32, h: f32, homogenous_depth: bool) math.Mat44f {
    return switch (camera.type) {
        .Perspective => math.Mat44f.perspectiveFovLh(
            std.math.degreesToRadians(camera.fov),
            w / h,
            camera.near,
            camera.far,
            homogenous_depth,
        ),
        .Ortho => math.Mat44f.orthographicLh(
            w,
            h,
            camera.near,
            camera.far,
            homogenous_depth,
        ),
    };
}

const api = public.CameraAPI{
    .projectionMatrixFromCamera = projectionMatrixFromCamera,
    .cameraSetingsMenu = cameraSetingsMenu,
    .selectMainCameraMenu = selectMainCameraMenu,
    .cameraMenu = cameraMenu,
};

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // Camera
        {
            const scale_idx = try cdb.addType(
                db,
                public.CameraCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.CameraCdb.propIdx(.Type), .name = "type", .type = cdb.PropType.STR },
                    .{ .prop_idx = public.CameraCdb.propIdx(.Fov), .name = "fov", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.CameraCdb.propIdx(.Near), .name = "near", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.CameraCdb.propIdx(.Far), .name = "far", .type = cdb.PropType.F32 },
                },
            );

            try public.CameraCdb.addAspect(
                editor.EditorComponentAspect,

                db,
                _g.editor_component_aspect,
            );

            const camera = public.Camera{};

            const default_camera = try cdb.createObject(db, scale_idx);
            const default_camera_w = cdb.writeObj(default_camera).?;
            try public.CameraCdb.setStr(default_camera_w, .Type, "perspective");
            public.CameraCdb.setValue(f32, default_camera_w, .Fov, camera.fov);
            public.CameraCdb.setValue(f32, default_camera_w, .Near, camera.near);
            public.CameraCdb.setValue(f32, default_camera_w, .Far, camera.far);
            try cdb.writeCommit(default_camera_w);
            cdb.setDefaultObject(default_camera);

            try public.CameraCdb.addPropertyAspect(
                editor_inspector.UiInspectorPropertyValueAspect,

                db,
                .Type,
                _g.camera_type_properties_aspec,
            );
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;
    public.api = &api;

    // impl api
    try apidb.setOrRemoveZigApi(module_name, public.CameraAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &camera_c, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.camera_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_camera_type_embed_prop_aspect", camera_type_aspec);
    _g.editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_editor_component_aspect", editor_component_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_camera(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
