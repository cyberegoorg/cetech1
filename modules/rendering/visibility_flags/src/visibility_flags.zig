const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const apidb = cetech1.apidb;

pub const MAX_FLAGS = 32;
pub const VisibilityFlags = cetech1.StaticBitSet(MAX_FLAGS);

pub const VisibilityFlagsCdb = cdb.CdbTypeDecl(
    "ct_visibility_flags",
    enum(u32) {
        Flags = 0,
    },
    struct {},
);

pub const VisibilityFlagCdb = cdb.CdbTypeDecl(
    "ct_visibility_flag",
    enum(u32) {
        UUID = 0,
    },
    struct {},
);

pub const VisibilityFlagI = struct {
    pub const c_name = "ct_visibility_flag_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    name: [:0]const u8,
    hash: cetech1.StrId32 = undefined,
    uuid: u32,
    default: bool,

    pub fn implement(args: VisibilityFlagI) VisibilityFlagI {
        var result = args;
        result.hash = .fromStr(result.name);
        return result;
    }
};

pub fn fromName(name: cetech1.StrId32) ?VisibilityFlags {
    return api.fromName(name);
}
pub fn toName(visibility_flag: VisibilityFlags) ?cetech1.StrId32 {
    return api.toName(visibility_flag);
}
pub fn createFlags(names: []const cetech1.StrId32) ?VisibilityFlags {
    return api.createFlags(names);
}
pub fn createFlagsFromUuids(names: []const u32) ?VisibilityFlags {
    return api.createFlagsFromUuids(names);
}

pub const VisibilityFlagsApi = struct {
    fromName: *const fn (name: cetech1.StrId32) ?VisibilityFlags,
    toName: *const fn (visibility_flag: VisibilityFlags) ?cetech1.StrId32,
    createFlags: *const fn (names: []const cetech1.StrId32) ?VisibilityFlags,
    createFlagsFromUuids: *const fn (names: []const u32) ?VisibilityFlags,
};

pub var api: *const VisibilityFlagsApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, VisibilityFlagsApi).?;
}
