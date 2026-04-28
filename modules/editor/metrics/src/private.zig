const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const metrics = cetech1.metrics;
const tempalloc = cetech1.tempalloc;

const editor = @import("editor");
const editor_tabs = @import("editor_tabs");
const Icons = coreui.CoreIcons;

const module_name = .editor_metrics;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_metrics_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _tempalloc: *const tempalloc.TempAllocApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor_tabs.TabTypeI = undefined,
};
var _g: *G = undefined;

const SelectedMetrics = cetech1.ArraySet([]const u8);
// Struct for tab type
const MetricsTab = struct {
    tab_i: editor_tabs.TabI,
    selected_metrics: SelectedMetrics,

    // Add filter
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,
};

// Fill editor tab interface
var foo_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),
    .create_on_init = true,
    .category = "Debug",
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Metrics ++ "  " ++ "Metrics";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Metrics ++ "  " ++ "Metrics";
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        _ = tab_id;

        var tab_inst = _allocator.create(MetricsTab) catch undefined;

        tab_inst.* = MetricsTab{
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
            .selected_metrics = SelectedMetrics.empty,
        };
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *MetricsTab = @ptrCast(@alignCast(tab_inst.inst));
        tab_o.selected_metrics.deinit(_allocator);
        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;
        const tab_o: *MetricsTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        var buf: [256]u8 = undefined;

        if (coreui.beginPlot("Metrics", .{
            .h = -1,
            .flags = .{
                .no_title = true,
                .no_frame = true,
                .equal = false,
            },
        })) {
            defer coreui.endPlot();

            {
                defer coreui.setupFinish();

                coreui.setupAxis(.x1, .{
                    .flags = .{
                        .auto_fit = true,
                    },
                });

                coreui.setupAxis(.y1, .{
                    .flags = .{
                        .auto_fit = true,
                    },
                });

                coreui.setupLegend(coreui.PlotLocation.north_west, .{
                    .outside = true,
                });
            }

            const metrics_name = try metrics.getMetricsName(allocator);
            defer allocator.free(metrics_name);

            var it = tab_o.selected_metrics.iterator();
            while (it.next()) |v| {
                var split_bw = std.mem.splitBackwardsAny(u8, v.key_ptr.*, "/");
                const metric_name = split_bw.first();
                const metric_last_category = split_bw.next();

                const name = try std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ metric_last_category.?, metric_name });

                if (metrics.getMetricValues(allocator, v.key_ptr.*)) |values| {
                    coreui.plotLineValuesF64(name, .{
                        .v = values,
                        .offset = @intCast(metrics.getMetricOffset(v.key_ptr.*).?),
                    });
                }
            }
        }
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *MetricsTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        var buf: [256]u8 = undefined;

        // Add metric
        if (coreui.beginMenu(_allocator, coreui.Icons.Add, true, null)) {
            defer coreui.endMenu();

            tab_o.filter = coreui.uiFilter(&tab_o.filter_buff, tab_o.filter);

            const metrics_name = try metrics.getMetricsName(allocator);
            defer allocator.free(metrics_name);

            if (tab_o.filter == null) {
                for (metrics_name) |metric_name| {
                    var split_bw = std.mem.splitBackwardsAny(u8, metric_name, "/");
                    const mname = split_bw.first();

                    var split = std.mem.splitAny(u8, split_bw.rest(), "/");
                    const first = split.first();

                    var it: ?[]const u8 = first;
                    var count: usize = 0;
                    var open = false;

                    while (it) |word| : (it = split.next()) {
                        const lbl = try std.fmt.bufPrintZ(&buf, "{s}", .{word});

                        open = coreui.beginMenu(_allocator, lbl, true, null);
                        if (!open) break;
                        count += 1;
                    }

                    if (open) {
                        const name = try std.fmt.bufPrintZ(&buf, "{s}###{s}", .{ mname, metric_name });
                        if (coreui.menuItem(_allocator, name, .{ .selected = tab_o.selected_metrics.contains(metric_name) }, null)) {
                            if (tab_o.selected_metrics.contains(metric_name)) {
                                _ = tab_o.selected_metrics.remove(metric_name);
                            } else {
                                _ = try tab_o.selected_metrics.add(_allocator, metric_name);
                            }
                        }
                    }

                    for (0..count) |_| {
                        coreui.endMenu();
                    }
                }
            } else {
                for (metrics_name) |metric_name| {
                    const name = try std.fmt.bufPrintZ(&buf, "{s}###{s}", .{ metric_name, metric_name });
                    if (coreui.menuItem(_allocator, name, .{ .selected = tab_o.selected_metrics.contains(metric_name) }, tab_o.filter)) {
                        if (tab_o.selected_metrics.contains(metric_name)) {
                            _ = tab_o.selected_metrics.remove(metric_name);
                        } else {
                            _ = try tab_o.selected_metrics.add(_allocator, metric_name);
                        }
                    }
                }
            }
        }

        // Remove
        if (coreui.beginMenu(_allocator, coreui.Icons.Remove, true, null)) {
            defer coreui.endMenu();

            var it = tab_o.selected_metrics.iterator();
            while (it.next()) |v| {
                const name = try std.fmt.bufPrintZ(&buf, "{s}###{s}", .{ v.key_ptr.*, v.key_ptr.* });
                if (coreui.menuItem(_allocator, name, .{}, null)) {
                    _ = tab_o.selected_metrics.remove(v.key_ptr.*);
                    break;
                }
            }
        }
    }

    // pub fn assetRootOpened(inst: *editor_tabs.TabO) !void {
    //     const tab_o: *MetricsTab = @alignCast(@ptrCast(inst));
    //     tab_o.filter = null;
    // }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;

    try cdb.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try metrics.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, foo_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &foo_tab, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_metrics(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
