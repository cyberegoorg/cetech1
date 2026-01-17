const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const math = cetech1.math;

const transform = @import("transform");
const zphy = @import("zphysics");
const physics = @import("physics");

const module_name = .physics_jolt;

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
var _dd: *const cetech1.gpu.GpuDDApi = undefined;
var _transform: *const transform.TransformApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

var my_debug_renderer = DebugRenderer{};
const debug_renderer_enabled = zphy.debug_renderer_enabled;

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "PhysicsJolt",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            try zphy.init(_allocator, .{});

            if (debug_renderer_enabled) try zphy.DebugRenderer.createSingleton(&my_debug_renderer);
        }

        pub fn shutdown() !void {
            if (debug_renderer_enabled) zphy.DebugRenderer.destroySingleton();

            zphy.deinit();
        }
    },
);

const PhysicsSystemJolt = struct {
    system: ?*zphy.PhysicsSystem,
    bpli: *BroadPhaseLayerInterface,
    obplf: *ObjectVsBroadPhaseLayerFilter,
    olpf: *ObjectLayerPairFilter,
    cl: *ContactListener,
    accum: f32 = 0,
};

const physics_system_jolt_c = ecs.ComponentI.implement(
    PhysicsSystemJolt,
    .{
        .display_name = "Physics system (Jolt)",
    },
    struct {
        pub fn onDestroy(components: []PhysicsSystemJolt) !void {
            for (components) |c| {
                if (c.system) |system| {
                    system.destroy();
                    _allocator.destroy(c.bpli);
                    _allocator.destroy(c.obplf);
                    _allocator.destroy(c.olpf);
                    _allocator.destroy(c.cl);
                }
            }
        }

        pub fn onMove(dsts: []PhysicsSystemJolt, srcs: []PhysicsSystemJolt) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.system = null;
            }
        }

        pub fn debugdraw(gpu_backend: gpu.GpuBackend, dd: gpu.DDEncoder, world: ecs.World, entites: []const ecs.EntityId, data: []const u8, size: math.Vec2f) !void {
            _ = size;
            _ = gpu_backend;
            _ = entites;
            _ = world;

            var systems: []const PhysicsSystemJolt = undefined;
            systems.ptr = @ptrCast(@alignCast(data.ptr));
            systems.len = data.len / @sizeOf(PhysicsSystemJolt);

            for (systems) |system| {
                my_debug_renderer.dd = &dd;
                defer my_debug_renderer.dd = null;

                const draw_settings: zphy.DebugRenderer.BodyDrawSettings = .{
                    .shape_wireframe = true,
                    .world_transform = true,
                    // .velocity = true,

                    // TODO: sigsev in text3D,
                    // .mass_and_inertia = true,
                    // .sleep_stats = true,
                };
                const draw_filter = zphy.DebugRenderer.createBodyDrawFilter(DebugRenderer.shouldBodyDraw);
                defer zphy.DebugRenderer.destroyBodyDrawFilter(draw_filter);

                system.system.?.drawBodies(&draw_settings, draw_filter);
            }
        }
    },
);

const PhysicsShapeJolt = struct {
    shape: ?*zphy.Shape = undefined,
};

const physics_shape_jolt_c = ecs.ComponentI.implement(
    PhysicsShapeJolt,
    .{
        .display_name = "Physics shape (Jolt)",
    },
    struct {
        pub fn onDestroy(components: []PhysicsShapeJolt) !void {
            for (components) |c| {
                if (c.shape) |shape| {
                    shape.release();
                }
            }
        }

        pub fn onMove(dsts: []PhysicsShapeJolt, srcs: []PhysicsShapeJolt) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.shape = null;
            }
        }
    },
);

const PhysicsBodyJolt = struct {
    body: zphy.BodyId = .invalid,
};

const physics_body_jolt_c = ecs.ComponentI.implement(
    PhysicsBodyJolt,
    .{
        .display_name = "Physics body (Jolt)",
    },
    struct {},
);

