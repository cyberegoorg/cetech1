// TODO: SHIT
const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const public = @import("shader_system.zig");

const graphvm = @import("graphvm");
const editor_inspector = @import("editor_inspector");

const basic_nodes = @import("basic_nodes.zig");
const render_viewport = @import("render_viewport");

const module_name = .shader_system;

const MAX_SHADER_INSTANCE = 1_024 * 2; // =D very naive // TODO: instance dynamic?
const MAX_PROGRAMS = 1_000; // =D very naive

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;
var _inspector: *const editor_inspector.InspectorAPI = undefined;
var _graphvm: *const graphvm.GraphVMApi = undefined;

const ShaderDefMap = cetech1.AutoArrayHashMap(cetech1.StrId32, public.ShaderDefinition);
const ShaderPool = cetech1.heap.VirtualPool(Shader);

const ProgramCache = cetech1.AutoArrayHashMap(u64, gpu.ProgramHandle);
const ProgramCounter = cetech1.heap.VirtualArray(cetech1.heap.AtomicInt);

const NodeIMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *const graphvm.NodeI);
const StringIntern = cetech1.string.InternWithLock([:0]const u8);
const NodeExportMap = cetech1.AutoArrayHashMap(cetech1.StrId32, public.DefExport);

const UniformBufferPool = cetech1.heap.VirtualPool(UniformBuffer);
const ShaderContextPool = cetech1.heap.VirtualPool(ShaderContext);

const VariableSemantic = enum {
    position,
    normal,
    tangent,
    bitangent,
    color0,
    color1,
    color2,
    color3,
    indices,
    weight,
    texcoord0,
    texcoord1,
    texcoord2,
    texcoord3,
    texcoord4,
    texcoord5,
    texcoord6,
    texcoord7,
};

const UniformHandleMap = cetech1.AutoArrayHashMap(cetech1.StrId32, gpu.UniformHandle);

const System = struct {
    uniforms: UniformHandleMap = .{},

    pub fn deinit(self: *System, allocator: Allocator) void {
        for (self.uniforms.values()) |u| {
            _gpu.destroyUniform(u);
        }
        self.uniforms.deinit(allocator);
    }
};

const VariantList = cetech1.ArrayList(public.ShaderVariant);
const ShaderVariantMap = cetech1.AutoArrayHashMap(cetech1.StrId32, VariantList);

const Shader = struct {
    variants: ShaderVariantMap = .{},

    pub fn deinit(self: *Shader, allocator: std.mem.Allocator) void {
        for (self.variants.values()) |*variants| {
            variants.deinit(allocator);
        }
        self.variants.deinit(allocator);
    }
};

const SystemToIdx = cetech1.AutoArrayHashMap(cetech1.StrId32, usize);

const MAX_UNIFORM_VALUE_SIZE = @sizeOf(zm.Mat);

const UniformBuffer = struct {
    data: cetech1.AutoArrayHashMap(cetech1.StrId32, [MAX_UNIFORM_VALUE_SIZE]u8) = .{},

    pub fn init() UniformBuffer {
        return .{};
    }

    pub fn deinit(self: *UniformBuffer) void {
        self.data.deinit(_allocator);
    }

    pub fn clear(self: *UniformBuffer) void {
        self.data.clearRetainingCapacity();
    }
};

const buffer_vt = public.UniformBuffer.VTable.implement(struct {
    pub fn set(self: *anyopaque, name: cetech1.StrId32, value: []const u8) !void {
        var true_buffer: *UniformBuffer = @alignCast(@ptrCast(self));
        const get_or_put = try true_buffer.data.getOrPut(_allocator, name);
        std.mem.copyForwards(u8, get_or_put.value_ptr, value);
    }
});

const ShaderContext = struct {
    systems: cetech1.ArrayList(*public.SystemInstance) = .{},

    pub fn init() ShaderContext {
        return .{};
    }

    pub fn deinit(self: *ShaderContext) void {
        self.systems.deinit(_allocator);
    }

    pub fn clear(self: *ShaderContext) void {
        self.systems.clearRetainingCapacity();
    }
};

const shader_context_vt = public.ShaderContext.VTable.implement(struct {
    pub fn addSystem(self: *anyopaque, system: *public.SystemInstance) !void {
        const true_buffer: *ShaderContext = @alignCast(@ptrCast(self));
        try true_buffer.systems.append(_allocator, system);
    }

    pub fn submit(
        self: *anyopaque,
        encoder: gpu.Encoder,
    ) void {
        const true_buffer: *ShaderContext = @alignCast(@ptrCast(self));
        for (true_buffer.systems.items) |instance| {
            submitSystem(encoder, instance.*);
        }
    }
});

// Global state that can surive hot-reload
const G = struct {
    shader_def_map: ShaderDefMap = undefined,
    shader_pool: ShaderPool = undefined,

    system_pool: [public.MAX_SYSTEMS]System = undefined,

    make_node_result_type_aspec: *editor_inspector.UiPropertyAspect = undefined,
    uniform_node_result_type_aspec: *editor_inspector.UiPropertyAspect = undefined,
    const_node_result_type_aspec: *editor_inspector.UiPropertyAspect = undefined,

    program_cache: ProgramCache = undefined,
    program_counter: ProgramCounter = undefined,

    output_node_iface_map: NodeIMap = .{},
    function_node_iface_map: NodeIMap = .{},
    exported_node_iface_map: NodeIMap = .{},
    exported_map: NodeExportMap = undefined,
    node_str_itern: StringIntern = undefined,

    system_to_idx: SystemToIdx = undefined,
    system_counter: cetech1.heap.AtomicInt = undefined,

    uniform_buffer_pool: UniformBufferPool = undefined,
    shader_context_pool: ShaderContextPool = undefined,
};
var _g: *G = undefined;

const api = public.ShaderSystemAPI{
    .addShaderDefiniton = addShaderDefiniton,
    .addSystemDefiniton = addSystemDefiniton,

    .compileShader = compileShader,

    .submitShaderUniforms = submitUniforms,
    .submitSystemUniforms = submitSystem,
    .destroyShader = destroyShader,
    .createShaderInstance = createShaderInstance,
    .destroyShaderInstance = destroyShaderInstance,

    .createSystemInstance = createSystemInstance,
    .destroySystemInstance = destroySystemInstance,

    .selectShaderVariant = selectShaderVariant,

    .createUniformBuffer = createUniformBuffer,
    .destroyUniformBuffer = destroyUniformBuffer,

    .createShaderContext = createShaderContext,
    .destroyShaderContext = destroyShaderContext,
};

inline fn nodeInputToType(input_type: public.DefGraphNodeInputType) cetech1.StrId32 {
    return switch (input_type) {
        .vec2 => public.PinTypes.GPU_VEC2,
        .vec3 => public.PinTypes.GPU_VEC3,
        .vec4 => public.PinTypes.GPU_VEC4,
        .float => public.PinTypes.GPU_FLOAT,
    };
}

inline fn defVariableToType(var_type: public.DefVariableType) cetech1.StrId32 {
    return switch (var_type) {
        .vec2 => public.PinTypes.GPU_VEC2,
        .vec3 => public.PinTypes.GPU_VEC3,
        .vec4 => public.PinTypes.GPU_VEC4,
        .float => public.PinTypes.GPU_FLOAT,
    };
}

inline fn nodeInputToTypeShort(input_type: public.DefGraphNodeInputType) []const u8 {
    return switch (input_type) {
        .vec2 => "v2",
        .vec3 => "v3",
        .vec4 => "v4",
        .float => "f",
    };
}

inline fn nodeOutputToType(input_type: public.DefGraphNodeOutputType) cetech1.StrId32 {
    return switch (input_type) {
        .vec2 => public.PinTypes.GPU_VEC2,
        .vec3 => public.PinTypes.GPU_VEC3,
        .vec4 => public.PinTypes.GPU_VEC4,
        .float => public.PinTypes.GPU_FLOAT,
    };
}

