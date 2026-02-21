const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const apidb = cetech1.apidb;

const shader_system = @import("shader_system");

pub const LightSystem = struct {
    system: shader_system.System = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resources: ?shader_system.ResourceBufferInstance = null,
    light_buffer: gpu.DynamicVertexBufferHandle = undefined,
};

pub fn createLightSystem(gpu_backend: gpu.GpuBackend) anyerror!LightSystem {
    return api.createLightSystem(gpu_backend);
}
pub fn destroyLightSystem(inst_system: LightSystem, gpu_backend: gpu.GpuBackend) void {
    return api.destroyLightSystem(inst_system, gpu_backend);
}

pub const LightSystemApi = struct {
    createLightSystem: *const fn (gpu_backend: gpu.GpuBackend) anyerror!LightSystem,
    destroyLightSystem: *const fn (inst_system: LightSystem, gpu_backend: gpu.GpuBackend) void,
};

pub var api: *const LightSystemApi = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, LightSystemApi).?;
}
