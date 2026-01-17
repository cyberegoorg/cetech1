// TODO: WIP, non optimal for large logs

const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const input = cetech1.input;

const editor = @import("editor");
const editor_tabs = @import("editor_tabs");
const Icons = coreui.CoreIcons;

const module_name = .editor_input;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_linput";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const coreui.CoreUIApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

const LogEntry = struct {
    level: cetech1.log.LogAPI.Level,
    scope: [:0]const u8,
    msg: [:0]const u8,
};

const LogBuffer = cetech1.ArrayList(LogEntry);

// Global state that can surive hot-reload
const G = struct {
    log_tab_vt_ptr: *editor_tabs.TabTypeI = undefined,
};
var _g: *G = undefined;

// Struct for tab type
const InputTab = struct {
    tab_i: editor_tabs.TabI,
};

// Fill editor tab interface
var input_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),
    .category = "Debug",
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_GAMEPAD ++ "  " ++ "Input";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_GAMEPAD ++ "  " ++ "Input";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        _ = tab_id;

        var tab_inst = _allocator.create(InputTab) catch undefined;
        tab_inst.* = .{
            .tab_i = .{
                .vt = _g.log_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *InputTab = @ptrCast(@alignCast(tab_inst.inst));
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick; // autofix
        _ = dt; // autofix
        const tab_o: *InputTab = @ptrCast(@alignCast(inst));
        _ = tab_o;

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        var label_buff: [128]u8 = undefined;

        if (_coreui.beginTabBar("input_sources", .{})) {
            defer _coreui.endTabBar();

            const impls = try _apidb.getImpl(allocator, input.InputSourceI);
            defer allocator.free(impls);
            for (impls) |iface| {
                if (_coreui.beginTabItem(iface.name, .{})) {
                    defer _coreui.endTabItem();

                    if (_coreui.beginTabBar("controllers", .{})) {
                        defer _coreui.endTabBar();
                        const controlers = try iface.getControllers(allocator);
                        defer allocator.free(controlers);

                        for (controlers) |controler_idx| {
                            _coreui.pushIntId(@truncate(controler_idx));
                            defer _coreui.popId();

                            const label = try std.fmt.bufPrintZ(&label_buff, "{d}", .{controler_idx});
                            if (_coreui.beginTabItem(label, .{})) {
                                defer _coreui.endTabItem();

                                if (_coreui.beginTable("source_items", .{
                                    .column = 2,
                                    .flags = .{
                                        //.sizing = .stretch_prop,
                                        .no_saved_settings = true,
                                        .row_bg = true,
                                    },
                                })) {
                                    defer _coreui.endTable();

                                    for (iface.getItems()) |item| {
                                        _coreui.tableNextColumn();
                                        _coreui.text(item.name);

                                        _coreui.tableNextColumn();
                                        const value = iface.getState(controler_idx, item.id).?;
                                        switch (value) {
                                            .action => |v| _coreui.text(@tagName(v)),
                                            .f => |v| {
                                                const l = try std.fmt.bufPrintZ(&label_buff, "{d}", .{v});
                                                _coreui.text(l);
                                            },
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;

    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _apidb = apidb;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.log_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, input_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &input_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_input(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
