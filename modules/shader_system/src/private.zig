const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math;

const public = @import("shader_system.zig");

const graphvm = @import("graphvm");

const module_name = .transform;

const MAX_SHADER_INSTANCE = 1_000; // =D very naive

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
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _gpu: *const gpu.GpuApi = undefined;

const ShaderDefMap = std.AutoArrayHashMap(strid.StrId32, public.ShaderDefinition);
const ShaderInstancePool = cetech1.mem.VirtualPool(ShaderInstance);

const ShaderInstance = struct {
    prg: gpu.ProgramHandle,

    state: u64,
    rgba: u32,
};

// Global state that can surive hot-reload
const G = struct {
    shader_def_map: ShaderDefMap = undefined,
    shader_instance_pool: ShaderInstancePool = undefined,

    prg: ?public.ShaderInstance = null, // TODO: TEMP SHIT
};
var _g: *G = undefined;

const api = public.ShaderSystemAPI{
    .addShaderDefiniton = addShaderDefiniton,
    .compileShader = compileProgram,
    .getGpuProgram = getGpuProgram,
    .getState = getState,
    .getRGBAState = getRGBAState,
};

fn addShaderDefiniton(name: []const u8, definition: public.ShaderDefinition) !void {
    try _g.shader_def_map.put(strid.strId32(name), definition);
}

// This is included for all shaders for simplicity
const bgfx_shader = @embedFile("embed/bgfx_shader.sh");
const bgfx_compute = @embedFile("embed/bgfx_compute.sh");

fn compileProgram(allocator: std.mem.Allocator, definitons: []const strid.StrId32) !?public.ShaderInstance {
    //TODO: BRAINDUMP SHIT DETECTED
    //TODO: merge defs

    var var_def = std.ArrayList(u8).init(allocator);
    defer var_def.deinit();

    var vs_imports = std.ArrayList(u8).init(allocator);
    defer vs_imports.deinit();

    var vs_exports = std.ArrayList(u8).init(allocator);
    defer vs_exports.deinit();

    var fs_imports = std.ArrayList(u8).init(allocator);
    defer fs_imports.deinit();

    var fs_blocks = std.ArrayList(u8).init(allocator);
    defer fs_blocks.deinit();

    var vs_blocks = std.ArrayList(u8).init(allocator);
    defer vs_blocks.deinit();

    var cmn_blocks = std.ArrayList(u8).init(allocator);
    defer cmn_blocks.deinit();

    var vs_imports_set = cetech1.mem.Set(public.DefImportVariableType).init(allocator);
    defer vs_imports_set.deinit();

    var vs_export_set = cetech1.mem.Set([]const u8).init(allocator);
    defer vs_export_set.deinit();

    var state: u64 = 0;
    var rgba: u32 = 0;

    for (definitons) |def_name| {
        const shader_def = _g.shader_def_map.get(def_name) orelse return null;

        state |= shader_def.state;
        rgba |= shader_def.rgba;

        if (shader_def.common_block) |cb| {
            try cmn_blocks.appendSlice(cb);
            try cmn_blocks.appendSlice("\n");
        }

        if (shader_def.vertex_block) |vb| {
            for (vb.imports, 0..) |value, idx| {
                if (!try vs_imports_set.add(value)) continue;

                try vs_imports.appendSlice(vertexInputsToVariableName(value));

                const line = try std.fmt.allocPrint(
                    allocator,
                    "{s} {s}  :   {s};\n",
                    .{
                        vertexInputsToVarTypeName(value),
                        vertexInputsToVariableName(value),
                        vertexInputsToSemanticName(value),
                    },
                );
                defer allocator.free(line);
                try var_def.appendSlice(line);

                if (idx != vb.imports.len - 1) {
                    try vs_imports.appendSlice(", ");
                }
            }
            try var_def.appendSlice("\n");

            for (vb.exports, 0..) |value, idx| {
                if (!try vs_export_set.add(value.name)) continue;

                const line = try std.fmt.allocPrint(
                    allocator,
                    "{s} {s}  :   {s};\n",
                    .{
                        @tagName(value.type),
                        value.name,
                        semanticToText(value.semantic),
                    },
                );
                defer allocator.free(line);
                try var_def.appendSlice(line);

                try vs_exports.appendSlice(value.name);
                try fs_imports.appendSlice(value.name);

                if (idx != vb.exports.len - 1) {
                    try vs_exports.appendSlice(", ");
                    try fs_imports.appendSlice(", ");
                }
            }

            try vs_blocks.appendSlice(vb.code);
            try vs_blocks.appendSlice("\n");
        }

        if (shader_def.fragment_block) |fb| {
            try fs_blocks.appendSlice(fb.code);
            try fs_blocks.appendSlice("\n");
        }
    }

    //
    // Compile vs shader
    //
    var vs_shader_options = _gpu.createDefaultOptionsForRenderer(_gpu.getBackendType());
    vs_shader_options.shaderType = .vertex;

    const vs_source = try std.fmt.allocPrint(
        allocator,
        \\$input {s}
        \\$output {s}
        \\
        \\// bgfx_shader.sh
        \\{s}
        \\
        \\// Common block
        \\{s}
        \\
        \\void main() {{
        \\{s}
        \\}}
    ,
        .{
            vs_imports.items,
            vs_exports.items,
            bgfx_shader,
            if (cmn_blocks.items.len != 0) cmn_blocks.items else "",
            if (vs_blocks.items.len != 0) vs_blocks.items else "",
        },
    );
    defer allocator.free(vs_source);

    const vs_shader = try _gpu.compileShader(allocator, var_def.items, vs_source, vs_shader_options);
    defer allocator.free(vs_shader);

    //
    // Compile fs shader
    //
    var fs_shader_options = _gpu.createDefaultOptionsForRenderer(_gpu.getBackendType());
    fs_shader_options.shaderType = .fragment;

    const fs_source = try std.fmt.allocPrint(
        allocator,
        \\$input {s}
        \\
        \\// bgfx_shader.sh
        \\{s}
        \\
        \\// Common block
        \\{s}
        \\
        \\void main() {{
        \\{s}
        \\}}
    ,
        .{
            fs_imports.items,
            bgfx_shader,
            if (cmn_blocks.items.len != 0) cmn_blocks.items else "",
            if (fs_blocks.items.len != 0) fs_blocks.items else "",
        },
    );
    defer allocator.free(fs_source);

    const fs_shader = try _gpu.compileShader(allocator, var_def.items, fs_source, fs_shader_options);
    defer allocator.free(fs_shader);

    //
    // Create bgfx shader and program
    //
    const fs_cubes = _gpu.createShader(_gpu.copy(fs_shader.ptr, @intCast(fs_shader.len)));
    const vs_cubes = _gpu.createShader(_gpu.copy(vs_shader.ptr, @intCast(vs_shader.len)));
    const programHandle = _gpu.createProgram(vs_cubes, fs_cubes, true);

    const instance = _g.shader_instance_pool.create(null);
    instance.prg = programHandle;
    instance.state = state;
    instance.rgba = rgba;

    return .{
        .idx = _g.shader_instance_pool.index(instance),
    };
}

