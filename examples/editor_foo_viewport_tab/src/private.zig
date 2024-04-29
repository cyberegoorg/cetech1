const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gpu = cetech1.gpu;
const gfx = cetech1.gfx;
const gfx_dd = cetech1.gfx.dd;
const gfx_rg = cetech1.gfx.rg;
const zm = cetech1.zmath;
const ecs = cetech1.ecs;
const primitives = cetech1.primitives;

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
var _gfx: *const gfx.GfxApi = undefined;
var _gfx_rg: *const gfx_rg.GfxRGApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.EditorTabTypeI = undefined,
    rg: gfx_rg.RenderGraph = undefined,
};
var _g: *G = undefined;

const SPHERE_COUNT = 10_000;

const seed: u64 = 1111;
var prng = std.rand.DefaultPrng.init(seed);

// Struct for tab type
const FooViewportTab = struct {
    tab_i: editor.EditorTabI,
    viewport: gpu.GpuViewport = undefined,
    world: ecs.World,
    last_pos: [2]f32 = .{ 0.0, 0.0 },
    camera_look_activated: bool = false,

    camera: SimpleFPSCamera = SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
        .yaw = std.math.degreesToRadians(180),
    }),
};

// Some components and systems
const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};
const Velocity = struct {
    x: f32,
    y: f32,
    z: f32,
};
const Sphere = struct {
    radius: f32,
};

const position_c = ecs.ComponentI.implement(Position);
const celocity_c = ecs.ComponentI.implement(Velocity);
const sphere_c = ecs.ComponentI.implement(Sphere);

