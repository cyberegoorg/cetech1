// TODO: naive first draft => slow and shity

const std = @import("std");

const apidb = @import("apidb.zig");
const cdb = @import("cdb.zig");
const tempalloc = @import("tempalloc.zig");
const task = @import("task.zig");
const profiler_private = @import("profiler.zig");
const assetdb_private = @import("assetdb.zig");

const cetech1 = @import("cetech1");
const public = cetech1.graphvm;
const strid = cetech1.strid;
const cdb_types = cetech1.cdb_types;

const module_name = .graphvm;
const log = std.log.scoped(module_name);

const VMNodeIdx = usize;

const Connection = struct {
    node: VMNodeIdx,
    pin: cetech1.strid.StrId32,
    pin_type: strid.StrId32,
    pin_idx: u32 = 0,
};

const ConnectionPair = struct {
    from: Connection,
    to: Connection,
};

const GraphNode = struct {
    parent: cetech1.cdb.ObjId,
    node: cetech1.cdb.ObjId,
};

const NodeTypeIfaceMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *const public.GraphNodeI);
const ValueTypeIfaceMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *const public.GraphValueTypeI);
const VMNodeMap = std.AutoArrayHashMap(GraphNode, VMNodeIdx);
const ConnectionPairList = std.ArrayList(ConnectionPair);
const ContainerPool = cetech1.mem.PoolWithLock(VMInstance);
const InstanceSet = std.AutoArrayHashMap(*VMInstance, void);
const NodeIdxPlan = std.AutoArrayHashMap(VMNodeIdx, []VMNodeIdx);
const VMPool = cetech1.mem.PoolWithLock(GraphVM);
const VMMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, *GraphVM);
const VMNodeByTypeMap = std.AutoArrayHashMap(cetech1.strid.StrId32, std.ArrayList(VMNodeIdx));
const ObjSet = cetech1.mem.HashSet(cetech1.cdb.ObjId);
const IdxSet = cetech1.mem.HashSet(VMNodeIdx);
const NodeSet = cetech1.mem.ArraySet(GraphNode);
const ObjArray = std.ArrayList(cetech1.cdb.ObjId);

const NodePrototypeMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, cetech1.cdb.ObjId);

//
const NodeKey = struct {
    obj: cetech1.cdb.ObjId,
    pin: strid.StrId32,
};
const NodeValue = struct {
    obj: cetech1.cdb.ObjId,
    pin: strid.StrId32,
};

const NodeValueSet = cetech1.mem.ArraySet(NodeValue);
const NodeMap = std.AutoArrayHashMap(NodeKey, NodeValueSet);

const OutConnection = struct {
    graph: cetech1.cdb.ObjId,
    c: cetech1.cdb.ObjId,
};
const OutConnectionArray = std.ArrayList(OutConnection);
//

const InputData = struct {
    const Self = @This();

    data: ?[]?[*]u8 = null,
    validity_hash: ?[]?*public.ValidityHash = null,
    types: ?[]?strid.StrId32 = null,

    pub fn init() Self {
        return Self{};
    }

    pub fn fromPins(self: *Self, allocator: std.mem.Allocator, blob_size: usize, pins: []const public.NodePin) !void {
        if (blob_size != 0) {
            self.data = try allocator.alloc(?[*]u8, pins.len);
            @memset(self.data.?, null);

            self.validity_hash = try allocator.alloc(?*public.ValidityHash, pins.len);
            @memset(self.validity_hash.?, null);

            self.types = try allocator.alloc(?strid.StrId32, pins.len);
            @memset(self.types.?, null);
        }
    }

    pub fn toPins(self: Self) public.InPins {
        return public.InPins{
            .data = self.data,
            .validity_hash = self.validity_hash,
            .types = self.types,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }
};

const OutputData = struct {
    const Self = @This();

    data: ?[]u8 = null,
    data_slices: ?[][*]u8 = null,

    validity_hash: ?[]public.ValidityHash = null,
    types: ?[]strid.StrId32 = null,

    pub fn init() Self {
        return Self{};
    }

    pub fn fromPins(self: *Self, allocator: std.mem.Allocator, blob_size: usize, pins: []const public.NodePin) !void {
        if (blob_size != 0) {
            self.data_slices = try allocator.alloc([*]u8, pins.len);
            self.data = try allocator.alloc(u8, blob_size);
            @memset(self.data.?, 0);

            self.types = try allocator.alloc(strid.StrId32, pins.len);
            @memset(self.types.?, .{});

            var pin_s: usize = 0;
            for (pins, 0..) |pin, idx| {
                const pin_def = findValueTypeI(pin.type_hash).?;
                self.data_slices.?[idx] = self.data.?[pin_s .. pin_s + pin_def.size].ptr;
                pin_s += pin_def.size;
                self.types.?[idx] = pin_def.type_hash;
            }

            self.validity_hash = try allocator.alloc(public.ValidityHash, pins.len);
            @memset(self.validity_hash.?, 0);
        }
    }

    pub fn toPins(self: Self) public.OutPins {
        return public.OutPins{
            .data = self.data_slices,
            .validity_hash = self.validity_hash,
            .types = self.types,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.data) |data| {
            allocator.free(data);
            self.data = null;
        }
        if (self.data_slices) |data| {
            allocator.free(data);
            self.data_slices = null;
        }
        if (self.validity_hash) |vh| {
            allocator.free(vh);
            self.validity_hash = null;
        }
        if (self.types) |vh| {
            allocator.free(vh);
            self.types = null;
        }
    }
};

const InstanceNode = struct {
    const Self = @This();

    in_data: InputData,
    out_data: OutputData,
    state: ?*anyopaque = null,

    last_inputs_validity_hash: []public.ValidityHash = undefined,

    vmnode_idx: VMNodeIdx,

    eval: bool = false,

    pub fn init(
        data_alloc: std.mem.Allocator,
        state: ?*anyopaque,
        inputs: []const public.NodePin,
        outputs: []const public.NodePin,
        input_blob_size: usize,
        output_blob_size: usize,
        vmnode_idx: VMNodeIdx,
    ) !Self {
        var self = Self{
            .in_data = InputData.init(),
            .out_data = OutputData.init(),
            .state = state,
            .vmnode_idx = vmnode_idx,
        };

        try self.in_data.fromPins(data_alloc, input_blob_size, inputs);
        try self.out_data.fromPins(data_alloc, output_blob_size, outputs);

        self.last_inputs_validity_hash = try _allocator.alloc(public.ValidityHash, inputs.len);
        @memset(self.last_inputs_validity_hash, 0);

        return self;
    }

    pub fn deinit(self: *Self) void {
        _allocator.free(self.last_inputs_validity_hash);
        self.in_data.deinit();
    }
};

const VMInstanceNodeIdx = usize;

// Instace of GraphVM

const VMNode = struct {
    const Self = @This();
    node_obj: cetech1.cdb.ObjId,
    settings: ?cetech1.cdb.ObjId,

    allocator: std.mem.Allocator,

    iface: *const public.GraphNodeI,

    inputs: []const public.NodePin = undefined,
    outputs: []const public.NodePin = undefined,

    input_blob_size: usize = 0,
    output_blob_size: usize = 0,

    input_count: usize = 0,
    output_count: usize = 0,

    data_map: public.PinDataIdxMap,

    has_flow: bool = false,
    has_flow_out: bool = false,

    cdb_version: cetech1.cdb.ObjVersion = 0,
    init: bool = false,

    pub fn init(allocator: std.mem.Allocator, iface: *const public.GraphNodeI, settings: ?cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId, cdb_version: cetech1.cdb.ObjVersion) Self {
        return Self{
            .allocator = allocator,
            .iface = iface,
            .data_map = public.PinDataIdxMap.init(allocator),
            .cdb_version = cdb_version,
            .node_obj = node_obj,
            .settings = settings,
            .init = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.init) return;
        self.data_map.deinit();
        self.allocator.free(self.outputs);
        self.allocator.free(self.inputs);
        self.init = true;
    }

    pub fn clean(self: *Self) void {
        self.data_map.clearRetainingCapacity();
        self.allocator.free(self.outputs);
        self.allocator.free(self.inputs);
    }

    fn getOutputPinsSize(self: *Self, pins: []const public.NodePin) !usize {
        var size: usize = 0;

        for (pins, 0..) |pin, idx| {
            const type_def = findValueTypeI(pin.type_hash).?;
            try self.data_map.put(pin.pin_hash, @intCast(idx));
            // const alignn = std.mem.alignForwardLog2(size, @intCast(type_def.alignn)) - size;
            size += type_def.size;
        }

        return size;
    }

    fn getInputPinsSize(self: *Self, pins: []const public.NodePin) !usize {
        const size: usize = @sizeOf(?*anyopaque) * pins.len;

        for (pins, 0..) |pin, idx| {
            try self.data_map.put(pin.pin_hash, @intCast(idx));
        }

        return size;
    }
};

const VMInstance = struct {
    const Self = @This();
    const InstanceNodeMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, *InstanceNode);

    const InstanceNodeIdxMap = std.AutoArrayHashMap(GraphNode, VMInstanceNodeIdx);
    const InstanceNodeMultiArray = std.MultiArrayList(InstanceNode);

    const DataHolder = std.ArrayList(u8);
    const StateHolder = std.ArrayList(u8);
    const ContextMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *anyopaque);

    allocator: std.mem.Allocator,
    vm: *GraphVM,

    node_idx_map: InstanceNodeIdxMap,
    nodes: InstanceNodeMultiArray = .{},

    context_map: ContextMap,

    graph_in: OutputData,
    graph_out: OutputData,

    node_arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, vm: *GraphVM) Self {
        return Self{
            .allocator = allocator,
            .vm = vm,
            .context_map = ContextMap.init(allocator),
            .graph_in = OutputData.init(),
            .graph_out = OutputData.init(),
            .node_idx_map = InstanceNodeIdxMap.init(allocator),
            .node_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.clean() catch undefined;

        const ifaces = self.vm.vmnodes.items(.iface);
        for (0..self.nodes.len) |idx| {
            var v = self.nodes.get(idx);
            if (v.state) |state| {
                const iface = ifaces[v.vmnode_idx];
                if (iface.destroy) |destroy| {
                    destroy(state, self.vm.db, false) catch undefined;
                }
            }
            v.deinit();
        }

        self.context_map.deinit();
        self.node_idx_map.deinit();
        self.nodes.deinit(self.allocator);
        self.node_arena.deinit();
    }

    pub fn clean(self: *Self) !void {
        self.context_map.clearRetainingCapacity();

        self.graph_in.deinit(self.allocator);
        self.graph_out.deinit(self.allocator);
    }

    pub fn setContext(self: *Self, context_name: strid.StrId32, context: *anyopaque) !void {
        try self.context_map.put(context_name, context);
    }

    pub fn getContext(self: *Self, context_name: strid.StrId32) ?*anyopaque {
        return self.context_map.get(context_name);
    }

    pub fn removeContext(self: *Self, context_name: strid.StrId32) void {
        _ = self.context_map.swapRemove(context_name);
    }
};

const RebuildTask = struct {
    instances: []const *VMInstance,
    changed_nodes: *const IdxSet,
    deleted_nodes: *const NodeSet,

    pub fn exec(self: *const @This()) !void {
        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);

        var vm = self.instances[0].vm;
        try vm.buildInstances(alloc, self.instances, self.deleted_nodes, self.changed_nodes);
    }
};
const VMNodeMultiArray = std.MultiArrayList(VMNode);
const PivotList = std.ArrayList(VMNodeIdx);