fn physicsBodyTypeToJolt(t: physics.PhysicsBodyType) zphy.MotionType {
    return switch (t) {
        .Static => .static,
        .Dynamic => .dynamic,
        .Kinematic => .kinematic,
    };
}

fn physicsBodyTypeToLayer(t: physics.PhysicsBodyType) zphy.ObjectLayer {
    return switch (t) {
        .Static => object_layers.non_moving,
        .Dynamic => object_layers.moving,
        .Kinematic => object_layers.moving,
    };
}

const init_physics_system_i = ecs.SystemI.implement(
    .{
        .name = "physics_jolt.init_system",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(PhysicsSystemJolt), .oper = .Not },
            .{ .id = ecs.id(physics.PhysicsSystem), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const components = it.field(physics.PhysicsSystem, 1).?;

            for (it.entities(), 0..) |ent, idx| {
                const system = components[idx];

                const broad_phase_layer_interface = try _allocator.create(BroadPhaseLayerInterface);
                broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();

                const object_vs_broad_phase_layer_filter = try _allocator.create(ObjectVsBroadPhaseLayerFilter);
                object_vs_broad_phase_layer_filter.* = .{};

                const object_layer_pair_filter = try _allocator.create(ObjectLayerPairFilter);
                object_layer_pair_filter.* = .{};

                const contact_listener = try _allocator.create(ContactListener);
                contact_listener.* = .{};

                const physics_system = try zphy.PhysicsSystem.create(
                    @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(broad_phase_layer_interface)),
                    @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(object_vs_broad_phase_layer_filter)),
                    @as(*const zphy.ObjectLayerPairFilter, @ptrCast(object_layer_pair_filter)),
                    .{
                        .max_bodies = 1024,
                        .num_body_mutexes = 0,
                        .max_body_pairs = 1024,
                        .max_contact_constraints = 1024,
                    },
                );
                physics_system.setGravity(.{ system.gravity.x, system.gravity.y, system.gravity.z });

                _ = world.setComponent(
                    PhysicsSystemJolt,
                    ent,
                    &PhysicsSystemJolt{
                        .system = physics_system,
                        .bpli = broad_phase_layer_interface,
                        .obplf = object_vs_broad_phase_layer_filter,
                        .olpf = object_layer_pair_filter,
                        .cl = contact_listener,
                    },
                );
            }
        }
    },
);

fn createShapeFromComponent(physics_shape: physics.PhysicsShape) !*zphy.Shape {
    switch (physics_shape.type) {
        .Box => {
            const shape_settings = try zphy.BoxShapeSettings.create(physics_shape.size.toArray());
            defer shape_settings.asShapeSettings().release();

            return try shape_settings.asShapeSettings().createShape();
        },
        .Sphere => {
            const shape_settings = try zphy.SphereShapeSettings.create(physics_shape.size.x);
            defer shape_settings.asShapeSettings().release();

            return try shape_settings.asShapeSettings().createShape();
        },
    }
}

const init_physics_shape_system_i = ecs.SystemI.implement(
    .{
        .name = "physics_jolt.init_physics_shape_system",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .In, .src = .{ .id = ecs.Up } },

            .{ .id = ecs.id(PhysicsShapeJolt), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(physics.PhysicsShape), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const ents = it.entities();
            const physics_shapes = it.field(physics.PhysicsShape, 2).?;

            for (0..it.count()) |idx| {
                const physics_shape = physics_shapes[idx];

                const shape = try createShapeFromComponent(physics_shape);
                _ = world.setComponent(PhysicsShapeJolt, ents[idx], &PhysicsShapeJolt{ .shape = shape });
            }
        }
    },
);

