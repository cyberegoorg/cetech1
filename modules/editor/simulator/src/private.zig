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

const camera = @import("camera");
const camera_controller = @import("camera_controller");
const transform = @import("transform");
const actions = @import("actions");

const render_viewport = @import("render_viewport");
const render_graph = @import("render_graph");
const light_component = @import("light_component");
const render_pipeline = @import("render_pipeline");
const physics = @import("physics");
const editor_tabs = @import("editor_tabs");

const Viewport = render_viewport.Viewport;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const module_name = .editor_simulator;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_simulator";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;
var _platform: *const cetech1.host.PlatformApi = undefined;

var _editor: *const editor.EditorAPI = undefined;
var _camera: *const camera.CameraAPI = undefined;
var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;
var _tabs: *const editor_tabs.TabsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor_tabs.TabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const SimulationTab = struct {
    tab_i: editor_tabs.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_ent: ecs.EntityId,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,

    render_pipeline: render_pipeline.RenderPipeline,

    flecs_port: ?u16 = null,

    explode_num: u32 = 100,
};

const seed: u64 = 1111;
var prng = std.Random.DefaultPrng.init(seed);

// Fill editor tab interface
var foo_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),

    //    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .show_pin_object = true,

    .ignore_selection_from_tab = &.{.fromStr("ct_editor_asset_browser_tab")},
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_GAMEPAD ++ "  " ++ "Simulator";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_GAMEPAD ++ "  " ++ "Simulator";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        const w = try _ecs.createWorld();
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Simulator {d}", .{tab_id});

        const camera_ent = w.newEntity(.{});
        _ = w.setComponent(camera.Camera, camera_ent, &camera.Camera{});
        _ = w.setComponent(camera_controller.CameraController, camera_ent, &camera_controller.CameraController{ .position = .{ .y = 2, .z = -12 } });

        const gpu_backend = _kernel.getGpuBackend().?;
        const pipeline = try _render_pipeline.createDefault(_allocator, gpu_backend, w);

        var tab_inst = _allocator.create(SimulationTab) catch undefined;
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
        const tab_o: *SimulationTab = @ptrCast(@alignCast(tab_inst.inst));
        _render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = dt; // autofix
        _ = kernel_tick;

        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        var entiy_obj = cdb.ObjId{};
        var selected_obj = cdb.ObjId{};

        selected_obj = tab_o.selection.top_level_obj;
        var db: cdb.DbId = undefined;
        if (!selected_obj.isEmpty()) {
            db = _cdb.getDbFromObjid(selected_obj);

            if (selected_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(_cdb, db))) {
                if (!_assetdb.isAssetObjTypeOf(selected_obj, ecs.EntityCdb.typeIdx(_cdb, db))) return;
                entiy_obj = _assetdb.getObjForAsset(selected_obj).?;
            } else if (selected_obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, db))) {
                entiy_obj = selected_obj;
            }
        }

        const new_entity = !tab_o.root_entity_obj.eql(entiy_obj);
        tab_o.root_entity_obj = entiy_obj;

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (new_entity) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
            }

            const ents = try _ecs.spawnManyFromCDB(allocator, tab_o.world, entiy_obj, 1);
            defer allocator.free(ents);

            tab_o.root_entity = ents[0];
        }

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

            // Only for editor camera
            if (tab_o.camera_ent == tab_o.viewport.getMainCamera()) {
                var controller = tab_o.world.getMutComponent(camera_controller.CameraController, tab_o.camera_ent).?;
                controller.input_enabled = hovered;
            }
        }

        tab_o.viewport.requestRender();
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);
            try _render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
        }

        if (try _camera.cameraMenu(allocator, tab_o.world, tab_o.camera_ent, tab_o.viewport.getMainCamera())) |c| {
            tab_o.viewport.setMainCamera(c);
        }

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Explosion, true, null)) {
            defer _coreui.endMenu();

            _ = _coreui.dragU32("", .{ .v = &tab_o.explode_num });

            _coreui.sameLine(.{});

            if (_coreui.button(cetech1.coreui.Icons.Explosion, .{})) {
                if (tab_o.root_entity) |root_ent| {
                    tab_o.world.destroyEntities(&.{root_ent});
                }

                const entities = try _ecs.spawnManyFromCDB(allocator, tab_o.world, tab_o.root_entity_obj, tab_o.explode_num);
                defer allocator.free(entities);

                const rnd = prng.random();

                // Spawn light
                const light_ent = tab_o.world.newEntity(.{});
                _ = tab_o.world.setComponent(transform.LocalTransformComponent, light_ent, &transform.LocalTransformComponent{ .local = .{ .position = .{ .y = 20 } } });
                _ = tab_o.world.setComponent(light_component.Light, light_ent, &light_component.Light{ .radius = 100, .power = 10000 });

                // Set random velocity.
                for (entities) |ent| {
                    _ = tab_o.world.setComponent(physics.Velocity, ent, &physics.Velocity{
                        .y = (rnd.float(f32) * 2 - 1) * 3.0,
                        .x = (rnd.float(f32) * 2 - 1) * 3.0,
                        .z = (rnd.float(f32) * 2 - 1) * 3.0,
                    });
                }
            }
        }

        _coreui.separatorMenu();
        tab_o.world.debuguiMenuItems(allocator);
        _coreui.separatorMenu();

        if (_coreui.menuItem(allocator, cetech1.coreui.Icons.Restart, .{}, null)) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
                tab_o.root_entity = null;
            }

            if (!tab_o.root_entity_obj.isEmpty()) {
                const ents = try _ecs.spawnManyFromCDB(allocator, tab_o.world, tab_o.root_entity_obj, 1);
                defer allocator.free(ents);
                tab_o.root_entity = ents[0];
            }
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) return;

        const db = _cdb.getDbFromObjid(selected.obj);
        if (_assetdb.isAssetObjTypeOf(selected.obj, ecs.EntityCdb.typeIdx(_cdb, db))) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, db))) {
            tab_o.selection = selected;
        }
    }

    pub fn focused(inst: *editor_tabs.TabO) !void {
        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        if (!tab_o.selection.isEmpty()) {
            _tabs.propagateSelection(inst, &.{tab_o.selection});
        }
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectionItem) !bool {
        _ = allocator; // autofix
        const db = _cdb.getDbFromObjid(selection[0].obj);
        const EntityTypeIdx = ecs.EntityCdb.typeIdx(_cdb, db);
        const AssetTypeIdx = assetdb.AssetCdb.typeIdx(_cdb, db);
        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(EntityTypeIdx) and !obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (!o.type_idx.eql(EntityTypeIdx)) return false;
        }
        return true;
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "EditorSimulationTab",
    &[_]cetech1.StrId64{
        render_viewport.VIEWPORT_KERNEL_TASK,
    },
    struct {
        pub fn init() !void {}

        pub fn shutdown() !void {}
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

    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _platform = apidb.getZigApi(module_name, cetech1.host.PlatformApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _camera = apidb.getZigApi(module_name, camera.CameraAPI).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;
    _tabs = apidb.getZigApi(module_name, editor_tabs.TabsAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_simulator(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
