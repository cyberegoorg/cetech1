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

const render_viewport = @import("render_viewport");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const Viewport = render_viewport.Viewport;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const graphvm = @import("graphvm");

const public = @import("entity_editor.zig");

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
var _graphvm: *const graphvm.GraphVMApi = undefined;
var _render_pipeline: *const render_pipeline.RenderPipelineApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const EntityEditorTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_look_activated: bool = false,
    camera_ent: ecs.EntityId,

    render_pipeline: render_pipeline.RenderPipeline,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,

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

    // TODO: Bug on linux CI
    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .show_pin_object = true,

    .ignore_selection_from_tab = &.{cetech1.strId32("ct_editor_asset_browser_tab")},
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
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Entity {d}", .{tab_id});

        const camera_ent = w.newEntity(null);
        _ = w.setId(transform.Position, camera_ent, &transform.Position{});
        _ = w.setId(transform.Rotation, camera_ent, &transform.Rotation{});
        _ = w.setId(camera.Camera, camera_ent, &camera.Camera{});

        var tab_inst = _allocator.create(EntityEditorTab) catch undefined;
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

        // tab_inst.viewport.setDebugCulling(true);

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(tab_inst.inst));
        _render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
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

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (new_entity) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
                tab_o.world.clear();
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

        const wpos = _coreui.getWindowPos();
        _ = wpos; // autofix
        const cpos = _coreui.getCursorPos();
        _ = cpos; // autofix
        const wfocused = _coreui.isWindowFocused(coreui.FocusedFlags.root_and_child_windows);
        _ = wfocused; // autofix

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

        const gizmo_manipulate = false;
        const gizmo_enabled = false;
        _ = gizmo_enabled; // autofix

        // TODO: bug in imguizmo
        // if (gizmo_enabled) {
        //     if (tab_o.root_entity != null and wfocused) {
        //         _coreui.gizmoSetDrawList(_coreui.getWindowDrawList());
        //         _coreui.gizmoSetRect(wpos[0] + cpos[0], wpos[1] + cpos[1], size[0], size[1]);

        //         const view = tab_o.camera.calcViewMtx();
        //         const projection = zm.matToArr(zm.perspectiveFovLhGl(
        //             0.25 * std.math.pi,
        //             size[0] / size[1],
        //             0.1,
        //             1000.0,
        //         ));

        //         // _coreui.pushPtrId(tab_o);
        //         gizmo_manipulate = _coreui.gizmoManipulate(
        //             &view,
        //             &projection,
        //             coreui.Operation.translate(),
        //             .local,
        //             &tab_o.world_mtx,
        //             .{},
        //         );
        //         // _coreui.popId();
        //     }
        // }

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
        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(inst));

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

        if (_coreui.menuItem(allocator, cetech1.coreui.CoreIcons.FA_GAMEPAD, .{}, null)) {
            _editor.openTabWithPinnedObj(cetech1.strId32("ct_editor_simulation"), .{
                .top_level_obj = tab_o.selection.top_level_obj,
                .obj = tab_o.selection.top_level_obj,
            });
        }

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            _render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
            tab_o.flecs_port = uiRemoteDebugMenuItems(&tab_o.world, allocator, tab_o.flecs_port);
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) !void {
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

    pub fn assetRootOpened(inst: *editor.TabO) !void {
        const tab_o: *EntityEditorTab = @alignCast(@ptrCast(inst));
        if (tab_o.root_entity) |ent| {
            tab_o.world.destroyEntities(&.{ent});

            tab_o.selection = coreui.SelectionItem.empty();
            tab_o.root_entity_obj = .{};
            tab_o.root_entity = null;
        }
    }
});

const entity_value_type_i = graphvm.GraphValueTypeI.implement(
    ecs.EntityId,
    .{
        .name = "entity",
        .type_hash = graphvm.PinTypes.Entity,
        .cdb_type_hash = cetech1.cdb_types.u64Type.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cetech1.cdb_types.u64Type.readValue(u64, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(u64, value)});
        }
    },
);

// TODO: move out
const get_entity_node_i = graphvm.NodeI.implement(
    .{
        .name = "Get entity",
        .type_name = "get_entity",
        .category = "ECS",
    },
    null,
    struct {
        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = self; // autofix

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", true), graphvm.PinTypes.Entity, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = in_pins; // autofix
            _ = self; // autofix
            if (_graphvm.getContext(anyopaque, args.instance, ecs.ECS_ENTITY_CONTEXT)) |ent| {
                const ent_id = @intFromPtr(ent);
                try out_pins.writeTyped(ecs.EntityId, 0, ent_id, ent_id);
            }
        }

        // pub fn icon(
        //     buff: [:0]u8,
        //     allocator: std.mem.Allocator,
        //     db: cdb.DbId,
        //     node_obj: cdb.ObjId,
        // ) ![:0]u8 {
        //     _ = allocator; // autofix
        //     _ = db; // autofix
        //     _ = node_obj; // autofix

        //     return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_STOP});
        // }
    },
);

const ActivatedViewportActionSet = cetech1.strId32("entity_activated_viewport");
const ViewportActionSet = cetech1.strId32("entity_viewport");
const MoveAction = cetech1.strId32("move");
const LookAction = cetech1.strId32("look");
const LookActivationAction = cetech1.strId32("look_activation");

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "EditorEntityTab",
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

fn uiRemoteDebugMenuItems(world: *ecs.World, allocator: std.mem.Allocator, port: ?u16) ?u16 {
    var remote_active = world.isRemoteDebugActive();
    var result: ?u16 = port;

    var buf: [256:0]u8 = undefined;
    const URL = "https://www.flecs.dev/explorer/?page=info&host=localhost:{d}";

    if (_coreui.beginMenu(allocator, coreui.Icons.Entity ++ "  " ++ "ECS", true, null)) {
        defer _coreui.endMenu();

        if (_coreui.menuItemPtr(
            allocator,
            coreui.Icons.Debug ++ "  " ++ "Remote debug",
            .{ .selected = &remote_active },
            null,
        )) {
            if (world.setRemoteDebugActive(remote_active)) |p| {
                const url = std.fmt.allocPrintZ(allocator, URL, .{p}) catch return null;
                defer allocator.free(url);

                _coreui.setClipboardText(url);
                result = p;
            } else {
                result = null;
            }
        }

        const copy_label = std.fmt.bufPrintZ(&buf, coreui.Icons.CopyToClipboard ++ "  " ++ "Copy url", .{}) catch return null;
        if (_coreui.menuItem(allocator, copy_label, .{ .enabled = port != null }, null)) {
            const url = std.fmt.allocPrintZ(allocator, URL, .{port.?}) catch return null;
            defer allocator.free(url);
            _coreui.setClipboardText(url);
        }
    }

    return result;
}

pub var api = public.EditorEntityAPI{
    .uiRemoteDebugMenuItems = &uiRemoteDebugMenuItems,
};

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
    _graphvm = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;
    _render_pipeline = apidb.getZigApi(module_name, render_pipeline.RenderPipelineApi).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.setOrRemoveZigApi(module_name, public.EditorEntityAPI, &api, load);

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, editor.TabTypeI, &foo_tab, load);

    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &entity_value_type_i, true);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &get_entity_node_i, true);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_entity(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