fn getGpuProgram(shader_instance: public.ShaderInstance) ?gpu.ProgramHandle {
    const inst = _g.shader_instance_pool.get(shader_instance.idx);
    return inst.prg;
}

fn getState(shader_instance: public.ShaderInstance) u64 {
    const inst = _g.shader_instance_pool.get(shader_instance.idx);
    return inst.state;
}
fn getRGBAState(shader_instance: public.ShaderInstance) u32 {
    const inst = _g.shader_instance_pool.get(shader_instance.idx);
    return inst.rgba;
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "ShaderSystem",
    &[_]strid.StrId64{},
    struct {
        pub fn init() !void {
            _g.shader_def_map = ShaderDefMap.init(_allocator);
            _g.shader_instance_pool = try ShaderInstancePool.init(_allocator, MAX_SHADER_INSTANCE);

            // Shaderlib from BGFX
            try api.addShaderDefiniton("shaderlib", .{
                .common_block = @embedFile("embed/shaderlib.sh"),
            });

            // TODO: TMP SHIT
            if (_gpu.getBackendType() != .noop) {
                try api.addShaderDefiniton("default", .{
                    .vertex_block = .{
                        .imports = &.{
                            .position,
                            .color0,
                        },
                        .exports = &.{
                            .{ .name = "v_color0", .type = .vec4, .semantic = .color0 },
                        },
                        .code =
                        \\  gl_Position = mul(u_modelViewProj, vec4(a_position, 1.0) );
                        \\  v_color0 = a_color0;
                        ,
                    },
                    .fragment_block = .{
                        .code =
                        \\  gl_FragColor = v_color0;
                        ,
                    },
                });

                _g.prg = try api.compileShader(_allocator, &.{ strid.strId32("shaderlib"), strid.strId32("default") });
            }
        }

        pub fn shutdown() !void {
            _g.shader_def_map.deinit();
            _g.shader_instance_pool.deinit();
        }
    },
);

inline fn semanticToText(semantic: public.DefExportVariableSemantic) []const u8 {
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

const gpu_shader_value_type_i = graphvm.GraphValueTypeI.implement(
    public.ShaderInstance,
    .{
        .name = "GPU shader",
        .type_hash = public.PinTypes.GPU_SHADER,
        .cdb_type_hash = public.GPUShaderInstanceCDB.type_hash,
    },
    struct {
        pub fn valueFromCdb(obj: cdb.ObjId, value: []u8) !void {
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

// ONLY FOR TESTING
const lsd_cube_node_i = graphvm.GraphNodeI.implement(
    .{
        .name = "Test shader",
        .type_name = "test_shader",
        .category = "Renderer",
    },
    null,
    struct {
        const Self = @This();

        pub fn getInputPins(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{});
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) ![]const graphvm.NodePin {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{
                graphvm.NodePin.init("GPU shader", graphvm.NodePin.pinHash("gpu_shader", true), public.PinTypes.GPU_SHADER),
            });
        }

        pub fn create(allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool) !void {
            _ = state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
        }

        pub fn execute(args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = args; // autofix
            _ = in_pins; // autofix

            try out_pins.writeTyped(public.ShaderInstance, 0, try gpu_shader_value_type_i.calcValidityHash(&std.mem.toBytes(_g.prg.?)), _g.prg.?);
        }

        pub fn icon(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

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
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    // register api
    try apidb.setOrRemoveZigApi(module_name, public.ShaderSystemAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, graphvm.GraphNodeI, &lsd_cube_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_shader_value_type_i, load);

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_shader_system(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
