const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const gpu = cetech1.gpu;
const gfx = cetech1.gfx;
const gfxdd = cetech1.gfxdd;
const gfxrg = cetech1.gfxrg;
const zm = cetech1.zm;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const module_name = .editor_foo_viewport_tab;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_foo_viewport_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _coreui: *coreui.CoreUIApi = undefined;
var _gpu: *gpu.GpuApi = undefined;
var _gfxrg: *gfxrg.GfxRGApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.EditorTabTypeI = undefined,
    rg: ?gfxrg.RenderGraph = null,
};
var _g: *G = undefined;

// Struct for tab type
const FooViewportTab = struct {
    tab_i: editor.EditorTabI,
    viewport: gpu.GpuViewport,
};

// Fill editor tab interface
var foo_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ " Foo viewport";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ " Foo viewport";
    }

    // Create new tab instantce
    pub fn create(db: *cdb.Db) !?*editor.EditorTabI {
        _ = db;
        var tab_inst = _allocator.create(FooViewportTab) catch undefined;
        tab_inst.tab_i = .{
            .vt = _g.test_tab_vt_ptr,
            .inst = @ptrCast(tab_inst),
        };

        tab_inst.viewport = try _gpu.createViewport(_g.rg.?);
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(tab_inst.inst));
        _gpu.destroyViewport(tab_o.viewport);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(inst));
        const size = _coreui.getContentRegionAvail();
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
        }
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *FooViewportTab = @alignCast(@ptrCast(inst));
        _ = tab_o;
    }
});

const rener_pass = gfxrg.Pass.implement(struct {
    pub fn setup(pass: *gfxrg.Pass, builder: gfxrg.GraphBuilder) !void {
        try builder.addPass(pass);
    }

    pub fn render(builder: gfxrg.GraphBuilder, gfx_api: *const gfx.GfxApi, viewport: gpu.GpuViewport) !void {
        _ = builder; // autofix
        const viewid = gfx_api.newViewId();

        const fb = viewport.getFb() orelse return;
        const fb_size = viewport.getSize();

        gfx_api.setViewFrameBuffer(viewid, fb);
        gfx_api.setViewClear(viewid, gfx.ClearFlags_Color | gfx.ClearFlags_Depth, 0x66CCFFff, 1.0, 0);
        gfx_api.setViewRectRatio(viewid, 0, 0, .Equal);

        const aspect_ratio = fb_size[0] / fb_size[1];
        const projMtx = zm.perspectiveFovRhGl(
            0.25 * std.math.pi,
            aspect_ratio,
            0.1,
            1000.0,
        );

        const viewMtx = zm.lookAtRh(
            zm.f32x4(0.0, 2.0, 12.0, 1.0),
            zm.f32x4(0.0, 2.0, 1.0, 1.0),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );

        gfx_api.setViewTransform(viewid, &zm.matToArr(viewMtx), &zm.matToArr(projMtx));

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

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _gfxrg = apidb.getZigApi(module_name, gfxrg.GfxRGApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Create rendergraph
    if (load) {
        if (_g.rg) |rg| {
            _gfxrg.destroy(rg);
        }
        _g.rg = try _gfxrg.create();
        try _g.rg.?.addPass(rener_pass);
    } else {
        if (_g.rg) |rg| {
            _gfxrg.destroy(rg);
        }
        _g.rg = null;
    }

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVar(editor.EditorTabTypeI, module_name, TAB_NAME, .{});
    // Patch vt pointer to new.
    _g.test_tab_vt_ptr.* = foo_tab;

    try apidb.implOrRemove(module_name, editor.EditorTabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_foo_viewport_tab(__apidb: *const cetech1.apidb.ct_apidb_api_t, __allocator: *const cetech1.apidb.ct_allocator_t, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}
