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

const ConnectionPair = struct {
    node: cetech1.cdb.ObjId,
    pin: cetech1.strid.StrId32,
    pin_type: strid.StrId32,
    pin_idx: u32 = 0,
};

const ContainerNodePool = cetech1.mem.PoolWithLock(InstanceNode);
const NodePool = cetech1.mem.PoolWithLock(Node);
const NodeTypeMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *Node);

const NodeTypeIfaceMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *const public.GraphNodeI);
const ValueTypeIfaceMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *const public.GraphValueTypeI);

const NodeSettingMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, cetech1.cdb.ObjId);

const NodeMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, *Node);
const ConnectionMap = std.AutoArrayHashMap(ConnectionPair, ConnectionPair);
const ContainerPool = cetech1.mem.PoolWithLock(Instance);
const ContainerSet = std.AutoArrayHashMap(*Instance, void);
const NodePlan = std.AutoArrayHashMap(cetech1.cdb.ObjId, []cetech1.cdb.ObjId);
const InstanceNodePlan = std.AutoArrayHashMap(cetech1.cdb.ObjId, []*InstanceNode);
const VMPool = cetech1.mem.PoolWithLock(GraphVM);
const VMMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, *GraphVM);

const VMNodeByTypeMap = std.AutoArrayHashMap(cetech1.strid.StrId32, std.ArrayList(cetech1.cdb.ObjId));

const WiresIn = struct {
    const Self = @This();

    data: ?[]?[*]u8 = null,

    pub fn init() Self {
        return Self{};
    }

    pub fn fromNode(self: *Self, allocator: std.mem.Allocator, blob_size: usize, pin_count: usize) !void {
        if (blob_size != 0) {
            self.data = try allocator.alloc(?[*]u8, pin_count);
            @memset(self.data.?, null);
        }
    }

    pub fn toPins(self: Self) public.InPins {
        return public.InPins{
            .data = self.data,
        };
    }
};

