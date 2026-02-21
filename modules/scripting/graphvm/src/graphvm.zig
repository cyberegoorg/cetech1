const std = @import("std");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const modules = cetech1.modules;
const math = cetech1.math;
const apidb = cetech1.apidb;

// TODO: MOVE
pub const EVENT_INIT_NODE_TYPE_STR = "event_init";
pub const EVENT_SHUTDOWN_NODE_TYPE_STR = "event_shutdown";
pub const EVENT_TICK_NODE_TYPE_STR = "event_tick";

pub const EVENT_INIT_NODE_TYPE = cetech1.strId32(EVENT_INIT_NODE_TYPE_STR);
pub const EVENT_SHUTDOWN_NODE_TYPE = cetech1.strId32(EVENT_SHUTDOWN_NODE_TYPE_STR);
pub const EVENT_TICK_NODE_TYPE = cetech1.strId32(EVENT_TICK_NODE_TYPE_STR);

pub const NodePinList = cetech1.ArrayList(NodePin);

pub const GraphTypeCdb = cdb.CdbTypeDecl(
    "ct_graph",
    enum(u32) {
        name = 0,
        nodes,
        groups,
        connections,
        interface,
        data,
    },
    struct {},
);

pub const GraphDataTypeCdb = cdb.CdbTypeDecl(
    "ct_graph_data",
    enum(u32) {
        to_node = 0,
        to_node_pin,
        value,
    },
    struct {},
);

pub const NodeTypeCdb = cdb.CdbTypeDecl(
    "ct_graph_node",
    enum(u32) {
        node_type = 0,
        settings,
        pos_x,
        pos_y,
    },
    struct {
        pub fn getNodeTypeId(reader: *cdb.Obj) cetech1.StrId32 {
            const str = NodeTypeCdb.readStr(reader, .node_type) orelse return .{};
            return .fromStr(str);
        }
    },
);

pub const GroupTypeCdb = cdb.CdbTypeDecl(
    "ct_graph_group",
    enum(u32) {
        title = 0,
        color,
        pos_x,
        pos_y,
        size_x,
        size_y,
    },
    struct {},
);

pub const ConnectionTypeCdb = cdb.CdbTypeDecl(
    "ct_graph_connection",
    enum(u32) {
        from_node = 0,
        to_node,
        from_pin,
        to_pin,
    },
    struct {
        pub fn getFromPinId(reader: *cdb.Obj) cetech1.StrId32 {
            const str = ConnectionTypeCdb.readStr(reader, .from_pin) orelse return .{};
            return .fromStr(str);
        }

        pub fn getToPinId(reader: *cdb.Obj) cetech1.StrId32 {
            const str = ConnectionTypeCdb.readStr(reader, .to_pin) orelse return .{};
            return .fromStr(str);
        }
    },
);

pub const InterfaceCdb = cdb.CdbTypeDecl(
    "ct_graph_interface",
    enum(u32) {
        inputs = 0,
        outputs,
    },
    struct {},
);

pub const InterfaceInputCdb = cdb.CdbTypeDecl(
    "ct_graph_interface_input",
    enum(u32) {
        name = 0,
        value,
    },
    struct {},
);

pub const InterfaceOutputCdb = cdb.CdbTypeDecl(
    "ct_graph_interface_output",
    enum(u32) {
        name = 0,
        value,
    },
    struct {},
);

pub const CallGraphNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_call_graph_node_settings",
    enum(u32) {
        graph = 0,
    },
    struct {},
);

pub const ConstNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_node_const_settings",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const RandomF32NodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_node_random_f32_settings",
    enum(u32) {
        min = 0,
        max,
    },
    struct {},
);

pub const flowTypeCdb = cdb.CdbTypeDecl(
    "ct_node_flow_type",
    enum(u32) {},
    struct {},
);

pub const PinTypes = struct {
    pub const Flow = cetech1.strId32("flow");
    pub const Bool = cetech1.strId32("bool");
    pub const String = cetech1.strId32("string");
    pub const I32 = cetech1.strId32("i32");
    pub const U32 = cetech1.strId32("u32");
    pub const I64 = cetech1.strId32("i64");
    pub const U64 = cetech1.strId32("u64");
    pub const F32 = cetech1.strId32("f32");
    pub const F64 = cetech1.strId32("f64");

    pub const VEC2F = cetech1.strId32("vec2f");
    pub const VEC3F = cetech1.strId32("vec3f");
    pub const VEC4F = cetech1.strId32("vec4f");
    pub const QUATF = cetech1.strId32("quatf");

    // TODO: Move
    pub const Entity = cetech1.strId32("entity");

    pub const Color4f = cetech1.strId32("Color4f");

    // For inputs
    pub const GENERIC = cetech1.strId32("generic");
};

