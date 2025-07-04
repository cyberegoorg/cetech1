const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;

const editor = @import("editor");
const editor_inspector = @import("editor_inspector");
const render_viewport = @import("render_viewport");
const renderer_nodes = @import("renderer_nodes");

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_renderer;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state
const G = struct {
    test_geometry_type_aspec: *editor_inspector.UiPropertyAspect = undefined,
};
var _g: *G = undefined;

const test_geometry_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = renderer_nodes.SimpleMeshNodeSettings.read(_cdb, obj).?;
        const type_str = renderer_nodes.SimpleMeshNodeSettings.readStr(_cdb, r, .type) orelse "cube";
        var type_enum = std.meta.stringToEnum(renderer_nodes.SimpleMeshNodeType, type_str).?;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = renderer_nodes.SimpleMeshNodeSettings.write(_cdb, obj).?;

            try renderer_nodes.SimpleMeshNodeSettings.setStr(_cdb, w, .type, @tagName(type_enum));
            try renderer_nodes.SimpleMeshNodeSettings.commit(_cdb, w);
        }
    }
});

// Create cdb types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        try renderer_nodes.SimpleMeshNodeSettings.addPropertyAspect(
            editor_inspector.UiPropertyAspect,
            _cdb,
            db,
            .type,
            _g.test_geometry_type_aspec,
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;

    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});
    _g.test_geometry_type_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_test_geometry_type_aspec", test_geometry_type_aspec);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_renderer(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
