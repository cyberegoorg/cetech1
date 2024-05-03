const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const coreui = cetech1.coreui;
const node_editor = cetech1.coreui_node_editor;
const assetdb = cetech1.assetdb;
const graph = cetech1.graphvm;
const cdb_types = cetech1.cdb_types;

const editor_inspector = @import("editor_inspector");

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
var _assetdb: *const assetdb.AssetDBAPI = undefined;
var _tempalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _graph: *const cetech1.graphvm.GraphVMApi = undefined;
var _editor_inspector: *const editor_inspector.InspectorAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    test_tab_vt_ptr: *editor.EditorTabTypeI = undefined,
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

    pub fn fromU64(value: u64) PinId {
        const ptr: *PinId = @ptrFromInt(@intFromPtr(&value));
        return ptr.*;
    }
};

// Struct for tab type
const GraphEditorTab = struct {
    tab_i: editor.EditorTabI,
    editor: *node_editor.EditorContext,

    db: cdb.Db,
    selection: cdb.ObjId = .{},
    inter_selection: cdb.ObjId,
    root_graph_obj: cdb.ObjId = .{},

    // Add node filter
    filter_buff: [256:0]u8 = std.mem.zeroes([256:0]u8),
    filter: ?[:0]const u8 = null,

    ctxNodeId: node_editor.NodeId = 0,
    ctxLinkId: node_editor.LinkId = 0,
    ctxPinId: node_editor.PinId = 0,
    ctxPos: [2]f32 = .{ 0, 0 },
};

const SaveJson = struct { group_size: struct { x: f32, y: f32 } };
fn saveNodeSettings(nodeId: node_editor.NodeId, data: [*]const u8, size: usize, reason: node_editor.SaveReasonFlags, userPointer: *anyopaque) callconv(.C) bool {
    const tab_o: *GraphEditorTab = @alignCast(@ptrCast(userPointer));

    if (reason.Position or reason.Size) {
        const pos = _node_editor.getNodePosition(nodeId);

        const node_obj = cdb.ObjId.fromU64(nodeId);
        const node_w = tab_o.db.writeObj(node_obj).?;

        if (graph.NodeType.isSameType(tab_o.db, node_obj)) {
            if (reason.Position) {
                graph.NodeType.setValue(tab_o.db, f32, node_w, .pos_x, pos[0] / _coreui.getScaleFactor());
                graph.NodeType.setValue(tab_o.db, f32, node_w, .pos_y, pos[1] / _coreui.getScaleFactor());
            }
        } else if (graph.GroupType.isSameType(tab_o.db, node_obj)) {
            if (reason.Position) {
                graph.GroupType.setValue(tab_o.db, f32, node_w, .pos_x, pos[0] / _coreui.getScaleFactor());
                graph.GroupType.setValue(tab_o.db, f32, node_w, .pos_y, pos[1] / _coreui.getScaleFactor());
            }

            if (reason.Size) {
                const foo = std.json.parseFromSlice(
                    SaveJson,
                    _allocator,
                    data[0..size],
                    .{ .ignore_unknown_fields = true },
                ) catch return false;
                defer foo.deinit();

                graph.GroupType.setValue(tab_o.db, f32, node_w, .size_x, foo.value.group_size.x / _coreui.getScaleFactor());
                graph.GroupType.setValue(tab_o.db, f32, node_w, .size_y, foo.value.group_size.y / _coreui.getScaleFactor());
            }
        }

        tab_o.db.writeCommit(node_w) catch undefined;
    }

    return true;
}

