const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gpu = cetech1.gpu;

const zm = cetech1.math.zmath;
const ecs = cetech1.ecs;
const actions = cetech1.actions;
const assetdb = cetech1.assetdb;
const uuid = cetech1.uuid;
const task = cetech1.task;

const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");
const Viewport = render_viewport.Viewport;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const transform = @import("transform");
const camera = @import("camera");
const editor_entity = @import("editor_entity");
const render_graph = @import("render_graph");
const light_component = @import("light_component");

const module_name = .editor_foo_viewport_tab;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_foo_viewport_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const coreui.CoreUIApi = undefined;
var _gpu: *const gpu.GpuApi = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _actions: *const actions.ActionsAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;
var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _editor_entity: *const editor_entity.EditorEntityAPI = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
    db: cdb.DbId = undefined, // TODO: SHIT
};
var _g: *G = undefined;

const DRAW_OBJ_COUNT = 1_000;

const seed: u64 = 1111;
var prng = std.Random.DefaultPrng.init(seed);

// Struct for tab type
const FooViewportTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,
    world: ecs.World,

    render_pipeline: render_pipeline.RenderPipeline,

    camera_ent: ecs.EntityId,
    camera_look_activated: bool = false,
    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, -12 },
    }),

    flecs_port: ?u16 = null,
};

// Some components and systems

const Velocity = struct {
    x: f32,
    y: f32,
    z: f32,
};
const velocity_c = ecs.ComponentI.implement(
    Velocity,
    .{
        .cdb_type_hash = VelocityCdb.type_hash,
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

            const position = std.mem.bytesAsValue(Velocity, data);
            position.* = Velocity{
                .x = VelocityCdb.readValue(f32, _cdb, r, .X),
                .y = VelocityCdb.readValue(f32, _cdb, r, .Y),
                .z = VelocityCdb.readValue(f32, _cdb, r, .Z),
            };
        }
    },
);

const move_system_i = ecs.SystemI.implement(
    .{
        .name = "move_system",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(transform.Position), .inout = .InOut },
            .{ .id = ecs.id(Velocity), .inout = .In },
        },
    },
    struct {
        pub fn update(world: ecs.World, it: *ecs.Iter) !void {
            _ = world;

            const p = it.field(transform.Position, 0).?;
            const v = it.field(Velocity, 1).?;

            for (0..it.count()) |i| {
                p[i].x += v[i].x;
                p[i].y += v[i].y;
                p[i].z += v[i].z;
            }
        }
    },
);

// Rendering component

const ECS_WORLD_CONTEXT = cetech1.strId32("ecs_world_context");
const ECS_ENTITY_CONTEXT = cetech1.strId32("ecs_entity_context");

// Fill editor tab interface
var foo_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = cetech1.strId32(TAB_NAME),
    .category = "Examples",
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ "  " ++ "Foo viewport";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ "  " ++ "Foo viewport";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor.TabI {
        const w = try _ecs.createWorld();

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Foo viewport {d}", .{tab_id});

        const camera_ent = w.newEntity(null);
        _ = w.setId(transform.Position, camera_ent, &transform.Position{});
        _ = w.setId(transform.Rotation, camera_ent, &transform.Rotation{});
        _ = w.setId(camera.Camera, camera_ent, &camera.Camera{});

        var tab_inst = _allocator.create(FooViewportTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _render_viewport.createViewport(
                name,
                w,
                camera_ent,
            ),
            .camera_ent = camera_ent,
            .world = w,

            .render_pipeline = try _render_pipeline.createDefault(_allocator, w),
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        var allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);
        {
            var zzz = _profiler.ZoneN(@src(), "Foo viewport tab - spawn entities");
            defer zzz.End();

            // TODO: TEMP HARDCODE SHIT HACK - created in 2024... if you still read this and year is not 2024 am still idiot ;)
            if (_assetdb.getObjId(_uuid.fromStr("0191e6d1-830a-73d8-992a-aa6f9add6d1e").?)) |e_obj| {
                const entities = try _ecs.spawnManyFromCDB(allocator, w, e_obj, DRAW_OBJ_COUNT);
                defer allocator.free(entities);

                const rnd = prng.random();

                for (entities, 0..) |ent, idx| {
                    _ = idx;

                    _ = w.setId(Velocity, ent, &Velocity{
                        .x = (rnd.float(f32) * 2 - 1) * 0.1,
                        .y = (rnd.float(f32) * 2 - 1) * 0.1,
                        .z = (rnd.float(f32) * 2 - 1) * 0.1,
                    });
                }

                const light_ent = w.newEntity(null);
                _ = w.setId(transform.Position, light_ent, &transform.Position{ .y = 20 });
                _ = w.setId(light_component.Light, light_ent, &light_component.Light{ .radius = 100, .power = 10000 });
            }
        }

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(tab_inst.inst));
        _render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;

        const tab_o: *FooViewportTab = @alignCast(@ptrCast(inst));
        const size = _coreui.getContentRegionAvail();
        tab_o.viewport.setSize(size);

        if (tab_o.viewport.getTexture()) |texture| {
            _coreui.image(
                texture,
                .{
                    .flags = 0,
                    .mip = 0,
                    .w = size[0],
                    .h = size[1],
                },
            );
            const hovered = _coreui.isItemHovered(.{});

            var camera_look_activated = false;
            {
                _actions.pushSet(ViewportActionSet);
                defer _actions.popSet();
                camera_look_activated = _actions.isActionDown(LookActivationAction);
            }

            if (hovered and camera_look_activated) {
                tab_o.camera_look_activated = true;
                _kernel.getMainWindow().?.setCursorMode(.disabled);
                _actions.pushSet(ActivatedViewportActionSet);
            }

            if (tab_o.camera_look_activated and !camera_look_activated) {
                tab_o.camera_look_activated = false;
                _kernel.getMainWindow().?.setCursorMode(.normal);
                _actions.popSet();
            }

            if (tab_o.camera_look_activated) {
                const move = _actions.getActionAxis(MoveAction);
                const look = _actions.getActionAxis(LookAction);

                tab_o.camera.update(move, look, dt);
            }
        }

        _ = tab_o.world.setId(transform.Position, tab_o.camera_ent, &transform.Position{
            .x = tab_o.camera.position[0],
            .y = tab_o.camera.position[1],
            .z = tab_o.camera.position[2],
        });

        _ = tab_o.world.setId(transform.Rotation, tab_o.camera_ent, &transform.Rotation{
            .q = zm.matToQuat(zm.mul(zm.rotationX(tab_o.camera.pitch), zm.rotationY(tab_o.camera.yaw))),
        });

        tab_o.viewport.requestRender(tab_o.render_pipeline);
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            _render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
            tab_o.flecs_port = _editor_entity.uiRemoteDebugMenuItems(&tab_o.world, allocator, tab_o.flecs_port);
        }
    }
});

