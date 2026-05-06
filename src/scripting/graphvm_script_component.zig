const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;

const graphvm = cetech1.scripting.graphvm;

pub const GraphVMScriptComponent = extern struct {
    graph: cdb.ObjId = .{},
};

pub const GraphVMScriptComponentInstance = extern struct {
    instance: graphvm.GraphInstance = .{},
};

pub const GraphVMScriptComponentCdb = cdb.CdbTypeDecl(
    "ct_graphvm_script_component",
    enum(u32) {
        Graph = 0,
    },
    struct {},
);
