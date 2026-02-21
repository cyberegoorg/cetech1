const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;
const math = cetech1.math;
const apidb = cetech1.apidb;

const shader_system = @import("shader_system");
const transform = @import("transform");

pub const InstanceSystem = struct {
    system: shader_system.System = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resources: ?shader_system.ResourceBufferInstance = null,
};

pub fn createInstanceSystem(mtxs: []const math.Mat44f) anyerror!InstanceSystem {
    return api.createInstanceSystem(mtxs);
}
pub fn destroyInstanceSystem(inst_system: InstanceSystem) void {
    api.destroyInstanceSystem(inst_system);
}

pub const InstanceSystemApi = struct {
    createInstanceSystem: *const fn (mtxs: []const math.Mat44f) anyerror!InstanceSystem,
    destroyInstanceSystem: *const fn (inst_system: InstanceSystem) void,
};

pub var api: *const InstanceSystemApi = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, InstanceSystemApi).?;
}
