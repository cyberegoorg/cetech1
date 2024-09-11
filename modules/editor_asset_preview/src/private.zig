const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const tempalloc = cetech1.tempalloc;
const gfx = cetech1.gpu;
const gfx_rg = cetech1.render_graph;
const zm = cetech1.math;
const ecs = cetech1.ecs;
const actions = cetech1.actions;
const graphvm = cetech1.graphvm;
const assetdb = cetech1.assetdb;
const uuid = cetech1.uuid;
const task = cetech1.task;
const transform = cetech1.transform;
const renderer = cetech1.renderer;
const camera = cetech1.camera;

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
var _gfx: *const gfx.GfxApi = undefined;
var _gfx_rg: *const gfx_rg.GfxRGApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _ecs: *const ecs.EcsAPI = undefined;
var _tempalloc: *const tempalloc.TempAllocApi = undefined;
var _actions: *const actions.ActionsAPI = undefined;
var _graph: *const graphvm.GraphVMApi = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _uuid: *const uuid.UuidAPI = undefined;
var _task: *const task.TaskAPI = undefined;
var _viewport: *const cetech1.renderer.RendererApi = undefined;
var _platform: *const cetech1.platform.PlatformApi = undefined;
var _editor: *const editor.EditorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
    db: cetech1.cdb.Db = undefined, // TODO: SHIT
};
var _g: *G = undefined;

// Struct for tab type
const AssetPreviewTab = struct {
    tab_i: editor.TabI,
    viewport: Viewport = undefined,
    db: cdb.Db,
    world: ecs.World,
    camera_look_activated: bool = false,

    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    root_entity_obj: cdb.ObjId = .{},
    root_entity: ?ecs.EntityId = null,

    rg: gfx_rg.RenderGraph = undefined,

    camera: camera.SimpleFPSCamera = camera.SimpleFPSCamera.init(.{
        .position = .{ 0, 2, 12 },
        .yaw = std.math.degreesToRadians(180),
    }),

    flecs_port: ?u16 = null,
};

// Fill editor tab interface
var foo_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },

    // TODO: Bug on linux CI
    .create_on_init = true,
    .show_sel_obj_in_title = true,
    .only_selection_from_tab = &.{cetech1.strid.strId32("ct_editor_asset_browser_tab")},
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
    pub fn create(db: cdb.Db, tab_id: u32) !?*editor.TabI {
        const w = try _ecs.createWorld();
        _g.db = db;

        var rg = try _gfx_rg.create();
        try rg.addPass(simple_pass);
        try rg.addPass(blit_pass);

        var buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, "Asset preview {d}", .{tab_id});

        var tab_inst = _allocator.create(AssetPreviewTab) catch undefined;
        tab_inst.* = .{
            .viewport = try _viewport.createViewport(name, rg, w),
            .world = w,
            .db = db,
            .rg = rg,
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *AssetPreviewTab = @alignCast(@ptrCast(tab_inst.inst));
        _viewport.destroyViewport(tab_o.viewport);
        _gfx_rg.destroy(tab_o.rg);
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

            tab_o.viewport.setViewMtx(tab_o.camera.calcViewMtx());
        } else {
            if (tab_o.db.getAspect(public.AssetPreviewAspectI, selected_obj.type_idx)) |iface| {
                if (iface.ui_preview) |ui_preview| {
                    try ui_preview(allocator, tab_o.db, selected_obj);
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
            tab_o.flecs_port = tab_o.world.uiRemoteDebugMenuItems(allocator, tab_o.flecs_port);
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, db: cdb.Db, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.strid.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *AssetPreviewTab = @alignCast(@ptrCast(inst));

        const selected = selection[0];
        var selected_obj = selected.top_level_obj;
        var asset_obj = cdb.ObjId{};

        if (selected_obj.type_idx.eql(assetdb.Asset.typeIdx(tab_o.db))) {
            asset_obj = _assetdb.getObjForAsset(selected_obj).?;
        } else {
            asset_obj = selected_obj;
        }

        if (!tab_o.selection.top_level_obj.eql(selected.top_level_obj)) {
            if (tab_o.root_entity) |ent| {
                tab_o.world.destroyEntities(&.{ent});
                tab_o.root_entity = null;
            }

            if (db.getAspect(public.AssetPreviewAspectI, asset_obj.type_idx)) |iface| {
                const allocator = try _tempalloc.create();
                defer _tempalloc.destroy(allocator);

                if (iface.create_preview_entity) |create_preview_entity| {
                    const ent = try create_preview_entity(allocator, db, asset_obj, tab_o.world);
                    tab_o.root_entity = ent;
                }
            }

            tab_o.selection = selected;

            tab_o.camera = camera.SimpleFPSCamera.init(.{
                .position = .{ 0, 2, 12 },
                .yaw = std.math.degreesToRadians(180),
            });
        }
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, db: cdb.Db, selection: []const coreui.SelectionItem) !bool {
        _ = allocator; // autofix
        _ = db; // autofix
        _ = selection; // autofix
        // TODO: implement
        return true;
    }
});

