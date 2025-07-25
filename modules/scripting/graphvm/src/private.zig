// TODO: SHIT
const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;

const public = @import("graphvm.zig");

const basic_nodes = @import("basic_nodes.zig");

const module_name = .graphvm;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _assetdb: *const cetech1.assetdb.AssetDBAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    vm_pool: VMPool = undefined,
    vm_map: VMMap = undefined,
    instance_pool: ContainerPool = undefined,
    nodetype_i_version: cetech1.apidb.InterfaceVersion = 0,
    valuetype_i_version: cetech1.apidb.InterfaceVersion = 0,
    node_type_iface_map: NodeTypeIfaceMap = undefined,
    value_type_iface_map: ValueTypeIfaceMap = undefined,
    value_type_iface_cdb_map: ValueTypeIfaceMap = undefined,
    graph_to_compile: ChangedObjsSet = undefined,
    string_intern: StringIntern = undefined,
};
var _g: *G = undefined;

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "GraphVMInit",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            _g.vm_map = .{};
            _g.vm_pool = try VMPool.initPreheated(_allocator, 1024);

            _g.instance_pool = try ContainerPool.initPreheated(_allocator, 1024);

            _g.node_type_iface_map = .{};

            _g.value_type_iface_map = .{};
            _g.value_type_iface_cdb_map = .{};
            _g.string_intern = StringIntern.init(_allocator);
            _g.graph_to_compile = ChangedObjsSet{};
        }

        pub fn shutdown() !void {
            for (_g.vm_map.values()) |value| {
                value.deinit();
            }

            _g.instance_pool.deinit();
            _g.vm_map.deinit(_allocator);
            _g.vm_pool.deinit();

            _g.node_type_iface_map.deinit(_allocator);
            _g.value_type_iface_map.deinit(_allocator);
            _g.value_type_iface_cdb_map.deinit(_allocator);
            _g.string_intern.deinit();
            _g.graph_to_compile.deinit(_allocator);
        }
    },
);

const VMNodeIdx = usize;

const Connection = struct {
    node: VMNodeIdx,
    pin: cetech1.StrId32,
    pin_type: cetech1.StrId32,
    pin_idx: u32 = 0,
};

const ConnectionPair = struct {
    from: Connection,
    to: Connection,
};

const GraphNode = struct {
    parent: cdb.ObjId,
    node: cdb.ObjId,
};

const NodeTypeIfaceMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.NodeI);
const ValueTypeIfaceMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *const public.GraphValueTypeI);
const VMNodeMap = cetech1.AutoArrayHashMap(GraphNode, VMNodeIdx);
const ConnectionPairList = cetech1.ArrayList(ConnectionPair);
const ContainerPool = cetech1.heap.PoolWithLock(VMInstance);
const InstanceSet = cetech1.AutoArrayHashMap(*VMInstance, void);
const NodeIdxPlan = cetech1.AutoArrayHashMap(VMNodeIdx, []VMNodeIdx);
const VMPool = cetech1.heap.PoolWithLock(GraphVM);
const VMMap = cetech1.AutoArrayHashMap(cdb.ObjId, *GraphVM);
const VMNodeByTypeMap = cetech1.AutoArrayHashMap(cetech1.StrId32, cetech1.ArrayList(VMNodeIdx));
const ObjSet = cetech1.ArraySet(cdb.ObjId);
const IdxSet = cetech1.ArraySet(VMNodeIdx);
const NodeSet = cetech1.ArraySet(GraphNode);
const ObjArray = cetech1.cdb.ObjIdList;

const NodePrototypeMap = cetech1.AutoArrayHashMap(cdb.ObjId, cdb.ObjId);

const TranspileStateMap = cetech1.AutoArrayHashMap(VMNodeIdx, []u8);
const TranspilerNodeMap = cetech1.AutoArrayHashMap(VMNodeIdx, VMNodeIdx);

//
const NodeKey = struct {
    obj: cdb.ObjId,
    pin: cetech1.StrId32,
};

const NodeValue = struct {
    graph: cdb.ObjId,
    obj: cdb.ObjId,
    pin: cetech1.StrId32,
};

const NodeValueSet = cetech1.ArraySet(NodeValue);
const NodeMap = cetech1.AutoArrayHashMap(NodeKey, NodeValueSet);

const OutConnection = struct {
    graph: cdb.ObjId,
    c: cdb.ObjId,
};
const OutConnectionArray = cetech1.ArrayList(OutConnection);
//

