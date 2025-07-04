const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const math = cetech1.math.zmath;
const gpu = cetech1.gpu;

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
};

pub const CullMode = enum {
    none,
    front,
    back,
};

pub const FrontFace = enum {
    cw,
    ccw,
};

pub const RasterState = struct {
    cullmode: ?CullMode = null,
    front_face: ?FrontFace = null,

    pub fn merge(self: RasterState, other: RasterState) RasterState {
        var r = self;

        if (self.cullmode) |_| {
            if (other.cullmode) |o| {
                r.cullmode = o;
            }
        } else {
            r.cullmode = other.cullmode;
        }

        if (self.front_face) |_| {
            if (other.front_face) |o| {
                r.front_face = o;
            }
        } else {
            r.front_face = other.front_face;
        }

        return r;
    }

    pub fn toState(self: RasterState) gpu.StateFlags {
        var r: u64 = gpu.StateFlags_None;

        if (self.cullmode) |cullmode| {
            switch (cullmode) {
                .front => {
                    if (self.front_face) |front_face| {
                        switch (front_face) {
                            .cw => {
                                r |= gpu.StateFlags_CullCw;
                            },
                            .ccw => {
                                r |= gpu.StateFlags_CullCcw;
                                r |= gpu.StateFlags_FrontCcw;
                            },
                        }
                    } else {
                        r |= gpu.StateFlags_CullCcw;
                        r |= gpu.StateFlags_FrontCcw;
                    }
                },
                .back => {
                    if (self.front_face) |front_face| {
                        switch (front_face) {
                            .cw => {
                                r |= gpu.StateFlags_CullCcw;
                            },
                            .ccw => {
                                r |= gpu.StateFlags_CullCw;
                                r |= gpu.StateFlags_FrontCcw;
                            },
                        }
                    } else {
                        r |= gpu.StateFlags_CullCw;
                    }
                },
                .none => {},
            }
        }

        if (self.front_face) |front_face| {
            switch (front_face) {
                .cw => {},
                .ccw => {
                    r |= gpu.StateFlags_FrontCcw;
                },
            }
        }

        return r;
    }
};

pub const DepthComapareOp = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
};

pub const DepthStencilState = struct {
    depth_test_enable: ?bool = null,
    depth_write_enable: ?bool = null,
    depth_comapre_op: ?DepthComapareOp = null,

    pub fn merge(self: DepthStencilState, other: DepthStencilState) DepthStencilState {
        var r = self;

        if (self.depth_test_enable) |_| {
            if (other.depth_test_enable) |o| {
                r.depth_test_enable = o;
            }
        } else {
            r.depth_test_enable = other.depth_test_enable;
        }

        if (self.depth_write_enable) |_| {
            if (other.depth_write_enable) |o| {
                r.depth_write_enable = o;
            }
        } else {
            r.depth_write_enable = other.depth_write_enable;
        }

        if (self.depth_comapre_op) |_| {
            if (other.depth_comapre_op) |o| {
                r.depth_comapre_op = o;
            }
        } else {
            r.depth_comapre_op = other.depth_comapre_op;
        }

        return r;
    }

    pub fn toState(self: DepthStencilState) gpu.StateFlags {
        var r: u64 = gpu.StateFlags_None;

        if (self.depth_test_enable) |depth_test_enable| {
            if (depth_test_enable) {
                if (self.depth_comapre_op) |depth_comapre_op| {
                    switch (depth_comapre_op) {
                        .never => r |= gpu.StateFlags_DepthTestNever,
                        .less => r |= gpu.StateFlags_DepthTestLess,
                        .equal => r |= gpu.StateFlags_DepthTestEqual,
                        .less_equal => r |= gpu.StateFlags_DepthTestLequal,
                        .greater => r |= gpu.StateFlags_DepthTestGreater,
                        .not_equal => r |= gpu.StateFlags_DepthTestNotequal,
                        .greater_equal => r |= gpu.StateFlags_DepthTestGequal,
                    }
                }
            }
        }

        if (self.depth_write_enable) |depth_write_enable| {
            if (depth_write_enable) r |= gpu.StateFlags_WriteZ;
        }

        return r;
    }
};

