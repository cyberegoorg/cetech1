const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const node_editor = cetech1.coreui_node_editor;
const assetdb = cetech1.assetdb;
const graphvm = cetech1.graphvm;
const cdb_types = cetech1.cdb_types;

const editor_inspector = @import("editor_inspector");
const editor_obj_buffer = @import("editor_obj_buffer");

const editor = @import("editor");
const Icons = coreui.CoreIcons;

const module_name = .editor_graph;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_graph_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const coreui.CoreUIApi = undefined;
var _node_editor: *const node_editor.NodeEditorApi = undefined;
var _editor: *const editor.EditorAPI = undefined;
var _editor_obj_buffer: *const editor_obj_buffer.EditorObjBufferAPI = undefined;
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _graph: *const cetech1.graphvm.GraphVMApi = undefined;
var _editor_inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.TabTypeI = undefined,
    graph_visual_aspect: *editor.UiVisualAspect = undefined,
    node_visual_aspect: *editor.UiVisualAspect = undefined,
    group_visual_aspect: *editor.UiVisualAspect = undefined,
    connection_visual_aspect: *editor.UiVisualAspect = undefined,
    interface_input_visual_aspect: *editor.UiVisualAspect = undefined,
    interface_output_visual_aspect: *editor.UiVisualAspect = undefined,
    ui_properties_aspect: *editor_inspector.UiPropertiesAspect = undefined,
    input_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
    output_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
    const_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
    data_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
};
var _g: *G = undefined;

const PinId = packed struct(u64) {
    objid: u24,
    objgen: cdb.ObjIdGen,
    pin_hash: u32,

    pub fn init(obj: cdb.ObjId, pin_hash: cetech1.strid.StrId32) PinId {
        return .{
            .objid = obj.id,
            .objgen = obj.gen,
            .pin_hash = pin_hash.id,
        };
    }
    pub fn toU64(self: *const PinId) u64 {
        const ptr: *u64 = @ptrFromInt(@intFromPtr(self));
        return ptr.*;
    }

    pub fn getObj(self: *const PinId, db: cdb.Db) cdb.ObjId {
        return .{ .gen = self.objgen, .id = self.objid, .type_idx = graphvm.NodeType.typeIdx(db) };
    }

    pub fn getPinHash(self: *const PinId) cetech1.strid.StrId32 {
        return .{ .id = self.pin_hash };
    }

    pub fn fromU64(value: u64) PinId {
        const ptr: *PinId = @ptrFromInt(@intFromPtr(&value));
        return ptr.*;
    }
};

const PinHashNameMap = std.AutoHashMap(struct { cdb.ObjId, cetech1.strid.StrId32 }, [:0]const u8);
const PinValueTypeMap = std.AutoHashMap(struct { cdb.ObjId, cetech1.strid.StrId32 }, cetech1.strid.StrId32);
const PinDataMap = std.AutoHashMap(struct { cdb.ObjId, cetech1.strid.StrId32 }, cdb.ObjId);

// Struct for tab type
const GraphEditorTab = struct {
    tab_i: editor.TabI,
    editor: *node_editor.EditorContext,

    db: cdb.Db,
    selection: coreui.SelectionItem = coreui.SelectionItem.empty(),
    inter_selection: coreui.Selection,
    root_graph_obj: cdb.ObjId = .{},

    // Add node filter
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,

    ctxNodeId: node_editor.NodeId = 0,
    ctxLinkId: node_editor.LinkId = 0,
    ctxPinId: node_editor.PinId = 0,
    ctxPos: [2]f32 = .{ 0, 0 },

    pinhash_map: PinHashNameMap,
    pindata_map: PinDataMap,
    pintype_map: PinValueTypeMap,
};

const SaveJson = struct { group_size: struct { x: f32, y: f32 } };
fn saveNodeSettings(nodeId: node_editor.NodeId, data: [*]const u8, size: usize, reason: node_editor.SaveReasonFlags, userPointer: *anyopaque) callconv(.C) bool {
    const tab_o: *GraphEditorTab = @alignCast(@ptrCast(userPointer));

    if (reason.Position or reason.Size) {
        const pos = _node_editor.getNodePosition(nodeId);

        const node_obj = cdb.ObjId.fromU64(nodeId);
        const node_w = tab_o.db.writeObj(node_obj).?;

        if (node_obj.type_idx.eql(NodeTypeIdx)) {
            if (reason.Position) {
                graphvm.NodeType.setValue(tab_o.db, f32, node_w, .pos_x, pos[0] / _coreui.getScaleFactor());
                graphvm.NodeType.setValue(tab_o.db, f32, node_w, .pos_y, pos[1] / _coreui.getScaleFactor());
            }
        } else if (node_obj.type_idx.eql(GroupTypeIdx)) {
            if (reason.Position) {
                graphvm.GroupType.setValue(tab_o.db, f32, node_w, .pos_x, pos[0] / _coreui.getScaleFactor());
                graphvm.GroupType.setValue(tab_o.db, f32, node_w, .pos_y, pos[1] / _coreui.getScaleFactor());
            }

            if (reason.Size) {
                const foo = std.json.parseFromSlice(
                    SaveJson,
                    _allocator,
                    data[0..size],
                    .{ .ignore_unknown_fields = true },
                ) catch return false;
                defer foo.deinit();

                graphvm.GroupType.setValue(tab_o.db, f32, node_w, .size_x, foo.value.group_size.x / _coreui.getScaleFactor());
                graphvm.GroupType.setValue(tab_o.db, f32, node_w, .size_y, foo.value.group_size.y / _coreui.getScaleFactor());
            }
        }

        tab_o.db.writeCommit(node_w) catch undefined;
    }

    return true;
}

const PinIconType = enum {
    cirecle,
};

fn drawIcon(drawlist: coreui.DrawList, icon_type: PinIconType, a: [2]f32, b: [2]f32, filled: bool, color: [4]f32) !void {
    const rect_x = a[0];
    _ = rect_x; // autofix
    const rect_y = a[1];
    _ = rect_y; // autofix
    const rect_w = b[0] - a[0];
    const rect_h = b[1] - a[1];
    _ = rect_h; // autofix
    const rect_center_x = (a[0] + b[0]) * 0.5;
    const rect_center_y = (a[1] + b[1]) * 0.5;
    const rect_center = .{ rect_center_x, rect_center_y };
    _ = rect_center; // autofix
    const col = _coreui.colorConvertFloat4ToU32(color);

    const rect_offset = -(rect_w * 0.25 * 0.25);
    const style = _node_editor.getStyle();

    switch (icon_type) {
        .cirecle => {
            const c = .{ rect_center_x + (rect_offset * 0.5), rect_center_y };
            //const r = 0.5 * rect_w / 2.0 - 0.5;
            const r = 0.65 * rect_w / 2;

            if (filled) {
                drawlist.addCircleFilled(.{
                    .p = c,
                    .r = r,
                    .col = col,
                });
            } else {
                var bg_c = style.getColor(.node_bg);
                bg_c[3] = 1.0;

                drawlist.addCircleFilled(.{
                    .p = c,
                    .r = r,
                    .col = _coreui.colorConvertFloat4ToU32(bg_c),
                });
                drawlist.addCircle(.{
                    .p = c,
                    .r = r,
                    .col = col,
                    .thickness = 2.0,
                });
            }
        },
    }
}