fn addShaderDefiniton(name: []const u8, definition: public.ShaderDefinition) !void {
    if (definition.graph_node) |graph_node| {
        // Function Node
        if (graph_node.outputs != null) {
            const iface = try _allocator.create(graphvm.NodeI);
            iface.* = graphvm.NodeI.implement(
                .{
                    .name = if (graph_node.display_name) |display_name| display_name else graph_node.name,
                    .type_name = graph_node.name,
                    .category = graph_node.category,
                },
                null,
                struct {
                    const Self = @This();

                    pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
                        _ = node_obj; // autofix
                        _ = graph_obj; // autofix
                        const shader_def = _g.shader_def_map.get(self.type_hash).?;

                        var in_pins = graphvm.NodePinList{};
                        var out_pins = graphvm.NodePinList{};

                        if (shader_def.graph_node.?.inputs) |inputs| {
                            try in_pins.ensureTotalCapacityPrecise(allocator, inputs.len);
                            for (inputs) |input| {
                                const pin_name = try graphvm.NodePin.alocPinHash(allocator, input.name, false);
                                defer allocator.free(pin_name);

                                in_pins.appendAssumeCapacity(
                                    graphvm.NodePin.init(
                                        if (input.display_name) |dn| dn else input.name,
                                        try _g.node_str_itern.intern(pin_name),
                                        if (input.type) |t| nodeInputToType(t) else graphvm.PinTypes.GENERIC,
                                        null,
                                    ),
                                );
                            }
                        }

                        if (shader_def.graph_node.?.outputs) |outputs| {
                            try out_pins.ensureTotalCapacityPrecise(allocator, outputs.len);

                            for (outputs) |output| {
                                const pin_name = try graphvm.NodePin.alocPinHash(allocator, output.name, true);
                                defer allocator.free(pin_name);

                                const tof_name = if (output.type_of) |tof| try graphvm.NodePin.alocPinHash(allocator, tof, false) else null;
                                defer if (tof_name) |tof| allocator.free(tof);

                                out_pins.appendAssumeCapacity(
                                    graphvm.NodePin.init(
                                        if (output.display_name) |dn| dn else output.name,
                                        try _g.node_str_itern.intern(pin_name),
                                        if (output.type) |t| nodeOutputToType(t) else graphvm.PinTypes.GENERIC,
                                        if (tof_name) |tof| try _g.node_str_itern.intern(tof) else null,
                                    ),
                                );
                            }
                        }

                        return .{
                            .in = try in_pins.toOwnedSlice(allocator),
                            .out = try out_pins.toOwnedSlice(allocator),
                        };
                    }

                    pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
                        _ = self; // autofix
                        _ = args; // autofix
                        _ = out_pins; // autofix
                        _ = in_pins; // autofix
                    }

                    pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
                        const real_state = public.GpuTranspileState.fromBytes(state);

                        const shader_def = _g.shader_def_map.get(self.type_hash).?;

                        var fce_name = cetech1.ByteList{};
                        var fce_name_w = fce_name.writer(args.allocator);
                        defer fce_name.deinit(args.allocator);

                        try fce_name_w.writeAll(self.type_name);

                        var fce_args = cetech1.ByteList{};
                        var fce_args_w = fce_args.writer(args.allocator);
                        defer fce_args.deinit(args.allocator);

                        var fce_out_struct = cetech1.ByteList{};
                        var fce_out_struct_w = fce_out_struct.writer(args.allocator);
                        defer fce_out_struct.deinit(args.allocator);

                        var inputs_vals = cetech1.ArrayList(?public.GpuValue){};
                        defer inputs_vals.deinit(args.allocator);

                        real_state.var_counter += 1;
                        const var_id = real_state.var_counter;
                        const out_var_name = try std.fmt.allocPrint(args.allocator, "fce_{d}", .{var_id});

                        if (shader_def.graph_node.?.inputs) |inputs| {
                            for (inputs, 0..) |input, idx| {
                                const is_generic = input.type == null;

                                const tt = blk: {
                                    if (is_generic) {
                                        const real_type = in_pins.getPinType(idx) orelse continue;

                                        const result_type: public.DefGraphNodeInputType = switch (real_type.id) {
                                            public.PinTypes.GPU_FLOAT.id => .float,
                                            public.PinTypes.GPU_VEC2.id => .vec2,
                                            public.PinTypes.GPU_VEC3.id => .vec3,
                                            public.PinTypes.GPU_VEC4.id => .vec4,
                                            else => undefined,
                                        };
                                        break :blk result_type;
                                    }
                                    break :blk input.type.?;
                                };
                                const short_type = nodeInputToTypeShort(tt);

                                try fce_name_w.print("{s}", .{short_type});

                                const dot = if (idx == inputs.len - 1) "" else ",";
                                try fce_args_w.print("in {s} {s}{s} ", .{ @tagName(tt), input.name, dot });

                                _, const val = in_pins.read(public.GpuValue, idx) orelse .{ 0, public.GpuValue{ .str = "vec4(1,1,1,1)" } };
                                try inputs_vals.append(args.allocator, val);
                            }
                        }

                        const get_result = try real_state.guard_set.getOrPut(real_state.allocator, cetech1.strId64(fce_name.items));

                        if (shader_def.graph_node.?.outputs) |outputs| {
                            for (outputs, 0..) |output, idx| {
                                const is_generic = output.type == null;

                                const tt = blk: {
                                    if (is_generic) {
                                        const real_type = in_pins.getPinType(idx) orelse continue;

                                        const result_type: public.DefGraphNodeOutputType = switch (real_type.id) {
                                            public.PinTypes.GPU_FLOAT.id => .float,
                                            public.PinTypes.GPU_VEC2.id => .vec2,
                                            public.PinTypes.GPU_VEC3.id => .vec3,
                                            public.PinTypes.GPU_VEC4.id => .vec4,
                                            else => undefined,
                                        };
                                        break :blk result_type;
                                    }
                                    break :blk output.type.?;
                                };

                                try fce_out_struct_w.print("  {s} {s};", .{ @tagName(tt), output.name });

                                const val = public.GpuValue{ .str = try std.fmt.allocPrint(args.allocator, "{s}.{s}", .{ out_var_name, output.name }) };
                                try out_pins.writeTyped(public.GpuValue, idx, cetech1.strId64(val.str).id, val);
                            }
                        }

                        if (!get_result.found_existing) {
                            var common_w = real_state.common_code.writer(real_state.allocator);
                            // Write fce output struct
                            try common_w.print(
                                \\struct {s}_out {{
                                \\  {s}
                                \\}};
                                \\
                            , .{ fce_name.items, fce_out_struct.items });

                            // Write fce decl
                            try common_w.print(
                                \\{s}_out {s}({s}) {{
                                \\  {s}_out output;
                                \\  {s}
                                \\  return output;
                                \\}}
                                \\
                            , .{
                                fce_name.items,
                                fce_name.items,
                                fce_args.items,
                                fce_name.items,
                                shader_def.function.?,
                            });
                        }

                        var w = try real_state.getWriter(context.?, stage.?);

                        try w.print("{s}_out {s} = {s}(", .{
                            fce_name.items,
                            out_var_name,
                            fce_name.items,
                        });
                        for (inputs_vals.items, 0..) |inputs, idx| {
                            const dot = if (idx == inputs_vals.items.len - 1) "" else ",";
                            try w.print("{s}{s}", .{ inputs.?.str, dot });
                        }
                        try w.print(");\n", .{});
                    }

                    pub fn icon(
                        self: *const graphvm.NodeI,
                        buff: [:0]u8,
                        allocator: std.mem.Allocator,
                        node_obj: cdb.ObjId,
                    ) ![:0]u8 {
                        _ = self; // autofix
                        _ = allocator; // autofix
                        _ = node_obj; // autofix

                        return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
                    }
                },
            );

            try _apidb.implOrRemove(module_name, graphvm.NodeI, iface, true);
            try _g.function_node_iface_map.put(_allocator, cetech1.strId32(graph_node.name), iface);

            // Output node
        } else {
            const iface = try _allocator.create(graphvm.NodeI);

            iface.* = graphvm.NodeI.implement(
                .{
                    .name = if (graph_node.display_name) |display_name| display_name else graph_node.name,
                    .type_name = graph_node.name,
                    .category = graph_node.category,

                    .pivot = .transpiler,
                    .sidefect = true,
                },
                CreateShaderState,
                struct {
                    const Self = @This();

                    pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
                        _ = node_obj; // autofix
                        _ = graph_obj; // autofix
                        const shader_def = _g.shader_def_map.get(self.type_hash).?;
                        var in_pins = graphvm.NodePinList{};
                        if (shader_def.graph_node.?.inputs) |inputs| {
                            try in_pins.ensureTotalCapacityPrecise(allocator, inputs.len);

                            for (inputs) |input| {
                                const pin_name = try graphvm.NodePin.alocPinHash(allocator, input.name, false);
                                defer allocator.free(pin_name);

                                in_pins.appendAssumeCapacity(
                                    graphvm.NodePin.init(
                                        if (input.display_name) |dn| dn else input.name,
                                        try _g.node_str_itern.intern(pin_name),
                                        if (input.type) |t| nodeInputToType(t) else graphvm.PinTypes.GENERIC,
                                        null,
                                    ),
                                );
                            }
                        }

                        return .{
                            .in = try in_pins.toOwnedSlice(allocator),
                            .out = try allocator.dupe(graphvm.NodePin, &.{
                                graphvm.NodePin.init("GPU shader", graphvm.NodePin.pinHash("gpu_shader", true), public.PinTypes.GPU_SHADER, null),
                            }),
                        };
                    }

                    pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
                        _ = self; // autofix
                        _ = reload; // autofix
                        _ = allocator; // autofix
                        _ = node_obj; // autofix
                        const real_state: *CreateShaderState = @alignCast(@ptrCast(state));
                        real_state.* = .{};

                        if (transpile_state) |ts| {
                            const t_state = std.mem.bytesAsValue(public.GpuTranspileState, ts);
                            real_state.shader = try createShaderInstance(t_state.shader.?);
                        }
                    }

                    pub fn destroy(self: *const graphvm.NodeI, state: *anyopaque, reload: bool) !void {
                        _ = self; // autofix
                        _ = reload; // autofix
                        const real_state: *CreateShaderState = @alignCast(@ptrCast(state));
                        if (real_state.shader) |*sh| {
                            destroyShaderInstance(sh);
                        }
                    }

                    pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
                        _ = self; // autofix
                        _ = in_pins; // autofix
                        const s = args.getState(CreateShaderState).?;
                        try out_pins.writeTyped(public.ShaderInstance, 0, try gpu_shader_value_type_i.calcValidityHash(&std.mem.toBytes(s.shader.?)), s.shader.?);
                    }

                    pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
                        _ = out_pins; // autofix
                        const real_state = public.GpuTranspileState.fromBytes(state);

                        const shader_def = _g.shader_def_map.get(self.type_hash).?;

                        if (context) |cctx| {
                            if (shader_def.graph_node.?.inputs) |inputs| {
                                for (inputs, 0..) |input, idx| {
                                    if (!input.stage.?.eql(stage.?)) continue;

                                    const input_contexts: []const []const u8 = if (input.contexts) |ctxs| ctxs else &.{"default"};
                                    for (input_contexts) |ctx| {
                                        if (!std.mem.eql(u8, ctx, cctx)) continue;

                                        const get_ctx_result = try real_state.context_result_map.getOrPut(real_state.allocator, ctx);
                                        if (!get_ctx_result.found_existing) {
                                            get_ctx_result.value_ptr.* = .{};
                                        }

                                        const get_result = try get_ctx_result.value_ptr.getOrPut(real_state.allocator, input.stage.?);
                                        if (!get_result.found_existing) {
                                            get_result.value_ptr.* = .{};
                                        }

                                        const w = get_result.value_ptr.*.writer(real_state.allocator);

                                        _, const val = in_pins.read(public.GpuValue, idx) orelse .{ 0, public.GpuValue{ .str = "" } };
                                        try w.print("graph.{s} = {s};\n", .{
                                            input.name,
                                            val.str,
                                        });
                                    }
                                }
                            }
                        } else {
                            var vs_common = cetech1.ByteList{};
                            defer vs_common.deinit(args.allocator);
                            const vs_common_w = vs_common.writer(args.allocator);

                            var fs_common = cetech1.ByteList{};
                            defer fs_common.deinit(args.allocator);
                            const fs_common_w = fs_common.writer(args.allocator);

                            var common_writer = real_state.common_code.writer(real_state.allocator);

                            // graph struct
                            try common_writer.print("struct ct_graph {{\n", .{});
                            if (shader_def.graph_node.?.inputs) |inputs| {
                                for (inputs, 0..) |input, idx| {
                                    const is_generic = input.type == null;

                                    const tt = blk: {
                                        if (is_generic) {
                                            const real_type = in_pins.getPinType(idx) orelse continue;

                                            const result_type: public.DefGraphNodeInputType = switch (real_type.id) {
                                                public.PinTypes.GPU_FLOAT.id => .float,
                                                public.PinTypes.GPU_VEC2.id => .vec2,
                                                public.PinTypes.GPU_VEC3.id => .vec3,
                                                public.PinTypes.GPU_VEC4.id => .vec4,
                                                else => undefined,
                                            };
                                            break :blk result_type;
                                        }
                                        break :blk input.type.?;
                                    };

                                    try common_writer.print("  {s} {s};\n", .{ @tagName(tt), input.name });
                                }
                            }

                            if (shader_def.vertex_block) |vb| {
                                if (vb.exports) |exports| {
                                    for (exports) |ex| {
                                        if (ex.to_node) {
                                            try common_writer.print("  {s} {s};\n", .{ @tagName(ex.type), ex.name });
                                        }
                                    }
                                }
                            }
                            if (shader_def.fragment_block) |fb| {
                                if (fb.exports) |exports| {
                                    for (exports) |ex| {
                                        if (ex.to_node) {
                                            try common_writer.print("  {s} {s};\n", .{ @tagName(ex.type), ex.name });
                                        }
                                    }
                                }
                            }
                            try common_writer.print("}};\n", .{});

                            // Graph structure init
                            try common_writer.print(
                                \\
                                \\void ct_graph_init(out ct_graph graph) {{
                                \\      graph = (ct_graph)0; 
                                \\}}
                                \\
                            , .{});

                            for (real_state.context_result_map.keys(), real_state.context_result_map.values()) |ctx, v| {
                                for (v.keys(), v.values()) |stage_id, data| {
                                    const w = if (stage_id.eql(public.TranspileStages.Fragment)) fs_common_w else vs_common_w;
                                    const is_default = std.mem.eql(u8, ctx, "default");

                                    try w.print("void ct_graph_eval{s}{s}(inout ct_graph graph, in ct_input input){{\n", .{
                                        if (!is_default) "_" else "",
                                        if (!is_default) ctx else "",
                                    });

                                    if (real_state.context_map.get(ctx)) |common_ctx| {
                                        if (common_ctx.get(stage_id)) |d| {
                                            try w.writeAll(d.items);
                                        }
                                    }

                                    try w.writeAll(data.items);

                                    try w.print("}}\n", .{});
                                }
                            }

                            const result_shader_def = public.ShaderDefinition{
                                .imports = real_state.imports.values(),
                                .common_block = real_state.common_code.items,
                                .vertex_block = .{
                                    .common_block = vs_common.items,
                                    .code = "",
                                },
                                .fragment_block = .{
                                    .common_block = fs_common.items,
                                    .code = "",
                                },
                                .defines = real_state.defines.keys(),
                                .compile = shader_def.compile,
                            };

                            //log.debug("Shader def: {s}", .{std.json.fmt(shader_def, .{ .whitespace = .indent_1 })});

                            if (result_shader_def.vertex_block) |vertex| {
                                log.debug("Shader def vertex code:", .{});
                                log.debug("{s}", .{vertex.code});

                                if (vertex.common_block) |common| {
                                    log.debug("Shader def vs common code:", .{});
                                    log.debug("{s}", .{common});
                                }
                            }

                            if (result_shader_def.fragment_block) |fragment| {
                                log.debug("Shader def fragment code:", .{});
                                log.debug("{s}", .{fragment.code});

                                if (fragment.common_block) |common| {
                                    log.debug("Shader def fs common code:", .{});
                                    log.debug("{s}", .{common});
                                }
                            }

                            if (result_shader_def.common_block) |common| {
                                log.debug("Shader def common code:", .{});
                                log.debug("{s}", .{common});
                            }

                            if (result_shader_def.defines) |dd| {
                                log.debug("Shader def defines: ", .{});
                                for (dd) |d| {
                                    log.debug("\t{s}", .{d});
                                }
                            }

                            real_state.shader = try compileShader(
                                _allocator,
                                &.{
                                    self.type_hash,
                                },
                                result_shader_def,
                            );

                            log.debug("Transpiled shader: {any}", .{real_state.shader});
                        }
                    }

                    pub fn getTranspileStages(self: *const graphvm.NodeI, allocator: std.mem.Allocator) ![]const graphvm.TranspileStage {
                        const shader_def = _g.shader_def_map.get(self.type_hash).?;

                        if (shader_def.graph_node.?.inputs) |inputs| {
                            var contexts = std.StringArrayHashMapUnmanaged(cetech1.AutoArrayHashMap(cetech1.StrId32, cetech1.ArrayList(u32))){};
                            defer {
                                for (contexts.values()) |*v| {
                                    for (v.values()) |*vv| {
                                        vv.deinit(allocator);
                                    }
                                    v.deinit(allocator);
                                }
                                contexts.deinit(allocator);
                            }

                            for (inputs, 0..) |input, idx| {
                                const pin_name = try graphvm.NodePin.alocPinHash(allocator, input.name, false);
                                defer allocator.free(pin_name);

                                const input_contexts: []const []const u8 = if (input.contexts) |ctxs| ctxs else &.{"default"};
                                for (input_contexts) |ctx| {
                                    const get_ctx_result = try contexts.getOrPut(allocator, ctx);
                                    if (!get_ctx_result.found_existing) {
                                        get_ctx_result.value_ptr.* = .{};
                                    }

                                    const get_result = try get_ctx_result.value_ptr.getOrPut(allocator, input.stage.?);
                                    if (!get_result.found_existing) {
                                        get_result.value_ptr.* = .{};
                                    }

                                    try get_result.value_ptr.append(allocator, @truncate(idx));
                                }
                            }

                            var pins = try cetech1.ArrayList(graphvm.TranspileStage).initCapacity(allocator, inputs.len);
                            for (contexts.keys(), contexts.values()) |ctx, v| {
                                for (v.keys(), v.values()) |stage_id, *pin_list| {
                                    try pins.append(
                                        allocator,
                                        .{
                                            .id = stage_id,
                                            .pin_idx = try pin_list.toOwnedSlice(allocator),
                                            .contexts = ctx,
                                        },
                                    );
                                }
                            }

                            return pins.toOwnedSlice(allocator);
                        }

                        return try allocator.dupe(graphvm.TranspileStage, &.{});
                    }

                    pub fn icon(
                        self: *const graphvm.NodeI,
                        buff: [:0]u8,
                        allocator: std.mem.Allocator,
                        node_obj: cdb.ObjId,
                    ) ![:0]u8 {
                        _ = self; // autofix
                        _ = allocator; // autofix
                        _ = node_obj; // autofix

                        return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
                    }

                    pub fn createTranspileState(self: *const graphvm.NodeI, allocator: std.mem.Allocator) anyerror![]u8 {
                        _ = self; // autofix
                        const state = try allocator.create(public.GpuTranspileState);
                        state.* = public.GpuTranspileState.init(allocator);
                        return std.mem.asBytes(state);
                    }

                    pub fn destroyTranspileState(self: *const graphvm.NodeI, state: []u8) void {
                        _ = self; // autofix
                        const real_state = public.GpuTranspileState.fromBytes(state);
                        if (real_state.shader) |shader| {
                            destroyShader(shader);
                        }
                        real_state.deinit();
                    }
                },
            );
            try _apidb.implOrRemove(module_name, graphvm.NodeI, iface, true);
            try _g.function_node_iface_map.put(_allocator, cetech1.strId32(graph_node.name), iface);

            if (definition.vertex_block) |vb| {
                if (vb.exports) |exports| {
                    for (exports) |ex| {
                        if (ex.to_node) {
                            try createExportedNode(_allocator, graph_node, ex);
                        }
                    }
                }
            }
            if (definition.fragment_block) |fb| {
                if (fb.exports) |exports| {
                    for (exports) |ex| {
                        if (ex.to_node) {
                            try createExportedNode(_allocator, graph_node, ex);
                        }
                    }
                }
            }
        }
        try _g.shader_def_map.put(_allocator, cetech1.strId32(graph_node.name), definition);
    } else {
        try _g.shader_def_map.put(_allocator, cetech1.strId32(name), definition);
    }
}

