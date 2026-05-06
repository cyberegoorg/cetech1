const std = @import("std");

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;
const math = cetech1.math;
const apidb = cetech1.apidb;
const graphvm = cetech1.scripting.graphvm;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(.graphvm);

const flow_value_type_i = graphvm.GraphValueTypeI.implement(
    bool,
    .{
        .name = "Flow",
        .type_hash = graphvm.PinTypes.Flow,
        .cdb_type_hash = graphvm.flowTypeCdb.type_hash,
        .color = .white,
    },

    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            _ = value;
            _ = obj;
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(bool, value);
            return @intFromBool(v.*);
        }
        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(bool, value)}, 0);
        }
    },
);

const i32_value_type_i = graphvm.GraphValueTypeI.implement(
    i32,
    .{
        .name = "i32",
        .type_hash = graphvm.PinTypes.I32,
        .cdb_type_hash = cdb_types.I32TypeCdb.type_hash,
        .color = .{ .r = 0.2, .g = 0.4, .b = 1.0, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.I32TypeCdb.readValue(i32, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(i32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(i32, value)}, 0);
        }
    },
);

const u32_value_type_i = graphvm.GraphValueTypeI.implement(
    u32,
    .{
        .name = "u32",
        .type_hash = graphvm.PinTypes.U32,
        .cdb_type_hash = cdb_types.U32TypeCdb.type_hash,
        .color = .{ .r = 0.4, .g = 0.6, .b = 1.0, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.U32TypeCdb.readValue(u32, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(u32, value)}, 0);
        }
    },
);

const f32_value_type_i = graphvm.GraphValueTypeI.implement(
    f32,
    .{
        .name = "f32",
        .type_hash = graphvm.PinTypes.F32,
        .cdb_type_hash = cdb_types.F32TypeCdb.type_hash,
        .color = .{ .g = 0.5, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.F32TypeCdb.readValue(f32, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(f32, value);
            return std.mem.bytesToValue(graphvm.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(f32, value)}, 0);
        }
    },
);

const i64_value_type_i = graphvm.GraphValueTypeI.implement(
    i64,
    .{
        .name = "i64",
        .type_hash = graphvm.PinTypes.I64,
        .cdb_type_hash = cdb_types.I64TypeCdb.type_hash,
        .color = .{ .r = 0.2, .g = 0.4, .b = 1.0, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.I64TypeCdb.readValue(i64, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(i64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(i64, value)}, 0);
        }
    },
);

const u64_value_type_i = graphvm.GraphValueTypeI.implement(
    u64,
    .{
        .name = "u64",
        .type_hash = graphvm.PinTypes.U64,
        .cdb_type_hash = cdb_types.U64TypeCdb.type_hash,
        .color = .{ .r = 0.4, .g = 0.6, .b = 1.0, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.U64TypeCdb.readValue(u64, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(u64, value)}, 0);
        }
    },
);

const f64_value_type_i = graphvm.GraphValueTypeI.implement(
    f64,
    .{
        .name = "f64",
        .type_hash = graphvm.PinTypes.F64,
        .cdb_type_hash = cdb_types.F64TypeCdb.type_hash,
        .color = .{ .g = 0.5, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.F64TypeCdb.readValue(f64, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(f64, value);
            return std.mem.bytesToValue(graphvm.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(f64, value)}, 0);
        }
    },
);

const bool_value_type_i = graphvm.GraphValueTypeI.implement(
    bool,
    .{
        .name = "bool",
        .type_hash = graphvm.PinTypes.Bool,
        .cdb_type_hash = cdb_types.BoolTypeCdb.type_hash,
        .color = .{ .r = 1.0, .g = 0.4, .b = 0.4, .a = 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.BoolTypeCdb.readValue(bool, cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(bool, value);
            return std.mem.bytesToValue(graphvm.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(bool, value)}, 0);
        }
    },
);

const string_value_type_i = graphvm.GraphValueTypeI.implement(
    [:0]u8,
    .{
        .name = "string",
        .type_hash = graphvm.PinTypes.String,
        .cdb_type_hash = cdb_types.StringTypeCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.StringTypeCdb.readStr(cdb.readObj(obj).?, .Value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue([:0]u8, value);
            return cetech1.strId64(v.*).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{s}", .{std.mem.bytesToValue([:0]u8, value)}, 0);
        }
    },
);

