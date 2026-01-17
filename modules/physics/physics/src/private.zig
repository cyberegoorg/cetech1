const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const transform = @import("transform");
const editor_inspector = @import("editor_inspector");

const public = @import("physics.zig");

const module_name = .physics;

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
var _gpu: *const cetech1.gpu.GpuBackendApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _transform: *const transform.TransformApi = undefined;

var _inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    shape_type_properties_aspec: *editor_inspector.UiPropertyAspect = undefined,
};
var _g: *G = undefined;

const velocity_c = ecs.ComponentI.implement(
    public.Velocity,
    .{
        .cdb_type_hash = public.VelocityCdb.type_hash,
        .category = "Physics",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.CoreIcons.FA_ANGLES_RIGHT});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Velocity, data);
            position.* = public.Velocity{
                .x = public.VelocityCdb.readValue(f32, _cdb, r, .X),
                .y = public.VelocityCdb.readValue(f32, _cdb, r, .Y),
                .z = public.VelocityCdb.readValue(f32, _cdb, r, .Z),
            };
        }
    },
);

const physics_system_c = ecs.ComponentI.implement(
    public.PhysicsSystem,
    .{
        .cdb_type_hash = public.PhysicsSystemCdb.type_hash,
        .category = "Physics",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.PhysicsWorld});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const system = std.mem.bytesAsValue(public.PhysicsSystem, data);

            const gravity: math.Vec3f = if (public.PhysicsSystemCdb.readSubObj(_cdb, r, .Gravity)) |gravity_obj| cetech1.cdb_types.Vec3fCdb.f.to(_cdb, gravity_obj) else .{};

            system.* = public.PhysicsSystem{
                .gravity = gravity,
            };
        }
    },
);

const physics_shape_c = ecs.ComponentI.implement(
    public.PhysicsShape,
    .{
        .cdb_type_hash = public.PhysicsShapeCdb.type_hash,
        .category = "Physics",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.PhysicsShapes});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const size_obj = public.PhysicsShapeCdb.readSubObj(_cdb, r, .size).?;
            const shape = std.mem.bytesAsValue(public.PhysicsShape, data);

            const type_str = public.PhysicsBodyCdb.readStr(_cdb, r, .type) orelse "box";

            shape.* = public.PhysicsShape{
                .type = std.meta.stringToEnum(public.PhysicsShapeType, type_str) orelse .box,
                .size = cetech1.cdb_types.Vec3fCdb.f.to(_cdb, size_obj),
            };
        }
    },
);

const physics_body_c = ecs.ComponentI.implement(
    public.PhysicsBody,
    .{
        .cdb_type_hash = public.PhysicsBodyCdb.type_hash,
        .category = "Physics",
    },
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.PhysicsBody});
        }

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const type_str = public.PhysicsBodyCdb.readStr(_cdb, r, .type) orelse "static";

            const position = std.mem.bytesAsValue(public.PhysicsBody, data);
            position.* = public.PhysicsBody{
                .type = std.meta.stringToEnum(public.PhysicsBodyType, type_str) orelse .static,
                .mass = public.PhysicsBodyCdb.readValue(f32, _cdb, r, .mass),
            };
        }
    },
);

// TODO: remove
const move_system_i = ecs.SystemI.implement(
    .{
        .name = "move_system",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(transform.LocalTransformComponent), .inout = .InOut },
            .{ .id = ecs.id(public.Velocity), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            const positions = it.field(transform.LocalTransformComponent, 0).?;
            const velocities = it.field(public.Velocity, 1).?;

            for (it.entities(), 0..it.count()) |ent, i| {
                positions[i].local.position.x += velocities[i].x * dt;
                positions[i].local.position.y += velocities[i].y * dt;
                positions[i].local.position.z += velocities[i].z * dt;

                _transform.transform(world, ent);
                // world.modified(ent, transform.LocalTransformComponent);
            }
        }
    },
);

var shape_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = public.PhysicsShapeCdb.read(_cdb, obj).?;
        const type_str = public.PhysicsShapeCdb.readStr(_cdb, r, .type) orelse "box";
        var type_enum: public.PhysicsShapeType = std.meta.stringToEnum(public.PhysicsShapeType, type_str) orelse .box;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = public.PhysicsShapeCdb.write(_cdb, obj).?;
            try public.PhysicsShapeCdb.setStr(_cdb, w, .type, @tagName(type_enum));
            try public.PhysicsShapeCdb.commit(_cdb, w);
        }
    }
});

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // VelocityCdb
        {
            _ = try _cdb.addType(
                db,
                public.VelocityCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.VelocityCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.VelocityCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.VelocityCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }

        // PhysicsSystemCdb
        {
            _ = try _cdb.addType(
                db,
                public.PhysicsSystemCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.PhysicsSystemCdb.propIdx(.Gravity),
                        .name = "gravity",
                        .type = cdb.PropType.SUBOBJECT,
                        .type_hash = cetech1.cdb_types.Vec3fCdb.type_hash,
                    },
                },
            );
        }

        // PhysicsShapeCdb
        {
            _ = try _cdb.addType(
                db,
                public.PhysicsShapeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.PhysicsShapeCdb.propIdx(.type), .name = "type", .type = cdb.PropType.STR },
                    .{
                        .prop_idx = public.PhysicsShapeCdb.propIdx(.size),
                        .name = "size",
                        .type = cdb.PropType.SUBOBJECT,
                        .type_hash = cetech1.cdb_types.Vec3fCdb.type_hash,
                    },
                },
            );

            try public.PhysicsShapeCdb.addPropertyAspect(
                editor_inspector.UiPropertyAspect,
                _cdb,
                db,
                .type,
                _g.shape_type_properties_aspec,
            );
        }

        // PhysicsBodyCdb
        {
            _ = try _cdb.addType(
                db,
                public.PhysicsBodyCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.PhysicsBodyCdb.propIdx(.type), .name = "type", .type = cdb.PropType.STR },
                    .{ .prop_idx = public.PhysicsBodyCdb.propIdx(.mass), .name = "mass", .type = cdb.PropType.F32 },
                },
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
    _gpu = apidb.getZigApi(module_name, cetech1.gpu.GpuBackendApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;
    _transform = apidb.getZigApi(module_name, transform.TransformApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &velocity_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &physics_system_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &physics_shape_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &physics_body_c, load);

    // System
    try apidb.implOrRemove(module_name, ecs.SystemI, &move_system_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.shape_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_physics_shape_type_prop_aspect", shape_type_aspec);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_physics(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