fn addSystemDefiniton(name: []const u8, definition: public.ShaderDefinition) !void {
    const system_id = cetech1.strId32(name);
    const idx = _g.system_counter.fetchAdd(1, .monotonic);

    try _g.system_to_idx.put(_allocator, system_id, idx);
    try _g.shader_def_map.put(_allocator, system_id, definition);

    var system = System{};

    if (definition.imports) |imports| {
        for (imports) |value| {
            const u_type: gpu.UniformType = switch (value.type) {
                .mat3 => .Mat3,
                .mat4 => .Mat4,
                .vec4 => .Vec4,
            };

            const u = _gpu.createUniform(value.name, u_type, 1);
            try system.uniforms.put(_allocator, cetech1.strId32(value.name), u);
        }
    }
    _g.system_pool[idx] = system;
}

fn systemsToSet(systems: []const cetech1.StrId32) public.SystemSet {
    var set = public.SystemSet.initEmpty();
    for (systems) |system| {
        set.set(_g.system_to_idx.get(system).?);
    }
    return set;
}

fn getSystemSet(systems: []*public.SystemInstance) public.SystemSet {
    var set = public.SystemSet.initEmpty();
    for (systems) |system| {
        set.set(system.system_idx);
    }
    return set;
}

fn createExportedNode(alloc: std.mem.Allocator, graph_node: public.DefGraphNode, export_def: public.DefExport) !void {
    const get_or_put = try _g.exported_node_iface_map.getOrPut(_allocator, cetech1.strId32(export_def.name));
    if (!get_or_put.found_existing) {
        const iface = try _allocator.create(graphvm.NodeI);
        get_or_put.value_ptr.* = iface;

        const name = try std.fmt.allocPrintZ(alloc, "gpu_shader_exported_var_{s}", .{export_def.name});
        defer alloc.free(name);

        const display_name = try std.fmt.allocPrintZ(alloc, "Shader export: {s}", .{export_def.name});
        defer alloc.free(display_name);

        const type_hash = cetech1.strId32(name);
        try _g.exported_map.put(_allocator, type_hash, export_def);

        iface.* = graphvm.NodeI.implement(
            .{
                .name = try _g.node_str_itern.intern(display_name),
                .type_name = try _g.node_str_itern.intern(name),
                .category = graph_node.category,
            },
            null,
            struct {
                const Self = @This();

                pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
                    _ = node_obj; // autofix
                    _ = graph_obj; // autofix

                    const exp = _g.exported_map.get(self.type_hash).?;
                    const t = defVariableToType(exp.type);

                    return .{
                        .in = try allocator.dupe(graphvm.NodePin, &.{}),
                        .out = try allocator.dupe(graphvm.NodePin, &.{
                            graphvm.NodePin.init("Value", graphvm.NodePin.pinHash("value", true), t, null),
                        }),
                    };
                }

                pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
                    _ = args; // autofix
                    _ = out_pins; // autofix
                    _ = self; // autofix
                    _ = in_pins; // autofix

                }

                pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
                    _ = stage; // autofix
                    _ = context; // autofix
                    _ = in_pins; // autofix
                    const real_state = public.GpuTranspileState.fromBytes(state);

                    const exp = _g.exported_map.get(self.type_hash).?;

                    const define = try std.fmt.allocPrint(args.allocator, "CT_EXPORTED_VAR_USED_{s}", .{exp.name});
                    try real_state.defines.put(real_state.allocator, define, {});

                    const val = public.GpuValue{ .str = try std.fmt.allocPrint(args.allocator, "graph.{s}", .{exp.name}) };
                    try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
                }

                pub fn icon(
                    self: *const graphvm.NodeI,
                    buff: [:0]u8,
                    allocator: std.mem.Allocator,
                    node_obj: cdb.ObjId,
                ) ![:0]u8 {
                    _ = self; // autofix
                    _ = allocator; // autofix
                    _ = node_obj; // autofix

                    return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
                }
            },
        );

        try _apidb.implOrRemove(module_name, graphvm.NodeI, iface, true);
    }
}

// This is included for all shaders for simplicity
const bgfx_shader = @embedFile("embed/bgfx_shader.sh");
const bgfx_compute = @embedFile("embed/bgfx_compute.sh");