// Fill editor tab interface
var graph_tab = editor.TabTypeI.implement(editor.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = cetech1.strid.strId32(TAB_NAME),
    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
    .ignore_selection_from_tab = &.{cetech1.strid.strId32("ct_editor_asset_browser_tab")},
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Graph ++ "  " ++ "Graph editor";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Graph ++ "  " ++ "Graph editor";
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, db: cdb.Db, selection: []const coreui.SelectionItem) !bool {
        _ = db; // autofix
        _ = allocator; // autofix
        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(GraphTypeIdx) and !obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (_assetdb.getObjForAsset(obj.obj)) |o| if (!o.type_idx.eql(GraphTypeIdx)) return false;
        }

        return true;
    }

    // Create new tab instantce
    pub fn create(db: cdb.Db, tab_id: u32) !?*editor.TabI {
        _ = tab_id;
        var tab_inst = _allocator.create(GraphEditorTab) catch undefined;

        tab_inst.* = .{
            .editor = _node_editor.createEditor(.{
                .EnableSmoothZoom = true,
                .UserPointer = tab_inst,
                .SaveNodeSettings = @ptrCast(&saveNodeSettings),
            }),
            .inter_selection = coreui.Selection.init(_allocator),
            .db = db,
            .pinhash_map = PinHashNameMap.init(_allocator),
            .pindata_map = PinDataMap.init(_allocator),
            .pintype_map = PinValueTypeMap.init(_allocator),
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.TabI) !void {
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(tab_inst.inst));

        tab_o.pinhash_map.deinit();
        tab_o.pindata_map.deinit();
        tab_o.pintype_map.deinit();

        tab_o.inter_selection.deinit();

        _node_editor.destroyEditor(tab_o.editor);

        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));

        const tmp_alloc = try _tempalloc.create();
        defer _tempalloc.destroy(tmp_alloc);

        var buf: [128]u8 = undefined;
        _node_editor.setCurrentEditor(tab_o.editor);

        {
            _node_editor.begin("GraphEditor", .{ 0, 0 });
            defer _node_editor.end();

            _node_editor.pushStyleVar1f(.link_strength, 0);
            _node_editor.pushStyleVar1f(.node_rounding, 4);
            defer _node_editor.popStyleVar(1);

            if (tab_o.selection.isEmpty()) {
                return;
            }

            var graph_obj = cdb.ObjId{};
            var selected_obj = cdb.ObjId{};

            selected_obj = tab_o.selection.obj;
            if (selected_obj.isEmpty()) return;

            if (selected_obj.type_idx.eql(AssetTypeIdx)) {
                if (!_assetdb.isAssetObjTypeOf(selected_obj, graphvm.GraphType.typeIdx(tab_o.db))) return;
                graph_obj = _assetdb.getObjForAsset(selected_obj).?;
            } else if (selected_obj.type_idx.eql(GraphTypeIdx)) {
                graph_obj = selected_obj;
            }

            const new_graph = !tab_o.root_graph_obj.eql(graph_obj);

            if (tab_o.db.isAlive(graph_obj)) {
                tab_o.root_graph_obj = graph_obj;
            } else {
                graph_obj = .{};
                tab_o.root_graph_obj = .{};
            }

            if (new_graph) {
                tab_o.pinhash_map.clearRetainingCapacity();
                tab_o.pindata_map.clearRetainingCapacity();
                tab_o.pintype_map.clearRetainingCapacity();
            }

            if (graph_obj.isEmpty()) return;

            const graph_r = tab_o.db.readObj(graph_obj) orelse return;
            const style = _coreui.getStyle();
            const ne_style = _node_editor.getStyle();

            if (new_graph) {
                if (try graphvm.GraphType.readSubObjSet(tab_o.db, graph_r, .data, tmp_alloc)) |datas| {
                    for (datas) |data| {
                        const data_r = graphvm.GraphDataType.read(tab_o.db, data).?;

                        const to_node = graphvm.GraphDataType.readRef(tab_o.db, data_r, .to_node).?;
                        const to_node_pin_str = graphvm.GraphDataType.readStr(tab_o.db, data_r, .to_node_pin).?;
                        const to_node_pin = cetech1.strid.strId32(to_node_pin_str);

                        const pin_k = .{ to_node, to_node_pin };
                        try tab_o.pindata_map.put(pin_k, data);
                    }
                }
            }

            // Nodes
            if (try graphvm.GraphType.readSubObjSet(tab_o.db, graph_r, .nodes, tmp_alloc)) |nodes| {
                defer tmp_alloc.free(nodes);

                for (nodes) |node| {
                    const node_r = tab_o.db.readObj(node).?;

                    const width = (128 + 32) * _coreui.getScaleFactor();
                    const pin_size = _coreui.getFontSize();
                    var header_min: [2]f32 = .{ 0, 0 };
                    var header_max: [2]f32 = .{ 0, 0 };

                    const enabled = tab_o.db.isChildOff(tab_o.selection.top_level_obj, node);

                    if (new_graph or !enabled) {
                        const node_pos_x = graphvm.NodeType.readValue(tab_o.db, f32, node_r, .pos_x);
                        const node_pos_y = graphvm.NodeType.readValue(tab_o.db, f32, node_r, .pos_y);
                        _node_editor.setNodePosition(node.toU64(), .{ node_pos_x * _coreui.getScaleFactor(), node_pos_y * _coreui.getScaleFactor() });
                    }

                    _coreui.beginDisabled(.{ .disabled = !enabled });
                    defer _coreui.endDisabled();
                    _node_editor.beginNode(node.toU64());
                    defer {
                        _node_editor.endNode();

                        if (_coreui.isItemVisible()) {
                            const half_border = ne_style.node_border_width * 0.5;
                            var dl = _node_editor.getNodeBackgroundDrawList(node.toU64());

                            const offset = 7.5;
                            dl.addRectFilled(.{
                                .pmin = .{ header_min[0] - (offset - half_border), header_min[1] - (offset - half_border) },
                                .pmax = .{ header_max[0] + (offset - half_border), header_max[1] },
                                .col = _coreui.colorConvertFloat4ToU32(style.getColor(.title_bg_active)),
                                .rounding = ne_style.node_rounding,
                                .flags = coreui.DrawFlags.round_corners_top,
                            });

                            dl.addLine(.{
                                .p1 = .{ header_min[0] - (offset - half_border) - 1, header_max[1] - (0.5) },
                                .p2 = .{ header_max[0] + (offset - half_border), header_max[1] - (0.5) },
                                .col = _coreui.colorConvertFloat4ToU32(ne_style.getColor(.node_border)),
                                .thickness = 1,
                            });
                        }
                    }

                    const dl = _coreui.getWindowDrawList();

                    const node_type_hash = graphvm.NodeType.f.getNodeTypeId(tab_o.db, node_r);
                    if (_graph.findNodeI(node_type_hash)) |node_i| {
                        if (_coreui.beginTable("table", .{
                            .column = 1,
                            .outer_size = .{ width, 0 },
                            .flags = .{
                                .resizable = false,
                                .no_clip = true,
                                .sizing = .stretch_prop,
                                .no_host_extend_x = true,
                            },
                        })) {
                            defer _coreui.endTable();

                            // Header
                            {
                                _coreui.pushStyleVar2f(.{ .idx = .cell_padding, .v = .{ 0, 0 } });
                                defer _coreui.popStyleVar(.{});

                                _coreui.tableNextColumn();
                                var node_title: [:0]const u8 = undefined;
                                defer tmp_alloc.free(node_title);
                                if (node_i.title) |title_fce| {
                                    node_title = try title_fce(tmp_alloc, tab_o.db, node);
                                } else {
                                    node_title = try tmp_alloc.dupeZ(u8, node_i.name);
                                }

                                var icon_buf: [16:0]u8 = undefined;
                                var node_icon: [:0]const u8 = undefined;

                                if (node_i.icon) |icon_fce| {
                                    node_icon = try icon_fce(&icon_buf, tmp_alloc, tab_o.db, node);
                                } else {
                                    node_icon = try std.fmt.bufPrintZ(&icon_buf, "{s}", .{coreui.Icons.Node});
                                }

                                _coreui.text(try std.fmt.bufPrintZ(&buf, "{s}  {s}", .{ node_icon, node_title }));

                                header_min = _coreui.getItemRectMin();
                                header_max = .{ header_min[0] + width, header_min[1] + (_coreui.getFontSize()) }; //_coreui.getItemRectMax();
                            }

                            // Outputs
                            const outputs = try node_i.getOutputPins(tmp_alloc, tab_o.db, graph_obj, node);
                            defer tmp_alloc.free(outputs);
                            for (outputs) |output| {
                                _coreui.tableNextColumn();

                                const color = _graph.getTypeColor(output.type_hash);

                                _node_editor.pushStyleVar2f(.pivot_alignment, .{ 0.8, 0.5 });
                                _node_editor.pushStyleVar2f(.pivot_size, .{ 0, 0 });
                                defer _node_editor.popStyleVar(2);

                                const max_x = width;
                                const txt_size = _coreui.calcTextSize(output.name, .{});
                                _coreui.setCursorPosX(_coreui.getCursorPosX() + (max_x - txt_size[0] - pin_size));

                                try tab_o.pinhash_map.put(.{ node, output.pin_hash }, output.pin_name);
                                const pinid = PinId.init(node, output.pin_hash).toU64();
                                _node_editor.beginPin(pinid, .Output);
                                {
                                    defer _node_editor.endPin();

                                    _coreui.text(output.name);
                                    _coreui.sameLine(.{ .spacing = 0 });

                                    const cpos = _coreui.getCursorScreenPos();

                                    const connected = _node_editor.pinHadAnyLinks(pinid);
                                    try drawIcon(
                                        dl,
                                        .cirecle,
                                        cpos,
                                        .{ cpos[0] + pin_size, cpos[1] + pin_size },
                                        connected,
                                        color,
                                    );

                                    _coreui.dummy(.{ .w = pin_size, .h = pin_size });
                                }
                            }

                            // Settings
                            if (true) {
                                if (!node_i.type_hash.eql(graphvm.CALL_GRAPH_NODE_TYPE)) {
                                    if (graphvm.NodeType.readSubObj(tab_o.db, node_r, .settings)) |setting_obj| {
                                        _coreui.pushObjUUID(node);
                                        defer _coreui.popId();

                                        try _editor_inspector.cdbPropertiesObj(tmp_alloc, tab_o.db, tab_o, tab_o.selection.top_level_obj, setting_obj, 0, .{
                                            .hide_proto = true,
                                            .max_autopen_depth = 0,
                                            .flat = true,
                                        });
                                    }
                                }
                            }

                            // Input
                            const inputs = try node_i.getInputPins(tmp_alloc, tab_o.db, graph_obj, node);
                            defer tmp_alloc.free(inputs);
                            for (inputs) |input| {
                                _coreui.tableNextColumn();

                                const color = _graph.getTypeColor(input.type_hash);

                                _node_editor.pushStyleVar2f(.pivot_alignment, .{ 0.2, 0.5 });
                                _node_editor.pushStyleVar2f(.pivot_size, .{ 0, 0 });
                                defer _node_editor.popStyleVar(2);

                                const pin_k = .{ node, input.pin_hash };
                                const data = tab_o.pindata_map.get(pin_k);
                                const data_connected = data != null;

                                try tab_o.pinhash_map.put(pin_k, input.pin_name);
                                try tab_o.pintype_map.put(pin_k, input.type_hash);

                                const pinid = PinId.init(node, input.pin_hash).toU64();

                                var pin_connected = false;

                                //_coreui.setCursorPosX(_coreui.getCursorScreenPos()[0] - (pin_size) + (8) + (ne_style.node_border_width / 2));
                                _node_editor.beginPin(pinid, .Input);
                                var text_pos: f32 = 0;
                                {
                                    defer _node_editor.endPin();
                                    pin_connected = _node_editor.pinHadAnyLinks(pinid);

                                    const cpos = _coreui.getCursorScreenPos();
                                    const connected = pin_connected or data_connected;
                                    try drawIcon(
                                        dl,
                                        .cirecle,
                                        cpos,
                                        .{ cpos[0] + pin_size, cpos[1] + pin_size },
                                        connected,
                                        color,
                                    );

                                    _coreui.dummy(.{ .w = pin_size / 2, .h = pin_size });
                                    _coreui.sameLine(.{});
                                    _coreui.text(input.name);
                                    text_pos = _coreui.getItemRectMax()[0] - _coreui.getItemRectMin()[0];
                                }

                                if (!pin_connected and data_connected) {
                                    //_coreui.dummy(.{ .w = 0, .h = 0 });
                                    //_coreui.sameLine(.{});
                                    const data_r = graphvm.GraphDataType.read(tab_o.db, data.?).?;

                                    if (graphvm.GraphDataType.readSubObj(tab_o.db, data_r, .value)) |value_obj| {
                                        const value_i = _graph.findValueTypeIByCdb(tab_o.db.getTypeHash(value_obj.type_idx).?).?;
                                        const one_value = tab_o.db.getTypePropDef(tab_o.db.getTypeIdx(value_i.cdb_type_hash).?).?.len == 1;

                                        try _editor_inspector.cdbPropertiesObj(
                                            tmp_alloc,
                                            tab_o.db,
                                            tab_o,
                                            tab_o.selection.top_level_obj,
                                            value_obj,
                                            1,
                                            .{
                                                .hide_proto = true,
                                                .max_autopen_depth = 0,
                                                .flat = true,
                                                .no_prop_label = one_value,
                                            },
                                        );
                                    }
                                }
                            }
                        }
                    } else {
                        _coreui.text("INVALID NODE TYPE HASH");
                    }
                }
            }

            //Groups
            if (try graphvm.GraphType.readSubObjSet(tab_o.db, graph_r, .groups, tmp_alloc)) |groups| {
                defer tmp_alloc.free(groups);

                for (groups) |group| {
                    const group_r = tab_o.db.readObj(group).?;

                    if (new_graph) {
                        const node_pos_x = graphvm.GroupType.readValue(tab_o.db, f32, group_r, .pos_x);
                        const node_pos_y = graphvm.GroupType.readValue(tab_o.db, f32, group_r, .pos_y);
                        _node_editor.setNodePosition(group.toU64(), .{ node_pos_x * _coreui.getScaleFactor(), node_pos_y * _coreui.getScaleFactor() });
                    }

                    const node_size_x = graphvm.GroupType.readValue(tab_o.db, f32, group_r, .size_x);
                    const node_size_y = graphvm.GroupType.readValue(tab_o.db, f32, group_r, .size_y);

                    const group_title = graphvm.GroupType.readStr(tab_o.db, group_r, .title) orelse "NO TITLE";

                    var color: [4]f32 = if (graphvm.GroupType.readSubObj(tab_o.db, group_r, .color)) |color_obj| cdb_types.Color4f.f.toSlice(tab_o.db, color_obj) else .{ 1, 1, 1, 0.4 };
                    color[3] = 0.4;

                    _node_editor.pushStyleColor(.node_bg, color);
                    defer _node_editor.popStyleColor(1);

                    _node_editor.beginNode(group.toU64());
                    _coreui.text(group_title);
                    _node_editor.group(.{ node_size_x * _coreui.getScaleFactor(), node_size_y * _coreui.getScaleFactor() });
                    defer _node_editor.endNode();
                }
            }

            // Connections
            if (try graphvm.GraphType.readSubObjSet(tab_o.db, graph_r, .connections, tmp_alloc)) |connections| {
                defer tmp_alloc.free(connections);

                for (connections) |connect| {
                    const node_r = tab_o.db.readObj(connect).?;

                    const from_node = graphvm.ConnectionType.readRef(tab_o.db, node_r, .from_node) orelse cetech1.cdb.ObjId{};
                    const from_pin = graphvm.ConnectionType.f.getFromPinId(tab_o.db, node_r);

                    const to_node = graphvm.ConnectionType.readRef(tab_o.db, node_r, .to_node) orelse cetech1.cdb.ObjId{};
                    const to_pin = graphvm.ConnectionType.f.getToPinId(tab_o.db, node_r);

                    const from_pin_id = PinId.init(from_node, from_pin).toU64();
                    const to_pin_id = PinId.init(to_node, to_pin).toU64();

                    var type_color: [4]f32 = .{ 1, 1, 1, 1 };

                    //TODO: inform user about invalid connection
                    if (tab_o.db.readObj(from_node)) |from_node_obj_r| {
                        const from_node_type = graphvm.NodeType.f.getNodeTypeId(tab_o.db, from_node_obj_r);
                        const out_pin = (try _graph.getOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node, from_node_type, from_pin)) orelse continue;
                        type_color = _graph.getTypeColor(out_pin.type_hash);
                    }

                    _node_editor.link(connect.toU64(), from_pin_id, to_pin_id, type_color, 3);
                }
            }

            if (new_graph) {
                _node_editor.navigateToContent(-1);
            }

            // Context menu
            const popup_pos = _coreui.getMousePos();

            _node_editor.suspend_();
            {
                defer _node_editor.resume_();
                if (_node_editor.showBackgroundContextMenu()) {
                    _coreui.openPopup("ui_graph_background_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (_node_editor.showNodeContextMenu(&tab_o.ctxNodeId)) {
                    _coreui.openPopup("ui_graph_node_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (_node_editor.showLinkContextMenu(&tab_o.ctxLinkId)) {
                    _coreui.openPopup("ui_graph_link_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (_node_editor.showPinContextMenu(&tab_o.ctxPinId)) {
                    _coreui.openPopup("ui_graph_pin_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (_coreui.beginPopup("ui_graph_background_context_menu", .{})) {
                    defer _coreui.endPopup();

                    tab_o.filter = _coreui.uiFilter(&tab_o.filter_buff, tab_o.filter);

                    const impls = try _apidb.getImpl(tmp_alloc, graphvm.GraphNodeI);
                    defer tmp_alloc.free(impls);

                    if (tab_o.filter == null) {
                        // Create category menu first
                        for (impls) |iface| {
                            if (iface.category) |category| {
                                var buff: [256:0]u8 = undefined;
                                const label = try std.fmt.bufPrintZ(&buff, "{s} {s}###{s}", .{ coreui.Icons.Folder, category, category });

                                if (_coreui.beginMenu(_allocator, label, true, null)) {
                                    _coreui.endMenu();
                                }
                            }
                        }
                    }

                    if (_coreui.menuItem(_allocator, coreui.Icons.Group ++ " " ++ "Group", .{}, tab_o.filter)) {
                        const node_obj = try graphvm.GroupType.createObject(tab_o.db);

                        const node_w = tab_o.db.writeObj(node_obj).?;

                        try graphvm.GroupType.setStr(tab_o.db, node_w, .title, "Group");

                        graphvm.GroupType.setValue(tab_o.db, f32, node_w, .pos_x, tab_o.ctxPos[0]);
                        graphvm.GroupType.setValue(tab_o.db, f32, node_w, .pos_x, tab_o.ctxPos[1]);

                        graphvm.GroupType.setValue(tab_o.db, f32, node_w, .size_x, 50);
                        graphvm.GroupType.setValue(tab_o.db, f32, node_w, .size_y, 50);

                        const graph_w = tab_o.db.writeObj(graph_obj).?;
                        try graphvm.GraphType.addSubObjToSet(tab_o.db, graph_w, .groups, &.{node_w});

                        try tab_o.db.writeCommit(node_w);
                        try tab_o.db.writeCommit(graph_w);

                        _node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                    }

                    for (impls) |iface| {
                        var category_open = true;

                        if (tab_o.filter == null) {
                            if (iface.category) |category| {
                                var buff: [256:0]u8 = undefined;
                                const label = try std.fmt.bufPrintZ(&buff, "###{s}", .{category});

                                category_open = _coreui.beginMenu(_allocator, label, true, null);
                            }
                        }

                        var icon_buf: [16:0]u8 = undefined;
                        var node_icon: [:0]const u8 = undefined;

                        if (iface.icon) |icon_fce| {
                            node_icon = try icon_fce(&icon_buf, tmp_alloc, tab_o.db, .{});
                        } else {
                            node_icon = try std.fmt.bufPrintZ(&icon_buf, "{s}", .{coreui.Icons.Node});
                        }

                        var buff: [256:0]u8 = undefined;
                        const label = try std.fmt.bufPrintZ(&buff, "{s} {s}###{s}", .{ node_icon, iface.name, iface.name });

                        if (category_open and _coreui.menuItem(_allocator, label, .{}, tab_o.filter)) {
                            const node_obj = try _graph.createCdbNode(tab_o.db, iface.type_hash, tab_o.ctxPos);

                            const node_w = tab_o.db.writeObj(node_obj).?;

                            const graph_w = tab_o.db.writeObj(graph_obj).?;
                            try graphvm.GraphType.addSubObjToSet(tab_o.db, graph_w, .nodes, &.{node_w});

                            try tab_o.db.writeCommit(node_w);
                            try tab_o.db.writeCommit(graph_w);

                            _node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                        }

                        if (tab_o.filter == null and category_open and iface.category != null) {
                            _coreui.endMenu();
                        }
                    }
                }

                // Node or Group
                if (_coreui.beginPopup("ui_graph_node_context_menu", .{})) {
                    defer _coreui.endPopup();

                    const node_obj = cdb.ObjId.fromU64(tab_o.ctxNodeId);
                    const enabled = tab_o.db.isChildOff(tab_o.selection.top_level_obj, node_obj);

                    if (node_obj.type_idx.eql(NodeTypeIdx)) {
                        const node_obj_r = graphvm.NodeType.read(tab_o.db, node_obj).?;
                        const node_type = graphvm.NodeType.f.getNodeTypeId(tab_o.db, node_obj_r);

                        if (node_type.eql(graphvm.CALL_GRAPH_NODE_TYPE)) {
                            if (graphvm.NodeType.readSubObj(tab_o.db, node_obj_r, .settings)) |settings| {
                                const settings_r = graphvm.CallGraphNodeSettings.read(tab_o.db, settings).?;
                                if (graphvm.CallGraphNodeSettings.readSubObj(tab_o.db, settings_r, .graph)) |graph| {
                                    if (_coreui.menuItem(_allocator, coreui.Icons.Open ++ "  " ++ "Open subgraph", .{}, null)) {
                                        try _editor_obj_buffer.addToFirst(tmp_alloc, tab_o.db, .{ .top_level_obj = tab_o.selection.top_level_obj, .obj = graph });
                                    }
                                }
                            }
                        }

                        _coreui.separator();
                    }

                    if (_coreui.menuItem(_allocator, coreui.Icons.Delete ++ "  " ++ "Delete node", .{ .enabled = enabled }, null)) {
                        _ = _node_editor.deleteNode(tab_o.ctxNodeId);
                    }
                }

                // Link
                if (_coreui.beginPopup("ui_graph_link_context_menu", .{})) {
                    defer _coreui.endPopup();

                    if (_coreui.menuItem(_allocator, coreui.Icons.Delete ++ "  " ++ "Delete link", .{}, null)) {
                        _ = _node_editor.deleteLink(tab_o.ctxLinkId);
                    }
                }

                // Pin
                if (_coreui.beginPopup("ui_graph_pin_context_menu", .{})) {
                    defer _coreui.endPopup();
                    const pin_connected = _node_editor.pinHadAnyLinks(tab_o.ctxPinId);

                    const pin_id = PinId.fromU64(tab_o.ctxPinId);
                    const node_obj = pin_id.getObj(tab_o.db);
                    const pin_hash = pin_id.getPinHash();
                    const pin_k = .{ node_obj, pin_hash };

                    const from_node_obj_r = tab_o.db.readObj(node_obj).?;
                    const from_node_type = graphvm.NodeType.f.getNodeTypeId(tab_o.db, from_node_obj_r);

                    const is_output = try _graph.isOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, node_obj, from_node_type, pin_hash);

                    const enabled = tab_o.db.isChildOff(tab_o.selection.top_level_obj, node_obj);

                    if (pin_connected) {
                        if (_coreui.menuItem(_allocator, "Break all links", .{}, null)) {
                            _ = _node_editor.breakPinLinks(tab_o.ctxPinId);
                        }
                    } else if (!is_output) {
                        const pin_type = tab_o.pintype_map.get(pin_k).?;
                        const generic_pin_type = graphvm.PinTypes.GENERIC.eql(pin_type);

                        const data = tab_o.pindata_map.get(pin_k);

                        if (data) |d| {
                            if (_coreui.menuItem(_allocator, "Delete data", .{ .enabled = enabled }, null)) {
                                tab_o.db.destroyObject(d);
                                _ = tab_o.pindata_map.remove(pin_k);
                            }
                        } else {
                            if (generic_pin_type) {
                                if (_coreui.beginMenu(_allocator, "Add value", enabled, null)) {
                                    defer _coreui.endMenu();

                                    const impls = try _apidb.getImpl(tmp_alloc, graphvm.GraphValueTypeI);
                                    defer tmp_alloc.free(impls);
                                    for (impls) |iface| {
                                        if (iface.cdb_type_hash.isEmpty()) continue;
                                        if (iface.type_hash.eql(graphvm.PinTypes.Flow)) continue;

                                        if (_coreui.menuItem(tmp_alloc, iface.name, .{}, null)) {
                                            const data_obj = try graphvm.GraphDataType.createObject(tab_o.db);
                                            const data_w = graphvm.GraphDataType.write(tab_o.db, data_obj).?;

                                            try graphvm.GraphDataType.setRef(tab_o.db, data_w, .to_node, node_obj);

                                            const pin_name = tab_o.pinhash_map.get(pin_k).?;
                                            try graphvm.GraphDataType.setStr(tab_o.db, data_w, .to_node_pin, pin_name);

                                            const value_obj = try tab_o.db.createObject(tab_o.db.getTypeIdx(iface.cdb_type_hash).?);
                                            const value_w = tab_o.db.writeObj(value_obj).?;

                                            try graphvm.GraphDataType.setSubObj(tab_o.db, data_w, .value, value_w);

                                            const graph_w = graphvm.GraphType.write(tab_o.db, graph_obj).?;
                                            try graphvm.GraphType.addSubObjToSet(tab_o.db, graph_w, .data, &.{data_w});

                                            try tab_o.db.writeCommit(value_w);
                                            try tab_o.db.writeCommit(data_w);
                                            try tab_o.db.writeCommit(graph_w);

                                            try tab_o.pindata_map.put(pin_k, data_obj);
                                        }
                                    }
                                }
                            } else if (!pin_type.eql(graphvm.PinTypes.Flow)) {
                                const type_i = _graph.findValueTypeI(pin_type).?;

                                const label = try std.fmt.bufPrintZ(&buf, "Set value ({s})", .{type_i.name});
                                if (_coreui.menuItem(_allocator, label, .{ .enabled = enabled }, null)) {
                                    const data_obj = try graphvm.GraphDataType.createObject(tab_o.db);
                                    const data_w = graphvm.GraphDataType.write(tab_o.db, data_obj).?;

                                    try graphvm.GraphDataType.setRef(tab_o.db, data_w, .to_node, node_obj);

                                    const pin_name = tab_o.pinhash_map.get(pin_k).?;
                                    try graphvm.GraphDataType.setStr(tab_o.db, data_w, .to_node_pin, pin_name);

                                    const value_obj = try tab_o.db.createObject(tab_o.db.getTypeIdx(type_i.cdb_type_hash).?);
                                    const value_w = tab_o.db.writeObj(value_obj).?;

                                    try graphvm.GraphDataType.setSubObj(tab_o.db, data_w, .value, value_w);

                                    const graph_w = graphvm.GraphType.write(tab_o.db, graph_obj).?;
                                    try graphvm.GraphType.addSubObjToSet(tab_o.db, graph_w, .data, &.{data_w});

                                    try tab_o.db.writeCommit(value_w);
                                    try tab_o.db.writeCommit(data_w);
                                    try tab_o.db.writeCommit(graph_w);

                                    try tab_o.pindata_map.put(pin_k, data_obj);
                                }
                            }
                        }
                    }
                }
            }

            // Created
            if (_node_editor.beginCreate()) {
                var ne_form_id: ?node_editor.PinId = null;
                var ne_to_id: ?node_editor.PinId = null;
                if (_node_editor.queryNewLink(&ne_form_id, &ne_to_id)) {
                    if (ne_form_id != null and ne_to_id != null) {
                        var from_id = PinId.fromU64(ne_form_id.?);
                        var from_node_obj = cdb.ObjId{ .id = from_id.objid, .gen = from_id.objgen, .type_idx = graphvm.NodeType.typeIdx(tab_o.db) };
                        const from_node_obj_r = tab_o.db.readObj(from_node_obj).?;
                        var from_node_type = graphvm.NodeType.f.getNodeTypeId(tab_o.db, from_node_obj_r);

                        var to_id = PinId.fromU64(ne_to_id.?);
                        var to_node_obj = cdb.ObjId{ .id = to_id.objid, .gen = to_id.objgen, .type_idx = graphvm.NodeType.typeIdx(tab_o.db) };
                        const to_node_obj_r = tab_o.db.readObj(to_node_obj).?;
                        var to_node_type = graphvm.NodeType.f.getNodeTypeId(tab_o.db, to_node_obj_r);

                        // If drag node from input to output swap it
                        // Allways OUT => IN semantic.
                        if (try _graph.isInputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node_obj, from_node_type, .{ .id = from_id.pin_hash })) {
                            std.mem.swap(PinId, &from_id, &to_id);
                            std.mem.swap(cdb.ObjId, &from_node_obj, &to_node_obj);
                            std.mem.swap(cetech1.strid.StrId32, &from_node_type, &to_node_type);
                            std.mem.swap(?node_editor.PinId, &ne_form_id, &ne_to_id);
                        }

                        const is_input = try _graph.isInputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, to_node_obj, to_node_type, .{ .id = to_id.pin_hash });
                        const is_output = try _graph.isOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node_obj, from_node_type, .{ .id = from_id.pin_hash });

                        if (ne_form_id.? == ne_to_id.?) {
                            _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 3);
                        } else if (!is_input or !is_output) {
                            _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 3);
                        } else if (from_node_obj.eql(to_node_obj)) {
                            _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 3);
                        } else {
                            const output_pin_def = (try _graph.getOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node_obj, from_node_type, .{ .id = from_id.pin_hash })).?;
                            const input_pin_def = (try _graph.getInputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, to_node_obj, to_node_type, .{ .id = to_id.pin_hash })).?;

                            const type_color = _graph.getTypeColor(output_pin_def.type_hash);

                            // Type check
                            if (!input_pin_def.type_hash.eql(graphvm.PinTypes.GENERIC) and !input_pin_def.type_hash.eql(output_pin_def.type_hash)) {
                                _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 3);
                            } else if (_node_editor.acceptNewItem(type_color, 3)) {
                                if (_node_editor.pinHadAnyLinks(ne_to_id.?)) {
                                    _ = _node_editor.breakPinLinks(ne_to_id.?);
                                }

                                const connection_obj = try graphvm.ConnectionType.createObject(tab_o.db);
                                const connection_w = tab_o.db.writeObj(connection_obj).?;

                                try graphvm.ConnectionType.setRef(tab_o.db, connection_w, .from_node, from_node_obj);
                                const from_pin_str = tab_o.pinhash_map.get(.{ from_node_obj, .{ .id = from_id.pin_hash } }).?;
                                try graphvm.ConnectionType.setStr(tab_o.db, connection_w, .from_pin, from_pin_str);

                                try graphvm.ConnectionType.setRef(tab_o.db, connection_w, .to_node, to_node_obj);
                                const to_pin_str = tab_o.pinhash_map.get(.{ to_node_obj, .{ .id = to_id.pin_hash } }).?;
                                try graphvm.ConnectionType.setStr(tab_o.db, connection_w, .to_pin, to_pin_str);

                                const graph_w = tab_o.db.writeObj(graph_obj).?;
                                try graphvm.GraphType.addSubObjToSet(tab_o.db, graph_w, .connections, &.{connection_w});

                                try tab_o.db.writeCommit(connection_w);
                                try tab_o.db.writeCommit(graph_w);
                            }
                        }
                    }
                }
            }
            _node_editor.endCreate();

            // Deleted
            if (_node_editor.beginDelete()) {
                var node_id: node_editor.NodeId = 0;
                while (_node_editor.queryDeletedNode(&node_id)) {
                    if (_node_editor.acceptDeletedItem(true)) {
                        const node_obj = cdb.ObjId.fromU64(node_id);
                        tab_o.db.destroyObject(node_obj);

                        var it = tab_o.pindata_map.iterator();
                        while (it.next()) |e| {
                            const k = e.key_ptr.*;
                            if (!k[0].eql(node_obj)) continue;

                            const v = e.value_ptr.*;
                            tab_o.db.destroyObject(v);
                        }
                    }
                }

                var link_id: node_editor.LinkId = 0;
                while (_node_editor.queryDeletedLink(&link_id, null, null)) {
                    if (_node_editor.acceptDeletedItem(true)) {
                        const link_obj = cdb.ObjId.fromU64(link_id);
                        tab_o.db.destroyObject(link_obj);
                    }
                }
            }
            _node_editor.endDelete();
        }

        // Selection handling
        if (_node_editor.hasSelectionChanged()) {
            const selected_object_n = _node_editor.getSelectedObjectCount();
            if (selected_object_n != 0) {
                const selected_nodes = try tmp_alloc.alloc(node_editor.NodeId, @intCast(selected_object_n));

                var items = try std.ArrayList(coreui.SelectionItem).initCapacity(tmp_alloc, @intCast(selected_object_n));
                defer items.deinit();
                // Nodes
                {
                    const nodes_n = _node_editor.getSelectedNodes(selected_nodes);
                    var selected_objs: []cdb.ObjId = undefined;
                    selected_objs.ptr = @ptrCast(selected_nodes.ptr);
                    selected_objs.len = @intCast(nodes_n);

                    for (selected_objs) |obj| {
                        if (obj.type_idx.eql(NodeTypeIdx)) {
                            items.appendAssumeCapacity(.{
                                .top_level_obj = tab_o.selection.top_level_obj,
                                .obj = obj,
                                .in_set_obj = obj,
                                .parent_obj = tab_o.root_graph_obj,
                                .prop_idx = graphvm.GraphType.propIdx(.nodes),
                            });
                        } else if (obj.type_idx.eql(GroupTypeIdx)) {
                            items.appendAssumeCapacity(.{
                                .top_level_obj = tab_o.selection.top_level_obj,
                                .obj = obj,
                                .in_set_obj = obj,
                                .parent_obj = tab_o.root_graph_obj,
                                .prop_idx = graphvm.GraphType.propIdx(.groups),
                            });
                        }
                    }
                }

                //Links
                {
                    const nodes_n = _node_editor.getSelectedLinks(selected_nodes);

                    var selected_objs: []cdb.ObjId = undefined;
                    selected_objs.ptr = @ptrCast(selected_nodes.ptr);
                    selected_objs.len = @intCast(nodes_n);

                    for (selected_objs) |obj| {
                        if (obj.type_idx.eql(ConnectionTypeIdx)) {
                            items.appendAssumeCapacity(.{
                                .top_level_obj = tab_o.selection.top_level_obj,
                                .obj = obj,
                                .in_set_obj = obj,
                                .parent_obj = tab_o.root_graph_obj,
                                .prop_idx = graphvm.GraphType.propIdx(.connections),
                            });
                        }
                    }
                }

                const objs = try items.toOwnedSlice();
                try tab_o.inter_selection.set(objs);
                _editor.propagateSelection(tab_o.db, inst, objs);
            } else {
                try tab_o.inter_selection.set(&.{tab_o.selection});
                _editor.propagateSelection(tab_o.db, inst, &.{tab_o.selection});
            }
        }

        _node_editor.setCurrentEditor(null);
    }

    // Draw tab menu
    pub fn menu(inst: *editor.TabO) !void {
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));

        const alloc = try _tempalloc.create();
        defer _tempalloc.destroy(alloc);

        if (_coreui.menuItem(_allocator, coreui.Icons.FitContent, .{}, null)) {
            _node_editor.setCurrentEditor(tab_o.editor);
            defer _node_editor.setCurrentEditor(null);

            _node_editor.navigateToContent(-1);
        }

        if (_coreui.menuItem(_allocator, coreui.Icons.FitContent, .{}, null)) {
            _node_editor.setCurrentEditor(tab_o.editor);
            defer _node_editor.setCurrentEditor(null);

            _node_editor.navigateToSelection(false, -1);
        }

        const need_build = _graph.needCompile(tab_o.root_graph_obj);
        if (_coreui.menuItem(_allocator, coreui.Icons.Build, .{ .enabled = need_build }, null)) {
            try _graph.compile(alloc, tab_o.root_graph_obj);
        }
    }

    pub fn focused(inst: *editor.TabO) !void {
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));

        const allocator = try _tempalloc.create();
        defer _tempalloc.destroy(allocator);

        if (!tab_o.inter_selection.isEmpty()) {
            if (tab_o.inter_selection.toSlice(allocator)) |objs| {
                defer allocator.free(objs);
                _editor.propagateSelection(tab_o.db, inst, objs);
            }
        } else if (!tab_o.selection.isEmpty()) {
            _editor.propagateSelection(tab_o.db, inst, &.{tab_o.selection});
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, db: cdb.Db, selection: []const coreui.SelectionItem, sender_tab_hash: ?cetech1.strid.StrId32) !void {
        _ = sender_tab_hash; // autofix
        var tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));

        if (tab_o.inter_selection.isSelectedAll(selection)) return;

        const selected = selection[0];

        if (_assetdb.isAssetObjTypeOf(selected.obj, graphvm.GraphType.typeIdx(db))) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(GraphTypeIdx)) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(NodeTypeIdx) or selected.obj.type_idx.eql(GroupTypeIdx)) {
            _node_editor.setCurrentEditor(tab_o.editor);
            defer _node_editor.setCurrentEditor(null);
            _node_editor.selectNode(selected.obj.toU64(), false);
            _node_editor.navigateToSelection(selected.obj.type_idx.eql(graphvm.GroupType.typeIdx(db)), -1);
        } else if (selected.obj.type_idx.eql(ConnectionTypeIdx)) {
            _node_editor.setCurrentEditor(tab_o.editor);
            defer _node_editor.setCurrentEditor(null);
            _node_editor.selectLink(selected.obj.toU64(), false);
            _node_editor.navigateToSelection(false, -1);
        }
    }

    pub fn assetRootOpened(inst: *editor.TabO) !void {
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));
        tab_o.filter = null;
        tab_o.root_graph_obj = .{};
    }
});

