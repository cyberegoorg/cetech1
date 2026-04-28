const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;

const kernel = cetech1.kernel;
const editor = @import("editor");
const editor_tree = @import("editor_tree");
const editor_tabs = @import("editor_tabs");

const public = @import("editor_obj_buffer.zig");
const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_obj_buffer;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_obj_buffer_tab";

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;

// Global state
const G = struct {
    tab_vt: *editor_tabs.TabTypeI = undefined,
    last_focused: ?*ObjBufferTab = null,
};
var _g: *G = undefined;

const api = public.EditorObjBufferAPI{
    .addToFirst = addToFirst,
};

fn addToFirst(allocator: std.mem.Allocator, db: cdb.DbId, obj: coreui.SelectedObj) !void {
    _ = db;
    var tab: ?*ObjBufferTab = null;
    if (_g.last_focused) |lf| {
        tab = lf;
    } else {
        const tabs = try editor_tabs.getAllTabsByType(allocator, _g.tab_vt.tab_hash);
        defer allocator.free(tabs);
        for (tabs) |t| {
            tab = @ptrCast(@alignCast(t.inst));
            break;
        }
    }

    if (tab) |tab_o| {
        try tab_o.obj_buffer.add(&.{obj});
        try tab_o.inter_selection.set(&.{obj});

        if (tab_o.inter_selection.toSlice(allocator)) |objs| {
            editor_tabs.propagateSelection(tab_o, objs);
        }
    }
}

const ObjBufferTab = struct {
    tab_i: editor_tabs.TabI,

    inter_selection: coreui.Selection,
    obj_buffer: coreui.Selection,
};

// Fill editor tab interface
var obj_buffer_tab = editor_tabs.TabTypeI.implement(
    editor_tabs.TabTypeIArgs{
        .tab_name = TAB_NAME,
        .tab_hash = .fromStr(TAB_NAME),

        .create_on_init = true,
        .show_pin_object = false,
        .show_sel_obj_in_title = false,
    },
    struct {
        pub fn menuName() ![:0]const u8 {
            return coreui.Icons.Buffer ++ "  " ++ "Obj buffer";
        }

        // Return tab title
        pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
            _ = inst;
            return coreui.Icons.Buffer ++ "  " ++ "Obj buffer";
        }

        // Create new ObjBufferTab instantce
        pub fn create(tab_id: u32) !?*editor_tabs.TabI {
            _ = tab_id;
            var tab_inst = try _allocator.create(ObjBufferTab);
            tab_inst.* = ObjBufferTab{
                .tab_i = .{
                    .vt = _g.tab_vt,
                    .inst = @ptrCast(tab_inst),
                },

                .inter_selection = coreui.Selection.init(_allocator),
                .obj_buffer = coreui.Selection.init(_allocator),
            };
            return &tab_inst.tab_i;
        }

        // Destroy ObjBufferTab instantce
        pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
            const tab_o: *ObjBufferTab = @ptrCast(@alignCast(tab_inst.inst));

            tab_o.inter_selection.deinit();
            tab_o.obj_buffer.deinit();

            editor_tabs.propagateSelection(tab_inst, &.{.{ .top_level_obj = .{}, .obj = .{} }});

            if (_g.last_focused == tab_o) {
                _g.last_focused = null;
            }

            _allocator.destroy(tab_o);
        }

        pub fn focused(inst: *editor_tabs.TabO) !void {
            const tab_o: *ObjBufferTab = @ptrCast(@alignCast(inst));

            const allocator = try tempalloc.create();
            defer tempalloc.destroy(allocator);

            _g.last_focused = tab_o;
        }

        // pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
        //     const tab_o: *ObjBufferTab = @alignCast(@ptrCast(inst));
        //     tab_o.inter_selection.clear();
        //     tab_o.obj_buffer.clear();
        // }

        // Draw tab menu
        pub fn menu(inst: *editor_tabs.TabO) !void {
            var tab_o: *ObjBufferTab = @ptrCast(@alignCast(inst));

            if (coreui.beginMenu(_allocator, coreui.Icons.ContextMenu, !tab_o.inter_selection.isEmpty(), null)) {
                defer coreui.endMenu();
                const allocator = try tempalloc.create();
                defer tempalloc.destroy(allocator);

                try editor.showObjContextMenu(allocator, tab_o, &.{public.objectBufferContext}, tab_o.inter_selection.first());
            }
        }

        // Draw tab content
        pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;
            const tab_o: *ObjBufferTab = @ptrCast(@alignCast(inst));

            const allocator = try tempalloc.create();
            defer tempalloc.destroy(allocator);

            defer coreui.endChild();
            if (coreui.beginChild("ObjBuffer", .{ .child_flags = .{ .border = true } })) {
                //coreui.pushStyleVar1f(.{ .idx = .indent_spacing, .v = 15 });
                //defer coreui.popStyleVar(.{});

                if (tab_o.obj_buffer.toSlice(allocator)) |selected_objs| {
                    defer allocator.free(selected_objs);

                    for (selected_objs) |obj| {
                        _ = try editor_tree.cdbTreeView(
                            allocator,
                            tab_o,
                            &.{ public.objectBufferContext, editor.Contexts.open },
                            obj,
                            &tab_o.inter_selection,
                            0,
                            .{
                                .multiselect = true,
                                .expand_object = false,
                                .show_root = true,
                            },
                        );
                    }
                }
            }
        }
    },
);

