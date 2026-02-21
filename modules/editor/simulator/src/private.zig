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
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_simulator";

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _task: *const task.TaskAPI = undefined;

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

    selection: coreui.SelectedObj = coreui.SelectedObj.empty(),
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
        return coreui.Icons.Gamepad ++ "  " ++ "Simulator";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Gamepad ++ "  " ++ "Simulator";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        const w = try ecs.createWorld();
        w.setSimulate(false);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Simulator {d}", .{tab_id});

        const camera_ent = w.newEntity(.{});
        _ = w.setComponent(camera.Camera, camera_ent, &camera.Camera{});
        _ = w.setComponent(camera_controller.CameraController, camera_ent, &camera_controller.CameraController{ .position = .{ .y = 2, .z = -12 } });

        const gpu_backend = kernel.getGpuBackend().?;
        const pipeline = try render_pipeline.createDefault(_allocator, gpu_backend, w);

        var tab_inst = _allocator.create(SimulationTab) catch undefined;
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
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *SimulationTab = @ptrCast(@alignCast(tab_inst.inst));
        render_viewport.destroyViewport(tab_o.viewport);
        tab_o.render_pipeline.deinit();
        ecs.destroyWorld(tab_o.world);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = dt;
        _ = kernel_tick;

        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        var entiy_obj = cdb.ObjId{};
        var selected_obj = cdb.ObjId{};

        selected_obj = tab_o.selection.top_level_obj;
        var db: cdb.DbId = undefined;
        if (!selected_obj.isEmpty()) {
            db = cdb.getDbFromObjid(selected_obj);

            if (selected_obj.type_idx.eql(assetdb.AssetCdb.typeIdx(db))) {
                if (!assetdb.isAssetObjTypeOf(selected_obj, ecs.EntityCdb.typeIdx(db))) return;
                entiy_obj = assetdb.getObjForAsset(selected_obj).?;
            } else if (selected_obj.type_idx.eql(ecs.EntityCdb.typeIdx(db))) {
                entiy_obj = selected_obj;
            }
        }

        const new_entity = !tab_o.root_entity_obj.eql(entiy_obj);
        tab_o.root_entity_obj = entiy_obj;

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (new_entity) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
            }

            const ents = try ecs.spawnManyFromCDB(allocator, tab_o.world, entiy_obj, 1);
            defer allocator.free(ents);

            tab_o.root_entity = ents[0];
        }

        const size = coreui.getContentRegionAvail();
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

        if (coreui.beginMenu(allocator, cetech1.coreui.Icons.Explosion, true, null)) {
            defer coreui.endMenu();

            _ = coreui.dragU32("", .{ .v = &tab_o.explode_num });

            coreui.sameLine(.{});

            if (coreui.button(cetech1.coreui.Icons.Explosion, .{})) {
                if (tab_o.root_entity) |root_ent| {
                    tab_o.world.destroyEntities(&.{root_ent});
                }

                const entities = try ecs.spawnManyFromCDB(allocator, tab_o.world, tab_o.root_entity_obj, tab_o.explode_num);
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

        coreui.separatorMenu();
        tab_o.world.debuguiMenuItems(allocator);
        coreui.separatorMenu();

        if (coreui.menuItem(allocator, cetech1.coreui.Icons.Restart, .{}, null)) {
            if (tab_o.root_entity) |root_ent| {
                tab_o.world.destroyEntities(&.{root_ent});
                tab_o.root_entity = null;
            }

            if (!tab_o.root_entity_obj.isEmpty()) {
                const ents = try ecs.spawnManyFromCDB(allocator, tab_o.world, tab_o.root_entity_obj, 1);
                defer allocator.free(ents);
                tab_o.root_entity = ents[0];
            }
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectedObj, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash;
        var tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

        const selected = selection[0];
        if (selected.isEmpty()) return;

        const db = cdb.getDbFromObjid(selected.obj);
        if (assetdb.isAssetObjTypeOf(selected.obj, ecs.EntityCdb.typeIdx(db))) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(ecs.EntityCdb.typeIdx(db))) {
            tab_o.selection = selected;
        }
    }

    pub fn focused(inst: *editor_tabs.TabO) !void {
        const tab_o: *SimulationTab = @ptrCast(@alignCast(inst));

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
pub fn load_module_zig(allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);

    try render_graph.loadAPI(module_name);
    try kernel.loadAPI(module_name);
    try ecs.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    try render_viewport.loadAPI(module_name);
    try editor.loadAPI(module_name);
    try camera.loadAPI(module_name);
    try render_pipeline.loadAPI(module_name);
    try editor_tabs.loadAPI(module_name);

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
pub export fn ct_load_module_editor_simulator(apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb_, allocator, load, reload);
}
