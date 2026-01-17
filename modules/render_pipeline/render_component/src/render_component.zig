const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const graphvm = @import("graphvm");
const shader_system = @import("shader_system");
const vertex_system = @import("vertex_system");
const visibility_flags = @import("visibility_flags");

pub const RenderComponent = struct {
    graph: cdb.ObjId = .{},
};

pub const RenderComponentInstance = struct {
    instance: graphvm.GraphInstance = .{},
};

pub const RenderComponentCdb = cdb.CdbTypeDecl(
    "ct_render_component",
    enum(u32) {
        Graph = 0,
    },
    struct {},
);
