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

const renderer = @import("renderer");
const Viewport = renderer.Viewport;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const public = @import("asset_preview.zig");

const module_name = .editor_asset_preview;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_asset_preview";

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
var _renderer: *const renderer.RendererApi = undefined;
var _platform: *const cetech1.platform.PlatformApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _editor_entity: *const editor_entity.EditorEntityAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const AssetPreviewTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_look_activated: bool = false,
    camera_ent: ecs.EntityId,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,

    rg: renderer.Graph = undefined,

    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
    }),

    flecs_port: ?u16 = null,
};

// Fill editor tab interface
var foo_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = cetech1.strId32(TAB_NAME),

    // TODO: Bug on linux CI
    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .only_selection_from_tab = &.{cetech1.strId32("ct_editor_asset_browser_tab")},
    .show_pin_object = true,
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_MAGNIFYING_GLASS ++ "  " ++ "Asset preview";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_MAGNIFYING_GLASS ++ "  " ++ "Asset preview";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor.TabI {
        const w = try _ecs.createWorld();
        w.setSimulate(false);

        const rg = try _render_graph.create();
        try _render_graph.createDefault(_allocator, rg);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Asset preview {d}", .{tab_id});

        const camera_ent = w.newEntity(null);
        _ = w.setId(transform.Position, camera_ent, &transform.Position{});
        _ = w.setId(transform.Rotation, camera_ent, &transform.Rotation{});
        _ = w.setId(camera.Camera, camera_ent, &camera.Camera{});

        var tab_inst = _allocator.create(AssetPreviewTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _renderer.createViewport(name, rg, w, camera_ent),
            .world = w,
            .camera_ent = camera_ent,
            .rg = rg,
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        tab_inst.viewport.setDebugCulling(true);

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *AssetPreviewTab = @alignCast(@ptrCast(tab_inst.inst));
        _renderer.destroyViewport(tab_o.viewport);
        _render_graph.destroy(tab_o.rg);
        _ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;

        const tab_o: *AssetPreviewTab = @alignCast(@ptrCast(inst));

        var selected_obj = cdb.ObjId{};

        const size = _coreui.getContentRegionAvail();
        const wsize = _coreui.getContentRegionMax();

        selected_obj = tab_o.selection.top_level_obj;
        if (selected_obj.isEmpty()) {
            const txt = "Select asset";
            const txt_size = _coreui.calcTextSize(txt, .{});
            _coreui.setCursorPosX(wsize[0] / 2 - txt_size[0] / 2);
            _coreui.setCursorPosY(wsize[1] / 2 + txt_size[1]);
            _coreui.text(txt);
            return;
        }

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (tab_o.root_entity) |ent| {
            _ = ent; // autofix

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

            _ = tab_o.world.setId(transform.Position, tab_o.camera_ent, &transform.Position{
                .x = tab_o.camera.position[0],
                .y = tab_o.camera.position[1],
                .z = tab_o.camera.position[2],
            });

            _ = tab_o.world.setId(transform.Rotation, tab_o.camera_ent, &transform.Rotation{
                .q = zm.matToQuat(zm.mul(zm.rotationX(tab_o.camera.pitch), zm.rotationY(tab_o.camera.yaw))),
            });

            tab_o.viewport.renderMe();
        } else {
            const db = _cdb.getDbFromObjid(selected_obj);
            if (_cdb.getAspect(public.AssetPreviewAspectI, db, selected_obj.type_idx)) |iface| {
                if (iface.ui_preview) |ui_preview| {
                    try ui_preview(allocator, selected_obj);
                }
            } else {
                const txt = "No preview";
                const txt_size = _coreui.calcTextSize(txt, .{});
                _coreui.setCursorPosX(wsize[0] / 2 - txt_size[0] / 2);
                _coreui.setCursorPosY(wsize[1] / 2 + txt_size[1]);
                _coreui.text(txt);
            }
        }
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *AssetPreviewTab = @alignCast(@ptrCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (_coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer _coreui.endMenu();
            _renderer.uiDebugMenuItems(allocator, tab_o.viewport);
            tab_o.flecs_port = _editor_entity.uiRemoteDebugMenuItems(&tab_o.world, allocator, tab_o.flecs_port);
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *AssetPreviewTab = @alignCast(@ptrCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) return;

        var selected_obj = selected.top_level_obj;
        var asset_obj = cdb.ObjId{};

        const db = _cdb.getDbFromObjid(selected_obj);

        if (selected_obj.type_idx.eql(assetdb.Asset.typeIdx(_cdb, db))) {
            asset_obj = _assetdb.getObjForAsset(selected_obj).?;
        } else {
            asset_obj = selected_obj;
        }

        if (!tab_o.selection.top_level_obj.eql(selected.top_level_obj)) {
            if (tab_o.root_entity) |ent| {
                tab_o.world.destroyEntities(&.{ent});
                tab_o.root_entity = null;
            }

            if (_cdb.getAspect(public.AssetPreviewAspectI, db, asset_obj.type_idx)) |iface| {
                const allocator = try _tempalloc.create();
                defer _tempalloc.destroy(allocator);

                if (iface.create_preview_entity) |create_preview_entity| {
                    const ent = try create_preview_entity(allocator, asset_obj, tab_o.world);
                    tab_o.root_entity = ent;
                }
            }

            tab_o.selection = selected;

            tab_o.camera = camera.SimpleFPSCamera.init(.{
                .position = .{ 0, 2, 12 },
            });
        }
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectionItem) !bool {
        _ = selection; // autofix
        _ = allocator; // autofix
        // TODO: implement
        return true;
    }

    pub fn assetRootOpened(inst: *editor.TabO) !void {
        const tab_o: *AssetPreviewTab = @alignCast(@ptrCast(inst));
        if (tab_o.root_entity) |ent| {
            tab_o.world.destroyEntities(&.{ent});
            tab_o.root_entity = null;

            tab_o.selection = coreui.SelectionItem.empty();
            tab_o.root_entity_obj = .{};
            tab_o.root_entity = null;
        }
    }
});

const ActivatedViewportActionSet = cetech1.strId32("preview_activated_viewport");
const ViewportActionSet = cetech1.strId32("preview_viewport");
const MoveAction = cetech1.strId32("move");
const LookAction = cetech1.strId32("look");
const LookActivationAction = cetech1.strId32("look_activation");

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "AssetPreviewTab",
    &[_]cetech1.StrId64{},
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
    _renderer = apidb.getZigApi(module_name, renderer.RendererApi).?;
    _platform = apidb.getZigApi(module_name, cetech1.platform.PlatformApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _editor_entity = apidb.getZigApi(module_name, editor_entity.EditorEntityAPI).?;

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
pub export fn ct_load_module_editor_asset_preview(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