const InputPinData = struct {
    const Self = @This();

    data: ?[]?[*]u8 = null,
    validity_hash: ?[]?*public.ValidityHash = null,
    types: ?[]?cetech1.StrId32 = null,

    pub fn init() Self {
        return Self{};
    }

    pub fn fromPins(self: *Self, allocator: std.mem.Allocator, blob_size: usize, pins: []const public.NodePin) !void {
        if (blob_size != 0) {
            self.data = try allocator.alloc(?[*]u8, pins.len);
            @memset(self.data.?, null);

            self.validity_hash = try allocator.alloc(?*public.ValidityHash, pins.len);
            @memset(self.validity_hash.?, null);

            self.types = try allocator.alloc(?cetech1.StrId32, pins.len);
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

const OutputPinData = struct {
    const Self = @This();

    data: ?[]u8 = null,
    data_slices: ?[][*]u8 = null,

    validity_hash: ?[]public.ValidityHash = null,
    types: ?[]cetech1.StrId32 = null,

    pub fn init() Self {
        return Self{};
    }

    pub fn fromPins(self: *Self, allocator: std.mem.Allocator, blob_size: usize, pins: []const public.NodePin) !void {
        if (blob_size != 0) {
            self.data_slices = try allocator.alloc([*]u8, pins.len);
            self.data = try allocator.alloc(u8, blob_size);
            @memset(self.data.?, 0);

            self.types = try allocator.alloc(cetech1.StrId32, pins.len);
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

    in_data: InputPinData,
    out_data: OutputPinData,
    state: ?*anyopaque = null,

    last_inputs_validity_hash: []public.ValidityHash = undefined,

    vmnode_idx: VMNodeIdx,

    eval: bool = false,

    pub fn init(
        data_alloc: std.mem.Allocator,
        state: ?*anyopaque,
        pin_def: public.NodePinDef,
        input_blob_size: usize,
        output_blob_size: usize,
        vmnode_idx: VMNodeIdx,
    ) !Self {
        var self = Self{
            .in_data = InputPinData.init(),
            .out_data = OutputPinData.init(),
            .state = state,
            .vmnode_idx = vmnode_idx,
        };

        try self.in_data.fromPins(data_alloc, input_blob_size, pin_def.in);
        try self.out_data.fromPins(data_alloc, output_blob_size, pin_def.out);

        self.last_inputs_validity_hash = try _allocator.alloc(public.ValidityHash, pin_def.in.len);
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
    node_obj: cdb.ObjId,
    settings: ?cdb.ObjId,

    allocator: std.mem.Allocator,

    iface: *const public.NodeI,

    pin_def: public.NodePinDef = undefined,

    input_blob_size: usize = 0,
    output_blob_size: usize = 0,

    data_map: public.PinDataIdxMap = .{},

    has_flow: bool = false,
    has_flow_out: bool = false,

    cdb_version: cdb.ObjVersion = 0,
    is_init: bool = false,

    pub fn init(allocator: std.mem.Allocator, iface: *const public.NodeI, settings: ?cdb.ObjId, node_obj: cdb.ObjId, cdb_version: cdb.ObjVersion) Self {
        return Self{
            .allocator = allocator,
            .iface = iface,
            .cdb_version = cdb_version,
            .node_obj = node_obj,
            .settings = settings,
            .is_init = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.is_init) return;
        self.data_map.deinit(self.allocator);
        self.pin_def.deinit(self.allocator);
        self.is_init = false;
    }

    pub fn clean(self: *Self) void {
        self.data_map.clearRetainingCapacity();
        self.pin_def.deinit(self.allocator);
    }

    fn getOutputPinsSize(self: *Self, pins: []const public.NodePin) !usize {
        var size: usize = 0;

        for (pins, 0..) |pin, idx| {
            try self.data_map.put(self.allocator, pin.pin_hash, @intCast(idx));

            if (!pin.type_hash.isEmpty()) {
                const type_def = findValueTypeI(pin.type_hash);
                if (type_def) |td| {
                    size += td.size;
                }
            }
            // const alignn = std.mem.alignForwardLog2(size, @intCast(type_def.alignn)) - size;

        }

        return size;
    }

    fn getInputPinsSize(self: *Self, pins: []const public.NodePin) !usize {
        const size: usize = @sizeOf(?*anyopaque) * pins.len;

        for (pins, 0..) |pin, idx| {
            try self.data_map.put(self.allocator, pin.pin_hash, @intCast(idx));
        }

        return size;
    }
};

const VMInstance = struct {
    const Self = @This();
    const InstanceNodeMap = cetech1.AutoArrayHashMap(cdb.ObjId, *InstanceNode);

    const InstanceNodeIdxMap = cetech1.AutoArrayHashMap(GraphNode, VMInstanceNodeIdx);
    const InstanceNodeMultiArray = std.MultiArrayList(InstanceNode);

    const DataHolder = cetech1.ByteList;
    const StateHolder = cetech1.ByteList;
    const ContextMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *anyopaque);

    allocator: std.mem.Allocator,
    vm: *GraphVM,

    node_idx_map: InstanceNodeIdxMap = .{},
    nodes: InstanceNodeMultiArray = .{},

    context_map: ContextMap = .{},

    graph_in: OutputPinData,
    graph_out: OutputPinData,
    graph_data: OutputPinData,

    node_arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, vm: *GraphVM) Self {
        return Self{
            .allocator = allocator,
            .vm = vm,
            .graph_in = OutputPinData.init(),
            .graph_out = OutputPinData.init(),
            .graph_data = OutputPinData.init(),
            .node_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        const ifaces = self.vm.vmnodes.items(.iface);

        for (0..self.nodes.len) |idx| {
            var v = self.nodes.get(idx);
            if (v.state) |state| {
                const iface = ifaces[v.vmnode_idx];
                if (iface.destroy) |destroy| {
                    destroy(iface, state, false) catch undefined;
                }
            }
            v.deinit();
        }

        self.clean() catch undefined;

        self.context_map.deinit(self.allocator);
        self.node_idx_map.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.node_arena.deinit();
    }

    pub fn clean(self: *Self) !void {
        self.context_map.clearRetainingCapacity();

        self.node_idx_map.clearRetainingCapacity();
        self.nodes.clearRetainingCapacity();

        self.graph_in.deinit(self.allocator);
        self.graph_out.deinit(self.allocator);
        self.graph_data.deinit(self.allocator);
    }

    pub fn setContext(self: *Self, context_name: cetech1.StrId32, context: *anyopaque) !void {
        try self.context_map.put(self.allocator, context_name, context);
    }

    pub fn getContext(self: *Self, context_name: cetech1.StrId32) ?*anyopaque {
        return self.context_map.get(context_name);
    }

    pub fn removeContext(self: *Self, context_name: cetech1.StrId32) void {
        _ = self.context_map.swapRemove(context_name);
    }
};

const RebuildTask = struct {
    instances: []const *VMInstance,
    changed_nodes: *const IdxSet,
    deleted_nodes: *const NodeSet,

    pub fn exec(self: *const @This()) !void {
        const alloc = try _tmpalloc.create();
        defer _tmpalloc.destroy(alloc);

        var vm = self.instances[0].vm;
        try vm.buildInstances(alloc, self.instances, self.deleted_nodes, self.changed_nodes);
    }
};
const VMNodeMultiArray = std.MultiArrayList(VMNode);
const PivotList = cetech1.ArrayList(VMNodeIdx);

const DataConnection = struct {
    graph: cdb.ObjId,
    to_node_idx: usize,
    to_node_pin_idx: usize,
    pin_hash: cetech1.StrId32,
    pin_type: cetech1.StrId32,
    value_i: *const public.GraphValueTypeI,
    value_obj: cdb.ObjId,
};
const DataList = cetech1.ArrayList(DataConnection);

const OutDataConnection = struct {
    graph: cdb.ObjId,
    to_node: cdb.ObjId,

    pin_hash: cetech1.StrId32,
    pin_type: cetech1.StrId32,
    value_i: *const public.GraphValueTypeI,
    value_obj: cdb.ObjId,
};
const OutDataList = cetech1.ArrayList(OutDataConnection);

const ToFromConMap = std.AutoHashMap(struct { VMNodeIdx, cetech1.StrId32 }, struct { VMNodeIdx, cetech1.StrId32 });

const PinValueTypeMap = cetech1.AutoArrayHashMap(struct { VMNodeIdx, cetech1.StrId32 }, cetech1.StrId32);
const PinDataTypeMap = cetech1.AutoArrayHashMap(struct { VMNodeIdx, u32 }, cetech1.StrId32);

const GraphVM = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    graph_obj: cdb.ObjId,
    graph_version: cdb.ObjVersion = 0,

    node_idx_map: VMNodeMap,
    vmnodes: VMNodeMultiArray = .{},

    free_idx: IdxSet,

    connection: ConnectionPairList = .{},
    data_list: DataList = .{},

    instance_set: InstanceSet,

    node_plan: NodeIdxPlan,
    plan_arena: std.heap.ArenaAllocator,

    transpile_arena: std.heap.ArenaAllocator,
    transpile_state_map: TranspileStateMap,
    transpile_map: TranspilerNodeMap,

    inputs: ?[]const public.NodePin = null,
    outputs: ?[]const public.NodePin = null,

    datas: ?[]const public.NodePin = null,

    node_by_type: VMNodeByTypeMap,

    output_blob_size: usize = 0,
    input_blob_size: usize = 0,
    data_blob_size: usize = 0,

    pub fn init(allocator: std.mem.Allocator, graph: cdb.ObjId) Self {
        return Self{
            .allocator = allocator,
            .graph_obj = graph,
            .instance_set = .{},
            .node_plan = .{},
            .node_by_type = .{},
            .node_idx_map = .{},
            .free_idx = IdxSet.init(),
            .plan_arena = std.heap.ArenaAllocator.init(allocator),

            .transpile_arena = std.heap.ArenaAllocator.init(allocator),
            .transpile_state_map = .{},
            .transpile_map = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        //        self.clean();

        for (self.node_by_type.values()) |*value| {
            value.deinit(self.allocator);
        }

        for (self.instance_set.keys()) |value| {
            value.deinit();
        }

        // for (self.node_plan.values()) |value| {
        //     self.allocator.free(value);
        // }

        if (self.inputs) |inputs| {
            self.allocator.free(inputs);
        }

        if (self.outputs) |outputs| {
            self.allocator.free(outputs);
        }

        if (self.datas) |datas| {
            self.allocator.free(datas);
        }

        for (0..self.vmnodes.len) |idx| {
            if (self.free_idx.contains(idx)) continue;
            var node = self.vmnodes.get(idx);
            node.deinit();
        }

        for (self.transpile_state_map.keys(), self.transpile_state_map.values()) |k, v| {
            const ifaces = self.vmnodes.items(.iface);
            const iface = ifaces[k];
            if (iface.destroyTranspileState) |destroyTranspileState| {
                destroyTranspileState(iface, v);
            }
        }

        self.transpile_map.deinit(self.allocator);

        self.node_plan.deinit(self.allocator);
        self.plan_arena.deinit();

        self.transpile_arena.deinit();
        self.transpile_state_map.deinit(self.allocator);

        self.connection.deinit(self.allocator);
        self.data_list.deinit(self.allocator);

        self.instance_set.deinit(self.allocator);
        self.node_by_type.deinit(self.allocator);

        self.vmnodes.deinit(self.allocator);
        self.node_idx_map.deinit(self.allocator);
        self.free_idx.deinit(self.allocator);
    }

    pub fn clean(self: *Self) !void {
        for (self.instance_set.keys()) |value| {
            try value.clean();
        }

        // for (self.node_plan.values()) |value| {
        //     self.allocator.free(value);
        // }

        for (self.node_by_type.values()) |*value| {
            value.clearRetainingCapacity();
        }

        for (self.transpile_state_map.keys(), self.transpile_state_map.values()) |k, v| {
            const ifaces = self.vmnodes.items(.iface);
            const iface = ifaces[k];
            if (iface.destroyTranspileState) |destroyTranspileState| {
                destroyTranspileState(iface, v);
            }
        }

        self.transpile_map.clearRetainingCapacity();

        self.node_plan.clearRetainingCapacity();
        _ = self.plan_arena.reset(.retain_capacity);

        _ = self.transpile_arena.reset(.retain_capacity);
        self.transpile_state_map.clearRetainingCapacity();

        self.connection.clearRetainingCapacity();
        self.data_list.clearRetainingCapacity();

        if (self.inputs) |inputs| {
            self.allocator.free(inputs);
            self.inputs = null;
        }

        if (self.outputs) |outputs| {
            self.allocator.free(outputs);
            self.outputs = null;
        }

        if (self.datas) |datas| {
            self.allocator.free(datas);
            self.datas = null;
        }
    }

    fn findNodeByType(self: Self, node_type: cetech1.StrId32) ?[]VMNodeIdx {
        var zone_ctx = _profiler.Zone(@src());
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
        parent_graph: cdb.ObjId,
        node: cdb.ObjId,
        node_prototype_map: *NodePrototypeMap,
        pivots: *PivotList,
        changed_nodes: *IdxSet,
        root: bool,
    ) anyerror!void {
        _ = root; // autofix

        var cdb_versions = self.vmnodes.items(.cdb_version);

        const node_r = _cdb.readObj(node).?;
        const type_hash = public.NodeType.f.getNodeTypeId(_cdb, node_r);
        const iface = findNodeI(type_hash).?;

        const prototype = _cdb.getPrototype(node_r);
        const node_version = _cdb.getVersion(node);

        //log.debug("addNode graph {any}", .{parent_graph});

        const node_idx_get = try self.node_idx_map.getOrPut(
            self.allocator,
            .{ .parent = parent_graph, .node = node },
        );

        // TODO: remove orphans nodes => exist in node_map but not in graph (need set)
        const exist = node_idx_get.found_existing;
        const regen = if (exist) cdb_versions[node_idx_get.value_ptr.*] != node_version else false;

        if (exist) {
            cdb_versions[node_idx_get.value_ptr.*] = node_version;
        }

        const settings = public.NodeType.readSubObj(_cdb, node_r, .settings);

        if (!prototype.isEmpty()) {
            try node_prototype_map.put(allocator, prototype, node);
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
            try self.buildVMNodes(node_idx, self.graph_obj, node);
            _ = try changed_nodes.add(self.allocator, node_idx);
        }

        if (iface.pivot != .none) {
            try pivots.append(self.allocator, node_idx);
        }

        const node_type_get = try self.node_by_type.getOrPut(self.allocator, iface.type_hash);
        if (!node_type_get.found_existing) {
            node_type_get.value_ptr.* = .{};
        }
        try node_type_get.value_ptr.*.append(self.allocator, node_idx);
    }

    fn addNodes(
        self: *Self,
        allocator: std.mem.Allocator,
        graph: cdb.ObjId,
        node_prototype_map: *NodePrototypeMap,
        pivots: *PivotList,
        changed_nodes: *IdxSet,
        used_nodes: *NodeSet,
        node_map: *NodeMap,
        node_backward_map: *NodeMap,
        out_connections: *OutConnectionArray,
        out_data: *OutDataList,
        parent_node: ?cdb.ObjId,
        root: bool,
    ) !void {
        const graph_r = _cdb.readObj(graph).?;

        // Nodes
        const nodes = (try public.GraphType.readSubObjSet(_cdb, graph_r, .nodes, allocator)).?;
        defer allocator.free(nodes);

        const connections = (try public.GraphType.readSubObjSet(_cdb, graph_r, .connections, allocator)).?;
        defer allocator.free(connections);

        try self.vmnodes.ensureUnusedCapacity(self.allocator, nodes.len);

        for (nodes) |node| {
            _ = try used_nodes.add(allocator, .{ .node = node, .parent = graph });
        }

        // Add node expect subgraph
        for (nodes) |node| {
            const node_r = _cdb.readObj(node).?;
            const type_hash = public.NodeType.f.getNodeTypeId(_cdb, node_r);
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
                const s = public.NodeType.readSubObj(_cdb, node_r, .settings) orelse continue;
                const s_r = public.CallGraphNodeSettings.read(_cdb, s).?;
                if (public.CallGraphNodeSettings.readSubObj(_cdb, s_r, .graph)) |sub_graph| {
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
                        out_data,
                        node,
                        false,
                    );
                }
                continue;
            } else {
                try self.addNode(allocator, graph, node, node_prototype_map, pivots, changed_nodes, root);
            }
        }

        for (connections) |connection| {
            const connection_r = _cdb.readObj(connection).?;
            var from_node_obj = public.ConnectionType.readRef(_cdb, connection_r, .from_node).?;
            const from_pin = public.ConnectionType.f.getFromPinId(_cdb, connection_r);

            var to_node_obj = public.ConnectionType.readRef(_cdb, connection_r, .to_node).?;
            const to_pin = public.ConnectionType.f.getToPinId(_cdb, connection_r);

            // Rewrite connection from prototype
            if (node_prototype_map.get(from_node_obj)) |node| {
                from_node_obj = node;
            }
            if (node_prototype_map.get(to_node_obj)) |node| {
                to_node_obj = node;
            }

            const from_node_obj_r = _cdb.readObj(from_node_obj).?;
            const from_node_type = public.NodeType.f.getNodeTypeId(_cdb, from_node_obj_r);
            const from_subgraph = call_graph_node_i.type_hash.eql(from_node_type);
            const from_inputs = graph_inputs_i.type_hash.eql(from_node_type);
            const from_node = !from_subgraph and !from_inputs;

            const to_node_obj_r = _cdb.readObj(to_node_obj).?;
            const to_node_type = public.NodeType.f.getNodeTypeId(_cdb, to_node_obj_r);
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
                const get = try node_map.getOrPut(allocator, .{ .obj = from_node_obj, .pin = from_pin });
                if (!get.found_existing) {
                    get.value_ptr.* = .init();
                }
                _ = try get.value_ptr.*.add(self.allocator, NodeValue{ .graph = graph, .obj = to_node_obj, .pin = to_pin });
            }

            // TO => FROM
            // Backward
            {
                const get = try node_backward_map.getOrPut(allocator, .{ .obj = to_node_obj, .pin = to_pin });
                if (!get.found_existing) {
                    get.value_ptr.* = .init();
                }
                _ = try get.value_ptr.*.add(self.allocator, NodeValue{ .graph = graph, .obj = from_node_obj, .pin = from_pin });
            }

            if (from_node or to_node) {
                try out_connections.append(allocator, .{ .c = connection, .graph = graph });
            }
        }

        // Data
        if (try public.GraphType.readSubObjSet(_cdb, graph_r, .data, allocator)) |datas| {
            for (datas) |data| {
                const data_r = public.GraphDataType.read(_cdb, data).?;
                const value_obj = public.GraphDataType.readSubObj(_cdb, data_r, .value).?;
                const db = _cdb.getDbFromObjid(value_obj);

                const type_def = findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;

                const to_node = public.GraphDataType.readRef(_cdb, data_r, .to_node).?;
                const to_node_pin_str = public.GraphDataType.readStr(_cdb, data_r, .to_node_pin).?;

                const to_node_pin = cetech1.strId32(to_node_pin_str);

                try out_data.append(
                    allocator,
                    OutDataConnection{
                        .graph = graph,
                        .pin_type = type_def.type_hash,
                        .pin_hash = to_node_pin,
                        .to_node = to_node,
                        .value_i = type_def,
                        .value_obj = value_obj,
                    },
                );
            }
        }
    }

    fn buildGraph(
        self: *Self,
        allocator: std.mem.Allocator,
        graph: cdb.ObjId,
        parent_node: ?cdb.ObjId,
        node_prototype_map: *NodePrototypeMap,
        pivots: *PivotList,
        changed_nodes: *IdxSet,
        used_nodes: *NodeSet,
        node_map: *NodeMap,
        node_backward_map: *NodeMap,
        out_connections: *OutConnectionArray,
        out_data: *OutDataList,
        root: bool,
    ) !void {
        const graph_r = _cdb.readObj(graph).?;

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
            out_data,
            parent_node,
            root,
        );

        // Now scan for CallGraph node and build
        const nodes = (try public.GraphType.readSubObjSet(_cdb, graph_r, .nodes, allocator)).?;
        defer allocator.free(nodes);
        for (nodes) |node| {
            const node_r = _cdb.readObj(node).?;
            const type_hash = public.NodeType.f.getNodeTypeId(_cdb, node_r);
            const iface = findNodeI(type_hash).?;
            _ = iface; // autofix

            if (type_hash.eql(call_graph_node_i.type_hash)) {
                const s = public.NodeType.readSubObj(_cdb, node_r, .settings) orelse continue;
                const s_r = public.CallGraphNodeSettings.read(_cdb, s).?;
                if (public.CallGraphNodeSettings.readSubObj(_cdb, s_r, .graph)) |sub_graph| {
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
                        out_data,
                        false,
                    );
                }
            }
        }
    }

    fn collectNodePoints(self: *Self, allcator: std.mem.Allocator, outs: *NodeValueSet, node_map: *NodeMap, node_obj: cdb.ObjId, pin: cetech1.StrId32) !void {
        if (node_map.get(.{ .obj = node_obj, .pin = pin })) |nexts| {
            var it = nexts.iterator();
            while (it.next()) |v| {
                const node_obj_r = _cdb.readObj(v.key_ptr.obj).?;
                const node_type = public.NodeType.f.getNodeTypeId(_cdb, node_obj_r);
                const from_subgraph = call_graph_node_i.type_hash.eql(node_type);

                if (from_subgraph) {
                    try self.collectNodePoints(allcator, outs, node_map, v.key_ptr.obj, v.key_ptr.pin);
                } else {
                    _ = try outs.add(allcator, v.key_ptr.*);
                }
            }
        }
    }

    pub fn buildVM(self: *Self, allocator: std.mem.Allocator) !void {
        var zone_ctx = _profiler.ZoneN(@src(), "GraphVM - build");
        defer zone_ctx.End();

        try self.clean();

        _ = _cdb.readObj(self.graph_obj);

        const graph_version = _cdb.getVersion(self.graph_obj);
        self.graph_version = graph_version;

        var pivots = cetech1.ArrayList(VMNodeIdx){};
        defer pivots.deinit(allocator);

        var changed_nodes = IdxSet.init();
        defer changed_nodes.deinit(allocator);

        var deleted_nodes = NodeSet.init();
        defer deleted_nodes.deinit(allocator);

        var node_prototype_map = NodePrototypeMap{};
        defer node_prototype_map.deinit(allocator);

        var graph_nodes_set = NodeSet.init();
        defer graph_nodes_set.deinit(allocator);

        var out_data = OutDataList{};
        defer out_data.deinit(allocator);

        var node_map = NodeMap{};
        defer {
            for (node_map.values()) |*v| v.deinit(allocator);
            node_map.deinit(allocator);
        }

        var node_backward_map = NodeMap{};
        defer {
            for (node_backward_map.values()) |*v| v.deinit(allocator);
            node_backward_map.deinit(allocator);
        }

        var out_connections = OutConnectionArray{};
        defer out_connections.deinit(allocator);

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
            &out_data,
            true,
        );

        // for (self.node_idx_map.keys(), self.node_idx_map.values()) |k, v| {
        //     log.debug("node_idx_map => parent: {s} | node: {s} | {any} | {any}", .{
        //         try _assetdb.getOrCreateUuid(k.parent),
        //         try _assetdb.getOrCreateUuid(k.node),
        //         k,
        //         v,
        //     });
        // }

        const data_maps = self.vmnodes.items(.data_map);
        const pin_def = self.vmnodes.items(.pin_def);
        const output_blob_size = self.vmnodes.items(.output_blob_size);

        const ifaces = self.vmnodes.items(.iface);

        for (out_connections.items) |v| {
            const connection_r = _cdb.readObj(v.c).?;
            var from_node_obj = public.ConnectionType.readRef(_cdb, connection_r, .from_node).?;
            const from_pin = public.ConnectionType.f.getFromPinId(_cdb, connection_r);

            var to_node_obj = public.ConnectionType.readRef(_cdb, connection_r, .to_node).?;
            const to_pin = public.ConnectionType.f.getToPinId(_cdb, connection_r);

            // Rewrite connection from prototype
            if (node_prototype_map.get(from_node_obj)) |node| {
                from_node_obj = node;
            }
            if (node_prototype_map.get(to_node_obj)) |node| {
                to_node_obj = node;
            }

            const from_node_obj_r = _cdb.readObj(from_node_obj).?;
            const from_node_type = public.NodeType.f.getNodeTypeId(_cdb, from_node_obj_r);
            const from_subgraph = call_graph_node_i.type_hash.eql(from_node_type);
            const from_inputs = graph_inputs_i.type_hash.eql(from_node_type);
            const from_node = !from_subgraph and !from_inputs;

            const to_node_obj_r = _cdb.readObj(to_node_obj).?;
            const to_node_type = public.NodeType.f.getNodeTypeId(_cdb, to_node_obj_r);
            const to_subgraph = call_graph_node_i.type_hash.eql(to_node_type);
            const to_outputs = graph_outputs_i.type_hash.eql(to_node_type);
            const to_node = !to_subgraph and !to_outputs;

            if (!to_node) {
                var outs = NodeValueSet.init();
                defer outs.deinit(allocator);

                try self.collectNodePoints(allocator, &outs, &node_map, to_node_obj, to_pin);

                const node_from_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = from_node_obj });

                var it = outs.iterator();
                while (it.next()) |vv| {
                    const node_to_idx = self.node_idx_map.get(.{ .parent = vv.key_ptr.graph, .node = vv.key_ptr.obj });

                    if (node_to_idx == null) {
                        log.err("Invalid node_to_idx for node with UUID {any}", .{_assetdb.getUuid(vv.key_ptr.obj)});
                    }

                    const pin_type: cetech1.StrId32 = blk: {
                        for (pin_def[node_from_idx.?].out) |pin| {
                            if (pin.pin_hash.eql(from_pin)) break :blk pin.type_hash;
                        }
                        break :blk .{ .id = 0 };
                    };

                    try self.connection.append(
                        self.allocator,
                        .{
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
                        },
                    );
                }
            } else if (!from_node) {
                var outs = NodeValueSet.init();
                defer outs.deinit(allocator);

                try self.collectNodePoints(allocator, &outs, &node_backward_map, from_node_obj, from_pin);

                const node_to_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = to_node_obj });

                // const node_to_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = to_node_obj }) orelse {
                //     log.err("Could not find to_node_obj with UUID {s}", .{_assetdb.getUuid(to_node_obj).?});
                //     continue;
                // };

                var it = outs.iterator();
                while (it.next()) |vv| {
                    //const node_from_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = vv.key_ptr.obj }) orelse continue;

                    const node_from_idx = self.node_idx_map.get(.{ .parent = vv.key_ptr.graph, .node = vv.key_ptr.obj }) orelse {
                        log.err("Could not find vv.key_ptr.obj with UUID {s} in graph UUID {s}", .{ _assetdb.getUuid(vv.key_ptr.obj).?, _assetdb.getUuid(vv.key_ptr.graph).? });
                        continue;
                    };

                    const pin_type: cetech1.StrId32 = blk: {
                        for (pin_def[node_from_idx].out) |pin| {
                            if (pin.pin_hash.eql(from_pin)) break :blk pin.type_hash;
                        }
                        break :blk .{ .id = 0 };
                    };

                    try self.connection.append(
                        self.allocator,
                        .{
                            .from = .{
                                .node = node_from_idx,
                                .pin = vv.key_ptr.pin,
                                .pin_type = pin_type,
                                .pin_idx = data_maps[node_from_idx].get(vv.key_ptr.pin).?,
                            },
                            .to = .{
                                .node = node_to_idx.?,
                                .pin = to_pin,
                                .pin_type = pin_type,
                                .pin_idx = data_maps[node_to_idx.?].get(to_pin).?,
                            },
                        },
                    );
                }
            } else {
                const node_from_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = from_node_obj }) orelse {
                    log.err("Could not find from_node_obj with UUID {s}", .{_assetdb.getUuid(from_node_obj).?});
                    continue;
                };

                const node_to_idx = self.node_idx_map.get(.{ .parent = v.graph, .node = to_node_obj }) orelse {
                    log.err("Could not find to_node_obj with UUID {s}", .{_assetdb.getUuid(to_node_obj).?});
                    continue;
                };

                const pin_type: cetech1.StrId32 = blk: {
                    for (pin_def[node_from_idx].out) |pin| {
                        if (pin.pin_hash.eql(from_pin)) break :blk pin.type_hash;
                    }
                    break :blk .{ .id = 0 };
                };

                try self.connection.append(
                    self.allocator,
                    .{
                        .from = .{
                            .node = node_from_idx,
                            .pin = from_pin,
                            .pin_type = pin_type,
                            .pin_idx = data_maps[node_from_idx].get(from_pin).?,
                        },
                        .to = .{
                            .node = node_to_idx,
                            .pin = to_pin,
                            .pin_type = pin_type,
                            .pin_idx = data_maps[node_to_idx].get(to_pin).?,
                        },
                    },
                );
            }
        }

        // Expand datas across whole graph
        var node_data_type_map = PinDataTypeMap{};
        defer node_data_type_map.deinit(allocator);

        for (out_data.items) |data| {

            // Rewrite connection from prototype
            var to_node_obj = data.to_node;

            if (node_prototype_map.get(data.to_node)) |node| {
                to_node_obj = node;
            }

            const to_node_obj_r = _cdb.readObj(to_node_obj).?;
            const to_node_type = public.NodeType.f.getNodeTypeId(_cdb, to_node_obj_r);
            const to_subgraph = call_graph_node_i.type_hash.eql(to_node_type);
            const to_outputs = graph_outputs_i.type_hash.eql(to_node_type);
            const to_node = !to_subgraph and !to_outputs;

            // If data is wire to sungraph we need collect and wire it to all sub graph input "consumers".
            if (!to_node) {
                var outs = NodeValueSet.init();
                defer outs.deinit(allocator);

                try self.collectNodePoints(allocator, &outs, &node_map, to_node_obj, data.pin_hash);

                var it = outs.iterator();
                while (it.next()) |vv| {
                    const node_to_idx = self.node_idx_map.get(.{ .parent = data.graph, .node = vv.key_ptr.obj }).?;
                    const to_node_pin_idx = data_maps[node_to_idx].get(vv.key_ptr.pin).?;

                    try self.data_list.append(
                        allocator,
                        .{
                            .graph = data.graph,
                            .to_node_idx = node_to_idx,
                            .to_node_pin_idx = to_node_pin_idx,
                            .pin_hash = data.pin_hash,
                            .pin_type = data.pin_type,
                            .value_i = data.value_i,
                            .value_obj = data.value_obj,
                        },
                    );

                    try node_data_type_map.put(allocator, .{ node_to_idx, to_node_pin_idx }, data.pin_type);
                }

                // Data is wire to clasic node inputs
            } else {
                const node_to_idx = self.node_idx_map.get(.{ .parent = data.graph, .node = to_node_obj }).?;
                const to_node_pin_idx = data_maps[node_to_idx].get(data.pin_hash).?;

                try self.data_list.append(
                    self.allocator,
                    .{
                        .graph = data.graph,
                        .to_node_idx = node_to_idx,
                        .to_node_pin_idx = to_node_pin_idx,
                        .pin_hash = data.pin_hash,
                        .pin_type = data.pin_type,
                        .value_i = data.value_i,
                        .value_obj = data.value_obj,
                    },
                );
                try node_data_type_map.put(allocator, .{ node_to_idx, to_node_pin_idx }, data.pin_type);
            }
        }

        // Resolve pin types (need for generics)
        // TODO: SHIT
        {
            var dag = cetech1.dag.DAG(VMNodeIdx).init(allocator);
            defer dag.deinit();

            var to_from_map = ToFromConMap.init(allocator);
            defer to_from_map.deinit();

            var depends = cetech1.AutoArrayHashMap(VMNodeIdx, void){};
            defer depends.deinit(allocator);

            var resolved_pintype_map = PinValueTypeMap{};
            defer resolved_pintype_map.deinit(allocator);

            var patched_nodes = cetech1.ArrayList(VMNodeIdx){};
            defer patched_nodes.deinit(allocator);

            var fnn = cetech1.AutoArrayHashMap(VMNodeIdx, void){};
            defer fnn.deinit(allocator);

            // add all nodes
            for (0..self.vmnodes.len) |node_idx| {
                depends.clearRetainingCapacity();

                const vm_node = self.vmnodes.get(node_idx);
                _ = vm_node; // autofix
                // log.debug("\tdddd: {s} {s}", .{ _assetdb.getUuid(vm_node.node_obj).?, ifaces[node_idx].name });

                for (self.connection.items) |connect| {
                    const from_node = connect.from.node;
                    const from_pin = connect.from.pin;

                    const to_node = connect.to.node;
                    const to_pin = connect.to.pin;

                    // only conection to this node
                    if (to_node != node_idx) continue;

                    try to_from_map.put(.{ to_node, to_pin }, .{ from_node, from_pin });
                    try depends.put(allocator, from_node, {});
                }

                try dag.add(node_idx, depends.keys());
            }

            try dag.build_all();

            // for (dag.output.keys()) |node_idx| {
            //     const vm_node = self.vmnodes.get(node_idx);
            //     log.debug("\taaaaaa {s} {s}", .{ _assetdb.getUuid(vm_node.node_obj).?, ifaces[node_idx].name });
            // }

            // log.debug("Collect types:", .{});
            for (dag.output.keys()) |node_idx| {
                const vm_node = self.vmnodes.get(node_idx);
                _ = vm_node; // autofix
                // log.debug("\t{s} {s}", .{ _assetdb.getUuid(vm_node.node_obj).?, ifaces[node_idx].name });

                const in_pins = pin_def[node_idx].in;
                const out_pins = pin_def[node_idx].out;

                for (in_pins, 0..) |in_pin, pin_idx| {
                    const is_generic = in_pin.type_hash.eql(public.PinTypes.GENERIC);
                    if (is_generic) {
                        const data = node_data_type_map.get(.{ node_idx, @truncate(pin_idx) });

                        var resolved_type: cetech1.StrId32 = .{};
                        if (data) |d| {
                            resolved_type = d;
                        } else {
                            if (to_from_map.get(.{ node_idx, in_pin.pin_hash })) |from_node| {
                                resolved_type = resolved_pintype_map.get(from_node).?;
                            } else {
                                resolved_type = in_pin.type_hash;
                            }
                        }

                        try resolved_pintype_map.put(allocator, .{ node_idx, in_pin.pin_hash }, resolved_type);
                    } else {
                        try resolved_pintype_map.put(allocator, .{ node_idx, in_pin.pin_hash }, in_pin.type_hash);
                    }
                }

                for (out_pins, 0..) |out_pin, pin_idx| {
                    if (out_pin.type_of) |tof| {
                        const from_node_type = resolved_pintype_map.get(.{ node_idx, tof }).?;
                        try resolved_pintype_map.put(allocator, .{ node_idx, out_pin.pin_hash }, from_node_type);
                        pin_def[node_idx].out[pin_idx].type_hash = from_node_type;
                        try patched_nodes.append(allocator, node_idx);
                    } else {
                        try resolved_pintype_map.put(allocator, .{ node_idx, out_pin.pin_hash }, out_pin.type_hash);
                    }
                }
            }

            for (patched_nodes.items) |node_idx| {
                var vm_node = self.vmnodes.get(node_idx);
                const size = try vm_node.getOutputPinsSize(vm_node.pin_def.out);
                output_blob_size[node_idx] = size;
                log.debug("Pathed output type {s} {s}", .{ _assetdb.getUuid(vm_node.node_obj).?, ifaces[node_idx].name });
            }
        }

        //Find deleted nodes
        for (self.node_idx_map.keys(), self.node_idx_map.values()) |k, v| {
            if (graph_nodes_set.contains(k)) continue;
            log.debug("Delete node: {any} {any}", .{ k, v });
            _ = try deleted_nodes.add(allocator, k);
        }

        const root_graph_r = _cdb.readObj(self.graph_obj).?;

        //
        // Interafces
        //
        if (public.GraphType.readSubObj(_cdb, root_graph_r, .interface)) |interface_obj| {
            _ = interface_obj; // autofix

            const in_pin_def = try graph_inputs_i.getPinsDef(&graph_inputs_i, self.allocator, self.graph_obj, .{});
            const out_pin_def = try graph_outputs_i.getPinsDef(&graph_outputs_i, self.allocator, self.graph_obj, .{});

            self.inputs = in_pin_def.out;
            self.outputs = out_pin_def.in;

            self.input_blob_size = try GraphVM.computePinSize(self.inputs.?);
            self.output_blob_size = try GraphVM.computePinSize(self.outputs.?);
        }

        if (self.data_list.items.len != 0) {
            var fake_pins = try public.NodePinList.initCapacity(_allocator, self.data_list.items.len);

            var size: usize = 0;
            for (self.data_list.items) |data| {
                size += data.value_i.size;
                fake_pins.appendAssumeCapacity(public.NodePin.init("fake", "fake", data.value_i.type_hash, null));
            }
            self.data_blob_size = size;
            self.datas = try fake_pins.toOwnedSlice(_allocator);
        }

        //
        // Plan pivots.
        //
        var dag = cetech1.dag.DAG(VMNodeIdx).init(allocator);
        defer dag.deinit();
        const has_flow_outs = self.vmnodes.items(.has_flow_out);

        var plan_allocator = self.plan_arena.allocator();

        var transpile_pivots = cetech1.ArrayList(VMNodeIdx){};
        defer transpile_pivots.deinit(allocator);

        for (pivots.items) |pivot| {
            try dag.reset();
            const pivot_vmnode = pivot;
            const pivot_type = ifaces[pivot_vmnode].pivot;

            if (pivot_type == .transpiler) {
                try transpile_pivots.append(allocator, pivot);
            } else {
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
                    try self.inputDag(allocator, &dag, pivot, true, null);
                }

                try dag.build_all();

                try self.node_plan.put(self.allocator, pivot, try plan_allocator.dupe(VMNodeIdx, dag.output.keys()));

                log.debug("Plan for pivot \"{s}\":", .{ifaces[pivot_vmnode].name});
                for (dag.output.keys()) |node| {
                    const vmnode = node;
                    log.debug("\t - {s}", .{ifaces[vmnode].name});
                }
            }
        }

        //
        // Transpile
        // TODO: SHIT
        {
            const instances = try self.createInstances(allocator, 1);
            try self.buildInstances(allocator, instances, null, null);
            const instance = instances[0];
            defer self.destroyInstance(instance);

            for (transpile_pivots.items) |transpile_pivot| {
                const iface: *const public.NodeI = ifaces[transpile_pivot];

                const stages = try iface.getTranspileStages.?(iface, allocator);
                defer allocator.free(stages);

                const t_alloc = self.transpile_arena.allocator();
                const state = try iface.createTranspileState.?(iface, t_alloc);

                // Plan and exec nodes for stages
                for (stages) |stage| {
                    try dag.reset();

                    try self.inputDag(allocator, &dag, transpile_pivot, false, stage.pin_idx);
                    try dag.build_all();

                    const plan = dag.output.keys()[0 .. dag.output.keys().len - 1];

                    for (plan) |node| {
                        const vmnode = node;
                        const transpile_border = ifaces[vmnode].transpile_border;
                        if (transpile_border) {
                            try self.transpile_map.put(self.allocator, vmnode, transpile_pivot);
                        }
                    }

                    log.debug("Plan for transpile pivot \"{s}\":", .{ifaces[transpile_pivot].name});
                    for (dag.output.keys()) |node| {
                        const vmnode = node;
                        log.debug("\t - {s}", .{ifaces[vmnode].name});
                    }

                    // Transpile nodes for pivot
                    try self.transpileNodesMany(
                        allocator,
                        &.{.{ .graph = self.graph_obj, .inst = instance }},
                        iface.type_hash,
                        plan,
                        state,
                        stage.id,
                        stage.contexts.?,
                    );

                    // Transpile pivot for stage and context
                    try self.transpileNodesMany(
                        allocator,
                        &.{.{ .graph = self.graph_obj, .inst = instance }},
                        iface.type_hash,
                        &.{transpile_pivot},
                        state,
                        stage.id,
                        stage.contexts.?,
                    );
                }

                // Final transpile all
                try self.transpileNodesMany(
                    allocator,
                    &.{.{ .graph = self.graph_obj, .inst = instance }},
                    iface.type_hash,
                    &.{transpile_pivot},
                    state,
                    null,
                    null,
                );

                try self.transpile_state_map.put(self.allocator, transpile_pivot, state);
            }
        }

        try self.writePlanD2(allocator);

        //
        // Rebuild exist instances.
        //
        if (self.instance_set.count() != 0) {
            const ARGS = struct {
                items: []const *VMInstance,
                changed_nodes: *const IdxSet,
                deleted_nodes: *const NodeSet,
            };
            if (try cetech1.task.batchWorkloadTask(
                .{
                    .allocator = allocator,
                    .task_api = _task,
                    .profiler_api = _profiler,

                    .count = self.instance_set.keys().len,
                },
                ARGS{
                    .items = self.instance_set.keys(),
                    .changed_nodes = &changed_nodes,
                    .deleted_nodes = &deleted_nodes,
                },
                struct {
                    pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) RebuildTask {
                        return RebuildTask{
                            .instances = create_args.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                            .changed_nodes = create_args.changed_nodes,
                            .deleted_nodes = create_args.deleted_nodes,
                        };
                    }
                },
            )) |t| {
                _task.wait(t);
            }
        }

        var deleted_it = deleted_nodes.iterator();
        while (deleted_it.next()) |entry| {
            const node = entry.key_ptr.*;
            const idx = self.node_idx_map.get(node).?;

            var vmnode = self.vmnodes.get(idx);
            vmnode.deinit();

            _ = try self.free_idx.add(self.allocator, idx);
            _ = self.node_idx_map.swapRemove(node);
        }
    }

    pub fn buildInstances(self: *Self, allocator: std.mem.Allocator, instances: []const *VMInstance, deleted_nodes: ?*const NodeSet, changed_nodes: ?*const IdxSet) !void {
        var zone_ctx = _profiler.ZoneN(@src(), "GraphVM - Instance build many");
        defer zone_ctx.End();

        const ifaces = self.vmnodes.items(.iface);
        const vmnode_pin_def = self.vmnodes.items(.pin_def);
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

            // Graph fake data pins
            if (self.datas) |datas| {
                try vminstance.graph_data.fromPins(vminstance.allocator, self.data_blob_size, datas);
            }

            // Init nodes
            {
                try vminstance.nodes.resize(vminstance.allocator, self.vmnodes.len);
                try vminstance.node_idx_map.ensureTotalCapacity(self.allocator, self.node_idx_map.count());

                for (self.node_idx_map.keys(), self.node_idx_map.values()) |k, node_idx| {
                    const iface: *const public.NodeI = ifaces[node_idx];

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
                            const ts = self.transpile_state_map.get(node_idx);
                            //log.debug("{any}, {any}", .{ self.transpile_state_map.keys(), node_idx });
                            try iface.create.?(iface, allocator, state.?, k.node, false, ts);
                        }

                        const new_node_idx = node_idx;
                        //std.debug.assert(new_node_idx == node_idx);

                        vminstance.nodes.set(node_idx, try InstanceNode.init(
                            data_alloc,
                            state,
                            vmnode_pin_def[new_node_idx],
                            vmnode_input_blob_size[new_node_idx],
                            vmnode_output_blob_size[new_node_idx],
                            new_node_idx,
                        ));

                        vminstance.node_idx_map.putAssumeCapacity(k, new_node_idx);
                    }

                    if (iface.pivot == .transpiler or (!new and changed)) {
                        if (iface.state_size != 0) {
                            state = states[node_idx];

                            if (iface.destroy) |destroy| {
                                try destroy(iface, state.?, true);
                            }
                            const ts = self.transpile_state_map.get(node_idx);
                            try iface.create.?(iface, allocator, state.?, k.node, true, ts);
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

                var graph_data = vminstance.graph_data;

                // Data
                for (0.., self.data_list.items) |idx, data| {
                    const to_node_idx = data.to_node_idx;
                    const to_node_pin_idx = data.to_node_pin_idx;

                    const value = try allocator.alloc(u8, data.value_i.size);
                    defer allocator.free(value);

                    // Write data from value obj
                    // TODO: better, faster, stronger
                    try data.value_i.valueFromCdb(data_alloc, data.value_obj, value);
                    const validity = try data.value_i.calcValidityHash(value);
                    try graph_data.toPins().write(idx, validity, value);

                    in_datas[to_node_idx].data.?[to_node_pin_idx] = graph_data.data_slices.?[idx];
                    in_datas[to_node_idx].validity_hash.?[to_node_pin_idx] = &graph_data.validity_hash.?[idx];
                    in_datas[to_node_idx].types.?[to_node_pin_idx] = graph_data.types.?[idx];
                }

                // Connections
                for (self.connection.items) |pair| {
                    const from_node_idx = pair.from.node;
                    const to_node_idx = pair.to.node;

                    const from_pin_idx = pair.from.pin_idx;
                    const to_pin_idx = pair.to.pin_idx;

                    const out_data_slices = out_datas[from_node_idx].data_slices orelse continue;

                    in_datas[to_node_idx].data.?[to_pin_idx] = out_data_slices[from_pin_idx];
                    in_datas[to_node_idx].validity_hash.?[to_pin_idx] = &out_datas[from_node_idx].validity_hash.?[from_pin_idx];
                    in_datas[to_node_idx].types.?[to_pin_idx] = out_datas[from_node_idx].types.?[from_pin_idx];
                }
            }
        }
    }

    pub fn buildVMNodes(self: *Self, node_idx: VMNodeIdx, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !void {
        var zone_ctx = _profiler.ZoneN(@src(), "GraphVM - Build VM nodes");
        defer zone_ctx.End();

        var vm_node = self.vmnodes.get(node_idx);
        const iface = vm_node.iface;

        vm_node.pin_def = try iface.getPinsDef(iface, self.allocator, graph_obj, node_obj);

        vm_node.has_flow = vm_node.pin_def.in.len != 0 and vm_node.pin_def.in[0].type_hash.eql(public.PinTypes.Flow);
        vm_node.input_blob_size = try vm_node.getInputPinsSize(vm_node.pin_def.in);

        vm_node.has_flow_out = vm_node.pin_def.out.len != 0 and vm_node.pin_def.out[0].type_hash.eql(public.PinTypes.Flow);
        vm_node.output_blob_size = try vm_node.getOutputPinsSize(vm_node.pin_def.out);

        self.vmnodes.set(node_idx, vm_node);
    }

    fn flowDag(self: *Self, allocator: std.mem.Allocator, dag: *cetech1.dag.DAG(VMNodeIdx), node: VMNodeIdx) !void {
        var depends = cetech1.ArrayList(VMNodeIdx){};
        defer depends.deinit(allocator);

        for (self.connection.items) |pair| {
            // only conection to this node
            if (pair.to.node != node) continue;
            try depends.append(allocator, pair.from.node);
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

    fn inputDag(self: *Self, allocator: std.mem.Allocator, dag: *cetech1.dag.DAG(VMNodeIdx), node: VMNodeIdx, skip_transpile: bool, only_pins: ?[]const u32) !void {
        var depends = cetech1.ArrayList(VMNodeIdx){};
        defer depends.deinit(allocator);

        const ifaces = self.vmnodes.items(.iface);
        const is_transpile_pivot = ifaces[node].pivot == .transpiler;
        const is_transpile_border = ifaces[node].transpile_border;
        const has_transpile = ifaces[node].transpile != null;
        const skip_node = skip_transpile and (is_transpile_pivot or (has_transpile and !is_transpile_border));

        conection_for: for (self.connection.items) |pair| {
            // only conection to this node
            if (pair.to.node != node) continue;

            // 5$
            if (only_pins) |op| {
                var contain = false;
                for (op) |value| {
                    if (value == pair.to.pin_idx) contain = true;
                }
                if (!contain) continue :conection_for;
            }

            if (!skip_node) {
                try depends.append(allocator, pair.from.node);
                try dag.add(pair.from.node, &.{});
            }

            try self.inputDag(allocator, dag, pair.from.node, skip_transpile, null);
        }

        if (!skip_node) {
            try dag.add(node, depends.items);
        }
    }

    pub fn createInstances(self: *Self, allocator: std.mem.Allocator, count: usize) ![]*VMInstance {
        const instances = try allocator.alloc(*VMInstance, count);

        try _g.instance_pool.createMany(instances, count);

        {
            // TODO: remove lock
            vm_lock.lock();
            defer vm_lock.unlock();

            try self.instance_set.ensureUnusedCapacity(self.allocator, count);
            for (0..count) |idx| {
                instances[idx].* = VMInstance.init(self.allocator, self);
                self.instance_set.putAssumeCapacity(instances[idx], {});
            }
        }

        return instances;
    }

    pub fn destroyInstance(self: *Self, instance: *VMInstance) void {
        instance.deinit();
        _ = self.instance_set.swapRemove(instance);
        _g.instance_pool.destroy(instance);
    }

    fn executeNodesMany(
        self: *Self,
        allocator: std.mem.Allocator,
        instances: []const public.GraphInstance,
        node_type: cetech1.StrId32,
        out_states: ?[]?*anyopaque,
    ) !void {
        var zone_ctx = _profiler.Zone(@src());
        defer zone_ctx.End();

        const ifaces = self.vmnodes.items(.iface);
        const settings = self.vmnodes.items(.settings);
        const pin_def = self.vmnodes.items(.pin_def);
        const has_flows = self.vmnodes.items(.has_flow);

        if (self.findNodeByType(node_type)) |event_nodes| {
            for (instances, 0..) |instance, instance_idx| {
                //if (!instance.isValid()) continue;

                var ints: *VMInstance = @alignCast(@ptrCast(instance.inst));

                const in_datas = ints.nodes.items(.in_data);
                const out_datas = ints.nodes.items(.out_data);
                const last_inputs_validity_hashs = ints.nodes.items(.last_inputs_validity_hash);
                const states = ints.nodes.items(.state);
                const evals = ints.nodes.items(.eval);

                if (out_states) |out| {
                    out[instance_idx] = null;
                }

                for (event_nodes) |event_node_idx| {
                    const plan = self.node_plan.get(event_node_idx).?;
                    for (plan) |node_idx| {
                        const iface: *const public.NodeI = ifaces[node_idx];

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
                            // var zone_exec_ctx = _profiler.ZoneN(@src(), "GraphVM - execute one node");
                            // defer zone_exec_ctx.End();

                            const ts = self.transpile_state_map.get(node_idx);
                            const transpier_node = self.transpile_map.get(node_idx);

                            try iface.execute(
                                iface,
                                .{
                                    .allocator = allocator,
                                    .settings = settings[node_idx],
                                    .state = states[node_idx],
                                    .graph = self.graph_obj,
                                    .instance = instance,
                                    .pin_def = pin_def[node_idx],
                                    .transpile_state = ts,
                                    .transpiler_node_state = if (transpier_node) |n| states[n] else null,
                                },
                                in_pins,
                                out_pins,
                            );

                            evals[node_idx] = true;
                        }

                        if (iface.type_hash.eql(node_type)) {
                            if (out_states) |out| {
                                out[instance_idx] = states[node_idx];
                            }
                        }
                    }
                }
            }
        }
    }

    fn transpileNodesMany(
        self: *Self,
        allocator: std.mem.Allocator,
        instances: []const public.GraphInstance,
        node_type: cetech1.StrId32,
        transpile_plan: []const VMNodeIdx,
        transpile_state: []u8,
        stage: ?cetech1.StrId32,
        context: ?[]const u8,
    ) !void {
        _ = node_type; // autofix
        var zone_ctx = _profiler.Zone(@src());
        defer zone_ctx.End();

        const ifaces = self.vmnodes.items(.iface);
        const settings = self.vmnodes.items(.settings);
        const pin_def = self.vmnodes.items(.pin_def);

        for (instances) |instance| {
            var ints: *VMInstance = @alignCast(@ptrCast(instance.inst));

            const in_datas = ints.nodes.items(.in_data);
            const out_datas = ints.nodes.items(.out_data);

            const states = ints.nodes.items(.state);

            const plan = transpile_plan;
            for (plan) |node_idx| {
                const iface: *const public.NodeI = ifaces[node_idx];

                const in_pins = in_datas[node_idx].toPins();
                const out_pins = out_datas[node_idx].toPins();

                var zone_exec_ctx = _profiler.ZoneN(@src(), "GraphVM - transpile one node");
                defer zone_exec_ctx.End();

                const transpile_fce = iface.transpile orelse continue;
                try transpile_fce(
                    iface,
                    .{
                        .allocator = allocator,
                        .settings = settings[node_idx],
                        .state = states[node_idx],
                        .graph = self.graph_obj,
                        .instance = instance,
                        .pin_def = pin_def[node_idx],
                        .transpile_state = null,
                        .transpiler_node_state = null,
                    },
                    transpile_state,
                    stage,
                    context,
                    in_pins,
                    out_pins,
                );
            }
        }
    }

    pub fn getNodeStateMany(self: *Self, results: []?*anyopaque, containers: []const public.GraphInstance, node_type: cetech1.StrId32) !void {
        var zone_ctx = _profiler.Zone(@src());
        defer zone_ctx.End();

        @memset(results, null);

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
        if (_assetdb.getAssetRootPath() == null) return;

        var root_dir = try std.fs.cwd().openDir(_assetdb.getAssetRootPath().?, .{});
        defer root_dir.close();

        const asset_obj = _assetdb.getAssetForObj(self.graph_obj).?;
        const asset_obj_r = cetech1.assetdb.Asset.read(_cdb, asset_obj).?;
        const name = cetech1.assetdb.Asset.readStr(_cdb, asset_obj_r, .Name).?;

        const filename = try std.fmt.allocPrint(allocator, "{s}/graph_{s}.md", .{ cetech1.assetdb.CT_TEMP_FOLDER, name });
        defer allocator.free(filename);

        var d2_file = try root_dir.createFile(filename, .{});
        defer d2_file.close();

        var bw = std.io.bufferedWriter(d2_file.writer());
        defer bw.flush() catch undefined;
        const writer = bw.writer();

        const ifaces = self.vmnodes.items(.iface);
        const node_objs = self.vmnodes.items(.node_obj);

        for (self.node_plan.keys(), self.node_plan.values()) |k, v| {
            const plan_node = k;
            try writer.print("# Plan for {s}\n\n", .{ifaces[plan_node].name});

            // write header
            try writer.print("```d2\n", .{});
            _ = try writer.write("vars: {d2-config: {layout-engine: elk}}\n\n");

            for (v) |node| {
                try writer.print("{s}: {s}\n", .{ try _assetdb.getOrCreateUuid(node_objs[node]), ifaces[node].name });
            }

            try writer.print("\n", .{});

            for (0..v.len - 1) |idx| {
                const node = v[idx];
                const nex_node = v[idx + 1];

                try writer.print("{s}->{s}\n", .{ try _assetdb.getOrCreateUuid(node_objs[node]), try _assetdb.getOrCreateUuid(node_objs[nex_node]) });
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
    .executeNodeAndGetStateFn = executeNodeAndGetState,

    .setInstanceContext = setInstanceContext,
    .getContextFn = getInstanceContext,
    .removeContext = removeInstanceContext,
    .getInputPins = getInputPins,
    .getOutputPins = getOutputPins,

    .needCompileAny = needCompileAny,
    .compileAllChanged = compileAllChanged,
};

const StringIntern = cetech1.string.InternWithLock([:0]const u8);

// CDB
var AssetTypeIdx: cdb.TypeIdx = undefined;
var CallGraphNodeSettingsIdx: cdb.TypeIdx = undefined;

pub fn createCdbNode(db: cdb.DbId, type_hash: cetech1.StrId32, pos: ?[2]f32) !cdb.ObjId {
    const iface = findNodeI(type_hash).?;
    const node = try public.NodeType.createObject(_cdb, db);

    const node_w = public.NodeType.write(_cdb, node).?;
    try public.NodeType.setStr(_cdb, node_w, .node_type, iface.type_name);

    if (!iface.settings_type.isEmpty()) {
        const settings = try _cdb.createObject(db, _cdb.getTypeIdx(db, iface.settings_type).?);

        const settings_w = _cdb.writeObj(settings).?;
        try public.NodeType.setSubObj(_cdb, node_w, .settings, settings_w);
        try _cdb.writeCommit(settings_w);
    }

    if (pos) |p| {
        public.NodeType.setValue(f32, _cdb, node_w, .pos_x, p[0]);
        public.NodeType.setValue(f32, _cdb, node_w, .pos_y, p[1]);
    }

    try _cdb.writeCommit(node_w);
    return node;
}

pub fn findNodeI(type_hash: cetech1.StrId32) ?*const public.NodeI {
    return _g.node_type_iface_map.get(type_hash);
}

pub fn findValueTypeI(type_hash: cetech1.StrId32) ?*const public.GraphValueTypeI {
    std.debug.assert(!type_hash.isEmpty());
    return _g.value_type_iface_map.get(type_hash);
}

pub fn findValueTypeIByCdb(type_hash: cetech1.StrId32) ?*const public.GraphValueTypeI {
    return _g.value_type_iface_cdb_map.get(type_hash);
}

fn isInputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) !bool {
    const iface = findNodeI(type_hash) orelse return false;
    var inputs = try iface.getPinsDef(iface, allocator, graph_obj, node_obj);
    defer inputs.deinit(allocator);
    for (inputs.in) |input| {
        if (input.pin_hash.eql(pin_hash)) return true;
    }
    return false;
}

fn getInputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) !?public.NodePin {
    const iface = findNodeI(type_hash) orelse return null;
    var inputs = try iface.getPinsDef(iface, allocator, graph_obj, node_obj);
    defer inputs.deinit(allocator);
    for (inputs.in) |input| {
        if (input.pin_hash.eql(pin_hash)) return input;
    }

    return null;
}

fn isOutputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) !bool {
    const iface = findNodeI(type_hash) orelse return false;
    var outputs = try iface.getPinsDef(iface, allocator, graph_obj, node_obj);
    defer outputs.deinit(allocator);
    for (outputs.out) |output| {
        if (output.pin_hash.eql(pin_hash)) return true;
    }
    return false;
}

fn getOutputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) !?public.NodePin {
    const iface = findNodeI(type_hash) orelse return null;
    var outputs = try iface.getPinsDef(iface, allocator, graph_obj, node_obj);
    defer outputs.deinit(allocator);

    for (outputs.out) |output| {
        if (output.pin_hash.eql(pin_hash)) return output;
    }
    return null;
}

