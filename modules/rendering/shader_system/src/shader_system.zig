const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const cdb_types = cetech1.cdb_types;
const math = cetech1.math;
const gpu = cetech1.gpu;
const apidb = cetech1.apidb;

const render_viewport = @import("render_viewport");

pub const MAX_SYSTEMS = 64;

pub const PinTypes = struct {
    pub const GPU_SHADER = cetech1.strId32("gpu_shader");

    pub const GPU_VEC2 = cetech1.strId32("gpu_vec2");
    pub const GPU_VEC3 = cetech1.strId32("gpu_vec3");
    pub const GPU_VEC4 = cetech1.strId32("gpu_vec4");

    pub const GPU_FLOAT = cetech1.strId32("gpu_float");
};

pub const GPUShaderValueCDB = cdb.CdbTypeDecl(
    "ct_gpu_shader",
    enum(u32) {
        Handle = 0,
    },
    struct {},
);

pub const GpuVec2fCdb = cdb.CdbTypeDecl(
    "ct_gpu_vec_2f",
    enum(u32) {
        X = 0,
        Y,
    },
    struct {
        pub fn toSlice(obj: cdb.ObjId) math.Vec2f {
            const r = cdb.readObj(obj) orelse return .{};
            return .{
                .x = GpuVec2fCdb.readValue(f32, r, .X),
                .y = GpuVec2fCdb.readValue(f32, r, .Y),
            };
        }

        pub fn fromSlice(obj_w: *cdb.Obj, value: math.Vec2f) void {
            GpuVec2fCdb.setValue(f32, obj_w, .X, value[0]);
            GpuVec2fCdb.setValue(f32, obj_w, .Y, value[1]);
        }
    },
);

pub const GpuVec3fCdb = cdb.CdbTypeDecl(
    "ct_gpu_vec_3f",
    enum(u32) {
        X = 0,
        Y,
        Z,
    },
    struct {
        pub fn toSlice(obj: cdb.ObjId) math.Vec3f {
            const r = cdb.readObj(obj) orelse return .{};
            return .{
                .x = cdb_types.Vec3fCdb.readValue(f32, r, .X),
                .y = cdb_types.Vec3fCdb.readValue(f32, r, .Y),
                .z = cdb_types.Vec3fCdb.readValue(f32, r, .Z),
            };
        }

        pub fn fromSlice(obj_w: *cdb.Obj, value: math.Vec3f) void {
            cdb_types.Vec3fCdb.setValue(f32, obj_w, .X, value.x);
            cdb_types.Vec3fCdb.setValue(f32, obj_w, .Y, value.y);
            cdb_types.Vec3fCdb.setValue(f32, obj_w, .Z, value.z);
        }
    },
);

pub const GpuVec4fCdb = cdb.CdbTypeDecl(
    "ct_gpu_vec_4f",
    enum(u32) {
        X = 0,
        Y,
        Z,
        W,
    },
    struct {
        pub fn toSlice(obj: cdb.ObjId) math.Vec4f {
            const r = cdb.readObj(obj) orelse return .{};
            return .{
                .x = GpuVec4fCdb.readValue(f32, r, .X),
                .y = GpuVec4fCdb.readValue(f32, r, .Y),
                .z = GpuVec4fCdb.readValue(f32, r, .Z),
                .w = GpuVec4fCdb.readValue(f32, r, .W),
            };
        }

        pub fn fromSlice(obj_w: *cdb.Obj, value: math.Vec4f) void {
            GpuVec4fCdb.setValue(f32, obj_w, .X, value.x);
            GpuVec4fCdb.setValue(f32, obj_w, .Y, value.y);
            GpuVec4fCdb.setValue(f32, obj_w, .Z, value.z);
            GpuVec4fCdb.setValue(f32, obj_w, .W, value.w);
        }
    },
);