// Fill editor tab interface
var foo_tab = editor.EditorTabTypeI.implement(editor.EditorTabTypeIArgs{
    .tab_name = TAB_NAME,
    .tab_hash = .{ .id = cetech1.strid.strId32(TAB_NAME).id },
    .create_on_init = true,
    .show_pin_object = true,
    .show_sel_obj_in_title = true,
}, struct {

    // Return name for menu /Tabs/
    pub fn menuName() ![:0]const u8 {
        return coreui.Icons.Graph ++ " " ++ "Graph editor";
    }

    // Return tab title
    pub fn title(inst: *editor.TabO) ![:0]const u8 {
        _ = inst;
        return coreui.Icons.Graph ++ " " ++ "Graph editor";
    }

    // Create new tab instantce
    pub fn create(db: cdb.Db) !?*editor.EditorTabI {
        var tab_inst = _allocator.create(GraphEditorTab) catch undefined;

        tab_inst.* = .{
            .editor = _node_editor.createEditor(.{
                .EnableSmoothZoom = true,
                .UserPointer = tab_inst,
                .SaveNodeSettings = @ptrCast(&saveNodeSettings),
            }),
            .inter_selection = try coreui.ObjSelection.createObject(db),
            .db = db,

            .tab_i = .{
                .vt = _g.test_tab_vt_ptr,
                .inst = @ptrCast(tab_inst),
            },
        };
        return &tab_inst.tab_i;
    }

    // Destroy tab instantce
    pub fn destroy(tab_inst: *editor.EditorTabI) !void {
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(tab_inst.inst));

        tab_o.db.destroyObject(tab_o.inter_selection);
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

        _node_editor.setCurrentEditor(tab_o.editor);

        {
            _node_editor.begin("GraphEditor", .{ 0, 0 });
            defer _node_editor.end();
            if (tab_o.selection.isEmpty()) {
                return;
            }

            const graph_asset = _coreui.getFirstSelected(tmp_alloc, tab_o.db, tab_o.selection);
            if (!_assetdb.isAssetObjTypeOf(graph_asset, graph.GraphType.typeIdx(tab_o.db))) return;
            if (graph_asset.isEmpty()) return;
            const graph_obj = _assetdb.getObjForAsset(graph_asset).?;

            const new_graph = !tab_o.root_graph_obj.eql(graph_obj);
            tab_o.root_graph_obj = graph_obj;

            if (graph_obj.isEmpty()) return;

            const graph_r = tab_o.db.readObj(graph_obj).?;

            // Nodes
            if (try graph.GraphType.readSubObjSet(tab_o.db, graph_r, .nodes, tmp_alloc)) |nodes| {
                defer tmp_alloc.free(nodes);

                for (nodes) |node| {
                    const node_r = tab_o.db.readObj(node).?;

                    if (new_graph) {
                        const node_pos_x = graph.NodeType.readValue(tab_o.db, f32, node_r, .pos_x);
                        const node_pos_y = graph.NodeType.readValue(tab_o.db, f32, node_r, .pos_y);
                        _node_editor.setNodePosition(node.toU64(), .{ node_pos_x * _coreui.getScaleFactor(), node_pos_y * _coreui.getScaleFactor() });
                    }

                    _node_editor.beginNode(node.toU64());
                    defer _node_editor.endNode();
                    const size = _node_editor.getNodeSize(node.toU64());
                    const node_type_hash = graph.NodeType.readValue(tab_o.db, u32, node_r, .node_type);
                    if (_graph.findNodeI(.{ .id = node_type_hash })) |node_i| {
                        _coreui.text(node_i.name);

                        if (node_i.title) |title_fce| {
                            const node_title = try title_fce(tmp_alloc, tab_o.db, node);
                            defer tmp_alloc.free(node_title);

                            _coreui.text(node_title);
                        }

                        const inputs = try node_i.getInputPins(tmp_alloc, tab_o.db, graph_obj, node);
                        defer tmp_alloc.free(inputs);
                        for (inputs) |input| {
                            const pinid = PinId.init(node, input.pin_hash).toU64();
                            _node_editor.beginPin(pinid, .Input);
                            {
                                defer _node_editor.endPin();
                                _coreui.text(input.name);
                            }
                        }

                        const outputs = try node_i.getOutputPins(tmp_alloc, tab_o.db, graph_obj, node);
                        defer tmp_alloc.free(inputs);
                        for (outputs) |output| {
                            const max_x = size[0] - 20;
                            const txt_size = _coreui.calcTextSize(output.name, .{});
                            _coreui.setCursorPosX(_coreui.getCursorPosX() + (max_x - txt_size[0]));

                            const pinid = PinId.init(node, output.pin_hash).toU64();
                            _node_editor.beginPin(pinid, .Output);
                            {
                                defer _node_editor.endPin();
                                _coreui.text(output.name);
                            }
                        }

                        // _coreui.pushItemWidth(200);
                        // {
                        //     defer _coreui.popItemWidth();
                        //     if (graph.NodeType.readSubObj(tab_o.db, node_r, .settings)) |setting_obj| {
                        //         try _editor_inspector.cdbPropertiesObj(tmp_alloc, tab_o.db, tab_o, setting_obj, 0, .{});
                        //     }
                        // }
                    } else {
                        _coreui.text("INVALID NODE TYPE HASH");
                    }
                }
            }

            //Groups
            if (try graph.GraphType.readSubObjSet(tab_o.db, graph_r, .groups, tmp_alloc)) |groups| {
                defer tmp_alloc.free(groups);

                for (groups) |group| {
                    const group_r = tab_o.db.readObj(group).?;

                    if (new_graph) {
                        const node_pos_x = graph.GroupType.readValue(tab_o.db, f32, group_r, .pos_x);
                        const node_pos_y = graph.GroupType.readValue(tab_o.db, f32, group_r, .pos_y);
                        _node_editor.setNodePosition(group.toU64(), .{ node_pos_x * _coreui.getScaleFactor(), node_pos_y * _coreui.getScaleFactor() });
                    }

                    const node_size_x = graph.GroupType.readValue(tab_o.db, f32, group_r, .size_x);
                    const node_size_y = graph.GroupType.readValue(tab_o.db, f32, group_r, .size_y);

                    const group_title = graph.GroupType.readStr(tab_o.db, group_r, .title) orelse "NO TITLE";

                    var color: [4]f32 = if (graph.GroupType.readSubObj(tab_o.db, group_r, .color)) |color_obj| cdb_types.Color4f.f.toSlice(tab_o.db, color_obj) else .{ 1, 1, 1, 0.4 };
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
            if (try graph.GraphType.readSubObjSet(tab_o.db, graph_r, .connections, tmp_alloc)) |connections| {
                defer tmp_alloc.free(connections);

                for (connections) |connect| {
                    const node_r = tab_o.db.readObj(connect).?;

                    const from_node = graph.ConnectionType.readRef(tab_o.db, node_r, .from_node) orelse cetech1.cdb.ObjId{};
                    const from_pin = graph.ConnectionType.readValue(tab_o.db, u32, node_r, .from_pin);

                    const to_node = graph.ConnectionType.readRef(tab_o.db, node_r, .to_node) orelse cetech1.cdb.ObjId{};
                    const to_pin = graph.ConnectionType.readValue(tab_o.db, u32, node_r, .to_pin);

                    const from_pin_id = PinId.init(from_node, .{ .id = from_pin }).toU64();
                    const to_pin_id = PinId.init(to_node, .{ .id = to_pin }).toU64();

                    var type_color: [4]f32 = .{ 1, 1, 1, 1 };

                    if (tab_o.db.readObj(from_node)) |from_node_obj_r| {
                        const from_node_type = graph.NodeType.readValue(tab_o.db, u32, from_node_obj_r, .node_type);
                        const out_pin = (try _graph.getOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node, .{ .id = from_node_type }, .{ .id = from_pin })).?;
                        type_color = _graph.getTypeColor(out_pin.type_hash);
                    }

                    _node_editor.link(connect.toU64(), from_pin_id, to_pin_id, type_color, 1);
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

                    var it = _apidb.getFirstImpl(graph.GraphNodeI);

                    if (tab_o.filter == null) {
                        // Create category menu first
                        while (it) |node| : (it = node.next) {
                            const iface = cetech1.apidb.ApiDbAPI.toInterface(graph.GraphNodeI, node);

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
                        const node_obj = try graph.GroupType.createObject(tab_o.db);

                        const node_w = tab_o.db.writeObj(node_obj).?;

                        try graph.GroupType.setStr(tab_o.db, node_w, .title, "Group");

                        graph.GroupType.setValue(tab_o.db, f32, node_w, .pos_x, tab_o.ctxPos[0]);
                        graph.GroupType.setValue(tab_o.db, f32, node_w, .pos_x, tab_o.ctxPos[1]);

                        graph.GroupType.setValue(tab_o.db, f32, node_w, .size_x, 50);
                        graph.GroupType.setValue(tab_o.db, f32, node_w, .size_y, 50);

                        const graph_w = tab_o.db.writeObj(graph_obj).?;
                        try graph.GraphType.addSubObjToSet(tab_o.db, graph_w, .groups, &.{node_w});

                        try tab_o.db.writeCommit(node_w);
                        try tab_o.db.writeCommit(graph_w);

                        _node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                    }

                    it = _apidb.getFirstImpl(graph.GraphNodeI);
                    while (it) |node| : (it = node.next) {
                        const iface = cetech1.apidb.ApiDbAPI.toInterface(graph.GraphNodeI, node);

                        var category_open = true;

                        if (tab_o.filter == null) {
                            if (iface.category) |category| {
                                var buff: [256:0]u8 = undefined;
                                const label = try std.fmt.bufPrintZ(&buff, "###{s}", .{category});

                                category_open = _coreui.beginMenu(_allocator, label, true, null);
                            }
                        }

                        var buff: [256:0]u8 = undefined;
                        const label = try std.fmt.bufPrintZ(&buff, "{s} {s}###{s}", .{ coreui.Icons.Node, iface.name, iface.name });

                        if (category_open and _coreui.menuItem(_allocator, label, .{}, tab_o.filter)) {
                            const node_obj = try _graph.createCdbNode(tab_o.db, iface.type_hash, tab_o.ctxPos);

                            const node_w = tab_o.db.writeObj(node_obj).?;

                            const graph_w = tab_o.db.writeObj(graph_obj).?;
                            try graph.GraphType.addSubObjToSet(tab_o.db, graph_w, .nodes, &.{node_w});

                            try tab_o.db.writeCommit(node_w);
                            try tab_o.db.writeCommit(graph_w);

                            _node_editor.setNodePosition(node_obj.toU64(), tab_o.ctxPos);
                        }

                        if (tab_o.filter == null and category_open and iface.category != null) {
                            _coreui.endMenu();
                        }
                    }
                }

                if (_coreui.beginPopup("ui_graph_node_context_menu", .{})) {
                    defer _coreui.endPopup();

                    if (_coreui.menuItem(_allocator, coreui.Icons.Delete ++ "  " ++ "Delete node", .{}, null)) {
                        _ = _node_editor.deleteNode(tab_o.ctxNodeId);
                    }
                }

                if (_coreui.beginPopup("ui_graph_link_context_menu", .{})) {
                    defer _coreui.endPopup();

                    if (_coreui.menuItem(_allocator, coreui.Icons.Delete ++ "  " ++ "Delete link", .{}, null)) {
                        _ = _node_editor.deleteLink(tab_o.ctxLinkId);
                    }
                }

                if (_coreui.beginPopup("ui_graph_pin_context_menu", .{})) {
                    defer _coreui.endPopup();

                    if (_coreui.menuItem(_allocator, "Break all links", .{}, null)) {
                        _ = _node_editor.breakPinLinks(tab_o.ctxPinId);
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
                        var from_node_obj = cdb.ObjId{ .id = from_id.objid, .gen = from_id.objgen, .type_idx = graph.NodeType.typeIdx(tab_o.db) };
                        const from_node_obj_r = tab_o.db.readObj(from_node_obj).?;
                        const from_node_type = graph.NodeType.readValue(tab_o.db, u32, from_node_obj_r, .node_type);

                        var to_id = PinId.fromU64(ne_to_id.?);
                        var to_node_obj = cdb.ObjId{ .id = to_id.objid, .gen = to_id.objgen, .type_idx = graph.NodeType.typeIdx(tab_o.db) };
                        const to_node_obj_r = tab_o.db.readObj(to_node_obj).?;
                        const to_node_type = graph.NodeType.readValue(tab_o.db, u32, to_node_obj_r, .node_type);

                        if (try _graph.isInputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node_obj, .{ .id = from_node_type }, .{ .id = from_id.pin_hash })) {
                            std.mem.swap(PinId, &from_id, &to_id);
                            std.mem.swap(cdb.ObjId, &from_node_obj, &to_node_obj);
                        }

                        const is_input = try _graph.isInputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, to_node_obj, .{ .id = to_node_type }, .{ .id = to_id.pin_hash });
                        const is_output = try _graph.isOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node_obj, .{ .id = from_node_type }, .{ .id = from_id.pin_hash });

                        if (ne_form_id.? == ne_to_id.?) {
                            _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 2);
                        } else if (!is_input or !is_output) {
                            _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 2);
                        } else if (from_node_obj.eql(to_node_obj)) {
                            _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 2);
                        } else {
                            const output_pin_def = (try _graph.getOutputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, from_node_obj, .{ .id = from_node_type }, .{ .id = from_id.pin_hash })).?;
                            const input_pin_def = (try _graph.getInputPin(tmp_alloc, tab_o.db, tab_o.root_graph_obj, to_node_obj, .{ .id = to_node_type }, .{ .id = to_id.pin_hash })).?;

                            const type_color = _graph.getTypeColor(output_pin_def.type_hash);

                            if (!input_pin_def.type_hash.eql(output_pin_def.type_hash)) {
                                _node_editor.rejectNewItem(.{ 1, 0, 0, 1 }, 2);
                            } else if (_node_editor.acceptNewItem(type_color, 1.0)) {
                                if (_node_editor.pinHadAnyLinks(ne_to_id.?)) {
                                    _ = _node_editor.breakPinLinks(ne_to_id.?);
                                }

                                const connection_obj = try graph.ConnectionType.createObject(tab_o.db);
                                const connection_w = tab_o.db.writeObj(connection_obj).?;

                                try graph.ConnectionType.setRef(tab_o.db, connection_w, .from_node, from_node_obj);
                                graph.ConnectionType.setValue(tab_o.db, u32, connection_w, .from_pin, from_id.pin_hash);

                                try graph.ConnectionType.setRef(tab_o.db, connection_w, .to_node, to_node_obj);
                                graph.ConnectionType.setValue(tab_o.db, u32, connection_w, .to_pin, to_id.pin_hash);

                                const graph_w = tab_o.db.writeObj(graph_obj).?;
                                try graph.GraphType.addSubObjToSet(tab_o.db, graph_w, .connections, &.{connection_w});

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

        if (_node_editor.hasSelectionChanged()) {
            const selected_object_n = _node_editor.getSelectedObjectCount();
            if (selected_object_n != 0) {
                const selected_nodes = try tmp_alloc.alloc(node_editor.NodeId, @intCast(selected_object_n));
                const nodes_n = _node_editor.getSelectedNodes(selected_nodes);
                var selected_objs: []cdb.ObjId = undefined;

                selected_objs.ptr = @ptrCast(selected_nodes.ptr);
                selected_objs.len = @intCast(nodes_n);

                try _coreui.clearSelection(tmp_alloc, tab_o.db, tab_o.inter_selection);
                for (selected_objs) |node_obj| {
                    try _coreui.addToSelection(tab_o.db, tab_o.inter_selection, node_obj);
                }
            } else {
                try _coreui.clearSelection(tmp_alloc, tab_o.db, tab_o.inter_selection);
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
        _editor.propagateSelection(tab_o.db, tab_o.inter_selection);
    }

    // Selected object
    pub fn objSelected(inst: *editor.TabO, db: cdb.Db, selection: cdb.ObjId) !void {
        var tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));
        if (tab_o.inter_selection.eql(selection)) return;

        const selected = _coreui.getFirstSelected(_allocator, db, selection);
        if (_assetdb.isAssetObjTypeOf(selected, graph.GraphType.typeIdx(db))) {
            tab_o.selection = selection;
        } else if (selected.type_idx.eql(graph.NodeType.typeIdx(db)) or selected.type_idx.eql(graph.GroupType.typeIdx(db))) {
            _node_editor.setCurrentEditor(tab_o.editor);
            defer _node_editor.setCurrentEditor(null);
            _node_editor.selectNode(selected.toU64(), false);
            _node_editor.navigateToSelection(selected.type_idx.eql(graph.GroupType.typeIdx(db)), -1);
        } else if (selected.type_idx.eql(graph.ConnectionType.typeIdx(db))) {
            _node_editor.setCurrentEditor(tab_o.editor);
            defer _node_editor.setCurrentEditor(null);
            _node_editor.selectLink(selected.toU64(), false);
            _node_editor.navigateToSelection(false, -1);
        }
    }

    pub fn assetRootOpened(inst: *editor.TabO) !void {
        const tab_o: *GraphEditorTab = @alignCast(@ptrCast(inst));
        tab_o.filter = null;
    }
});

