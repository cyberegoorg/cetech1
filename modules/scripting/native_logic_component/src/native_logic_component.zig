const std = @import("std");
const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;

pub const NativeScriptI = struct {
    const Self = @This();
    pub const c_name = "ct_native_script_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    id: cetech1.StrId32 = undefined,
    name: [:0]const u8,
    display_name: [:0]const u8,

    init: *const fn (allocator: std.mem.Allocator) anyerror!?*anyopaque = undefined,
    shutdown: *const fn (allocator: std.mem.Allocator, inst: ?*anyopaque) anyerror!void = undefined,
    update: *const fn (inst: ?*anyopaque) anyerror!void = undefined,

    pub fn implement(args: NativeScriptI, comptime T: type) Self {
        return Self{
            .id = cetech1.strId32(args.name),
            .name = args.name,
            .display_name = args.display_name,
            .init = T.init,
            .shutdown = T.shutdown,
            .update = T.update,
        };
    }
};

pub const NativeLogicComponent = struct {
    native_script: ?cetech1.StrId32 = null,
};

pub const NativeLogicComponentInstance = struct {
    inst: ?*anyopaque = null,
    iface: *const NativeScriptI,
};

pub const NativeLogicComponentCdb = cdb.CdbTypeDecl(
    "ct_native_logic_component",
    enum(u32) {
        native_script = 0,
    },
    struct {},
);
