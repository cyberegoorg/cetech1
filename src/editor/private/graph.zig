const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const node_editor = cetech1.coreui_node_editor;
const assetdb = cetech1.assetdb;
const math = cetech1.math;
const cdb_types = cetech1.cdb_types;
const Icons = coreui.CoreIcons;

const editor = cetech1.editor;
const editor_inspector = cetech1.editor.inspector;
const editor_obj_buffer = cetech1.editor.obj_buffer;
const graphvm = cetech1.scripting.graphvm;
const editor_tabs = cetech1.editor.tabs;
const editor_assetdb = cetech1.editor.assetdb;

const module_name = .editor_graph;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

const TAB_NAME = "ct_editor_graph_tab";

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

var _assetdb: *const assetdb.AssetDBAPI = undefined;
const tempalloc = cetech1.tempalloc;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor_tabs.TabTypeI = undefined,
    graph_visual_aspect: *editor.UiVisualAspect = undefined,
    node_visual_aspect: *editor.UiVisualAspect = undefined,
    group_visual_aspect: *editor.UiVisualAspect = undefined,
    connection_visual_aspect: *editor.UiVisualAspect = undefined,
    interface_input_visual_aspect: *editor.UiVisualAspect = undefined,
    interface_output_visual_aspect: *editor.UiVisualAspect = undefined,
    ui_properties_aspect: *editor_inspector.UiInspectorObjAspect = undefined,
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

    pub fn init(obj: cdb.ObjId, pin_hash: cetech1.StrId32) PinId {
        return .{
            .objid = obj.id,
            .objgen = obj.gen,
            .pin_hash = pin_hash.id,
        };
    }
    pub fn toU64(self: *const PinId) u64 {
        const ptr: *const u64 = @ptrCast(@alignCast(self));
        return ptr.*;
    }

    pub fn getObj(self: *const PinId, db: cdb.DbId) cdb.ObjId {
        return .{ .gen = self.objgen, .id = self.objid, .type_idx = graphvm.NodeTypeCdb.typeIdx(db), .db = db };
    }

    pub fn getPinHash(self: *const PinId) cetech1.StrId32 {
        return .{ .id = self.pin_hash };
    }

    pub fn fromU64(value: u64) PinId {
        const ptr: *const PinId = @ptrCast(@alignCast(&value));
        return ptr.*;
    }
};

const PinHashNameMap = cetech1.AutoHashMap(struct { cdb.ObjId, cetech1.StrId32 }, [:0]const u8);
const PinValueTypeMap = cetech1.AutoArrayHashMap(struct { cdb.ObjId, cetech1.StrId32 }, cetech1.StrId32);
const PinDataMap = cetech1.AutoHashMap(struct { cdb.ObjId, cetech1.StrId32 }, cdb.ObjId);

const ToFromConMap = cetech1.AutoHashMap(struct { cdb.ObjId, cetech1.StrId32 }, struct { cdb.ObjId, cetech1.StrId32 });

// Struct for tab type
const GraphEditorTab = struct {
    tab_i: editor_tabs.TabI,
    editor: *node_editor.EditorContext,

    db: cdb.DbId,
    selection: coreui.SelectedObj = coreui.SelectedObj.empty(),
    inter_selection: coreui.Selection,
    root_graph_obj: cdb.ObjId = .{},

    // Add node filter
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,

    ctxNodeId: node_editor.NodeId = 0,
    ctxLinkId: node_editor.LinkId = 0,
    ctxPinId: node_editor.PinId = 0,
    ctxPos: math.Vec2f = .{},

    pinhash_map: PinHashNameMap = .{},
    pindata_map: PinDataMap = .{},
    pintype_map: PinValueTypeMap = .{},
    resolved_pintype_map: PinValueTypeMap = .{},

    breadcrumb: cdb.ObjIdList = .empty,
};

const SaveJson = struct { group_size: struct { x: f32, y: f32 } };
fn saveNodeSettings(nodeId: node_editor.NodeId, data: [*]const u8, size: usize, reason: node_editor.SaveReasonFlags, userPointer: *anyopaque) callconv(.c) bool {
    const tab_o: *GraphEditorTab = @ptrCast(@alignCast(userPointer));
    _ = tab_o;

    if (reason.position or reason.size) {
        const pos = node_editor.getNodePosition(nodeId);

        const node_obj = cdb.ObjId.fromU64(nodeId);
        const node_w = cdb.writeObj(node_obj).?;

        if (node_obj.type_idx.eql(NodeTypeIdx)) {
            if (reason.position) {
                graphvm.NodeTypeCdb.setValue(f32, node_w, .pos_x, pos.x);
                graphvm.NodeTypeCdb.setValue(f32, node_w, .pos_y, pos.y);
            }
        } else if (node_obj.type_idx.eql(GroupTypeIdx)) {
            if (reason.position) {
                graphvm.GroupTypeCdb.setValue(f32, node_w, .pos_x, pos.x);
                graphvm.GroupTypeCdb.setValue(f32, node_w, .pos_y, pos.y);
            }

            if (reason.size) {
                const foo = std.json.parseFromSlice(
                    SaveJson,
                    _allocator,
                    data[0..size],
                    .{ .ignore_unknown_fields = true },
                ) catch return false;
                defer foo.deinit();

                graphvm.GroupTypeCdb.setValue(f32, node_w, .size_x, foo.value.group_size.x);
                graphvm.GroupTypeCdb.setValue(f32, node_w, .size_y, foo.value.group_size.y);
            }
        }

        cdb.writeCommit(node_w) catch undefined;
    }

    return true;
}

const PinIconType = enum {
    Circle,
};