pub const NodePinDef = struct {
    in: []NodePin,
    out: []NodePin,

    pub fn deinit(self: *NodePinDef, allocator: std.mem.Allocator) void {
        allocator.free(self.in);
        allocator.free(self.out);
    }
};

pub const NodePin = struct {
    name: [:0]const u8,

    pin_name: [:0]const u8,
    pin_hash: cetech1.StrId32,

    type_hash: cetech1.StrId32,
    type_of: ?cetech1.StrId32 = null,

    pub fn init(name: [:0]const u8, pin_name: [:0]const u8, type_hash: cetech1.StrId32, type_of: ?[:0]const u8) NodePin {
        return .{
            .name = name,
            .pin_name = pin_name,
            .pin_hash = .fromStr(pin_name),
            .type_hash = type_hash,
            .type_of = if (type_of) |t| .fromStr(t) else null,
        };
    }

    pub fn initRaw(name: [:0]const u8, pin_name: [:0]const u8, type_hash: cetech1.StrId32) NodePin {
        return .{
            .name = name,
            .pin_name = pin_name,
            .pin_hash = .fromStr(pin_name),
            .type_hash = type_hash,
        };
    }

    pub fn pinHash(comptime name: []const u8, comptime is_output: bool) [:0]const u8 {
        const prefix = if (is_output) "out" else "in";
        return prefix ++ ":" ++ name;
    }

    pub fn alocPinHash(allocator: std.mem.Allocator, name: []const u8, comptime is_output: bool) ![:0]const u8 {
        const prefix = if (is_output) "out" else "in";
        return std.fmt.allocPrintSentinel(allocator, "{s}:{s}", .{ prefix, name }, 0);
    }
};

pub const ExecuteArgs = struct {
    allocator: std.mem.Allocator,
    graph: cdb.ObjId,
    settings: ?cdb.ObjId,
    state: ?*anyopaque,
    instance: GraphInstance,
    pin_def: NodePinDef,

    transpile_state: ?[]u8,
    transpiler_node_state: ?*anyopaque,

    pub fn getState(self: ExecuteArgs, comptime T: type) ?*T {
        if (self.state) |s| {
            return @ptrCast(@alignCast(s));
        }
        return null;
    }
};

pub const PivotType = enum {
    None,
    Pivot,
    Transpiler,
};

pub const TranspileStage = struct {
    id: cetech1.StrId32,
    pin_idx: []const u32,
    contexts: ?[]const u8 = null,
};