fn getTypeColor(type_hash: cetech1.StrId32) [4]f32 {
    if (public.PinTypes.GENERIC.eql(type_hash)) return .{ 0.8, 0.0, 0.8, 1.0 };

    const iface = findValueTypeI(type_hash).?;

    if (iface.color) |color| {
        return color;
    }

    if (true) {
        const b: f32 = @floatFromInt((type_hash.id & 0xFF0000) >> 16);
        const g: f32 = @floatFromInt((type_hash.id & 0x00FF00) >> 8);
        const r: f32 = @floatFromInt(type_hash.id & 0x0000FF);

        return .{
            std.math.clamp(std.math.sin(r + 1), 0.4, 0.8),
            std.math.clamp(std.math.sin(g + 2), 0.4, 0.8),
            std.math.clamp(std.math.sin(b + 3), 0.4, 0.8),
            1.0,
        };
    }

    return .{ 1, 1, 1, 1 };
}

fn createVM(graph: cdb.ObjId) !*GraphVM {
    const vm = try _g.vm_pool.create();
    vm.* = GraphVM.init(_allocator, graph);
    try _g.vm_map.put(_allocator, graph, vm);

    const alloc = try _tmpalloc.create();
    defer _tmpalloc.destroy(alloc);

    try vm.buildVM(alloc);

    return @ptrCast(vm);
}

