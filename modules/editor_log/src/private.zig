// TODO: WIP, non optimal for large logs

const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const MODULE_NAME = "editor_log";

// Need for logging from std.
pub const std_options = struct {
    pub const logFn = cetech1.log.zigLogFnGen(&_log);
};
// Log for module
const log = std.log.scoped(.editor_log);

const TAB_NAME = "ct_editor_log";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _coreui: *coreui.CoreUIApi = undefined;
var _editor: *editor.EditorAPI = undefined;

const LogEntry = struct {
    level: cetech1.log.LogAPI.Level,
    scope: [:0]const u8,
    msg: [:0]const u8,
};

const LogBuffer = std.ArrayList(LogEntry);

// Global state that can surive hot-reload
const G = struct {
    log_tab_vt_ptr: *editor.EditorTabTypeI = undefined,

    log_buffer: ?LogBuffer = null,
    log_buffer_lock: std.Thread.Mutex = .{},
};
var _g: *G = undefined;

// Struct for tab type
const LogTab = struct {
    tab_i: editor.EditorTabI,

    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,

    autoscroll: bool = true,

    enabled_levels: struct {
        err: bool = true,
        warn: bool = true,
        debug: bool = true,
        info: bool = true,

        pub fn pass(enabled_levels: @This(), level: cetech1.log.LogAPI.Level) bool {
            return switch (level) {
                .err => enabled_levels.err,
                .warn => enabled_levels.warn,
                .info => enabled_levels.info,
                .debug => enabled_levels.debug,
                else => false,
            };
        }
    } = .{},
};

pub fn levelIcon(level: cetech1.log.LogAPI.Level) [:0]const u8 {
    return switch (level) {
        .err => Icons.FA_RADIATION,
        .warn => Icons.FA_TRIANGLE_EXCLAMATION,
        .info => Icons.FA_CIRCLE_INFO,
        .debug => Icons.FA_BUG,
        else => "SHIT",
    };
}

pub fn levelColor(level: cetech1.log.LogAPI.Level) [4]f32 {
    if (!_editor.isColorsEnabled()) return _coreui.getStyle().getColor(.text);

    return switch (level) {
        .err => .{ 1.0, 0.0, 0.0, 1.0 },
        .warn => .{ 0.7, 0.7, 0.0, 1.0 },
        .debug => .{ 0.0, 1.0, 0.0, 1.0 },
        else => _coreui.getStyle().getColor(.text),
    };
}