// Create graph asset
var create_graph_i = editor.CreateAssetI.implement(
    graphvm.GraphType.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.Db,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try _assetdb.buffGetValidName(
                allocator,
                &buff,
                db,
                folder,
                db.getTypeIdx(graphvm.GraphType.type_hash).?,
                "NewGraph",
            );

            const new_obj = try graphvm.GraphType.createObject(db);

            _ = _assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Graph ++ "  " ++ "Graph";
        }
    },
);

var graph_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        _ = db;
        _ = obj;

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Graph});
    }
});

var node_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = db.readObj(obj).?;

        const node_type_hash = graphvm.NodeType.f.getNodeTypeId(db, obj_r);
        if (_graph.findNodeI(node_type_hash)) |node_i| {
            return std.fmt.bufPrintZ(
                buff,
                "{s}",
                .{
                    node_i.name,
                },
            ) catch "";
        }
        return std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                "!!! Invalid node type",
            },
        ) catch "";
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const obj_r = db.readObj(obj).?;

        const node_type_hash = graphvm.NodeType.f.getNodeTypeId(db, obj_r);
        if (_graph.findNodeI(node_type_hash)) |node_i| {
            if (node_i.icon) |icon| {
                return icon(buff, allocator, db, obj);
            }
        }

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Node});
    }
});

