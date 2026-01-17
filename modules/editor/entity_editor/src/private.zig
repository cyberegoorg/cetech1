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

const render_viewport = @import("render_viewport");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const light_component = @import("light_component");
const Viewport = render_viewport.Viewport;
const graphvm = @import("graphvm");
const editor = @import("editor");
const editor_tabs = @import("editor_tabs");
const editor_gizmo = @import("editor_gizmo");

const public = @import("entity_editor.zig");

const Icons = coreui.CoreIcons;

const module_name = .editor_entity;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_entity";

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
var _platform: *const cetech1.host.PlatformApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _camera: *const camera.CameraAPI = undefined;
var _graphvm: *const graphvm.GraphVMApi = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;
var _camera_controller: *const camera_controller.CameraControllerAPI = undefined;
var _gizmo: *const editor_gizmo.EditorGizmoApi = undefined;
var _tabs: *const editor_tabs.TabsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor_tabs.TabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const EntityEditorTab = struct {
    tab_i: editor_tabs.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_ent: ecs.EntityId,
    light_ent: ?ecs.EntityId = null,

    render_pipeline: render_pipeline.RenderPipeline,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,
    db: cdb.DbId = .{},

    selected_component: ?cdb.ObjId = null,
    selected_ent_obj: ?cdb.ObjId = null,
    selected_ent: ?ecs.EntityId = null,

    gizmo_options: editor.GizmoOptions = .{},

    flecs_port: ?u16 = null,
};

