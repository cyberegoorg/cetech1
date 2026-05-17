const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;
const gpu_dd = cetech1.gpu_dd;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;

const editor_inspector = cetech1.editor.inspector;
const editor = cetech1.editor;
const transform = cetech1.transform;

const public = cetech1.physics;

const module_name = .physics;

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

// Global state that can surive hot-reload
const G = struct {
    shape_type_properties_aspec: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
    velocity_editor_component_aspect: *editor.EditorComponentAspect = undefined,
    system_editor_component_aspect: *editor.EditorComponentAspect = undefined,
    shape_editor_component_aspect: *editor.EditorComponentAspect = undefined,
    body_editor_component_aspect: *editor.EditorComponentAspect = undefined,
};
var _g: *G = undefined;

const velocity_c = ecs.ComponentI.implement(
    public.Velocity,
    .{
        .display_name = "Velocity",
        .cdb_type_hash = public.VelocityCdb.type_hash,
        .category = "Physics",
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.Velocity, data);
            position.* = public.Velocity{
                .x = public.VelocityCdb.readValue(f32, r, .X),
                .y = public.VelocityCdb.readValue(f32, r, .Y),
                .z = public.VelocityCdb.readValue(f32, r, .Z),
            };
        }

        pub fn debugdraw(gpu_backend: gpu.GpuBackend, dd: gpu_dd.Encoder, world: *ecs.World, entites: []const ecs.EntityId, data: []const u8, size: math.Vec2f) !void {
            _ = size;
            _ = gpu_backend;

            var velocities: []const public.Velocity = undefined;
            velocities.ptr = @ptrCast(@alignCast(data.ptr));
            velocities.len = data.len / @sizeOf(public.Velocity);

            for (entites, velocities) |ent, velocity| {
                const wt = world.getComponent(transform.WorldTransformComponent, ent) orelse continue;

                dd.pushTransform(wt.world.toMat());
                defer dd.popTransform();

                const v = math.Vec3f{ .x = velocity.x, .y = velocity.y, .z = velocity.z };
                dd.drawCone(.{}, v, 0.05);
            }
        }
    },
);

const physics_system_c = ecs.ComponentI.implement(
    public.PhysicsSystem,
    .{
        .display_name = "Physics system",
        .cdb_type_hash = public.PhysicsSystemCdb.type_hash,
        .category = "Physics",
        .on_instantiate = .Inherit,
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const system = std.mem.bytesAsValue(public.PhysicsSystem, data);

            const gravity: math.Vec3f = if (public.PhysicsSystemCdb.readSubObj(r, .Gravity)) |gravity_obj| cetech1.cdb_types.Vec3fCdb.f.to(gravity_obj) else .{};

            system.* = public.PhysicsSystem{
                .gravity = gravity,
            };
        }
    },
);

const physics_shape_c = ecs.ComponentI.implement(
    public.PhysicsShape,
    .{
        .display_name = "Physics shape",
        .cdb_type_hash = public.PhysicsShapeCdb.type_hash,
        .category = "Physics",
        .on_instantiate = .Inherit,
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const size_obj = public.PhysicsShapeCdb.readSubObj(r, .Size).?;
            const shape = std.mem.bytesAsValue(public.PhysicsShape, data);

            shape.* = public.PhysicsShape{
                .type = public.PhysicsShapeCdb.readStrEnum(public.PhysicsShapeType, r, .Type, .Box),
                .size = cetech1.cdb_types.Vec3fCdb.f.to(size_obj),
            };
        }

        pub fn debugdraw(gpu_backend: gpu.GpuBackend, dd: gpu_dd.Encoder, world: *ecs.World, entites: []const ecs.EntityId, data: []const u8, size: math.Vec2f) !void {
            _ = size;
            _ = gpu_backend;

            var shapes: []const public.PhysicsShape = undefined;
            shapes.ptr = @ptrCast(@alignCast(data.ptr));
            shapes.len = data.len / @sizeOf(public.PhysicsShape);

            dd.setWireframe(true);
            defer dd.setWireframe(false);

            for (entites, shapes) |ent, shape| {
                const wt = world.getComponent(transform.WorldTransformComponent, ent) orelse continue;

                switch (shape.type) {
                    .Box => {
                        dd.pushTransform(wt.world.toMat());
                        defer dd.popTransform();
                        dd.drawAABB(shape.size.negative(), shape.size);
                    },
                    .Sphere => {
                        dd.drawSphere(wt.world.position, shape.size.x);
                    },
                }
            }
        }
    },
);