const GraphVM = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    db: cetech1.cdb.Db,
    graph_obj: cetech1.cdb.ObjId,
    graph_version: cetech1.cdb.ObjVersion = 0,

    node_idx_map: VMNodeMap,
    vmnodes: VMNodeMultiArray = .{},

    free_idx: IdxSet,

    connection: ConnectionPairList,

    instance_set: InstanceSet,

    node_plan: NodeIdxPlan,

    inputs: ?[]const public.NodePin = null,
    outputs: ?[]const public.NodePin = null,

    node_by_type: VMNodeByTypeMap,

    output_blob_size: usize = 0,
    input_blob_size: usize = 0,

    pub fn init(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId) Self {
        return Self{
            .allocator = allocator,
            .graph_obj = graph,
            .db = db,
            .instance_set = InstanceSet.init(allocator),
            .node_plan = NodeIdxPlan.init(allocator),
            .node_by_type = VMNodeByTypeMap.init(allocator),
            .connection = ConnectionPairList.init(allocator),
            .node_idx_map = VMNodeMap.init(allocator),
            .free_idx = IdxSet.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        //        self.clean();

        for (self.node_by_type.values()) |value| {
            value.deinit();
        }

        for (self.instance_set.keys()) |value| {
            value.deinit();
        }

        for (self.node_plan.values()) |value| {
            self.allocator.free(value);
        }

        if (self.inputs) |inputs| {
            self.allocator.free(inputs);
        }

        if (self.outputs) |outputs| {
            self.allocator.free(outputs);
        }

        for (0..self.vmnodes.len) |idx| {
            if (self.free_idx.contains(idx)) continue;
            var node = self.vmnodes.get(idx);
            node.deinit();
        }

        self.node_plan.deinit();

        self.connection.deinit();

        self.instance_set.deinit();
        self.node_by_type.deinit();

        self.vmnodes.deinit(self.allocator);
        self.node_idx_map.deinit();
        self.free_idx.deinit();
    }

    pub fn clean(self: *Self) !void {
        for (self.instance_set.keys()) |value| {
            try value.clean();
        }

        for (self.node_plan.values()) |value| {
            self.allocator.free(value);
        }

        for (self.node_by_type.values()) |*value| {
            value.clearRetainingCapacity();
        }

        self.node_plan.clearRetainingCapacity();
        self.connection.clearRetainingCapacity();

        if (self.inputs) |inputs| {
            self.allocator.free(inputs);
        }

        if (self.outputs) |outputs| {
            self.allocator.free(outputs);
        }
    }

    fn findNodeByType(self: Self, node_type: cetech1.strid.StrId32) ?[]VMNodeIdx {
        var zone_ctx = profiler_private.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (self.node_by_type.get(node_type)) |nodes| {
            if (nodes.items.len == 0) return null;
            return nodes.items;
        }

        return null;
    }

    fn computePinSize(pins: []const public.NodePin) !usize {
        var size: usize = 0;

        for (pins, 0..) |pin, idx| {
            _ = idx; // autofix
            const type_def = findValueTypeI(pin.type_hash).?;
            // const alignn = std.mem.alignForwardLog2(size, @intCast(type_def.alignn)) - size;
            size += type_def.size;
        }

        return size;
    }

    fn addNode(
        self: *Self,
        allocator: std.mem.Allocator,
        parent_grap: cetech1.cdb.ObjId,
        node: cetech1.cdb.ObjId,
        node_prototype_map: *NodePrototypeMap,
        pivots: *PivotList,
        changed_nodes: *IdxSet,
        root: bool,
    ) anyerror!void {
        _ = root; // autofix
        _ = allocator; // autofix
        var cdb_versions = self.vmnodes.items(.cdb_version);

        const node_r = self.db.readObj(node).?;
        const type_hash = public.NodeType.f.getNodeTypeId(self.db, node_r);
        const iface = findNodeI(type_hash).?;

        const prototype = self.db.getPrototype(node_r);
        const node_version = self.db.getVersion(node);
        const node_idx_get = try self.node_idx_map.getOrPut(.{ .parent = parent_grap, .node = node });

        // TODO: remove orphans nodes => exist in node_map but not in graph (need set)
        const exist = node_idx_get.found_existing;
        const regen = if (exist) cdb_versions[node_idx_get.value_ptr.*] != node_version else false;

        if (exist) {
            cdb_versions[node_idx_get.value_ptr.*] = node_version;
        }

        const settings = public.NodeType.readSubObj(self.db, node_r, .settings);

        if (!prototype.isEmpty()) {
            try node_prototype_map.put(prototype, node);
        }

        if (!exist) {
            if (self.free_idx.pop()) |idx| {
                node_idx_get.value_ptr.* = idx;
                self.vmnodes.set(idx, VMNode.init(
                    _allocator,
                    iface,
                    settings,
                    node,
                    node_version,
                ));
            } else {
                node_idx_get.value_ptr.* = self.vmnodes.len;
                self.vmnodes.appendAssumeCapacity(VMNode.init(
                    _allocator,
                    iface,
                    settings,
                    node,
                    node_version,
                ));
            }
        } else if (regen) {
            var vmnode = self.vmnodes.get(node_idx_get.value_ptr.*);
            vmnode.clean();
        }

        const node_idx = node_idx_get.value_ptr.*;

        if (!exist or regen) {
            try self.buildVMNodes(node_idx, self.db, self.graph_obj, node);
            _ = try changed_nodes.add(node_idx);
        }

        if (iface.pivot != .none) {
            try pivots.append(node_idx);
        }

        const node_type_get = try self.node_by_type.getOrPut(iface.type_hash);
        if (!node_type_get.found_existing) {
            node_type_get.value_ptr.* = std.ArrayList(VMNodeIdx).init(self.allocator);
        }
        try node_type_get.value_ptr.*.append(node_idx);
    }

    fn addNodes(
        self: *Self,
        allocator: std.mem.Allocator,
        graph: cetech1.cdb.ObjId,
        node_prototype_map: *NodePrototypeMap,
        pivots: *PivotList,
        changed_nodes: *IdxSet,
        used_nodes: *NodeSet,
        node_map: *NodeMap,
        node_backward_map: *NodeMap,
        out_connections: *OutConnectionArray,
        parent_node: ?cetech1.cdb.ObjId,
        root: bool,
    ) !void {
        const graph_r = self.db.readObj(graph).?;

        // Nodes
        const nodes = (try public.GraphType.readSubObjSet(self.db, graph_r, .nodes, allocator)).?;
        defer allocator.free(nodes);

        const connections = (try public.GraphType.readSubObjSet(self.db, graph_r, .connections, allocator)).?;
        defer allocator.free(connections);

        try self.vmnodes.ensureUnusedCapacity(self.allocator, nodes.len);

        for (nodes) |node| {
            _ = try used_nodes.add(.{ .node = node, .parent = graph });
        }

        // Add node expect subgraph
        for (nodes) |node| {
            const node_r = self.db.readObj(node).?;
            const type_hash = public.NodeType.f.getNodeTypeId(self.db, node_r);
            const iface = findNodeI(type_hash).?;

            if (!root) {
                if (iface.type_hash.eql(graph_inputs_i.type_hash)) {
                    continue;
                }

                if (iface.type_hash.eql(graph_outputs_i.type_hash)) {
                    continue;
                }
            }

            if (iface.type_hash.eql(call_graph_node_i.type_hash)) {
                const s = public.NodeType.readSubObj(self.db, node_r, .settings) orelse continue;
                const s_r = public.CallGraphNodeSettings.read(self.db, s).?;
                if (public.CallGraphNodeSettings.readSubObj(self.db, s_r, .graph)) |sub_graph| {
                    try self.addNodes(
                        allocator,
                        sub_graph,
                        node_prototype_map,
                        pivots,
                        changed_nodes,
                        used_nodes,

                        node_map,
                        node_backward_map,
                        out_connections,
                        node,
                        false,
                    );
                }
                continue;
            }

            try self.addNode(allocator, self.graph_obj, node, node_prototype_map, pivots, changed_nodes, root);
        }

        for (connections) |connection| {
            const connection_r = self.db.readObj(connection).?;
            var from_node_obj = public.ConnectionType.readRef(self.db, connection_r, .from_node).?;
            const from_pin = public.ConnectionType.f.getFromPinId(self.db, connection_r);

            var to_node_obj = public.ConnectionType.readRef(self.db, connection_r, .to_node).?;
            const to_pin = public.ConnectionType.f.getToPinId(self.db, connection_r);

            // Rewrite connection from prototype
            if (node_prototype_map.get(from_node_obj)) |node| {
                from_node_obj = node;
            }
            if (node_prototype_map.get(to_node_obj)) |node| {
                to_node_obj = node;
            }

            const from_node_obj_r = self.db.readObj(from_node_obj).?;
            const from_node_type = public.NodeType.f.getNodeTypeId(self.db, from_node_obj_r);
            const from_subgraph = call_graph_node_i.type_hash.eql(from_node_type);
            const from_inputs = graph_inputs_i.type_hash.eql(from_node_type);
            const from_node = !from_subgraph and !from_inputs;

            const to_node_obj_r = self.db.readObj(to_node_obj).?;
            const to_node_type = public.NodeType.f.getNodeTypeId(self.db, to_node_obj_r);
            const to_subgraph = call_graph_node_i.type_hash.eql(to_node_type);
            const to_outputs = graph_outputs_i.type_hash.eql(to_node_type);
            const to_node = !to_subgraph and !to_outputs;

            // Change input nodes to call graph node
            if (from_inputs and parent_node != null) {
                from_node_obj = parent_node.?;
            }

            // Change output nodes to call graph node
            if (to_outputs and parent_node != null) {
                to_node_obj = parent_node.?;
            }

            // FROM => TO
            // Forward
            {
                const get = try node_map.getOrPut(.{ .obj = from_node_obj, .pin = from_pin });
                if (!get.found_existing) {
                    get.value_ptr.* = NodeValueSet.init(self.allocator);
                }
                _ = try get.value_ptr.*.add(NodeValue{ .obj = to_node_obj, .pin = to_pin });
            }

            // TO => FROM
            // Backward
            {
                const get = try node_backward_map.getOrPut(.{ .obj = to_node_obj, .pin = to_pin });
                if (!get.found_existing) {
                    get.value_ptr.* = NodeValueSet.init(self.allocator);
                }
                _ = try get.value_ptr.*.add(NodeValue{ .obj = from_node_obj, .pin = from_pin });
            }

            if (from_node or to_node) {
                try out_connections.append(.{ .c = connection, .graph = graph });
            }
        }
    }

    fn buildGraph(
        self: *Self,
        allocator: std.mem.Allocator,
        graph: cetech1.cdb.ObjId,
        parent_node: ?cetech1.cdb.ObjId,
        node_prototype_map: *NodePrototypeMap,
        pivots: *PivotList,
        changed_nodes: *IdxSet,
        used_nodes: *NodeSet,
        node_map: *NodeMap,
        node_backward_map: *NodeMap,
        out_connections: *OutConnectionArray,
        root: bool,
    ) !void {
        const graph_r = self.db.readObj(graph).?;

        const connections = (try public.GraphType.readSubObjSet(self.db, graph_r, .connections, allocator)).?;
        defer allocator.free(connections);

        try self.addNodes(
            allocator,
            graph,
            node_prototype_map,
            pivots,
            changed_nodes,
            used_nodes,

            node_map,
            node_backward_map,
            out_connections,
            parent_node,
            root,
        );

        // Now scan for CallGraph node and build
        const nodes = (try public.GraphType.readSubObjSet(self.db, graph_r, .nodes, allocator)).?;
        defer allocator.free(nodes);
        for (nodes) |node| {
            const node_r = self.db.readObj(node).?;
            const type_hash = public.NodeType.f.getNodeTypeId(self.db, node_r);
            const iface = findNodeI(type_hash).?;
            _ = iface; // autofix

            if (type_hash.eql(call_graph_node_i.type_hash)) {
                const s = public.NodeType.readSubObj(self.db, node_r, .settings) orelse continue;
                const s_r = public.CallGraphNodeSettings.read(self.db, s).?;
                if (public.CallGraphNodeSettings.readSubObj(self.db, s_r, .graph)) |sub_graph| {
                    try self.buildGraph(
                        allocator,
                        sub_graph,
                        node,
                        node_prototype_map,
                        pivots,
                        changed_nodes,
                        used_nodes,

                        node_map,
                        node_backward_map,
                        out_connections,
                        false,
                    );
                }
            }
        }
    }

    fn collectNodePoints(self: *Self, outs: *NodeValueSet, node_map: *NodeMap, node_obj: cetech1.cdb.ObjId, pin: strid.StrId32) !void {
        if (node_map.get(.{ .obj = node_obj, .pin = pin })) |nexts| {
            var it = nexts.iterator();
            while (it.next()) |v| {
                const node_obj_r = self.db.readObj(v.key_ptr.obj).?;
                const node_type = public.NodeType.f.getNodeTypeId(self.db, node_obj_r);
                const from_subgraph = call_graph_node_i.type_hash.eql(node_type);

                if (from_subgraph) {
                    try self.collectNodePoints(outs, node_map, v.key_ptr.obj, v.key_ptr.pin);
                } else {
                    _ = try outs.add(v.key_ptr.*);
                }
            }
        }
    }

    pub fn buildVM(self: *Self, allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - build");
        defer zone_ctx.End();

        try self.clean();

        const graph_version = self.db.getVersion(self.graph_obj);
        self.graph_version = graph_version;

        var pivots = std.ArrayList(VMNodeIdx).init(allocator);
        defer pivots.deinit();

        var changed_nodes = IdxSet.init(allocator);
        defer changed_nodes.deinit();

        var deleted_nodes = NodeSet.init(allocator);
        defer deleted_nodes.deinit();

        var node_prototype_map = NodePrototypeMap.init(allocator);
        defer node_prototype_map.deinit();

        var graph_nodes_set = NodeSet.init(allocator);
        defer graph_nodes_set.deinit();

        var node_map = NodeMap.init(allocator);
        defer {
            for (node_map.values()) |*v| v.deinit();
            node_map.deinit();
        }

        var node_backward_map = NodeMap.init(allocator);
        defer {
            for (node_backward_map.values()) |*v| v.deinit();
            node_backward_map.deinit();
        }

        var out_connections = OutConnectionArray.init(allocator);
        defer out_connections.deinit();

        try self.buildGraph(
            allocator,
            self.graph_obj,
            null,
            &node_prototype_map,
            &pivots,
            &changed_nodes,
            &graph_nodes_set,
            &node_map,
            &node_backward_map,
            &out_connections,
            true,
        );

        const data_maps = self.vmnodes.items(.data_map);
        const outputs = self.vmnodes.items(.outputs);

        const ifaces = self.vmnodes.items(.iface);

        for (out_connections.items) |v| {
            const connection_r = self.db.readObj(v.c).?;
            var from_node_obj = public.ConnectionType.readRef(self.db, connection_r, .from_node).?;
            const orig_from_node_obj = from_node_obj;
            _ = orig_from_node_obj; // autofix
            const from_pin = public.ConnectionType.f.getFromPinId(self.db, connection_r);

            var to_node_obj = public.ConnectionType.readRef(self.db, connection_r, .to_node).?;
            const orig_to_node_obj = to_node_obj;
            _ = orig_to_node_obj; // autofix
            const to_pin = public.ConnectionType.f.getToPinId(self.db, connection_r);

            // Rewrite connection from prototype
            if (node_prototype_map.get(from_node_obj)) |node| {
                from_node_obj = node;
            }
            if (node_prototype_map.get(to_node_obj)) |node| {
                to_node_obj = node;
            }

            const from_node_obj_r = self.db.readObj(from_node_obj).?;
            const from_node_type = public.NodeType.f.getNodeTypeId(self.db, from_node_obj_r);
            const from_subgraph = call_graph_node_i.type_hash.eql(from_node_type);
            const from_inputs = graph_inputs_i.type_hash.eql(from_node_type);
            const from_node = !from_subgraph and !from_inputs;

            const to_node_obj_r = self.db.readObj(to_node_obj).?;
            const to_node_type = public.NodeType.f.getNodeTypeId(self.db, to_node_obj_r);
            const to_subgraph = call_graph_node_i.type_hash.eql(to_node_type);
            const to_outputs = graph_outputs_i.type_hash.eql(to_node_type);
            const to_node = !to_subgraph and !to_outputs;

            if (!to_node) {
                var outs = NodeValueSet.init(allocator);
                defer outs.deinit();

                try self.collectNodePoints(&outs, &node_map, to_node_obj, to_pin);

                const node_from_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = from_node_obj });

                var it = outs.iterator();
                while (it.next()) |vv| {
                    const node_to_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = vv.key_ptr.obj });

                    const pin_type: strid.StrId32 = blk: {
                        for (outputs[node_from_idx.?]) |pin| {
                            if (pin.pin_hash.eql(from_pin)) break :blk pin.type_hash;
                        }
                        break :blk .{ .id = 0 };
                    };

                    try self.connection.append(.{
                        .from = .{
                            .node = node_from_idx.?,
                            .pin = from_pin,
                            .pin_type = pin_type,
                            .pin_idx = data_maps[node_from_idx.?].get(from_pin).?,
                        },
                        .to = .{
                            .node = node_to_idx.?,
                            .pin = vv.key_ptr.pin,
                            .pin_type = pin_type,
                            .pin_idx = data_maps[node_to_idx.?].get(vv.key_ptr.pin).?,
                        },
                    });
                }
            } else if (!from_node) {
                var outs = NodeValueSet.init(allocator);
                defer outs.deinit();

                try self.collectNodePoints(&outs, &node_backward_map, from_node_obj, from_pin);

                const node_to_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = to_node_obj });

                var it = outs.iterator();
                while (it.next()) |vv| {
                    const node_from_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = vv.key_ptr.obj });

                    const pin_type: strid.StrId32 = blk: {
                        for (outputs[node_from_idx.?]) |pin| {
                            if (pin.pin_hash.eql(from_pin)) break :blk pin.type_hash;
                        }
                        break :blk .{ .id = 0 };
                    };

                    try self.connection.append(.{
                        .from = .{
                            .node = node_from_idx.?,
                            .pin = vv.key_ptr.pin,
                            .pin_type = pin_type,
                            .pin_idx = data_maps[node_from_idx.?].get(vv.key_ptr.pin).?,
                        },
                        .to = .{
                            .node = node_to_idx.?,
                            .pin = to_pin,
                            .pin_type = pin_type,
                            .pin_idx = data_maps[node_to_idx.?].get(to_pin).?,
                        },
                    });
                }
            } else {
                const node_from_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = from_node_obj });
                const node_to_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = to_node_obj });

                const pin_type: strid.StrId32 = blk: {
                    for (outputs[node_from_idx.?]) |pin| {
                        if (pin.pin_hash.eql(from_pin)) break :blk pin.type_hash;
                    }
                    break :blk .{ .id = 0 };
                };

                try self.connection.append(.{
                    .from = .{
                        .node = node_from_idx.?,
                        .pin = from_pin,
                        .pin_type = pin_type,
                        .pin_idx = data_maps[node_from_idx.?].get(from_pin).?,
                    },
                    .to = .{
                        .node = node_to_idx.?,
                        .pin = to_pin,
                        .pin_type = pin_type,
                        .pin_idx = data_maps[node_to_idx.?].get(to_pin).?,
                    },
                });
            }
        }

        //Find deleted nodes
        for (self.node_idx_map.keys(), self.node_idx_map.values()) |k, v| {
            if (graph_nodes_set.contains(k)) continue;
            log.debug("Delete node: {any} {any}", .{ k, v });
            _ = try deleted_nodes.add(k);
        }

        const root_graph_r = self.db.readObj(self.graph_obj).?;

        // Interafces
        if (public.GraphType.readSubObj(self.db, root_graph_r, .interface)) |interface_obj| {
            _ = interface_obj; // autofix
            self.inputs = try graph_inputs_i.getOutputPins(self.allocator, self.db, self.graph_obj, .{});
            self.outputs = try graph_outputs_i.getInputPins(self.allocator, self.db, self.graph_obj, .{});

            self.input_blob_size = try GraphVM.computePinSize(self.inputs.?);
            self.output_blob_size = try GraphVM.computePinSize(self.outputs.?);
        }

        // Plan pivots.
        var dag = cetech1.dag.DAG(VMNodeIdx).init(allocator);
        defer dag.deinit();
        const has_flow_outs = self.vmnodes.items(.has_flow_out);

        for (pivots.items) |pivot| {
            try dag.reset();
            const pivot_vmnode = pivot;

            if (has_flow_outs[pivot_vmnode]) {
                try dag.add(pivot, &.{});
                for (self.connection.items) |pair| {
                    // only conection from this node
                    if (pair.from.node != pivot) continue;

                    // Only flow
                    if (!pair.from.pin_type.eql(public.PinTypes.Flow)) continue;

                    try self.flowDag(allocator, &dag, pair.to.node);
                }
            } else {
                try self.inputDag(allocator, &dag, pivot, true);
            }

            try dag.build_all();

            try self.node_plan.put(pivot, try self.allocator.dupe(VMNodeIdx, dag.output.keys()));

            log.debug("Plan for pivot \"{s}\":", .{ifaces[pivot_vmnode].name});
            for (dag.output.keys()) |node| {
                const vmnode = node;
                log.debug("\t - {s}", .{ifaces[vmnode].name});
            }
        }

        try self.writePlanD2(allocator);

        // Rebuild exist instances.
        if (self.instance_set.count() != 0) {
            const ARGS = struct {
                changed_nodes: *const IdxSet,
                deleted_nodes: *const NodeSet,
            };
            if (try BatchWorkload(
                *VMInstance,
                ARGS,
                64,
                allocator,
                ARGS{
                    .changed_nodes = &changed_nodes,
                    .deleted_nodes = &deleted_nodes,
                },
                self.instance_set.keys(),
                struct {
                    pub fn createTask(args: ARGS, batch_id: usize, batch_size: usize, items: []const *VMInstance) RebuildTask {
                        _ = batch_id;
                        _ = batch_size;

                        return RebuildTask{
                            .instances = items,
                            .changed_nodes = args.changed_nodes,
                            .deleted_nodes = args.deleted_nodes,
                        };
                    }
                },
            )) |t| {
                task.api.wait(t);
            }
        }

        var deleted_it = deleted_nodes.iterator();
        while (deleted_it.next()) |entry| {
            const node = entry.key_ptr.*;
            const idx = self.node_idx_map.get(node).?;

            var vmnode = self.vmnodes.get(idx);
            vmnode.deinit();

            _ = try self.free_idx.add(idx);
            _ = self.node_idx_map.swapRemove(node);
        }
    }

    pub fn buildInstances(self: *Self, allocator: std.mem.Allocator, instances: []const *VMInstance, deleted_nodes: ?*const NodeSet, changed_nodes: ?*const IdxSet) !void {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - Instance build many");
        defer zone_ctx.End();

        const ifaces = self.vmnodes.items(.iface);
        const vmnode_inputs = self.vmnodes.items(.inputs);
        const vmnode_outputs = self.vmnodes.items(.outputs);
        const vmnode_input_blob_size = self.vmnodes.items(.input_blob_size);
        const vmnode_output_blob_size = self.vmnodes.items(.output_blob_size);

        for (instances) |vminstance| {
            try vminstance.clean();

            const data_alloc = vminstance.node_arena.allocator(); //dat_fba.allocator();
            const state_alloc = vminstance.node_arena.allocator(); //state_fba.allocator();

            // Graph input pins
            if (self.inputs) |inputs| {
                try vminstance.graph_in.fromPins(vminstance.allocator, self.input_blob_size, inputs);
            }

            // Graph outputs pins
            if (self.outputs) |outputs| {
                try vminstance.graph_out.fromPins(vminstance.allocator, self.output_blob_size, outputs);
            }

            // Init nodes
            {
                try vminstance.nodes.resize(vminstance.allocator, self.vmnodes.len);
                try vminstance.node_idx_map.ensureTotalCapacity(self.node_idx_map.count());

                for (self.node_idx_map.keys(), self.node_idx_map.values()) |k, node_idx| {
                    const iface: *const public.GraphNodeI = ifaces[node_idx];

                    const exist_node = vminstance.node_idx_map.get(k);
                    const new = exist_node == null;
                    const changed = if (!new) if (changed_nodes) |ch| ch.contains(exist_node.?) else false else false;

                    var state: ?*anyopaque = null;

                    const states = vminstance.nodes.items(.state);
                    const evals = vminstance.nodes.items(.eval);

                    if (new) {
                        if (iface.state_size != 0) {
                            const state_data = try state_alloc.alloc(u8, iface.state_size);
                            state = std.mem.alignPointer(state_data.ptr, iface.state_align);
                            try iface.create.?(allocator, state.?, self.db, k.node, false);
                        }

                        const new_node_idx = node_idx;
                        //std.debug.assert(new_node_idx == node_idx);

                        vminstance.nodes.set(node_idx, try InstanceNode.init(
                            data_alloc,
                            state,
                            vmnode_inputs[new_node_idx],
                            vmnode_outputs[new_node_idx],
                            vmnode_input_blob_size[new_node_idx],
                            vmnode_output_blob_size[new_node_idx],
                            new_node_idx,
                        ));

                        vminstance.node_idx_map.putAssumeCapacity(k, new_node_idx);
                    }

                    if (!new and changed) {
                        if (iface.state_size != 0) {
                            state = states[node_idx];

                            if (iface.destroy) |destroy| {
                                try destroy(state.?, self.db, true);
                            }

                            try iface.create.?(allocator, state.?, self.db, k.node, true);
                        }

                        evals[node_idx] = false;
                    }
                }

                if (deleted_nodes) |deleted| {
                    var it = deleted.iterator();
                    while (it.next()) |entry| {
                        const idx = vminstance.node_idx_map.get(entry.key_ptr.*) orelse continue;

                        var node = vminstance.nodes.get(idx);
                        node.deinit();

                        _ = vminstance.node_idx_map.swapRemove(entry.key_ptr.*);
                    }
                }
            }

            // Wire nodes
            // Set input slice in input node to output slice of output node
            // With this is not needeed to propagate value after exec because input is linked to output.
            {
                var in_datas = vminstance.nodes.items(.in_data);
                var out_datas = vminstance.nodes.items(.out_data);
                for (self.connection.items) |pair| {
                    const from_node_idx = pair.from.node;
                    const to_node_idx = pair.to.node;

                    const from_pin_idx = pair.from.pin_idx;
                    const to_pin_idx = pair.to.pin_idx;

                    in_datas[to_node_idx].data.?[to_pin_idx] = out_datas[from_node_idx].data_slices.?[from_pin_idx];
                    in_datas[to_node_idx].validity_hash.?[to_pin_idx] = &out_datas[from_node_idx].validity_hash.?[from_pin_idx];
                    in_datas[to_node_idx].types.?[to_pin_idx] = out_datas[from_node_idx].types.?[from_pin_idx];
                }
            }
        }
    }

    pub fn buildVMNodes(self: *Self, node_idx: VMNodeIdx, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) !void {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - Build VM nodes");
        defer zone_ctx.End();

        var vm_node = self.vmnodes.get(node_idx);
        const iface = vm_node.iface;

        vm_node.inputs = try iface.getInputPins(self.allocator, db, graph_obj, node_obj);
        vm_node.input_count = vm_node.inputs.len;
        vm_node.has_flow = vm_node.inputs.len != 0 and vm_node.inputs[0].type_hash.eql(public.PinTypes.Flow);
        vm_node.input_blob_size = try vm_node.getInputPinsSize(vm_node.inputs);

        const outputs = try iface.getOutputPins(self.allocator, db, graph_obj, node_obj);
        vm_node.outputs = outputs;
        vm_node.output_count = outputs.len;
        vm_node.has_flow_out = vm_node.outputs.len != 0 and vm_node.outputs[0].type_hash.eql(public.PinTypes.Flow);
        vm_node.output_blob_size = try vm_node.getOutputPinsSize(outputs);

        self.vmnodes.set(node_idx, vm_node);
    }

    fn flowDag(self: *Self, allocator: std.mem.Allocator, dag: *cetech1.dag.DAG(VMNodeIdx), node: VMNodeIdx) !void {
        var depends = std.ArrayList(VMNodeIdx).init(allocator);
        defer depends.deinit();

        for (self.connection.items) |pair| {
            // only conection to this node
            if (pair.to.node != node) continue;
            try depends.append(pair.from.node);
            try dag.add(pair.from.node, &.{});
        }

        try dag.add(node, depends.items);

        for (self.connection.items) |pair| {
            // Follow only flow
            if (!pair.from.pin_type.eql(public.PinTypes.Flow)) {
                continue;
            }

            // only conection from this node
            if (pair.from.node != node) continue;
            try self.flowDag(allocator, dag, pair.to.node);
        }
    }

    fn inputDag(self: *Self, allocator: std.mem.Allocator, dag: *cetech1.dag.DAG(VMNodeIdx), node: VMNodeIdx, root: bool) !void {
        _ = root; // autofix
        var depends = std.ArrayList(VMNodeIdx).init(allocator);
        defer depends.deinit();

        for (self.connection.items) |pair| {
            // only conection to this node
            if (pair.to.node != node) continue;

            try depends.append(pair.from.node);
            try dag.add(pair.from.node, &.{});
            try self.inputDag(allocator, dag, pair.from.node, false);
        }

        try dag.add(node, depends.items);
    }

    pub fn createInstances(self: *Self, allocator: std.mem.Allocator, count: usize) ![]*VMInstance {
        const instances = try allocator.alloc(*VMInstance, count);

        try _instance_pool.createMany(instances, count);

        {
            // TODO: remove lock
            vm_lock.lock();
            defer vm_lock.unlock();
            try self.instance_set.ensureUnusedCapacity(count);
        }

        for (0..count) |idx| {
            instances[idx].* = VMInstance.init(self.allocator, self);
            self.instance_set.putAssumeCapacity(instances[idx], {});
        }

        return instances;
    }

    pub fn destroyInstance(self: *Self, instance: *VMInstance) void {
        instance.deinit();
        _ = self.instance_set.swapRemove(instance);
        _instance_pool.destroy(instance);
    }

    fn executeNodesMany(self: *Self, allocator: std.mem.Allocator, instances: []const public.GraphInstance, node_type: strid.StrId32) !void {
        var zone_ctx = profiler_private.ztracy.Zone(@src());
        defer zone_ctx.End();

        const ifaces = self.vmnodes.items(.iface);
        const settings = self.vmnodes.items(.settings);
        const inputs = self.vmnodes.items(.inputs);
        const outputs = self.vmnodes.items(.outputs);
        const has_flows = self.vmnodes.items(.has_flow);

        if (self.findNodeByType(node_type)) |event_nodes| {
            for (instances) |instance| {
                //if (!instance.isValid()) continue;

                var ints: *VMInstance = @alignCast(@ptrCast(instance.inst));

                const in_datas = ints.nodes.items(.in_data);
                const out_datas = ints.nodes.items(.out_data);
                const last_inputs_validity_hashs = ints.nodes.items(.last_inputs_validity_hash);
                const states = ints.nodes.items(.state);
                const evals = ints.nodes.items(.eval);

                for (event_nodes) |event_node_idx| {
                    const plan = self.node_plan.get(event_node_idx).?;
                    for (plan) |node_idx| {
                        const iface: *const public.GraphNodeI = ifaces[node_idx];

                        const in_pins = in_datas[node_idx].toPins();
                        const out_pins = out_datas[node_idx].toPins();

                        var node_inputs_changed = false;
                        if (in_pins.validity_hash) |validity_hash| {
                            for (0..last_inputs_validity_hashs[node_idx].len) |pin_idx| {
                                if (validity_hash[pin_idx] == null) continue;

                                const vh = validity_hash[pin_idx].?.*;
                                if (last_inputs_validity_hashs[node_idx][pin_idx] != vh) {
                                    last_inputs_validity_hashs[node_idx][pin_idx] = vh;
                                    node_inputs_changed = true;
                                }
                            }
                        }

                        // If node has sidefect we must eval it every time
                        if (iface.sidefect) {
                            node_inputs_changed = true;
                        }

                        // If node has input flow check if its True.
                        // Input flow node is always 0 idx
                        if (has_flows[node_idx]) {
                            if (!in_pins.read(bool, 0).?[1]) continue;
                        }

                        if (!evals[node_idx] or node_inputs_changed) {
                            var zone_exec_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - execute one node");
                            defer zone_exec_ctx.End();

                            try iface.execute(
                                .{
                                    .allocator = allocator,
                                    .db = self.db,
                                    .settings = settings[node_idx],
                                    .state = states[node_idx],
                                    .graph = self.graph_obj,
                                    .instance = instance,
                                    .outputs = outputs[node_idx],
                                    .inputs = inputs[node_idx],
                                },
                                in_pins,
                                out_pins,
                            );

                            evals[node_idx] = true;
                        }
                    }
                }
            }
        }
    }

    pub fn getNodeStateMany(self: *Self, results: []*anyopaque, containers: []const public.GraphInstance, node_type: strid.StrId32) !void {
        var zone_ctx = profiler_private.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (self.findNodeByType(node_type)) |nodes| {
            for (containers, 0..) |container, idx| {
                if (!container.isValid()) continue;
                var c: *VMInstance = @alignCast(@ptrCast(container.inst));
                const states = c.nodes.items(.state);
                const node_idx = nodes[0];
                if (states[node_idx]) |state| {
                    results[idx] = state;
                }
            }
        }
    }

    fn writePlanD2(self: Self, allocator: std.mem.Allocator) !void {
        if (assetdb_private._assetroot_fs.asset_root_path == null) return;

        var root_dir = try std.fs.cwd().openDir(assetdb_private._assetroot_fs.asset_root_path.?, .{});
        defer root_dir.close();

        const asset_obj = assetdb_private.api.getAssetForObj(self.graph_obj).?;
        const asset_obj_r = cetech1.assetdb.Asset.read(self.db, asset_obj).?;
        const name = cetech1.assetdb.Asset.readStr(self.db, asset_obj_r, .Name).?;

        const filename = try std.fmt.allocPrint(allocator, "{s}/graph_{s}.md", .{ cetech1.assetdb.CT_TEMP_FOLDER, name });
        defer allocator.free(filename);

        var d2_file = try root_dir.createFile(filename, .{});
        defer d2_file.close();

        var writer = d2_file.writer();

        const ifaces = self.vmnodes.items(.iface);
        const node_objs = self.vmnodes.items(.node_obj);

        for (self.node_plan.keys(), self.node_plan.values()) |k, v| {
            const plan_node = k;
            try writer.print("# Plan for {s}\n\n", .{ifaces[plan_node].name});

            // write header
            try writer.print("```d2\n", .{});
            _ = try writer.write("vars: {d2-config: {layout-engine: elk}}\n\n");

            for (v) |node| {
                try writer.print("{s}: {s}\n", .{ try assetdb_private.api.getOrCreateUuid(node_objs[node]), ifaces[node].name });
            }

            try writer.print("\n", .{});

            for (0..v.len - 1) |idx| {
                const node = v[idx];
                const nex_node = v[idx + 1];

                try writer.print("{s}->{s}\n", .{ try assetdb_private.api.getOrCreateUuid(node_objs[node]), try assetdb_private.api.getOrCreateUuid(node_objs[nex_node]) });
            }

            try writer.print("```\n", .{});
            try writer.print("\n", .{});
        }
    }
};

