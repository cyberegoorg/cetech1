const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const strid = cetech1.strid;
const math = cetech1.math;
const gpu = cetech1.gpu;

pub const PinTypes = struct {
    pub const GPU_SHADER = strid.strId32("gpu_shader");
};

pub const GPUShaderInstanceCDB = cdb.CdbTypeDecl(
    "ct_gpu_shader",
    enum(u32) {
        handle = 0,
    },
    struct {},
);

pub const DefVariableType = enum {
    vec2,
    vec3,
    vec4,
    float,
};

pub const DefExportVariableSemantic = enum {
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
    semantic: DefExportVariableSemantic,
};

pub const DefVertexBlock = struct {
    import_semantic: ?[]const []const u8 = null,
    imports: []const DefImportVariableType,
    exports: []const DefExport,
    code: []const u8,
};

pub const DefFragmentBlock = struct {
    code: []const u8,
};

pub const ShaderDefinition = struct {
    common_block: ?[]const u8 = null,

    vertex_block: ?DefVertexBlock = null,
    fragment_block: ?DefFragmentBlock = null,
};

pub const ShaderInstance = struct {
    idx: u32 = 0,
};

pub const ShaderSystemAPI = struct {
    addShaderDefiniton: *const fn (name: []const u8, definition: ShaderDefinition) anyerror!void,

    compileProgram: *const fn (allocator: std.mem.Allocator, definitons: []const strid.StrId32) anyerror!?ShaderInstance,

    getGpuProgram: *const fn (shader_instance: ShaderInstance) ?gpu.ProgramHandle,
};