fn destroyVM(vm: *GraphVM) void {
    vm.deinit();
    _ = _g.vm_map.swapRemove(vm.graph_obj);
    _g.vm_pool.destroy(vm);
}

var vm_lock = std.Thread.Mutex{};

fn createInstance(allocator: std.mem.Allocator, graph: cdb.ObjId) !public.GraphInstance {
    var vm = _g.vm_map.get(graph).?;

    const containers = try vm.createInstances(allocator, 1);
    defer allocator.free(containers);

    return .{
        .graph = graph,
        .inst = containers[0],
    };
}

fn createInstances(allocator: std.mem.Allocator, graph: cdb.ObjId, instances: []public.GraphInstance) !void {
    var vm = _g.vm_map.get(graph) orelse try createVM(graph);

    const containers = try vm.createInstances(allocator, instances.len);
    defer allocator.free(containers);

    for (0..instances.len) |idx| instances[idx] = .{ .graph = graph, .inst = containers[idx] };
}

fn destroyInstance(vmc: public.GraphInstance) void {
    var vm = _g.vm_map.get(vmc.graph) orelse return; //TODO: ?
    vm.destroyInstance(@alignCast(@ptrCast(vmc.inst)));
}

const executeNodesTask = struct {
    instances: []const public.GraphInstance,
    out_states: ?[]?*anyopaque,
    event_hash: cetech1.StrId32,

    pub fn exec(self: *const @This()) !void {
        const c0: *VMInstance = @alignCast(@ptrCast(self.instances[0].inst));
        const vm = c0.vm;
        const alloc = try _tmpalloc.create();
        defer _tmpalloc.destroy(alloc);
        try vm.executeNodesMany(alloc, self.instances, self.event_hash, self.out_states);
    }
};