const vec2f_value_type_i = graphvm.GraphValueTypeI.implement(
    math.Vec2f,
    .{
        .name = "vec2f",
        .type_hash = graphvm.PinTypes.VEC2F,
        .cdb_type_hash = cdb_types.Vec2fCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.Vec2fCdb.f.to(obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue(math.Vec2f, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const vec3f_value_type_i = graphvm.GraphValueTypeI.implement(
    math.Vec3f,
    .{
        .name = "vec3f",
        .type_hash = graphvm.PinTypes.VEC3F,
        .cdb_type_hash = cdb_types.Vec3fCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.Vec3fCdb.f.to(obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue(math.Vec3f, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const vec4f_value_type_i = graphvm.GraphValueTypeI.implement(
    math.Vec4f,
    .{
        .name = "vec4f",
        .type_hash = graphvm.PinTypes.VEC4F,
        .cdb_type_hash = cdb_types.Vec4fCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.Vec4fCdb.f.to(obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([4]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const quatf_value_type_i = graphvm.GraphValueTypeI.implement(
    math.Quatf,
    .{
        .name = "quatf",
        .type_hash = graphvm.PinTypes.QUATF,
        .cdb_type_hash = cdb_types.QuatfCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.QuatfCdb.f.to(obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([4]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const Color4f_value_type_i = graphvm.GraphValueTypeI.implement(
    [4]f32,
    .{
        .name = "Color4f",
        .type_hash = graphvm.PinTypes.Color4f,
        .cdb_type_hash = cdb_types.Color4fCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator;
            const v = cdb_types.Color4fCdb.f.to(obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([4]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const event_node_i = graphvm.NodeI.implement(
    .{
        .name = "Event Init",
        .type_name = graphvm.EVENT_INIT_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .Pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self;
            _ = node_obj;
            _ = graph_obj;

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", true), graphvm.PinTypes.Flow, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self;
            _ = allocator;
            _ = node_obj;

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Play});
        }
    },
);

const event_shutdown_node_i = graphvm.NodeI.implement(
    .{
        .name = "Event Shutdown",
        .type_name = graphvm.EVENT_SHUTDOWN_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .Pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self;
            _ = node_obj;
            _ = graph_obj;
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", true), graphvm.PinTypes.Flow, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self;
            _ = allocator;
            _ = node_obj;

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Stop});
        }
    },
);

const event_tick_node_i = graphvm.NodeI.implement(
    .{
        .name = "Event Tick",
        .type_name = graphvm.EVENT_TICK_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .Pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self;
            _ = node_obj;
            _ = graph_obj;
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", true), graphvm.PinTypes.Flow, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self;
            _ = allocator;
            _ = node_obj;

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Timer});
        }
    },
);

const PrintNodeState = struct {
    input_validity: graphvm.ValidityHash = 0,
};

const print_node_i = graphvm.NodeI.implement(
    .{
        .name = "Print",
        .type_name = "print",
        .sidefect = true,
    },
    PrintNodeState,
    struct {
        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self;
            _ = node_obj;
            _ = graph_obj;
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", false), graphvm.PinTypes.Flow, null),
                    graphvm.NodePin.init("Value", graphvm.NodePin.pinHash("value", false), graphvm.PinTypes.GENERIC, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{}),
            };
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self;
            _ = transpile_state;
            _ = reload;
            _ = allocator;
            _ = node_obj;
            const real_state: *PrintNodeState = @ptrCast(@alignCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            _ = args;
            _ = out_pins;

            const value_pin_type = in_pins.getPinType(1) orelse return;
            const iface = graphvm.findValueTypeI(value_pin_type).?;

            var buffer: [256]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const allocator = fba.allocator();

            const str_value = try iface.valueToString(allocator, in_pins.data[1].?[0..iface.size]);
            log.debug("{s}", .{str_value});
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self;
            _ = allocator;
            _ = node_obj;

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Print});
        }
    },
);

const ConstNodeState = struct {
    version: cdb.ObjVersion = 0,
    value_type: *const graphvm.GraphValueTypeI = undefined,
    value_obj: cdb.ObjId = .{},
};

const const_node_i = graphvm.NodeI.implement(
    .{
        .name = "Const",
        .type_name = "const",
        .settings_type = graphvm.ConstNodeSettingsCdb.type_hash,
    },
    ConstNodeState,
    struct {
        const Self = @This();
        const out = graphvm.NodePin.pinHash("value", true);

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self;

            const db = cdb.getDbFromObjid(graph_obj);
            const node_r = graphvm.GraphTypeCdb.read(node_obj).?;

            var type_hash: cetech1.StrId32 = .{};
            if (graphvm.NodeTypeCdb.readSubObj(node_r, .settings)) |setting| {
                const settings_r = graphvm.ConstNodeSettingsCdb.read(setting).?;

                if (graphvm.ConstNodeSettingsCdb.readSubObj(settings_r, .value)) |value_obj| {
                    const value_type = graphvm.findValueTypeIByCdb(cdb.getTypeHash(db, value_obj.type_idx).?).?;
                    type_hash = value_type.type_hash;
                }
            }

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Value", graphvm.NodePin.pinHash("value", true), type_hash, null),
                }),
            };
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self;
            _ = transpile_state;
            _ = reload;
            _ = allocator;
            const real_state: *ConstNodeState = @ptrCast(@alignCast(state));
            real_state.* = .{};

            const db = cdb.getDbFromObjid(node_obj);

            const node_r = graphvm.GraphTypeCdb.read(node_obj).?;
            if (graphvm.NodeTypeCdb.readSubObj(node_r, .settings)) |setting| {
                const settings_r = graphvm.ConstNodeSettingsCdb.read(setting).?;

                if (graphvm.ConstNodeSettingsCdb.readSubObj(settings_r, .value)) |value_obj| {
                    const value_type = graphvm.findValueTypeIByCdb(cdb.getTypeHash(db, value_obj.type_idx).?).?;
                    real_state.value_type = value_type;
                    real_state.value_obj = value_obj;
                }
            }
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            _ = in_pins;
            const real_state: *ConstNodeState = @ptrCast(@alignCast(args.state));

            // TODO: SHIT
            var value: [2048]u8 = undefined;
            try real_state.value_type.valueFromCdb(args.allocator, real_state.value_obj, value[0..real_state.value_type.size]);
            const vh = try real_state.value_type.calcValidityHash(value[0..real_state.value_type.size]);
            try out_pins.write(0, vh, value[0..real_state.value_type.size]);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self;
            _ = allocator;
            _ = node_obj;

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Const});
        }
    },
);

const RandomF32NodeState = struct {
    prg: ?std.Random.DefaultPrng = null,
    random: std.Random = undefined,
};
const random_f32_node_i = graphvm.NodeI.implement(
    .{
        .name = "Random f32",
        .type_name = "random_f32",
        .category = "Random",
    },
    RandomF32NodeState,
    struct {
        const Self = @This();
        const out = graphvm.NodePin.pinHash("value", true);

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self;
            _ = node_obj;
            _ = graph_obj;
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Min", graphvm.NodePin.pinHash("min", false), graphvm.PinTypes.F32, null),
                    graphvm.NodePin.init("Max", graphvm.NodePin.pinHash("max", false), graphvm.PinTypes.F32, null),
                    graphvm.NodePin.init("Seed", graphvm.NodePin.pinHash("seed", false), graphvm.PinTypes.U64, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Value", graphvm.NodePin.pinHash("value", true), graphvm.PinTypes.F32, null),
                }),
            };
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self;
            _ = transpile_state;
            _ = node_obj;
            _ = reload;
            _ = allocator;

            const real_state: *RandomF32NodeState = @ptrCast(@alignCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self;
            const real_state: *RandomF32NodeState = @ptrCast(@alignCast(args.state));

            _, const min = in_pins.read(f32, 0) orelse .{ 0, 0 };
            _, const max = in_pins.read(f32, 1) orelse .{ 0, 0 };
            _, const seed = in_pins.read(u64, 2) orelse .{ 0, 0 };

            if (real_state.prg == null) {
                real_state.prg = std.Random.DefaultPrng.init(@bitCast(seed));
                real_state.random = real_state.prg.?.random();
            }

            const value = real_state.random.float(f32) * (max - min) + min;

            const vh = try f32_value_type_i.calcValidityHash(std.mem.asBytes(&value));
            try out_pins.writeTyped(f32, 0, vh, value);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self;
            _ = allocator;
            _ = node_obj;

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Random});
        }
    },
);

