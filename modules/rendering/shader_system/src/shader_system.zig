const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const strid = cetech1.strid;
const math = cetech1.math.zmath;
const gpu = cetech1.gpu;

const renderer = @import("renderer");

pub const MAX_SYSTEMS = 64;

pub const PinTypes = struct {
    pub const GPU_SHADER = cetech1.strId32("gpu_shader");

    pub const GPU_VEC2 = cetech1.strId32("gpu_vec2");
    pub const GPU_VEC3 = cetech1.strId32("gpu_vec3");
    pub const GPU_VEC4 = cetech1.strId32("gpu_vec4");

    pub const GPU_FLOAT = cetech1.strId32("gpu_float");
};

pub const GPUShaderInstanceCDB = cdb.CdbTypeDecl(
    "ct_gpu_shader",
    enum(u32) {
        handle = 0,
    },
    struct {},
);

pub const Vec2f = cdb.CdbTypeDecl(
    "ct_gpu_vec_2f",
    enum(u32) {
        X = 0,
        Y,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [2]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0 };
            return .{
                Vec2f.readValue(f32, api, r, .X),
                Vec2f.readValue(f32, api, r, .Y),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [2]f32) void {
            Vec2f.setValue(f32, api, obj_w, .X, value[0]);
            Vec2f.setValue(f32, api, obj_w, .Y, value[1]);
        }
    },
);

pub const Vec3f = cdb.CdbTypeDecl(
    "ct_gpu_vec_3f",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [3]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0, 0.0 };
            return .{
                Vec3f.readValue(f32, api, r, .X),
                Vec3f.readValue(f32, api, r, .Y),
                Vec3f.readValue(f32, api, r, .Z),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [3]f32) void {
            Vec3f.setValue(f32, api, obj_w, .X, value[0]);
            Vec3f.setValue(f32, api, obj_w, .Y, value[1]);
            Vec3f.setValue(f32, api, obj_w, .Z, value[2]);
        }
    },
);

pub const Vec4f = cdb.CdbTypeDecl(
    "ct_gpu_vec_4f",
    enum(u32) {
        X = 0,
        Y,
        Z,
        W,
    },
    struct {
        pub fn toSlice(api: *const cdb.CdbAPI, obj: cdb.ObjId) [4]f32 {
            const r = api.readObj(obj) orelse return .{ 0.0, 0.0, 0.0, 0.0 };
            return .{
                Vec4f.readValue(f32, api, r, .X),
                Vec4f.readValue(f32, api, r, .Y),
                Vec4f.readValue(f32, api, r, .Z),
                Vec4f.readValue(f32, api, r, .W),
            };
        }

        pub fn fromSlice(api: *const cdb.CdbAPI, obj_w: *cdb.Obj, value: [3]f32) void {
            Vec4f.setValue(f32, api, obj_w, .X, value[0]);
            Vec4f.setValue(f32, api, obj_w, .Y, value[1]);
            Vec4f.setValue(f32, api, obj_w, .Z, value[2]);
            Vec4f.setValue(f32, api, obj_w, .W, value[3]);
        }
    },
);

pub const f32Type = cdb.CdbTypeDecl(
    "ct_gpu_f32",
    enum(u32) {
        value = 0,
    },
    struct {},
);

pub const DefVariableType = enum {
    vec2,
    vec3,
    vec4,
    float,
};