const buildInstancesTask = struct {
    instances: []const public.GraphInstance,

    pub fn exec(self: *const @This()) !void {
        const alloc = try _tmpalloc.create();
        defer _tmpalloc.destroy(alloc);

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

fn lessThanGraphInstance(ctx: void, lhs: public.GraphInstance, rhs: public.GraphInstance) bool {
    _ = ctx; // autofix
    return lhs.graph.toU64() < rhs.graph.toU64();
}

fn clusterByGraph(allocator: std.mem.Allocator, sorted_instances: []const public.GraphInstance) ![][]const public.GraphInstance {
    var zone2_ctx = _profiler.ZoneN(@src(), "clusterByGraph");
    defer zone2_ctx.End();

    var clusters = cetech1.ArrayList([]const public.GraphInstance){};
    defer clusters.deinit(allocator);

    var cluster_begin_idx: usize = 0;
    var current_obj = sorted_instances[0].graph;
    for (sorted_instances, 0..) |inst, idx| {
        if (inst.graph.isEmpty()) continue;

        if (inst.graph.eql(current_obj)) continue;
        try clusters.append(allocator, sorted_instances[cluster_begin_idx..idx]);
        current_obj = inst.graph;
        cluster_begin_idx = idx; //-1;
    }
    try clusters.append(allocator, sorted_instances[cluster_begin_idx..sorted_instances.len]);

    return clusters.toOwnedSlice(allocator);
}

fn executeNodes(allocator: std.mem.Allocator, instances: []const public.GraphInstance, event_hash: cetech1.StrId32, cfg: public.ExecuteConfig) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "GraphVM - execute nodes");
    defer zone_ctx.End();

    if (instances.len == 0) return;

    const sorted_instances = try allocator.dupe(public.GraphInstance, instances);
    defer allocator.free(sorted_instances);
    std.sort.insertion(public.GraphInstance, sorted_instances, void{}, lessThanGraphInstance);

    const clusters = try clusterByGraph(allocator, sorted_instances);
    defer allocator.free(clusters);

    var tasks = try cetech1.task.TaskIdList.initCapacity(allocator, clusters.len);
    defer tasks.deinit(allocator);

    const ARGS = struct {
        items: []const public.GraphInstance,
        event_hash: cetech1.StrId32,
        cfg: public.ExecuteConfig,
    };

    for (clusters) |cluster| {
        if (try cetech1.task.batchWorkloadTask(
            .{
                .allocator = allocator,
                .task_api = _task,
                .profiler_api = _profiler,

                .count = cluster.len,
                .batch_size = if (cfg.use_tasks) cetech1.task.default_bacth_size else cluster.len,
            },
            ARGS{
                .items = cluster,
                .event_hash = event_hash,
                .cfg = cfg,
            },
            struct {
                pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) executeNodesTask {
                    return executeNodesTask{
                        .instances = create_args.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                        .out_states = if (create_args.cfg.out_states) |out| out[batch_id * args.batch_size .. (batch_id * args.batch_size) + count] else null,
                        .event_hash = create_args.event_hash,
                    };
                }
            },
        )) |t| {
            tasks.appendAssumeCapacity(t);
        }
    }

    if (tasks.items.len != 0) {
        _task.waitMany(tasks.items);
    }
}