fn drawIcon(drawlist: coreui.DrawList, icon_type: PinIconType, center: math.Vec2f, size: math.Vec2f, filled: bool, color: math.Color4f) !void {
    const col = math.SRGBA.fromColor4f(color);

    const rect_offset = -(size.x * 0.25 * 0.25);
    const style = node_editor.getStyle();

    switch (icon_type) {
        .Circle => {
            const c = math.Vec2f{ .x = center.x + (rect_offset * 0.5), .y = center.y };
            const r = 0.65 * size.x / 2;

            if (filled) {
                drawlist.addCircleFilled(.{
                    .p = c,
                    .r = r,
                    .col = col,
                });
            } else {
                var bg_c = style.getColor(.node_bg);
                bg_c.a = 1.0;

                drawlist.addCircleFilled(.{
                    .p = c,
                    .r = r,
                    .col = .fromColor4f(bg_c),
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

fn lessThanNodePath(allocator: std.mem.Allocator, lhs: *const graphvm.NodeI, rhs: *const graphvm.NodeI) bool {
    const lhs_full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ lhs.category orelse "", lhs.name }) catch undefined;
    defer allocator.free(lhs_full);

    const rhs_full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ rhs.category orelse "", rhs.name }) catch undefined;
    defer allocator.free(rhs_full);

    return std.ascii.lessThanIgnoreCase(lhs_full, rhs_full);
}

// Fill editor tab interface
var graph_tab = editor_tabs.TabTypeI.implement(editor_tabs.TabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .fromStr(TAB_NAME),
    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
    .ignore_selection_from_tab = &.{.fromStr("ct_editor_asset_browser_tab")},
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Graph ++ "  " ++ "Graph editor";
    }

    // Return tab title
    pub fn title(inst: *editor_tabs.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Graph ++ "  " ++ "Graph editor";
    }

    // Can open tab
    pub fn canOpen(allocator: Allocator, selection: []const coreui.SelectedObj) !bool {
        _ = allocator;
        for (selection) |obj| {
            if (!obj.obj.type_idx.eql(GraphTypeIdx) and !obj.obj.type_idx.eql(AssetTypeIdx)) return false;
            if (assetdb.getObjForAsset(obj.obj)) |o| if (!o.type_idx.eql(GraphTypeIdx)) return false;
        }

        return true;
    }

    // Create new tab instantce
    pub fn create(tab_id: u32) !?*editor_tabs.TabI {
        _ = tab_id;
        var tab_inst = _allocator.create(GraphEditorTab) catch undefined;

        tab_inst.* = .{
            .editor = node_editor.createEditor(.{
                .enable_smooth_zoom = true,
                .user_pointer = tab_inst,
                .save_node_settings = @ptrCast(&saveNodeSettings),
            }),
            .inter_selection = coreui.Selection.init(_allocator),
            .db = assetdb.getDb(),
            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor_tabs.TabI) !void {
        const tab_o: *GraphEditorTab = @ptrCast(@alignCast(tab_inst.inst));

        tab_o.pinhash_map.deinit(_allocator);
        tab_o.pindata_map.deinit(_allocator);
        tab_o.pintype_map.deinit(_allocator);
        tab_o.resolved_pintype_map.deinit(_allocator);

        tab_o.inter_selection.deinit();

        tab_o.breadcrumb.deinit(_allocator);

        node_editor.destroyEditor(tab_o.editor);

        _allocator.destroy(tab_o);
    }

    // Draw tab content
    pub fn ui(inst: *editor_tabs.TabO, kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;
        const tab_o: *GraphEditorTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        var buf: [128]u8 = undefined;

        node_editor.setCurrentEditor(tab_o.editor);
        {
            node_editor.begin("GraphEditor", .{});
            defer node_editor.end();

            node_editor.pushStyleVar1f(.link_strength, 0);
            node_editor.pushStyleVar1f(.node_rounding, 0);
            defer node_editor.popStyleVar(2);

            if (tab_o.selection.isEmpty()) {
                return;
            }

            var graph_obj = cdb.ObjId{};
            var selected_obj = cdb.ObjId{};

            selected_obj = tab_o.selection.obj;
            if (selected_obj.isEmpty()) return;

            if (selected_obj.type_idx.eql(AssetTypeIdx)) {
                if (!assetdb.isAssetObjTypeOf(selected_obj, graphvm.GraphTypeCdb.typeIdx(tab_o.db))) return;
                graph_obj = assetdb.getObjForAsset(selected_obj).?;
            } else if (selected_obj.type_idx.eql(GraphTypeIdx)) {
                graph_obj = selected_obj;
            }

            const new_graph = !tab_o.root_graph_obj.eql(graph_obj);

            if (cdb.isAlive(graph_obj)) {
                tab_o.root_graph_obj = graph_obj;
            } else {
                graph_obj = .{};
                tab_o.root_graph_obj = .{};
            }

            if (new_graph) {
                tab_o.pinhash_map.clearRetainingCapacity();
                tab_o.pindata_map.clearRetainingCapacity();
                tab_o.pintype_map.clearRetainingCapacity();

                if (tab_o.breadcrumb.items.len == 0) {
                    try tab_o.breadcrumb.append(_allocator, graph_obj);
                }
            }

            if (graph_obj.isEmpty()) return;

            const graph_r = cdb.readObj(graph_obj) orelse return;

            if (new_graph) {
                if (try graphvm.GraphTypeCdb.readSubObjSet(graph_r, .data, allocator)) |datas| {
                    for (datas) |data| {
                        const data_r = graphvm.GraphDataTypeCdb.read(data).?;

                        const to_node = graphvm.GraphDataTypeCdb.readRef(data_r, .to_node).?;
                        const to_node_pin_str = graphvm.GraphDataTypeCdb.readStr(data_r, .to_node_pin).?;
                        const to_node_pin = cetech1.strId32(to_node_pin_str);

                        const pin_k = .{ to_node, to_node_pin };
                        try tab_o.pindata_map.put(_allocator, pin_k, data);
                    }
                }
            }

            const all_connections = try graphvm.GraphTypeCdb.readSubObjSet(graph_r, .connections, allocator);
            defer if (all_connections) |c| allocator.free(c);

            const all_nodes = try graphvm.GraphTypeCdb.readSubObjSet(graph_r, .nodes, allocator);
            defer if (all_nodes) |c| allocator.free(c);

            // Resolve pin types (need for generics)
            // TODO: SHIT
            // TODO: cache and move to graphvm
            {
                var dag = cetech1.dag.DAG(u64).init(allocator);
                defer dag.deinit();

                var to_from_map = ToFromConMap{};
                defer to_from_map.deinit(allocator);

                var depends = cetech1.ArrayList(u64).empty;
                defer depends.deinit(allocator);

                tab_o.resolved_pintype_map.clearRetainingCapacity();

                // add all nodes
                if (all_nodes) |nodes| {
                    for (nodes) |node| {
                        depends.clearRetainingCapacity();

                        //try dag.add(node.toU64(), &.{});

                        if (all_connections) |connections| {
                            for (connections) |connect| {
                                const conn_r = cdb.readObj(connect).?;

                                const from_node = graphvm.ConnectionTypeCdb.readRef(conn_r, .from_node) orelse cdb.ObjId{};
                                const from_pin = graphvm.ConnectionTypeCdb.f.getFromPinId(conn_r);

                                const to_node = graphvm.ConnectionTypeCdb.readRef(conn_r, .to_node) orelse cdb.ObjId{};
                                const to_pin = graphvm.ConnectionTypeCdb.f.getToPinId(conn_r);

                                // only conection to this node
                                if (to_node != node) continue;

                                try to_from_map.put(allocator, .{ to_node, to_pin }, .{ from_node, from_pin });
                                try depends.append(allocator, from_node.toU64());
                                //try dag.add(from_node.toU64(), &.{});
                            }
                        }
                        try dag.add(node.toU64(), depends.items);
                    }
                }

                try dag.build_all();

                // log.debug("Collect types EDITOR:", .{});
                for (dag.output.keys()) |node_id| {
                    const node_obj = cdb.ObjId.fromU64(node_id);
                    const node_r = cdb.readObj(node_obj).?;

                    const node_type_hash = graphvm.NodeTypeCdb.f.getNodeTypeId(node_r);
                    const node_iface = graphvm.findNodeI(node_type_hash).?;

                    // log.debug("\t{s} {s}", .{ cdb.getUuid(node_obj).?, node_iface.name });
                    var pins_def = try node_iface.getPinsDef(node_iface, allocator, graph_obj, node_obj);
                    defer pins_def.deinit(allocator);

                    for (pins_def.in) |in_pin| {
                        const is_generic = in_pin.type_hash.eql(graphvm.PinTypes.GENERIC);
                        if (is_generic) {
                            const data = tab_o.pindata_map.get(.{ node_obj, in_pin.pin_hash });

                            var resolved_type: cetech1.StrId32 = .{};
                            if (data) |d| {
                                const data_r = graphvm.GraphDataTypeCdb.read(d).?;

                                if (graphvm.GraphDataTypeCdb.readSubObj(data_r, .value)) |value_obj| {
                                    const value_i = graphvm.findValueTypeIByCdb(cdb.getTypeHash(tab_o.db, value_obj.type_idx).?).?;
                                    resolved_type = value_i.type_hash;
                                }
                            } else {
                                if (to_from_map.get(.{ node_obj, in_pin.pin_hash })) |from_node| {
                                    resolved_type = tab_o.resolved_pintype_map.get(from_node).?;
                                } else {
                                    resolved_type = in_pin.type_hash;
                                }
                            }

                            try tab_o.resolved_pintype_map.put(_allocator, .{ node_obj, in_pin.pin_hash }, resolved_type);
                        } else {
                            try tab_o.resolved_pintype_map.put(_allocator, .{ node_obj, in_pin.pin_hash }, in_pin.type_hash);
                        }
                    }

                    for (pins_def.out) |out_pin| {
                        if (out_pin.type_of) |tof| {
                            const from_node_type = tab_o.resolved_pintype_map.get(.{ node_obj, tof }) orelse continue;
                            try tab_o.resolved_pintype_map.put(_allocator, .{ node_obj, out_pin.pin_hash }, from_node_type);
                        } else {
                            try tab_o.resolved_pintype_map.put(_allocator, .{ node_obj, out_pin.pin_hash }, out_pin.type_hash);
                        }
                    }
                }
            }

            // for (tab_o.pintype_map.keys(), tab_o.pintype_map.values()) |k, v| {
            //     log.debug("{any} => {any}", .{ k, v });
            // }

            const node_padding = [4]f32{ 4, 4, 4, 4 };
            // Nodes
            if (all_nodes) |nodes| {
                for (nodes) |node| {
                    const node_r = cdb.readObj(node).?;

                    const width = (128 + 32);
                    const pin_size = coreui.getFontSize();
                    var header_min: math.Vec2f = .{};
                    var header_max: math.Vec2f = .{};

                    const enabled = cdb.isChildOff(tab_o.selection.top_level_obj, node);

                    if (new_graph or !enabled) {
                        const node_pos_x = graphvm.NodeTypeCdb.readValue(f32, node_r, .pos_x);
                        const node_pos_y = graphvm.NodeTypeCdb.readValue(f32, node_r, .pos_y);
                        node_editor.setNodePosition(node.toU64(), .{
                            .x = node_pos_x,
                            .y = node_pos_y,
                        });
                    }

                    coreui.beginDisabled(.{ .disabled = !enabled });
                    defer coreui.endDisabled();

                    node_editor.pushStyleVar4f(.node_padding, node_padding);
                    defer node_editor.popStyleVar(1);

                    node_editor.beginNode(node.toU64());
                    defer {
                        node_editor.endNode();

                        if (coreui.isItemVisible()) {
                            const style = coreui.getStyle();
                            const ne_style = node_editor.getStyle();

                            const half_border = ne_style.node_border_width * 0.5;

                            var dl = node_editor.getNodeBackgroundDrawList(node.toU64());

                            dl.addRectFilled(.{
                                .pmin = .{ .x = header_min.x - (half_border + node_padding[0] / 2), .y = header_min.y - (half_border + node_padding[0] / 2) },
                                .pmax = .{ .x = header_max.x + (half_border + node_padding[1] / 2), .y = header_max.y + (node_padding[1] / 2) - 1 },
                                .col = .fromColor4f(style.getColor(.title_bg_active)),
                                .rounding = ne_style.node_rounding,
                                .flags = coreui.DrawFlags.round_corners_top,
                            });

                            // dl.addLine(.{
                            //     .p1 = .{ .x = header_min.x - (node_padding[0]), .y = header_max.y + node_padding[0] / 2 },
                            //     .p2 = .{ .x = header_max.x + (node_padding[1]), .y = header_max.y + node_padding[1] / 2 },
                            //     .col = .fromColor4f(ne_style.getColor(.node_border)),
                            //     .thickness = 2,
                            // });
                        }
                    }

                    const dl = coreui.getWindowDrawList();

                    const node_type_hash = graphvm.NodeTypeCdb.f.getNodeTypeId(node_r);
                    if (graphvm.findNodeI(node_type_hash)) |node_i| {
                        if (coreui.beginTable("table", .{
                            .column = 1,
                            .outer_size = .{ .x = width },
                            .flags = .{
                                // .borders = .{
                                //     .outer_v = true,
                                //     .outer_h = true,
                                // },

                                .no_saved_settings = true,
                                .resizable = false,
                                .no_clip = true,
                                .sizing = .stretch_prop,
                                // .no_host_extend_x = true,
                            },
                        })) {
                            defer coreui.endTable();

                            //
                            // Header
                            //
                            {
                                coreui.pushStyleVar2f(.{ .idx = .cell_padding, .v = .{} });
                                coreui.pushStyleVar2f(.{ .idx = .frame_padding, .v = .{} });
                                defer coreui.popStyleVar(.{ .count = 2 });

                                _ = coreui.tableNextColumn();
                                var node_title: [:0]const u8 = undefined;
                                defer allocator.free(node_title);
                                if (node_i.title) |title_fce| {
                                    node_title = try title_fce(node_i, allocator, node);
                                } else {
                                    node_title = try allocator.dupeZ(u8, node_i.name);
                                }

                                var icon_buf: [16:0]u8 = undefined;
                                var node_icon: [:0]const u8 = undefined;

                                if (node_i.icon) |icon_fce| {
                                    node_icon = try icon_fce(node_i, &icon_buf, allocator, node);
                                } else {
                                    node_icon = try std.fmt.bufPrintZ(&icon_buf, "{s}", .{coreui.Icons.Node});
                                }
                                coreui.alignTextToFramePadding();
                                coreui.text(try std.fmt.bufPrintZ(&buf, "{s}  {s}", .{ node_icon, node_title }));

                                header_min = coreui.getItemRectMin();
                                header_max = .{ .x = header_min.x + width, .y = coreui.getItemRectMax().y }; //coreui.getItemRectMax();
                                // header_max = coreui.getItemRectMax();
                            }

                            //
                            // Outputs
                            //
                            var pin_def = try node_i.getPinsDef(node_i, allocator, graph_obj, node);
                            defer pin_def.deinit(allocator);

                            for (pin_def.out) |output| {
                                _ = coreui.tableNextColumn();

                                const resolved_type = tab_o.resolved_pintype_map.get(.{ node, output.pin_hash }) orelse output.pin_hash;
                                const color = graphvm.getTypeColor(resolved_type);

                                const txt_size = coreui.calcTextSize(output.name, .{});

                                node_editor.pushStyleVar2f(.pivot_alignment, .{ .x = 1 - pin_size / 2 * (1 / (pin_size + txt_size.x + coreui.getStyle().frame_padding.x * 2)), .y = 0.5 });
                                defer node_editor.popStyleVar(1);

                                const max_x = width;
                                coreui.setCursorPosX(coreui.getCursorPosX() + (max_x - txt_size.x - pin_size));

                                try tab_o.pinhash_map.put(_allocator, .{ node, output.pin_hash }, output.pin_name);
                                const pinid = PinId.init(node, output.pin_hash).toU64();
                                node_editor.beginPin(pinid, .Output);
                                {
                                    defer node_editor.endPin();

                                    coreui.text(output.name);
                                    coreui.sameLine(.{ .spacing = 0 });

                                    const cpos = coreui.getCursorScreenPos();

                                    const connected = node_editor.pinHadAnyLinks(pinid);
                                    try drawIcon(
                                        dl,
                                        .Circle,
                                        cpos.add(.{ .x = pin_size / 2, .y = pin_size / 2 }),
                                        .{ .x = pin_size, .y = pin_size },
                                        connected,
                                        color,
                                    );
                                    coreui.dummy(.{ .w = pin_size, .h = pin_size });
                                }
                            }

                            //
                            // Settings
                            //
                            if (false) {
                                if (!node_i.type_hash.eql(graphvm.CALL_GRAPH_NODE_TYPE)) {
                                    if (graphvm.NodeTypeCdb.readSubObj(node_r, .settings)) |setting_obj| {
                                        coreui.pushObjUUID(node);
                                        defer coreui.popId();

                                        try editor_inspector.cdbPropertiesView(
                                            allocator,
                                            tab_o,
                                            tab_o.selection.top_level_obj,
                                            setting_obj,
                                            0,
                                            .{
                                                .hide_proto = true,
                                                .max_autopen_depth = 0,
                                                .flat = true,
                                            },
                                        );
                                    }
                                }
                            }

                            //
                            // Inputs
                            //
                            for (pin_def.in) |input| {
                                _ = coreui.tableNextColumn();

                                const resolved_type = tab_o.resolved_pintype_map.get(.{ node, input.pin_hash }) orelse input.pin_hash;
                                const color = graphvm.getTypeColor(resolved_type);

                                const txt_w = coreui.calcTextSize(input.name, .{}).x;

                                node_editor.pushStyleVar2f(.pivot_alignment, .{ .x = pin_size / 2 * (1 / (pin_size + txt_w + coreui.getStyle().frame_padding.x * 2)), .y = 0.5 });
                                defer node_editor.popStyleVar(1);

                                const pin_k = .{ node, input.pin_hash };
                                const data = tab_o.pindata_map.get(pin_k);
                                const data_connected = data != null;

                                try tab_o.pinhash_map.put(_allocator, pin_k, input.pin_name);
                                try tab_o.pintype_map.put(_allocator, pin_k, input.type_hash);

                                const pinid = PinId.init(node, input.pin_hash).toU64();

                                var pin_connected = false;

                                node_editor.beginPin(pinid, .Input);
                                {
                                    defer node_editor.endPin();
                                    pin_connected = node_editor.pinHadAnyLinks(pinid);

                                    const cpos = coreui.getCursorScreenPos();
                                    const connected = pin_connected or data_connected;
                                    try drawIcon(
                                        dl,
                                        .Circle,
                                        cpos.add(.{ .x = pin_size / 2, .y = pin_size / 2 }),
                                        .{ .x = pin_size, .y = pin_size },
                                        connected,
                                        color,
                                    );
                                    coreui.dummy(.{ .w = pin_size, .h = pin_size });
                                    coreui.sameLine(.{ .spacing = 0 });
                                    coreui.text(input.name);
                                }

                                if (!pin_connected and data_connected) {
                                    const data_r = graphvm.GraphDataTypeCdb.read(data.?).?;

                                    if (graphvm.GraphDataTypeCdb.readSubObj(data_r, .value)) |value_obj| {
                                        const value_i = graphvm.findValueTypeIByCdb(cdb.getTypeHash(tab_o.db, value_obj.type_idx).?).?;

                                        const one_value = cdb.getTypePropDef(tab_o.db, cdb.getTypeIdx(tab_o.db, value_i.cdb_type_hash).?).?.len == 1;

                                        try editor_inspector.cdbPropertiesView(
                                            allocator,
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
                        coreui.text("INVALID NODE TYPE HASH");
                    }
                }
            }

            //Groups
            if (try graphvm.GraphTypeCdb.readSubObjSet(graph_r, .groups, allocator)) |groups| {
                defer allocator.free(groups);

                for (groups) |group| {
                    const group_r = cdb.readObj(group).?;

                    if (new_graph) {
                        const node_pos_x = graphvm.GroupTypeCdb.readValue(f32, group_r, .pos_x);
                        const node_pos_y = graphvm.GroupTypeCdb.readValue(f32, group_r, .pos_y);
                        node_editor.setNodePosition(group.toU64(), .{
                            .x = node_pos_x,
                            .y = node_pos_y,
                        });
                    }

                    const node_size_x = graphvm.GroupTypeCdb.readValue(f32, group_r, .size_x);
                    const node_size_y = graphvm.GroupTypeCdb.readValue(f32, group_r, .size_y);

                    const group_title = graphvm.GroupTypeCdb.readStr(group_r, .title) orelse "NO TITLE";

                    var color: math.Color4f = if (graphvm.GroupTypeCdb.readSubObj(group_r, .color)) |color_obj| cdb_types.Color4fCdb.f.to(color_obj) else .{ .r = 1, .g = 1, .b = 1, .a = 0.4 };
                    color.a = 0.4;

                    node_editor.pushStyleColor(.node_bg, color);
                    defer node_editor.popStyleColor(1);

                    node_editor.beginNode(group.toU64());
                    coreui.text(group_title);
                    node_editor.group(.{ .x = node_size_x, .y = node_size_y });
                    defer node_editor.endNode();
                }
            }

            // Connections
            if (all_connections) |connections| {
                for (connections) |connect| {
                    const node_r = cdb.readObj(connect).?;

                    const from_node = graphvm.ConnectionTypeCdb.readRef(node_r, .from_node) orelse cdb.ObjId{};
                    const from_pin = graphvm.ConnectionTypeCdb.f.getFromPinId(node_r);

                    const to_node = graphvm.ConnectionTypeCdb.readRef(node_r, .to_node) orelse cdb.ObjId{};
                    const to_pin = graphvm.ConnectionTypeCdb.f.getToPinId(node_r);

                    const from_pin_id = PinId.init(from_node, from_pin).toU64();
                    const to_pin_id = PinId.init(to_node, to_pin).toU64();

                    var type_color: math.Color4f = .white;

                    //TODO: inform user about invalid connection
                    if (cdb.readObj(from_node)) |from_node_obj_r| {
                        const from_node_type = graphvm.NodeTypeCdb.f.getNodeTypeId(from_node_obj_r);
                        const out_pin = (try graphvm.getOutputPin(allocator, tab_o.root_graph_obj, from_node, from_node_type, from_pin)) orelse continue;

                        const resolved_type = tab_o.resolved_pintype_map.get(.{ from_node, from_pin }) orelse out_pin.type_hash;
                        type_color = graphvm.getTypeColor(resolved_type);
                    }

                    node_editor.link(connect.toU64(), from_pin_id, to_pin_id, type_color, 3);
                }
            }

            if (new_graph) {
                node_editor.navigateToContent(-1);
            }

            // Context menu
            const popup_pos = coreui.getMousePos();

            node_editor.suspend_();
            {
                defer node_editor.resume_();
                if (node_editor.showBackgroundContextMenu()) {
                    coreui.openPopup("ui_graph_background_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (node_editor.showNodeContextMenu(&tab_o.ctxNodeId)) {
                    coreui.openPopup("ui_graph_node_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (node_editor.showLinkContextMenu(&tab_o.ctxLinkId)) {
                    coreui.openPopup("ui_graph_link_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (node_editor.showPinContextMenu(&tab_o.ctxPinId)) {
                    coreui.openPopup("ui_graph_pin_context_menu", .{});
                    tab_o.ctxPos = popup_pos;
                }

                if (coreui.beginPopup("ui_graph_background_context_menu", .{})) {
                    defer coreui.endPopup();

                    tab_o.filter = coreui.uiFilter(&tab_o.filter_buff, tab_o.filter);

                    const impls = try apidb.getImpl(allocator, graphvm.NodeI);
                    defer allocator.free(impls);

                    var node_without_category = cetech1.ArrayList(*const graphvm.NodeI).empty;
                    defer node_without_category.deinit(allocator);

                    std.sort.insertion(*const graphvm.NodeI, impls, allocator, lessThanNodePath);

                    if (tab_o.filter) |filter| {
                        for (impls) |iface| {
                            var icon_buf: [16:0]u8 = undefined;
                            var node_icon: [:0]const u8 = undefined;

                            if (iface.icon) |icon_fce| {
                                node_icon = try icon_fce(iface, &icon_buf, allocator, .{});
                            } else {
                                node_icon = try std.fmt.bufPrintZ(&icon_buf, "{s}", .{coreui.Icons.Node});
                            }

                            const name = try std.fmt.bufPrintZ(
                                &buf,
                                "{s}  {s}{s}{s}###{s}",
                                .{
                                    node_icon,
                                    if (iface.category) |c| c else "",
                                    if (iface.category == null) "" else "/",
                                    iface.name,
                                    iface.type_name,
                                },
                            );
                            if (coreui.menuItem(_allocator, name, .{}, filter)) {
                                const node_obj = try graphvm.createCdbNode(tab_o.db, iface.type_hash, tab_o.ctxPos);

                                const node_w = cdb.writeObj(node_obj).?;

                                const graph_w = cdb.writeObj(graph_obj).?;
                                try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .nodes, &.{node_w});

                                try cdb.writeCommit(node_w);
                                try cdb.writeCommit(graph_w);

                                node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                            }
                        }
                    } else {
                        // Create category menu first
                        {
                            for (impls) |iface| {
                                var count: usize = 0;
                                var open = false;

                                if (iface.category) |category| {
                                    var split_bw = std.mem.splitBackwardsAny(u8, category, "/");

                                    var split = std.mem.splitAny(u8, split_bw.rest(), "/");
                                    const first = split.first();

                                    var it: ?[]const u8 = first;

                                    while (it) |word| : (it = split.next()) {
                                        const lbl = try std.fmt.bufPrintZ(&buf, "{s}  {s}###{s}", .{ coreui.Icons.Folder, word, word });

                                        open = coreui.beginMenu(_allocator, lbl, true, null);
                                        if (!open) break;
                                        count += 1;
                                    }
                                }

                                for (0..count) |_| {
                                    coreui.endMenu();
                                }
                            }
                        }

                        for (impls) |iface| {
                            var open_category = false;
                            var count: usize = 0;

                            // prepeare prepared category
                            if (iface.category) |category| {
                                var split_bw = std.mem.splitBackwardsAny(u8, category, "/");

                                var split = std.mem.splitAny(u8, split_bw.rest(), "/");
                                const first = split.first();

                                var it: ?[]const u8 = first;

                                while (it) |word| : (it = split.next()) {
                                    const lbl = try std.fmt.bufPrintZ(&buf, "###{s}", .{word});

                                    open_category = coreui.beginMenu(_allocator, lbl, true, null);
                                    if (!open_category) break;
                                    count += 1;
                                }
                            } else {
                                try node_without_category.append(allocator, iface);
                                continue;
                            }

                            if (open_category) {
                                var icon_buf: [16:0]u8 = undefined;
                                var node_icon: [:0]const u8 = undefined;

                                if (iface.icon) |icon_fce| {
                                    node_icon = try icon_fce(iface, &icon_buf, allocator, .{});
                                } else {
                                    node_icon = try std.fmt.bufPrintZ(&icon_buf, "{s}", .{coreui.Icons.Node});
                                }

                                const name = try std.fmt.bufPrintZ(&buf, "{s}  {s}###{s}", .{ node_icon, iface.name, iface.type_name });
                                if (coreui.menuItem(_allocator, name, .{}, tab_o.filter)) {
                                    const node_obj = try graphvm.createCdbNode(tab_o.db, iface.type_hash, tab_o.ctxPos);

                                    const node_w = cdb.writeObj(node_obj).?;

                                    const graph_w = cdb.writeObj(graph_obj).?;
                                    try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .nodes, &.{node_w});

                                    try cdb.writeCommit(node_w);
                                    try cdb.writeCommit(graph_w);

                                    node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                                }
                            }

                            for (0..count) |_| {
                                coreui.endMenu();
                            }
                        }

                        if (coreui.menuItem(_allocator, coreui.Icons.Group ++ " " ++ "Group", .{}, tab_o.filter)) {
                            const node_obj = try graphvm.GroupTypeCdb.createObject(tab_o.db);

                            const node_w = cdb.writeObj(node_obj).?;

                            try graphvm.GroupTypeCdb.setStr(node_w, .title, "Group");

                            graphvm.GroupTypeCdb.setValue(f32, node_w, .pos_x, tab_o.ctxPos.x);
                            graphvm.GroupTypeCdb.setValue(f32, node_w, .pos_x, tab_o.ctxPos.y);

                            graphvm.GroupTypeCdb.setValue(f32, node_w, .size_x, 50);
                            graphvm.GroupTypeCdb.setValue(f32, node_w, .size_y, 50);

                            const graph_w = cdb.writeObj(graph_obj).?;
                            try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .groups, &.{node_w});

                            try cdb.writeCommit(node_w);
                            try cdb.writeCommit(graph_w);

                            node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                        }

                        for (node_without_category.items) |iface| {
                            var icon_buf: [16:0]u8 = undefined;
                            var node_icon: [:0]const u8 = undefined;

                            if (iface.icon) |icon_fce| {
                                node_icon = try icon_fce(iface, &icon_buf, allocator, .{});
                            } else {
                                node_icon = try std.fmt.bufPrintZ(&icon_buf, "{s}", .{coreui.Icons.Node});
                            }

                            const name = try std.fmt.bufPrintZ(&buf, "{s}  {s}###{s}", .{ node_icon, iface.name, iface.type_name });
                            if (coreui.menuItem(_allocator, name, .{}, tab_o.filter)) {
                                const node_obj = try graphvm.createCdbNode(tab_o.db, iface.type_hash, tab_o.ctxPos);

                                const node_w = cdb.writeObj(node_obj).?;

                                const graph_w = cdb.writeObj(graph_obj).?;
                                try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .nodes, &.{node_w});

                                try cdb.writeCommit(node_w);
                                try cdb.writeCommit(graph_w);

                                node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                            }
                        }
                    }
                }

                // Node or Group
                if (coreui.beginPopup("ui_graph_node_context_menu", .{})) {
                    defer coreui.endPopup();

                    const node_obj = cdb.ObjId.fromU64(tab_o.ctxNodeId);
                    const enabled = cdb.isChildOff(tab_o.selection.top_level_obj, node_obj);

                    if (node_obj.type_idx.eql(NodeTypeIdx)) {
                        const node_obj_r = graphvm.NodeTypeCdb.read(node_obj).?;
                        const node_type = graphvm.NodeTypeCdb.f.getNodeTypeId(node_obj_r);

                        if (graphvm.NodeTypeCdb.readSubObj(node_obj_r, .settings)) |settings| {
                            const settings_r = graphvm.CallGraphNodeSettingsCdb.read(settings).?;

                            if (node_type.eql(graphvm.CALL_GRAPH_NODE_TYPE)) {
                                if (graphvm.CallGraphNodeSettingsCdb.readSubObj(settings_r, .graph)) |graph| {
                                    if (coreui.menuItem(_allocator, coreui.Icons.Open ++ "  " ++ "Open subgraph", .{}, null)) {
                                        try editor_obj_buffer.addToFirst(allocator, tab_o.db, .{ .top_level_obj = tab_o.selection.top_level_obj, .obj = graph });
                                        try tab_o.breadcrumb.append(_allocator, graph);
                                    }
                                }
                            } else {
                                if (true) {
                                    coreui.pushObjUUID(node_obj);
                                    defer coreui.popId();

                                    try editor_inspector.cdbPropertiesView(
                                        allocator,
                                        tab_o,
                                        tab_o.selection.top_level_obj,
                                        settings,
                                        0,
                                        .{
                                            .hide_proto = true,
                                            .max_autopen_depth = 0,
                                            .flat = true,
                                        },
                                    );
                                    coreui.separator();
                                }
                            }
                        }
                    }

                    if (coreui.menuItem(_allocator, coreui.Icons.Delete ++ "  " ++ "Delete node", .{ .enabled = enabled }, null)) {
                        _ = node_editor.deleteNode(tab_o.ctxNodeId);
                    }
                }

                // Link
                if (coreui.beginPopup("ui_graph_link_context_menu", .{})) {
                    defer coreui.endPopup();

                    if (coreui.menuItem(_allocator, coreui.Icons.Delete ++ "  " ++ "Delete link", .{}, null)) {
                        _ = node_editor.deleteLink(tab_o.ctxLinkId);
                    }
                }

                // Pin
                if (coreui.beginPopup("ui_graph_pin_context_menu", .{})) {
                    defer coreui.endPopup();
                    const pin_connected = node_editor.pinHadAnyLinks(tab_o.ctxPinId);

                    const pin_id = PinId.fromU64(tab_o.ctxPinId);
                    const node_obj = pin_id.getObj(tab_o.db);
                    const pin_hash = pin_id.getPinHash();
                    const pin_k = .{ node_obj, pin_hash };

                    const from_node_obj_r = cdb.readObj(node_obj).?;
                    const from_node_type = graphvm.NodeTypeCdb.f.getNodeTypeId(from_node_obj_r);

                    const is_output = try graphvm.isOutputPin(allocator, tab_o.root_graph_obj, node_obj, from_node_type, pin_hash);

                    const enabled = cdb.isChildOff(tab_o.selection.top_level_obj, node_obj);

                    if (pin_connected) {
                        if (coreui.menuItem(_allocator, "Break all links", .{}, null)) {
                            _ = node_editor.breakPinLinks(tab_o.ctxPinId);
                        }
                    } else if (!is_output) {
                        const pin_type = tab_o.pintype_map.get(pin_k).?;
                        const generic_pin_type = graphvm.PinTypes.GENERIC.eql(pin_type);

                        const data = tab_o.pindata_map.get(pin_k);

                        if (data) |d| {
                            if (coreui.menuItem(_allocator, "Delete data", .{ .enabled = enabled }, null)) {
                                cdb.destroyObject(d);
                                _ = tab_o.pindata_map.remove(pin_k);
                            }
                        } else {
                            if (generic_pin_type) {
                                if (coreui.beginMenu(_allocator, "Add value", enabled, null)) {
                                    defer coreui.endMenu();

                                    const impls = try apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                                    defer allocator.free(impls);
                                    for (impls) |iface| {
                                        if (iface.cdb_type_hash.isEmpty()) continue;
                                        if (iface.type_hash.eql(graphvm.PinTypes.Flow)) continue;

                                        if (coreui.menuItem(allocator, iface.name, .{}, null)) {
                                            const data_obj = try graphvm.GraphDataTypeCdb.createObject(tab_o.db);
                                            const data_w = graphvm.GraphDataTypeCdb.write(data_obj).?;

                                            try graphvm.GraphDataTypeCdb.setRef(data_w, .to_node, node_obj);

                                            const pin_name = tab_o.pinhash_map.get(pin_k).?;
                                            try graphvm.GraphDataTypeCdb.setStr(data_w, .to_node_pin, pin_name);

                                            const value_obj = try cdb.createObject(tab_o.db, cdb.getTypeIdx(tab_o.db, iface.cdb_type_hash).?);
                                            const value_w = cdb.writeObj(value_obj).?;

                                            try graphvm.GraphDataTypeCdb.setSubObj(data_w, .value, value_w);

                                            const graph_w = graphvm.GraphTypeCdb.write(graph_obj).?;
                                            try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .data, &.{data_w});

                                            try cdb.writeCommit(value_w);
                                            try cdb.writeCommit(data_w);
                                            try cdb.writeCommit(graph_w);

                                            try tab_o.pindata_map.put(_allocator, pin_k, data_obj);
                                        }
                                    }
                                }
                            } else if (!pin_type.eql(graphvm.PinTypes.Flow)) {
                                const type_i = graphvm.findValueTypeI(pin_type).?;

                                const label = try std.fmt.bufPrintZ(&buf, "Set value ({s})", .{type_i.name});
                                if (coreui.menuItem(_allocator, label, .{ .enabled = enabled }, null)) {
                                    const data_obj = try graphvm.GraphDataTypeCdb.createObject(tab_o.db);
                                    const data_w = graphvm.GraphDataTypeCdb.write(data_obj).?;

                                    try graphvm.GraphDataTypeCdb.setRef(data_w, .to_node, node_obj);

                                    const pin_name = tab_o.pinhash_map.get(pin_k).?;
                                    try graphvm.GraphDataTypeCdb.setStr(data_w, .to_node_pin, pin_name);

                                    const value_obj = try cdb.createObject(tab_o.db, cdb.getTypeIdx(tab_o.db, type_i.cdb_type_hash).?);
                                    const value_w = cdb.writeObj(value_obj).?;

                                    try graphvm.GraphDataTypeCdb.setSubObj(data_w, .value, value_w);

                                    const graph_w = graphvm.GraphTypeCdb.write(graph_obj).?;
                                    try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .data, &.{data_w});

                                    try cdb.writeCommit(value_w);
                                    try cdb.writeCommit(data_w);
                                    try cdb.writeCommit(graph_w);

                                    try tab_o.pindata_map.put(_allocator, pin_k, data_obj);
                                }
                            }
                        }
                    }
                }
            }

            // Created
            if (node_editor.beginCreate()) {
                var ne_form_id: ?node_editor.PinId = null;
                var ne_to_id: ?node_editor.PinId = null;
                if (node_editor.queryNewLink(&ne_form_id, &ne_to_id)) {
                    if (ne_form_id != null and ne_to_id != null) {
                        var from_id = PinId.fromU64(ne_form_id.?);
                        var from_node_obj = from_id.getObj(tab_o.db);
                        const from_node_obj_r = cdb.readObj(from_node_obj).?;
                        var from_node_type = graphvm.NodeTypeCdb.f.getNodeTypeId(from_node_obj_r);

                        var to_id = PinId.fromU64(ne_to_id.?);
                        var to_node_obj = to_id.getObj(tab_o.db);
                        const to_node_obj_r = cdb.readObj(to_node_obj).?;
                        var to_node_type = graphvm.NodeTypeCdb.f.getNodeTypeId(to_node_obj_r);

                        // If drag node from input to output swap it
                        // Allways OUT => IN semantic.
                        if (try graphvm.isInputPin(allocator, tab_o.root_graph_obj, from_node_obj, from_node_type, .{ .id = from_id.pin_hash })) {
                            std.mem.swap(PinId, &from_id, &to_id);
                            std.mem.swap(cdb.ObjId, &from_node_obj, &to_node_obj);
                            std.mem.swap(cetech1.StrId32, &from_node_type, &to_node_type);
                            std.mem.swap(?node_editor.PinId, &ne_form_id, &ne_to_id);
                        }

                        const is_input = try graphvm.isInputPin(allocator, tab_o.root_graph_obj, to_node_obj, to_node_type, .{ .id = to_id.pin_hash });
                        const is_output = try graphvm.isOutputPin(allocator, tab_o.root_graph_obj, from_node_obj, from_node_type, .{ .id = from_id.pin_hash });

                        if (ne_form_id.? == ne_to_id.?) {
                            node_editor.rejectNewItem(.red, 3);
                        } else if (!is_input or !is_output) {
                            node_editor.rejectNewItem(.red, 3);
                        } else if (from_node_obj.eql(to_node_obj)) {
                            node_editor.rejectNewItem(.red, 3);
                        } else {
                            const output_pin_def = (try graphvm.getOutputPin(allocator, tab_o.root_graph_obj, from_node_obj, from_node_type, .{ .id = from_id.pin_hash })).?;
                            const input_pin_def = (try graphvm.getInputPin(allocator, tab_o.root_graph_obj, to_node_obj, to_node_type, .{ .id = to_id.pin_hash })).?;

                            const resolved_output = tab_o.resolved_pintype_map.get(.{ from_node_obj, .{ .id = from_id.pin_hash } }) orelse output_pin_def.type_hash;
                            const resolved_input = tab_o.resolved_pintype_map.get(.{ to_node_obj, .{ .id = to_id.pin_hash } }) orelse input_pin_def.type_hash;

                            const type_color = graphvm.getTypeColor(resolved_output);

                            // Type check
                            if (!input_pin_def.type_hash.eql(graphvm.PinTypes.GENERIC) and !resolved_input.eql(resolved_output)) {
                                node_editor.rejectNewItem(.red, 3);
                            } else if (node_editor.acceptNewItem(type_color, 3)) {
                                if (node_editor.pinHadAnyLinks(ne_to_id.?)) {
                                    _ = node_editor.breakPinLinks(ne_to_id.?);
                                }

                                const connection_obj = try graphvm.ConnectionTypeCdb.createObject(tab_o.db);
                                const connection_w = cdb.writeObj(connection_obj).?;

                                try graphvm.ConnectionTypeCdb.setRef(connection_w, .from_node, from_node_obj);
                                const from_pin_str = tab_o.pinhash_map.get(.{ from_node_obj, .{ .id = from_id.pin_hash } }).?;
                                try graphvm.ConnectionTypeCdb.setStr(connection_w, .from_pin, from_pin_str);

                                try graphvm.ConnectionTypeCdb.setRef(connection_w, .to_node, to_node_obj);
                                const to_pin_str = tab_o.pinhash_map.get(.{ to_node_obj, .{ .id = to_id.pin_hash } }).?;
                                try graphvm.ConnectionTypeCdb.setStr(connection_w, .to_pin, to_pin_str);

                                const graph_w = cdb.writeObj(graph_obj).?;
                                try graphvm.GraphTypeCdb.addSubObjToSet(graph_w, .connections, &.{connection_w});

                                try cdb.writeCommit(connection_w);
                                try cdb.writeCommit(graph_w);
                            }
                        }
                    }
                }
            }
            node_editor.endCreate();

            // Deleted
            if (node_editor.beginDelete()) {
                var node_id: node_editor.NodeId = 0;
                while (node_editor.queryDeletedNode(&node_id)) {
                    if (node_editor.acceptDeletedItem(true)) {
                        const node_obj = cdb.ObjId.fromU64(node_id);
                        cdb.destroyObject(node_obj);

                        var it = tab_o.pindata_map.iterator();
                        while (it.next()) |e| {
                            const k = e.key_ptr.*;
                            if (!k[0].eql(node_obj)) continue;

                            const v = e.value_ptr.*;
                            cdb.destroyObject(v);
                        }
                    }
                }

                var link_id: node_editor.LinkId = 0;
                while (node_editor.queryDeletedLink(&link_id, null, null)) {
                    if (node_editor.acceptDeletedItem(true)) {
                        const link_obj = cdb.ObjId.fromU64(link_id);
                        cdb.destroyObject(link_obj);
                    }
                }
            }
            node_editor.endDelete();
        }

        // Selection handling
        if (node_editor.hasSelectionChanged()) {
            const selected_object_n = node_editor.getSelectedObjectCount();
            if (selected_object_n != 0) {
                const selected_nodes = try allocator.alloc(node_editor.NodeId, @intCast(selected_object_n));

                var items = try cetech1.ArrayList(coreui.SelectedObj).initCapacity(allocator, @intCast(selected_object_n));
                defer items.deinit(allocator);
                // Nodes
                {
                    const nodes_n = node_editor.getSelectedNodes(selected_nodes);
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
                                .prop_idx = graphvm.GraphTypeCdb.propIdx(.nodes),
                            });
                        } else if (obj.type_idx.eql(GroupTypeIdx)) {
                            items.appendAssumeCapacity(.{
                                .top_level_obj = tab_o.selection.top_level_obj,
                                .obj = obj,
                                .in_set_obj = obj,
                                .parent_obj = tab_o.root_graph_obj,
                                .prop_idx = graphvm.GraphTypeCdb.propIdx(.groups),
                            });
                        }
                    }
                }

                //Links
                {
                    const nodes_n = node_editor.getSelectedLinks(selected_nodes);

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
                                .prop_idx = graphvm.GraphTypeCdb.propIdx(.connections),
                            });
                        }
                    }
                }

                const objs = try items.toOwnedSlice(allocator);
                try tab_o.inter_selection.set(objs);
                editor_tabs.propagateSelection(inst, objs);
            } else {
                try tab_o.inter_selection.set(&.{tab_o.selection});
                editor_tabs.propagateSelection(inst, &.{tab_o.selection});
            }
        }

        node_editor.setCurrentEditor(null);
    }

    // Draw tab menu
    pub fn menu(inst: *editor_tabs.TabO) !void {
        const tab_o: *GraphEditorTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (coreui.menuItem(_allocator, coreui.Icons.FitContent ++ "###FitAll", .{}, null)) {
            node_editor.setCurrentEditor(tab_o.editor);
            defer node_editor.setCurrentEditor(null);

            node_editor.navigateToContent(-1);
        }

        if (coreui.menuItem(_allocator, coreui.Icons.FitContent ++ "###FitSelection", .{}, null)) {
            node_editor.setCurrentEditor(tab_o.editor);
            defer node_editor.setCurrentEditor(null);

            node_editor.navigateToSelection(false, -1);
        }

        const need_build = graphvm.needCompileAny();
        if (coreui.menuItem(_allocator, coreui.Icons.Build, .{ .enabled = need_build }, null)) {
            try graphvm.compileAllChanged(allocator);
        }

        if (true) {
            coreui.separator();
            coreui.sameLine(.{});

            for (tab_o.breadcrumb.items, 0..) |value, idx| {
                //const value = tab_o.breadcrumb.items[output.items.len - idx - 1];
                const asset = assetdb.getAssetForObj(value);
                //const asset_or_obj = asset orelse value;

                const uuid = try cdb.getOrCreateUuid(value);

                const name = blk: {
                    const graph_r = cdb.readObj(value).?;

                    if (graphvm.GraphTypeCdb.readStr(graph_r, .name)) |n| {
                        break :blk n;
                    }

                    if (asset) |a| {
                        const a_r = cdb.readObj(a).?;

                        if (assetdb.AssetCdb.readStr(a_r, .Name)) |n| {
                            break :blk n;
                        }
                    }

                    break :blk "Subgraph";
                };
                const label = try std.fmt.allocPrintSentinel(allocator, "{s}###{f}", .{ name, uuid }, 0);
                defer allocator.free(label);

                if (coreui.button(label, .{})) {
                    editor_tabs.propagateSelection(
                        inst,
                        &.{
                            .{ .top_level_obj = tab_o.selection.top_level_obj, .obj = value },
                        },
                    );
                    const value_idx = std.mem.indexOf(cdb.ObjId, tab_o.breadcrumb.items, &.{value}).?;
                    tab_o.breadcrumb.shrinkRetainingCapacity(value_idx + 1);
                }

                if (idx != tab_o.breadcrumb.items.len - 1) {
                    coreui.sameLine(.{});
                    coreui.text(coreui.Icons.ChevronRight);
                    coreui.sameLine(.{});
                }
            }
        }
    }

    pub fn focused(inst: *editor_tabs.TabO) !void {
        const tab_o: *GraphEditorTab = @ptrCast(@alignCast(inst));

        const allocator = try tempalloc.create();
        defer tempalloc.destroy(allocator);

        if (!tab_o.inter_selection.isEmpty()) {
            if (tab_o.inter_selection.toSlice(allocator)) |objs| {
                defer allocator.free(objs);
                editor_tabs.propagateSelection(inst, objs);
            }
        } else if (!tab_o.selection.isEmpty()) {
            editor_tabs.propagateSelection(inst, &.{tab_o.selection});
        }
    }

    // Selected object
    pub fn objSelected(inst: *editor_tabs.TabO, selection: []const coreui.SelectedObj, sender_tab_hash: ?cetech1.StrId32) !void {
        _ = sender_tab_hash;
        var tab_o: *GraphEditorTab = @ptrCast(@alignCast(inst));

        if (tab_o.inter_selection.isSelectedAll(selection)) return;

        const selected = selection[0];
        if (selected.isEmpty()) return;
        const db = cdb.getDbFromObjid(selected.obj);

        if (selected.top_level_obj != tab_o.selection.top_level_obj) {
            tab_o.breadcrumb.clearRetainingCapacity();
        }

        if (assetdb.isAssetObjTypeOf(selected.obj, graphvm.GraphTypeCdb.typeIdx(db))) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(GraphTypeIdx)) {
            tab_o.selection = selected;
        } else if (selected.obj.type_idx.eql(NodeTypeIdx) or selected.obj.type_idx.eql(GroupTypeIdx)) {
            node_editor.setCurrentEditor(tab_o.editor);
            defer node_editor.setCurrentEditor(null);
            node_editor.selectNode(selected.obj.toU64(), false);
            node_editor.navigateToSelection(selected.obj.type_idx.eql(graphvm.GroupTypeCdb.typeIdx(db)), -1);
        } else if (selected.obj.type_idx.eql(ConnectionTypeIdx)) {
            node_editor.setCurrentEditor(tab_o.editor);
            defer node_editor.setCurrentEditor(null);
            node_editor.selectLink(selected.obj.toU64(), false);
            node_editor.navigateToSelection(false, -1);
        }
    }
});

