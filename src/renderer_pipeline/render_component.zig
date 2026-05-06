const std = @import("std");

const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const gpu = cetech1.gpu;

const graphvm = cetech1.scripting.graphvm;

pub const RenderComponent = extern struct {
    graph: cdb.ObjId = .{},
};

pub const RenderComponentInstance = extern struct {
    instance: graphvm.GraphInstance = .{},
};

pub const RenderComponentCdb = cdb.CdbTypeDecl(
    "ct_render_component",
    enum(u32) {
        Graph = 0,
    },
    struct {},
);
