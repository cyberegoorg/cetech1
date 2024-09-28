const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gpu = cetech1.gpu;

const zm = cetech1.math;
const ecs = cetech1.ecs;
const primitives = cetech1.primitives;
const actions = cetech1.actions;
const assetdb = cetech1.assetdb;
const uuid = cetech1.uuid;
const task = cetech1.task;
const transform = cetech1.transform;
const renderer = cetech1.renderer;
const camera = cetech1.camera;

const Viewport = renderer.Viewport;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

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
var _render_graph: *const renderer.RenderGraphApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _actions: *const actions.ActionsAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;
var _renderer: *const cetech1.renderer.RendererApi = undefined;

const World2CullingQuery = std.AutoArrayHashMap(ecs.World, ecs.Query);

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
    rg: renderer.Graph = undefined,
    db: cetech1.cdb.DbId = undefined, // TODO: SHIT
};
var _g: *G = undefined;

const SPHERE_COUNT = 1_000;

const seed: u64 = 1111;
var prng = std.rand.DefaultPrng.init(seed);

// Struct for tab type
const FooViewportTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,
    world: ecs.World,
    camera_look_activated: bool = false,

    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
        .yaw = std.math.degreesToRadians(180),
    }),

    flecs_port: ?u16 = null,
};

// Some components and systems

const Velocity = struct {
    x: f32,
    y: f32,
    z: f32,
};
const velocity_c = ecs.ComponentI.implement(Velocity, null, struct {});

const move_system_i = ecs.SystemI.implement(
    .{
        .name = "move system",
        .multi_threaded = false,
        .phase = ecs.OnUpdate,
        .query = &.{
            .{ .id = ecs.id(transform.Position), .inout = .InOut },
            .{ .id = ecs.id(Velocity), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *ecs.IterO) !void {
            var it = _ecs.toIter(iter);

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

const ECS_WORLD_CONTEXT = cetech1.strid.strId32("ecs_world_context");
const ECS_ENTITY_CONTEXT = cetech1.strid.strId32("ecs_entity_context");

// Fill editor tab interface
var foo_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },
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

        var tab_inst = _allocator.create(FooViewportTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _renderer.createViewport(name, _g.rg, w),
            .world = w,
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        var allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        // TODO: TEMP HARDCODE SHIT HACK - created in 2024... if you still read this and year is not 2024 am still idiot ;)
        if (_assetdb.getObjId(_uuid.fromStr("0191e6d1-830a-73d8-992a-aa6f9add6d1e").?)) |e_obj| {
            const entities = try _ecs.spawnManyFromCDB(allocator, w, e_obj, SPHERE_COUNT);
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
        }

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(tab_inst.inst));
        _renderer.destroyViewport(tab_o.viewport);
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

        tab_o.viewport.setViewMtx(tab_o.camera.calcViewMtx());
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);
        }
    }
});

const ActivatedViewportActionSet = cetech1.strid.strId32("foo_activated_viewport");
const ViewportActionSet = cetech1.strid.strId32("foo_viewport");
const MoveAction = cetech1.strid.strId32("move");
const LookAction = cetech1.strid.strId32("look");
const LookActivationAction = cetech1.strid.strId32("look_activation");

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "FooViewportTab",
    &[_]cetech1.strid.StrId64{},
    struct {
        pub fn init() !void {
            _g.rg = try _render_graph.create();
            try _render_graph.createDefault(_allocator, _g.rg);

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

        pub fn shutdown() !void {
            _render_graph.destroy(_g.rg);
        }
    },
);

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
    _render_graph = apidb.getZigApi(module_name, renderer.RenderGraphApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;
    _actions = apidb.getZigApi(module_name, actions.ActionsAPI).?;

    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    _renderer = apidb.getZigApi(module_name, cetech1.renderer.RendererApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVarValue(editor.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &foo_tab, load);

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