fn buildInstances(allocator: std.mem.Allocator, instances: []const public.GraphInstance) !void {
    var zone_ctx = _profiler.ZoneN(@src(), "GraphVM - buildInstances");
    defer zone_ctx.End();

    if (instances.len == 0) return;

    const sorted_instances = try allocator.dupe(public.GraphInstance, instances);
    defer allocator.free(sorted_instances);
    std.sort.insertion(public.GraphInstance, sorted_instances, void{}, lessThanGraphInstance);

    const clusters = try clusterByGraph(allocator, sorted_instances);
    defer allocator.free(clusters);

    var tasks = try cetech1.task.TaskIdList.initCapacity(allocator, clusters.len);
    defer tasks.deinit(allocator);

    const ARGS = struct {
        items: []const public.GraphInstance,
    };

    for (clusters) |cluster| {
        if (try cetech1.task.batchWorkloadTask(
            .{
                .allocator = allocator,
                .task_api = _task,
                .profiler_api = _profiler,

                .count = cluster.len,
            },
            ARGS{
                .items = cluster,
            },
            struct {
                pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) buildInstancesTask {
                    return buildInstancesTask{
                        .instances = create_args.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                    };
                }
            },
        )) |t| {
            tasks.appendAssumeCapacity(t);
        }
    }

    if (tasks.items.len != 0) {
        _task.waitMany(tasks.items);
    }
}