const physics_body_c = ecs.ComponentI.implement(
    public.PhysicsBody,
    .{
        .display_name = "Physics body",
        .cdb_type_hash = public.PhysicsBodyCdb.type_hash,
        .category = "Physics",
        .on_instantiate = .Inherit,
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.PhysicsBody, data);
            position.* = public.PhysicsBody{
                .type = public.PhysicsShapeCdb.readStrEnum(public.PhysicsBodyType, r, .Type, .Static),
                .mass = public.PhysicsBodyCdb.readValue(f32, r, .Mass),
            };
        }
    },
);

const editor_velocity_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator;
            _ = obj;
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.ChevronsRight});
        }
    },
);

const editor_system_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator;
            _ = obj;
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.PhysicsWorld});
        }
    },
);

const editor_shape_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator;
            _ = obj;
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.PhysicsShapes});
        }
    },
);

const editor_body_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator;
            _ = obj;
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.PhysicsBody});
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
        pub fn tick(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);

            var all_ents = cetech1.ArrayList(ecs.EntityId).empty;
            defer all_ents.deinit(alloc);

            while (it.next()) {
                const transforms = it.field(transform.LocalTransformComponent, 0).?;
                const velocities = it.field(public.Velocity, 1).?;

                try all_ents.appendSlice(alloc, it.entities());

                for (it.entities(), 0..it.count()) |ent, i| {
                    _ = ent;

                    transforms[i].local.position.x += velocities[i].x * dt;
                    transforms[i].local.position.y += velocities[i].y * dt;
                    transforms[i].local.position.z += velocities[i].z * dt;
                    // transform.transform(world, ent);
                    // world.modified(ent, transform.LocalTransformComponent);
                }
            }

            // TODO: SHIT: better system for dirty batch. this calc transform for childs many times.
            for (all_ents.items) |ent| {
                transform.transform(world, ent);
            }
        }
    },
);

var shape_type_aspec = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = prop_idx;
        _ = allocator;
        _ = args;
        const r = public.PhysicsShapeCdb.read(obj).?;

        var type_enum = public.PhysicsShapeCdb.readStrEnum(public.PhysicsShapeType, r, .Type, .Box);

        coreui.setNextItemWidth(-1.0);
        if (coreui.comboFromEnum("##select_shape_type", &type_enum)) {
            const w = public.PhysicsShapeCdb.write(obj).?;
            try public.PhysicsShapeCdb.setStr(w, .Type, @tagName(type_enum));
            try public.PhysicsShapeCdb.commit(w);
        }
    }
});

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // VelocityCdb
        {
            _ = try cdb.addType(
                db,
                public.VelocityCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.VelocityCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.VelocityCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.VelocityCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );

            try public.VelocityCdb.addAspect(
                editor.EditorComponentAspect,

                db,
                _g.velocity_editor_component_aspect,
            );
        }

        // PhysicsSystemCdb
        {
            _ = try cdb.addType(
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

            try public.PhysicsSystemCdb.addAspect(
                editor.EditorComponentAspect,

                db,
                _g.system_editor_component_aspect,
            );
        }

        // PhysicsShapeCdb
        {
            _ = try cdb.addType(
                db,
                public.PhysicsShapeCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.PhysicsShapeCdb.propIdx(.Type), .name = "type", .type = cdb.PropType.STR },
                    .{
                        .prop_idx = public.PhysicsShapeCdb.propIdx(.Size),
                        .name = "size",
                        .type = cdb.PropType.SUBOBJECT,
                        .type_hash = cetech1.cdb_types.Vec3fCdb.type_hash,
                    },
                },
            );

            try public.PhysicsShapeCdb.addAspect(
                editor.EditorComponentAspect,

                db,
                _g.shape_editor_component_aspect,
            );

            try public.PhysicsShapeCdb.addPropertyAspect(
                editor_inspector.UiInspectorPropertyValueAspect,

                db,
                .Type,
                _g.shape_type_properties_aspec,
            );
        }

        // PhysicsBodyCdb
        {
            _ = try cdb.addType(
                db,
                public.PhysicsBodyCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.PhysicsBodyCdb.propIdx(.Type), .name = "type", .type = cdb.PropType.STR },
                    .{ .prop_idx = public.PhysicsBodyCdb.propIdx(.Mass), .name = "mass", .type = cdb.PropType.F32 },
                },
            );

            try public.PhysicsBodyCdb.addAspect(
                editor.EditorComponentAspect,

                db,
                _g.body_editor_component_aspect,
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

    _g.shape_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_physics_shape_type_prop_aspect", shape_type_aspec);
    _g.velocity_editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_velocity_editor_component_aspect_aspect", editor_velocity_component_aspect);
    _g.system_editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_system_editor_component_aspect_aspect", editor_system_component_aspect);
    _g.shape_editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_shape_editor_component_aspect_aspect", editor_shape_component_aspect);
    _g.body_editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_body_editor_component_aspect_aspect", editor_body_component_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_physics(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
