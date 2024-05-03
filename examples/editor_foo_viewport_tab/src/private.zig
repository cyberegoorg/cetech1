const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gpu = cetech1.gpu;
const gfx = cetech1.gpu;
const gfx_rg = cetech1.render_graph;
const zm = cetech1.math;
const ecs = cetech1.ecs;
const primitives = cetech1.primitives;
const actions = cetech1.actions;
const graphvm = cetech1.graphvm;
const assetdb = cetech1.assetdb;
const uuid = cetech1.uuid;
const task = cetech1.task;
const transform = cetech1.transform;
const renderer = cetech1.renderer;

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
var _gfx: *const gfx.GfxApi = undefined;
var _gfx_rg: *const gfx_rg.GfxRGApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _actions: *const actions.ActionsAPI = undefined;
var _graph: *const graphvm.GraphVMApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;
var _viewport: *const cetech1.renderer.RendererApi = undefined;

const World2CullingQuery = std.AutoArrayHashMap(ecs.World, ecs.Query);

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.EditorTabTypeI = undefined,
    rg: gfx_rg.RenderGraph = undefined,
    db: cetech1.cdb.Db = undefined, // TODO: SHIT
};
var _g: *G = undefined;

const SPHERE_COUNT = 1_000;

const seed: u64 = 1111;
var prng = std.rand.DefaultPrng.init(seed);

// Struct for tab type
const FooViewportTab = struct {
    tab_i: editor.EditorTabI,
    viewport: Viewport = undefined,
    world: ecs.World,
    camera_look_activated: bool = false,

    camera: SimpleFPSCamera = SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
        .yaw = std.math.degreesToRadians(180),
    }),
};

// Some components and systems

const Velocity = struct {
    x: f32,
    y: f32,
    z: f32,
};
const velocity_c = ecs.ComponentI.implement(Velocity, struct {});

const move_system_i = ecs.SystemI.implement(
    .{
        .name = "move system",
        .multi_threaded = true,
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
var foo_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
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
    pub fn create(db: cdb.Db, tab_id: u32) !?*editor.EditorTabI {
        const w = try _ecs.createWorld();
        _g.db = db;

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Foo viewport {d}", .{tab_id});

        var tab_inst = _allocator.create(FooViewportTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _viewport.createViewport(name, _g.rg, w),
            .world = w,
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        var allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        // TODO: HACK
        const graph_obj = _assetdb.getObjId(_uuid.fromStr("018f4363-065b-73ef-943a-d3c88bdaef02").?);
        const logic_graph_obj = _assetdb.getObjId(_uuid.fromStr("0190a235-26c1-7ced-aea1-6af9190f0fe1").?);

        if (w.newEntities(allocator, SPHERE_COUNT)) |entities| {
            defer allocator.free(entities);

            const rnd = prng.random();

            for (entities, 0..) |ent, idx| {
                _ = idx;
                _ = w.setId(
                    transform.Position,
                    ent,
                    &transform.Position{},
                );

                // _ = w.setId(
                //     transform.Scale,
                //     ent,
                //     &transform.Scale{
                //         .x = 2,
                //         .y = 2,
                //         .z = 2,
                //     },
                // );

                // _ = w.setId(
                //     transform.Rotation,
                //     ent,
                //     &transform.Rotation{
                //         .q = zm.quatFromRollPitchYaw(0, 0, 0),
                //     },
                // );

                _ = w.setId(Velocity, ent, &Velocity{
                    .x = (rnd.float(f32) * 2 - 1) * 0.1,
                    .y = (rnd.float(f32) * 2 - 1) * 0.1,
                    .z = (rnd.float(f32) * 2 - 1) * 0.1,
                });

                if (graph_obj) |obj| {
                    _ = w.setId(renderer.RenderComponent, ent, &renderer.RenderComponent{
                        .graph = obj,
                    });
                }

                if (logic_graph_obj) |obj| {
                    _ = w.setId(ecs.EntityLogicComponent, ent, &ecs.EntityLogicComponent{
                        .graph = obj,
                    });
                }
            }
        }

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(tab_inst.inst));
        _viewport.destroyViewport(tab_o.viewport);
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
        _ = tab_o;
    }
});