pub const Gpuf32Cdb = cdb.CdbTypeDecl(
    "ct_gpu_f32",
    enum(u32) {
        Value = 0,
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
    i_data0,
    i_data1,
    i_data2,
    i_data3,
};

pub const DefExport = struct {
    name: []const u8,
    type: DefVariableType,
    to_node: bool = false,
    flat: bool = false,
};

pub const DefVertexImportSemantics = enum {
    vertex_id,
    instance_id,
};

pub const DefVertexBlock = struct {
    import_semantic: ?[]const DefVertexImportSemantics = null,
    imports: ?[]const DefImportVariableType = null,
    exports: ?[]const DefExport = null,
    common_block: ?[]const u8 = null,
    code: ?[]const u8 = null,
};

pub const DefFragmentBlock = struct {
    common_block: ?[]const u8 = null,
    exports: ?[]const DefExport = null,
    code: ?[]const u8 = null,
};

pub const DefMainImportVariableType = enum {
    vec4,
    mat3,
    mat4,
    buffer,
    sampler2d,
};

pub const DefMainImportVariableBufferType = enum {
    float,
    vec4,
};

pub const DefMainImportVariableBufferAccess = enum {
    read,
    write,
    read_write,
};

pub const DefImport = struct {
    name: [:0]const u8,
    type: DefMainImportVariableType,
    count: ?usize = null,
    buffer_type: ?DefMainImportVariableBufferType = null,
    buffer_acces: ?DefMainImportVariableBufferAccess = null,
    sampler: ?[:0]const u8 = null,
};

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
    raster_state: ?gpu.RasterState = .{},
    color_state: ?gpu.ColorState = .{},
    depth_stencil_state: ?gpu.DepthStencilState = .{},
    blend_state: ?gpu.BlendState = .{},
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

pub const DefSampler = struct {
    name: [:0]const u8,
    defs: gpu.SamplerFlags,
};

pub const ShaderDefinition = struct {
    rgba: u32 = 0,

    raster_state: ?gpu.RasterState = .{},
    color_state: ?gpu.ColorState = .{},
    depth_stencil_state: ?gpu.DepthStencilState = .{},
    blend_state: ?gpu.BlendState = .{},

    samplers: ?[]const DefSampler = null,

    imports: ?[]const DefImport = null,
    defines: ?[]const []const u8 = null,

    common_block: ?[]const u8 = null,

    vertex_block: ?DefVertexBlock = null,
    fragment_block: ?DefFragmentBlock = null,

    function: ?[]const u8 = null,

    graph_node: ?DefGraphNode = null,

    compile: ?DefCompile = null,
};

pub const UniformBufferInstance = struct {
    idx: u32,
};

pub const ResourceBufferInstance = struct {
    idx: u32,
};

pub const Shader = struct {
    idx: u32 = 0,
};

pub const ShaderVariant = struct {
    prg: ?gpu.ProgramHandle = null,
    state: gpu.RenderState,
    rgba: u32,

    hash: u64,
    layer: ?cetech1.StrId32,
    system_set: SystemSet,
};

pub const SystemInstnace = struct {
    system: System = .{},
    uniforms: ?UniformBufferInstance = null,
    resources: ?ResourceBufferInstance = null,
};

pub const SystemContext = struct {
    pub inline fn addSystem(self: *SystemContext, system: System, uniforms: ?UniformBufferInstance, resources: ?ResourceBufferInstance) !void {
        return self.vtable.addSystem(self.ptr, system, uniforms, resources);
    }

    pub inline fn getSystem(self: *const SystemContext, system: System) ?SystemInstnace {
        return self.vtable.getSystem(
            self.ptr,
            system,
        );
    }

    pub inline fn bind(self: *const SystemContext, shader: ShaderIO, encoder: gpu.GpuEncoder) void {
        self.vtable.bind(self.ptr, shader, encoder);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addSystem: *const fn (self: *anyopaque, system: System, uniforms: ?UniformBufferInstance, resources: ?ResourceBufferInstance) anyerror!void,
        getSystem: *const fn (self: *anyopaque, system: System) ?SystemInstnace,

        bind: *const fn (
            self: *anyopaque,
            shader: ShaderIO,
            encoder: gpu.GpuEncoder,
        ) void,

        pub fn implement(comptime T: type) VTable {
            return VTable{
                .addSystem = &T.addSystem,
                .bind = &T.bind,
                .getSystem = &T.getSystem,
            };
        }
    };
};

pub const ShaderIO = struct {
    ptr: *anyopaque,
};

pub const GpuShaderValue = struct {
    shader: ?Shader = .{},
    uniforms: ?UniformBufferInstance = null,
    resouces: ?ResourceBufferInstance = null,
};

pub const GpuValue = struct {
    str: []const u8,
};

pub const TranspileStages = struct {
    pub const Vertex = cetech1.strId32("gpu_vertex");
    pub const Fragment = cetech1.strId32("gpu_fragment");
};

pub const ConstructNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_gpu_construct_node_settings",
    enum(u32) {
        ResultType,
    },
    struct {},
);

