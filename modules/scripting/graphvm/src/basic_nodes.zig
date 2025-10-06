const std = @import("std");

const public = @import("graphvm.zig");
const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(.graphvm);

var _cdb: *const cdb.CdbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _graphvm: *const public.GraphVMApi = undefined;

const flow_value_type_i = public.GraphValueTypeI.implement(
    bool,
    .{
        .name = "Flow",
        .type_hash = public.PinTypes.Flow,
        .cdb_type_hash = public.flowType.type_hash,
        .color = .{ 1, 1, 1, 1 },
    },

    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            _ = value; // autofix
            _ = obj; // autofix
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(bool, value);
            return @intFromBool(v.*);
        }
        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(bool, value)}, 0);
        }
    },
);

const i32_value_type_i = public.GraphValueTypeI.implement(
    i32,
    .{
        .name = "i32",
        .type_hash = public.PinTypes.I32,
        .cdb_type_hash = cdb_types.i32Type.type_hash,
        .color = .{ 0.2, 0.4, 1.0, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.i32Type.readValue(i32, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(i32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(i32, value)}, 0);
        }
    },
);

const u32_value_type_i = public.GraphValueTypeI.implement(
    u32,
    .{
        .name = "u32",
        .type_hash = public.PinTypes.U32,
        .cdb_type_hash = cdb_types.u32Type.type_hash,
        .color = .{ 0.4, 0.6, 1.0, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.u32Type.readValue(u32, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(u32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(u32, value)}, 0);
        }
    },
);

const f32_value_type_i = public.GraphValueTypeI.implement(
    f32,
    .{
        .name = "f32",
        .type_hash = public.PinTypes.F32,
        .cdb_type_hash = cdb_types.f32Type.type_hash,
        .color = .{ 0.0, 0.5, 0.0, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.f32Type.readValue(f32, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(f32, value);
            return std.mem.bytesToValue(public.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(f32, value)}, 0);
        }
    },
);

const i64_value_type_i = public.GraphValueTypeI.implement(
    i64,
    .{
        .name = "i64",
        .type_hash = public.PinTypes.I64,
        .cdb_type_hash = cdb_types.i64Type.type_hash,
        .color = .{ 0.2, 0.4, 1.0, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.i64Type.readValue(i64, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(i64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(i64, value)}, 0);
        }
    },
);

const u64_value_type_i = public.GraphValueTypeI.implement(
    u64,
    .{
        .name = "u64",
        .type_hash = public.PinTypes.U64,
        .cdb_type_hash = cdb_types.u64Type.type_hash,
        .color = .{ 0.4, 0.6, 1.0, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.u64Type.readValue(u64, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(u64, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(u64, value)}, 0);
        }
    },
);

const f64_value_type_i = public.GraphValueTypeI.implement(
    f64,
    .{
        .name = "f64",
        .type_hash = public.PinTypes.F64,
        .cdb_type_hash = cdb_types.f64Type.type_hash,
        .color = .{ 0.0, 0.5, 0.0, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.f64Type.readValue(f64, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(f64, value);
            return std.mem.bytesToValue(public.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(f64, value)}, 0);
        }
    },
);

const bool_value_type_i = public.GraphValueTypeI.implement(
    bool,
    .{
        .name = "bool",
        .type_hash = public.PinTypes.Bool,
        .cdb_type_hash = cdb_types.BoolType.type_hash,
        .color = .{ 1.0, 0.4, 0.4, 1.0 },
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.BoolType.readValue(bool, _cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue(bool, value);
            return std.mem.bytesToValue(public.ValidityHash, v);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(bool, value)}, 0);
        }
    },
);

const string_value_type_i = public.GraphValueTypeI.implement(
    [:0]u8,
    .{
        .name = "string",
        .type_hash = public.PinTypes.String,
        .cdb_type_hash = cdb_types.StringType.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.StringType.readStr(_cdb, _cdb.readObj(obj).?, .value);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            const v = std.mem.bytesAsValue([:0]u8, value);
            return cetech1.strId64(v.*).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{s}", .{std.mem.bytesToValue([:0]u8, value)}, 0);
        }
    },
);