const init_physics_body_system_i = ecs.SystemI.implement(
    .{
        .name = "physics_jolt.init_body_system",
        .multi_threaded = true, // TODO: invalid matrix?
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(PhysicsBodyJolt), .inout = .Out, .oper = .Not },

            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .In, .src = .{ .id = ecs.Up } },
            .{ .id = ecs.id(transform.WorldTransformComponent), .inout = .In },
            .{ .id = ecs.id(PhysicsShapeJolt), .inout = .In },
            .{ .id = ecs.id(physics.PhysicsBody), .inout = .In },
        },
    },
    struct {
        pub fn tick(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            var body_ids = cetech1.ArrayList(zphy.BodyId){};
            defer body_ids.deinit(alloc);

            // TODO: =(
            var body_interface: ?*zphy.BodyInterface = null;
            var physics_system: ?*PhysicsSystemJolt = null;

            while (it.next()) {
                try body_ids.ensureUnusedCapacity(alloc, it.count());

                const ents = it.entities();
                physics_system = &it.field(PhysicsSystemJolt, 1).?[0];
                const transforms = it.field(transform.WorldTransformComponent, 2).?;
                const physics_shapes = it.field(PhysicsShapeJolt, 3).?;
                const physics_bodies = it.field(physics.PhysicsBody, 4).?;

                if (body_interface == null) {
                    body_interface = physics_system.?.system.?.getBodyInterfaceMut();
                }

                for (0..it.count()) |idx| {
                    const physics_body = physics_bodies[idx];
                    const physics_shape = physics_shapes[idx];

                    const t = transforms[idx];

                    const body = try body_interface.?.createBody(.{
                        .user_data = ents[idx],
                        .motion_type = physicsBodyTypeToJolt(physics_body.type),

                        .position = .{ t.world.position.x, t.world.position.y, t.world.position.z, 0 },
                        .rotation = t.world.rotation.toArray(),

                        .shape = physics_shape.shape,
                        .object_layer = physicsBodyTypeToLayer(physics_body.type),

                        .mass_properties_override = .{ .mass = physics_body.mass },
                    });

                    body_ids.appendAssumeCapacity(body.id);

                    _ = world.setComponent(PhysicsBodyJolt, ents[idx], &PhysicsBodyJolt{ .body = body.id });
                }
            }

            if (body_interface) |bi| {
                if (body_ids.items.len != 0) {
                    // log.debug("Adding {d} bodies", .{body_ids.items.len});
                    const add_state = bi.addBodiesPrepare(body_ids.items);
                    bi.addBodiesFinalize(body_ids.items, add_state, .activate);
                }
            }

            // if (physics_system) |ps| {
            //     ps.system.?.optimizeBroadPhase();
            // }
        }
    },
);

const simulate_system_i = ecs.SystemI.implement(
    .{
        .name = "physics_jolt.simulate",
        .phase = ecs.OnUpdate,
        .multi_threaded = false,
        .simulation = true,
        .immediate = true,
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsSystem), .inout = .In },
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .In },
        },
    },
    struct {
        // TODO: SHIT!!!!
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            // _ = dt;
            // _ = world;
            const FIX_STEP = 1.0 / 60.0; // TODO: config

            world.enableObserver(transform_changed_observer_i.id, false);
            defer world.enableObserver(transform_changed_observer_i.id, true);

            const physics_system = it.field(PhysicsSystemJolt, 1);
            if (physics_system) |pss| {
                if (pss.len == 0) return;

                var sys = &pss[0];

                if (sys.system) |system| {
                    sys.accum += dt;
                    sys.accum = @min(sys.accum, 2 * FIX_STEP);

                    // Tick physics
                    var tick_count: u32 = 0;
                    while (sys.accum >= FIX_STEP) {
                        try system.update(FIX_STEP, .{});

                        sys.accum -= FIX_STEP;
                        tick_count += 1;
                    }
                    // log.debug("Update steps {d}", .{tick_count});
                    // log.debug("Gravity {any}", .{sys.system.?.getGravity()});

                    // Sync active bodies transforms.
                    const alloc = try _tmpalloc.create();
                    defer _tmpalloc.destroy(alloc);

                    const all_bodies = system.getBodiesUnsafe();
                    var active_bodies = std.ArrayList(zphy.BodyId){};
                    defer active_bodies.deinit(alloc);

                    // TODO: make unsafe. simulation is done.
                    try system.getActiveBodyIds(alloc, &active_bodies);

                    // if (active_bodies.items.len > 0) {
                    //     log.debug("Update {d} active bodies.", .{active_bodies.items.len});
                    // }

                    const alpha = (FIX_STEP + sys.accum) / FIX_STEP;
                    // log.debug("alha {d}", .{alpha});

                    for (active_bodies.items) |body_id| {
                        const body = zphy.tryGetBody(all_bodies, body_id).?;
                        const ent = body.getUserData();
                        const pos = body.getPosition();
                        const rot = body.getRotation();

                        const t = world.getMutComponent(transform.WorldTransformComponent, ent).?; // TODO: WORLD !!!!

                        const a_t = t.world;
                        const b_t = cetech1.math.Transform{
                            .position = .fromArray(pos),
                            .rotation = .fromArray(rot),
                            .scale = t.world.scale,
                        };

                        t.world = a_t.blendTransform(b_t, alpha);

                        //  _transform.transformChilds(world, ent);
                        _transform.transformOnlyChilds(world, ent);
                        // world.modified(ent, transform.LocalTransformComponent);
                    }
                }
            }
        }
    },
);

