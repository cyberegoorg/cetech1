const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const shader_system = @import("shader_system");

pub const LightSystem = struct {
    system: shader_system.System = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resources: ?shader_system.ResourceBufferInstance = null,
    light_buffer: gpu.DynamicVertexBufferHandle = undefined,
};

pub const LightSystemApi = struct {
    createLightSystem: *const fn () anyerror!LightSystem,
    destroyLightSystem: *const fn (inst_system: LightSystem) void,
};
