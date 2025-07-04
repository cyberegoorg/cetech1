const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const shader_system = @import("shader_system");
const vertex_system = @import("vertex_system");
const visibility_flags = @import("visibility_flags");

pub const DrawCall = struct {
    shader: ?shader_system.Shader = .{},
    uniforms: ?shader_system.UniformBufferInstance = null,
    resouces: ?shader_system.ResourceBufferInstance = null,

    geometry: ?vertex_system.GPUGeometry = null,
    index_buffer: ?gpu.IndexBufferHandle = null,

    vertex_count: u32 = 0,
    index_count: u32 = 0,

    visibility_mask: visibility_flags.VisibilityFlags,
    hash: u64 = 0,

    pub fn calcHash(self: *DrawCall) void {
        var h = std.hash.Wyhash.init(0);

        std.hash.autoHash(&h, self.shader);
        std.hash.autoHash(&h, self.resouces);
        std.hash.autoHash(&h, self.uniforms);
        std.hash.autoHash(&h, self.geometry);
        std.hash.autoHash(&h, self.index_buffer);
        std.hash.autoHash(&h, self.vertex_count);
        std.hash.autoHash(&h, self.index_count);
        std.hash.autoHash(&h, self.visibility_mask.mask);

        self.hash = h.final();
    }
};
