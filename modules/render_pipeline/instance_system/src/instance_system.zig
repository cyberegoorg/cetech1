const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const math = cetech1.math;

const shader_system = @import("shader_system");
const transform = @import("transform");

pub const InstanceSystem = struct {
    system: shader_system.System = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resources: ?shader_system.ResourceBufferInstance = null,
};

pub const InstanceSystemApi = struct {
    createInstanceSystem: *const fn (mtxs: []const math.Mat44f) anyerror!InstanceSystem,
    destroyInstanceSystem: *const fn (inst_system: InstanceSystem) void,
};