pub const api = public.GraphVMApi{
    .findNodeI = findNodeI,
    .findValueTypeI = findValueTypeI,
    .findValueTypeIByCdb = findValueTypeIByCdb,

    .isOutputPin = isOutputPin,
    .isInputPin = isInputPin,
    .getInputPin = getInputPin,
    .getOutputPin = getOutputPin,
    .getTypeColor = getTypeColor,
    .createInstance = createInstance,
    .createInstances = createInstances,
    .destroyInstance = destroyInstance,
    .executeNode = executeNodes,
    .buildInstances = buildInstances,
    .needCompile = needCompile,
    .compile = compile,
    .createCdbNode = createCdbNode,
    .getNodeStateFn = getNodeState,

    .setInstanceContext = setInstanceContext,
    .getContext = getInstanceContext,
    .removeContext = removeInstanceContext,
    .getInputPins = getInputPins,
    .getOutputPins = getOutputPins,
};

var _allocator: std.mem.Allocator = undefined;
var _vm_pool: VMPool = undefined;
var _vm_map: VMMap = undefined;

var _instance_pool: ContainerPool = undefined;

var _nodetype_i_version: cetech1.apidb.InterfaceVersion = 0;
var _valuetype_i_version: cetech1.apidb.InterfaceVersion = 0;