fn compileShader(allocator: std.mem.Allocator, use_definitions: []const cetech1.StrId32, definition: ?public.ShaderDefinition) !?public.Shader {
    const instance = _g.shader_pool.create(null);
    const instance_idx = _g.shader_pool.index(instance);

    instance.* = .{};

    const compile = definition.?.compile.?;

    var config_map = cetech1.AutoArrayHashMap(cetech1.StrId32, public.DefCompileConfiguration){};
    defer config_map.deinit(allocator);
    try config_map.ensureTotalCapacity(allocator, compile.configurations.len);

    for (compile.configurations) |config| {
        config_map.putAssumeCapacity(cetech1.strId32(config.name), config);
    }
    const common_includes = definition.?.compile.?.includes;
    const common_includes_len = if (common_includes) |i| i.len else 0;

    var includes = try cetech1.StrId32List.initCapacity(allocator, use_definitions.len + common_includes_len);
    defer includes.deinit(allocator);

    for (use_definitions) |def| {
        includes.appendAssumeCapacity(def);
    }

    if (common_includes) |incl| {
        for (incl) |i| {
            includes.appendAssumeCapacity(cetech1.strId32(i));
        }
    }

    for (compile.contexts) |context| {
        const context_item = try instance.variants.getOrPut(_allocator, cetech1.strId32(context.name));
        context_item.value_ptr.* = .{};

        for (context.defs) |def| {
            const cfg = config_map.get(cetech1.strId32(def.config)).?;
            for (cfg.variations) |variation| {
                const systems_len = if (variation.systems) |s| s.len else 0;

                var sytem_ids = try cetech1.StrId32List.initCapacity(allocator, systems_len);
                defer sytem_ids.deinit(allocator);

                if (variation.systems) |systems| {
                    for (systems) |value| {
                        sytem_ids.appendAssumeCapacity(cetech1.strId32(value));
                    }
                }

                var d = definition.?;
                if (variation.state) |s| {
                    d.state = s;
                }

                const layer = if (def.layer) |l| cetech1.strId32(l) else null;
                const shader_variant = try compileShaderVariant(
                    allocator,
                    includes.items,
                    d,
                    layer,
                    sytem_ids.items,
                );

                try context_item.value_ptr.append(_allocator, shader_variant);
            }
        }
    }

    return .{
        .idx = instance_idx,
    };
}

fn compileShaderVariant(
    allocator: std.mem.Allocator,
    use_definitions: []const cetech1.StrId32,
    definition: ?public.ShaderDefinition,
    layer: ?cetech1.StrId32,
    systems: []const cetech1.StrId32,
) !public.ShaderVariant {
    //TODO: BRAINDUMP SHIT DETECTED
    //TODO: merge defs rules

    var var_def = cetech1.ByteList{};
    defer var_def.deinit(allocator);
    var var_def_w = var_def.writer(allocator);

    var vs_imports = cetech1.ByteList{};
    defer vs_imports.deinit(allocator);
    var vs_imports_w = vs_imports.writer(allocator);

    var vs_exports = cetech1.ByteList{};
    defer vs_exports.deinit(allocator);
    var vs_exports_w = vs_exports.writer(allocator);

    var fs_imports = cetech1.ByteList{};
    defer fs_imports.deinit(allocator);
    var fs_imports_w = fs_imports.writer(allocator);

    var fs_blocks = cetech1.ByteList{};
    defer fs_blocks.deinit(allocator);
    var fs_blocks_w = fs_blocks.writer(allocator);

    var vs_blocks = cetech1.ByteList{};
    defer vs_blocks.deinit(allocator);
    var vs_blocks_w = vs_blocks.writer(allocator);

    var cmn_blocks = cetech1.ByteList{};
    defer cmn_blocks.deinit(allocator);
    var cmn_blocks_w = cmn_blocks.writer(allocator);

    var vs_cmn_blocks = cetech1.ByteList{};
    defer vs_cmn_blocks.deinit(allocator);
    const vs_cmn_blocks_w = vs_cmn_blocks.writer(allocator);

    var fs_cmn_blocks = cetech1.ByteList{};
    defer fs_cmn_blocks.deinit(allocator);
    var fs_cmn_blocks_w = fs_cmn_blocks.writer(allocator);

    var main_imports = cetech1.ByteList{};
    defer main_imports.deinit(allocator);
    var main_imports_w = main_imports.writer(allocator);

    var vs_imports_set = cetech1.ArraySet(public.DefImportVariableType).init();
    defer vs_imports_set.deinit(allocator);

    var vs_export_set = cetech1.ArraySet([]const u8).init();
    defer vs_export_set.deinit(allocator);

    var main_imports_set = std.StringArrayHashMapUnmanaged(public.DefImport){};
    defer main_imports_set.deinit(allocator);

    var vs_input_struct = cetech1.ByteList{};
    defer vs_input_struct.deinit(allocator);
    var vs_input_struct_w = vs_input_struct.writer(allocator);

    var vs_fill_input_struct = cetech1.ByteList{};
    defer vs_fill_input_struct.deinit(allocator);
    var vs_fill_input_struct_w = vs_fill_input_struct.writer(allocator);

    var vs_fill_ouput_struct = cetech1.ByteList{};
    defer vs_fill_ouput_struct.deinit(allocator);
    var vs_fill_ouput_struct_w = vs_fill_ouput_struct.writer(allocator);

    var vs_output_struct = cetech1.ByteList{};
    defer vs_output_struct.deinit(allocator);
    var vs_output_struct_w = vs_output_struct.writer(allocator);

    var fs_input_struct = cetech1.ByteList{};
    defer fs_input_struct.deinit(allocator);
    const fs_input_struct_w = fs_input_struct.writer(allocator);

    var fs_fill_input_struct = cetech1.ByteList{};
    defer fs_fill_input_struct.deinit(allocator);
    const fs_fill_input_struct_w = fs_fill_input_struct.writer(allocator);

    var fs_output_struct = cetech1.ByteList{};
    defer fs_output_struct.deinit(allocator);
    const fs_output_struct_w = fs_output_struct.writer(allocator);

    var fs_fill_ouput_struct = cetech1.ByteList{};
    defer fs_fill_ouput_struct.deinit(allocator);
    var fs_fill_ouput_struct_w = fs_fill_ouput_struct.writer(allocator);

    var defines = std.StringArrayHashMapUnmanaged(void){};
    defer defines.deinit(allocator);

    var state: u64 = 0;
    var rgba: u32 = 0;

    const dn: usize = if (definition != null) 1 else 0;
    const system_count = systems.len;

    var all_definitions = try cetech1.ArrayList(public.ShaderDefinition).initCapacity(allocator, use_definitions.len + dn + system_count);
    defer all_definitions.deinit(allocator);

    for (use_definitions) |def_name| {
        const shader_def = _g.shader_def_map.get(def_name) orelse @panic("where shader def?");
        all_definitions.appendAssumeCapacity(shader_def);
    }

    for (systems) |system| {
        const shader_def = _g.shader_def_map.get(system) orelse @panic("where shader def?");
        all_definitions.appendAssumeCapacity(shader_def);
    }

    if (definition) |d| {
        all_definitions.appendAssumeCapacity(d);
    }

    try vs_output_struct_w.print("  vec4 position;\n", .{});
    try vs_fill_ouput_struct_w.print("  gl_Position = output.position;\n", .{});

    try fs_output_struct_w.print("  vec4 color0;\n", .{});
    try fs_fill_ouput_struct_w.print("  gl_FragData[0] = output.color0;\n", .{});

    var vs_export_semantic_counter: usize = 1;

    for (all_definitions.items) |shader_def| {
        if (shader_def.state != 0) {
            state = shader_def.state;
        }

        rgba |= shader_def.rgba;

        if (shader_def.common_block) |cb| {
            try cmn_blocks_w.print("{s}\n", .{cb});
        }

        if (shader_def.defines) |dd| {
            for (dd) |d| {
                try defines.put(allocator, d, {});
            }
        }

        if (shader_def.imports) |imports| {
            for (imports) |import| {
                const get_or_put = try main_imports_set.getOrPutValue(allocator, import.name, import);
                if (!get_or_put.found_existing) {
                    try main_imports_w.print("uniform {s} {s};\n", .{ @tagName(import.type), import.name });
                    try main_imports_w.print(
                        \\{s} load_{s}() {{
                        \\  return {s};
                        \\}}
                        \\
                    , .{ @tagName(import.type), import.name, import.name });
                }
            }
        }

        if (shader_def.vertex_block) |vb| {
            if (vb.imports) |imports| {
                for (imports, 0..) |value, idx| {
                    if (!try vs_imports_set.add(allocator, value)) continue;

                    try vs_imports_w.writeAll(vertexInputsToVariableName(value));

                    try vs_input_struct_w.print("  {s} {s};\n", .{
                        vertexInputsToVarTypeName(value),
                        vertexInputsToVariableName(value),
                    });

                    try vs_fill_input_struct_w.print("  input.{s} = {s};\n", .{ vertexInputsToVariableName(value), vertexInputsToVariableName(value) });

                    try var_def_w.print(
                        "{s} {s}  :   {s};\n",
                        .{
                            vertexInputsToVarTypeName(value),
                            vertexInputsToVariableName(value),
                            vertexInputsToSemanticName(value),
                        },
                    );

                    if (idx != imports.len - 1) {
                        try vs_imports_w.writeAll(", ");
                    }
                }
                try var_def_w.writeAll("\n");
            }

            if (vb.exports) |exports| {
                for (exports, 0..) |value, idx| {
                    if (!try vs_export_set.add(allocator, value.name)) continue;

                    const sem: VariableSemantic = @enumFromInt(vs_export_semantic_counter);
                    vs_export_semantic_counter += 1;

                    try vs_output_struct_w.print("  {s} {s};\n", .{
                        @tagName(value.type),
                        value.name,
                    });

                    try fs_input_struct_w.print("  {s} {s};\n", .{
                        @tagName(value.type),
                        value.name,
                    });

                    try fs_fill_input_struct_w.print("input.{s} = v_{s};\n", .{
                        value.name,
                        value.name,
                    });

                    try vs_fill_ouput_struct_w.print("  v_{s} = output.{s};\n", .{
                        value.name,
                        value.name,
                    });

                    try var_def_w.print(
                        "{s} v_{s}  :   {s};\n",
                        .{
                            @tagName(value.type),
                            value.name,
                            semanticToText(sem),
                        },
                    );

                    try vs_exports_w.print("v_{s}", .{value.name});
                    try fs_imports_w.print("v_{s}", .{value.name});

                    if (idx != exports.len - 1) {
                        try vs_exports_w.writeAll(", ");
                        try fs_imports_w.writeAll(", ");
                    }
                }
            }

            if (vb.common_block) |cb| {
                try vs_cmn_blocks_w.writeAll(cb);
            }

            try vs_blocks_w.writeAll(vb.code);
            try vs_blocks_w.writeAll("\n");
        }

        if (shader_def.fragment_block) |fb| {
            if (fb.common_block) |cb| {
                try fs_cmn_blocks_w.writeAll(cb);
            }

            try fs_blocks_w.writeAll(fb.code);
            try fs_blocks_w.writeAll("\n");
        }
    }

    //
    // Compile vs shader
    //
    var vs_shader_options = _gpu.createDefaultOptionsForRenderer(_gpu.getBackendType());
    vs_shader_options.shaderType = .vertex;
    vs_shader_options.defines = if (defines.count() != 0) defines.keys() else null;

    const vs_source = try std.fmt.allocPrint(
        allocator,
        \\$input {s}
        \\$output {s}
        \\
        \\// bgfx_shader.sh
        \\{s}
        \\
        \\// INPUTS
        \\struct ct_input {{
        \\{s}
        \\}};
        \\
        \\// OUTPUTS
        \\struct ct_output {{
        \\{s}
        \\}};
        \\
        \\// Common block
        \\{s}
        \\
        \\// Uniforms
        \\{s}
        \\
        \\// Common vs block
        \\{s}
        \\
        \\void main() {{
        \\  // Input and Outputs
        \\  ct_input input;
        \\  ct_output output;
        \\{s}
        \\
        \\  // Main
        \\{s}
        \\
        \\  // Write
        \\{s}
        \\
        \\}}
    ,
        .{
            vs_imports.items,
            vs_exports.items,
            bgfx_shader,

            if (vs_input_struct.items.len != 0) vs_input_struct.items else "",
            if (vs_output_struct.items.len != 0) vs_output_struct.items else "",

            if (cmn_blocks.items.len != 0) cmn_blocks.items else "",

            if (main_imports.items.len != 0) main_imports.items else "",

            if (vs_cmn_blocks.items.len != 0) vs_cmn_blocks.items else "",
            if (vs_fill_input_struct.items.len != 0) vs_fill_input_struct.items else "",
            if (vs_blocks.items.len != 0) vs_blocks.items else "",

            if (vs_fill_ouput_struct.items.len != 0) vs_fill_ouput_struct.items else "",
        },
    );
    defer allocator.free(vs_source);
    // std.debug.print("VS:\n{s}\n", .{vs_source});

    //
    // Compile fs shader
    //
    var fs_shader_options = _gpu.createDefaultOptionsForRenderer(_gpu.getBackendType());
    fs_shader_options.shaderType = .fragment;
    fs_shader_options.defines = if (defines.count() != 0) defines.keys() else null;

    const fs_source = try std.fmt.allocPrint(
        allocator,
        \\$input {s}
        \\
        \\// bgfx_shader.sh
        \\{s}
        \\
        \\// INPUTS
        \\struct ct_input {{
        \\{s}
        \\}};
        \\
        \\// OUTPUTS
        \\struct ct_output {{
        \\{s}
        \\}};
        \\
        \\// Common block
        \\{s}
        \\
        \\// Uniforms
        \\{s}
        \\
        \\// Common vs block
        \\{s}
        \\
        \\void main() {{
        \\  // Input and Outputs
        \\  ct_input input;
        \\  ct_output output;
        \\{s}
        \\
        \\  // Main
        \\{s}
        \\
        \\  // Write
        \\{s}
        \\
        \\}}
    ,
        .{
            fs_imports.items,
            bgfx_shader,
            if (fs_input_struct.items.len != 0) fs_input_struct.items else "",
            if (fs_output_struct.items.len != 0) fs_output_struct.items else "",

            if (cmn_blocks.items.len != 0) cmn_blocks.items else "",

            if (main_imports.items.len != 0) main_imports.items else "",

            if (fs_cmn_blocks.items.len != 0) fs_cmn_blocks.items else "",
            if (fs_fill_input_struct.items.len != 0) fs_fill_input_struct.items else "",
            if (fs_blocks.items.len != 0) fs_blocks.items else "",

            if (fs_fill_ouput_struct.items.len != 0) fs_fill_ouput_struct.items else "",
        },
    );
    defer allocator.free(fs_source);
    //std.debug.print("FS:\n{s}\n", .{fs_source});
    //std.debug.print("FS:\n{s}\n", .{main_imports.items});

    var h = std.hash.Wyhash.init(0);
    h.update(vs_source);
    h.update(fs_source);
    const hash = h.final();

    var shader = public.ShaderVariant{
        .hash = hash,
        .state = state,
        .rgba = rgba,
        .layer = layer,
        .system_set = systemsToSet(systems),
    };

    for (main_imports_set.values()) |value| {
        const u_type: gpu.UniformType = switch (value.type) {
            .mat3 => .Mat3,
            .mat4 => .Mat4,
            .vec4 => .Vec4,
        };

        const u = _gpu.createUniform(value.name, u_type, 1);
        try shader.uniforms.put(allocator, cetech1.strId32(value.name), u);
    }

    const cached_program = try _g.program_cache.getOrPut(_allocator, hash);
    if (cached_program.found_existing) {
        shader.prg = cached_program.value_ptr.*;

        if (shader.prg) |prg| {
            _ = _g.program_counter.items[prg.idx].fetchAdd(1, .monotonic);
        }

        return shader;
    }

    // Compile shader
    const vs_shader = try _gpu.compileShader(allocator, var_def.items, vs_source, vs_shader_options);
    defer allocator.free(vs_shader);

    const fs_shader = try _gpu.compileShader(allocator, var_def.items, fs_source, fs_shader_options);
    defer allocator.free(fs_shader);

    //
    // Create bgfx shader and program
    //
    const fs_cubes = _gpu.createShader(_gpu.copy(fs_shader.ptr, @intCast(fs_shader.len)));
    const vs_cubes = _gpu.createShader(_gpu.copy(vs_shader.ptr, @intCast(vs_shader.len)));
    const programHandle = _gpu.createProgram(vs_cubes, fs_cubes, true);

    cached_program.value_ptr.* = programHandle;
    shader.prg = programHandle;

    log.debug("prg: {d}", .{programHandle.idx});
    _g.program_counter.items[programHandle.idx] = cetech1.heap.AtomicInt.init(1);

    return shader;
}

