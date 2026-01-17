const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

const graphvm = @import("graphvm");

pub const GraphVMScriptComponent = struct {
    graph: cdb.ObjId = .{},
};

pub const GraphVMScriptComponentInstance = struct {
    instance: graphvm.GraphInstance = .{},
};

pub const GraphVMScriptComponentCdb = cdb.CdbTypeDecl(
    "ct_graphvm_script_component",
    enum(u32) {
        Graph = 0,
    },
    struct {},
);
