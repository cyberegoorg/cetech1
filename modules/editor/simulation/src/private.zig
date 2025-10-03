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

const camera = @import("camera");
const transform = @import("transform");
const editor_entity = @import("editor_entity");

const render_viewport = @import("render_viewport");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const Viewport = render_viewport.Viewport;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const module_name = .editor_simulation;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_simulation";

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
var _platform: *const cetech1.platform.PlatformApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _camera: *const camera.CameraAPI = undefined;
var _editor_entity: *const editor_entity.EditorEntityAPI = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const SimulationTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_look_activated: bool = false,
    camera_ent: ecs.EntityId,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,

    render_pipeline: render_pipeline.RenderPipeline,

    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
    }),

    flecs_port: ?u16 = null,

    world_mtx: [16]f32 = zm.matToArr(zm.identity()),
};

// Fill editor tab interface
var foo_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = cetech1.strId32(TAB_NAME),

    //    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .show_pin_object = true,

    .ignore_selection_from_tab = &.{cetech1.strId32("ct_editor_asset_browser_tab")},
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_GAMEPAD ++ "  " ++ "Entity simulation";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_GAMEPAD ++ "  " ++ "Entity simulation";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor.TabI {
        const w = try _ecs.createWorld();
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Entity simulation {d}", .{tab_id});

        const camera_ent = w.newEntity(null);
        _ = w.setId(transform.Position, camera_ent, &transform.Position{});
        _ = w.setId(transform.Rotation, camera_ent, &transform.Rotation{});
        _ = w.setId(camera.Camera, camera_ent, &camera.Camera{});

        var tab_inst = _allocator.create(SimulationTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _render_viewport.createViewport(name, w, camera_ent),
            .world = w,
            .camera_ent = camera_ent,
            .render_pipeline = try _render_pipeline.createDefault(_allocator, w),
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *SimulationTab = @ptrCast(@alignCast(tab_inst.inst));
        _render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = dt; // autofix
        _ = kernel_tick;

        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        var entiy_obj = cdb.ObjId{};
        var selected_obj = cdb.ObjId{};

        selected_obj = tab_o.selection.top_level_obj;
        var db: cdb.DbId = undefined;
        if (!selected_obj.isEmpty()) {
            db = _cdb.getDbFromObjid(selected_obj);

            if (selected_obj.type_idx.eql(assetdb.Asset.typeIdx(_cdb, db))) {
                if (!_assetdb.isAssetObjTypeOf(selected_obj, ecs.Entity.typeIdx(_cdb, db))) return;
                entiy_obj = _assetdb.getObjForAsset(selected_obj).?;
            } else if (selected_obj.type_idx.eql(ecs.Entity.typeIdx(_cdb, db))) {
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

            tab_o.camera = camera.SimpleFPSCamera.init(.{
                .position = .{ 0, 2, -12 },
            });
        }

        const size = _coreui.getContentRegionAvail();
        tab_o.viewport.setSize(size);

        if (tab_o.viewport.getTexture()) |texture| {
            _coreui.image(
                texture,
                .{
                    .w = size[0],
                    .h = size[1],
                },
            );
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
        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Camera, true, null)) {
            defer _coreui.endMenu();

            if (_coreui.beginMenu(allocator, "Active camera", true, null)) {
                defer _coreui.endMenu();
                if (try _camera.selectMainCameraMenu(allocator, tab_o.world, tab_o.camera_ent, tab_o.viewport.getMainCamera())) |c| {
                    tab_o.viewport.setMainCamera(c);
                }
            }

            if (_coreui.beginMenu(allocator, "Editor camera", true, null)) {
                defer _coreui.endMenu();
                _camera.cameraSetingsMenu(tab_o.world, tab_o.camera_ent);
            }
        }

        const is_simulate = tab_o.world.isSimulate();

        if (_coreui.menuItem(allocator, if (!is_simulate) cetech1.coreui.Icons.Play else cetech1.coreui.Icons.Pause, .{}, null)) {
            tab_o.world.setSimulate(!is_simulate);
        }

        if (_coreui.menuItem(allocator, cetech1.coreui.Icons.Restart, .{}, null)) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
            }

            const ents = try _ecs.spawnManyFromCDB(allocator, tab_o.world, tab_o.root_entity_obj, 1);
            defer allocator.free(ents);
            tab_o.root_entity = ents[0];

            tab_o.camera = camera.SimpleFPSCamera.init(.{
                .position = .{ 0, 2, -12 },
            });
        }

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            _render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
            tab_o.flecs_port = _editor_entity.uiRemoteDebugMenuItems(&tab_o.world, allocator, tab_o.flecs_port);
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) return;

        const db = _cdb.getDbFromObjid(selected.obj);
        if (_assetdb.isAssetObjTypeOf(selected.obj, ecs.Entity.typeIdx(_cdb, db))) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(ecs.Entity.typeIdx(_cdb, db))) {
            tab_o.selection = selected;
        }
    }

    pub fn focused(inst: *editor.TabO) !void {
        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        if (!tab_o.selection.isEmpty()) {
            _editor.propagateSelection(inst, &.{tab_o.selection});
        }
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectionItem) !bool {
        _ = allocator; // autofix
        const db = _cdb.getDbFromObjid(selection[0].obj);
        const EntityTypeIdx = ecs.Entity.typeIdx(_cdb, db);
        const AssetTypeIdx = assetdb.Asset.typeIdx(_cdb, db);
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
    _platform = apidb.getZigApi(module_name, cetech1.platform.PlatformApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _camera = apidb.getZigApi(module_name, camera.CameraAPI).?;
    _editor_entity = apidb.getZigApi(module_name, editor_entity.EditorEntityAPI).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_simulation(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