pub const ColorState = struct {
    pub const rgb = ColorState{ .write_r = true, .write_g = true, .write_b = true, .write_a = false };
    pub const rgba = ColorState{ .write_r = true, .write_g = true, .write_b = true, .write_a = true };
    pub const only_a = ColorState{ .write_r = false, .write_g = false, .write_b = false, .write_a = true };

    write_r: ?bool = null,
    write_g: ?bool = null,
    write_b: ?bool = null,
    write_a: ?bool = null,

    pub fn merge(self: ColorState, other: ColorState) ColorState {
        var r = self;

        if (self.write_r) |_| {
            if (other.write_r) |o| {
                r.write_r = o;
            }
        } else {
            r.write_r = other.write_r;
        }

        if (self.write_g) |_| {
            if (other.write_g) |o| {
                r.write_g = o;
            }
        } else {
            r.write_g = other.write_g;
        }

        if (self.write_b) |_| {
            if (other.write_b) |o| {
                r.write_b = o;
            }
        } else {
            r.write_b = other.write_b;
        }

        if (self.write_a) |_| {
            if (other.write_a) |o| {
                r.write_a = o;
            }
        } else {
            r.write_a = other.write_a;
        }
        return r;
    }

    pub fn toState(self: ColorState) gpu.StateFlags {
        var r: u64 = gpu.StateFlags_None;

        if (self.write_r) |write_r| {
            if (write_r) r |= gpu.StateFlags_WriteR;
        }

        if (self.write_g) |write_g| {
            if (write_g) r |= gpu.StateFlags_WriteG;
        }

        if (self.write_b) |write_b| {
            if (write_b) r |= gpu.StateFlags_WriteB;
        }

        if (self.write_a) |write_a| {
            if (write_a) r |= gpu.StateFlags_WriteA;
        }

        return r;
    }
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
    raster_state: ?RasterState = .{},
    color_state: ?ColorState = .{},
    depth_stencil_state: ?DepthStencilState = .{},
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
    rgba: u32 = 0,

    raster_state: ?RasterState = .{},
    color_state: ?ColorState = .{},
    depth_stencil_state: ?DepthStencilState = .{},

    imports: ?[]const DefImport = null,
    defines: ?[]const []const u8 = null,

    common_block: ?[]const u8 = null,

    vertex_block: ?DefVertexBlock = null,
    fragment_block: ?DefFragmentBlock = null,

    function: ?[]const u8 = null,

    graph_node: ?DefGraphNode = null,

    compile: ?DefCompile = null,
};

pub const BufferHandle = union(enum) {
    vb: gpu.VertexBufferHandle,
    dvb: gpu.DynamicVertexBufferHandle,

    ib: gpu.IndexBufferHandle,
    dib: gpu.DynamicIndexBufferHandle,
};

pub const PrimitiveType = enum {
    triangles,
    triangles_strip,
    lines,
    lines_strip,
    points,

    pub fn toState(self: PrimitiveType) u64 {
        return switch (self) {
            .triangles => 0,
            .triangles_strip => gpu.StateFlags_PtTristrip,
            .lines => gpu.StateFlags_PtLines,
            .lines_strip => gpu.StateFlags_PtLinestrip,
            .points => gpu.StateFlags_PtPoints,
        };
    }
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
    hash: u64,
    state: u64,
    rgba: u32,

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

    pub inline fn bind(self: *const SystemContext, shader: ShaderIO, encoder: gpu.Encoder) void {
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
            encoder: gpu.Encoder,
        ) void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addSystem")) @compileError("implement me");
            if (!std.meta.hasFn(T, "bind")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getSystem")) @compileError("implement me");

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
    buffer: BufferHandle,
    texture: gpu.TextureHandle,
};

pub const UpdateResourceItem = struct {
    name: cetech1.StrId32,
    value: UpdateResourceValue,
};

pub const ShaderSystemAPI = struct {
    addShaderDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,
    addSystemDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,

    compileShader: *const fn (allocator: std.mem.Allocator, use_definitions: []const cetech1.StrId32, definition: ?ShaderDefinition, name: ?[:0]const u8) anyerror!?Shader,
    destroyShader: *const fn (shader: Shader) void,

    selectShaderVariant: *const fn (
        allocator: std.mem.Allocator,
        shader: Shader,
        context: []const cetech1.StrId32,
        system_context: *const SystemContext,
    ) anyerror![]*const ShaderVariant,

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

    bindConstant: *const fn (shader_io: ShaderIO, uniform_buffer: UniformBufferInstance, encoder: gpu.Encoder) void,
    bindSystemConstant: *const fn (shader_io: ShaderIO, system: System, uniform_buffer: UniformBufferInstance, encoder: gpu.Encoder) void,

    bindResource: *const fn (shader_io: ShaderIO, resource_buffer: ResourceBufferInstance, encoder: gpu.Encoder) void,
    bindSystemResource: *const fn (shader_io: ShaderIO, system: System, resource_buffer: ResourceBufferInstance, encoder: gpu.Encoder) void,
};