const simple_pass = gfx_rg.Pass.implement(struct {
    pub fn setup(pass: *gfx_rg.Pass, builder: gfx_rg.GraphBuilder) !void {
        try builder.exportLayer(pass, "color");

        try builder.createTexture2D(
            pass,
            "foo",
            .{
                .format = gfx.TextureFormat.BGRA8,
                .flags = 0 |
                    gfx.TextureFlags_Rt |
                    gfx.SamplerFlags_MinPoint |
                    gfx.SamplerFlags_MipMask |
                    gfx.SamplerFlags_MagPoint |
                    gfx.SamplerFlags_MipPoint |
                    gfx.SamplerFlags_UClamp |
                    gfx.SamplerFlags_VClamp,

                .clear_color = 0x66CCFFff,
            },
        );
        try builder.createTexture2D(
            pass,
            "foo_depth",
            .{
                .format = gfx.TextureFormat.D24,
                .flags = 0 |
                    gfx.TextureFlags_Rt |
                    gfx.SamplerFlags_MinPoint |
                    gfx.SamplerFlags_MagPoint |
                    gfx.SamplerFlags_MipPoint |
                    gfx.SamplerFlags_UClamp |
                    gfx.SamplerFlags_VClamp,

                .clear_depth = 1.0,
            },
        );

        try builder.addPass("simple_pass", pass);
    }

    pub fn render(builder: gfx_rg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: Viewport, viewid: gfx.ViewId) !void {
        _ = builder;

        const fb_size = viewport.getSize();
        const aspect_ratio = fb_size[0] / fb_size[1];
        const projMtx = zm.perspectiveFovRhGl(
            0.25 * std.math.pi,
            aspect_ratio,
            0.1,
            1000.0,
        );

        const viewMtx = viewport.getViewMtx();
        gfx_api.setViewTransform(viewid, &viewMtx, &zm.matToArr(projMtx));

        if (gfx_api.getEncoder()) |e| {
            e.touch(viewid);

            const dd = viewport.getDD();
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, -2, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
            }
        }
    }
});

const blit_pass = gfx_rg.Pass.implement(struct {
    pub fn setup(pass: *gfx_rg.Pass, builder: gfx_rg.GraphBuilder) !void {
        try builder.writeTexture(pass, gfx_rg.ViewportColorResource);
        try builder.readTexture(pass, "foo");
        try builder.addPass("blit", pass);
    }

    pub fn render(builder: gfx_rg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: Viewport, viewid: gfx.ViewId) !void {
        const fb_size = viewport.getSize();

        if (gfx_api.getEncoder()) |e| {
            const out_tex = builder.getTexture(gfx_rg.ViewportColorResource).?;
            const foo_tex = builder.getTexture("foo").?;
            e.blit(
                viewid,
                out_tex,
                0,
                0,
                0,
                0,
                foo_tex,
                0,
                0,
                0,
                0,
                @intFromFloat(fb_size[0]),
                @intFromFloat(fb_size[1]),
                0,
            );
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
            _g.rg = try _gfx_rg.create();
            try _g.rg.addPass(simple_pass);
            try _g.rg.addPass(blit_pass);

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
            _gfx_rg.destroy(_g.rg);
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
    _gfx = apidb.getZigApi(module_name, gfx.GfxApi).?;
    _gfx_rg = apidb.getZigApi(module_name, gfx_rg.GfxRGApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;
    _actions = apidb.getZigApi(module_name, actions.ActionsAPI).?;
    _graph = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    _viewport = apidb.getZigApi(module_name, cetech1.renderer.RendererApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVarValue(editor.EditorTabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.EditorTabTypeI, &foo_tab, load);

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

const SimpleFPSCamera = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    forward: [3]f32 = .{ 0.0, 0.0, 0.0 },
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    move_speed: f32 = 5.0,
    look_speed: f32 = 0.0025,

    pub fn init(params: SimpleFPSCamera) SimpleFPSCamera {
        var camera = params;
        camera.calcForward();
        return camera;
    }

    pub fn update(self: *SimpleFPSCamera, move: [2]f32, mouse_delta: [2]f32, dt: f32) void {
        const speed = zm.f32x4s(self.move_speed);
        const delta_time = zm.f32x4s(dt);

        // Look handle
        {
            self.pitch += self.look_speed * mouse_delta[1] * -1;
            self.yaw += self.look_speed * mouse_delta[0] * -1;
            self.pitch = @min(self.pitch, 0.48 * std.math.pi);
            self.pitch = @max(self.pitch, -0.48 * std.math.pi);
            self.yaw = zm.modAngle(self.yaw);

            self.calcForward();
        }

        // Move handle
        {
            var forward = zm.loadArr3(self.forward);
            const right = speed * delta_time * -zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 1.0), forward));
            forward = speed * delta_time * forward;

            var cam_pos = zm.loadArr3(self.position);
            cam_pos += forward * zm.f32x4s(move[1]);
            cam_pos += right * zm.f32x4s(move[0]);
            zm.storeArr3(&self.position, cam_pos);
        }
    }

    pub fn calcViewMtx(self: SimpleFPSCamera) [16]f32 {
        const viewMtx = zm.lookAtRh(
            zm.loadArr3(self.position),
            zm.loadArr3(self.position) + zm.loadArr3(self.forward),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );
        return zm.matToArr(viewMtx);
    }

    inline fn calcForward(self: *SimpleFPSCamera) void {
        const t = zm.mul(zm.rotationX(self.pitch), zm.rotationY(self.yaw));
        const forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 1.0), t));
        zm.storeArr3(&self.forward, forward);
    }
};