// Create folder
var create_graph_i = editor.CreateAssetI.implement(
    graph.GraphType.type_hash,
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
                db.getTypeIdx(graph.GraphType.type_hash).?,
                "NewGraph",
            );

            const new_obj = try graph.GraphType.createObject(db);

            _ = _assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Graph ++ "  " ++ "Graph";
        }
    },
);

var graph_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiIcons(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = db;

        _ = obj;
        return std.fmt.allocPrintZ(allocator, "{s}", .{coreui.Icons.Graph});
    }
});

var node_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const obj_r = db.readObj(obj).?;

        const node_type_hash = graph.NodeType.readValue(db, u32, obj_r, .node_type);
        if (_graph.findNodeI(.{ .id = node_type_hash })) |node_i| {
            return std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{
                    node_i.name,
                },
            ) catch "";
        }
        return std.fmt.allocPrintZ(
            allocator,
            "{s}",
            .{
                "!!! Invalid node type",
            },
        ) catch "";
    }

    pub fn uiIcons(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = db;
        _ = obj;
        return std.fmt.allocPrintZ(allocator, "{s}", .{coreui.Icons.Node});
    }
});

var group_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const obj_r = db.readObj(obj).?;

        if (graph.GroupType.readStr(db, obj_r, .title)) |tile| {
            return std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{
                    tile,
                },
            ) catch "";
        }

        return std.fmt.allocPrintZ(
            allocator,
            "{s}",
            .{
                "No title",
            },
        ) catch "";
    }

    pub fn uiIcons(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = db;
        _ = obj;
        return std.fmt.allocPrintZ(allocator, "{s}", .{coreui.Icons.Group});
    }

    pub fn uiColor(
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![4]f32 {
        const obj_r = db.readObj(obj).?;
        const color = graph.GroupType.readSubObj(db, obj_r, .color) orelse return .{ 1.0, 1.0, 1.0, 1.0 };
        return cetech1.cdb_types.Color4f.f.toSlice(db, color);
    }
});

