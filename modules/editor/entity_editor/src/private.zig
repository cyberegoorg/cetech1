const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gpu = cetech1.gpu;

const kernel = cetech1.kernel;
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
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_entity";

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;

var _platform: *const cetech1.host.PlatformApi = undefined;

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

    selection: coreui.SelectedObj = coreui.SelectedObj.empty(),
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
        return coreui.Icons.Entity ++ "  " ++ "Entity editor";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Entity ++ "  " ++ "Entity editor";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        const w = try ecs.createWorld();
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Entity {d}", .{tab_id});

        const camera_ent = w.newEntity(.{});
        _ = w.setComponent(camera.Camera, camera_ent, &camera.Camera{});
        _ = w.setComponent(camera_controller.CameraController, camera_ent, &camera_controller.CameraController{ .position = .{ .y = 2, .z = -12 } });

        const gpu_backend = kernel.getGpuBackend().?;
        const pipeline = try render_pipeline.createDefault(_allocator, gpu_backend, w);

        var tab_inst = _allocator.create(EntityEditorTab) catch undefined;
        tab_inst.* = .{
            .viewport = try render_viewport.createViewport(name, gpu_backend, pipeline, w, false),
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
        render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        const wpos = coreui.getWindowPos();
        const cpos = coreui.getCursorPos();
        const size = coreui.getContentRegionAvail();
        const wsize = coreui.getWindowSize();

        tab_o.viewport.setSize(size);

        if (tab_o.selected_ent_obj == null) {
            const txt = "Open entity";
            const txt_size = coreui.calcTextSize(txt, .{});
            coreui.setCursorPosX(wsize.x / 2 - txt_size.x / 2);
            coreui.setCursorPosY(wsize.y / 2 + txt_size.y);
            coreui.text(txt);
            return;
        }

        var hovered = false;
        if (tab_o.viewport.getTexture()) |texture| {
            coreui.image(
                texture,
                .{
                    .w = size.x,
                    .h = size.y,
                },
            );
            hovered = coreui.isItemHovered(.{});

            if (coreui.beginDragDropTarget()) {
                defer coreui.endDragDropTarget();
                if (coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
                    const drag_obj: cdb.ObjId = payload.toValue(cdb.ObjId);

                    if (drag_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(tab_o.db))) {
                        const asset_entity_obj = assetdb.getObjForAsset(drag_obj).?;
                        if (!tab_o.root_entity_obj.eql(asset_entity_obj)) {
                            if (asset_entity_obj.type_idx.eql(ecs.EntityCdb.typeIdx(tab_o.db))) {
                                const new_obj = try cdb.createObjectFromPrototype(asset_entity_obj);

                                const new_obj_w = ecs.EntityCdb.write(new_obj).?;
                                const entiy_obj_w = ecs.EntityCdb.write(tab_o.root_entity_obj).?;

                                try ecs.EntityCdb.addSubObjToSet(entiy_obj_w, .Childrens, &.{new_obj_w});

                                try ecs.EntityCdb.commit(new_obj_w);
                                try ecs.EntityCdb.commit(entiy_obj_w);
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
            const projection = camera.projectionMatrixFromCamera(
                ed_camera.*,
                size.x,
                size.y,
                kernel.getGpuBackend().?.isHomogenousDepth(),
            );

            coreui.pushPtrId(tab_o);
            defer coreui.popId();

            if (tab_o.selected_component) |obj| {
                const ent_obj = cdb.getParent(obj);

                if (tab_o.selected_ent) |ent| {
                    gizmo_result = try editor_gizmo.ecsGizmo(
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
                gizmo_result = try editor_gizmo.ecsGizmo(
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

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer coreui.endMenu();

            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);

            try render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
        }

        if (try camera.cameraMenu(allocator, tab_o.world, tab_o.camera_ent, tab_o.viewport.getMainCamera())) |c| {
            tab_o.viewport.setMainCamera(c);
        }

        if (coreui.menuItem(allocator, cetech1.coreui.Icons.Gamepad, .{}, null)) {
            editor_tabs.openTabWithPinnedObj(.fromStr("ct_editor_simulator"), .{
                .top_level_obj = tab_o.selection.top_level_obj,
                .obj = tab_o.selection.top_level_obj,
            });
        }

        if (tab_o.selected_ent) |ent| {
            coreui.separatorMenu();
            try editor_gizmo.ecsGizmoMenu(
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
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectedObj, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash;
        var tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) {
            tab_o.selection = selected;
            tab_o.selected_ent = null;
            tab_o.selected_ent_obj = null;
            tab_o.selected_component = null;
            return;
        }

        const db = cdb.getDbFromObjid(selected.obj);

        const component_hash: cetech1.StrId32 = cdb.getTypeHash(db, selected.obj.type_idx) orelse .{};
        if (assetdb.isAssetObjTypeOf(selected.obj, ecs.EntityCdb.typeIdx(db))) {
            tab_o.selection = selected;
            tab_o.selected_ent_obj = assetdb.getObjForAsset(selected.obj);
            tab_o.selected_component = null;
        } else if (selected.obj.type_idx.eql(ecs.EntityCdb.typeIdx(db))) {
            tab_o.selection = selected;
            tab_o.selected_ent_obj = selected.obj;
            tab_o.selected_component = null;
        } else if (ecs.findComponentIByCdbHash(component_hash) != null) {
            tab_o.selection = selected;
            tab_o.selected_ent_obj = cdb.getParent(selected.obj);
            tab_o.selected_component = selected.obj;
        }

        var top_level_obj = tab_o.selection.top_level_obj;
        var top_level_entiy_obj = cdb.ObjId{};

        tab_o.db = db;

        if (!top_level_obj.isEmpty()) {
            if (top_level_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(db))) {
                if (!assetdb.isAssetObjTypeOf(top_level_obj, ecs.EntityCdb.typeIdx(db))) return;
                top_level_entiy_obj = assetdb.getObjForAsset(top_level_obj).?;
            } else if (top_level_obj.type_idx.eql(ecs.EntityCdb.typeIdx(db))) {
                top_level_entiy_obj = top_level_obj;
            }
        }

        const new_entity = !tab_o.root_entity_obj.eql(top_level_entiy_obj);
        tab_o.root_entity_obj = top_level_entiy_obj;

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

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

            const ents = try ecs.spawnManyFromCDB(allocator, tab_o.world, top_level_entiy_obj, 1);
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
            editor_tabs.propagateSelection(inst, &.{tab_o.selection});
        }
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectedObj) !bool {
        _ = allocator;
        const db = cdb.getDbFromObjid(selection[0].obj);
        const EntityTypeIdx = ecs.EntityCdb.typeIdx(db);
        const AssetTypeIdx = assetdb.AssetCdb.typeIdx(db);
        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(EntityTypeIdx) and !obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (!o.type_idx.eql(EntityTypeIdx)) return false;
        }
        return true;
    }

    pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
        const tab_o: *EntityEditorTab = @ptrCast(@alignCast(inst));
        if (tab_o.root_entity) |ent| {
            tab_o.world.destroyEntities(&.{ent});

            tab_o.selection = coreui.SelectedObj.empty();
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
        .cdb_type_hash = cetech1.cdb_types.U64TypeCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cetech1.cdb_types.U64TypeCdb.readValue(u64, cdb.readObj(obj).?, .Value);
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
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;

    // basic
    _allocator = allocator;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);

    try render_graph.loadAPI(module_name);
    try kernel.loadAPI(module_name);
    try ecs.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    try render_viewport.loadAPI(module_name);
    _platform = apidb.getZigApi(module_name, cetech1.host.PlatformApi).?;
    try editor.loadAPI(module_name);
    try camera.loadAPI(module_name);
    try camera_controller.loadAPI(module_name);
    try graphvm.loadAPI(module_name);
    try render_pipeline.loadAPI(module_name);
    try editor_gizmo.loadAPI(module_name);
    try editor_tabs.loadAPI(module_name);

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
pub export fn ct_load_module_editor_entity(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
