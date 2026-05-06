const std = @import("std");

const cetech1 = @import("cetech1");
const luauvm = cetech1.scripting.luauvm;

const zlua = @import("zlua");

pub const StrId = struct {
    pub const ApiName = "strid";

    pub const strId32 = cetech1.strId32;
    pub const strId64 = cetech1.strId64;
};

pub const Transform = struct {
    pub const ApiName = "transform";

    pub fn get(word: *cetech1.ecs.World, ent: cetech1.ecs.EntityId) ?cetech1.math.Transform {
        const res = word.getComponent(cetech1.transform.LocalTransformComponent, ent) orelse return null;
        return res.local;
    }

    pub fn set(word: *cetech1.ecs.World, ent: cetech1.ecs.EntityId, t: cetech1.math.Transform) void {
        _ = word.setComponent(cetech1.transform.LocalTransformComponent, ent, &.{ .local = t });
    }
};

const all_apis = .{
    StrId,
    Transform,
};

pub fn openApis(l: *luauvm.Lua) void {
    inline for (all_apis) |api| {
        l.registerLuaApi(api.ApiName, api);
    }
}

pub fn main(init: std.process.Init) !void {
    const output_file_path = std.mem.sliceTo(init.minimal.args.vector[1], 0);
    try zlua.define(init.io, std.heap.c_allocator, output_file_path, &all_apis);
}