const vec2f_value_type_i = public.GraphValueTypeI.implement(
    [2]f32,
    .{
        .name = "vec2f",
        .type_hash = public.PinTypes.VEC2F,
        .cdb_type_hash = cdb_types.Vec2f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.Vec2f.f.toSlice(_cdb, obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([2]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const vec3f_value_type_i = public.GraphValueTypeI.implement(
    [3]f32,
    .{
        .name = "vec3f",
        .type_hash = public.PinTypes.VEC3F,
        .cdb_type_hash = cdb_types.Vec3f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.Vec3f.f.toSlice(_cdb, obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([3]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const vec4f_value_type_i = public.GraphValueTypeI.implement(
    [4]f32,
    .{
        .name = "vec4f",
        .type_hash = public.PinTypes.VEC4F,
        .cdb_type_hash = cdb_types.Vec4f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.Vec4f.f.toSlice(_cdb, obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([4]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const quatf_value_type_i = public.GraphValueTypeI.implement(
    [4]f32,
    .{
        .name = "quatf",
        .type_hash = public.PinTypes.QUATF,
        .cdb_type_hash = cdb_types.Quatf.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.Vec4f.f.toSlice(_cdb, obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([4]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const color4f_value_type_i = public.GraphValueTypeI.implement(
    [4]f32,
    .{
        .name = "color4f",
        .type_hash = public.PinTypes.COLOR4F,
        .cdb_type_hash = cdb_types.Color4f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = cdb_types.Color4f.f.toSlice(_cdb, obj);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !public.ValidityHash {
            return std.hash.Murmur2_64.hash(value);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const v = std.mem.bytesToValue([4]f32, value);
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{v}, 0);
        }
    },
);

const event_node_i = public.NodeI.implement(
    .{
        .name = "Event Init",
        .type_name = public.EVENT_INIT_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix

            return .{
                .in = try allocator.dupe(public.NodePin, &.{}),
                .out = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Flow", public.NodePin.pinHash("flow", true), public.PinTypes.Flow, null),
                }),
            };
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = self; // autofix
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
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

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_PLAY});
        }
    },
);

const event_shutdown_node_i = public.NodeI.implement(
    .{
        .name = "Event Shutdown",
        .type_name = public.EVENT_SHUTDOWN_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(public.NodePin, &.{}),
                .out = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Flow", public.NodePin.pinHash("flow", true), public.PinTypes.Flow, null),
                }),
            };
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = self; // autofix
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
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

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_STOP});
        }
    },
);

const event_tick_node_i = public.NodeI.implement(
    .{
        .name = "Event Tick",
        .type_name = public.EVENT_TICK_NODE_TYPE_STR,
        .category = "Event",
        .pivot = .pivot,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(public.NodePin, &.{}),
                .out = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Flow", public.NodePin.pinHash("flow", true), public.PinTypes.Flow, null),
                }),
            };
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = self; // autofix
            _ = args;
            _ = in_pins;
            try out_pins.writeTyped(bool, 0, 0, true);
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

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_STOPWATCH});
        }
    },
);

const PrintNodeState = struct {
    input_validity: public.ValidityHash = 0,
};

const print_node_i = public.NodeI.implement(
    .{
        .name = "Print",
        .type_name = "print",
        .sidefect = true,
    },
    PrintNodeState,
    struct {
        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Flow", public.NodePin.pinHash("flow", false), public.PinTypes.Flow, null),
                    public.NodePin.init("Value", public.NodePin.pinHash("value", false), public.PinTypes.GENERIC, null),
                }),
                .out = try allocator.dupe(public.NodePin, &.{}),
            };
        }

        pub fn create(self: *const public.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
            const real_state: *PrintNodeState = @ptrCast(@alignCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins;

            const value_pin_type = in_pins.getPinType(1) orelse return;
            const iface = _graphvm.findValueTypeI(value_pin_type).?;

            var buffer: [256]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const allocator = fba.allocator();

            const str_value = try iface.valueToString(allocator, in_pins.data[1].?[0..iface.size]);
            log.debug("{s}", .{str_value});
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

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_PRINT});
        }
    },
);

const ConstNodeState = struct {
    version: cdb.ObjVersion = 0,
    value_type: *const public.GraphValueTypeI = undefined,
    value_obj: cdb.ObjId = .{},
};

const const_node_i = public.NodeI.implement(
    .{
        .name = "Const",
        .type_name = "const",
        .settings_type = public.ConstNodeSettings.type_hash,
    },
    ConstNodeState,
    struct {
        const Self = @This();
        const out = public.NodePin.pinHash("value", true);

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix

            const db = _cdb.getDbFromObjid(graph_obj);
            const node_r = public.GraphType.read(_cdb, node_obj).?;

            var type_hash: cetech1.StrId32 = .{};
            if (public.NodeType.readSubObj(_cdb, node_r, .settings)) |setting| {
                const settings_r = public.ConstNodeSettings.read(_cdb, setting).?;

                if (public.ConstNodeSettings.readSubObj(_cdb, settings_r, .value)) |value_obj| {
                    const value_type = _graphvm.findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;
                    type_hash = value_type.type_hash;
                }
            }

            return .{
                .in = try allocator.dupe(public.NodePin, &.{}),
                .out = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Value", public.NodePin.pinHash("value", true), type_hash, null),
                }),
            };
        }

        pub fn create(self: *const public.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            const real_state: *ConstNodeState = @ptrCast(@alignCast(state));
            real_state.* = .{};

            const db = _cdb.getDbFromObjid(node_obj);

            const node_r = public.GraphType.read(_cdb, node_obj).?;
            if (public.NodeType.readSubObj(_cdb, node_r, .settings)) |setting| {
                const settings_r = public.ConstNodeSettings.read(_cdb, setting).?;

                if (public.ConstNodeSettings.readSubObj(_cdb, settings_r, .value)) |value_obj| {
                    const value_type = _graphvm.findValueTypeIByCdb(_cdb.getTypeHash(db, value_obj.type_idx).?).?;
                    real_state.value_type = value_type;
                    real_state.value_obj = value_obj;
                }
            }
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = self; // autofix
            _ = in_pins;
            const real_state: *ConstNodeState = @ptrCast(@alignCast(args.state));

            // TODO: SHIT
            var value: [2048]u8 = undefined;
            try real_state.value_type.valueFromCdb(args.allocator, real_state.value_obj, value[0..real_state.value_type.size]);
            const vh = try real_state.value_type.calcValidityHash(value[0..real_state.value_type.size]);
            try out_pins.write(0, vh, value[0..real_state.value_type.size]);
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

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Const});
        }
    },
);

