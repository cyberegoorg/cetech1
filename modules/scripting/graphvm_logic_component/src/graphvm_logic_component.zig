const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const graphvm = @import("graphvm");

pub const GraphVMLogicComponent = struct {
    graph: cdb.ObjId = .{},
};

pub const GraphVMLogicComponentInstance = struct {
    graph_container: graphvm.GraphInstance = .{},
};

pub const GraphVMLogicComponentCdb = cdb.CdbTypeDecl(
    "ct_graphvm_logic_component",
    enum(u32) {
        graph = 0,
    },
    struct {},
);
