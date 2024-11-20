const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const graphvm = @import("graphvm");

pub const RenderComponent = struct {
    graph: cdb.ObjId = .{},
};

pub const RenderComponentInstance = struct {
    graph_container: graphvm.GraphInstance = .{},
};

pub const RenderComponentCdb = cdb.CdbTypeDecl(
    "ct_render_component",
    enum(u32) {
        graph = 0,
    },
    struct {},
);