var interface_input_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const obj_r = db.readObj(obj).?;

        if (graph.InterfaceInput.readStr(db, obj_r, .name)) |tile| {
            return std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{
                    tile,
                },
            ) catch "";
        }

        return std.fmt.allocPrintZ(
            allocator,
            "{s}",
            .{
                "No title",
            },
        ) catch "";
    }
});

var interface_output_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiName(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        const obj_r = db.readObj(obj).?;

        if (graph.InterfaceOutput.readStr(db, obj_r, .name)) |tile| {
            return std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{
                    tile,
                },
            ) catch "";
        }

        return std.fmt.allocPrintZ(
            allocator,
            "{s}",
            .{
                "No title",
            },
        ) catch "";
    }
});

var connection_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiIcons(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = db;
        _ = obj;
        return std.fmt.allocPrintZ(allocator, "{s}", .{coreui.Icons.Link});
    }
});

const node_prop_aspect = editor_inspector.UiPropertiesAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        tab: *editor.TabO,
        obj: cdb.ObjId,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        const node_r = graph.NodeType.read(db, obj).?;

        if (graph.NodeType.readSubObj(db, node_r, .settings)) |setting_obj| {
            try _editor_inspector.cdbPropertiesObj(allocator, db, tab, setting_obj, 0, args);
        }
    }
});