var _node_type_iface_map: NodeTypeIfaceMap = undefined;
var _value_type_iface_map: ValueTypeIfaceMap = undefined;
var _value_type_iface_cdb_map: ValueTypeIfaceMap = undefined;

var _string_intern: cetech1.mem.StringInternWithLock = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _vm_map = VMMap.init(allocator);
    _vm_pool = try VMPool.initPreheated(allocator, 1024);

    _instance_pool = try ContainerPool.initPreheated(allocator, 1024);

    _node_type_iface_map = NodeTypeIfaceMap.init(allocator);

    _value_type_iface_map = ValueTypeIfaceMap.init(allocator);
    _value_type_iface_cdb_map = ValueTypeIfaceMap.init(allocator);
    _string_intern = cetech1.mem.StringInternWithLock.init(allocator);
}

pub fn deinit() void {
    for (_vm_map.values()) |value| {
        value.deinit();
    }

    _instance_pool.deinit();
    _vm_map.deinit();
    _vm_pool.deinit();

    _node_type_iface_map.deinit();
    _value_type_iface_map.deinit();
    _value_type_iface_cdb_map.deinit();
    _string_intern.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.GraphVMApi, &api);
    try apidb.api.implOrRemove(module_name, cetech1.cdb.CreateTypesI, &create_cdb_types_i, true);
    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, true);

    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &event_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &event_tick_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &event_shutdown_node_i, true);

    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &print_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &const_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &graph_inputs_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &graph_outputs_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &call_graph_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &random_f32_node_i, true);

    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &culling_volume_node_i, true);

    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &flow_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &i32_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &f32_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &i64_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &f64_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &bool_value_type_i, true);
}