pub const DefImportVariableType = enum {
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

pub const DefExport = struct {
    name: []const u8,
    type: DefVariableType,
    to_node: bool = false,
};

pub const DefVertexBlock = struct {
    import_semantic: ?[]const []const u8 = null,
    imports: ?[]const DefImportVariableType = null,
    exports: ?[]const DefExport = null,
    common_block: ?[]const u8 = null,
    code: []const u8,
};

pub const DefFragmentBlock = struct {
    common_block: ?[]const u8 = null,
    exports: ?[]const DefExport = null,
    code: []const u8,
};

pub const DefMainImportVariableType = enum {
    vec4,
    mat3,
    mat4,
};

pub const DefImport = struct {
    name: [:0]const u8,
    type: DefMainImportVariableType,
};

const defualt_state = 0 |
    gpu.StateFlags_WriteRgb |
    gpu.StateFlags_WriteA |
    gpu.StateFlags_WriteZ |
    gpu.StateFlags_DepthTestLess |
    gpu.StateFlags_CullCcw |
    gpu.StateFlags_Msaa;

pub const DefGraphNodeInputType = enum {
    vec2,
    vec3,
    vec4,
    float,
};

pub const DefGraphNodeOutputType = enum {
    vec2,
    vec3,
    vec4,
    float,
};

pub const DefGraphNodeInput = struct {
    name: [:0]const u8,
    display_name: ?[:0]const u8 = null,
    type: ?DefGraphNodeInputType = null,
    stage: ?cetech1.StrId32 = null,
    contexts: ?[]const []const u8 = null,
};

pub const DefGraphNodeOutputs = struct {
    name: [:0]const u8,
    display_name: ?[:0]const u8 = null,
    type: ?DefGraphNodeOutputType = null,
    type_of: ?[:0]const u8 = null,
};

pub const DefGraphNode = struct {
    name: [:0]const u8,
    display_name: ?[:0]const u8 = null,
    category: ?[:0]const u8 = null,

    inputs: ?[]const DefGraphNodeInput = null,
    outputs: ?[]const DefGraphNodeOutputs = null,
};

pub const DefCompileConfigurationVariation = struct {
    systems: ?[]const [:0]const u8 = null,
};

pub const DefCompileConfiguration = struct {
    name: [:0]const u8,
    variations: []const DefCompileConfigurationVariation,
};

pub const DefCompileContextDef = struct {
    layer: ?[:0]const u8 = null,
    config: [:0]const u8,
};

pub const DefCompileContext = struct {
    name: [:0]const u8,
    defs: []const DefCompileContextDef,
};

pub const DefCompile = struct {
    includes: ?[]const [:0]const u8 = null,
    configurations: []const DefCompileConfiguration,
    contexts: []const DefCompileContext,
};

pub const ShaderDefinition = struct {
    state: u64 = defualt_state,
    rgba: u32 = 0,

    imports: ?[]const DefImport = null,
    defines: ?[]const []const u8 = null,

    common_block: ?[]const u8 = null,

    vertex_block: ?DefVertexBlock = null,
    fragment_block: ?DefFragmentBlock = null,

    function: ?[]const u8 = null,

    graph_node: ?DefGraphNode = null,

    compile: ?DefCompile = null,
};

pub const Shader = struct {
    idx: u32 = 0,
};

// TODO: opaque?
pub const ShaderVariant = struct {
    prg: ?gpu.ProgramHandle = null,
    hash: u64,
    state: u64,
    rgba: u32,

    layer: ?cetech1.StrId32,

    uniforms: cetech1.AutoArrayHashMap(cetech1.StrId32, gpu.UniformHandle) = .{},

    system_set: SystemSet,
};

// TODO: use idx and and array
pub const UniformMap = struct {
    allocator: std.mem.Allocator,
    data: cetech1.AutoArrayHashMap(cetech1.StrId32, []u8),

    pub fn init(allocator: std.mem.Allocator, max_uniforms: usize) !UniformMap {
        var data = cetech1.AutoArrayHashMap(cetech1.StrId32, []u8){};
        try data.ensureTotalCapacity(allocator, max_uniforms);

        return .{
            .allocator = allocator,
            .data = data,
        };
    }

    pub fn deinit(self: *UniformMap) void {
        for (self.data.values()) |values| {
            self.allocator.free(values);
        }
        self.data.deinit(self.allocator);
    }

    pub fn set(self: *UniformMap, name: cetech1.StrId32, value: anytype) !void {
        // TODO: prealocate on create
        const result = self.data.getOrPutAssumeCapacity(name);
        if (!result.found_existing) {
            result.value_ptr.* = try self.allocator.dupe(u8, std.mem.asBytes(&value));
            return;
        }
        @memcpy(result.value_ptr.*, std.mem.asBytes(&value));
    }
};

pub const ShaderInstance = struct {
    idx: u32 = 0,
    uniforms: ?UniformMap = null,
};

pub const GpuValue = struct {
    str: []const u8,
};

pub const TranspileStages = struct {
    pub const Vertex = cetech1.strId32("gpu_vertex");
    pub const Fragment = cetech1.strId32("gpu_fragment");
};

pub const ConstructNodeSettings = cdb.CdbTypeDecl(
    "ct_gpu_construct_node_settings",
    enum(u32) {
        result_type,
    },
    struct {},
);

pub const ConstructNodeResultType = enum {
    vec2,
    vec3,
    vec4,
};

pub const ConstNodeSettings = cdb.CdbTypeDecl(
    "ct_gpu_const_node_settings",
    enum(u32) {
        result_type,
        value,
    },
    struct {},
);

pub const ConstNodeResultType = enum {
    vec2,
    vec3,
    vec4,
    color,
    float,
};

pub const UniformNodeSettings = cdb.CdbTypeDecl(
    "ct_gpu_uniform_node_settings",
    enum(u32) {
        name,
        result_type,
    },
    struct {},
);

pub const UniformNodeResultType = enum {
    vec4,
    color,
};

pub const TranspileStageMap = cetech1.AutoArrayHashMap(cetech1.StrId32, cetech1.ByteList);
pub const TranspileContextMap = std.StringArrayHashMapUnmanaged(TranspileStageMap);

pub const GpuTranspileState = struct {
    shader: ?Shader = null,

    // TODO: split to transpile context and state?
    common_code: cetech1.ByteList = .{},

    context_map: TranspileContextMap = .{},
    context_result_map: TranspileContextMap = .{},

    imports: std.StringArrayHashMapUnmanaged(DefImport) = .{},
    guard_set: cetech1.AutoArrayHashMap(cetech1.StrId64, void) = .{},
    var_counter: u32 = 0,

    defines: std.StringArrayHashMapUnmanaged(void) = .{},

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GpuTranspileState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GpuTranspileState) void {
        self.common_code.deinit(self.allocator);

        self.imports.deinit(self.allocator);
        self.guard_set.deinit(self.allocator);

        self.defines.deinit(self.allocator);

        for (self.context_map.values()) |*v| {
            for (v.values()) |*vv| {
                vv.deinit(self.allocator);
            }
            v.deinit(self.allocator);
        }

        for (self.context_result_map.values()) |*v| {
            for (v.values()) |*vv| {
                vv.deinit(self.allocator);
            }
            v.deinit(self.allocator);
        }
    }

    pub fn getWriter(self: *GpuTranspileState, context: []const u8, stage: cetech1.StrId32) !cetech1.ByteList.Writer {
        const get_ctx_result = try self.context_map.getOrPut(self.allocator, context);
        if (!get_ctx_result.found_existing) {
            get_ctx_result.value_ptr.* = .{};
        }

        const get_result = try get_ctx_result.value_ptr.getOrPut(self.allocator, stage);
        if (!get_result.found_existing) {
            get_result.value_ptr.* = .{};
        }

        return get_result.value_ptr.*.writer(self.allocator);
    }

    pub inline fn fromBytes(state: []u8) *GpuTranspileState {
        return @alignCast(std.mem.bytesAsValue(GpuTranspileState, state));
    }
};