const RandomF32NodeState = struct {
    prg: ?std.Random.DefaultPrng = null,
    random: std.Random = undefined,
};
const random_f32_node_i = public.NodeI.implement(
    .{
        .name = "Random f32",
        .type_name = "random_f32",
        .category = "Random",
    },
    RandomF32NodeState,
    struct {
        const Self = @This();
        const out = public.NodePin.pinHash("value", true);

        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Min", public.NodePin.pinHash("min", false), public.PinTypes.F32, null),
                    public.NodePin.init("Max", public.NodePin.pinHash("max", false), public.PinTypes.F32, null),
                    public.NodePin.init("Seed", public.NodePin.pinHash("seed", false), public.PinTypes.U64, null),
                }),
                .out = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Value", public.NodePin.pinHash("value", true), public.PinTypes.F32, null),
                }),
            };
        }

        pub fn create(self: *const public.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = node_obj; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix

            const real_state: *RandomF32NodeState = @ptrCast(@alignCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = self; // autofix
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
            self: *const public.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Random});
        }
    },
);

const get_entity_node_i = public.NodeI.implement(
    .{
        .name = "Get entity",
        .type_name = "get_entity",
        .category = "ECS",
    },
    null,
    struct {
        pub fn getPinsDef(self: *const public.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !public.NodePinDef {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = self; // autofix

            return .{
                .in = try allocator.dupe(public.NodePin, &.{}),
                .out = try allocator.dupe(public.NodePin, &.{
                    public.NodePin.init("Entity", public.NodePin.pinHash("entity", true), public.PinTypes.Entity, null),
                }),
            };
        }

        pub fn execute(self: *const public.NodeI, args: public.ExecuteArgs, in_pins: public.InPins, out_pins: *public.OutPins) !void {
            _ = in_pins; // autofix
            _ = self; // autofix
            if (_graphvm.getContext(anyopaque, args.instance, ecs.ECS_ENTITY_CONTEXT)) |ent| {
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
        //     _ = allocator; // autofix
        //     _ = db; // autofix
        //     _ = node_obj; // autofix

        //     return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_STOP});
        // }
    },
);

pub fn addOrRemove(
    comptime module_name: @Type(.enum_literal),
    apidb: *const cetech1.apidb.ApiDbAPI,
    cdbapi: *const cdb.CdbAPI,
    logapi: *const cetech1.log.LogAPI,
    graphvmapi: *const public.GraphVMApi,
    load: bool,
) !void {
    _log = logapi;
    _graphvm = graphvmapi;
    _cdb = cdbapi;

    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &flow_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &bool_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &string_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &i32_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &u32_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &i64_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &u64_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &f32_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &f64_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &vec2f_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &vec3f_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &vec4f_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &quatf_value_type_i, load);
    try apidb.implOrRemove(module_name, public.GraphValueTypeI, &color4f_value_type_i, load);

    try apidb.implOrRemove(module_name, public.NodeI, &event_node_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &event_tick_node_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &event_shutdown_node_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &print_node_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &const_node_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &random_f32_node_i, load);
    try apidb.implOrRemove(module_name, public.NodeI, &get_entity_node_i, load);
}

pub fn createTypes(db: cdb.DbId) !void {
    // ConstNodeSettings
    {
        _ = try _cdb.addType(
            db,
            public.ConstNodeSettings.name,
            &[_]cdb.PropDef{
                .{ .prop_idx = public.ConstNodeSettings.propIdx(.value), .name = "value", .type = .SUBOBJECT },
            },
        );
    }

    // RandomF32NodeSettings
    {
        _ = try _cdb.addType(
            db,
            public.RandomF32NodeSettings.name,
            &[_]cdb.PropDef{},
        );
    }

    // flowType
    {
        _ = try _cdb.addType(
            db,
            public.flowType.name,
            &[_]cdb.PropDef{},
        );
    }
}