// CDB
var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cetech1.cdb.Db) !void {

        // GraphNodeType
        {
            _ = try db.addType(
                public.GraphType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.GraphType.propIdx(.name), .name = "name", .type = .STR },
                    .{ .prop_idx = public.GraphType.propIdx(.nodes), .name = "nodes", .type = .SUBOBJECT_SET, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.groups), .name = "groups", .type = .SUBOBJECT_SET, .type_hash = public.GroupType.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.connections), .name = "connections", .type = .SUBOBJECT_SET, .type_hash = public.ConnectionType.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.interface), .name = "interface", .type = .SUBOBJECT, .type_hash = public.Interface.type_hash },
                },
            );
        }

        // GraphNodeType
        {
            _ = try db.addType(
                public.NodeType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.NodeType.propIdx(.node_type), .name = "node_type", .type = .STR },
                    .{ .prop_idx = public.NodeType.propIdx(.settings), .name = "settings", .type = .SUBOBJECT },
                    .{ .prop_idx = public.NodeType.propIdx(.pos_x), .name = "pos_x", .type = .F32 },
                    .{ .prop_idx = public.NodeType.propIdx(.pos_y), .name = "pos_y", .type = .F32 },
                },
            );
        }

        // GroupType
        {
            _ = try db.addType(
                public.GroupType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.GroupType.propIdx(.title), .name = "title", .type = .STR },
                    .{ .prop_idx = public.GroupType.propIdx(.color), .name = "color", .type = .SUBOBJECT, .type_hash = cdb_types.Color4f.type_hash },
                    .{ .prop_idx = public.GroupType.propIdx(.pos_x), .name = "pos_x", .type = .F32 },
                    .{ .prop_idx = public.GroupType.propIdx(.pos_y), .name = "pos_y", .type = .F32 },
                    .{ .prop_idx = public.GroupType.propIdx(.size_x), .name = "size_x", .type = .F32 },
                    .{ .prop_idx = public.GroupType.propIdx(.size_y), .name = "size_y", .type = .F32 },
                },
            );
        }

        // GraphConnectionType
        {
            _ = try db.addType(
                public.ConnectionType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.ConnectionType.propIdx(.from_node), .name = "from_node", .type = .REFERENCE, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.ConnectionType.propIdx(.to_node), .name = "to_node", .type = .REFERENCE, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.ConnectionType.propIdx(.from_pin), .name = "from_pin", .type = .STR },
                    .{ .prop_idx = public.ConnectionType.propIdx(.to_pin), .name = "to_pin", .type = .STR },
                },
            );
        }

        // Interface
        {
            _ = try db.addType(
                public.Interface.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.Interface.propIdx(.inputs), .name = "inputs", .type = .SUBOBJECT_SET, .type_hash = public.InterfaceInput.type_hash },
                    .{ .prop_idx = public.Interface.propIdx(.outputs), .name = "outputs", .type = .SUBOBJECT_SET, .type_hash = public.InterfaceOutput.type_hash },
                },
            );
        }

        // InterfaceInput
        {
            _ = try db.addType(
                public.InterfaceInput.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.InterfaceInput.propIdx(.name), .name = "name", .type = .STR },
                    .{ .prop_idx = public.InterfaceInput.propIdx(.value), .name = "value", .type = .SUBOBJECT },
                },
            );
        }

        // InterfaceOutput
        {
            _ = try db.addType(
                public.InterfaceOutput.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.InterfaceOutput.propIdx(.name), .name = "name", .type = .STR },
                    .{ .prop_idx = public.InterfaceOutput.propIdx(.value), .name = "value", .type = .SUBOBJECT },
                },
            );
        }

        // CallGraphNodeSettings
        {
            _ = try db.addType(
                public.CallGraphNodeSettings.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.CallGraphNodeSettings.propIdx(.graph), .name = "graph", .type = .SUBOBJECT, .type_hash = public.GraphType.type_hash },
                },
            );
        }

        // ConstNodeSettings
        {
            _ = try db.addType(
                public.ConstNodeSettings.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.ConstNodeSettings.propIdx(.value), .name = "value", .type = .SUBOBJECT },
                },
            );
        }

        // RandomF32NodeSettings
        {
            _ = try db.addType(
                public.RandomF32NodeSettings.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.RandomF32NodeSettings.propIdx(.min), .name = "min", .type = .F32 },
                    .{ .prop_idx = public.RandomF32NodeSettings.propIdx(.max), .name = "max", .type = .F32 },
                },
            );
        }

        // flowType
        {
            _ = try db.addType(
                public.flowType.name,
                &[_]cetech1.cdb.PropDef{},
            );
        }

        // TODO:  Move

        // value i32
        {
            _ = try db.addType(
                public.i32Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.i32Type.propIdx(.value), .name = "value", .type = .I32 },
                },
            );
        }

        // value f32
        {
            _ = try db.addType(
                public.f32Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.f32Type.propIdx(.value), .name = "value", .type = .F32 },
                },
            );
        }

        // value i64
        {
            _ = try db.addType(
                public.i64Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.i64Type.propIdx(.value), .name = "value", .type = .I64 },
                },
            );
        }

        // value f64
        {
            _ = try db.addType(
                public.f64Type.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.f64Type.propIdx(.value), .name = "value", .type = .F64 },
                },
            );
        }

        // value bool
        {
            _ = try db.addType(
                public.BoolType.name,
                &[_]cetech1.cdb.PropDef{
                    .{ .prop_idx = public.BoolType.propIdx(.value), .name = "value", .type = .BOOL },
                },
            );
        }
    }
});

pub fn createCdbNode(db: cetech1.cdb.Db, type_hash: strid.StrId32, pos: ?[2]f32) !cetech1.cdb.ObjId {
    const iface = findNodeI(type_hash).?;
    const node = try public.NodeType.createObject(db);

    const node_w = public.NodeType.write(db, node).?;
    try public.NodeType.setStr(db, node_w, .node_type, iface.type_name);

    if (!iface.settings_type.isEmpty()) {
        const settings = try db.createObject(db.getTypeIdx(iface.settings_type).?);

        const settings_w = db.writeObj(settings).?;
        try public.NodeType.setSubObj(db, node_w, .settings, settings_w);
        try db.writeCommit(settings_w);
    }

    if (pos) |p| {
        public.NodeType.setValue(db, f32, node_w, .pos_x, p[0]);
        public.NodeType.setValue(db, f32, node_w, .pos_y, p[1]);
    }

    try db.writeCommit(node_w);
    return node;
}

pub fn findNodeI(type_hash: strid.StrId32) ?*const public.GraphNodeI {
    return _node_type_iface_map.get(type_hash);
}

pub fn findValueTypeI(type_hash: strid.StrId32) ?*const public.GraphValueTypeI {
    return _value_type_iface_map.get(type_hash);
}

pub fn findValueTypeIByCdb(type_hash: strid.StrId32) ?*const public.GraphValueTypeI {
    return _value_type_iface_cdb_map.get(type_hash);
}

fn isInputPin(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) !bool {
    const iface = findNodeI(type_hash) orelse return false;
    const inputs = try iface.getInputPins(allocator, db, graph_obj, node_obj);
    defer allocator.free(inputs);
    for (inputs) |input| {
        if (input.pin_hash.eql(pin_hash)) return true;
    }
    return false;
}