fn selectShaderVariant(
    allocator: std.mem.Allocator,
    shader_instance: public.ShaderInstance,
    context: cetech1.StrId32,
    shader_context: *const public.ShaderContext,
) ![]*const public.ShaderVariant {
    const inst = _g.shader_pool.get(shader_instance.idx);

    var result = cetech1.ArrayList(*const public.ShaderVariant){};

    const variants = inst.variants.get(context) orelse return try result.toOwnedSlice(allocator);
    try result.ensureTotalCapacity(allocator, variants.items.len);

    var set = public.SystemSet.initEmpty();
    const true_shader_context: *const ShaderContext = @alignCast(@ptrCast(shader_context.ptr));
    for (true_shader_context.systems.items) |system| {
        set.set(system.system_idx);
    }

    for (variants.items) |*variant| {
        const intersection = set.intersectWith(variant.system_set);
        if (intersection.count() != 0) {
            result.appendAssumeCapacity(variant);
        }
    }

    return result.toOwnedSlice(allocator);
}

fn submitUniforms(encoder: gpu.Encoder, variant: *const public.ShaderVariant, shader_instance: public.ShaderInstance) void {
    if (shader_instance.uniforms) |uniforms| {
        var buffer: *UniformBuffer = @alignCast(@ptrCast(uniforms.ptr));

        for (buffer.data.keys(), buffer.data.values()) |k, v| {
            const handler = variant.uniforms.get(k) orelse continue;
            encoder.setUniform(handler, &v, 1);
        }
    }
}

fn submitSystem(encoder: gpu.Encoder, system_instance: public.SystemInstance) void {
    if (system_instance.uniforms) |uniforms| {
        var buffer: *UniformBuffer = @alignCast(@ptrCast(uniforms.ptr));

        for (buffer.data.keys(), buffer.data.values()) |k, v| {
            const system = _g.system_pool[system_instance.system_idx];

            const handler = system.uniforms.get(k).?;
            encoder.setUniform(handler, &v, 1);
        }
    }
}

fn destroyShader(shader_instance: public.Shader) void {
    const inst = _g.shader_pool.get(shader_instance.idx);

    for (inst.variants.values()) |variants| {
        for (variants.items) |variant| {
            if (variant.prg) |prg| {
                if (1 == _g.program_counter.items[prg.idx].fetchSub(1, .release)) {
                    _ = _g.program_counter.items[prg.idx].load(.acquire);
                    _gpu.destroyProgram(prg);
                    _ = _g.program_cache.swapRemove(variant.hash);
                }
            }
        }
    }

    inst.deinit(_allocator);

    _g.shader_pool.destroy(inst) catch undefined;
}

fn createShaderInstance(shader: public.Shader) !public.ShaderInstance {
    const inst = _g.shader_pool.get(shader.idx);

    var max_u: usize = 0;
    for (inst.variants.values()) |variants| {
        for (variants.items) |variant| {
            max_u = @max(max_u, variant.uniforms.count());
        }
    }

    const umap = try createUniformBuffer();

    return .{ .idx = shader.idx, .uniforms = umap };
}

fn destroyShaderInstance(shader: *public.ShaderInstance) void {
    if (shader.uniforms) |u| {
        destroyUniformBuffer(u);
    }
}

fn createSystemInstance(system_id: cetech1.StrId32) !public.SystemInstance {
    const system_idx = _g.system_to_idx.get(system_id) orelse return .{ .system_idx = 0 };
    // const system = _g.system_pool[system_idx];

    const umap = try createUniformBuffer();

    return .{ .system_idx = system_idx, .uniforms = umap };
}

fn destroySystemInstance(system: *public.SystemInstance) void {
    if (system.uniforms) |u| {
        destroyUniformBuffer(u);
    }
}

fn createUniformBuffer() !public.UniformBuffer {
    var new: bool = false;
    const buffer = _g.uniform_buffer_pool.create(&new);

    if (new) {
        buffer.* = .init();
    } else {
        buffer.clear();
    }

    return .{ .ptr = buffer, .vtable = &buffer_vt };
}
fn destroyUniformBuffer(buffer: public.UniformBuffer) void {
    const true_buffer: *UniformBuffer = @alignCast(@ptrCast(buffer.ptr));
    _g.uniform_buffer_pool.destroy(true_buffer) catch undefined;
}

fn createShaderContext() !public.ShaderContext {
    var new: bool = false;
    const buffer = _g.shader_context_pool.create(&new);

    if (new) {
        buffer.* = .init();
    } else {
        buffer.clear();
    }

    return .{ .ptr = buffer, .vtable = &shader_context_vt };
}
fn destroyShaderContext(buffer: public.ShaderContext) void {
    const true_buffer: *ShaderContext = @alignCast(@ptrCast(buffer.ptr));
    _g.shader_context_pool.destroy(true_buffer) catch undefined;
}