const simple_pass = gfx_rg.Pass.implement(struct {
    pub fn setup(pass: *gfx_rg.Pass, builder: gfx_rg.GraphBuilder) !void {
        try builder.exportLayer(pass, "color");

        try builder.createTexture2D(
            pass,
            "foo",
            .{
                .format = gfx.TextureFormat.BGRA8,
                .flags = 0 |
                    gfx.TextureFlags_Rt |
                    gfx.SamplerFlags_MinPoint |
                    gfx.SamplerFlags_MipMask |
                    gfx.SamplerFlags_MagPoint |
                    gfx.SamplerFlags_MipPoint |
                    gfx.SamplerFlags_UClamp |
                    gfx.SamplerFlags_VClamp,

                .clear_color = 0x66CCFFff,
            },
        );
        try builder.createTexture2D(
            pass,
            "foo_depth",
            .{
                .format = gfx.TextureFormat.D24,
                .flags = 0 |
                    gfx.TextureFlags_Rt |
                    gfx.SamplerFlags_MinPoint |
                    gfx.SamplerFlags_MagPoint |
                    gfx.SamplerFlags_MipPoint |
                    gfx.SamplerFlags_UClamp |
                    gfx.SamplerFlags_VClamp,

                .clear_depth = 1.0,
            },
        );

        try builder.addPass("simple_pass", pass);
    }

    pub fn render(builder: gfx_rg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: Viewport, viewid: gfx.ViewId) !void {
        _ = builder;

        const fb_size = viewport.getSize();
        const aspect_ratio = fb_size[0] / fb_size[1];
        const projMtx = zm.perspectiveFovRhGl(
            0.25 * std.math.pi,
            aspect_ratio,
            0.1,
            1000.0,
        );

        const viewMtx = viewport.getViewMtx();
        gfx_api.setViewTransform(viewid, &viewMtx, &zm.matToArr(projMtx));

        if (gfx_api.getEncoder()) |e| {
            e.touch(viewid);

            const dd = viewport.getDD();
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, -2, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
            }
        }
    }
});

const blit_pass = gfx_rg.Pass.implement(struct {
    pub fn setup(pass: *gfx_rg.Pass, builder: gfx_rg.GraphBuilder) !void {
        try builder.writeTexture(pass, gfx_rg.ViewportColorResource);
        try builder.readTexture(pass, "foo");
        try builder.addPass("blit", pass);
    }

    pub fn render(builder: gfx_rg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: Viewport, viewid: gfx.ViewId) !void {
        const fb_size = viewport.getSize();

        if (gfx_api.getEncoder()) |e| {
            const out_tex = builder.getTexture(gfx_rg.ViewportColorResource).?;
            const foo_tex = builder.getTexture("foo").?;
            e.blit(
                viewid,
                out_tex,
                0,
                0,
                0,
                0,
                foo_tex,
                0,
                0,
                0,
                0,
                @intFromFloat(fb_size[0]),
                @intFromFloat(fb_size[1]),
                0,
            );
        }
    }
});

const ActivatedViewportActionSet = cetech1.strid.strId32("preview_activated_viewport");
const ViewportActionSet = cetech1.strid.strId32("preview_viewport");
const MoveAction = cetech1.strid.strId32("move");
const LookAction = cetech1.strid.strId32("look");
const LookActivationAction = cetech1.strid.strId32("look_activation");

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "AssetPreviewTab",
    &[_]cetech1.strid.StrId64{},
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
    _gfx = apidb.getZigApi(module_name, gfx.GfxApi).?;
    _gfx_rg = apidb.getZigApi(module_name, gfx_rg.GfxRGApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _tempalloc = apidb.getZigApi(module_name, tempalloc.TempAllocApi).?;
    _actions = apidb.getZigApi(module_name, actions.ActionsAPI).?;
    _graph = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _uuid = apidb.getZigApi(module_name, uuid.UuidAPI).?;
    _task = apidb.getZigApi(module_name, task.TaskAPI).?;
    _viewport = apidb.getZigApi(module_name, cetech1.renderer.RendererApi).?;
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
pub export fn ct_load_module_editor_asset_preview(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