var group_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = db.readObj(obj).?;

        if (graphvm.GroupType.readStr(db, obj_r, .title)) |tile| {
            return std.fmt.bufPrintZ(
                buff,
                "{s}",
                .{
                    tile,
                },
            ) catch "";
        }

        return std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                "No title",
            },
        ) catch "";
    }

    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        _ = db;
        _ = obj;
        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Group});
    }

    pub fn uiColor(
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![4]f32 {
        const obj_r = db.readObj(obj).?;
        const color = graphvm.GroupType.readSubObj(db, obj_r, .color) orelse return .{ 1.0, 1.0, 1.0, 1.0 };
        return cetech1.cdb_types.Color4f.f.toSlice(db, color);
    }
});

var interface_input_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = db.readObj(obj).?;

        if (graphvm.InterfaceInput.readStr(db, obj_r, .name)) |tile| {
            return std.fmt.bufPrintZ(
                buff,
                "{s}",
                .{
                    tile,
                },
            ) catch "";
        }

        return std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                "No title",
            },
        ) catch "";
    }
});

var interface_output_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        const obj_r = db.readObj(obj).?;

        if (graphvm.InterfaceOutput.readStr(db, obj_r, .name)) |tile| {
            return std.fmt.bufPrintZ(
                buff,
                "{s}",
                .{
                    tile,
                },
            ) catch "";
        }

        return std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                "No title",
            },
        ) catch "";
    }
});