fn needCompile(graph: cdb.ObjId) bool {
    const vm = _g.vm_map.get(graph) orelse return false;
    if (graph.isEmpty()) return false;
    if (!_cdb.isAlive(graph)) return false;
    return vm.graph_version != _cdb.getVersion(graph);
}
fn compile(allocator: std.mem.Allocator, graph: cdb.ObjId) !void {
    var vm = _g.vm_map.get(graph).?;
    try vm.buildVM(allocator);
}

fn needCompileAny() bool {
    return _g.graph_to_compile.count() != 0;
}
fn compileAllChanged(allocator: std.mem.Allocator) !void {
    for (_g.graph_to_compile.keys()) |graph| {
        var vm = _g.vm_map.get(graph).?;
        try vm.buildVM(allocator);
    }
    _g.graph_to_compile.clearRetainingCapacity();
}

const getNodeStateTask = struct {
    containers: []const public.GraphInstance,
    node_type: cetech1.StrId32,
    output: []?*anyopaque,
    pub fn exec(self: *const @This()) !void {
        var c: *VMInstance = @alignCast(@ptrCast(self.containers[0].inst));
        try c.vm.getNodeStateMany(self.output, self.containers, self.node_type);
    }
};

pub fn getNodeState(allocator: std.mem.Allocator, instances: []const public.GraphInstance, node_type: cetech1.StrId32) ![]?*anyopaque {
    var zone_ctx = _profiler.ZoneN(@src(), "GraphVM - get node state");
    defer zone_ctx.End();

    var results = try cetech1.ArrayList(?*anyopaque).initCapacity(allocator, instances.len);
    try results.resize(allocator, instances.len);

    if (instances.len == 0) return results.toOwnedSlice(allocator);

    const sorted_instances = try allocator.dupe(public.GraphInstance, instances);
    defer allocator.free(sorted_instances);
    std.sort.insertion(public.GraphInstance, sorted_instances, void{}, lessThanGraphInstance);

    const clusters = try clusterByGraph(allocator, sorted_instances);
    defer allocator.free(clusters);

    var tasks = try cetech1.task.TaskIdList.initCapacity(allocator, clusters.len);
    defer tasks.deinit(allocator);

    const ARGS = struct {
        items: []const public.GraphInstance,
        node_type: cetech1.StrId32,
        results: []?*anyopaque,
    };

    var result_idx: usize = 0;
    for (clusters) |cluster| {
        const r = results.items[result_idx .. result_idx + cluster.len];
        result_idx += cluster.len;

        if (try cetech1.task.batchWorkloadTask(
            .{
                .allocator = allocator,
                .task_api = _task,
                .profiler_api = _profiler,

                .count = cluster.len,
            },
            ARGS{
                .items = cluster,
                .node_type = node_type,
                .results = r,
            },
            struct {
                pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) getNodeStateTask {
                    return getNodeStateTask{
                        .containers = create_args.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                        .node_type = create_args.node_type,
                        .output = create_args.results[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                    };
                }
            },
        )) |t| {
            tasks.appendAssumeCapacity(t);
        }
    }

    if (tasks.items.len != 0) {
        _task.waitMany(tasks.items);
    }

    return results.toOwnedSlice(allocator);
}

pub fn executeNodeAndGetState(allocator: std.mem.Allocator, instances: []const public.GraphInstance, node_type: cetech1.StrId32, cfg: public.ExecuteConfig) ![]?*anyopaque {
    var results = try cetech1.ArrayList(?*anyopaque).initCapacity(allocator, instances.len);
    try results.resize(allocator, instances.len);

    try executeNodes(allocator, instances, node_type, .{ .use_tasks = cfg.use_tasks, .out_states = results.items });

    return results.toOwnedSlice(allocator);
}

fn setInstanceContext(instance: public.GraphInstance, context_name: cetech1.StrId32, context: *anyopaque) !void {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    try c.setContext(context_name, context);
}

fn getInstanceContext(instance: public.GraphInstance, context_name: cetech1.StrId32) ?*anyopaque {
    const c: *VMInstance = @alignCast(@ptrCast(instance.inst));
    return c.getContext(context_name);
}

fn removeInstanceContext(instance: public.GraphInstance, context_name: cetech1.StrId32) void {
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

const ChangedObjsSet = cetech1.AutoArrayHashMap(cdb.ObjId, void);
var _last_check: cdb.TypeVersion = 0;

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "Graph",
    &[_]cetech1.StrId64{},
    null,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            const nodetype_i_version = _apidb.getInterafcesVersion(public.NodeI);
            if (nodetype_i_version != _g.nodetype_i_version) {
                log.debug("Supported nodes:", .{});
                const impls = try _apidb.getImpl(alloc, public.NodeI);
                defer alloc.free(impls);
                for (impls) |iface| {
                    log.debug("\t - {s} - {s} - {d}", .{ iface.name, iface.type_name, iface.type_hash.id });
                    try _g.node_type_iface_map.put(_allocator, iface.type_hash, iface);
                }
                _g.nodetype_i_version = nodetype_i_version;
            }

            const valuetype_i_version = _apidb.getInterafcesVersion(public.GraphValueTypeI);
            if (valuetype_i_version != _g.valuetype_i_version) {
                log.debug("Supported values:", .{});

                const impls = try _apidb.getImpl(alloc, public.GraphValueTypeI);
                defer alloc.free(impls);
                for (impls) |iface| {
                    log.debug("\t - {s} - {d}", .{ iface.name, iface.type_hash.id });

                    try _g.value_type_iface_map.put(_allocator, iface.type_hash, iface);
                    try _g.value_type_iface_cdb_map.put(_allocator, iface.cdb_type_hash, iface);
                }
                _g.valuetype_i_version = valuetype_i_version;
            }

            if (true) {
                var processed_obj = ChangedObjsSet{};
                defer processed_obj.deinit(alloc);

                const db = _assetdb.getDb();

                const changed = try _cdb.getChangeObjects(alloc, db, public.GraphType.typeIdx(_cdb, db), _last_check);
                defer alloc.free(changed.objects);

                if (!changed.need_fullscan) {
                    for (changed.objects) |graph| {
                        if (processed_obj.contains(graph)) continue;

                        if (!_g.vm_map.contains(graph)) {
                            // skip subgraph
                            const parent = _cdb.getParent(graph);
                            if (!parent.isEmpty()) {
                                if (parent.type_idx.eql(CallGraphNodeSettingsIdx)) continue;
                            }

                            const vm = try createVM(graph);
                            _ = vm; // autofix
                        }

                        try processed_obj.put(alloc, graph, {});
                        try _g.graph_to_compile.put(_allocator, graph, {});
                    }
                } else {
                    if (_cdb.getAllObjectByType(alloc, db, public.GraphType.typeIdx(_cdb, db))) |objs| {
                        for (objs) |graph| {
                            if (!_g.vm_map.contains(graph)) {
                                // skip subgraph
                                const parent = _cdb.getParent(graph);
                                if (!parent.isEmpty()) {
                                    if (parent.type_idx.eql(CallGraphNodeSettingsIdx)) continue;
                                }
                                const vm = try createVM(graph);
                                _ = vm; // autofix

                                try _g.graph_to_compile.put(_allocator, graph, {});
                            }
                        }
                    }
                }

                _last_check = changed.last_version;
            }
        }
    },
);

//
// Nodes
//

const PRINT_NODE_TYPE = cetech1.strId32("print");

// Inputs

const graph_inputs_i = public.NodeI.implement(
    .{
        .name = "Graph Inputs",
        .type_name = "graph_inputs",
        .category = "Interface",
        .sidefect = true,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj;

            const db = _cdb.getDbFromObjid(graph_obj);
            var pins = public.NodePinList{};

            const graph_r = public.GraphType.read(_cdb, graph_obj).?;

            if (public.GraphType.readSubObj(_cdb, graph_r, .interface)) |iface_obj| {
                const iface_r = public.Interface.read(_cdb, iface_obj).?;

                if (try public.Interface.readSubObjSet(_cdb, iface_r, .inputs, allocator)) |inputs| {
                    defer allocator.free(inputs);

                    for (inputs) |input| {
                        const input_r = _cdb.readObj(input).?;

                        const name = public.InterfaceInput.readStr(_cdb, input_r, .name) orelse "NO NAME!!";
                        const value_obj = public.InterfaceInput.readSubObj(_cdb, input_r, .value) orelse continue;

                        const uuid = try _assetdb.getOrCreateUuid(input);
                        var buffer: [128]u8 = undefined;
                        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                        const value_type = findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;

                        try pins.append(
                            allocator,
                            public.NodePin.initRaw(
                                name,
                                try _g.string_intern.intern(str),
                                value_type.type_hash,
                            ),
                        );
                    }
                }
            }

            return .{
                .in = try allocator.dupe(public.NodePin, &.{}),
                .out = try pins.toOwnedSlice(allocator),
            };
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = self; // autofix
            _ = in_pins; // autofix

            const graph_in_pins = api.getInputPins(args.instance);

            for (args.pin_def.out, 0..) |input, idx| {
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
            self: *const public.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Input});
        }
    },
);