const ActivatedViewportActionSet = cetech1.strId32("foo_activated_viewport");
const ViewportActionSet = cetech1.strId32("foo_viewport");
const MoveAction = cetech1.strId32("move");
const LookAction = cetech1.strId32("look");
const LookActivationAction = cetech1.strId32("look_activation");

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "FooViewportTab",
    &[_]cetech1.StrId64{render_viewport.VIEWPORT_KERNEL_TASK},
    struct {
        pub fn init() !void {
            try _actions.createActionSet(ViewportActionSet);
            try _actions.addActions(ViewportActionSet, &.{
                .{ .name = LookActivationAction, .action = .{ .button = actions.ButtonAction{} } },
            });

            try _actions.addMappings(ViewportActionSet, LookActivationAction, &.{
                .{ .gamepadAxisButton = actions.GamepadAxisButtonMapping{ .a = .right_trigger } },
                .{ .mouseButton = actions.MouseButtonMapping{ .b = .left } },
            });

            try _actions.createActionSet(ActivatedViewportActionSet);
            try _actions.addActions(ActivatedViewportActionSet, &.{
                .{ .name = MoveAction, .action = .{ .axis = actions.AxisAction{} } },
                .{ .name = LookAction, .action = .{ .axis = actions.AxisAction{} } },
            });
            try _actions.addMappings(ActivatedViewportActionSet, MoveAction, &.{
                // WSAD
                .{ .key = actions.KeyButtonMapping{ .k = .w, .axis_map = &.{ 0, 1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .s, .axis_map = &.{ 0, -1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .a, .axis_map = &.{ -1, 0 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .d, .axis_map = &.{ 1, 0 } } },

                // Arrow
                .{ .key = actions.KeyButtonMapping{ .k = .up, .axis_map = &.{ 0, 1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .down, .axis_map = &.{ 0, -1 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .left, .axis_map = &.{ -1, 0 } } },
                .{ .key = actions.KeyButtonMapping{ .k = .right, .axis_map = &.{ 1, 0 } } },

                // Dpad
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_up, .axis_map = &.{ 0, 1 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_down, .axis_map = &.{ 0, -1 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_left, .axis_map = &.{ -1, 0 } } },
                .{ .gamepadButton = actions.GamepadButtonMapping{ .b = .dpad_right, .axis_map = &.{ 1, 0 } } },

                // Clasic gamepad move
                .{ .gamepadAxis = actions.GamepadAxisMapping{ .x = .left_x, .y = .left_y } },
            });
            try _actions.addMappings(ActivatedViewportActionSet, LookAction, &.{
                .{ .mouse = actions.MouseMapping{ .delta = true } },

                .{ .gamepadAxis = actions.GamepadAxisMapping{
                    .x = .right_x,
                    .y = .right_y,
                    .scale_x = 10,
                    .scale_y = 10,
                } },
            });
        }

        pub fn shutdown() !void {}
    },
);

// Register all cdb stuff in this method
pub const VelocityCdb = cdb.CdbTypeDecl(
    "ct_velocity",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {},
);

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // EntityLogicComponentCdb
        {
            _ = try _cdb.addType(
                db,
                VelocityCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = VelocityCdb.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = VelocityCdb.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = VelocityCdb.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;
    _actions = apidb.getZigApi(module_name, actions.ActionsAPI).?;

    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _editor_entity = apidb.getZigApi(module_name, editor_entity.EditorEntityAPI).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &foo_tab, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &velocity_c, load);

    // System
    try apidb.implOrRemove(module_name, ecs.SystemI, &move_system_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_foo_viewport_tab(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