fn getInputPin(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) !?public.NodePin {
    const iface = findNodeI(type_hash) orelse return null;
    const inputs = try iface.getInputPins(allocator, db, graph_obj, node_obj);
    defer allocator.free(inputs);
    for (inputs) |input| {
        if (input.pin_hash.eql(pin_hash)) return input;
    }

    return null;
}

fn isOutputPin(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) !bool {
    const iface = findNodeI(type_hash) orelse return false;
    const outputs = try iface.getOutputPins(allocator, db, graph_obj, node_obj);
    defer allocator.free(outputs);
    for (outputs) |output| {
        if (output.pin_hash.eql(pin_hash)) return true;
    }
    return false;
}

fn getOutputPin(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) !?public.NodePin {
    const iface = findNodeI(type_hash) orelse return null;
    const outputs = try iface.getOutputPins(allocator, db, graph_obj, node_obj);
    defer allocator.free(outputs);
    for (outputs) |output| {
        if (output.pin_hash.eql(pin_hash)) return output;
    }
    return null;
}

fn getTypeColor(type_hash: strid.StrId32) [4]f32 {
    //TODO: from iface or random by hash?
    if (public.PinTypes.F32.eql(type_hash)) return .{ 0.0, 0.5, 0.0, 1.0 };
    if (public.PinTypes.F64.eql(type_hash)) return .{ 0.0, 0.5, 0.0, 1.0 };
    if (public.PinTypes.I32.eql(type_hash)) return .{ 0.2, 0.4, 1.0, 1.0 };
    if (public.PinTypes.I64.eql(type_hash)) return .{ 0.2, 0.4, 1.0, 1.0 };
    if (public.PinTypes.Bool.eql(type_hash)) return .{ 1.0, 0.4, 0.4, 1.0 };
    if (public.PinTypes.GENERIC.eql(type_hash)) return .{ 0.8, 0.0, 0.8, 1.0 };
    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn createVM(db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId) !*GraphVM {
    const vm = try _vm_pool.create();
    vm.* = GraphVM.init(_allocator, db, graph);
    try _vm_map.put(graph, vm);

    const alloc = try tempalloc.api.create();
    defer tempalloc.api.destroy(alloc);

    try vm.buildVM(alloc);

    return @ptrCast(vm);
}

fn destroyVM(vm: *GraphVM) void {
    vm.deinit();
    _ = _vm_map.swapRemove(vm.graph_obj);
    _vm_pool.destroy(vm);
}

var vm_lock = std.Thread.Mutex{};

fn createInstance(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId) !public.GraphInstance {
    _ = db; // autofix

    var vm = _vm_map.get(graph).?;

    const containers = try vm.createInstances(allocator, 1);
    defer allocator.free(containers);

    return .{
        .graph = graph,
        .inst = containers[0],
    };
}

fn createInstances(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId, count: usize) ![]public.GraphInstance {
    _ = db; // autofix

    var vm = _vm_map.get(graph).?;

    const containers = try vm.createInstances(allocator, count);
    defer allocator.free(containers);

    var result = try allocator.alloc(public.GraphInstance, count);

    for (0..count) |idx| result[idx] = .{ .graph = graph, .inst = containers[idx] };

    return result;
}

fn destroyInstance(vmc: public.GraphInstance) void {
    var vm = _vm_map.get(vmc.graph) orelse return; //TODO: ?
    vm.destroyInstance(@alignCast(@ptrCast(vmc.inst)));
}

const executeNodesTask = struct {
    instances: []const public.GraphInstance,
    event_hash: strid.StrId32,

    pub fn exec(self: *const @This()) !void {
        const c0: *VMInstance = @alignCast(@ptrCast(self.instances[0].inst));
        const vm = c0.vm;
        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);
        try vm.executeNodesMany(alloc, self.instances, self.event_hash);
    }
};

const buildInstancesTask = struct {
    instances: []const public.GraphInstance,

    pub fn exec(self: *const @This()) !void {
        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);

        var instatnces = try alloc.alloc(*VMInstance, self.instances.len);
        defer alloc.free(instatnces);

        for (self.instances, 0..) |inst, idx| {
            instatnces[idx] = @alignCast(@ptrCast(inst.inst));
        }

        const c0: *VMInstance = @alignCast(@ptrCast(self.instances[0].inst));
        var vm = c0.vm;

        try vm.buildInstances(alloc, instatnces, null, null);
    }
};

fn BatchWorkload(
    comptime T: type,
    comptime ARGS: type,
    comptime BATCH_SIZE: usize,
    allocator: std.mem.Allocator,
    args: ARGS,
    items: []const T,
    comptime CREATE_FCE: type,
) !?cetech1.task.TaskID {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "BatchedWork");
    defer zone_ctx.End();

    const items_count = items.len;

    if (items.len <= BATCH_SIZE) {
        const t = CREATE_FCE.createTask(args, 0, items.len, items);
        try t.exec();
        return null;
    }

    const batch_count = items_count / BATCH_SIZE;
    const batch_rest = items_count - (batch_count * BATCH_SIZE);

    var tasks = std.ArrayList(cetech1.task.TaskID).init(allocator);
    defer tasks.deinit();

    for (0..batch_count - 1) |batch_id| {
        const task_id = try task.api.schedule(
            cetech1.task.TaskID.none,
            CREATE_FCE.createTask(args, batch_id, BATCH_SIZE, items[batch_id * BATCH_SIZE .. (batch_id * BATCH_SIZE) + BATCH_SIZE]),
        );
        try tasks.append(task_id);
    }

    const last_batch_id = batch_count - 1;
    const task_id = try task.api.schedule(
        cetech1.task.TaskID.none,
        CREATE_FCE.createTask(args, last_batch_id, BATCH_SIZE, items[last_batch_id * BATCH_SIZE .. (last_batch_id * BATCH_SIZE) + (BATCH_SIZE + batch_rest)]),
    );
    try tasks.append(task_id);

    return if (tasks.items.len == 0) null else try task.api.combine(tasks.items);
}

fn executeNodes(allocator: std.mem.Allocator, instances: []const public.GraphInstance, event_hash: strid.StrId32) !void {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - execute nodes");
    defer zone_ctx.End();

    if (instances.len == 1) {
        const c0: *VMInstance = @alignCast(@ptrCast(instances[0].inst));
        const vm = c0.vm;
        try vm.executeNodesMany(allocator, instances, event_hash);
        return;
    }

    const ARGS = struct {
        event_hash: strid.StrId32,
    };

    if (try BatchWorkload(
        public.GraphInstance,
        ARGS,
        64,
        allocator,
        ARGS{
            .event_hash = event_hash,
        },
        instances,
        struct {
            pub fn createTask(args: ARGS, batch_id: usize, batch_size: usize, items: []const public.GraphInstance) executeNodesTask {
                _ = batch_id;
                _ = batch_size;

                return executeNodesTask{
                    .instances = items,
                    .event_hash = args.event_hash,
                };
            }
        },
    )) |t| {
        task.api.wait(t);
    }
}

fn buildInstances(containers: []const public.GraphInstance) !void {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - buildInstances");
    defer zone_ctx.End();

    const alloc = try tempalloc.api.create();
    defer tempalloc.api.destroy(alloc);

    if (containers.len == 1) {
        const c0: *VMInstance = @alignCast(@ptrCast(containers[0].inst));
        try c0.vm.buildInstances(alloc, &.{c0}, null, null);
        return;
    }

    const ARGS = struct {};

    if (try BatchWorkload(
        public.GraphInstance,
        ARGS,
        32,
        alloc,
        ARGS{},
        containers,
        struct {
            pub fn createTask(args: ARGS, batch_id: usize, batch_size: usize, items: []const public.GraphInstance) buildInstancesTask {
                _ = batch_id;
                _ = batch_size;
                _ = args;

                return buildInstancesTask{
                    .instances = items,
                };
            }
        },
    )) |t| {
        task.api.wait(t);
    }
}

fn needCompile(graph: cetech1.cdb.ObjId) bool {
    var vm = _vm_map.get(graph) orelse return false;
    return vm.graph_version != vm.db.getVersion(graph);
}
fn compile(allocator: std.mem.Allocator, graph: cetech1.cdb.ObjId) !void {
    var vm = _vm_map.get(graph).?;
    try vm.buildVM(allocator);
}

const getNodeStateTask = struct {
    containers: []const public.GraphInstance,
    node_type: strid.StrId32,
    output: []*anyopaque,
    pub fn exec(self: *const @This()) !void {
        var c: *VMInstance = @alignCast(@ptrCast(self.containers[0].inst));
        try c.vm.getNodeStateMany(self.output, self.containers, self.node_type);
    }
};

pub fn getNodeState(allocator: std.mem.Allocator, containers: []const public.GraphInstance, node_type: strid.StrId32) ![]*anyopaque {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - get node state");
    defer zone_ctx.End();

    var results = try std.ArrayList(*anyopaque).initCapacity(allocator, containers.len);
    try results.resize(containers.len);

    const alloc = try tempalloc.api.create();
    defer tempalloc.api.destroy(alloc);

    if (containers.len == 1) {
        var c: *VMInstance = @alignCast(@ptrCast(containers[0].inst));
        try c.vm.getNodeStateMany(results.items, containers, node_type);
        return try results.toOwnedSlice();
    }

    const ARGS = struct {
        node_type: strid.StrId32,
        results: *std.ArrayList(*anyopaque),
    };

    if (try BatchWorkload(
        public.GraphInstance,
        ARGS,
        64,
        alloc,
        ARGS{
            .node_type = node_type,
            .results = &results,
        },
        containers,
        struct {
            pub fn createTask(args: ARGS, batch_id: usize, batch_size: usize, items: []const public.GraphInstance) getNodeStateTask {
                return getNodeStateTask{
                    .containers = items,
                    .node_type = args.node_type,
                    .output = args.results.items[batch_id * batch_size .. (batch_id * batch_size) + items.len],
                };
            }
        },
    )) |t| {
        task.api.wait(t);
    }

    return results.toOwnedSlice();
}

fn setInstanceContext(instance: public.GraphInstance, context_name: strid.StrId32, context: *anyopaque) !void {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    try c.setContext(context_name, context);
}

fn getInstanceContext(instance: public.GraphInstance, context_name: strid.StrId32) ?*anyopaque {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    return c.getContext(context_name);
}

fn removeInstanceContext(instance: public.GraphInstance, context_name: strid.StrId32) void {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    return c.removeContext(context_name);
}

fn getInputPins(instance: public.GraphInstance) public.OutPins {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    return c.graph_in.toPins();
}

fn getOutputPins(instance: public.GraphInstance) public.OutPins {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    return c.graph_out.toPins();
}