pub const ConstructNodeResultType = enum {
    vec2,
    vec3,
    vec4,
};

pub const ConstNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_gpu_const_node_settings",
    enum(u32) {
        ResultType,
        value,
    },
    struct {},
);

pub const ConstNodeResultType = enum {
    vec2,
    vec3,
    vec4,
    color3,
    color4,
    float,
};

pub const UniformNodeSettingsCdb = cdb.CdbTypeDecl(
    "ct_gpu_uniform_node_settings",
    enum(u32) {
        Name,
        ResultType,
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
    uniforms: ?UniformBufferInstance = null,
    resouces: ?ResourceBufferInstance = null,

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

pub const System = struct {
    idx: u32 = 0,
};

pub const UpdateUniformItem = struct {
    name: cetech1.StrId32,
    value: []const u8,
};

pub const UpdateResourceValue = union(enum) {
    buffer: gpu.BufferHandle,
    texture: gpu.TextureHandle,
};

pub const UpdateResourceItem = struct {
    name: cetech1.StrId32,
    value: UpdateResourceValue,
};

pub fn addShaderDefiniton(name: []const u8, definition: ShaderDefinition) anyerror!void {
    return api.addShaderDefiniton(name, definition);
}
pub fn addSystemDefiniton(name: []const u8, definition: ShaderDefinition) anyerror!void {
    return api.addSystemDefiniton(name, definition);
}
pub fn compileShader(allocator: std.mem.Allocator, use_definitions: []const cetech1.StrId32, definition: ?ShaderDefinition, name: ?[:0]const u8) anyerror!?Shader {
    return api.compileShader(allocator, use_definitions, definition, name);
}
pub fn destroyShader(shader: Shader) void {
    return api.destroyShader(shader);
}
pub fn selectShaderVariant(allocator: std.mem.Allocator, shader: Shader, context: []const cetech1.StrId32, system_context: *const SystemContext) anyerror![]*const ShaderVariant {
    return api.selectShaderVariant(allocator, shader, context, system_context);
}
pub fn createSystemContext() anyerror!SystemContext {
    return api.createSystemContext();
}
pub fn cloneSystemContext(context: SystemContext) anyerror!SystemContext {
    return api.cloneSystemContext(context);
}
pub fn destroySystemContext(context: SystemContext) void {
    return api.destroySystemContext(context);
}
pub fn getShaderIO(shader: Shader) ShaderIO {
    return api.getShaderIO(shader);
}
pub fn getSystemIO(system: System) ShaderIO {
    return api.getSystemIO(system);
}
pub fn findShaderByName(name: cetech1.StrId32) ?Shader {
    return api.findShaderByName(name);
}
pub fn findSystemByName(name: cetech1.StrId32) ?System {
    return api.findSystemByName(name);
}
pub fn createUniformBuffer(shader_io: ShaderIO) anyerror!?UniformBufferInstance {
    return api.createUniformBuffer(shader_io);
}
pub fn destroyUniformBuffer(shader_io: ShaderIO, buffer: UniformBufferInstance) void {
    return api.destroyUniformBuffer(shader_io, buffer);
}
pub fn createResourceBuffer(shader_io: ShaderIO) anyerror!?ResourceBufferInstance {
    return api.createResourceBuffer(shader_io);
}
pub fn destroyResourceBuffer(shader_io: ShaderIO, buffer: ResourceBufferInstance) void {
    return api.destroyResourceBuffer(shader_io, buffer);
}
pub fn updateUniforms(shader: ShaderIO, uniform_buffer: UniformBufferInstance, items: []const UpdateUniformItem) anyerror!void {
    return api.updateUniforms(shader, uniform_buffer, items);
}
pub fn updateResources(shader: ShaderIO, resource_buffer: ResourceBufferInstance, items: []const UpdateResourceItem) anyerror!void {
    return api.updateResources(shader, resource_buffer, items);
}
pub fn bindConstant(shader_io: ShaderIO, uniform_buffer: UniformBufferInstance, encoder: gpu.GpuEncoder) void {
    return api.bindConstant(shader_io, uniform_buffer, encoder);
}
pub fn bindSystemConstant(shader_io: ShaderIO, system: System, uniform_buffer: UniformBufferInstance, encoder: gpu.GpuEncoder) void {
    return api.bindSystemConstant(shader_io, system, uniform_buffer, encoder);
}
pub fn bindResource(shader_io: ShaderIO, resource_buffer: ResourceBufferInstance, encoder: gpu.GpuEncoder) void {
    return api.bindResource(shader_io, resource_buffer, encoder);
}
pub fn bindSystemResource(shader_io: ShaderIO, system: System, resource_buffer: ResourceBufferInstance, encoder: gpu.GpuEncoder) void {
    return api.bindSystemResource(shader_io, system, resource_buffer, encoder);
}

pub const ShaderSystemAPI = struct {
    addShaderDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,
    addSystemDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,
    compileShader: *const fn (allocator: std.mem.Allocator, use_definitions: []const cetech1.StrId32, definition: ?ShaderDefinition, name: ?[:0]const u8) anyerror!?Shader,
    destroyShader: *const fn (shader: Shader) void,
    selectShaderVariant: *const fn (allocator: std.mem.Allocator, shader: Shader, context: []const cetech1.StrId32, system_context: *const SystemContext) anyerror![]*const ShaderVariant,
    createSystemContext: *const fn () anyerror!SystemContext,
    cloneSystemContext: *const fn (context: SystemContext) anyerror!SystemContext,
    destroySystemContext: *const fn (context: SystemContext) void,
    getShaderIO: *const fn (shader: Shader) ShaderIO,
    getSystemIO: *const fn (system: System) ShaderIO,
    findShaderByName: *const fn (name: cetech1.StrId32) ?Shader,
    findSystemByName: *const fn (name: cetech1.StrId32) ?System,
    createUniformBuffer: *const fn (shader_io: ShaderIO) anyerror!?UniformBufferInstance,
    destroyUniformBuffer: *const fn (shader_io: ShaderIO, buffer: UniformBufferInstance) void,
    createResourceBuffer: *const fn (shader_io: ShaderIO) anyerror!?ResourceBufferInstance,
    destroyResourceBuffer: *const fn (shader_io: ShaderIO, buffer: ResourceBufferInstance) void,
    updateUniforms: *const fn (shader: ShaderIO, uniform_buffer: UniformBufferInstance, items: []const UpdateUniformItem) anyerror!void,
    updateResources: *const fn (shader: ShaderIO, resource_buffer: ResourceBufferInstance, items: []const UpdateResourceItem) anyerror!void,
    bindConstant: *const fn (shader_io: ShaderIO, uniform_buffer: UniformBufferInstance, encoder: gpu.GpuEncoder) void,
    bindSystemConstant: *const fn (shader_io: ShaderIO, system: System, uniform_buffer: UniformBufferInstance, encoder: gpu.GpuEncoder) void,
    bindResource: *const fn (shader_io: ShaderIO, resource_buffer: ResourceBufferInstance, encoder: gpu.GpuEncoder) void,
    bindSystemResource: *const fn (shader_io: ShaderIO, system: System, resource_buffer: ResourceBufferInstance, encoder: gpu.GpuEncoder) void,
};

pub var api: *const ShaderSystemAPI = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, ShaderSystemAPI).?;
}