const input_variable_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) !void {
        _ = prop_idx; // autofix

        const subobj = graph.InterfaceInput.readSubObj(db, graph.InterfaceInput.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                var it = _apidb.getFirstImpl(graph.GraphValueTypeI);
                while (it) |node| : (it = node.next) {
                    const iface = cetech1.apidb.ApiDbAPI.toInterface(graph.GraphValueTypeI, node);
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graph.InterfaceInput.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graph.InterfaceInput.setSubObj(db, obj_w, .value, value_obj_w);

                        try db.writeCommit(value_obj_w);
                        try db.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

const output_variable_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        db: cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
    ) !void {
        _ = prop_idx; // autofix

        const subobj = graph.InterfaceInput.readSubObj(db, graph.InterfaceInput.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                var it = _apidb.getFirstImpl(graph.GraphValueTypeI);
                while (it) |node| : (it = node.next) {
                    const iface = cetech1.apidb.ApiDbAPI.toInterface(graph.GraphValueTypeI, node);
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graph.InterfaceOutput.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graph.InterfaceOutput.setSubObj(db, obj_w, .value, value_obj_w);

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

        const subobj = graph.ConstNodeSettings.readSubObj(db, graph.ConstNodeSettings.read(db, obj).?, .value);

        if (subobj) |value_obj| {
            if (_coreui.menuItem(allocator, coreui.Icons.Delete ++ "  " ++ "Delete", .{}, null)) {
                db.destroyObject(value_obj);
            }
        } else {
            if (_coreui.beginMenu(allocator, coreui.Icons.Add ++ " " ++ "Add value", true, null)) {
                defer _coreui.endMenu();

                var it = _apidb.getFirstImpl(graph.GraphValueTypeI);
                while (it) |node| : (it = node.next) {
                    const iface = cetech1.apidb.ApiDbAPI.toInterface(graph.GraphValueTypeI, node);
                    if (iface.cdb_type_hash.eql(graph.flowType.type_hash)) continue;
                    if (iface.cdb_type_hash.isEmpty()) continue;

                    if (_coreui.menuItem(allocator, iface.name, .{}, null)) {
                        const obj_w = graph.ConstNodeSettings.write(db, obj).?;

                        const value_obj = try db.createObject(db.getTypeIdx(iface.cdb_type_hash).?);
                        const value_obj_w = db.writeObj(value_obj).?;

                        try graph.ConstNodeSettings.setSubObj(db, obj_w, .value, value_obj_w);

                        try db.writeCommit(value_obj_w);
                        try db.writeCommit(obj_w);
                    }
                }
            }
        }
    }
});

var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cetech1.cdb.Db) !void {
        try graph.GraphType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.graph_visual_aspect,
        );

        try graph.NodeType.addAspect(
            db,
            editor_inspector.UiPropertiesAspect,
            _g.ui_properties_aspect,
        );

        try graph.GroupType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.group_visual_aspect,
        );

        try graph.NodeType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.node_visual_aspect,
        );

        try graph.ConnectionType.addAspect(
            db,
            editor.UiVisualAspect,
            _g.connection_visual_aspect,
        );

        try graph.InterfaceInput.addAspect(
            db,
            editor.UiVisualAspect,
            _g.interface_input_visual_aspect,
        );

        try graph.InterfaceInput.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.input_value_menu_aspect,
        );

        try graph.InterfaceOutput.addAspect(
            db,
            editor.UiVisualAspect,
            _g.interface_output_visual_aspect,
        );

        try graph.InterfaceOutput.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.output_value_menu_aspect,
        );

        try graph.ConstNodeSettings.addPropertyAspect(
            db,
            editor.UiSetMenusAspect,
            .value,
            _g.const_value_menu_aspect,
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

    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;
    _node_editor = apidb.getZigApi(module_name, node_editor.NodeEditorApi).?;
    _assetdb = apidb.getZigApi(module_name, assetdb.AssetDBAPI).?;
    _editor = apidb.getZigApi(module_name, editor.EditorAPI).?;
    _tempalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _graph = apidb.getZigApi(module_name, cetech1.graphvm.GraphVMApi).?;
    _editor_inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    // Alocate memory for VT of tab.
    // Need for hot reload becasue vtable is shared we need strong pointer adress.
    _g.test_tab_vt_ptr = try apidb.globalVar(editor.EditorTabTypeI, module_name, TAB_NAME, .{});
    // Patch vt pointer to new.
    _g.test_tab_vt_ptr.* = foo_tab;

    try apidb.implOrRemove(module_name, editor.EditorTabTypeI, &foo_tab, load);
    try apidb.implOrRemove(module_name, editor.CreateAssetI, &create_graph_i, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    _g.graph_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_visual_aspect", .{}, graph_visual_aspect);
    _g.node_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_node_visual_aspect", .{}, node_visual_aspect);
    _g.group_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_group_visual_aspect", .{}, group_visual_aspect);
    _g.connection_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_connection_visual_aspect", .{}, connection_visual_aspect);
    _g.interface_input_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_interface_input_visual_aspect", .{}, interface_input_visual_aspect);
    _g.interface_output_visual_aspect = try apidb.globalVarValue(editor.UiVisualAspect, module_name, "ct_graph_interface_output_visual_aspect", .{}, interface_output_visual_aspect);
    _g.ui_properties_aspect = try apidb.globalVarValue(editor_inspector.UiPropertiesAspect, module_name, "ct_graph_node_properties_aspect", .{}, node_prop_aspect);
    _g.input_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_interface_input_menu_aspect", .{}, input_variable_menu_aspect);
    _g.output_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_interface_output_menu_aspect", .{}, output_variable_menu_aspect);
    _g.const_value_menu_aspect = try apidb.globalVarValue(editor.UiSetMenusAspect, module_name, "ct_graph_node_const_menu_aspect", .{}, const_value_menu_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_graph(__apidb: *const cetech1.apidb.ApiDbAPI, __allocator: *const std.mem.Allocator, __load: bool, __reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, __apidb, __allocator, __load, __reload);
}