const deleted_system_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.deleted_observer",
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsSystem), .inout = .In },
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnRemove},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const ents = it.entities();

            for (0..it.count()) |idx| {
                // log.debug("delete PhysicsSystemJolt  instnace : {d} ", .{idx});
                world.removeComponent(PhysicsSystemJolt, ents[idx]);
            }
        }
    },
);

const deleted_body_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.deleted_body_observer",
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsBody), .inout = .In },
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .InOutFilter, .src = .{ .id = ecs.Up } },
            .{ .id = ecs.id(PhysicsBodyJolt), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnRemove},
    },
    struct {
        pub fn tick(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            var body_ids = cetech1.ArrayList(zphy.BodyId){};
            defer body_ids.deinit(alloc);

            // TODO: =(
            var body_interface: ?*zphy.BodyInterface = null;
            var physics_system: ?*PhysicsSystemJolt = null;

            while (it.next()) {
                try body_ids.ensureUnusedCapacity(alloc, it.count());

                const ents = it.entities();
                physics_system = &it.field(PhysicsSystemJolt, 1).?[0];
                const physics_bodies = it.field(PhysicsBodyJolt, 2).?;

                if (body_interface == null) {
                    body_interface = physics_system.?.system.?.getBodyInterfaceMut();
                }

                for (0..it.count()) |idx| {
                    const physics_body = physics_bodies[idx];

                    body_ids.appendAssumeCapacity(physics_body.body);
                    world.removeComponent(PhysicsBodyJolt, ents[idx]);
                }
            }

            if (body_interface) |bi| {
                if (body_ids.items.len != 0) {
                    // log.debug("removing {d} bodies", .{body_ids.items.len});
                    bi.removeBodies(body_ids.items);
                    bi.destroyBodies(body_ids.items);
                }
            }
        }
    },
);

const transform_changed_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.transform_changed_observer",
        .query = &.{
            .{ .id = ecs.id(transform.WorldTransformComponent), .inout = .In },
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .InOutFilter, .src = .{ .id = ecs.Up } },
            .{ .id = ecs.id(PhysicsBodyJolt), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnSet},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            // log.debug("changed: {d}", .{it.count()});

            // while (it.next()) {
            const ents = it.entities();
            _ = ents;
            _ = world;

            const physics_system = &it.field(PhysicsSystemJolt, 1).?[0];

            const bi = physics_system.system.?.getBodyInterfaceMut();

            const transforms = it.field(transform.WorldTransformComponent, 0).?;
            const bodies = it.field(PhysicsBodyJolt, 2).?;

            for (bodies, transforms) |body, t| {
                const body_id = body.body;
                const pos = t.world.position;
                const rot = t.world.rotation;

                if (!std.meta.eql(pos.toArray(), bi.getPosition(body_id))) {
                    bi.setPosition(body_id, pos.toArray(), .activate);
                    // log.debug("changed pos", .{});
                }

                if (!std.meta.eql(rot.toArray(), bi.getRotation(body_id))) {
                    bi.setRotation(body_id, rot.toArray(), .activate);
                    // log.debug("changed rot", .{});
                }
            }
            // }
        }
    },
);

