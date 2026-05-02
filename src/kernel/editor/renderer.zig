const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;

const editor = cetech1.editor;
const editor_inspector = cetech1.editor.inspector;
const render_viewport = cetech1.renderer.viewport;
const renderer_nodes = cetech1.renderer.nodes;

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_renderer;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;

// Global state
const G = struct {
    test_geometry_type_aspec: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
};
var _g: *G = undefined;

const test_geometry_type_aspec = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = prop_idx;
        _ = allocator;
        _ = args;
        const r = renderer_nodes.SimpleMeshNodeSettingsCdb.read(obj).?;

        var type_enum = renderer_nodes.SimpleMeshNodeSettingsCdb.readStrEnum(renderer_nodes.SimpleMeshNodeType, r, .Type, .Cube);

        coreui.setNextItemWidth(-1.0);
        if (coreui.comboFromEnum("", &type_enum)) {
            const w = renderer_nodes.SimpleMeshNodeSettingsCdb.write(obj).?;
            try renderer_nodes.SimpleMeshNodeSettingsCdb.setStr(w, .Type, @tagName(type_enum));
            try renderer_nodes.SimpleMeshNodeSettingsCdb.commit(w);
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
        try renderer_nodes.SimpleMeshNodeSettingsCdb.addPropertyAspect(
            editor_inspector.UiInspectorPropertyValueAspect,

            db,
            .Type,
            _g.test_geometry_type_aspec,
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});
    _g.test_geometry_type_aspec = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_test_geometry_type_aspec", test_geometry_type_aspec);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_renderer(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