fn objContextMenu(
    allocator: std.mem.Allocator,
    obj_buffer: *coreui.Selection,
    inter_selection: *coreui.Selection,
    selection: []const coreui.SelectedObj,
    filter: ?[:0]const u8,
) !void {
    // Open

    if (coreui.menuItem(
        allocator,
        coreui.Icons.Remove ++ "  " ++ "Remove from buffer",
        .{ .enabled = selection.len != 0 },
        filter,
    )) {
        for (selection) |obj| {
            obj_buffer.remove(&.{obj});
            inter_selection.remove(&.{obj});
        }
    }

    if (coreui.menuItem(
        allocator,
        coreui.Icons.Remove ++ "  " ++ "Clear buffer",
        .{ .enabled = selection.len != 0 },
        filter,
    )) {
        obj_buffer.clear();
        inter_selection.clear();
    }
}

// TODO: separe
const FOLDER_ICON = coreui.Icons.Folder;
const ASSET_ICON = coreui.Icons.Asset;

var buffer_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = selection;

        if (contexts.id != public.objectBufferContext.id) return false;

        if (filter) |f| {
            if (coreui.uiFilterPass(allocator, f, "Remove from buffer", false) != null) return true;
            if (coreui.uiFilterPass(allocator, f, "Clear buffer", false) != null) return true;
            return false;
        }

        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = contexts;
        const tab_o: *ObjBufferTab = @ptrCast(@alignCast(tab));

        coreui.separatorText("Obj buffer");
        objContextMenu(allocator, &tab_o.obj_buffer, &tab_o.inter_selection, selection, filter) catch undefined;
    }
});

var add_to_buffer_context_menu_i = editor.ObjContextMenuI.implement(struct {
    pub fn isValid(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !bool {
        _ = tab;
        _ = selection;

        if (contexts.id != editor.Contexts.open.id) return false;

        const tabs = editor_tabs.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        if (filter) |f| {
            var label_buff: [1024]u8 = undefined;
            for (tabs) |t| {
                const label = std.fmt.bufPrintZ(&label_buff, "In buffer {d}", .{t.tabid}) catch undefined;
                if (coreui.uiFilterPass(allocator, f, label, false) != null) return true;
            }
            return false;
        }
        return true;
    }

    pub fn menu(
        allocator: std.mem.Allocator,
        tab_: *editor_tabs.TabO,
        contexts: cetech1.StrId64,
        selection: []const coreui.SelectedObj,
        filter: ?[:0]const u8,
    ) !void {
        _ = tab_;
        _ = contexts;

        const tabs = editor_tabs.getAllTabsByType(allocator, _g.tab_vt.tab_hash) catch undefined;
        defer allocator.free(tabs);

        var label_buff: [1024]u8 = undefined;
        for (tabs) |tab| {
            const label = std.fmt.bufPrintZ(&label_buff, coreui.Icons.Buffer ++ "  " ++ "In buffer {d}" ++ "###EditInObjBuffer{d}", .{ tab.tabid, tab.tabid }) catch undefined;

            if (coreui.menuItem(allocator, label, .{}, filter)) {
                const tab_o: *ObjBufferTab = @ptrCast(@alignCast(tab.inst));

                for (selection, 0..) |obj, idx| {
                    try tab_o.obj_buffer.add(&.{obj});
                    if (idx == 0) {
                        try tab_o.inter_selection.set(&.{obj});
                    } else {
                        try tab_o.inter_selection.add(&.{obj});
                    }
                }

                if (tab_o.inter_selection.toSlice(allocator)) |objs| {
                    defer allocator.free(objs);
                    editor_tabs.propagateSelection(tab.inst, objs);
                }
            }
        }
    }
});

// Test
var register_tests_i = coreui.RegisterTestsI.implement(struct {
    pub fn registerTests() !void {
        _ = coreui.registerTest(
            "ObjBuffer",
            "should_add_asset_to_buffer_by_double_click",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");
                    ctx.itemAction(.DoubleClick, "**/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(.DoubleClick, "**/###core", .{}, null);

                    ctx.setRef("###ct_editor_obj_buffer_tab_1");
                    ctx.windowFocus("");
                    ctx.itemAction(.Click, "**/###foo.ct_foo_asset", .{}, null);
                    ctx.itemAction(.Click, "**/###core", .{}, null);
                }
            },
        );

        _ = coreui.registerTest(
            "ContextMenu",
            "should_add_asset_to_buffer_by_ctx_menu",
            @src(),
            struct {
                pub fn run(ctx: *coreui.TestContext) !void {
                    kernel.openAssetRoot("fixtures/test_asset");
                    ctx.yield(1);

                    ctx.setRef("###ct_editor_asset_browser_tab_1");
                    ctx.windowFocus("");
                    // ctx.menuAction(  .Check, "###AssetBrowserMenu/###Vertical");

                    // TODO: FIx mutli select
                    //ctx.keyDown(  .mod_ctrl);
                    ctx.itemAction(.Click, "**/###foo.ct_foo_asset", .{}, null);
                    //ctx.itemAction(  .Click, "**/###core", .{}, null);
                    //ctx.keyUp(  .mod_ctrl);

                    ctx.menuAction(.Click, "###ObjContextMenu/###EditInObjBuffer1");

                    ctx.setRef("###ct_editor_obj_buffer_tab_1");
                    ctx.windowFocus("");
                    ctx.itemAction(.Click, "**/###foo.ct_foo_asset", .{}, null);
                    //ctx.itemAction(  .Click, "**/###core", .{}, null);
                }
            },
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    try kernel.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);

    try editor.loadAPI(module_name);
    try editor_tree.loadAPI(module_name);
    try editor_tabs.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.tab_vt = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, obj_buffer_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &obj_buffer_tab, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &buffer_context_menu_i, load);
    try apidb.implOrRemove(module_name, editor.ObjContextMenuI, &add_to_buffer_context_menu_i, load);
    try apidb.implOrRemove(module_name, coreui.RegisterTestsI, &register_tests_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.EditorObjBufferAPI, &api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_obj_buffer(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
