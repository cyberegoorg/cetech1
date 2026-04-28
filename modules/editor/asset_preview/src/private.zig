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
const actions = @import("actions");

const render_viewport = @import("render_viewport");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const light_component = @import("light_component");
const Viewport = render_viewport.Viewport;

const editor = @import("editor");
const editor_tabs = @import("editor_tabs");
const Icons = coreui.CoreIcons;

const public = @import("asset_preview.zig");

const module_name = .editor_asset_preview;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_asset_preview";

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
const AssetPreviewTab = struct {
    tab_i: editor_tabs.TabI,
    viewport: Viewport = undefined,

    world: ecs.World,
    camera_ent: ecs.EntityId,

    selection: coreui.SelectedObj = coreui.SelectedObj.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,
    light_ent: ?ecs.EntityId = null,

    render_pipeline: render_pipeline.RenderPipeline,

    flecs_port: ?u16 = null,
};

const default_camera_controler = camera_controller.CameraController{
    .type = .Orbital,
    .move_speed = 0.5,
    .position = .{ .y = 2 },
    .rotation = .{ .x = -std.math.degreesToRadians(25), .y = -std.math.degreesToRadians(180) },
};

// Fill editor tab interface
var asset_preview_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),

    // TODO: Bug on linux CI
    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .only_selection_from_tab = &.{.fromStr("ct_editor_asset_browser_tab")},
    .show_pin_object = true,
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Preview ++ "  " ++ "Asset preview";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Preview ++ "  " ++ "Asset preview";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        const w = try ecs.createWorld();
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Asset preview {d}", .{tab_id});

        const camera_ent = w.newEntity(.{});
        _ = w.setComponent(camera.Camera, camera_ent, &camera.Camera{});
        _ = w.setComponent(camera_controller.CameraController, camera_ent, &default_camera_controler);

        const gpu_backend = kernel.getGpuBackend().?;
        const pipeline = try render_pipeline.createDefault(_allocator, gpu_backend, w);

        var tab_inst = _allocator.create(AssetPreviewTab) catch undefined;
        tab_inst.* = .{
            .viewport = try render_viewport.createViewport(name, gpu_backend, pipeline, w, false),
            .camera_ent = camera_ent,
            .world = w,
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
        const tab_o: *AssetPreviewTab = @ptrCast(@alignCast(tab_inst.inst));
        render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const tab_o: *AssetPreviewTab = @ptrCast(@alignCast(inst));

        var selected_obj = cdb.ObjId{};

        const size = coreui.getContentRegionAvail();
        const wsize = coreui.getWindowSize();

        selected_obj = tab_o.selection.top_level_obj;
        if (selected_obj.isEmpty()) {
            const txt = "Select asset";
            const txt_size = coreui.calcTextSize(txt, .{});
            coreui.setCursorPosX(wsize.x / 2 - txt_size.x / 2);
            coreui.setCursorPosY(wsize.y / 2 + txt_size.y);
            coreui.text(txt);
            return;
        }

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (tab_o.root_entity) |ent| {
            _ = ent;

            tab_o.viewport.setSize(size);

            if (tab_o.viewport.getTexture()) |texture| {
                coreui.image(
                    texture,
                    .{
                        .w = size.x,
                        .h = size.y,
                    },
                );
                const hovered = coreui.isItemHovered(.{});
                var controller = tab_o.world.getMutComponent(camera_controller.CameraController, tab_o.camera_ent).?;
                controller.input_enabled = hovered;
            }

            tab_o.viewport.requestRender();
        } else {
            const db = cdb.getDbFromObjid(selected_obj);
            if (cdb.getAspect(public.AssetPreviewAspectI, db, selected_obj.type_idx)) |iface| {
                if (iface.ui_preview) |ui_preview| {
                    try ui_preview(allocator, selected_obj);
                }
            } else {
                const txt = "No preview";
                const txt_size = coreui.calcTextSize(txt, .{});
                coreui.setCursorPosX(wsize.x / 2 - txt_size.x / 2);
                coreui.setCursorPosY(wsize.y / 2 + txt_size.y);
                coreui.text(txt);
            }
        }
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *AssetPreviewTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (coreui.beginMenu(allocator, cetech1.coreui.Icons.Debug, true, null)) {
            defer coreui.endMenu();
            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);
            try render_viewport.uiDebugMenuItems(allocator, tab_o.viewport);
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectedObj, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash;
        var tab_o: *AssetPreviewTab = @ptrCast(@alignCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) return;

        var selected_obj = selected.top_level_obj;
        var asset_obj = cdb.ObjId{};

        const db = cdb.getDbFromObjid(selected_obj);

        if (selected_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(db))) {
            asset_obj = assetdb.getObjForAsset(selected_obj).?;
        } else {
            asset_obj = selected_obj;
        }

        if (!tab_o.selection.top_level_obj.eql(selected.top_level_obj)) {
            if (tab_o.light_ent) |ent| tab_o.world.destroyEntities(&.{ent});

            if (tab_o.root_entity) |ent| {
                tab_o.world.destroyEntities(&.{ent});
                tab_o.root_entity = null;
                // tab_o.world.clear();

                _ = tab_o.world.setComponent(
                    camera_controller.CameraController,
                    tab_o.camera_ent,
                    &default_camera_controler,
                );
            }

            if (cdb.getAspect(public.AssetPreviewAspectI, db, asset_obj.type_idx)) |iface| {
                const allocator = try tempalloc.create();
                defer tempalloc.destroy(allocator);

                if (iface.create_preview_entity) |create_preview_entity| {
                    const ent = try create_preview_entity(allocator, asset_obj, tab_o.world);
                    tab_o.root_entity = ent;

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
            }

            tab_o.selection = selected;
        }
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectedObj) !bool {
        _ = selection;
        _ = allocator;
        // TODO: implement
        return true;
    }

    pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
        const tab_o: *AssetPreviewTab = @ptrCast(@alignCast(inst));
        if (tab_o.root_entity) |ent| {
            tab_o.world.destroyEntities(&.{ent});
            tab_o.root_entity = null;

            tab_o.selection = coreui.SelectedObj.empty();
            tab_o.root_entity_obj = .{};
            tab_o.root_entity = null;
        }
    }
});

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
    try render_pipeline.loadAPI(module_name);
    try camera_controller.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, asset_preview_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &asset_preview_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_asset_preview(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