const shape_add_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.shape_add_observer_i",
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsShape), .inout = .In },
        },
        .events = &.{ecs.OnAdd},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const ents = it.entities();
            const physics_shapes = it.field(physics.PhysicsShape, 0).?;

            for (0..it.count()) |idx| {
                const physics_shape = physics_shapes[idx];

                const shape = try createShapeFromComponent(physics_shape);
                _ = world.setComponent(PhysicsShapeJolt, ents[idx], &PhysicsShapeJolt{ .shape = shape });
            }
        }
    },
);

const shape_changed_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.shape_changed_observer",
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsShape), .inout = .In },
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .InOutFilter, .src = .{ .id = ecs.Up } },
            .{ .id = ecs.id(PhysicsShapeJolt), .inout = .InOutFilter },
            .{ .id = ecs.id(PhysicsBodyJolt), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnSet},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const physics_shapes = it.field(physics.PhysicsShape, 0).?;
            const physics_system = &it.field(PhysicsSystemJolt, 1).?[0];
            const jolt_shapes = it.field(PhysicsShapeJolt, 2).?;
            const jolt_bodies = it.field(PhysicsBodyJolt, 3).?;

            const ents = it.entities();

            _ = ents;
            _ = world;
            const bi = physics_system.system.?.getBodyInterfaceMut();

            for (0..it.count()) |idx| {
                const physics_shape = physics_shapes[idx];
                const shape = jolt_shapes[idx].shape.?;
                const body_id = jolt_bodies[idx].body;

                const new_shape = try createShapeFromComponent(physics_shape);
                jolt_shapes[idx].shape = new_shape;

                bi.setShape(body_id, new_shape, true, .activate);

                shape.release();
            }
        }
    },
);

const deleted_shape_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.deleted_shape_observer",
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsShape), .inout = .In },
            .{ .id = ecs.id(PhysicsShapeJolt), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnRemove},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            // const ents = it.entities();
            const jolt_shapes = it.field(PhysicsShapeJolt, 1).?;

            for (0..it.count()) |idx| {
                const shape = jolt_shapes[idx].shape.?;
                shape.release();
                jolt_shapes[idx].shape = null;
                // log.debug("delete PhysicsShapeJolt  instnace : {d} ", .{idx});

            }
        }
    },
);

const system_changed_observer_i = ecs.ObserverI.implement(
    .{
        .name = "physics_jolt.system_changed_observer",
        .query = &.{
            .{ .id = ecs.id(physics.PhysicsSystem), .inout = .In },
            .{ .id = ecs.id(PhysicsSystemJolt), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnSet},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            const systems = it.field(physics.PhysicsSystem, 0).?;
            const physics_system = &it.field(PhysicsSystemJolt, 1).?[0];

            for (0..it.count()) |idx| {
                const gravity = systems[idx].gravity;
                physics_system.system.?.setGravity(.{ gravity.x, gravity.y, gravity.z });
            }
        }
    },
);

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;
    }
});

const object_layers = struct {
    const non_moving: zphy.ObjectLayer = 0;
    const moving: zphy.ObjectLayer = 1;
    const len: u32 = 2;
};

const broad_phase_layers = struct {
    const non_moving: zphy.BroadPhaseLayer = 0;
    const moving: zphy.BroadPhaseLayer = 1;
    const len: u32 = 2;
};