const MAX_UNIFORM_BUFFERS = 4 * 1024;
const MAX_SHADER_CONTEXT = 128;

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "ShaderSystem",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            _g.shader_def_map = .{};
            _g.shader_pool = try ShaderPool.init(_allocator, MAX_SHADER_INSTANCE);

            _g.program_cache = .{};
            _g.program_counter = try ProgramCounter.init(MAX_PROGRAMS);

            _g.function_node_iface_map = .{};
            _g.output_node_iface_map = .{};

            _g.exported_node_iface_map = .{};
            _g.exported_map = .{};

            _g.node_str_itern = StringIntern.init(_allocator);

            _g.system_to_idx = .{};
            _g.system_counter = cetech1.heap.AtomicInt.init(0);

            _g.uniform_buffer_pool = try UniformBufferPool.init(_allocator, MAX_UNIFORM_BUFFERS);
            _g.shader_context_pool = try ShaderContextPool.init(_allocator, MAX_SHADER_CONTEXT);

            // Shaderlib from BGFX
            try api.addShaderDefiniton("shaderlib", .{
                .common_block = @embedFile("embed/shaderlib.sh"),
            });

            try basic_nodes.init(&api);

            // TODO: TMP SHIT
            if (_gpu.getBackendType() != .noop) {}

            // Node fce
            try api.addShaderDefiniton("node_fce1", .{
                .function =
                \\output.result = a * b;
                ,
                .graph_node = .{
                    .name = "node_fce1",
                    .display_name = "Node FCE",
                    .category = "FOO",

                    .inputs = &.{
                        .{ .name = "a", .display_name = "A" },
                        .{ .name = "b", .display_name = "B", .type = .vec4 },
                    },
                    .outputs = &.{
                        .{ .name = "result", .display_name = "Result", .type_of = "a" },
                    },
                },
            });

            // Depth system
            try api.addSystemDefiniton("depth_system", .{});

            // Time system
            try api.addSystemDefiniton("time_system", .{
                .imports = &.{
                    .{ .name = "time", .type = .vec4 },
                },
            });

            // Viewer system
            try api.addSystemDefiniton(
                "viewer_system",
                .{
                    .common_block =
                    \\vec4 load_view_rect() {
                    \\  return u_viewRect;
                    \\}
                    \\
                    \\vec4 load_view_texel() {
                    \\  return u_viewTexel;
                    \\}
                    \\
                    \\mat4 load_view() {
                    \\  return u_view;
                    \\}
                    \\
                    \\mat4 load_inv_view() {
                    \\  return u_invView;
                    \\}
                    \\
                    \\mat4 load_proj() {
                    \\  return u_proj;
                    \\}
                    \\
                    \\mat4 load_inv_proj() {
                    \\  return u_invProj;
                    \\}
                    \\
                    \\mat4 load_view_proj() {
                    \\  return u_viewProj;
                    \\}
                    \\
                    \\mat4 load_inv_view_proj() {
                    \\  return u_invViewProj;
                    \\}
                    ,
                },
            );

            // Foo output node
            try api.addShaderDefiniton("node_foo_output", .{
                .state = public.default_state | gpu.StateFlags_DepthTestEqual,
                .graph_node = .{
                    .name = "node_foo_output",
                    .display_name = "Foo Output",
                    .category = "FOO",

                    .inputs = &.{
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = public.TranspileStages.Vertex },
                        .{ .name = "color", .display_name = "Color", .type = .vec4, .stage = public.TranspileStages.Fragment, .contexts = &.{ "default", "color" } },
                    },
                },

                .vertex_block = .{
                    .imports = &.{
                        .position,
                        .color0,
                    },
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                    },
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\  ct_graph_eval(graph, input);
                    \\
                    \\  output.position = graph.position;
                    \\  output.color0 = a_color0;
                    ,
                },
                .fragment_block = .{
                    .exports = &.{
                        .{ .name = "foo", .type = .vec4, .to_node = true },
                    },
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\
                    \\  graph.foo = vec4(0,1,0,1);
                    \\
                    \\  ct_graph_eval(graph, input);
                    \\
                    \\  output.color0 = graph.color;
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{ "time_system", "viewer_system" } },
                            },
                        },
                        .{
                            .name = "depth",
                            .variations = &.{
                                .{
                                    .systems = &.{ "time_system", "viewer_system", "depth_system" },
                                    .state = gpu.StateFlags_WriteZ | gpu.StateFlags_CullCcw | gpu.StateFlags_DepthTestLess,
                                },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .layer = "color", .config = "default" },
                                .{ .layer = "depth", .config = "depth" },
                            },
                        },
                    },
                },
            });
        }

        pub fn shutdown() !void {
            _g.shader_def_map.deinit(_allocator);
            _g.shader_pool.deinit();
            _g.program_cache.deinit(_allocator);
            _g.program_counter.deinit();

            for (_g.function_node_iface_map.values()) |iface| {
                try _apidb.implOrRemove(module_name, graphvm.NodeI, iface, false);
                _allocator.destroy(iface);
            }
            _g.function_node_iface_map.deinit(_allocator);

            for (_g.output_node_iface_map.values()) |iface| {
                try _apidb.implOrRemove(module_name, graphvm.NodeI, iface, false);
                _allocator.destroy(iface);
            }
            _g.output_node_iface_map.deinit(_allocator);

            for (_g.exported_node_iface_map.values()) |iface| {
                try _apidb.implOrRemove(module_name, graphvm.NodeI, iface, false);
                _allocator.destroy(iface);
            }
            _g.exported_node_iface_map.deinit(_allocator);

            _g.exported_map.deinit(_allocator);

            _g.node_str_itern.deinit();

            for (_g.system_to_idx.values()) |idx| {
                var system = _g.system_pool[idx];
                system.deinit(_allocator);
            }

            _g.system_to_idx.deinit(_allocator);

            for (_g.uniform_buffer_pool.mem.items[0.._g.uniform_buffer_pool.alocated_items.raw]) |*obj| {
                obj.deinit();
            }
            _g.uniform_buffer_pool.deinit();

            for (_g.shader_context_pool.mem.items[0.._g.shader_context_pool.alocated_items.raw]) |*obj| {
                obj.deinit();
            }
            _g.shader_context_pool.deinit();
        }
    },
);

inline fn semanticToText(semantic: VariableSemantic) []const u8 {
    return switch (semantic) {
        .position => "POSITION",
        .normal => "NORMAL",
        .tangent => "TANGENT",
        .bitangent => "BITANGENT",
        .color0 => "COLOR0",
        .color1 => "COLOR1",
        .color2 => "COLOR2",
        .color3 => "COLOR3",
        .indices => "INDICES",
        .weight => "WEIGHT",
        .texcoord0 => "TEXCOORD0",
        .texcoord1 => "TEXCOORD1",
        .texcoord2 => "TEXCOORD2",
        .texcoord3 => "TEXCOORD3",
        .texcoord4 => "TEXCOORD4",
        .texcoord5 => "TEXCOORD5",
        .texcoord6 => "TEXCOORD6",
        .texcoord7 => "TEXCOORD7",
    };
}

inline fn vertexInputsToVariableName(semantic: public.DefImportVariableType) []const u8 {
    return switch (semantic) {
        .position => "a_position",
        .normal => "a_normal",
        .tangent => "a_tangent",
        .bitangent => "a_bitangent",
        .color0 => "a_color0",
        .color1 => "a_color1",
        .color2 => "a_color2",
        .color3 => "a_color3",
        .indices => "a_indices",
        .weight => "a_weight",
        .texcoord0 => "a_texcoord0",
        .texcoord1 => "a_texcoord1",
        .texcoord2 => "a_texcoord2",
        .texcoord3 => "a_texcoord3",
        .texcoord4 => "a_texcoord4",
        .texcoord5 => "a_texcoord5",
        .texcoord6 => "a_texcoord6",
        .texcoord7 => "a_texcoord7",
    };
}

inline fn vertexInputsToSemanticName(semantic: public.DefImportVariableType) []const u8 {
    return switch (semantic) {
        .position => "POSITION",
        .normal => "NORMAL",
        .tangent => "TANGENT",
        .bitangent => "BITANGENT",
        .color0 => "COLOR0",
        .color1 => "COLOR1",
        .color2 => "COLOR2",
        .color3 => "COLOR3",
        .indices => "INDICES",
        .weight => "WEIGHT",
        .texcoord0 => "TEXCOORD0",
        .texcoord1 => "TEXCOORD1",
        .texcoord2 => "TEXCOORD2",
        .texcoord3 => "TEXCOORD3",
        .texcoord4 => "TEXCOORD4",
        .texcoord5 => "TEXCOORD5",
        .texcoord6 => "TEXCOORD6",
        .texcoord7 => "TEXCOORD7",
    };
}

inline fn vertexInputsToVarTypeName(semantic: public.DefImportVariableType) []const u8 {
    return switch (semantic) {
        .position => "vec3",
        .normal => "vec3",
        .tangent => "vec3",
        .bitangent => "vec3",
        .color0 => "vec4",
        .color1 => "vec4",
        .color2 => "vec4",
        .color3 => "vec4",
        .indices => "uvec4",
        .weight => "vec3",
        .texcoord0 => "vec2",
        .texcoord1 => "vec2",
        .texcoord2 => "vec2",
        .texcoord3 => "vec2",
        .texcoord4 => "vec2",
        .texcoord5 => "vec2",
        .texcoord6 => "vec2",
        .texcoord7 => "vec2",
    };
}

//
// GraphVM value type
//
const gpu_shader_value_type_i = graphvm.GraphValueTypeI.implement(
    public.ShaderInstance,
    .{
        .name = "GPU shader",
        .type_hash = public.PinTypes.GPU_SHADER,
        .cdb_type_hash = public.GPUShaderInstanceCDB.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = public.GPUShaderInstanceCDB.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintZ(allocator, "{any}", .{std.mem.bytesToValue(u32, value)});
        }
    },
);

const gpu_vec4_value_type_i = graphvm.GraphValueTypeI.implement(
    public.GpuValue,
    .{
        .name = "GPU vec4",
        .type_hash = public.PinTypes.GPU_VEC4,
        .cdb_type_hash = public.Vec4f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            const v = public.Vec4f.f.toSlice(_cdb, obj);
            const s = try std.fmt.allocPrint(allocator, "vec4({d},{d},{d},{d})", .{ v[0], v[1], v[2], v[3] });
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            gv.str = s;
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return cetech1.strId64(value).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            return std.fmt.allocPrintZ(allocator, "{s}", .{gv.str});
        }
    },
);

const gpu_vec2_value_type_i = graphvm.GraphValueTypeI.implement(
    public.GpuValue,
    .{
        .name = "GPU vec2",
        .type_hash = public.PinTypes.GPU_VEC2,
        .cdb_type_hash = public.Vec2f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            const v = public.Vec2f.f.toSlice(_cdb, obj);
            const s = try std.fmt.allocPrint(allocator, "vec2({d},{d})", .{ v[0], v[1] });
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            gv.str = s;
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return cetech1.strId64(value).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            return std.fmt.allocPrintZ(allocator, "{s}", .{gv.str});
        }
    },
);

const gpu_vec3_value_type_i = graphvm.GraphValueTypeI.implement(
    public.GpuValue,
    .{
        .name = "GPU vec3",
        .type_hash = public.PinTypes.GPU_VEC3,
        .cdb_type_hash = public.Vec3f.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            const v = public.Vec3f.f.toSlice(_cdb, obj);
            const s = try std.fmt.allocPrint(allocator, "vec3({d},{d},{d})", .{ v[0], v[1], v[2] });
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            gv.str = s;
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return cetech1.strId64(value).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            return std.fmt.allocPrintZ(allocator, "{s}", .{gv.str});
        }
    },
);