pub const SystemSet = std.bit_set.IntegerBitSet(MAX_SYSTEMS);

pub const SystemInstance = struct {
    system_idx: usize,
    uniforms: ?UniformMap = null,
};

pub const ShaderSystemAPI = struct {
    addShaderDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,
    addSystemDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,

    compileShader: *const fn (allocator: std.mem.Allocator, use_definitions: []const cetech1.StrId32, definition: ?ShaderDefinition) anyerror!?Shader,
    destroyShader: *const fn (shader: Shader) void,

    createShaderInstance: *const fn (shader: Shader) anyerror!ShaderInstance,
    destroyShaderInstance: *const fn (shader: *ShaderInstance) void,
    selectShaderVariant: *const fn (
        shader_instance: ShaderInstance,
        context: cetech1.StrId32,
        systems: SystemSet,
    ) ?*const ShaderVariant,

    submitShaderUniforms: *const fn (encoder: gpu.Encoder, variant: *const ShaderVariant, shader_instance: ShaderInstance) void,

    createSystemInstance: *const fn (system: cetech1.StrId32) anyerror!SystemInstance,
    destroySystemInstance: *const fn (system: *SystemInstance) void,
    submitSystemUniforms: *const fn (encoder: gpu.Encoder, system_instance: SystemInstance) void,

    getSystemIdx: *const fn (system: cetech1.StrId32) usize,
};