// Create graph asset
var create_graph_i = editor_assetdb.CreateAssetI.implement(
    graphvm.GraphTypeCdb.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                cdb.getTypeIdx(db, graphvm.GraphTypeCdb.type_hash).?,
                "NewGraph",
            );

            const new_obj = try graphvm.GraphTypeCdb.createObject(db);

            _ = assetdb.createAsset(name, folder, new_obj);
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
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        _ = obj;

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Graph});
    }
});

var node_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;

        const node_type_hash = graphvm.NodeTypeCdb.f.getNodeTypeId(obj_r);
        if (graphvm.findNodeI(node_type_hash)) |node_i| {
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
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const db = cdb.getDbFromObjid(obj);
        _ = db;

        const obj_r = cdb.readObj(obj).?;

        const node_type_hash = graphvm.NodeTypeCdb.f.getNodeTypeId(obj_r);
        if (graphvm.findNodeI(node_type_hash)) |node_i| {
            if (node_i.icon) |icon| {
                return icon(node_i, buff, allocator, obj);
            }
        }

        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Node});
    }
});

var group_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;

        if (graphvm.GroupTypeCdb.readStr(obj_r, .title)) |tile| {
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
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        _ = obj;
        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Group});
    }

    pub fn uiColor(
        obj: cdb.ObjId,
    ) !math.Color4f {
        const obj_r = cdb.readObj(obj).?;
        const color = graphvm.GroupTypeCdb.readSubObj(obj_r, .color) orelse return .white;
        return cetech1.cdb_types.Color4fCdb.f.to(color);
    }
});

