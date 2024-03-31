const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const module_name = .editor_foo_tab;

// Need for logging from std.
pub const std_options = struct {
    pub const logFn = cetech1.log.zigLogFnGen(&_log);
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_foo_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _coreui: *coreui.CoreUIApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.EditorTabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const FooTab = struct {
    tab_i: editor.EditorTabI,
};

// Fill editor tab interface
var foo_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_ROBOT ++ " Foo tab";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_ROBOT ++ " Foo tab";
    }

    // Create new tab instantce
    pub fn create(db: *cdb.Db) !?*editor.EditorTabI {
        _ = db;
        var tab_inst = _allocator.create(FooTab) catch undefined;
        tab_inst.tab_i = .{
            .vt = _g.test_tab_vt_ptr,
            .inst = @ptrCast(tab_inst),
        };
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *FooTab = @alignCast(@ptrCast(tab_inst.inst));
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO) !void {
        const tab_o: *FooTab = @alignCast(@ptrCast(inst));
        _ = tab_o;
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *FooTab = @alignCast(@ptrCast(inst));
        _ = tab_o;
        if (_coreui.beginMenu(_allocator, "foo", true, null)) {
            defer _coreui.endMenu();

            if (_coreui.beginMenu(_allocator, "bar", true, null)) {
                defer _coreui.endMenu();

                _ = _coreui.menuItem(_allocator, "baz", .{}, null);
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
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _apidb = apidb;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVar(editor.EditorTabTypeI, module_name, TAB_NAME, .{});
    // Patch vt pointer to new.
    _g.test_tab_vt_ptr.* = foo_tab;

    try apidb.implOrRemove(module_name, editor.EditorTabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_foo_tab(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}