pub const NodeI = struct {
    pub const c_name = "ct_graph_node_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8,
    type_name: [:0]const u8,
    type_hash: cetech1.StrId32 = undefined,
    category: ?[:0]const u8 = null,
    pivot: PivotType = .None,
    settings_type: cetech1.StrId32 = .{},
    sidefect: bool = false,
    transpile_border: bool = false,

    // TODO: alow null for none in/out?
    getPinsDef: *const fn (self: *const NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) anyerror!NodePinDef = undefined,

    state_size: usize = 0,
    state_align: u8 = 0,

    create: ?*const fn (self: *const NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) anyerror!void = null,
    destroy: ?*const fn (self: *const NodeI, state: *anyopaque, reload: bool) anyerror!void = null,

    execute: *const fn (self: *const NodeI, args: ExecuteArgs, in_pins: InPins, out_pins: *OutPins) anyerror!void = undefined,

    // TODO: Clean transpile API and ARGS
    createTranspileState: ?*const fn (self: *const NodeI, allocator: std.mem.Allocator) anyerror![]u8 = null,
    destroyTranspileState: ?*const fn (self: *const NodeI, state: []u8) void = null,
    getTranspileStages: ?*const fn (self: *const NodeI, allocator: std.mem.Allocator) anyerror![]const TranspileStage = undefined,
    transpile: ?*const fn (self: *const NodeI, args: ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: InPins, out_pins: *OutPins) anyerror!void = undefined,

    title: ?*const fn (
        self: *const NodeI,
        allocator: std.mem.Allocator,
        node_obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    icon: ?*const fn (
        self: *const NodeI,
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        node_obj: cdb.ObjId,
    ) anyerror![:0]u8 = null,

    pub fn implement(args: NodeI, comptime S: ?type, comptime T: type) NodeI {
        var self = args;
        self.type_hash = .fromStr(args.type_name);
        self.getPinsDef = T.getPinsDef;
        self.execute = T.execute;

        if (S) |State| {
            self.state_size = @sizeOf(State);
            self.state_align = @alignOf(State);
            self.create = T.create;
            self.destroy = if (std.meta.hasFn(T, "destroy")) T.destroy else null;
        }

        self.title = if (std.meta.hasFn(T, "title")) T.title else null;
        self.icon = if (std.meta.hasFn(T, "icon")) T.icon else null;

        self.createTranspileState = if (std.meta.hasFn(T, "createTranspileState")) T.createTranspileState else null;
        self.destroyTranspileState = if (std.meta.hasFn(T, "destroyTranspileState")) T.destroyTranspileState else null;
        self.getTranspileStages = if (std.meta.hasFn(T, "getTranspileStages")) T.getTranspileStages else null;
        self.transpile = if (std.meta.hasFn(T, "transpile")) T.transpile else null;

        return self;
    }
};

pub const PinDataIdxMap = cetech1.AutoArrayHashMap(cetech1.StrId32, u32);
pub const ValidityHash = u64;

pub const MAX_INPUT_PINS = 32;
pub const MAX_OUTPUT_PINS = 32;

pub const InPins = struct {
    const Self = @This();

    data: []const ?[*]u8 = &.{},
    validity_hash: []const ?*ValidityHash = &.{},
    types: []const ?cetech1.StrId32 = &.{},

    pub fn read(self: Self, comptime T: type, pin_idx: usize) ?struct { ValidityHash, T } {
        // if (self.data == null) return null;
        if (self.data[pin_idx] == null) return null;

        const vh = self.validity_hash[pin_idx].?;
        const v = std.mem.bytesAsValue(T, self.data[pin_idx].?);
        return .{ vh.*, v.* };
    }

    pub fn getPinType(self: Self, pin_idx: usize) ?cetech1.StrId32 {
        return self.types[pin_idx];
    }
};

pub const OutPins = struct {
    const Self = @This();

    data: []const [*]u8 = &.{},
    validity_hash: []ValidityHash = &.{},
    types: []const cetech1.StrId32 = &.{},

    pub fn writeTyped(self: *Self, comptime T: type, pin_idx: usize, validity_hash: ValidityHash, value: T) !void {
        try self.write(pin_idx, validity_hash, std.mem.asBytes(&value));
    }

    pub fn write(self: *Self, pin_idx: usize, validity_hash: ValidityHash, value: []const u8) !void {
        //if (self.data == null) return;

        self.validity_hash[pin_idx] = validity_hash;

        const v = self.data[pin_idx];
        @memcpy(v, value);
    }

    pub fn getPinType(self: Self, pin_idx: usize) cetech1.StrId32 {
        return self.types[pin_idx];
    }
};

pub const GraphValueTypeI = struct {
    pub const c_name = "ct_graph_value_type_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8,
    type_hash: cetech1.StrId32,
    cdb_type_hash: cetech1.StrId32,

    size: usize = undefined,
    alignn: usize = undefined,

    color: ?math.Color4f = null,

    valueFromCdb: *const fn (allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) anyerror!void = undefined,
    calcValidityHash: *const fn (value: []const u8) anyerror!ValidityHash = undefined,
    destoryValue: ?*const fn (allocator: std.mem.Allocator, value: []u8) anyerror!void = undefined,

    valueToString: *const fn (allocator: std.mem.Allocator, value: []const u8) anyerror![:0]u8 = undefined,

    pub fn implement(
        comptime T: type,
        args: GraphValueTypeI,
        comptime Impl: type,
    ) GraphValueTypeI {
        return GraphValueTypeI{
            .name = args.name,
            .type_hash = args.type_hash,
            .cdb_type_hash = args.cdb_type_hash,
            .color = args.color,
            .size = @sizeOf(T),
            .alignn = @alignOf(T),
            .valueFromCdb = Impl.valueFromCdb,
            .calcValidityHash = Impl.calcValidityHash,
            .valueToString = Impl.valueToString,
            .destoryValue = if (std.meta.hasFn(T, "destoryValue")) T.destoryValue else null,
        };
    }
};

pub const GraphInstance = extern struct {
    graph: cdb.ObjId = .{},
    inst: *anyopaque = undefined,

    pub fn isValid(self: GraphInstance) bool {
        return !self.graph.isEmpty();
    }
};

pub const CALL_GRAPH_NODE_TYPE_STR = "call_graph";
pub const CALL_GRAPH_NODE_TYPE = cetech1.strId32(CALL_GRAPH_NODE_TYPE_STR);

pub const ExecuteConfig = struct {
    use_tasks: bool = true,
    out_states: ?[]?*anyopaque = null,
    sort: bool = true,
};

pub const GetNodeConfig = struct {
    sort: bool = true,
};

pub inline fn getNodeState(comptime T: type, allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: cetech1.StrId32, cfg: GetNodeConfig) ![]?*T {
    const result = try api.getNodeStateFn(allocator, instances, node_type, cfg);

    var r: []?*T = undefined;
    r.ptr = @ptrCast(@alignCast(result.ptr));
    r.len = result.len;

    return r;
}

pub inline fn executeNodeAndGetState(comptime T: type, allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: cetech1.StrId32, cfg: ExecuteConfig) ![]?*T {
    const result = try api.executeNodeAndGetStateFn(allocator, instances, node_type, cfg);

    var r: []?*T = undefined;
    r.ptr = @ptrCast(@alignCast(result.ptr));
    r.len = result.len;

    return r;
}

pub inline fn getContext(comptime T: type, instance: GraphInstance, context_name: cetech1.StrId32) ?*T {
    const result = api.getContextFn(instance, context_name) orelse return null;
    return @ptrCast(@alignCast(result));
}

pub fn findNodeI(type_hash: cetech1.StrId32) ?*const NodeI {
    return api.findNodeI(type_hash);
}
pub fn findValueTypeI(type_hash: cetech1.StrId32) ?*const GraphValueTypeI {
    return api.findValueTypeI(type_hash);
}
pub fn findValueTypeIByCdb(type_hash: cetech1.StrId32) ?*const GraphValueTypeI {
    return api.findValueTypeIByCdb(type_hash);
}
pub fn createCdbNode(db: cdb.DbId, type_hash: cetech1.StrId32, pos: ?math.Vec2f) anyerror!cdb.ObjId {
    return api.createCdbNode(db, type_hash, pos);
}
pub fn isOutputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!bool {
    return api.isOutputPin(allocator, graph_obj, node_obj, type_hash, pin_hash);
}
pub fn isInputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!bool {
    return api.isInputPin(allocator, graph_obj, node_obj, type_hash, pin_hash);
}
pub fn getInputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!?NodePin {
    return api.getInputPin(allocator, graph_obj, node_obj, type_hash, pin_hash);
}
pub fn getOutputPin(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!?NodePin {
    return api.getOutputPin(allocator, graph_obj, node_obj, type_hash, pin_hash);
}
pub fn getTypeColor(type_hash: cetech1.StrId32) math.Color4f {
    return api.getTypeColor(type_hash);
}
pub fn needCompile(graph: cdb.ObjId) bool {
    return api.needCompile(graph);
}
pub fn compile(allocator: std.mem.Allocator, graph: cdb.ObjId) anyerror!void {
    return api.compile(allocator, graph);
}
pub fn needCompileAny() bool {
    return api.needCompileAny();
}
pub fn compileAllChanged(allocator: std.mem.Allocator) anyerror!void {
    return api.compileAllChanged(allocator);
}
pub fn getPrototypeNode(graph: cdb.ObjId, node: cdb.ObjId) ?cdb.ObjId {
    return api.getPrototypeNode(graph, node);
}
pub fn createInstance(allocator: std.mem.Allocator, graph: cdb.ObjId) anyerror!GraphInstance {
    return api.createInstance(allocator, graph);
}
pub fn createInstances(allocator: std.mem.Allocator, graph: cdb.ObjId, instances: []GraphInstance) anyerror!void {
    return api.createInstances(allocator, graph, instances);
}
pub fn destroyInstance(instance: GraphInstance) void {
    return api.destroyInstance(instance);
}
pub fn buildInstances(allocator: std.mem.Allocator, instances: []const GraphInstance) anyerror!void {
    return api.buildInstances(allocator, instances);
}
pub fn setInstanceContext(instance: GraphInstance, context_name: cetech1.StrId32, context: *anyopaque) anyerror!void {
    return api.setInstanceContext(instance, context_name, context);
}
pub fn setInstancesContext(instances: []const GraphInstance, context_name: cetech1.StrId32, context: *anyopaque) anyerror!void {
    return api.setInstancesContext(instances, context_name, context);
}
pub fn removeContext(instance: GraphInstance, context_name: cetech1.StrId32) void {
    return api.removeContext(instance, context_name);
}
pub fn getInputPins(instance: GraphInstance) OutPins {
    return api.getInputPins(instance);
}
pub fn getOutputPins(instance: GraphInstance) OutPins {
    return api.getOutputPins(instance);
}
pub fn executeNode(allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: cetech1.StrId32, cfg: ExecuteConfig) anyerror!void {
    return api.executeNode(allocator, instances, node_type, cfg);
}

pub fn getNodeStateMultyFn(allocator: std.mem.Allocator, instances: []const GraphInstance, node_types: []const cetech1.StrId32, cfg: GetNodeConfig) anyerror![][]?*anyopaque {
    return api.getNodeStateMultyFn(allocator, instances, node_types, cfg);
}
pub const GraphVMApi = struct {
    findNodeI: *const fn (type_hash: cetech1.StrId32) ?*const NodeI,
    findValueTypeI: *const fn (type_hash: cetech1.StrId32) ?*const GraphValueTypeI,
    findValueTypeIByCdb: *const fn (type_hash: cetech1.StrId32) ?*const GraphValueTypeI,
    createCdbNode: *const fn (db: cdb.DbId, type_hash: cetech1.StrId32, pos: ?math.Vec2f) anyerror!cdb.ObjId,
    isOutputPin: *const fn (allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!bool,
    isInputPin: *const fn (allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!bool,
    getInputPin: *const fn (allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!?NodePin,
    getOutputPin: *const fn (allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: cetech1.StrId32, pin_hash: cetech1.StrId32) anyerror!?NodePin,
    getTypeColor: *const fn (type_hash: cetech1.StrId32) math.Color4f,
    needCompile: *const fn (graph: cdb.ObjId) bool,
    compile: *const fn (allocator: std.mem.Allocator, graph: cdb.ObjId) anyerror!void,
    needCompileAny: *const fn () bool,
    compileAllChanged: *const fn (allocator: std.mem.Allocator) anyerror!void,
    getPrototypeNode: *const fn (graph: cdb.ObjId, node: cdb.ObjId) ?cdb.ObjId,
    createInstance: *const fn (allocator: std.mem.Allocator, graph: cdb.ObjId) anyerror!GraphInstance,
    createInstances: *const fn (allocator: std.mem.Allocator, graph: cdb.ObjId, instances: []GraphInstance) anyerror!void,
    destroyInstance: *const fn (instance: GraphInstance) void,
    buildInstances: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance) anyerror!void,
    setInstanceContext: *const fn (instance: GraphInstance, context_name: cetech1.StrId32, context: *anyopaque) anyerror!void,
    setInstancesContext: *const fn (instances: []const GraphInstance, context_name: cetech1.StrId32, context: *anyopaque) anyerror!void,
    getContextFn: *const fn (instance: GraphInstance, context_name: cetech1.StrId32) ?*anyopaque,
    removeContext: *const fn (instance: GraphInstance, context_name: cetech1.StrId32) void,
    getInputPins: *const fn (instance: GraphInstance) OutPins,
    getOutputPins: *const fn (instance: GraphInstance) OutPins,
    executeNode: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: cetech1.StrId32, cfg: ExecuteConfig) anyerror!void,
    getNodeStateFn: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: cetech1.StrId32, cfg: GetNodeConfig) anyerror![]?*anyopaque,
    getNodeStateMultyFn: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance, node_types: []const cetech1.StrId32, cfg: GetNodeConfig) anyerror![][]?*anyopaque,
    executeNodeAndGetStateFn: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: cetech1.StrId32, cfg: ExecuteConfig) anyerror![]?*anyopaque,
};

pub var api: *const GraphVMApi = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, GraphVMApi).?;
}