// Fill editor tab interface
var foo_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),

    // TODO: Bug on linux CI
    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .show_pin_object = true,

    .ignore_selection_from_tab = &.{.fromStr("ct_editor_asset_browser_tab")},
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ "  " ++ "Entity editor";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ "  " ++ "Entity editor";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        const w = try _ecs.createWorld();
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Entity {d}", .{tab_id});

        const camera_ent = w.newEntity(.{});
        _ = w.setComponent(camera.Camera, camera_ent, &camera.Camera{});
        _ = w.setComponent(camera_controller.CameraController, camera_ent, &camera_controller.CameraController{ .position = .{ .y = 2, .z = -12 } });

        const gpu_backend = _kernel.getGpuBackend().?;
        const pipeline = try _render_pipeline.createDefault(_allocator, gpu_backend, w);

        var tab_inst = _allocator.create(EntityEditorTab) catch undefined;
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

        // tab_inst.viewport.setDebugCulling(true);

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(tab_inst.inst));
        _render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        const wpos = _coreui.getWindowPos();
        const cpos = _coreui.getCursorPos();
        const size = _coreui.getContentRegionAvail();
        const wsize = _coreui.getWindowSize();

        tab_o.viewport.setSize(size);

        if (tab_o.selected_ent_obj == null) {
            const txt = "Open entity";
            const txt_size = _coreui.calcTextSize(txt, .{});
            _coreui.setCursorPosX(wsize.x / 2 - txt_size.x / 2);
            _coreui.setCursorPosY(wsize.y / 2 + txt_size.y);
            _coreui.text(txt);
            return;
        }

        var hovered = false;
        if (tab_o.viewport.getTexture()) |texture| {
            _coreui.image(
                texture,
                .{
                    .w = size.x,
                    .h = size.y,
                },
            );
            hovered = _coreui.isItemHovered(.{});

            if (_coreui.beginDragDropTarget()) {
                defer _coreui.endDragDropTarget();
                if (_coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
                    const drag_obj: cdb.ObjId = std.mem.bytesToValue(cdb.ObjId, payload.data.?);

                    if (drag_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(_cdb, tab_o.db))) {
                        const asset_entity_obj = _assetdb.getObjForAsset(drag_obj).?;
                        if (!tab_o.root_entity_obj.eql(asset_entity_obj)) {
                            if (asset_entity_obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, tab_o.db))) {
                                const new_obj = try _cdb.createObjectFromPrototype(asset_entity_obj);

                                const new_obj_w = ecs.EntityCdb.write(_cdb, new_obj).?;
                                const entiy_obj_w = ecs.EntityCdb.write(_cdb, tab_o.root_entity_obj).?;

                                try ecs.EntityCdb.addSubObjToSet(_cdb, entiy_obj_w, .Childrens, &.{new_obj_w});

                                try ecs.EntityCdb.commit(_cdb, new_obj_w);
                                try ecs.EntityCdb.commit(_cdb, entiy_obj_w);
                            }
                        }
                    }
                }
            }
        }

        var gizmo_result: editor_gizmo.GizmoResult = .{};
        if (tab_o.root_entity != null) {
            const tranform = tab_o.world.getComponent(transform.WorldTransformComponent, tab_o.camera_ent).?;
            const ed_camera = tab_o.world.getComponent(camera.Camera, tab_o.camera_ent).?;

            const view = tranform.world.inverse().toMat();
            const projection = _camera.projectionMatrixFromCamera(
                ed_camera.*,
                size.x,
                size.y,
                _kernel.getGpuBackend().?.isHomogenousDepth(),
            );

            _coreui.pushPtrId(tab_o);
            defer _coreui.popId();

            if (tab_o.selected_component) |obj| {
                const ent_obj = _cdb.getParent(obj);

                if (tab_o.selected_ent) |ent| {
                    gizmo_result = try _gizmo.ecsGizmo(
                        allocator,
                        tab_o.gizmo_options,
                        tab_o.db,
                        tab_o.world,
                        ent,
                        ent_obj,
                        obj,
                        view,
                        projection,
                        wpos.add(cpos),
                        size,
                    );
                }
            } else if (tab_o.selected_ent) |ent| {
                gizmo_result = try _gizmo.ecsGizmo(
                    allocator,
                    tab_o.gizmo_options,
                    tab_o.db,
                    tab_o.world,
                    ent,
                    tab_o.selected_ent_obj.?,
                    null,
                    view,
                    projection,
                    wpos.add(cpos),
                    size,
                );
            }
        }

        var controller = tab_o.world.getMutComponent(camera_controller.CameraController, tab_o.camera_ent).?;
        controller.input_enabled = !gizmo_result.using and hovered;

        tab_o.viewport.requestRender();
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));

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

        if (_coreui.menuItem(allocator, cetech1.coreui.CoreIcons.FA_GAMEPAD, .{}, null)) {
            _tabs.openTabWithPinnedObj(.fromStr("ct_editor_simulator"), .{
                .top_level_obj = tab_o.selection.top_level_obj,
                .obj = tab_o.selection.top_level_obj,
            });
        }

        if (tab_o.selected_ent) |ent| {
            _coreui.separatorMenu();
            try _gizmo.ecsGizmoMenu(
                allocator,
                tab_o.world,
                ent,
                tab_o.selected_ent_obj.?,
                tab_o.selected_component,
                &tab_o.gizmo_options,
            );
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) {
            tab_o.selection = selected;
            tab_o.selected_ent = null;
            tab_o.selected_ent_obj = null;
            tab_o.selected_component = null;
            return;
        }

        const db = _cdb.getDbFromObjid(selected.obj);

        const component_hash: cetech1.StrId32 = _cdb.getTypeHash(db, selected.obj.type_idx) orelse .{};
        if (_assetdb.isAssetObjTypeOf(selected.obj, ecs.EntityCdb.typeIdx(_cdb, db))) {
            tab_o.selection = selected;
            tab_o.selected_ent_obj = _assetdb.getObjForAsset(selected.obj);
            tab_o.selected_component = null;
        } else if (selected.obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, db))) {
            tab_o.selection = selected;
            tab_o.selected_ent_obj = selected.obj;
            tab_o.selected_component = null;
        } else if (_ecs.findComponentIByCdbHash(component_hash) != null) {
            tab_o.selection = selected;
            tab_o.selected_ent_obj = _cdb.getParent(selected.obj);
            tab_o.selected_component = selected.obj;
        }

        var top_level_obj = tab_o.selection.top_level_obj;
        var top_level_entiy_obj = cdb.ObjId{};

        tab_o.db = db;

        if (!top_level_obj.isEmpty()) {
            if (top_level_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(_cdb, db))) {
                if (!_assetdb.isAssetObjTypeOf(top_level_obj, ecs.EntityCdb.typeIdx(_cdb, db))) return;
                top_level_entiy_obj = _assetdb.getObjForAsset(top_level_obj).?;
            } else if (top_level_obj.type_idx.eql(ecs.EntityCdb.typeIdx(_cdb, db))) {
                top_level_entiy_obj = top_level_obj;
            }
        }

        const new_entity = !tab_o.root_entity_obj.eql(top_level_entiy_obj);
        tab_o.root_entity_obj = top_level_entiy_obj;

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (new_entity) {
            if (tab_o.light_ent) |ent| tab_o.world.destroyEntities(&.{ent});
            tab_o.viewport.frezeMainCameraCulling(false);

            _ = tab_o.world.setComponent(
                camera_controller.CameraController,
                tab_o.camera_ent,
                &camera_controller.CameraController{ .position = .{ .y = 2, .z = -12 } },
            );

            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
                // tab_o.world.clear();
            }

            const ents = try _ecs.spawnManyFromCDB(allocator, tab_o.world, top_level_entiy_obj, 1);
            defer allocator.free(ents);
            tab_o.root_entity = ents[0];

            {
                var q = try tab_o.world.createQuery(.{
                    .query = &.{
                        .{ .id = ecs.id(light_component.Light), .inout = .In },
                    },
                });
                defer q.destroy();
                const light_component_n = q.count().entities;
                if (light_component_n == 0) {
                    tab_o.light_ent = tab_o.world.newEntity(.{});

                    _ = tab_o.world.setComponent(
                        transform.LocalTransformComponent,
                        tab_o.light_ent.?,
                        &transform.LocalTransformComponent{
                            .local = .{
                                .position = .{ .y = 20 },
                                .rotation = .fromRollPitchYaw(-130, 180, 0),
                            },
                        },
                    );

                    _ = tab_o.world.setComponent(
                        light_component.Light,
                        tab_o.light_ent.?,
                        &light_component.Light{
                            .type = .Direction,
                            .radius = 10000,
                            .power = 1.0,
                        },
                    );
                }
            }
        }

        if (tab_o.selected_ent_obj) |selected_ent_obj| {
            if (try tab_o.world.findEntityByCdbObj(selected_ent_obj)) |ent| {
                tab_o.selected_ent = ent;
                tab_o.viewport.setSelectedEntity(ent);
            } else {
                tab_o.selected_ent = null;
                tab_o.viewport.setSelectedEntity(null);
            }
        }
    }

    pub fn focused(inst: *editor_tabs.TabO) !void {
        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));

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

    pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));
        if (tab_o.root_entity) |ent| {
            tab_o.world.destroyEntities(&.{ent});

            tab_o.selection = coreui.SelectionItem.empty();
            tab_o.root_entity_obj = .{};
            tab_o.root_entity = null;
            tab_o.selected_ent_obj = null;
            tab_o.selected_component = null;
            tab_o.selected_ent = null;
        }
    }
});

const entity_value_type_i = graphvm.GraphValueTypeI.implement(
    ecs.EntityId,
    .{
        .name = "entity",
        .type_hash = graphvm.PinTypes.Entity,
        .cdb_type_hash = cetech1.cdb_types.u64TypeCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cetech1.cdb_types.u64TypeCdb.readValue(u64, _cdb, _cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(u64, value)}, 0);
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
    _camera_controller = apidb.getZigApi(module_name, camera_controller.CameraControllerAPI).?;
    _graphvm = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;
    _gizmo = apidb.getZigApi(module_name, editor_gizmo.EditorGizmoApi).?;
    _tabs = apidb.getZigApi(module_name, editor_tabs.TabsAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &foo_tab, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &entity_value_type_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_entity(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
