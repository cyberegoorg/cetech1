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
const graphvm = graphvm;
const assetdb = cetech1.assetdb;
const uuid = cetech1.uuid;
const task = cetech1.task;
const transform = cetech1.transform;
const renderer = cetech1.renderer;
const camera = cetech1.camera;

const Viewport = renderer.Viewport;

const editor = @import("editor");
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
var _platform: *const cetech1.platform.PlatformApi = undefined;
var _editor: *const editor.EditorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
    rg: renderer.Graph = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const EntityEditorTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_look_activated: bool = false,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,

    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
        .yaw = std.math.degreesToRadians(180),
    }),

    flecs_port: ?u16 = null,

    world_mtx: [16]f32 = zm.matToArr(zm.identity()),
};

// Fill editor tab interface
var foo_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },

    // TODO: Bug on linux CI
    .create_on_init = true,
    .show_sel_obj_in_title = true,

    .ignore_selection_from_tab = &.{cetech1.strid.strId32("ct_editor_asset_browser_tab")},
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ "  " ++ "Entity editor";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ "  " ++ "Entity editor";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor.TabI {
        const w = try _ecs.createWorld();

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Entity {d}", .{tab_id});

        var tab_inst = _allocator.create(EntityEditorTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _renderer.createViewport(name, _g.rg, w),
            .world = w,

            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(tab_inst.inst));
        _renderer.destroyViewport(tab_o.viewport);
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;

        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(inst));

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

        const tmp_alloc = try _tempalloc.create();
        defer _tempalloc.destroy(tmp_alloc);

        if (new_entity) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
            }

            const ents = try _ecs.spawnManyFromCDB(tmp_alloc, tab_o.world, entiy_obj, 1);
            defer tmp_alloc.free(ents);
            tab_o.root_entity = ents[0];

            tab_o.camera = camera.SimpleFPSCamera.init(.{
                .position = .{ 0, 2, 12 },
                .yaw = std.math.degreesToRadians(180),
            });
        }

        const size = _coreui.getContentRegionAvail();
        tab_o.viewport.setSize(size);

        const wpos = _coreui.getWindowPos();
        const cpos = _coreui.getCursorPos();
        const wfocused = _coreui.isWindowFocused(coreui.FocusedFlags.root_and_child_windows);

        var hovered = false;
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
            hovered = _coreui.isItemHovered(.{});

            if (_coreui.beginDragDropTarget()) {
                defer _coreui.endDragDropTarget();
                if (_coreui.acceptDragDropPayload("obj", .{ .source_allow_null_id = true })) |payload| {
                    const drag_obj: cdb.ObjId = std.mem.bytesToValue(cdb.ObjId, payload.data.?);

                    if (drag_obj.type_idx.eql(assetdb.Asset.typeIdx(_cdb, db))) {
                        const asset_entity_obj = _assetdb.getObjForAsset(drag_obj).?;
                        if (!entiy_obj.eql(asset_entity_obj)) {
                            if (asset_entity_obj.type_idx.eql(ecs.Entity.typeIdx(_cdb, db))) {
                                const new_obj = try _cdb.createObjectFromPrototype(asset_entity_obj);

                                const new_obj_w = ecs.Entity.write(_cdb, new_obj).?;
                                const entiy_obj_w = ecs.Entity.write(_cdb, entiy_obj).?;

                                try ecs.Entity.addSubObjToSet(_cdb, entiy_obj_w, .childrens, &.{new_obj_w});

                                try ecs.Entity.commit(_cdb, new_obj_w);
                                try ecs.Entity.commit(_cdb, entiy_obj_w);
                            }
                        }
                    }
                }
            }
        }

        var gizmo_manipulate = false;
        const gizmo_enabled = false;

        // TODO: bug in imguizmo
        if (gizmo_enabled) {
            if (tab_o.root_entity != null and wfocused) {
                _coreui.gizmoSetDrawList(_coreui.getWindowDrawList());
                _coreui.gizmoSetRect(wpos[0] + cpos[0], wpos[1] + cpos[1], size[0], size[1]);

                const view = tab_o.camera.calcViewMtx();
                const projection = zm.matToArr(zm.perspectiveFovRhGl(
                    0.25 * std.math.pi,
                    size[0] / size[1],
                    0.1,
                    1000.0,
                ));

                // _coreui.pushPtrId(tab_o);
                gizmo_manipulate = _coreui.gizmoManipulate(
                    &view,
                    &projection,
                    coreui.Operation.translate(),
                    .local,
                    &tab_o.world_mtx,
                    .{},
                );
                // _coreui.popId();
            }
        }

        if (!gizmo_manipulate) {
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
        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.strid.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *EntityEditorTab = @alignCast(@ptrCast(inst));

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
        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(inst));

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

const ActivatedViewportActionSet = cetech1.strid.strId32("entity_activated_viewport");
const ViewportActionSet = cetech1.strid.strId32("entity_viewport");
const MoveAction = cetech1.strid.strId32("move");
const LookAction = cetech1.strid.strId32("look");
const LookActivationAction = cetech1.strid.strId32("look_activation");

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "EditorEntityTab",
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
    _platform = apidb.getZigApi(module_name, cetech1.platform.PlatformApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVarValue(editor.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_entity(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