const move_system_i = ecs.SystemI.implement(
    .{
        .name = "move system",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .query = &.{
            .{ .id = ecs.id(Position) },
            .{ .id = ecs.id(Velocity), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *ecs.IterO) !void {
            const it = _ecs.toIter(iter);

            const p = it.field(Position, 1).?;
            const v = it.field(Velocity, 2).?;

            for (0..it.count()) |i| {
                p[i].x += v[i].x;
                p[i].y += v[i].y;
                p[i].z += v[i].z;
            }
        }
    },
);

// Rendering component
const SphereRenderParam = struct {
    viewers: []gfx_rg.Viewer,
    result: *gfx_rg.CullingResult,
};

const position_renderer_i = gfx_rg.ComponentRendererI.implement(struct {
    pub fn culling(allocator: std.mem.Allocator, builder: gfx_rg.GraphBuilder, world: ecs.World, viewers: []gfx_rg.Viewer) !gfx_rg.CullingResult {
        _ = builder; // autofix

        var result = gfx_rg.CullingResult.init(allocator);
        world.runSystem(
            cetech1.strid.strId32("sphere_culling"),
            &SphereRenderParam{
                .result = &result,
                .viewers = viewers,
            },
        );
        return result;
    }

    pub fn render(builder: gfx_rg.GraphBuilder, world: ecs.World, viewport: gpu.GpuViewport, culling_result: ?gfx_rg.CullingResult) !void {
        _ = world; // autofix

        const layer = builder.getLayer("color");
        if (_gfx.getEncoder()) |e| {
            const dd = viewport.getDD();
            {
                dd.begin(layer, true, e);
                defer dd.end();

                if (culling_result) |result| {
                    for (result.renderables.items, result.mtx.items) |r, mtx| {
                        const s: *const Sphere = @alignCast(@ptrCast(r));

                        {
                            dd.pushTransform(@ptrCast(&mtx));
                            defer dd.popTransform();

                            dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
                            dd.drawSphere(.{ 0, 0, 0 }, s.radius);
                        }
                    }
                }
            }
        }
    }
});

// Fill editor tab interface
var foo_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ " Foo viewport";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ " Foo viewport";
    }

    // Create new tab instantce
    pub fn create(db: cdb.Db) !?*editor.EditorTabI {
        _ = db;
        const w = try _ecs.createWorld();

        var tab_inst = _allocator.create(FooViewportTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _gpu.createViewport(_g.rg, w),
            .world = w,
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        // Sphere culling system
        _ = try w.createSystem(
            "sphere_culling",
            &.{
                .{ .id = ecs.id(Position), .inout = .In },
                .{ .id = ecs.id(Sphere), .inout = .In },
            },
            struct {
                pub fn update(iter: *ecs.IterO) !void {
                    const it = _ecs.toIter(iter);
                    const param = it.getParam(SphereRenderParam).?;

                    const frustrum_planes = primitives.buildFrustumPlanes(param.viewers[0].mtx);

                    const p = it.field(Position, 1).?;
                    const s = it.field(Sphere, 2).?;

                    for (0..it.count()) |i| {
                        if (primitives.frustumPlanesVsSphere(
                            frustrum_planes,
                            .{ p[i].x, p[i].y, p[i].z },
                            s[i].radius,
                        )) {
                            const model_mat = zm.translation(p[i].x, p[i].y, p[i].z);
                            try param.result.append(zm.matToArr(model_mat), &s[i]);
                        }
                    }
                }
            },
        );

        var allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (w.newEntities(allocator, SPHERE_COUNT)) |entities| {
            defer allocator.free(entities);

            const rnd = prng.random();

            for (entities) |ent| {
                _ = w.setId(
                    Position,
                    ent,
                    &Position{
                        .x = (rnd.float(f32) * 2 - 1) * 30,
                        .y = (rnd.float(f32) * 2 - 1) * 30,
                        .z = (rnd.float(f32) * 2 - 1) * 30,
                    },
                );

                _ = w.setId(Velocity, ent, &Velocity{
                    .x = (rnd.float(f32) * 2 - 1) * 0.1,
                    .y = (rnd.float(f32) * 2 - 1) * 0.1,
                    .z = (rnd.float(f32) * 2 - 1) * 0.1,
                });

                _ = w.setId(Sphere, ent, &Sphere{
                    .radius = rnd.float(f32) * 2,
                });
            }
        }

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(tab_inst.inst));
        _gpu.destroyViewport(tab_o.viewport);
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

            const mouse_pos = _coreui.getMousePos();
            const camera_look_activated = _coreui.isMouseDown(.left);

            if (hovered and camera_look_activated) {
                tab_o.camera_look_activated = true;
                _kernel.getMainWindow().?.setCursorMode(.disabled);
            }

            if (tab_o.camera_look_activated and !camera_look_activated) {
                tab_o.camera_look_activated = false;
                _kernel.getMainWindow().?.setCursorMode(.normal);
            }

            if (tab_o.camera_look_activated) {
                const mouse_delta = if (tab_o.last_pos[0] == 0 and tab_o.last_pos[1] == 0) .{ 0, 0 } else .{
                    tab_o.last_pos[0] - mouse_pos[0],
                    mouse_pos[1] - tab_o.last_pos[1],
                };

                const move_forward: f32 = if (_coreui.isKeyDown(.w)) 1 else if (_coreui.isKeyDown(.s)) -1 else 0;
                const move_right: f32 = if (_coreui.isKeyDown(.d)) 1 else if (_coreui.isKeyDown(.a)) -1 else 0;

                tab_o.camera.update(move_forward, move_right, mouse_delta, dt);
            }
            tab_o.last_pos = mouse_pos;
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

    pub fn render(builder: gfx_rg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: gpu.GpuViewport, viewid: gfx.ViewId) !void {
        _ = builder; // autofix

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

    pub fn render(builder: gfx_rg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: gpu.GpuViewport, viewid: gfx.ViewId) !void {
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

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "FooViewportTab",
    &[_]cetech1.strid.StrId64{},
    struct {
        pub fn init() !void {
            _g.rg = try _gfx_rg.create();
            try _g.rg.addPass(simple_pass);
            try _g.rg.addPass(blit_pass);
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
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _gfx = apidb.getZigApi(module_name, gfx.GfxApi).?;
    _gfx_rg = apidb.getZigApi(module_name, gfx_rg.GfxRGApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVar(editor.EditorTabTypeI, module_name, TAB_NAME, .{});
    // Patch vt pointer to new.
    _g.test_tab_vt_ptr.* = foo_tab;

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.EditorTabTypeI, &foo_tab, load);

    // Components
    try apidb.implInterface(module_name, ecs.ComponentI, &position_c);
    try apidb.implInterface(module_name, ecs.ComponentI, &celocity_c);
    try apidb.implInterface(module_name, ecs.ComponentI, &sphere_c);

    try apidb.implInterface(module_name, ecs.SystemI, &move_system_i);

    try apidb.implInterface(module_name, gfx_rg.ComponentRendererI, &position_renderer_i);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_foo_viewport_tab(__apidb: *const cetech1.apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
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

    pub fn update(self: *SimpleFPSCamera, updown: f32, rightleft: f32, mouse_delta: [2]f32, dt: f32) void {
        const speed = zm.f32x4s(self.move_speed);
        const delta_time = zm.f32x4s(dt);

        // Look handle
        {
            self.pitch += self.look_speed * mouse_delta[1];
            self.yaw += self.look_speed * mouse_delta[0];
            self.pitch = @min(self.pitch, 0.48 * std.math.pi);
            self.pitch = @max(self.pitch, -0.48 * std.math.pi);
            self.yaw = zm.modAngle(self.yaw);

            self.calcForward();
        }

        // Move handle
        {
            var forward = zm.loadArr3(self.forward);
            const right = speed * delta_time * -zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
            forward = speed * delta_time * forward;

            var cam_pos = zm.loadArr3(self.position);
            cam_pos += forward * zm.f32x4s(updown);
            cam_pos += right * zm.f32x4s(rightleft);
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
        const transform = zm.mul(zm.rotationX(self.pitch), zm.rotationY(self.yaw));
        const forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));
        zm.storeArr3(&self.forward, forward);
    }
};