const get_entity_node_i = graphvm.NodeI.implement(
    .{
        .name = "Get entity",
        .type_name = "get_entity",
        .category = "ECS",
    },
    null,
    struct {
        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = node_obj;
            _ = graph_obj;
            _ = self;

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", true), graphvm.PinTypes.Entity, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = in_pins;
            _ = self;
            if (graphvm.getContext(anyopaque, args.instance, ecs.ECS_ENTITY_CONTEXT)) |ent| {
                const ent_id = @intFromPtr(ent);
                try out_pins.writeTyped(ecs.EntityId, 0, ent_id, ent_id);
            }
        }

        // pub fn icon(
        //     buff: [:0]u8,
        //     allocator: std.mem.Allocator,
        //     db: cdb.DbId,
        //     node_obj: cdb.ObjId,
        // ) ![:0]u8 {
        //     _ = allocator;
        //     _ = db;
        //     _ = node_obj;

        //     return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_STOP});
        // }
    },
);

pub fn addOrRemove(
    comptime module_name: @EnumLiteral(),
    load: bool,
) !void {
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &flow_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &bool_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &string_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &i32_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &u32_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &i64_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &u64_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &f32_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &f64_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &vec2f_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &vec3f_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &vec4f_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &quatf_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &Color4f_value_type_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &event_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &event_tick_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &event_shutdown_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &print_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &const_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &random_f32_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &get_entity_node_i, load);
}

pub fn createTypes(db: cdb.DbId) !void {
    // ConstNodeSettings
    {
        _ = try cdb.addType(
            db,
            graphvm.ConstNodeSettingsCdb.name,
            &[_]cdb.PropDef{
                .{ .prop_idx = graphvm.ConstNodeSettingsCdb.propIdx(.value), .name = "value", .type = .SUBOBJECT },
            },
        );
    }

    // RandomF32NodeSettings
    {
        _ = try cdb.addType(
            db,
            graphvm.RandomF32NodeSettingsCdb.name,
            &[_]cdb.PropDef{},
        );
    }

    // flowType
    {
        _ = try cdb.addType(
            db,
            graphvm.flowTypeCdb.name,
            &[_]cdb.PropDef{},
        );
    }
}