const graph_outputs_i = public.NodeI.implement(
    .{
        .name = "Graph Outputs",
        .type_name = "graph_outputs",
        .category = "Interface",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            var pins = public.NodePinList{};

            const db = _cdb.getDbFromObjid(graph_obj);

            const graph_r = public.GraphType.read(_cdb, graph_obj).?;

            if (public.GraphType.readSubObj(_cdb, graph_r, .interface)) |iface_obj| {
                const iface_r = public.Interface.read(_cdb, iface_obj).?;

                if (try public.Interface.readSubObjSet(_cdb, iface_r, .outputs, allocator)) |outputs| {
                    defer allocator.free(outputs);

                    for (outputs) |input| {
                        const input_r = _cdb.readObj(input).?;

                        const name = public.InterfaceInput.readStr(_cdb, input_r, .name) orelse "NO NAME!!";
                        const value_obj = public.InterfaceInput.readSubObj(_cdb, input_r, .value) orelse continue;

                        const uuid = try _assetdb.getOrCreateUuid(input);
                        var buffer: [128]u8 = undefined;
                        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                        const value_type = findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;

                        try pins.append(
                            allocator,
                            public.NodePin.initRaw(
                                name,
                                try _g.string_intern.intern(str),
                                value_type.type_hash,
                            ),
                        );
                    }
                }
            }

            return .{
                .in = try pins.toOwnedSlice(allocator),
                .out = try allocator.dupe(public.NodePin, &.{}),
            };
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = self; // autofix
            _ = out_pins; // autofix

            const graph_out_pins = api.getOutputPins(args.instance);

            for (args.pin_def.in, 0..) |input, idx| {
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
            self: *const public.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Output});
        }
    },
);

const CallGraphNodeState = struct {
    graph: cdb.ObjId = .{},
    instance: ?public.GraphInstance = null,
};

const call_graph_node_i = public.NodeI.implement(
    .{
        .name = "Call graph",
        .type_name = public.CALL_GRAPH_NODE_TYPE_STR,
        .category = "Interface",

        .settings_type = public.CallGraphNodeSettings.type_hash,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            const db = _cdb.getDbFromObjid(graph_obj);
            var in_pins = public.NodePinList{};
            var out_pins = public.NodePinList{};

            const node_obj_r = public.NodeType.read(_cdb, node_obj).?;
            if (public.NodeType.readSubObj(_cdb, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(_cdb, settings).?;
                if (public.CallGraphNodeSettings.readSubObj(_cdb, settings_r, .graph)) |graph| {
                    const graph_r = public.GraphType.read(_cdb, graph).?;
                    if (public.GraphType.readSubObj(_cdb, graph_r, .interface)) |iface_obj| {
                        const iface_r = public.Interface.read(_cdb, iface_obj).?;

                        if (try public.Interface.readSubObjSet(_cdb, iface_r, .inputs, allocator)) |inputs| {
                            defer allocator.free(inputs);

                            try in_pins.ensureTotalCapacityPrecise(allocator, inputs.len);

                            for (inputs) |input| {
                                const input_r = _cdb.readObj(input).?;

                                const name = public.InterfaceInput.readStr(_cdb, input_r, .name) orelse "NO NAME!!";
                                const value_obj = public.InterfaceInput.readSubObj(_cdb, input_r, .value) orelse continue;

                                const uuid = try _assetdb.getOrCreateUuid(input);
                                var buffer: [128]u8 = undefined;
                                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                                const value_type = findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;

                                in_pins.appendAssumeCapacity(
                                    public.NodePin.initRaw(name, try _g.string_intern.intern(str), value_type.type_hash),
                                );
                            }
                        }

                        if (try public.Interface.readSubObjSet(_cdb, iface_r, .outputs, allocator)) |outputs| {
                            defer allocator.free(outputs);

                            try out_pins.ensureTotalCapacityPrecise(allocator, outputs.len);

                            for (outputs) |input| {
                                const input_r = _cdb.readObj(input).?;

                                const name = public.InterfaceOutput.readStr(_cdb, input_r, .name) orelse "NO NAME!!";
                                const value_obj = public.InterfaceOutput.readSubObj(_cdb, input_r, .value) orelse continue;

                                const uuid = try _assetdb.getOrCreateUuid(input);
                                var buffer: [128]u8 = undefined;
                                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{uuid});

                                const value_type = findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;

                                out_pins.appendAssumeCapacity(
                                    public.NodePin.initRaw(name, try _g.string_intern.intern(str), value_type.type_hash),
                                );
                            }
                        }
                    }
                }
            }

            return .{
                .in = try in_pins.toOwnedSlice(allocator),
                .out = try out_pins.toOwnedSlice(allocator),
            };
        }

        pub fn title(
            self: *const public.NodeI,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = self; // autofix
            const node_obj_r = public.NodeType.read(_cdb, node_obj).?;

            if (public.NodeType.readSubObj(_cdb, node_obj_r, .settings)) |settings| {
                const settings_r = public.CallGraphNodeSettings.read(_cdb, settings).?;
                if (public.CallGraphNodeSettings.readSubObj(_cdb, settings_r, .graph)) |graph| {
                    const graph_r = public.GraphType.read(_cdb, graph).?;

                    if (public.GraphType.readStr(_cdb, graph_r, .name)) |name| {
                        if (name.len != 0) {
                            return allocator.dupeZ(u8, name);
                        }
                    }

                    const prototype = _cdb.getPrototype(graph_r);
                    if (prototype.isEmpty()) {
                        const graph_asset = _assetdb.getAssetForObj(graph) orelse return allocator.dupeZ(u8, "");
                        const name = cetech1.assetdb.Asset.readStr(_cdb, _cdb.readObj(graph_asset).?, .Name) orelse return allocator.dupeZ(u8, "");
                        return allocator.dupeZ(u8, name);
                    } else {
                        const graph_asset = _assetdb.getAssetForObj(prototype) orelse return allocator.dupeZ(u8, "");
                        const name = cetech1.assetdb.Asset.readStr(_cdb, _cdb.readObj(graph_asset).?, .Name) orelse return allocator.dupeZ(u8, "");
                        return allocator.dupeZ(u8, name);
                    }
                } else {
                    return allocator.dupeZ(u8, "SELECT GRAPH !!!");
                }
            }

            return allocator.dupeZ(u8, "PROBLEM?");
        }

        pub fn icon(
            self: *const public.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Graph});
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: public.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = in_pins; // autofix
            _ = out_pins; // autofix
        }
    },
);

// Values def

// Foo cdb type decl

// Register all cdb stuff in this method

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // GraphNodeType
        {
            _ = try _cdb.addType(
                db,
                public.GraphType.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.GraphType.propIdx(.name), .name = "name", .type = .STR },
                    .{ .prop_idx = public.GraphType.propIdx(.nodes), .name = "nodes", .type = .SUBOBJECT_SET, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.groups), .name = "groups", .type = .SUBOBJECT_SET, .type_hash = public.GroupType.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.connections), .name = "connections", .type = .SUBOBJECT_SET, .type_hash = public.ConnectionType.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.interface), .name = "interface", .type = .SUBOBJECT, .type_hash = public.Interface.type_hash },
                    .{ .prop_idx = public.GraphType.propIdx(.data), .name = "data", .type = .SUBOBJECT_SET, .type_hash = public.GraphDataType.type_hash },
                },
            );
        }

        // GraphNodeType
        {
            _ = try _cdb.addType(
                db,
                public.GraphDataType.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.GraphDataType.propIdx(.to_node), .name = "to_node", .type = .REFERENCE, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.GraphDataType.propIdx(.to_node_pin), .name = "to_node_pin", .type = .STR },
                    .{ .prop_idx = public.GraphDataType.propIdx(.value), .name = "value", .type = .SUBOBJECT },
                },
            );
        }

        // GraphNodeType
        {
            _ = try _cdb.addType(
                db,
                public.NodeType.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.NodeType.propIdx(.node_type), .name = "node_type", .type = .STR },
                    .{ .prop_idx = public.NodeType.propIdx(.settings), .name = "settings", .type = .SUBOBJECT },
                    .{ .prop_idx = public.NodeType.propIdx(.pos_x), .name = "pos_x", .type = .F32 },
                    .{ .prop_idx = public.NodeType.propIdx(.pos_y), .name = "pos_y", .type = .F32 },
                },
            );
        }

        // GroupType
        {
            _ = try _cdb.addType(
                db,
                public.GroupType.name,
                &[_]cdb.PropDef{
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
            _ = try _cdb.addType(
                db,
                public.ConnectionType.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.ConnectionType.propIdx(.from_node), .name = "from_node", .type = .REFERENCE, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.ConnectionType.propIdx(.to_node), .name = "to_node", .type = .REFERENCE, .type_hash = public.NodeType.type_hash },
                    .{ .prop_idx = public.ConnectionType.propIdx(.from_pin), .name = "from_pin", .type = .STR },
                    .{ .prop_idx = public.ConnectionType.propIdx(.to_pin), .name = "to_pin", .type = .STR },
                },
            );
        }

        // Interface
        {
            _ = try _cdb.addType(
                db,
                public.Interface.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Interface.propIdx(.inputs), .name = "inputs", .type = .SUBOBJECT_SET, .type_hash = public.InterfaceInput.type_hash },
                    .{ .prop_idx = public.Interface.propIdx(.outputs), .name = "outputs", .type = .SUBOBJECT_SET, .type_hash = public.InterfaceOutput.type_hash },
                },
            );
        }

        // InterfaceInput
        {
            _ = try _cdb.addType(
                db,
                public.InterfaceInput.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.InterfaceInput.propIdx(.name), .name = "name", .type = .STR },
                    .{ .prop_idx = public.InterfaceInput.propIdx(.value), .name = "value", .type = .SUBOBJECT },
                },
            );
        }

        // InterfaceOutput
        {
            _ = try _cdb.addType(
                db,
                public.InterfaceOutput.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.InterfaceOutput.propIdx(.name), .name = "name", .type = .STR },
                    .{ .prop_idx = public.InterfaceOutput.propIdx(.value), .name = "value", .type = .SUBOBJECT },
                },
            );
        }

        // CallGraphNodeSettings
        {
            CallGraphNodeSettingsIdx = try _cdb.addType(
                db,
                public.CallGraphNodeSettings.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.CallGraphNodeSettings.propIdx(.graph), .name = "graph", .type = .SUBOBJECT, .type_hash = public.GraphType.type_hash },
                },
            );
        }

        try basic_nodes.createTypes(db);

        // TODO:  Move
        AssetTypeIdx = cetech1.assetdb.Asset.typeIdx(_cdb, db);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _assetdb = apidb.getZigApi(module_name, cetech1.assetdb.AssetDBAPI).?;

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.setOrRemoveZigApi(module_name, public.GraphVMApi, &api, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);

    try basic_nodes.addOrRemove(module_name, apidb, _cdb, _log, &api, load);

    try apidb.implOrRemove(module_name, public.NodeI, &graph_inputs_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &graph_outputs_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &call_graph_node_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_graphvm(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
