const std = @import("std");
const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;

pub const LuauScriptComponentCdb = cdb.CdbTypeDecl(
    "ct_luau_script_component",
    enum(u32) {
        Script = 0,
    },
    struct {},
);

pub const LuauScriptComponent = extern struct {
    script: cdb.ObjId = .{},
};
