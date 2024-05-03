const std = @import("std");

const cdb = @import("cdb.zig");
const modules = @import("modules.zig");
const strid = @import("strid.zig");

const log = std.log.scoped(.graphvm);

// TODO: MOVE
pub const EVENT_INIT_NODE_TYPE_STR = "event_init";
pub const EVENT_SHUTDOWN_NODE_TYPE_STR = "event_shutdown";
pub const EVENT_TICK_NODE_TYPE_STR = "event_tick";
pub const CULLING_VOLUME_NODE_TYPE_STR = "culling_volume";

pub const EVENT_INIT_NODE_TYPE = strid.strId32(EVENT_INIT_NODE_TYPE_STR);
pub const EVENT_SHUTDOWN_NODE_TYPE = strid.strId32(EVENT_SHUTDOWN_NODE_TYPE_STR);
pub const EVENT_TICK_NODE_TYPE = strid.strId32(EVENT_TICK_NODE_TYPE_STR);
pub const CULLING_VOLUME_NODE_TYPE = strid.strId32(CULLING_VOLUME_NODE_TYPE_STR);

pub const GraphType = cdb.CdbTypeDecl(
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

pub const GraphDataType = cdb.CdbTypeDecl(
    "ct_graph_data",
    enum(u32) {
        to_node = 0,
        to_node_pin,
        value,
    },
    struct {},
);

pub const NodeType = cdb.CdbTypeDecl(
    "ct_graph_node",
    enum(u32) {
        node_type = 0,
        settings,
        pos_x,
        pos_y,
    },
    struct {
        pub fn getNodeTypeId(db: cdb.Db, reader: *cdb.Obj) strid.StrId32 {
            const str = NodeType.readStr(db, reader, .node_type) orelse return .{};
            return strid.strId32(str);
        }
    },
);

pub const GroupType = cdb.CdbTypeDecl(
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

pub const ConnectionType = cdb.CdbTypeDecl(
    "ct_graph_connection",
    enum(u32) {
        from_node = 0,
        to_node,
        from_pin,
        to_pin,
    },
    struct {
        pub fn getFromPinId(db: cdb.Db, reader: *cdb.Obj) strid.StrId32 {
            const str = ConnectionType.readStr(db, reader, .from_pin) orelse return .{};
            return strid.strId32(str);
        }

        pub fn getToPinId(db: cdb.Db, reader: *cdb.Obj) strid.StrId32 {
            const str = ConnectionType.readStr(db, reader, .to_pin) orelse return .{};
            return strid.strId32(str);
        }
    },
);

pub const Interface = cdb.CdbTypeDecl(
    "ct_graph_interface",
    enum(u32) {
        inputs = 0,
        outputs,
    },
    struct {},
);

pub const InterfaceInput = cdb.CdbTypeDecl(
    "ct_graph_interface_input",
    enum(u32) {
        name = 0,
        value,
    },
    struct {},
);

pub const InterfaceOutput = cdb.CdbTypeDecl(
    "ct_graph_interface_output",
    enum(u32) {
        name = 0,
        value,
    },
    struct {},
);

pub const CallGraphNodeSettings = cdb.CdbTypeDecl(
    "ct_call_graph_node_settings",
    enum(u32) {
        graph = 0,
    },
    struct {},
);

pub const ConstNodeSettings = cdb.CdbTypeDecl(
    "ct_node_const_settings",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const RandomF32NodeSettings = cdb.CdbTypeDecl(
    "ct_node_random_f32_settings",
    enum(u32) {
        min = 0,
        max,
    },
    struct {},
);

pub const flowType = cdb.CdbTypeDecl(
    "ct_node_flow_type",
    enum(u32) {},
    struct {},
);

pub const PinTypes = struct {
    pub const Flow = strid.strId32("flow");
    pub const Bool = strid.strId32("bool");
    pub const String = strid.strId32("string");
    pub const I32 = strid.strId32("i32");
    pub const U32 = strid.strId32("u32");
    pub const I64 = strid.strId32("i64");
    pub const U64 = strid.strId32("u64");
    pub const F32 = strid.strId32("f32");
    pub const F64 = strid.strId32("f64");

    pub const VEC2F = strid.strId32("vec2f");
    pub const VEC3F = strid.strId32("vec3f");
    pub const VEC4F = strid.strId32("vec4f");
    pub const QUATF = strid.strId32("quatf");

    // For inputs
    pub const GENERIC = strid.strId32("generic");
};

pub const NodePin = struct {
    name: [:0]const u8,

    pin_name: [:0]const u8,
    pin_hash: strid.StrId32,

    type_hash: strid.StrId32,

    pub fn init(name: [:0]const u8, pin_name: [:0]const u8, type_hash: strid.StrId32) NodePin {
        return .{
            .name = name,
            .pin_name = pin_name,
            .pin_hash = strid.strId32(pin_name),
            .type_hash = type_hash,
        };
    }

    pub fn initRaw(name: [:0]const u8, pin_name: [:0]const u8, type_hash: strid.StrId32) NodePin {
        return .{
            .name = name,
            .pin_name = pin_name,
            .pin_hash = strid.strId32(pin_name),
            .type_hash = type_hash,
        };
    }

    pub fn pinHash(comptime name: []const u8, comptime is_output: bool) [:0]const u8 {
        const prefix = if (is_output) "out" else "in";
        return prefix ++ ":" ++ name;
    }
};

pub const ExecuteArgs = struct {
    allocator: std.mem.Allocator,
    db: cdb.Db,
    graph: cdb.ObjId,
    settings: ?cdb.ObjId,
    state: ?*anyopaque,
    instance: GraphInstance,
    inputs: []const NodePin,
    outputs: []const NodePin,

    pub fn getState(self: ExecuteArgs, comptime T: type) ?*T {
        if (self.state) |s| {
            return @alignCast(@ptrCast(s));
        }
        return null;
    }
};

pub const PivotType = enum {
    none,
    pivot,
};

pub const GraphNodeI = struct {
    pub const c_name = "ct_graph_node_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8,
    type_name: [:0]const u8,
    type_hash: strid.StrId32 = undefined,
    category: ?[:0]const u8 = null,
    pivot: PivotType = .none,
    settings_type: strid.StrId32 = .{},
    sidefect: bool = false,

    getInputPins: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) anyerror![]const NodePin = undefined,
    getOutputPins: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) anyerror![]const NodePin = undefined,

    state_size: usize = 0,
    state_align: u8 = 0,

    create: ?*const fn (allocator: std.mem.Allocator, state: *anyopaque, db: cdb.Db, node_obj: cdb.ObjId, reload: bool) anyerror!void = null,
    destroy: ?*const fn (state: *anyopaque, db: cdb.Db, reload: bool) anyerror!void = null,

    execute: *const fn (args: ExecuteArgs, in_pins: InPins, out_pins: OutPins) anyerror!void = undefined,

    title: ?*const fn (
        allocator: std.mem.Allocator,
        db: cdb.Db,
        node_obj: cdb.ObjId,
    ) anyerror![:0]const u8 = null,

    icon: ?*const fn (
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        db: cdb.Db,
        node_obj: cdb.ObjId,
    ) anyerror![:0]u8 = null,

    pub fn implement(args: GraphNodeI, comptime S: ?type, comptime T: type) GraphNodeI {
        var self = args;
        self.type_hash = strid.strId32(args.type_name);
        self.getInputPins = T.getInputPins;
        self.getOutputPins = T.getOutputPins;
        self.execute = T.execute;

        if (S) |State| {
            self.state_size = @sizeOf(State);
            self.state_align = @alignOf(State);
            self.create = T.create;
            self.destroy = if (std.meta.hasFn(T, "destroy")) T.destroy else null;
        }

        self.title = if (std.meta.hasFn(T, "title")) T.title else null;
        self.icon = if (std.meta.hasFn(T, "icon")) T.icon else null;

        return self;
    }
};

pub const PinDataIdxMap = std.AutoArrayHashMap(strid.StrId32, u32);
pub const ValidityHash = u64;

pub const InPins = struct {
    const Self = @This();

    data: ?[]?[*]u8 = undefined,
    validity_hash: ?[]?*ValidityHash = null,
    types: ?[]?strid.StrId32 = null,

    pub fn read(self: Self, comptime T: type, pin_idx: usize) ?struct { ValidityHash, T } {
        if (self.data == null) return null;
        if (self.data.?[pin_idx] == null) return null;

        const vh = self.validity_hash.?[pin_idx].?;
        const v: *T = @alignCast(@ptrCast(self.data.?[pin_idx].?));
        return .{ vh.*, v.* };
    }

    pub fn getPinType(self: Self, pin_idx: usize) ?strid.StrId32 {
        return self.types.?[pin_idx];
    }
};

pub const OutPins = struct {
    const Self = @This();

    data: ?[][*]u8 = undefined,
    validity_hash: ?[]ValidityHash = null,
    types: ?[]strid.StrId32 = null,

    pub fn writeTyped(self: Self, comptime T: type, pin_idx: usize, validity_hash: ValidityHash, value: T) !void {
        try self.write(pin_idx, validity_hash, std.mem.asBytes(&value));
    }

    pub fn write(self: Self, pin_idx: usize, validity_hash: ValidityHash, value: []const u8) !void {
        if (self.data == null) return;

        self.validity_hash.?[pin_idx] = validity_hash;

        const v = self.data.?[pin_idx];
        @memcpy(v, value);
    }

    pub fn getPinType(self: Self, pin_idx: usize) strid.StrId32 {
        return self.types.?[pin_idx];
    }
};

pub const GraphValueTypeI = struct {
    pub const c_name = "ct_graph_value_type_i";
    pub const name_hash = strid.strId64(@This().c_name);

    name: [:0]const u8,
    type_hash: strid.StrId32,
    cdb_type_hash: strid.StrId32,

    size: usize = undefined,
    alignn: usize = undefined,

    valueFromCdb: *const fn (db: cdb.Db, obj: cdb.ObjId, value: []u8) anyerror!void = undefined,
    calcValidityHash: *const fn (value: []const u8) anyerror!ValidityHash = undefined,

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
            .size = @sizeOf(T),
            .alignn = @alignOf(T),
            .valueFromCdb = Impl.valueFromCdb,
            .calcValidityHash = Impl.calcValidityHash,
            .valueToString = Impl.valueToString,
        };
    }
};