const ChangedObjsSet = std.AutoArrayHashMap(cetech1.cdb.ObjId, void);
var _last_check: cetech1.cdb.TypeVersion = 0;
const UpdateTask = struct {
    pub fn update(kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const nodetype_i_version = apidb.api.getInterafcesVersion(public.GraphNodeI);
        if (nodetype_i_version != _nodetype_i_version) {
            log.debug("Supported nodes:", .{});
            var it = apidb.api.getFirstImpl(public.GraphNodeI);
            while (it) |node| : (it = node.next) {
                const iface = cetech1.apidb.ApiDbAPI.toInterface(public.GraphNodeI, node);
                log.debug("\t - {s} - {s} - {d}", .{ iface.name, iface.type_name, iface.type_hash.id });
                try _node_type_iface_map.put(iface.type_hash, iface);
            }
            _nodetype_i_version = nodetype_i_version;
        }

        const valuetype_i_version = apidb.api.getInterafcesVersion(public.GraphValueTypeI);
        if (valuetype_i_version != _valuetype_i_version) {
            log.debug("Supported values:", .{});
            var it = apidb.api.getFirstImpl(public.GraphValueTypeI);
            while (it) |node| : (it = node.next) {
                const iface = cetech1.apidb.ApiDbAPI.toInterface(public.GraphValueTypeI, node);

                log.debug("\t - {s} - {d}", .{ iface.name, iface.type_hash.id });

                try _value_type_iface_map.put(iface.type_hash, iface);
                try _value_type_iface_cdb_map.put(iface.cdb_type_hash, iface);
            }
            _valuetype_i_version = valuetype_i_version;
        }

        if (true) {
            const alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(alloc);

            var processed_obj = ChangedObjsSet.init(alloc);
            defer processed_obj.deinit();

            var db = assetdb_private.getDb();

            const changed = try db.getChangeObjects(alloc, public.GraphType.typeIdx(db), _last_check);
            defer alloc.free(changed.objects);

            if (!changed.need_fullscan) {
                for (changed.objects) |graph| {
                    if (processed_obj.contains(graph)) continue;

                    if (!_vm_map.contains(graph)) {
                        // Only asset
                        const parent = db.getParent(graph);
                        if (!parent.isEmpty()) {
                            if (!cetech1.assetdb.Asset.isSameType(db, parent)) continue;
                        }
                        const vm = try createVM(db, graph);
                        _ = vm; // autofix
                    }

                    try processed_obj.put(graph, {});
                }
            } else {
                if (db.getAllObjectByType(alloc, public.GraphType.typeIdx(db))) |objs| {
                    for (objs) |graph| {
                        if (!_vm_map.contains(graph)) {
                            // Only asset
                            const parent = db.getParent(graph);
                            if (!parent.isEmpty()) {
                                if (!cetech1.assetdb.Asset.isSameType(db, parent)) continue;
                            }
                            const vm = try createVM(db, graph);
                            _ = vm; // autofix
                        }
                    }
                }
            }

            _last_check = changed.last_version;
        }
    }
};

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "Graph",
    &[_]cetech1.strid.StrId64{},
    UpdateTask.update,
);

//
// Nodes
//

const PRINT_NODE_TYPE = cetech1.strid.strId32("print");

const event_node_i = public.GraphNodeI.implement(
    .{
        .name = "Event Init",
        .type_name = public.EVENT_INIT_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = db; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin.init("Flow", public.NodePin.pinHash("flow", true), public.PinTypes.Flow),
            });
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.CoreIcons.FA_PLAY);
        }
    },
);

const event_shutdown_node_i = public.GraphNodeI.implement(
    .{
        .name = "Event Shutdown",
        .type_name = public.EVENT_SHUTDOWN_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = db; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin.init("Flow", public.NodePin.pinHash("flow", true), public.PinTypes.Flow),
            });
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.CoreIcons.FA_STOP);
        }
    },
);

const event_tick_node_i = public.GraphNodeI.implement(
    .{
        .name = "Event Tick",
        .type_name = public.EVENT_TICK_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = db; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin.init("Flow", public.NodePin.pinHash("flow", true), public.PinTypes.Flow),
            });
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.CoreIcons.FA_STOPWATCH);
        }
    },
);

const PrintNodeState = struct {
    input_validity: public.ValidityHash = 0,
};

const print_node_i = public.GraphNodeI.implement(
    .{
        .name = "Print",
        .type_name = "print",
        .sidefect = true,
    },
    PrintNodeState,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin.init("Flow", public.NodePin.pinHash("flow", false), public.PinTypes.Flow),
                public.NodePin.init("Value", public.NodePin.pinHash("int", false), public.PinTypes.GENERIC),
            });
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn create(allocator: std.mem.Allocator, state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId, reload: bool) !void {
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = db; // autofix
            _ = node_obj; // autofix
            const real_state: *PrintNodeState = @alignCast(@ptrCast(state));
            real_state.* = .{};
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = args; // autofix
            _ = out_pins;
            // var state = args.getState(PrintNodeState).?;
            // _ = state; // autofix

            const value_pin_type = in_pins.getPinType(1) orelse return;
            const iface = findValueTypeI(value_pin_type).?;

            var buffer: [256]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const tmp_allocator = fba.allocator();

            const str_value = try iface.valueToString(tmp_allocator, in_pins.data.?[1].?[0..iface.size]);
            log.debug("{s}", .{str_value});
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.CoreIcons.FA_PRINT);
        }
    },
);

const ConstNodeState = struct {
    version: cetech1.cdb.ObjVersion = 0,
    value_type: *const public.GraphValueTypeI = undefined,
    value_obj: cetech1.cdb.ObjId = .{},
};

const const_node_i = public.GraphNodeI.implement(
    .{
        .name = "Const",
        .type_name = "const",
        .settings_type = public.ConstNodeSettings.type_hash,
    },
    ConstNodeState,
    struct {
        const Self = @This();
        const out = public.NodePin.pinHash("value", true);

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = graph_obj; // autofix

            const node_r = public.GraphType.read(db, node_obj).?;
            if (public.NodeType.readSubObj(db, node_r, .settings)) |setting| {
                const settings_r = public.ConstNodeSettings.read(db, setting).?;

                if (public.ConstNodeSettings.readSubObj(db, settings_r, .value)) |value_obj| {
                    const value_type = findValueTypeIByCdb(cetech1.strid.strId32(db.getTypeName(value_obj.type_idx).?)).?;

                    return allocator.dupe(public.NodePin, &.{
                        public.NodePin.init("Value", public.NodePin.pinHash("value", true), value_type.type_hash),
                    });
                }
            }

            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn create(allocator: std.mem.Allocator, state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId, reload: bool) !void {
            _ = reload; // autofix
            _ = allocator; // autofix
            const real_state: *ConstNodeState = @alignCast(@ptrCast(state));
            real_state.* = .{};

            const node_r = public.GraphType.read(db, node_obj).?;
            if (public.NodeType.readSubObj(db, node_r, .settings)) |setting| {
                const settings_r = public.ConstNodeSettings.read(db, setting).?;

                if (public.ConstNodeSettings.readSubObj(db, settings_r, .value)) |value_obj| {
                    const value_type = findValueTypeIByCdb(cetech1.strid.strId32(db.getTypeName(value_obj.type_idx).?)).?;
                    real_state.value_type = value_type;
                    real_state.value_obj = value_obj;
                }
            }
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = in_pins;
            const real_state: *ConstNodeState = @alignCast(@ptrCast(args.state));

            var value: [2048]u8 = undefined;
            try real_state.value_type.valueFromCdb(args.db, real_state.value_obj, value[0..real_state.value_type.size]);
            const vh = try real_state.value_type.calcValidityHash(value[0..real_state.value_type.size]);
            try out_pins.write(0, vh, value[0..real_state.value_type.size]);
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.Icons.Const);
        }
    },
);

const culling_volume_node_i = public.GraphNodeI.implement(
    .{
        .name = "Culling volume",
        .type_name = public.CULLING_VOLUME_NODE_TYPE_STR,
        .pivot = .pivot,
        .category = "Culling",
    },
    cetech1.renderer.CullingVolume,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin.init("Radius", public.NodePin.pinHash("radius", false), public.PinTypes.F32),
            });
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn create(allocator: std.mem.Allocator, state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId, reload: bool) !void {
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = db; // autofix
            _ = node_obj; // autofix
            const real_state: *cetech1.renderer.CullingVolume = @alignCast(@ptrCast(state));
            real_state.* = .{};
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = out_pins;
            var state = args.getState(cetech1.renderer.CullingVolume).?;
            _, const radius = in_pins.read(f32, 0) orelse .{ 0, 0 };
            state.radius = radius;
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.Icons.Bounding);
        }
    },
);

const RandomF32NodeState = struct {
    min: f32 = 0,
    max: f32 = 1,
};

const seed: u64 = 1111;
var prng = std.rand.DefaultPrng.init(seed);

const random_f32_node_i = public.GraphNodeI.implement(
    .{
        .name = "Random f32",
        .type_name = "random_f32",
        .settings_type = public.RandomF32NodeSettings.type_hash,
        .category = "Random",
    },
    RandomF32NodeState,
    struct {
        const Self = @This();
        const out = public.NodePin.pinHash("value", true);

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = db; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix

            return allocator.dupe(public.NodePin, &.{
                public.NodePin.init("Value", public.NodePin.pinHash("value", true), public.PinTypes.F32),
            });
        }

        pub fn create(allocator: std.mem.Allocator, state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId, reload: bool) !void {
            _ = reload; // autofix
            _ = allocator; // autofix
            const real_state: *RandomF32NodeState = @alignCast(@ptrCast(state));
            real_state.* = .{};

            const node_r = public.GraphType.read(db, node_obj).?;
            if (public.NodeType.readSubObj(db, node_r, .settings)) |setting| {
                const settings_r = public.RandomF32NodeSettings.read(db, setting).?;

                real_state.min = public.RandomF32NodeSettings.readValue(db, f32, settings_r, .min);
                real_state.max = public.RandomF32NodeSettings.readValue(db, f32, settings_r, .max);
            }
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = in_pins;
            const real_state: *RandomF32NodeState = @alignCast(@ptrCast(args.state));

            const rnd = prng.random();
            const value = rnd.float(f32) * (real_state.max - real_state.min) + real_state.min;

            const vh = try f32_value_type_i.calcValidityHash(std.mem.asBytes(&value));
            try out_pins.writeTyped(f32, 0, vh, value);
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.Icons.Random);
        }
    },
);

// Inputs

const graph_inputs_i = public.GraphNodeI.implement(
    .{
        .name = "Graph Inputs",
        .type_name = "graph_inputs",
        .category = "Interface",
        .sidefect = true,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj;
            _ = db;
            _ = graph_obj;
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            var pins = std.ArrayList(public.NodePin).init(allocator);

            const graph_r = public.GraphType.read(db, graph_obj).?;

            if (public.GraphType.readSubObj(db, graph_r, .interface)) |iface_obj| {
                const iface_r = public.Interface.read(db, iface_obj).?;

                if (try public.Interface.readSubObjSet(db, iface_r, .inputs, allocator)) |inputs| {
                    defer allocator.free(inputs);

                    for (inputs) |input| {
                        const input_r = db.readObj(input).?;

                        const name = public.InterfaceInput.readStr(db, input_r, .name) orelse "NO NAME!!";
                        const value_obj = public.InterfaceInput.readSubObj(db, input_r, .value) orelse continue;

                        const uuid = try assetdb_private.api.getOrCreateUuid(input);
                        var buffer: [128]u8 = undefined;
                        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                        const value_type = findValueTypeIByCdb(cetech1.strid.strId32(db.getTypeName(value_obj.type_idx).?)).?;

                        try pins.append(public.NodePin.initRaw(
                            name,
                            try _string_intern.intern(str),
                            value_type.type_hash,
                        ));
                    }
                }
            }

            return try pins.toOwnedSlice();
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = in_pins; // autofix

            const graph_in_pins = api.getInputPins(args.instance);

            for (args.outputs, 0..) |input, idx| {
                const value_type = findValueTypeI(input.type_hash).?;

                @memcpy(
                    out_pins.data.?[idx][0..value_type.size],
                    graph_in_pins.data.?[idx][0..value_type.size],
                );
            }

            @memcpy(
                out_pins.validity_hash.?,
                graph_in_pins.validity_hash.?,
            );
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.Icons.Input);
        }
    },
);