const gpu_float_value_type_i = graphvm.GraphValueTypeI.implement(
    public.GpuValue,
    .{
        .name = "GPU float",
        .type_hash = public.PinTypes.GPU_FLOAT,
        .cdb_type_hash = public.f32Type.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            const r = public.f32Type.read(_cdb, obj).?;
            const v = public.f32Type.readValue(f32, _cdb, r, .value);
            const s = try std.fmt.allocPrint(allocator, "{d}", .{v});
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            gv.str = s;
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return cetech1.strId64(value).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            const gv = std.mem.bytesAsValue(public.GpuValue, value);
            return std.fmt.allocPrintZ(allocator, "{s}", .{gv.str});
        }
    },
);

//
// GraphVM shader nodes
//
const CreateShaderState = struct {
    shader: ?public.ShaderInstance = null,
};

const gpu_vertex_color_node_i = graphvm.NodeI.implement(
    .{
        .name = "Vertex color",
        .type_name = "gpu_vertex_color",
        .category = "Shader",
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Color", graphvm.NodePin.pinHash("color", true), public.PinTypes.GPU_VEC4, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins; // autofix
            _ = in_pins; // autofix
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = self; // autofix
            _ = stage; // autofix
            _ = args; // autofix
            _ = in_pins; // autofix
            const real_state = std.mem.bytesAsValue(public.GpuTranspileState, state);
            _ = real_state; // autofix

            const val = public.GpuValue{ .str = "input.color0" };
            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

const gpu_vertex_position_node_i = graphvm.NodeI.implement(
    .{
        .name = "Vertex position",
        .type_name = "gpu_vertex_position",
        .category = "Shader",
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", true), public.PinTypes.GPU_VEC3, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins; // autofix
            _ = in_pins; // autofix
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = self; // autofix
            _ = stage; // autofix
            _ = args; // autofix
            _ = in_pins; // autofix
            const real_state = std.mem.bytesAsValue(public.GpuTranspileState, state);
            _ = real_state; // autofix

            const val = public.GpuValue{ .str = "input.a_position" };
            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

const gpu_time_node_i = graphvm.NodeI.implement(
    .{
        .name = "Time",
        .type_name = "gpu_time",
        .category = "Shader",
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Time", graphvm.NodePin.pinHash("time", true), public.PinTypes.GPU_FLOAT, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins; // autofix
            _ = in_pins; // autofix
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = self; // autofix
            _ = stage; // autofix
            _ = args; // autofix
            _ = in_pins; // autofix
            const real_state = std.mem.bytesAsValue(public.GpuTranspileState, state);
            _ = real_state; // autofix

            const val = public.GpuValue{ .str = "load_time().x" };
            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

const gpu_mul_mvp_node_i = graphvm.NodeI.implement(
    .{
        .name = "Mul MVP",
        .type_name = "gpu_mul_mvp",
        .category = "Shader/Math",
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", false), public.PinTypes.GPU_VEC3, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", true), public.PinTypes.GPU_VEC4, null),
                }),
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins; // autofix
            _ = in_pins; // autofix
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = self; // autofix
            _ = state; // autofix
            _ = stage; // autofix
            _, const position = in_pins.read(public.GpuValue, 0) orelse .{ 0, public.GpuValue{ .str = "a_position" } };

            const val = public.GpuValue{
                .str = try std.fmt.allocPrint(args.allocator, "mul(u_modelViewProj, vec4({s}, 1.0))", .{position.str}),
            };

            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

const gpu_construct_node_i = graphvm.NodeI.implement(
    .{
        .name = "Construct",
        .type_name = "gpu_construct",
        .category = "Shader",
        .settings_type = public.ConstructNodeSettings.type_hash,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = graph_obj; // autofix

            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;

            var output_type: cetech1.StrId32 = .{};
            var in_pins: []graphvm.NodePin = undefined;

            if (graphvm.NodeType.readSubObj(_cdb, node_obj_r, .settings)) |settings| {
                const settings_r = public.ConstructNodeSettings.read(_cdb, settings).?;

                const type_str = public.ConstructNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";
                const type_enum = std.meta.stringToEnum(public.ConstructNodeResultType, type_str).?;

                in_pins = blk: switch (type_enum) {
                    .vec2 => break :blk try allocator.dupe(graphvm.NodePin, &.{
                        graphvm.NodePin.init("X", graphvm.NodePin.pinHash("x", false), public.PinTypes.GPU_FLOAT, null),
                        graphvm.NodePin.init("Y", graphvm.NodePin.pinHash("y", false), public.PinTypes.GPU_FLOAT, null),
                    }),
                    .vec3 => break :blk try allocator.dupe(graphvm.NodePin, &.{
                        graphvm.NodePin.init("X", graphvm.NodePin.pinHash("x", false), public.PinTypes.GPU_FLOAT, null),
                        graphvm.NodePin.init("Y", graphvm.NodePin.pinHash("y", false), public.PinTypes.GPU_FLOAT, null),
                        graphvm.NodePin.init("Z", graphvm.NodePin.pinHash("z", false), public.PinTypes.GPU_FLOAT, null),
                    }),
                    .vec4 => break :blk try allocator.dupe(graphvm.NodePin, &.{
                        graphvm.NodePin.init("X", graphvm.NodePin.pinHash("x", false), public.PinTypes.GPU_FLOAT, null),
                        graphvm.NodePin.init("Y", graphvm.NodePin.pinHash("y", false), public.PinTypes.GPU_FLOAT, null),
                        graphvm.NodePin.init("Z", graphvm.NodePin.pinHash("z", false), public.PinTypes.GPU_FLOAT, null),
                        graphvm.NodePin.init("W", graphvm.NodePin.pinHash("w", false), public.PinTypes.GPU_FLOAT, null),
                    }),
                };

                output_type = switch (type_enum) {
                    .vec2 => public.PinTypes.GPU_VEC2,
                    .vec3 => public.PinTypes.GPU_VEC3,
                    .vec4 => public.PinTypes.GPU_VEC4,
                };
            }

            return .{
                .in = in_pins,
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("output", graphvm.NodePin.pinHash("output", true), output_type, null),
                }),
            };
        }

        pub fn title(
            self: *const graphvm.NodeI,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = self; // autofix
            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;
            _ = node_obj_r; // autofix
            const header_label = "Make";

            return std.fmt.allocPrintZ(allocator, header_label, .{});
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = self; // autofix
            _ = stage; // autofix
            const real_state = std.mem.bytesAsValue(public.GpuTranspileState, state);
            _ = real_state; // autofix

            const settings_r = public.ConstructNodeSettings.read(_cdb, args.settings.?).?;

            const type_str = public.ConstructNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";
            const type_enum = std.meta.stringToEnum(public.ConstructNodeResultType, type_str).?;

            const str = str_blk: switch (type_enum) {
                .vec2 => {
                    _, const x = in_pins.read(public.GpuValue, 0) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    _, const y = in_pins.read(public.GpuValue, 1) orelse .{ 0, public.GpuValue{ .str = "0" } };

                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec2({s},{s})", .{ x.str, y.str });
                },
                .vec3 => {
                    _, const x = in_pins.read(public.GpuValue, 0) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    _, const y = in_pins.read(public.GpuValue, 1) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    _, const z = in_pins.read(public.GpuValue, 2) orelse .{ 0, public.GpuValue{ .str = "0" } };

                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec3({s},{s},{s})", .{ x.str, y.str, z.str });
                },
                .vec4 => {
                    _, const x = in_pins.read(public.GpuValue, 0) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    _, const y = in_pins.read(public.GpuValue, 1) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    _, const z = in_pins.read(public.GpuValue, 2) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    _, const w = in_pins.read(public.GpuValue, 3) orelse .{ 0, public.GpuValue{ .str = "0" } };
                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec4({s},{s},{s},{s})", .{ x.str, y.str, z.str, w.str });
                },
            };

            const val = public.GpuValue{ .str = str };
            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins; // autofix
            _ = in_pins; // autofix
        }
    },
);

const gpu_const_node_i = graphvm.NodeI.implement(
    .{
        .name = "Const",
        .type_name = "gpu_const",
        .category = "Shader",
        .settings_type = public.ConstNodeSettings.type_hash,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = graph_obj; // autofix

            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;
            var output_type: cetech1.StrId32 = .{};
            if (graphvm.NodeType.readSubObj(_cdb, node_obj_r, .settings)) |settings| {
                const settings_r = public.ConstructNodeSettings.read(_cdb, settings).?;

                const type_str = public.ConstructNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";
                const type_enum = std.meta.stringToEnum(public.ConstNodeResultType, type_str).?;

                output_type = switch (type_enum) {
                    .float => public.PinTypes.GPU_FLOAT,
                    .vec2 => public.PinTypes.GPU_VEC2,
                    .vec3 => public.PinTypes.GPU_VEC3,
                    .vec4 => public.PinTypes.GPU_VEC4,
                    .color => public.PinTypes.GPU_VEC4,
                };
            }

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("output", graphvm.NodePin.pinHash("output", true), output_type, null),
                }),
            };
        }

        pub fn title(
            self: *const graphvm.NodeI,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = self; // autofix
            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;
            _ = node_obj_r; // autofix
            const header_label = "GPU const";

            return std.fmt.allocPrintZ(allocator, header_label, .{});
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = in_pins; // autofix
            _ = self; // autofix
            _ = stage; // autofix
            const real_state = std.mem.bytesAsValue(public.GpuTranspileState, state);
            _ = real_state; // autofix

            const settings_r = public.ConstNodeSettings.read(_cdb, args.settings.?).?;

            const type_str = public.ConstNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";
            const type_enum = std.meta.stringToEnum(public.ConstNodeResultType, type_str).?;

            const value = public.ConstNodeSettings.readSubObj(_cdb, settings_r, .value);

            const str = str_blk: switch (type_enum) {
                .float => {
                    const v: f32 = blk: {
                        if (value) |v| {
                            const v_r = cdb_types.f32Type.read(_cdb, v) orelse break :blk 0.0;
                            break :blk cdb_types.f32Type.readValue(f32, _cdb, v_r, .value);
                        }
                        break :blk 0.0;
                    };

                    break :str_blk try std.fmt.allocPrint(args.allocator, "{d}", .{v});
                },

                .vec2 => {
                    const v = if (value) |v| cdb_types.Vec2f.f.toSlice(_cdb, v) else .{ 0, 0 };
                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec2({d},{d})", .{ v[0], v[1] });
                },
                .vec3 => {
                    const v = if (value) |v| cdb_types.Vec3f.f.toSlice(_cdb, v) else .{ 0, 0, 0 };
                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec2({d},{d},{d})", .{ v[0], v[1], v[2] });
                },
                .vec4 => {
                    const v = if (value) |v| cdb_types.Vec4f.f.toSlice(_cdb, v) else .{ 0, 0, 0, 0 };
                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec4({d},{d},{d},{d})", .{ v[0], v[1], v[2], v[3] });
                },
                .color => {
                    const v = if (value) |v| cdb_types.Color4f.f.toSlice(_cdb, v) else .{ 0, 0, 0, 1 };
                    break :str_blk try std.fmt.allocPrint(args.allocator, "vec4({d},{d},{d},{d})", .{ v[0], v[1], v[2], v[3] });
                },
            };

            const val = public.GpuValue{ .str = str };
            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = args; // autofix
            _ = out_pins; // autofix
            _ = in_pins; // autofix
        }
    },
);