const BroadPhaseLayerInterface = extern struct {
    broad_phase_layer_interface: zphy.BroadPhaseLayerInterface = .init(@This()),
    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined,

    fn init() BroadPhaseLayerInterface {
        var object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined;
        object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return .{ .object_to_broad_phase = object_to_broad_phase };
    }

    fn selfPtr(broad_phase_layer_interface: *zphy.BroadPhaseLayerInterface) *BroadPhaseLayerInterface {
        return @alignCast(@fieldParentPtr("broad_phase_layer_interface", broad_phase_layer_interface));
    }

    fn selfPtrConst(broad_phase_layer_interface: *const zphy.BroadPhaseLayerInterface) *const BroadPhaseLayerInterface {
        return @alignCast(@fieldParentPtr("broad_phase_layer_interface", broad_phase_layer_interface));
    }

    pub fn getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.c) u32 {
        return broad_phase_layers.len;
    }

    pub fn getBroadPhaseLayer(
        broad_phase_layer_interface: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.c) zphy.BroadPhaseLayer {
        return selfPtrConst(broad_phase_layer_interface).object_to_broad_phase[layer];
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    object_vs_broad_phase_layer_filter: zphy.ObjectVsBroadPhaseLayerFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.c) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    object_layer_pair_filter: zphy.ObjectLayerPairFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.c) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ContactListener = extern struct {
    contact_listener: zphy.ContactListener = .init(@This()),

    fn selfPtr(contact_listener: *zphy.ContactListener) *ContactListener {
        return @alignCast(@fieldParentPtr("contact_listener", contact_listener));
    }

    fn selfPtrConst(contact_listener: *const zphy.ContactListener) *const ContactListener {
        return @alignCast(@fieldParentPtr("contact_listener", contact_listener));
    }

    pub fn onContactValidate(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        base_offset: *const [3]zphy.Real,
        collision_result: *const zphy.CollideShapeResult,
    ) callconv(.c) zphy.ValidateResult {
        _ = contact_listener;
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }

    pub fn onContactAdded(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        _: *const zphy.ContactManifold,
        _: *zphy.ContactSettings,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = body1;
        _ = body2;
    }

    pub fn onContactPersisted(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        _: *const zphy.ContactManifold,
        _: *zphy.ContactSettings,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = body1;
        _ = body2;
    }

    pub fn onContactRemoved(
        contact_listener: *zphy.ContactListener,
        sub_shape_id_pair: *const zphy.SubShapeIdPair,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = sub_shape_id_pair;
    }
};

