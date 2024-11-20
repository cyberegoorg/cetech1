const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const graphvm = @import("graphvm");

pub const EntityLogicComponent = struct {
    graph: cdb.ObjId = .{},
};

pub const EntityLogicComponentInstance = struct {
    graph_container: graphvm.GraphInstance = .{},
};

pub const EntityLogicComponentCdb = cdb.CdbTypeDecl(
    "ct_entity_logic_component",
    enum(u32) {
        graph = 0,
    },
    struct {},
);