const UniformNodeState = struct {
    vec4: [4]f32 = .{ 0, 0, 0, 0 },
};

const gpu_uniform_node_i = graphvm.NodeI.implement(
    .{
        .name = "Uniform",
        .type_name = "gpu_uniform",
        .category = "Shader",
        .settings_type = public.UniformNodeSettings.type_hash,
        .transpile_border = true,
    },
    UniformNodeState,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = graph_obj; // autofix

            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;
            var in_type: cetech1.StrId32 = .{};
            var output_type: cetech1.StrId32 = .{};

            if (graphvm.NodeType.readSubObj(_cdb, node_obj_r, .settings)) |settings| {
                const settings_r = public.UniformNodeSettings.read(_cdb, settings).?;

                const type_str = public.UniformNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";
                const type_enum = std.meta.stringToEnum(public.UniformNodeResultType, type_str).?;

                in_type = switch (type_enum) {
                    .vec4 => graphvm.PinTypes.VEC4F,
                    .color => graphvm.PinTypes.COLOR4F,
                };

                output_type = switch (type_enum) {
                    .vec4 => public.PinTypes.GPU_VEC4,
                    .color => public.PinTypes.GPU_VEC4,
                };
            }

            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("value", graphvm.NodePin.pinHash("value", false), in_type, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("value", graphvm.NodePin.pinHash("value", true), output_type, null),
                }),
            };
        }

        pub fn getOutputPins(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = self; // autofix
            _ = graph_obj; // autofix

            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;
            var output_type: cetech1.StrId32 = .{};
            if (graphvm.NodeType.readSubObj(_cdb, node_obj_r, .settings)) |settings| {
                const settings_r = public.UniformNodeSettings.read(_cdb, settings).?;

                const type_str = public.UniformNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";
                const type_enum = std.meta.stringToEnum(public.UniformNodeResultType, type_str).?;

                output_type = switch (type_enum) {
                    .vec4 => public.PinTypes.GPU_VEC4,
                    .color => public.PinTypes.GPU_VEC4,
                };
            }

            return allocator.dupe(graphvm.NodePin, &.{
                graphvm.NodePin.init("value", graphvm.NodePin.pinHash("value", true), output_type, null),
            });
        }

        pub fn title(
            self: *const graphvm.NodeI,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = self; // autofix
            const node_obj_r = graphvm.NodeType.read(_cdb, node_obj).?;
            _ = node_obj_r; // autofix
            const header_label = "Uniform";

            return std.fmt.allocPrintZ(allocator, header_label, .{});
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
            const real_state: *UniformNodeState = @alignCast(@ptrCast(state));
            real_state.* = .{};
        }

        pub fn transpile(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, state: []u8, stage: ?cetech1.StrId32, context: ?[]const u8, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = context; // autofix
            _ = self; // autofix
            _ = in_pins; // autofix
            _ = stage; // autofix
            const real_state = public.GpuTranspileState.fromBytes(state);

            const settings_r = public.UniformNodeSettings.read(_cdb, args.settings.?).?;

            const name = public.UniformNodeSettings.readStr(_cdb, settings_r, .name) orelse "INVALLID";
            const str = try std.fmt.allocPrint(args.allocator, "{s}", .{name});

            const type_str = public.UniformNodeSettings.readStr(_cdb, settings_r, .result_type) orelse "vec4";

            const type_enum = if (std.mem.eql(u8, type_str, "color")) .vec4 else std.meta.stringToEnum(public.DefMainImportVariableType, type_str).?;

            try real_state.imports.put(real_state.allocator, name, .{ .name = name, .type = type_enum });

            const val = public.GpuValue{ .str = str };
            try out_pins.writeTyped(public.GpuValue, 0, cetech1.strId64(val.str).id, val);
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = self; // autofix
            _ = out_pins; // autofix
            const cs_state: *CreateShaderState = @alignCast(@ptrCast(args.transpiler_node_state.?));

            const settings_r = public.UniformNodeSettings.read(_cdb, args.settings.?).?;

            const name = public.UniformNodeSettings.readStr(_cdb, settings_r, .name) orelse "INVALLID";

            const real_state = args.getState(UniformNodeState).?;

            _, const value = in_pins.read([4]f32, 0) orelse return;
            real_state.vec4 = value;

            if (cs_state.shader) |*shader| {
                try shader.uniforms.?.set(cetech1.strId32(name), real_state.vec4);
            }
            //log.debug("TS: {any}", .{args.transpiler_node_state});
        }
    },
);

const construct_node_result_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = public.ConstructNodeSettings.read(_cdb, obj).?;
        const type_str = public.ConstructNodeSettings.readStr(_cdb, r, .result_type) orelse "vec4";
        var type_enum = std.meta.stringToEnum(public.ConstructNodeResultType, type_str).?;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = public.ConstructNodeSettings.write(_cdb, obj).?;
            const str = switch (type_enum) {
                .vec2 => "vec2",
                .vec3 => "vec3",
                .vec4 => "vec4",
            };
            try public.ConstructNodeSettings.setStr(_cdb, w, .result_type, str);
            try public.ConstructNodeSettings.commit(_cdb, w);
        }
    }
});

const const_node_result_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = public.ConstNodeSettings.read(_cdb, obj).?;
        const type_str = public.ConstNodeSettings.readStr(_cdb, r, .result_type) orelse "vec4";
        var type_enum = std.meta.stringToEnum(public.ConstNodeResultType, type_str).?;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = public.ConstNodeSettings.write(_cdb, obj).?;

            const db = _cdb.getDbFromObj(w);
            const value_obj = switch (type_enum) {
                .float => try cdb_types.f32Type.createObject(_cdb, db),
                .vec2 => try cdb_types.Vec2f.createObject(_cdb, db),
                .vec3 => try cdb_types.Vec3f.createObject(_cdb, db),
                .vec4 => try cdb_types.Vec4f.createObject(_cdb, db),
                .color => try cdb_types.Color4f.createObject(_cdb, db),
            };

            const value_w = _cdb.writeObj(value_obj).?;
            try public.ConstNodeSettings.setSubObj(_cdb, w, .value, value_w);
            try _cdb.writeCommit(value_w);

            try public.ConstNodeSettings.setStr(_cdb, w, .result_type, @tagName(type_enum));
            try public.ConstNodeSettings.commit(_cdb, w);
        }
    }
});

const uniform_node_result_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = public.UniformNodeSettings.read(_cdb, obj).?;
        const type_str = public.UniformNodeSettings.readStr(_cdb, r, .result_type) orelse "vec4";
        var type_enum = std.meta.stringToEnum(public.UniformNodeResultType, type_str).?;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = public.UniformNodeSettings.write(_cdb, obj).?;
            const str = @tagName(type_enum);
            try public.UniformNodeSettings.setStr(_cdb, w, .result_type, str);
            try public.UniformNodeSettings.commit(_cdb, w);
        }
    }
});

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // GPUShaderCDB
        {
            const type_idx = try _cdb.addType(
                db,
                public.GPUShaderInstanceCDB.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.GPUShaderInstanceCDB.propIdx(.handle),
                        .name = "handle",
                        .type = cdb.PropType.U32,
                    },
                },
            );
            _ = type_idx; // autofix
        }

        // value f32
        {
            _ = try _cdb.addType(
                db,
                public.f32Type.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.f32Type.propIdx(.value), .name = "value", .type = .F32 },
                },
            );
        }

        // value vec2
        {
            _ = try _cdb.addType(
                db,
                public.Vec2f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec2f.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec2f.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                },
            );
        }

        // value vec3
        {
            _ = try _cdb.addType(
                db,
                public.Vec3f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec3f.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3f.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec3f.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                },
            );
        }

        // value vec4
        {
            _ = try _cdb.addType(
                db,
                public.Vec4f.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.Vec4f.propIdx(.X), .name = "x", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.Y), .name = "y", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.Z), .name = "z", .type = cdb.PropType.F32 },
                    .{ .prop_idx = public.Vec4f.propIdx(.W), .name = "w", .type = cdb.PropType.F32 },
                },
            );
        }

        // ConstructNodeSettings
        {
            const type_idx = try _cdb.addType(
                db,
                public.ConstructNodeSettings.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.ConstructNodeSettings.propIdx(.result_type),
                        .name = "result_type",
                        .type = cdb.PropType.STR,
                    },
                },
            );
            _ = type_idx; // autofix

            try public.ConstructNodeSettings.addPropertyAspect(
                editor_inspector.UiPropertyAspect,
                _cdb,
                db,
                .result_type,
                _g.make_node_result_type_aspec,
            );
        }

        // ConstNodeSettings
        {
            const type_idx = try _cdb.addType(
                db,
                public.ConstNodeSettings.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.ConstNodeSettings.propIdx(.result_type),
                        .name = "result_type",
                        .type = .STR,
                    },
                    .{
                        .prop_idx = public.ConstNodeSettings.propIdx(.value),
                        .name = "value",
                        .type = .SUBOBJECT,
                    },
                },
            );
            _ = type_idx; // autofix

            try public.ConstNodeSettings.addPropertyAspect(
                editor_inspector.UiPropertyAspect,
                _cdb,
                db,
                .result_type,
                _g.const_node_result_type_aspec,
            );
        }

        // UniformNodeSettings
        {
            const type_idx = try _cdb.addType(
                db,
                public.UniformNodeSettings.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.UniformNodeSettings.propIdx(.name),
                        .name = "name",
                        .type = cdb.PropType.STR,
                    },
                    .{
                        .prop_idx = public.UniformNodeSettings.propIdx(.result_type),
                        .name = "result_type",
                        .type = cdb.PropType.STR,
                    },
                },
            );
            _ = type_idx; // autofix

            try public.UniformNodeSettings.addPropertyAspect(
                editor_inspector.UiPropertyAspect,
                _cdb,
                db,
                .result_type,
                _g.uniform_node_result_type_aspec,
            );
        }
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
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;
    _graphvm = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;

    // register api
    try apidb.setOrRemoveZigApi(module_name, public.ShaderSystemAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_vertex_color_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_vertex_position_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_mul_mvp_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_time_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_construct_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_uniform_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &gpu_const_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_shader_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_vec2_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_vec3_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_vec4_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_float_value_type_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.make_node_result_type_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_construct_node_result_type_aspec", construct_node_result_type_aspec);
    _g.uniform_node_result_type_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_uniform_node_result_type_aspec", uniform_node_result_type_aspec);
    _g.const_node_result_type_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_const_node_result_type_aspec", const_node_result_type_aspec);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_shader_system(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