const graph_outputs_i = public.GraphNodeI.implement(
    .{
        .name = "Graph Outputs",
        .type_name = "graph_outputs",
        .category = "Interface",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            var pins = std.ArrayList(public.NodePin).init(allocator);

            const graph_r = public.GraphType.read(db, graph_obj).?;

            if (public.GraphType.readSubObj(db, graph_r, .interface)) |iface_obj| {
                const iface_r = public.Interface.read(db, iface_obj).?;

                if (try public.Interface.readSubObjSet(db, iface_r, .outputs, allocator)) |outputs| {
                    defer allocator.free(outputs);

                    for (outputs) |input| {
                        const input_r = db.readObj(input).?;

                        const name = public.InterfaceInput.readStr(db, input_r, .name) orelse "NO NAME!!";
                        const value_obj = public.InterfaceInput.readSubObj(db, input_r, .value) orelse continue;

                        const uuid = try assetdb_private.api.getOrCreateUuid(input);
                        var buffer: [128]u8 = undefined;
                        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                        const value_type = findValueTypeIByCdb(cetech1.strid.strId32(db.getTypeName(value_obj.type_idx).?)).?;

                        try pins.append(
                            public.NodePin.initRaw(
                                name,
                                try _string_intern.intern(str),
                                value_type.type_hash,
                            ),
                        );
                    }
                }
            }

            return try pins.toOwnedSlice();
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = out_pins; // autofix

            const graph_out_pins = api.getOutputPins(args.instance);

            for (args.inputs, 0..) |input, idx| {
                const value_type = findValueTypeI(input.type_hash).?;

                if (in_pins.data.?[idx] == null) continue;

                @memcpy(
                    graph_out_pins.data.?[idx][0..value_type.size],
                    in_pins.data.?[idx].?[0..value_type.size],
                );

                graph_out_pins.validity_hash.?[idx] = in_pins.validity_hash.?[idx].?.*;
            }
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.Icons.Output);
        }
    },
);

const CallGraphNodeState = struct {
    graph: cetech1.cdb.ObjId = .{},
    instance: ?public.GraphInstance = null,
};

const call_graph_node_i = public.GraphNodeI.implement(
    .{
        .name = "Call graph",
        .type_name = public.CALL_GRAPH_NODE_TYPE_STR,
        .category = "Interface",

        .settings_type = public.CallGraphNodeSettings.type_hash,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = graph_obj; // autofix
            var pins = std.ArrayList(public.NodePin).init(allocator);

            const node_obj_r = public.NodeType.read(db, node_obj).?;
            if (public.NodeType.readSubObj(db, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(db, settings).?;
                if (public.CallGraphNodeSettings.readSubObj(db, settings_r, .graph)) |graph| {
                    const graph_r = public.GraphType.read(db, graph).?;
                    if (public.GraphType.readSubObj(db, graph_r, .interface)) |iface_obj| {
                        const iface_r = public.Interface.read(db, iface_obj).?;

                        if (try public.Interface.readSubObjSet(db, iface_r, .inputs, allocator)) |outputs| {
                            defer allocator.free(outputs);

                            for (outputs) |input| {
                                const input_r = db.readObj(input).?;

                                const name = public.InterfaceInput.readStr(db, input_r, .name) orelse "NO NAME!!";
                                const value_obj = public.InterfaceInput.readSubObj(db, input_r, .value) orelse continue;

                                const uuid = try assetdb_private.api.getOrCreateUuid(input);
                                var buffer: [128]u8 = undefined;
                                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                                const value_type = findValueTypeIByCdb(cetech1.strid.strId32(db.getTypeName(value_obj.type_idx).?)).?;

                                try pins.append(
                                    public.NodePin.initRaw(name, try _string_intern.intern(str), value_type.type_hash),
                                );
                            }
                        }
                    }
                }
            }

            return try pins.toOwnedSlice();
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = graph_obj; // autofix
            var pins = std.ArrayList(public.NodePin).init(allocator);

            const node_obj_r = public.NodeType.read(db, node_obj).?;

            if (public.NodeType.readSubObj(db, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(db, settings).?;
                if (public.CallGraphNodeSettings.readSubObj(db, settings_r, .graph)) |graph| {
                    const graph_r = public.GraphType.read(db, graph).?;
                    if (public.GraphType.readSubObj(db, graph_r, .interface)) |iface_obj| {
                        const iface_r = public.Interface.read(db, iface_obj).?;

                        if (try public.Interface.readSubObjSet(db, iface_r, .outputs, allocator)) |outputs| {
                            defer allocator.free(outputs);

                            for (outputs) |input| {
                                const input_r = db.readObj(input).?;

                                const name = public.InterfaceOutput.readStr(db, input_r, .name) orelse "NO NAME!!";
                                const value_obj = public.InterfaceOutput.readSubObj(db, input_r, .value) orelse continue;

                                const uuid = try assetdb_private.api.getOrCreateUuid(input);
                                var buffer: [128]u8 = undefined;
                                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                                const value_type = findValueTypeIByCdb(cetech1.strid.strId32(db.getTypeName(value_obj.type_idx).?)).?;

                                try pins.append(
                                    public.NodePin.initRaw(name, try _string_intern.intern(str), value_type.type_hash),
                                );
                            }
                        }
                    }
                }
            }

            return try pins.toOwnedSlice();
        }

        pub fn title(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]const u8 {
            const node_obj_r = public.NodeType.read(db, node_obj).?;

            if (public.NodeType.readSubObj(db, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(db, settings).?;
                if (public.CallGraphNodeSettings.readSubObj(db, settings_r, .graph)) |graph| {
                    const graph_r = public.GraphType.read(db, graph).?;

                    const graph_name = public.GraphType.readStr(db, graph_r, .name);

                    if (graph_name) |name| {
                        if (name.len != 0) {
                            return allocator.dupeZ(u8, name);
                        }
                    }

                    const prototype = db.getPrototype(graph_r);
                    if (prototype.isEmpty()) {
                        const graph_asset = assetdb_private.api.getAssetForObj(graph) orelse return allocator.dupeZ(u8, "");
                        const name = cetech1.assetdb.Asset.readStr(db, db.readObj(graph_asset).?, .Name) orelse return allocator.dupeZ(u8, "");
                        return allocator.dupeZ(u8, name);
                    } else {
                        const graph_asset = assetdb_private.api.getAssetForObj(prototype) orelse return allocator.dupeZ(u8, "");
                        const name = cetech1.assetdb.Asset.readStr(db, db.readObj(graph_asset).?, .Name) orelse return allocator.dupeZ(u8, "");
                        return allocator.dupeZ(u8, name);
                    }
                } else {
                    return allocator.dupeZ(u8, "SELECT GRAPH !!!");
                }
            }

            return allocator.dupeZ(u8, "PROBLEM?");
        }

        pub fn icon(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]u8 {
            _ = db; // autofix
            _ = node_obj; // autofix
            return allocator.dupeZ(u8, cetech1.coreui.Icons.Graph);
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = args; // autofix
            _ = in_pins; // autofix
            _ = out_pins; // autofix
            // const real_state: *CallGraphNodeState = @alignCast(@ptrCast(args.state));
            // if (real_state.instance) |instance| {

            //     // Write node inputs to graph inputs
            //     const graph_in_pins = api.getInputPins(instance);
            //     for (args.inputs, 0..) |input, idx| {
            //         const value_type = findValueTypeI(input.type_hash).?;

            //         if (in_pins.data.?[idx] == null) continue;

            //         @memcpy(
            //             graph_in_pins.data.?[idx][0..value_type.size],
            //             in_pins.data.?[idx].?[0..value_type.size],
            //         );

            //         graph_in_pins.validity_hash.?[idx] = in_pins.validity_hash.?[idx].?.*;
            //     }

            //     // Execute graph
            //     try api.executeNode(args.allocator, &.{instance}, graph_outputs_i.type_hash);

            //     // Write  graph outputs to node outpus
            //     const graph_out_pins = api.getOutputPins(instance);
            //     for (args.outputs, 0..) |input, idx| {
            //         const value_type = findValueTypeI(input.type_hash).?;

            //         @memcpy(
            //             out_pins.data.?[idx][0..value_type.size],
            //             graph_out_pins.data.?[idx][0..value_type.size],
            //         );
            //     }

            //     @memcpy(
            //         out_pins.validity_hash.?,
            //         graph_out_pins.validity_hash.?,
            //     );
            // }
        }
    },
);

// Values def
const flow_value_type_i = public.GraphValueTypeI.implement(
    bool,
    .{
        .name = "Flow",
        .type_hash = public.PinTypes.Flow,
        .cdb_type_hash = public.flowType.type_hash,
    },

    struct {
        pub fn valueFromCdb(db: cetech1.cdb.Db, obj: cetech1.cdb.ObjId, value: []u8) !void {
            _ = value; // autofix
            _ = db; // autofix
            _ = obj; // autofix
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(bool, value);
            return @intFromBool(v.*);
        }
        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(bool, value)});
        }
    },
);

const i32_value_type_i = public.GraphValueTypeI.implement(
    i32,
    .{
        .name = "i32",
        .type_hash = public.PinTypes.I32,
        .cdb_type_hash = public.i32Type.type_hash,
    },
    struct {
        pub fn valueFromCdb(db: cetech1.cdb.Db, obj: cetech1.cdb.ObjId, value: []u8) !void {
            const v = public.i32Type.readValue(db, i32, db.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(i32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(i32, value)});
        }
    },
);

const f32_value_type_i = public.GraphValueTypeI.implement(
    f32,
    .{
        .name = "f32",
        .type_hash = public.PinTypes.F32,
        .cdb_type_hash = public.f32Type.type_hash,
    },
    struct {
        pub fn valueFromCdb(db: cetech1.cdb.Db, obj: cetech1.cdb.ObjId, value: []u8) !void {
            const v = public.f32Type.readValue(db, f32, db.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(f32, value);
            return std.mem.bytesToValue(public.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(f32, value)});
        }
    },
);

const i64_value_type_i = public.GraphValueTypeI.implement(
    i64,
    .{
        .name = "i64",
        .type_hash = public.PinTypes.I64,
        .cdb_type_hash = public.i64Type.type_hash,
    },
    struct {
        pub fn valueFromCdb(db: cetech1.cdb.Db, obj: cetech1.cdb.ObjId, value: []u8) !void {
            const v = public.i64Type.readValue(db, i64, db.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(i64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(i64, value)});
        }
    },
);

const f64_value_type_i = public.GraphValueTypeI.implement(
    f64,
    .{
        .name = "f64",
        .type_hash = public.PinTypes.F64,
        .cdb_type_hash = public.f64Type.type_hash,
    },
    struct {
        pub fn valueFromCdb(db: cetech1.cdb.Db, obj: cetech1.cdb.ObjId, value: []u8) !void {
            const v = public.f64Type.readValue(db, f64, db.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(f64, value);
            return std.mem.bytesToValue(public.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(f64, value)});
        }
    },
);

const bool_value_type_i = public.GraphValueTypeI.implement(
    bool,
    .{
        .name = "bool",
        .type_hash = public.PinTypes.Bool,
        .cdb_type_hash = public.BoolType.type_hash,
    },
    struct {
        pub fn valueFromCdb(db: cetech1.cdb.Db, obj: cetech1.cdb.ObjId, value: []u8) !void {
            const v = public.BoolType.readValue(db, bool, db.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(bool, value);
            return std.mem.bytesToValue(public.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(bool, value)});
        }
    },
);