pub const GraphInstance = struct {
    graph: cdb.ObjId = .{},
    inst: *anyopaque = undefined,

    pub fn isValid(self: GraphInstance) bool {
        return !self.graph.isEmpty();
    }
};

pub const CALL_GRAPH_NODE_TYPE_STR = "call_graph";
pub const CALL_GRAPH_NODE_TYPE = strid.strId32(CALL_GRAPH_NODE_TYPE_STR);

pub const GraphVMApi = struct {
    pub inline fn getNodeState(api: *const GraphVMApi, comptime T: type, allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: strid.StrId32) ![]*T {
        const result = try api.getNodeStateFn(allocator, instances, node_type);

        var r: []*T = undefined;
        r.ptr = @alignCast(@ptrCast(result.ptr));
        r.len = result.len;

        return r;
    }

    pub inline fn getContext(api: *const GraphVMApi, comptime T: type, instance: GraphInstance, context_name: strid.StrId32) ?*T {
        const result = api.getContextFn(instance, context_name) orelse return null;
        return @alignCast(@ptrCast(result));
    }

    findNodeI: *const fn (type_hash: strid.StrId32) ?*const GraphNodeI,
    findValueTypeI: *const fn (type_hash: strid.StrId32) ?*const GraphValueTypeI,
    findValueTypeIByCdb: *const fn (type_hash: strid.StrId32) ?*const GraphValueTypeI,

    createCdbNode: *const fn (db: cdb.Db, type_hash: strid.StrId32, pos: ?[2]f32) anyerror!cdb.ObjId,

    isOutputPin: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) anyerror!bool,
    isInputPin: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) anyerror!bool,
    getInputPin: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, ype_hash: strid.StrId32, pin_hash: strid.StrId32) anyerror!?NodePin,
    getOutputPin: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph_obj: cdb.ObjId, node_obj: cdb.ObjId, type_hash: strid.StrId32, pin_hash: strid.StrId32) anyerror!?NodePin,

    // TODO: move to editor_graph?
    getTypeColor: *const fn (type_hash: strid.StrId32) [4]f32,

    needCompile: *const fn (graph: cdb.ObjId) bool,
    compile: *const fn (allocator: std.mem.Allocator, graph: cdb.ObjId) anyerror!void,

    createInstance: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph: cdb.ObjId) anyerror!GraphInstance,
    createInstances: *const fn (allocator: std.mem.Allocator, db: cdb.Db, graph: cdb.ObjId, instances: []GraphInstance) anyerror!void,
    destroyInstance: *const fn (instance: GraphInstance) void,
    executeNode: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance, node_type: strid.StrId32) anyerror!void,
    buildInstances: *const fn (allocator: std.mem.Allocator, instances: []const GraphInstance) anyerror!void,

    setInstanceContext: *const fn (instance: GraphInstance, context_name: strid.StrId32, context: *anyopaque) anyerror!void,
    getContextFn: *const fn (instance: GraphInstance, context_name: strid.StrId32) ?*anyopaque,
    removeContext: *const fn (instance: GraphInstance, context_name: strid.StrId32) void,
    getInputPins: *const fn (instance: GraphInstance) OutPins,
    getOutputPins: *const fn (instance: GraphInstance) OutPins,

    getNodeStateFn: *const fn (allocator: std.mem.Allocator, containers: []const GraphInstance, node_type: strid.StrId32) anyerror![]*anyopaque,
};
