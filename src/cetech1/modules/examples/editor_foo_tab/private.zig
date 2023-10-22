const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const editor = @import("editor");

const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor_foo_tab";
const FOO_TAB_NAME = "ct_editor_foo_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.c.ct_editorui_tab_type_i = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const FooTab = struct {
    tab_i: editor.c.ct_editorui_tab_i,
};

// Fill editor tab interface
var foo_tab = editor.c.ct_editorui_tab_type_i{
    .tab_name = FOO_TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(FOO_TAB_NAME).id },

    .menu_name = tabMenuItem,
    .title = tabTitle,
    .create = @ptrCast(&tabCreate),
    .destroy = tabDestroy,
    .ui = tabUi,
    .menu = tabMenu,
};

// Return name for menu /Tabs/
fn tabMenuItem() callconv(.C) [*]const u8 {
    return Icons.FA_ROBOT ++ " Foo tab";
}

// Return tab title
fn tabTitle(inst: ?*editor.c.ct_editorui_tab_o) callconv(.C) [*]const u8 {
    _ = inst;
    return Icons.FA_ROBOT ++ " Foo tab";
}

// Create new FooTab instantce
fn tabCreate(db: ?*cetech1.c.ct_cdb_db_t) callconv(.C) ?*editor.c.ct_editorui_tab_i {
    _ = db;
    var tab_inst = _allocator.create(FooTab) catch undefined;
    tab_inst.tab_i = .{
        .vt = _g.test_tab_vt_ptr,
        .inst = @ptrCast(tab_inst),
    };
    return &tab_inst.tab_i;
}

// Destroy FooTab instantce
fn tabDestroy(tab_inst: ?*editor.c.ct_editorui_tab_i) callconv(.C) void {
    var tab_o: *FooTab = @alignCast(@ptrCast(tab_inst.?.inst));
    _allocator.destroy(tab_o);
}

// Draw tab content
fn tabUi(inst: ?*editor.c.ct_editorui_tab_o) callconv(.C) void {
    var tab_o: *FooTab = @alignCast(@ptrCast(inst));
    _ = tab_o;
}

// Draw tab menu
fn tabMenu(inst: ?*editor.c.ct_editorui_tab_o) callconv(.C) void {
    var tab_o: *FooTab = @alignCast(@ptrCast(inst));
    _ = tab_o;
    if (_editorui.beginMenu("foo", true)) {
        defer _editorui.endMenu();

        if (_editorui.beginMenu("bar", true)) {
            defer _editorui.endMenu();

            _ = _editorui.menuItem("baz", .{});
        }
    }
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log;
    _cdb = apidb.getZigApi(cetech1.cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;
    _apidb = apidb;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVar(editor.c.ct_editorui_tab_type_i, MODULE_NAME, FOO_TAB_NAME, .{});
    // Patch vt pointer to new.
    _g.test_tab_vt_ptr.* = foo_tab;

    try apidb.implOrRemove(editor.c.ct_editorui_tab_type_i, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_foo_tab(__apidb: ?*const cetech1.c.ct_apidb_api_t, __allocator: ?*const cetech1.c.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