const DebugRenderer = if (!debug_renderer_enabled) void else extern struct {
    const VTable = zphy.DebugRenderer.VTable(@This());
    vtable: *const VTable = zphy.DebugRenderer.initVTable(@This()),

    dd: ?*const gpu.DDEncoder = null,

    pub fn shouldBodyDraw(_: *const zphy.Body) callconv(.c) bool {
        return true;
    }

    pub fn drawLine(
        self: *DebugRenderer,
        from: *const [3]zphy.Real,
        to: *const [3]zphy.Real,
        color: zphy.DebugRenderer.Color,
    ) callconv(.c) void {
        // _ = self;
        // _ = from;
        // _ = to;
        _ = color;
        if (self.dd) |dd| {
            dd.push();
            defer dd.pop();
            dd.setState(false, false, false);
            dd.setTransform(.identity);
            dd.moveTo(.fromArray(from.*));
            dd.lineTo(.fromArray(to.*));
        }
    }
    pub fn drawTriangle(
        self: *DebugRenderer,
        v1: *const [3]zphy.Real,
        v2: *const [3]zphy.Real,
        v3: *const [3]zphy.Real,
        color: zphy.DebugRenderer.Color,
    ) callconv(.c) void {
        _ = self;
        _ = v1;
        _ = v2;
        _ = v3;
        _ = color;
    }
    pub fn createTriangleBatch(
        self: *DebugRenderer,
        triangles: [*]zphy.DebugRenderer.Triangle,
        triangle_count: u32,
    ) callconv(.c) *zphy.DebugRenderer.TriangleBatch {
        // _ = self;
        _ = triangles;
        _ = triangle_count;

        return zphy.DebugRenderer.createTriangleBatch(self);
    }
    pub fn createTriangleBatchIndexed(
        self: *DebugRenderer,
        vertices: [*]zphy.DebugRenderer.Vertex,
        vertex_count: u32,
        indices: [*]u32,
        index_count: u32,
    ) callconv(.c) *zphy.DebugRenderer.TriangleBatch {
        _ = self;
        // _ = vertices;
        // _ = vertex_count;
        // _ = indices;
        // _ = index_count;

        const alloc = _tmpalloc.create() catch undefined;
        defer _tmpalloc.destroy(alloc);

        const dd_vers = alloc.alloc(gpu.DDVertex, vertex_count) catch undefined;
        defer alloc.free(dd_vers);

        for (0..vertex_count) |vidx| {
            dd_vers[vidx] = .{
                .x = vertices[vidx].position[0],
                .y = vertices[vidx].position[1],
                .z = vertices[vidx].position[2],
            };
        }
        const geom = _dd.createGeometry(vertex_count, dd_vers, index_count, @ptrCast(indices), true);
        return zphy.DebugRenderer.createTriangleBatch(@ptrFromInt(geom.idx + 1));
    }
    pub fn destroyTriangleBatch(
        self: *DebugRenderer,
        batch: *anyopaque,
    ) callconv(.c) void {
        _ = self;

        const geom = gpu.DDGeometryHandle{ .idx = @truncate(@intFromPtr(batch) - 1) };
        _dd.destroyGeometry(geom);
    }
    pub fn drawGeometry(
        self: *DebugRenderer,
        model_matrix: *const zphy.RMatrix,
        world_space_bound: *const zphy.AABox,
        lod_scale_sq: f32,
        color: zphy.DebugRenderer.Color,
        geometry: *const zphy.DebugRenderer.Geometry,
        cull_mode: zphy.DebugRenderer.CullMode,
        cast_shadow: zphy.DebugRenderer.CastShadow,
        draw_mode: zphy.DebugRenderer.DrawMode,
    ) callconv(.c) void {
        // _ = model_matrix;
        _ = world_space_bound;
        _ = lod_scale_sq;
        // _ = color;
        // _ = geometry;
        _ = cull_mode;
        _ = cast_shadow;
        // _ = draw_mode;

        if (self.dd) |dd| {
            dd.push();
            defer dd.pop();

            const prim = zphy.DebugRenderer.getPrimitiveFromBatch(geometry.LODs[0].batch);
            const geom = gpu.DDGeometryHandle{ .idx = @truncate(@intFromPtr(prim) - 1) };

            dd.setColor(.fromU32(color.uint));

            dd.setState(false, false, false);
            dd.setWireframe(draw_mode == .draw_mode_wireframe);
            dd.setTransform(@bitCast(model_matrix.*));
            dd.drawGeometry(geom);
        }
    }

    pub fn drawText3D(
        self: *DebugRenderer,
        positions: *const [3]zphy.Real,
        string: [*:0]const u8,
        color: zphy.DebugRenderer.Color,
        height: f32,
    ) callconv(.c) void {
        _ = self;
        _ = positions;
        _ = string;
        _ = color;
        _ = height;
    }
};

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
    _dd = apidb.getZigApi(module_name, cetech1.gpu.GpuDDApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _transform = apidb.getZigApi(module_name, transform.TransformApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &physics_system_jolt_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &physics_shape_jolt_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &physics_body_jolt_c, load);

    // Systems
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_physics_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_physics_shape_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_physics_body_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &simulate_system_i, load);

    // Observers
    try apidb.implOrRemove(module_name, ecs.ObserverI, &transform_changed_observer_i, load);
    try apidb.implOrRemove(module_name, ecs.ObserverI, &deleted_system_observer_i, load);
    try apidb.implOrRemove(module_name, ecs.ObserverI, &deleted_body_observer_i, load);
    try apidb.implOrRemove(module_name, ecs.ObserverI, &system_changed_observer_i, load);
    try apidb.implOrRemove(module_name, ecs.ObserverI, &deleted_shape_observer_i, load);
    // try apidb.implOrRemove(module_name, ecs.ObserverI, &shape_add_observer_i, load);
    try apidb.implOrRemove(module_name, ecs.ObserverI, &shape_changed_observer_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_physics_jolt(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