const WiresOut = struct {
    const Self = @This();

    data: ?[]u8 = null,
    data_slices: ?[][*]u8 = null,

    pub fn init() Self {
        return Self{};
    }

    pub fn fromNode(self: *Self, allocator: std.mem.Allocator, blob_size: usize, pins: []const public.NodePin) !void {
        if (blob_size != 0) {
            self.data_slices = try allocator.alloc([*]u8, pins.len);
            self.data = try allocator.alloc(u8, blob_size);
            @memset(self.data.?, 0);

            var pin_s: usize = 0;
            for (pins, 0..) |pin, idx| {
                const pin_def = findValueTypeI(pin.type_hash).?;
                self.data_slices.?[idx] = self.data.?[pin_s .. pin_s + pin_def.size + @sizeOf(public.ValidityHash)].ptr;
                pin_s += pin_def.size;
            }
        }
    }

    pub fn toPins(self: Self) public.OutPins {
        return public.OutPins{
            .data = self.data_slices,
        };
    }
};
const InstanceNode = struct {
    const Self = @This();

    in: WiresIn,
    out: WiresOut,

    settings: ?cetech1.cdb.ObjId,
    settings_version: cetech1.cdb.ObjVersion = 0,

    graph: cetech1.cdb.ObjId,
    vmnode: *const Node,
    check_flow: bool,

    state: ?*anyopaque = null,

    last_in_vh: []public.ValidityHash = undefined,
    eval: bool = false,

    pub fn init(
        data_alloc: std.mem.Allocator,
        node: *const Node,
        state: ?*anyopaque,
        settings: ?cetech1.cdb.ObjId,
        graph: cetech1.cdb.ObjId,
    ) !Self {
        var self = Self{
            .in = WiresIn.init(),
            .out = WiresOut.init(),
            .settings = settings,
            .graph = graph,
            .vmnode = node,
            .check_flow = node.has_flow,
            .state = state,
        };

        try self.in.fromNode(data_alloc, node.input_blob_size, node.input_count);
        try self.out.fromNode(data_alloc, node.output_blob_size, node.outputs);

        self.last_in_vh = try _allocator.alloc(public.ValidityHash, node.input_count);
        for (0..self.last_in_vh.len) |idx| {
            self.last_in_vh[idx] = 0;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        _allocator.free(self.last_in_vh);
    }
};

// Instace of GraphVM
const Instance = struct {
    const Self = @This();
    const InstanceNodeMap = std.AutoArrayHashMap(cetech1.cdb.ObjId, *InstanceNode);
    const DataHolder = std.ArrayList(u8);
    const StateHolder = std.ArrayList(u8);
    const ContextMap = std.AutoArrayHashMap(cetech1.strid.StrId32, *anyopaque);

    allocator: std.mem.Allocator,
    vm: *GraphVM,

    node_map: InstanceNodeMap,

    data: DataHolder,
    state_data: StateHolder,

    context_map: ContextMap,

    in: WiresOut,
    input_blob_size: usize = 0,

    out: WiresOut,
    output_blob_size: usize = 0,

    instance_plan: InstanceNodePlan,

    pub fn init(allocator: std.mem.Allocator, vm: *GraphVM) Self {
        return Self{
            .allocator = allocator,
            .vm = vm,
            .node_map = InstanceNodeMap.init(allocator),
            .data = DataHolder.init(allocator),
            .state_data = StateHolder.init(allocator),
            .context_map = ContextMap.init(allocator),
            .in = WiresOut.init(),
            .out = WiresOut.init(),
            .instance_plan = InstanceNodePlan.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.clean();
        self.node_map.deinit();
        self.data.deinit();
        self.state_data.deinit();
        self.context_map.deinit();
        self.instance_plan.deinit();
    }

    pub fn clean(self: *Self) void {
        for (self.node_map.values()) |v| {
            if (v.state) |state| {
                if (v.vmnode.iface.destroy) |destroy| {
                    destroy(state, self.vm.db) catch undefined;
                }
            }
            v.deinit();
            _instance_node_pool.destroy(v);
        }
        self.node_map.clearRetainingCapacity();
        self.data.clearRetainingCapacity();
        self.state_data.clearRetainingCapacity();
        self.context_map.clearRetainingCapacity();

        for (self.instance_plan.values()) |v| {
            self.allocator.free(v);
        }
        self.instance_plan.clearRetainingCapacity();

        // TODO: move to wire, alloc to wire?
        if (self.in.data) |data| {
            self.allocator.free(data);
            self.in.data = null;
        }
        if (self.in.data_slices) |data| {
            self.allocator.free(data);
            self.in.data_slices = null;
        }
        if (self.out.data) |data| {
            self.allocator.free(data);
            self.out.data = null;
        }
        if (self.out.data_slices) |data| {
            self.allocator.free(data);
            self.out.data_slices = null;
        }
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

    fn compilePins(self: *Self, pins: []const public.NodePin, is_output: bool) !void {
        var size: usize = 0;

        for (pins, 0..) |pin, idx| {
            _ = idx; // autofix
            const type_def = findValueTypeI(pin.type_hash).?;
            //try self.data_map.put(pin.pin_hash, @intCast(idx));
            // const alignn = std.mem.alignForwardLog2(size, @intCast(type_def.alignn)) - size;
            size += type_def.size + @sizeOf(public.ValidityHash);
        }

        if (is_output) {
            self.output_blob_size = size;
        } else {
            self.input_blob_size = size;
        }
    }

    pub fn build(self: *Self) !void {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - Instance build");
        defer zone_ctx.End();

        self.clean();

        try self.data.resize(self.vm.data_size);
        try self.state_data.resize(self.vm.state_size);

        var dat_fba = std.heap.FixedBufferAllocator.init(self.data.items);
        const data_alloc = dat_fba.allocator();

        var state_fba = std.heap.FixedBufferAllocator.init(self.state_data.items);
        const state_alloc = state_fba.allocator();

        // Graph input pins
        if (self.vm.inputs) |inputs| {
            try self.compilePins(inputs, false);
            try self.in.fromNode(self.allocator, self.input_blob_size, inputs);

            if (public.GraphType.readSubObj(self.vm.db, public.GraphType.read(self.vm.db, self.vm.graph_obj).?, .interface)) |iface_obj| {
                const iface_r = public.Interface.read(self.vm.db, iface_obj).?;

                // TODO: allocator form params
                if (try public.Interface.readSubObjSet(self.vm.db, iface_r, .inputs, _allocator)) |inputss| {
                    defer _allocator.free(inputss);

                    for (inputss, 0..) |input, idx| {
                        const input_r = self.vm.db.readObj(input).?;
                        const value_obj = public.InterfaceInput.readSubObj(self.vm.db, input_r, .value) orelse continue;
                        const value_type = findValueTypeIByCdb(cetech1.strid.strId32(self.vm.db.getTypeName(value_obj.type_idx).?)).?;

                        // TODO: dynamic?
                        var value: [2048]u8 = undefined;
                        try value_type.valueFromCdb(self.vm.db, value_obj, value[0..value_type.size]);
                        const vh = try value_type.calcValidityHash(value[0..value_type.size]);

                        try self.in.toPins().write(idx, vh, value[0..value_type.size]);
                    }
                }
            }
        }

        // Graph outputs pins
        if (self.vm.outputs) |outputs| {
            try self.compilePins(outputs, true);
            try self.out.fromNode(self.allocator, self.output_blob_size, outputs);

            if (public.GraphType.readSubObj(self.vm.db, public.GraphType.read(self.vm.db, self.vm.graph_obj).?, .interface)) |iface_obj| {
                const iface_r = public.Interface.read(self.vm.db, iface_obj).?;

                // TODO: allocator form params
                if (try public.Interface.readSubObjSet(self.vm.db, iface_r, .outputs, _allocator)) |outputss| {
                    defer _allocator.free(outputss);

                    for (outputss, 0..) |output, idx| {
                        const output_r = self.vm.db.readObj(output).?;
                        const value_obj = public.InterfaceOutput.readSubObj(self.vm.db, output_r, .value) orelse continue;
                        const value_type = findValueTypeIByCdb(cetech1.strid.strId32(self.vm.db.getTypeName(value_obj.type_idx).?)).?;

                        // TODO: dynamic?
                        var value: [2048]u8 = undefined;

                        try value_type.valueFromCdb(self.vm.db, value_obj, value[0..value_type.size]);
                        const vh = try value_type.calcValidityHash(value[0..value_type.size]);

                        try self.out.toPins().write(idx, vh, value[0..value_type.size]);
                    }
                }
            }
        }

        // Init nodes
        for (self.vm.node_map.keys(), self.vm.node_map.values()) |k, v| {
            const instance_node = try _instance_node_pool.create();

            var state: ?*anyopaque = null;
            if (v.iface.state_size != 0) {
                const state_data = try state_alloc.alloc(u8, v.iface.state_size);
                state = std.mem.alignPointer(state_data.ptr, v.iface.state_align);
                try v.iface.create.?(state.?, self.vm.db, k);
            }

            instance_node.* = try InstanceNode.init(
                data_alloc,
                v,
                state,
                self.vm.node_settings.get(k),
                self.vm.graph_obj,
            );
            try self.node_map.put(k, instance_node);
        }

        // Wire nodes
        // Set input slice in input node to output slice of output node
        // With this is not needeed to propagate value after exec because input is linked to output.
        for (self.vm.connection_map.keys(), self.vm.connection_map.values()) |k, v| {
            const out_node = self.node_map.get(k.node).?;
            var in_node = self.node_map.get(v.node).?;

            const out_idx = k.pin_idx;
            const in_idx = v.pin_idx;

            in_node.in.data.?[in_idx] = out_node.out.data_slices.?[out_idx];
        }

        // Prepare instance plan

        for (self.vm.node_plan.keys(), self.vm.node_plan.values()) |k, plan| {
            var new_plan = try std.ArrayList(*InstanceNode).initCapacity(_allocator, plan.len);
            defer new_plan.deinit();

            for (plan) |n| {
                const node = self.node_map.get(n).?;
                try new_plan.append(node);
            }

            try self.instance_plan.put(k, try new_plan.toOwnedSlice());
        }
    }
};

const Node = struct {
    const Self = @This();

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

    pub fn init(allocator: std.mem.Allocator, iface: *const public.GraphNodeI) Self {
        return Self{
            .allocator = allocator,
            .iface = iface,
            .data_map = public.PinDataIdxMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.data_map.deinit();
        self.allocator.free(self.outputs);
        self.allocator.free(self.inputs);
    }

    fn compilePins(self: *Self, pins: []const public.NodePin, is_output: bool) !void {
        var size: usize = 0;

        for (pins, 0..) |pin, idx| {
            const type_def = findValueTypeI(pin.type_hash).?;
            try self.data_map.put(pin.pin_hash, @intCast(idx));
            // const alignn = std.mem.alignForwardLog2(size, @intCast(type_def.alignn)) - size;
            size += type_def.size + @sizeOf(public.ValidityHash);
        }

        if (is_output) {
            self.output_blob_size = size;
        } else {
            self.input_blob_size = size;
        }
    }

    pub fn compile(self: *Self, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) !void {
        self.inputs = try self.iface.getInputPins(self.allocator, db, graph_obj, node_obj);
        self.input_count = self.inputs.len;
        self.has_flow = self.inputs.len != 0 and self.inputs[0].type_hash.eql(public.PinTypes.Flow);
        try self.compilePins(self.inputs, false);

        const outputs = try self.iface.getOutputPins(self.allocator, db, graph_obj, node_obj);
        self.outputs = outputs;
        self.output_count = outputs.len;
        self.has_flow_out = self.outputs.len != 0 and self.outputs[0].type_hash.eql(public.PinTypes.Flow);
        try self.compilePins(outputs, true);
    }
};

const GraphVM = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    db: cetech1.cdb.Db,
    graph_obj: cetech1.cdb.ObjId,
    graph_version: cetech1.cdb.ObjVersion = 0,

    node_map: NodeMap,
    connection_map: ConnectionMap,

    container_set: ContainerSet,

    node_plan: NodePlan,

    node_settings: NodeSettingMap,

    data_size: usize = 0,
    state_size: usize = 0,

    inputs: ?[]const public.NodePin = null,
    outputs: ?[]const public.NodePin = null,

    node_by_type: VMNodeByTypeMap,

    pub fn init(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId) Self {
        return Self{
            .allocator = allocator,
            .graph_obj = graph,
            .db = db,
            .node_map = NodeMap.init(allocator),
            .connection_map = ConnectionMap.init(allocator),
            .container_set = ContainerSet.init(allocator),
            .node_plan = NodePlan.init(allocator),
            .node_settings = NodeSettingMap.init(allocator),
            .node_by_type = VMNodeByTypeMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.clean();

        for (self.container_set.keys()) |value| {
            value.deinit();
        }

        self.node_plan.deinit();
        self.node_map.deinit();
        self.connection_map.deinit();
        self.container_set.deinit();
        self.node_settings.deinit();
        self.node_by_type.deinit();
    }

    pub fn clean(self: *Self) void {
        for (self.container_set.keys()) |value| {
            value.clean();
        }

        for (self.node_plan.values()) |value| {
            self.allocator.free(value);
        }

        for (self.node_map.values()) |value| {
            value.deinit();
            _node_pool.destroy(value);
        }

        for (self.node_by_type.values()) |value| {
            value.deinit();
        }

        self.node_settings.clearRetainingCapacity();
        self.node_plan.clearRetainingCapacity();
        self.node_map.clearRetainingCapacity();
        self.connection_map.clearRetainingCapacity();
        self.node_by_type.clearRetainingCapacity();

        if (self.inputs) |inputs| {
            self.allocator.free(inputs);
        }

        if (self.outputs) |outputs| {
            self.allocator.free(outputs);
        }
    }

    fn findNodeByType(self: Self, node_type: cetech1.strid.StrId32) ?[]cetech1.cdb.ObjId {
        var zone_ctx = profiler_private.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (self.node_by_type.get(node_type)) |nodes| {
            return nodes.items;
        }

        return null;
    }

    pub fn compile(self: *Self, allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - build");
        defer zone_ctx.End();

        self.clean();

        const graph_version = self.db.getVersion(self.graph_obj);
        self.graph_version = graph_version;

        const graph_r = self.db.readObj(self.graph_obj).?;

        var pivots = std.ArrayList(cetech1.cdb.ObjId).init(allocator);
        defer pivots.deinit();

        // Nodes
        self.data_size = 0;

        if (try public.GraphType.readSubObjSet(self.db, graph_r, .nodes, allocator)) |nodes| {
            defer allocator.free(nodes);

            for (nodes) |node| {
                const node_r = self.db.readObj(node).?;

                const type_hash = public.NodeType.readValue(self.db, u32, node_r, .node_type);

                if (public.NodeType.readSubObj(self.db, node_r, .settings)) |settings| {
                    try self.node_settings.put(node, settings);
                }

                const vmnode = try _node_pool.create();
                const iface = findNodeI(.{ .id = type_hash }).?;
                vmnode.* = Node.init(_allocator, iface);

                try vmnode.compile(
                    self.db,
                    self.graph_obj,
                    node,
                );

                self.data_size += vmnode.input_blob_size + vmnode.output_blob_size;
                self.data_size += (vmnode.input_count + vmnode.output_count) * @sizeOf([]u8);
                self.state_size += vmnode.iface.state_size;

                if (vmnode.iface.pivot != .none) {
                    try pivots.append(node);
                }

                try self.node_map.put(node, vmnode);

                const node_type_get = try self.node_by_type.getOrPut(iface.type_hash);
                if (!node_type_get.found_existing) {
                    node_type_get.value_ptr.* = std.ArrayList(cetech1.cdb.ObjId).init(self.allocator);
                }
                try node_type_get.value_ptr.*.append(node);
            }
        }

        // Connections
        if (try public.GraphType.readSubObjSet(self.db, graph_r, .connections, allocator)) |conections| {
            defer allocator.free(conections);

            for (conections) |connection| {
                const connection_r = self.db.readObj(connection).?;

                const from_node = public.ConnectionType.readRef(self.db, connection_r, .from_node).?;
                const from_pin = public.ConnectionType.readValue(self.db, u32, connection_r, .from_pin);

                const to_node = public.ConnectionType.readRef(self.db, connection_r, .to_node).?;
                const to_pin = public.ConnectionType.readValue(self.db, u32, connection_r, .to_pin);

                const node = self.node_map.get(from_node).?;
                const node_to = self.node_map.get(to_node).?;

                const pin_type: strid.StrId32 = blk: {
                    for (node.outputs) |pin| {
                        if (pin.pin_hash.eql(.{ .id = from_pin })) break :blk pin.type_hash;
                    }
                    break :blk .{ .id = 0 };
                };

                try self.connection_map.put(
                    .{ .node = from_node, .pin = .{ .id = from_pin }, .pin_type = pin_type, .pin_idx = node.data_map.get(.{ .id = from_pin }).? },
                    .{ .node = to_node, .pin = .{ .id = to_pin }, .pin_type = pin_type, .pin_idx = node_to.data_map.get(.{ .id = to_pin }).? },
                );
            }
        }

        // Interafces
        if (public.GraphType.readSubObj(self.db, graph_r, .interface)) |interface_obj| {
            _ = interface_obj; // autofix
            self.inputs = try graph_inputs_i.getOutputPins(self.allocator, self.db, self.graph_obj, .{});
            self.outputs = try graph_outputs_i.getInputPins(self.allocator, self.db, self.graph_obj, .{});
        }

        // Plan pivots.
        var dag = cetech1.dag.DAG(cetech1.cdb.ObjId).init(allocator);
        defer dag.deinit();
        for (pivots.items) |pivot| {
            try dag.reset();
            const pivot_vmnode = self.node_map.get(pivot).?;

            if (pivot_vmnode.has_flow_out) {
                //std.debug.assert(pivot_vmnode.iface.pivot == .flow and pivot_vmnode.has_flow);

                try dag.add(pivot, &.{});
                for (self.connection_map.keys(), self.connection_map.values()) |k, v| {
                    // only conection from this node
                    if (!k.node.eql(pivot)) continue;

                    // Only flow
                    if (!k.pin_type.eql(public.PinTypes.Flow)) continue;

                    try self.flowDag(allocator, &dag, v.node);
                }
            } else {
                try self.inputDag(allocator, &dag, pivot);
            }

            try dag.build_all();
            try self.node_plan.put(pivot, try self.allocator.dupe(cetech1.cdb.ObjId, dag.output.keys()));

            log.debug("Plan \"{s}\" for pivot \"{s}\":", .{ @tagName(pivot_vmnode.iface.pivot), pivot_vmnode.iface.name });
            for (dag.output.keys()) |node| {
                const vmnode = self.node_map.get(node).?;
                log.debug("\t - {s}", .{vmnode.iface.name});
            }
        }

        // Rebuild exist containers.
        for (self.container_set.keys()) |value| {
            try value.build();
        }
    }

    fn flowDag(self: *Self, allocator: std.mem.Allocator, dag: *cetech1.dag.DAG(cetech1.cdb.ObjId), node: cetech1.cdb.ObjId) !void {
        var depends = std.ArrayList(cetech1.cdb.ObjId).init(allocator);
        defer depends.deinit();

        for (self.connection_map.keys(), self.connection_map.values()) |k, v| {
            // only conection to this node
            if (!v.node.eql(node)) continue;
            try depends.append(k.node);
            try dag.add(k.node, &.{});
        }

        try dag.add(node, depends.items);

        for (self.connection_map.keys(), self.connection_map.values()) |k, v| {
            // Follow only flow
            if (!k.pin_type.eql(public.PinTypes.Flow)) {
                continue;
            }

            // only conection from this node
            if (!k.node.eql(node)) continue;
            try self.flowDag(allocator, dag, v.node);
        }
    }

    fn inputDag(self: *Self, allocator: std.mem.Allocator, dag: *cetech1.dag.DAG(cetech1.cdb.ObjId), node: cetech1.cdb.ObjId) !void {
        var depends = std.ArrayList(cetech1.cdb.ObjId).init(allocator);
        defer depends.deinit();

        for (self.connection_map.keys(), self.connection_map.values()) |k, v| {
            // only conection to this node
            if (!v.node.eql(node)) continue;
            try depends.append(k.node);
            try dag.add(k.node, &.{});
            try self.inputDag(allocator, dag, k.node);
        }

        try dag.add(node, depends.items);
    }

    pub fn createContainer(self: *Self) !*Instance {
        var container = try _container_pool.create();
        container.* = Instance.init(self.allocator, self);

        try self.container_set.put(container, {});
        try container.build();

        return container;
    }

    pub fn destroyContainer(self: *Self, container: *Instance) void {
        container.deinit();
        _ = self.container_set.swapRemove(container);
        _container_pool.destroy(container);
    }

    fn executeNodesMany(self: *Self, containers: []const public.GraphInstance, event_hash: strid.StrId32) !void {
        var zone_ctx = profiler_private.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (self.findNodeByType(event_hash)) |event_nodes| {
            for (containers) |container| {
                if (!container.isValid()) continue;
                var c: *Instance = @alignCast(@ptrCast(container.inst));

                for (event_nodes) |event_node| {
                    const plan = c.instance_plan.get(event_node).?;
                    for (plan) |node| {
                        var vm_node = node.vmnode;

                        const in_pins = node.in.toPins();
                        const out_pins = node.out.toPins();

                        // If node has flow check if its True.
                        // FLow node is always 0
                        if (node.check_flow) {
                            if (!in_pins.read(bool, 0).?[1]) return;
                        }

                        var node_changed = false;

                        for (0..node.last_in_vh.len) |pin_idx| {
                            if (in_pins.data == null) break;
                            if (in_pins.data.?[pin_idx] == null) continue;

                            const vh: *public.ValidityHash = @alignCast(@ptrCast(in_pins.data.?[pin_idx]));
                            if (node.last_in_vh[pin_idx] != vh.*) {
                                node_changed = true;
                                node.last_in_vh[pin_idx] = vh.*;
                            }
                        }

                        if (node_changed or !node.eval) {
                            var zone_exec_ctx = profiler_private.ztracy.ZoneN(@src(), vm_node.iface.name);
                            defer zone_exec_ctx.End();

                            try vm_node.iface.execute(
                                .{
                                    .db = c.vm.db,
                                    .settings = node.settings,
                                    .state = node.state,
                                    .graph = node.graph,
                                    .instance = container,
                                    .outputs = node.vmnode.outputs,
                                    .inputs = node.vmnode.inputs,
                                },
                                in_pins,
                                out_pins,
                            );

                            node.eval = true;
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
                var c: *Instance = @alignCast(@ptrCast(container.inst));
                const node = c.node_map.get(nodes[0]) orelse continue;
                if (node.state) |state| {
                    results[idx] = state;
                }
            }
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
    .destroyInstance = destroyInstance,
    .executeNode = executeNodes,
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

var _node_pool: NodePool = undefined;
var _instance_node_pool: ContainerNodePool = undefined;
var _container_pool: ContainerPool = undefined;

var _nodetype_i_version: cetech1.apidb.InterfaceVersion = 0;
var _valuetype_i_version: cetech1.apidb.InterfaceVersion = 0;

var _node_type_iface_map: NodeTypeIfaceMap = undefined;
var _value_type_iface_map: ValueTypeIfaceMap = undefined;
var _value_type_iface_cdb_map: ValueTypeIfaceMap = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _vm_map = VMMap.init(allocator);
    _vm_pool = try VMPool.initPreheated(allocator, 1024);

    _node_pool = try NodePool.initPreheated(allocator, 1024);
    _instance_node_pool = try ContainerNodePool.initPreheated(allocator, 1024);
    _container_pool = try ContainerPool.initPreheated(allocator, 1024);

    _node_type_iface_map = NodeTypeIfaceMap.init(allocator);

    _value_type_iface_map = ValueTypeIfaceMap.init(allocator);
    _value_type_iface_cdb_map = ValueTypeIfaceMap.init(allocator);
}

pub fn deinit() void {
    for (_vm_map.values()) |value| {
        value.deinit();
    }

    _container_pool.deinit();
    _instance_node_pool.deinit();
    _node_pool.deinit();
    _vm_map.deinit();
    _vm_pool.deinit();

    _node_type_iface_map.deinit();
    _value_type_iface_map.deinit();
    _value_type_iface_cdb_map.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.GraphVMApi, &api);
    try apidb.api.implOrRemove(module_name, cetech1.cdb.CreateTypesI, &create_cdb_types_i, true);
    try apidb.api.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, true);

    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &event_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &print_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &const_node_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &graph_inputs_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &graph_outputs_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &call_graph_node_i, true);

    try apidb.api.implOrRemove(module_name, public.GraphNodeI, &culling_volume_node_i, true);

    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &flow_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &i32_value_type_i, true);
    try apidb.api.implOrRemove(module_name, public.GraphValueTypeI, &f32_value_type_i, true);
}

// CDB
var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cetech1.cdb.Db) !void {

        // GraphNodeType
        {
            _ = try db.addType(
                public.GraphType.name,
                &[_]cetech1.cdb.PropDef{
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
                    .{ .prop_idx = public.NodeType.propIdx(.node_type), .name = "node_type", .type = .U32 },
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
                    .{ .prop_idx = public.ConnectionType.propIdx(.from_pin), .name = "from_pin", .type = .U32 },
                    .{ .prop_idx = public.ConnectionType.propIdx(.to_pin), .name = "to_pin", .type = .U32 },
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
                    .{ .prop_idx = public.CallGraphNodeSettings.propIdx(.graph), .name = "graph", .type = .REFERENCE, .type_hash = public.GraphType.type_hash },
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
    }
});

pub fn createCdbNode(db: cetech1.cdb.Db, type_hash: strid.StrId32, pos: ?[2]f32) !cetech1.cdb.ObjId {
    const iface = findNodeI(type_hash).?;
    const node = try public.NodeType.createObject(db);

    const node_w = public.NodeType.write(db, node).?;
    public.NodeType.setValue(db, u32, node_w, .node_type, iface.type_hash.id);

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
    if (public.PinTypes.I32.eql(type_hash)) return .{ 0.0, 0.0, 0.5, 1.0 };
    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn createVM(db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId) !*GraphVM {
    const vm = try _vm_pool.create();
    vm.* = GraphVM.init(_allocator, db, graph);
    try _vm_map.put(graph, vm);

    const alloc = try tempalloc.api.create();
    defer tempalloc.api.destroy(alloc);

    try vm.compile(alloc);

    return @ptrCast(vm);
}

fn destroyVM(vm: *GraphVM) void {
    vm.deinit();
    _ = _vm_map.swapRemove(vm.graph_obj);
    _vm_pool.destroy(vm);
}

fn createInstance(db: cetech1.cdb.Db, graph: cetech1.cdb.ObjId) !public.GraphInstance {
    if (!_vm_map.contains(graph)) {
        _ = try createVM(db, graph);
    }

    var vm = _vm_map.get(graph).?;

    const container = try vm.createContainer();

    return .{
        .graph = graph,
        .inst = container,
    };
}

fn destroyInstance(vmc: public.GraphInstance) void {
    var vm = _vm_map.get(vmc.graph).?;
    vm.destroyContainer(@alignCast(@ptrCast(vmc.inst)));
}

const executeNodesTask = struct {
    instances: []const public.GraphInstance,
    event_hash: strid.StrId32,

    pub fn exec(self: *@This()) !void {
        const c0: *Instance = @alignCast(@ptrCast(self.instances[0].inst));
        const vm = c0.vm;
        try vm.executeNodesMany(self.instances, self.event_hash);
    }
};

fn executeNodes(containers: []const public.GraphInstance, event_hash: strid.StrId32) !void {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - execute nodes");
    defer zone_ctx.End();

    const items_count = containers.len;
    const batch_size = 64;
    if (containers.len <= batch_size) {
        const c0: *Instance = @alignCast(@ptrCast(containers[0].inst));
        const vm = c0.vm;
        try vm.executeNodesMany(containers, event_hash);
    }

    const batch_count = items_count / batch_size;
    const batch_rest = items_count - (batch_count * batch_size);

    const alloc = try tempalloc.api.create();
    defer tempalloc.api.destroy(alloc);

    var tasks = std.ArrayList(cetech1.task.TaskID).init(alloc);
    defer tasks.deinit();

    for (0..batch_count) |batch_id| {
        var worker_items: usize = batch_size;
        if (batch_id == (batch_count - 1)) worker_items += batch_rest;

        const task_id = try task.api.schedule(
            cetech1.task.TaskID.none,
            executeNodesTask{
                .instances = containers[batch_id * batch_size .. (batch_id * batch_size) + worker_items],
                .event_hash = event_hash,
            },
        );
        try tasks.append(task_id);
    }

    if (tasks.items.len != 0) {
        task.api.wait(try task.api.combine(tasks.items));
    }
}

fn needCompile(graph: cetech1.cdb.ObjId) bool {
    var vm = _vm_map.get(graph) orelse return false;
    return vm.graph_version != vm.db.getVersion(graph);
}
fn compile(allocator: std.mem.Allocator, graph: cetech1.cdb.ObjId) !void {
    var vm = _vm_map.get(graph).?;
    try vm.compile(allocator);
}

const getNodeStateTask = struct {
    containers: []const public.GraphInstance,
    node_type: strid.StrId32,
    output: []*anyopaque,
    pub fn exec(self: *@This()) !void {
        var c: *Instance = @alignCast(@ptrCast(self.containers[0].inst));
        try c.vm.getNodeStateMany(self.output, self.containers, self.node_type);
    }
};

pub fn getNodeState(allocator: std.mem.Allocator, containers: []const public.GraphInstance, node_type: strid.StrId32) ![]*anyopaque {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GraphVM - get node state");
    defer zone_ctx.End();

    var results = try std.ArrayList(*anyopaque).initCapacity(allocator, containers.len);
    try results.resize(containers.len);

    const items_count = containers.len;
    const batch_size = 64;
    if (containers.len < batch_size) {
        var c: *Instance = @alignCast(@ptrCast(containers[0].inst));
        try c.vm.getNodeStateMany(results.items, containers, node_type);
    } else {
        const batch_count = items_count / batch_size;
        const batch_rest = items_count - (batch_count * batch_size);

        const alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(alloc);

        var tasks = std.ArrayList(cetech1.task.TaskID).init(alloc);
        defer tasks.deinit();

        for (0..batch_count) |batch_id| {
            var worker_items: usize = batch_size;
            if (batch_id == (batch_count - 1)) worker_items += batch_rest;

            const task_id = try task.api.schedule(
                cetech1.task.TaskID.none,
                getNodeStateTask{
                    .containers = containers[batch_id * batch_size .. (batch_id * batch_size) + worker_items],
                    .node_type = node_type,
                    .output = results.items[batch_id * batch_size .. (batch_id * batch_size) + worker_items],
                },
            );
            try tasks.append(task_id);
        }

        if (tasks.items.len != 0) {
            task.api.wait(try task.api.combine(tasks.items));
        }
    }

    return results.toOwnedSlice();
}

fn setInstanceContext(instance: public.GraphInstance, context_name: strid.StrId32, context: *anyopaque) !void {
    const c: *Instance = @alignCast(@ptrCast(instance.inst));
    try c.setContext(context_name, context);
}

fn getInstanceContext(instance: public.GraphInstance, context_name: strid.StrId32) ?*anyopaque {
    const c: *Instance = @alignCast(@ptrCast(instance.inst));
    return c.getContext(context_name);
}

fn removeInstanceContext(instance: public.GraphInstance, context_name: strid.StrId32) void {
    const c: *Instance = @alignCast(@ptrCast(instance.inst));
    return c.removeContext(context_name);
}

fn getInputPins(instance: public.GraphInstance) public.OutPins {
    const c: *Instance = @alignCast(@ptrCast(instance.inst));
    return c.in.toPins();
}

fn getOutputPins(instance: public.GraphInstance) public.OutPins {
    const c: *Instance = @alignCast(@ptrCast(instance.inst));
    return c.out.toPins();
}

const ChangedObjsSet = std.AutoArrayHashMap(cetech1.cdb.ObjId, void);
var _last_check: cetech1.cdb.TypeVersion = 0;
const OnLoadTask = struct {
    pub fn update(kernel_tick: u64, dt: f32) !void {
        _ = kernel_tick;
        _ = dt;

        const nodetype_i_version = apidb.api.getInterafcesVersion(public.GraphNodeI);
        if (nodetype_i_version != _nodetype_i_version) {
            log.debug("Supported nodes:", .{});
            var it = apidb.api.getFirstImpl(public.GraphNodeI);
            while (it) |node| : (it = node.next) {
                const iface = cetech1.apidb.ApiDbAPI.toInterface(public.GraphNodeI, node);
                log.debug("\t - {s} - {d}", .{ iface.name, iface.type_hash.id });
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

        if (false) {
            const alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(alloc);

            var processed_obj = ChangedObjsSet.init(alloc);
            defer processed_obj.deinit();

            for (_vm_map.values()) |value| {
                var db = value.db;

                const changed = try db.getChangeObjects(alloc, public.GraphType.typeIdx(db), _last_check);
                defer alloc.free(changed.objects);

                for (changed.objects) |graph| {
                    if (processed_obj.contains(graph)) continue;

                    if (_vm_map.get(graph)) |vm| {
                        try vm.build(alloc);
                    }

                    try processed_obj.put(graph, {});
                }

                _last_check = changed.last_version;

                return;
            }
        }
    }
};

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "Graph",
    &[_]cetech1.strid.StrId64{},
    OnLoadTask.update,
);

//
// Nodes
//

const PRINT_NODE_TYPE = cetech1.strid.strId32("print");

const event_node_i = public.GraphNodeI.implement(
    .{
        .name = "Event Init",
        .type_hash = public.EVENT_INIT_NODE_TYPE,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();
        const flow_in = public.NodePin.pinHash("flow", false);

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
                public.NodePin{
                    .name = "Flow",
                    .pin_hash = Self.flow_in,
                    .type_hash = public.PinTypes.Flow,
                },
            });
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }
    },
);

const PrintNodeState = struct {
    input_validity: public.ValidityHash = 0,
};

const print_node_i = public.GraphNodeI.implement(
    .{
        .name = "Print",
        .type_hash = PRINT_NODE_TYPE,
    },
    PrintNodeState,
    struct {
        const Self = @This();
        const flow_in = public.NodePin.pinHash("flow", false);
        const int_in = public.NodePin.pinHash("int", false);

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin{
                    .name = "Flow",
                    .pin_hash = Self.flow_in,
                    .type_hash = public.PinTypes.Flow,
                },
                public.NodePin{
                    .name = "Int",
                    .pin_hash = Self.int_in,
                    .type_hash = public.PinTypes.I32,
                },
            });
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn create(state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId) !void {
            _ = db; // autofix
            _ = node_obj; // autofix
            const real_state: *PrintNodeState = @alignCast(@ptrCast(state));
            real_state.* = .{};
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = out_pins;
            var state = args.getState(PrintNodeState).?;

            const in_flow = in_pins.read(bool, 0).?;
            const in_int = in_pins.read(i32, 1).?;

            if (state.input_validity == in_int[0]) return;

            log.debug("{any} {any}", .{ in_flow, in_int });
            state.input_validity = in_int[0];
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
        .type_hash = strid.strId32("const"),
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

                    return allocator.dupe(public.NodePin, &.{public.NodePin{
                        .name = "Value",
                        .pin_hash = cetech1.strid.strId32("value"),
                        .type_hash = value_type.type_hash,
                    }});
                }
            }

            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn create(state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId) !void {
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
            const s = args.settings orelse return;
            const real_state: *ConstNodeState = @alignCast(@ptrCast(args.state));
            const version = args.db.getVersion(s);

            if (version == real_state.version) return;
            real_state.version = version;

            // TODO: FIx read real_state
            const settings_r = public.ConstNodeSettings.read(args.db, s).?;
            if (public.ConstNodeSettings.readSubObj(args.db, settings_r, .value)) |value_obj| {
                const value_type = findValueTypeIByCdb(cetech1.strid.strId32(args.db.getTypeName(value_obj.type_idx).?)).?;
                real_state.value_type = value_type;
                real_state.value_obj = value_obj;
            }

            var value: [2048]u8 = undefined;
            try real_state.value_type.valueFromCdb(args.db, real_state.value_obj, value[0..real_state.value_type.size]);
            const vh = try real_state.value_type.calcValidityHash(value[0..real_state.value_type.size]);
            try out_pins.write(0, vh, value[0..real_state.value_type.size]);
        }
    },
);

const culling_volume_node_i = public.GraphNodeI.implement(
    .{
        .name = "Culling volume",
        .type_hash = public.CULLING_VOLUME_NODE_TYPE,
        .pivot = .pivot,
        .category = "Culling",
    },
    cetech1.renderer.CullingVolume,
    struct {
        const Self = @This();
        const radius_in = public.NodePin.pinHash("radius", false);

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{
                public.NodePin{
                    .name = "Radius",
                    .pin_hash = Self.radius_in,
                    .type_hash = public.PinTypes.F32,
                },
            });
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(public.NodePin, &.{});
        }

        pub fn create(state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId) !void {
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
    },
);