// Fill editor tab interface
var log_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = cetech1.strid.strId32(TAB_NAME),
    .create_on_init = true,
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return Icons.FA_SCROLL ++ " Log";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return Icons.FA_SCROLL ++ " Log";
    }

    // Create new tab instantce
    pub fn create(db: *cdb.Db) !?*editor.EditorTabI {
        _ = db;
        var tab_inst = _allocator.create(LogTab) catch undefined;
        tab_inst.* = .{
            .tab_i = .{
                .vt = _g.log_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };

        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *LogTab = @alignCast(@ptrCast(tab_inst.inst));
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO) !void {
        const tab_o: *LogTab = @alignCast(@ptrCast(inst));
        var scrollBotom = false;

        _ = _coreui.checkbox("###Autoscroll", .{ .v = &tab_o.autoscroll });

        _coreui.sameLine(.{});
        if (_coreui.button(Icons.FA_ANGLES_DOWN ++ "###ScrollBotom", .{})) {
            scrollBotom = true;
        }

        {
            _coreui.pushStyleColor4f(.{ .idx = .text, .c = levelColor(.err) });
            defer _coreui.popStyleColor(.{ .count = 1 });

            _coreui.sameLine(.{});
            if (_coreui.checkbox(levelIcon(.err), .{ .v = &tab_o.enabled_levels.err })) {}
        }
        {
            _coreui.pushStyleColor4f(.{ .idx = .text, .c = levelColor(.debug) });
            defer _coreui.popStyleColor(.{ .count = 1 });

            _coreui.sameLine(.{});
            if (_coreui.checkbox(levelIcon(.debug), .{ .v = &tab_o.enabled_levels.debug })) {}
        }
        {
            _coreui.pushStyleColor4f(.{ .idx = .text, .c = levelColor(.warn) });
            defer _coreui.popStyleColor(.{ .count = 1 });

            _coreui.sameLine(.{});
            if (_coreui.checkbox(levelIcon(.warn), .{ .v = &tab_o.enabled_levels.warn })) {}
        }
        {
            _coreui.pushStyleColor4f(.{ .idx = .text, .c = levelColor(.info) });
            defer _coreui.popStyleColor(.{ .count = 1 });

            _coreui.sameLine(.{});
            if (_coreui.checkbox(levelIcon(.info), .{ .v = &tab_o.enabled_levels.info })) {}
        }

        _coreui.sameLine(.{});
        tab_o.filter = _coreui.uiFilter(&tab_o.filter_buff, tab_o.filter);

        if (_coreui.beginTable("###LogTable", .{
            .column = 3,
            .flags = .{
                .no_saved_settings = true,
                .row_bg = true,
                .scroll_x = true,
                .scroll_y = true,
                .resizable = true,
            },
        })) {
            defer _coreui.endTable();
            _coreui.tableSetupScrollFreeze(2, 0);

            if (_g.log_buffer) |buffer| {
                _g.log_buffer_lock.lock();
                defer _g.log_buffer_lock.unlock();

                for (buffer.items) |entry| {
                    if (!tab_o.enabled_levels.pass(entry.level)) continue;

                    if (tab_o.filter) |f| {
                        if (null == _coreui.uiFilterPass(_allocator, f, entry.scope, false) and null == _coreui.uiFilterPass(_allocator, f, entry.msg, false)) continue;
                    }

                    _coreui.tableNextColumn();
                    _coreui.textColored(levelColor(entry.level), levelIcon(entry.level));

                    _coreui.tableNextColumn();
                    _coreui.text(entry.scope);

                    _coreui.tableNextColumn();
                    _coreui.text(entry.msg);
                }
            }

            const scroll_y = _coreui.getScrollY();
            const max_scroll_y = _coreui.getScrollMaxY();
            if (scrollBotom or (tab_o.autoscroll and scroll_y >= max_scroll_y)) {
                _coreui.setScrollHereY(.{ .center_y_ratio = 1.0 });
            }
        }
    }

    // Draw tab menu
    // pub fn menu(inst: *editor.TabO) !void {
    //     const tab_o: *LogTab = @alignCast(@ptrCast(inst));
    //     _ = tab_o; // autofix
    // }
});

var handler = cetech1.log.LogHandlerI.implement(struct {
    pub fn logFn(level: cetech1.log.LogAPI.Level, scope: [:0]const u8, log_msg: [:0]const u8) !void {
        _g.log_buffer_lock.lock();
        defer _g.log_buffer_lock.unlock();

        if (_g.log_buffer) |*buffer| {
            try buffer.append(.{ .level = level, .scope = try _allocator.dupeZ(u8, scope), .msg = try _allocator.dupeZ(u8, log_msg) });
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {

    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(coreui.CoreUIApi).?;
    _editor = apidb.getZigApi(editor.EditorAPI).?;
    _apidb = apidb;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});
    if (_g.log_buffer == null) _g.log_buffer = LogBuffer.init(_allocator);

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.log_tab_vt_ptr = try apidb.globalVar(editor.EditorTabTypeI, MODULE_NAME, TAB_NAME, .{});
    // Patch vt pointer to new.
    _g.log_tab_vt_ptr.* = log_tab;

    try apidb.implOrRemove(editor.EditorTabTypeI, &log_tab, load);
    try apidb.implOrRemove(cetech1.log.LogHandlerI, &handler, load);

    if (!reload and !load) {
        _g.log_buffer_lock.lock();
        defer _g.log_buffer_lock.unlock();

        for (_g.log_buffer.?.items) |entry| {
            _allocator.free(entry.msg);
            _allocator.free(entry.scope);
        }

        _g.log_buffer.?.deinit();
        _g.log_buffer = null;
    }

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_log(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
