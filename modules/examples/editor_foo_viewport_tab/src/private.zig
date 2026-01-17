const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gpu = cetech1.gpu;
const ecs = cetech1.ecs;
const assetdb = cetech1.assetdb;
const uuid = cetech1.uuid;
const task = cetech1.task;

const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");
const editor = @import("editor");
const editor_tabs = @import("editor_tabs");
const transform = @import("transform");
const camera = @import("camera");
const camera_controller = @import("camera_controller");
const render_graph = @import("render_graph");

const Icons = coreui.CoreIcons;
const Viewport = render_viewport.Viewport;

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

var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;
var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _camera_controller: *const camera_controller.CameraControllerAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor_tabs.TabTypeI = undefined,
    db: cdb.DbId = undefined, // TODO: SHIT
};
var _g: *G = undefined;

// Struct for tab type
const FooViewportTab = struct {
    tab_i: editor_tabs.TabI,
    viewport: Viewport = undefined,
    world: ecs.World,

    render_pipeline: render_pipeline.RenderPipeline,

    camera_ent: ecs.EntityId,

    flecs_port: ?u16 = null,
};

// Fill editor tab interface
var foo_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),
    .category = "Examples",
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ "  " ++ "Foo viewport";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ "  " ++ "Foo viewport";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        const w = try _ecs.createWorld();

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Foo viewport {d}", .{tab_id});

        const camera_ent = w.newEntity(.{});
        _ = w.setComponent(camera.Camera, camera_ent, &camera.Camera{});
        _ = w.setComponent(camera_controller.CameraController, camera_ent, &camera_controller.CameraController{ .position = .{ .y = 2, .z = -12 } });

        const gpu_backend = _kernel.getGpuBackend().?;
        const pipeline = try _render_pipeline.createDefault(_allocator, gpu_backend, w);

        var tab_inst = _allocator.create(FooViewportTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _render_viewport.createViewport(name, gpu_backend, pipeline, w, false),
            .world = w,
            .camera_ent = camera_ent,
            .render_pipeline = pipeline,
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        tab_inst.viewport.setMainCamera(tab_inst.camera_ent);

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *FooViewportTab = @ptrCast(@alignCast(tab_inst.inst));
        _render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const tab_o: *FooViewportTab = @ptrCast(@alignCast(inst));
        const size = _coreui.getContentRegionAvail();
        tab_o.viewport.setSize(size);

        if (tab_o.viewport.getTexture()) |texture| {
            _coreui.image(
                texture,
                .{
                    .w = size.x,
                    .h = size.y,
                },
            );
            const hovered = _coreui.isItemHovered(.{});

            var controller = tab_o.world.getMutComponent(camera_controller.CameraController, tab_o.camera_ent).?;
            controller.input_enabled = hovered;
        }

        tab_o.viewport.requestRender();
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *FooViewportTab = @ptrCast(@alignCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);
            try _render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
        }
    }
});

// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;
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

    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;

    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &foo_tab, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_foo_viewport_tab(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