var interface_input_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;

        if (graphvm.InterfaceInputCdb.readStr(obj_r, .name)) |tile| {
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
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        const obj_r = cdb.readObj(obj).?;

        if (graphvm.InterfaceOutputCdb.readStr(obj_r, .name)) |tile| {
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
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        _ = obj;
        return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Link});
    }
});

const node_prop_aspect = editor_inspector.UiInspectorObjAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        const node_r = graphvm.NodeTypeCdb.read(obj).?;

        if (graphvm.NodeTypeCdb.readSubObj(node_r, .settings)) |setting_obj| {
            try editor_inspector.cdbPropertiesObj(allocator, tab, top_level_obj, setting_obj, depth, args);
        }
    }
});

// TODO: generic/join variable menu
const input_variable_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx;
        _ = filter;

        const db = cdb.getDbFromObjid(obj);
        const subobj = graphvm.InterfaceInputCdb.readSubObj(graphvm.InterfaceInputCdb.read(obj).?, .value);

        if (subobj) |value_obj| {
            if (coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                cdb.destroyObject(value_obj);
            }
        } else {
            if (coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer coreui.endMenu();

                const impls = try apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.InterfaceInputCdb.write(obj).?;

                        const value_obj = try cdb.createObject(db, cdb.getTypeIdx(db, iface.cdb_type_hash).?);
                        const value_obj_w = cdb.writeObj(value_obj).?;

                        try graphvm.InterfaceInputCdb.setSubObj(obj_w, .value, value_obj_w);

                        try cdb.writeCommit(value_obj_w);
                        try cdb.writeCommit(obj_w);
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
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx;
        _ = filter;

        const db = cdb.getDbFromObjid(obj);
        const subobj = graphvm.InterfaceInputCdb.readSubObj(graphvm.InterfaceInputCdb.read(obj).?, .value);

        if (subobj) |value_obj| {
            if (coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                cdb.destroyObject(value_obj);
            }
        } else {
            if (coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer coreui.endMenu();

                const impls = try apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.InterfaceOutputCdb.write(obj).?;

                        const value_obj = try cdb.createObject(db, cdb.getTypeIdx(db, iface.cdb_type_hash).?);
                        const value_obj_w = cdb.writeObj(value_obj).?;

                        try graphvm.InterfaceOutputCdb.setSubObj(obj_w, .value, value_obj_w);

                        try cdb.writeCommit(value_obj_w);
                        try cdb.writeCommit(obj_w);
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
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx;
        _ = filter;
        const db = cdb.getDbFromObjid(obj);
        const subobj = graphvm.GraphDataTypeCdb.readSubObj(graphvm.GraphDataTypeCdb.read(obj).?, .value);

        if (subobj) |value_obj| {
            if (coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                cdb.destroyObject(value_obj);
            }
        } else {
            if (coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer coreui.endMenu();

                const impls = try apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.GraphDataTypeCdb.write(obj).?;

                        const value_obj = try cdb.createObject(db, cdb.getTypeIdx(db, iface.cdb_type_hash).?);
                        const value_obj_w = cdb.writeObj(value_obj).?;

                        try graphvm.GraphDataTypeCdb.setSubObj(obj_w, .value, value_obj_w);

                        try cdb.writeCommit(value_obj_w);
                        try cdb.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

const const_value_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx;
        _ = filter;

        const db = cdb.getDbFromObjid(obj);
        const subobj = graphvm.ConstNodeSettingsCdb.readSubObj(graphvm.ConstNodeSettingsCdb.read(obj).?, .value);

        if (subobj) |value_obj| {
            if (coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                cdb.destroyObject(value_obj);
            }
        } else {
            if (coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer coreui.endMenu();

                const impls = try apidb.getImpl(allocator, graphvm.GraphValueTypeI);
                defer allocator.free(impls);
                for (impls) |iface| {
                    if (iface.cdb_type_hash.eql(graphvm.flowTypeCdb.type_hash)) continue;
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graphvm.ConstNodeSettingsCdb.write(obj).?;

                        const value_obj = try cdb.createObject(db, cdb.getTypeIdx(db, iface.cdb_type_hash).?);
                        const value_obj_w = cdb.writeObj(value_obj).?;

                        try graphvm.ConstNodeSettingsCdb.setSubObj(obj_w, .value, value_obj_w);

                        try cdb.writeCommit(value_obj_w);
                        try cdb.writeCommit(obj_w);
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

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = db;
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        try graphvm.GraphTypeCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.graph_visual_aspect,
        );

        try graphvm.NodeTypeCdb.addAspect(
            editor_inspector.UiInspectorObjAspect,

            db,
            _g.ui_properties_aspect,
        );

        try graphvm.NodeTypeCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.node_visual_aspect,
        );

        try graphvm.GroupTypeCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.group_visual_aspect,
        );

        try graphvm.ConnectionTypeCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.connection_visual_aspect,
        );

        try graphvm.InterfaceInputCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.interface_input_visual_aspect,
        );

        try graphvm.InterfaceInputCdb.addPropertyAspect(
            editor.UiSetMenusAspect,

            db,
            .value,
            _g.input_value_menu_aspect,
        );

        try graphvm.InterfaceOutputCdb.addAspect(
            editor.UiVisualAspect,

            db,
            _g.interface_output_visual_aspect,
        );

        try graphvm.InterfaceOutputCdb.addPropertyAspect(
            editor.UiSetMenusAspect,

            db,
            .value,
            _g.output_value_menu_aspect,
        );

        try graphvm.ConstNodeSettingsCdb.addPropertyAspect(
            editor.UiSetMenusAspect,

            db,
            .value,
            _g.const_value_menu_aspect,
        );

        try graphvm.GraphDataTypeCdb.addPropertyAspect(
            editor.UiSetMenusAspect,

            db,
            .value,
            _g.data_value_menu_aspect,
        );

        AssetTypeIdx = assetdb.AssetCdb.typeIdx(db);
        GraphTypeIdx = graphvm.GraphTypeCdb.typeIdx(db);
        ConnectionTypeIdx = graphvm.ConnectionTypeCdb.typeIdx(db);
        NodeTypeIdx = graphvm.NodeTypeCdb.typeIdx(db);
        GroupTypeIdx = graphvm.GroupTypeCdb.typeIdx(db);
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

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.setGlobalVarValue(editor_tabs.TabTypeI, module_name, TAB_NAME, graph_tab);

    try apidb.implOrRemove(module_name, editor_tabs.TabTypeI, &graph_tab, load);
    try apidb.implOrRemove(module_name, editor_assetdb.CreateAssetI, &create_graph_i, load);

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    _g.graph_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_graph_visual_aspect", graph_visual_aspect);
    _g.node_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_graph_node_visual_aspect", node_visual_aspect);
    _g.group_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_graph_group_visual_aspect", group_visual_aspect);
    _g.connection_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_graph_connection_visual_aspect", connection_visual_aspect);
    _g.interface_input_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_graph_interface_input_visual_aspect", interface_input_visual_aspect);
    _g.interface_output_visual_aspect = try apidb.setGlobalVarValue(editor.UiVisualAspect, module_name, "ct_graph_interface_output_visual_aspect", interface_output_visual_aspect);
    _g.ui_properties_aspect = try apidb.setGlobalVarValue(editor_inspector.UiInspectorObjAspect, module_name, "ct_graph_node_properties_aspect", node_prop_aspect);
    _g.input_value_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_interface_input_menu_aspect", input_variable_menu_aspect);
    _g.output_value_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_interface_output_menu_aspect", output_variable_menu_aspect);
    _g.const_value_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_node_const_menu_aspect", const_value_menu_aspect);
    _g.data_value_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_data_variable_menu_aspect", data_variable_menu_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_graph(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