var connection_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator; // autofix
        _ = db;
        _ = obj;
        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Link});
    }
});

const node_prop_aspect = editor_inspector.UiPropertiesAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        tab: *editor.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        const node_r = graphvm.NodeType.read(db, obj).?;

        if (graphvm.NodeType.readSubObj(db, node_r, .settings)) |setting_obj| {
            try _editor_inspector.cdbPropertiesObj(allocator, db, tab, top_level_obj, setting_obj, depth, args);
        }
    }
});

// TODO: generic/join variable menu
const input_variable_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) !void {
        _ = prop_idx; // autofix

        const subobj = graphvm.InterfaceInput.readSubObj(db, graphvm.InterfaceInput.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                const impls = try _apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.InterfaceInput.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graphvm.InterfaceInput.setSubObj(db, obj_w, .value, value_obj_w);

                        try db.writeCommit(value_obj_w);
                        try db.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

// TODO: generic/join variable menu
const output_variable_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) !void {
        _ = prop_idx; // autofix

        const subobj = graphvm.InterfaceInput.readSubObj(db, graphvm.InterfaceInput.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                const impls = try _apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.InterfaceOutput.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graphvm.InterfaceOutput.setSubObj(db, obj_w, .value, value_obj_w);

                        try db.writeCommit(value_obj_w);
                        try db.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

// TODO: generic/join variable menu
const data_variable_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) !void {
        _ = prop_idx; // autofix

        const subobj = graphvm.GraphDataType.readSubObj(db, graphvm.GraphDataType.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                const impls = try _apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.GraphDataType.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graphvm.GraphDataType.setSubObj(db, obj_w, .value, value_obj_w);

                        try db.writeCommit(value_obj_w);
                        try db.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

const const_value_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) !void {
        _ = prop_idx; // autofix

        const subobj = graphvm.ConstNodeSettings.readSubObj(db, graphvm.ConstNodeSettings.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                const impls = try _apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.eql(graphvm.flowType.type_hash)) continue;
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.ConstNodeSettings.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graphvm.ConstNodeSettings.setSubObj(db, obj_w, .value, value_obj_w);

                        try db.writeCommit(value_obj_w);
                        try db.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

var AssetTypeIdx: cdb.TypeIdx = undefined;
var GraphTypeIdx: cdb.TypeIdx = undefined;
var ConnectionTypeIdx: cdb.TypeIdx = undefined;
var NodeTypeIdx: cdb.TypeIdx = undefined;
var GroupTypeIdx: cdb.TypeIdx = undefined;

var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cetech1.cdb.Db) !void {
        try graphvm.GraphType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.graph_visual_aspect,
        );

        try graphvm.NodeType.addAspect(
            db,
            editor_inspector.UiPropertiesAspect,
            _g.ui_properties_aspect,
        );

        try graphvm.NodeType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.node_visual_aspect,
        );

        try graphvm.GroupType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.group_visual_aspect,
        );

        try graphvm.ConnectionType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.connection_visual_aspect,
        );

        try graphvm.InterfaceInput.addAspect(
            db,
            editor.UiVisualAspect,
            _g.interface_input_visual_aspect,
        );

        try graphvm.InterfaceInput.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.input_value_menu_aspect,
        );

        try graphvm.InterfaceOutput.addAspect(
            db,
            editor.UiVisualAspect,
            _g.interface_output_visual_aspect,
        );

        try graphvm.InterfaceOutput.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.output_value_menu_aspect,
        );

        try graphvm.ConstNodeSettings.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.const_value_menu_aspect,
        );

        try graphvm.GraphDataType.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.data_value_menu_aspect,
        );

        AssetTypeIdx = assetdb.Asset.typeIdx(db);
        GraphTypeIdx = graphvm.GraphType.typeIdx(db);
        ConnectionTypeIdx = graphvm.ConnectionType.typeIdx(db);
        NodeTypeIdx = graphvm.NodeType.typeIdx(db);
        GroupTypeIdx = graphvm.GroupType.typeIdx(db);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;

    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _node_editor = apidb.getZigApi(module_name, node_editor.NodeEditorApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _graph = apidb.getZigApi(module_name, cetech1.graphvm.GraphVMApi).?;
    _editor_inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;
    _editor_obj_buffer = apidb.getZigApi(module_name, editor_obj_buffer.EditorObjBufferAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVarValue(editor.TabTypeI, module_name, TAB_NAME, graph_tab);

    try apidb.implOrRemove(module_name, editor.TabTypeI, &graph_tab, load);
    try apidb.implOrRemove(module_name, editor.CreateAssetI, &create_graph_i, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    _g.graph_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_visual_aspect", graph_visual_aspect);
    _g.node_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_node_visual_aspect", node_visual_aspect);
    _g.group_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_group_visual_aspect", group_visual_aspect);
    _g.connection_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_connection_visual_aspect", connection_visual_aspect);
    _g.interface_input_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_interface_input_visual_aspect", interface_input_visual_aspect);
    _g.interface_output_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_interface_output_visual_aspect", interface_output_visual_aspect);
    _g.ui_properties_aspect = try apidb.globalVarValue(editor_inspector.UiPropertiesAspect, module_name, "ct_graph_node_properties_aspect", node_prop_aspect);
    _g.input_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_interface_input_menu_aspect", input_variable_menu_aspect);
    _g.output_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_interface_output_menu_aspect", output_variable_menu_aspect);
    _g.const_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_node_const_menu_aspect", const_value_menu_aspect);
    _g.data_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_data_variable_menu_aspect", data_variable_menu_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_graph(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