// Inputs

const graph_inputs_i = public.GraphNodeI.implement(
    .{
        .name = "Graph Inputs",
        .type_hash = strid.strId32("graph_inputs"),
        .category = "Interface",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
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

                        try pins.append(public.NodePin{
                            .name = name,
                            .pin_hash = cetech1.strid.strId32(str),
                            .type_hash = value_type.type_hash,
                        });
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
                    out_pins.data.?[idx][0 .. @sizeOf(public.ValidityHash) + value_type.size],
                    graph_in_pins.data.?[idx][0 .. @sizeOf(public.ValidityHash) + value_type.size],
                );
            }
        }
    },
);

const graph_outputs_i = public.GraphNodeI.implement(
    .{
        .name = "Graph Outputs",
        .type_hash = strid.strId32("graph_outputs"),
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

                        try pins.append(public.NodePin{
                            .name = name,
                            .pin_hash = cetech1.strid.strId32(str),
                            .type_hash = value_type.type_hash,
                        });
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
                    graph_out_pins.data.?[idx][0 .. @sizeOf(public.ValidityHash) + value_type.size],
                    in_pins.data.?[idx].?[0 .. @sizeOf(public.ValidityHash) + value_type.size],
                );
            }
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
        .type_hash = strid.strId32("call_graph"),
        .category = "Interface",
        //.pivot = .flow,
        .settings_type = public.CallGraphNodeSettings.type_hash,
    },
    CallGraphNodeState,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const public.NodePin {
            _ = graph_obj; // autofix
            var pins = std.ArrayList(public.NodePin).init(allocator);

            const node_obj_r = public.NodeType.read(db, node_obj).?;

            if (public.NodeType.readSubObj(db, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(db, settings).?;
                if (public.CallGraphNodeSettings.readRef(db, settings_r, .graph)) |graph| {
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

                                try pins.append(public.NodePin{
                                    .name = name,
                                    .pin_hash = cetech1.strid.strId32(str),
                                    .type_hash = value_type.type_hash,
                                });
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
                if (public.CallGraphNodeSettings.readRef(db, settings_r, .graph)) |graph| {
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

                                try pins.append(public.NodePin{
                                    .name = name,
                                    .pin_hash = cetech1.strid.strId32(str),
                                    .type_hash = value_type.type_hash,
                                });
                            }
                        }
                    }
                }
            }

            return try pins.toOwnedSlice();
        }

        pub fn create(state: *anyopaque, db: cetech1.cdb.Db, node_obj: cetech1.cdb.ObjId) !void {
            const real_state: *CallGraphNodeState = @alignCast(@ptrCast(state));
            real_state.* = .{};

            const node_obj_r = public.NodeType.read(db, node_obj).?;
            if (public.NodeType.readSubObj(db, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(db, settings).?;
                if (public.CallGraphNodeSettings.readRef(db, settings_r, .graph)) |graph| {
                    //real_state.graph = graph;
                    real_state.instance = try createInstance(db, graph);
                }
            }
        }

        pub fn destroy(state: *anyopaque, db: cetech1.cdb.Db) !void {
            _ = db; // autofix
            const real_state: *CallGraphNodeState = @alignCast(@ptrCast(state));
            if (real_state.instance) |instance| {
                destroyInstance(instance);
            }
        }

        pub fn title(
            allocator: std.mem.Allocator,
            db: cetech1.cdb.Db,
            node_obj: cetech1.cdb.ObjId,
        ) ![:0]const u8 {
            const node_obj_r = public.NodeType.read(db, node_obj).?;

            if (public.NodeType.readSubObj(db, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(db, settings).?;
                if (public.CallGraphNodeSettings.readRef(db, settings_r, .graph)) |graph| {
                    const graph_asset = assetdb_private.api.getAssetForObj(graph) orelse return allocator.dupeZ(u8, "");
                    const name = cetech1.assetdb.Asset.readStr(db, db.readObj(graph_asset).?, .Name) orelse return allocator.dupeZ(u8, "");
                    return allocator.dupeZ(u8, name);
                }
            }
            return allocator.dupeZ(u8, "");
        }

        pub fn execute(args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            const real_state: *CallGraphNodeState = @alignCast(@ptrCast(args.state));
            if (real_state.instance) |instance| {

                // Write node inputs to graph inputs
                const graph_in_pins = api.getInputPins(instance);
                for (args.inputs, 0..) |input, idx| {
                    const value_type = findValueTypeI(input.type_hash).?;

                    if (in_pins.data.?[idx] == null) continue;

                    @memcpy(
                        graph_in_pins.data.?[idx][0 .. @sizeOf(public.ValidityHash) + value_type.size],
                        in_pins.data.?[idx].?[0 .. @sizeOf(public.ValidityHash) + value_type.size],
                    );
                }

                // Execute graph
                try api.executeNode(&.{instance}, graph_outputs_i.type_hash);

                // Write  graph outputs to node outpus
                const graph_out_pins = api.getOutputPins(instance);
                for (args.outputs, 0..) |input, idx| {
                    const value_type = findValueTypeI(input.type_hash).?;

                    @memcpy(
                        out_pins.data.?[idx][0 .. @sizeOf(public.ValidityHash) + value_type.size],
                        graph_out_pins.data.?[idx][0 .. @sizeOf(public.ValidityHash) + value_type.size],
                    );
                }
            }
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
            return @intCast(@as(i32, @bitCast(v.*)));
        }
    },
);
