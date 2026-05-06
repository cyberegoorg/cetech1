const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const apidb = cetech1.apidb;
const tempalloc = cetech1.tempalloc;
const assetdb = cetech1.assetdb;
const luauvm = cetech1.scripting.luauvm;

const public = cetech1.scripting.luauvm_script_component;

const module_name = .luauvm_script_component;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};

// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

const logic_c = ecs.ComponentI.implement(
    public.LuauScriptComponent,
    .{
        .display_name = "Luau script",
        .cdb_type_hash = public.LuauScriptComponentCdb.type_hash,
        .category = "Scripting",
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.LuauScriptComponent, data);
            position.* = public.LuauScriptComponent{
                .script = public.LuauScriptComponentCdb.readRef(r, .Script) orelse .{},
            };
        }
    },
);

pub const LuauScriptComponentInstance = extern struct {
    instance: ?*luauvm.Lua = null,
    instance_thread: ?*luauvm.Lua = null,
    tick_ref: i32 = std.math.minInt(i32),
};

const logic_instance_c = ecs.ComponentI.implement(
    LuauScriptComponentInstance,
    .{
        .display_name = "Luau logic instance ",
    },
    struct {
        pub fn onDestroy(components: []LuauScriptComponentInstance) !void {
            for (components) |c| {
                if (c.instance_thread) |inst| {
                    if (c.tick_ref != std.math.minInt(i32)) {
                        inst.unref(c.tick_ref);
                    }
                }

                if (c.instance) |inst| {
                    var l: *luauvm.Lua = @ptrCast(inst);
                    l.destroy();
                }
            }
        }

        pub fn onMove(dsts: []LuauScriptComponentInstance, srcs: []LuauScriptComponentInstance) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.instance = null;
                src.instance_thread = null;
            }
        }

        pub fn onRemove(manager: ?*anyopaque, iter: *ecs.Iter) !void {
            _ = manager;
            _ = iter;

            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);
        }
    },
);

const init_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "luau_script_component.init",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(LuauScriptComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.LuauScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;
            const ents = it.entities();

            const render_components = it.field(public.LuauScriptComponent, 1).?;
            for (0..it.count()) |idx| {
                const c = render_components[idx];
                if (c.script.isEmpty()) continue;

                const scipt_r = luauvm.LuauScriptCdb.read(c.script).?;
                const bytecode = luauvm.LuauScriptCdb.readBlob(scipt_r, .Bytecode);

                const lua_state = try luauvm.Lua.create(_allocator);
                lua_state.gcStop();

                errdefer lua_state.destroy();
                lua_state.sandbox();

                const l_thread = lua_state.newThread();
                l_thread.sandboxThread();

                // TODO: chunkname
                try l_thread.loadBytecode("", bytecode);
                l_thread.protectedCall(.{}) catch |err| {
                    switch (err) {
                        error.LuaRuntime => {
                            const err_msg = try l_thread.toString(-1);
                            log.err("{s}", .{err_msg});
                        },
                        else => return err,
                    }
                };

                const tick_ref: i32 = blk: {
                    _ = l_thread.getGlobal("tick") catch |err| {
                        if (err == error.LuaError) break :blk std.math.minInt(i32);
                    };

                    const ref_idx = l_thread.ref(-1);
                    l_thread.pop(1);
                    break :blk ref_idx;
                };

                _ = world.setComponent(LuauScriptComponentInstance, ents[idx], &.{
                    .instance = lua_state,
                    .instance_thread = l_thread,
                    .tick_ref = tick_ref,
                });
            }
        }
    },
);

const tick_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "luau_component.tick",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(LuauScriptComponentInstance), .inout = .In },
            .{ .id = ecs.id(public.LuauScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            const ents = it.entities();
            for (ents, 0..) |ent, idx| {
                const inst = it.field(LuauScriptComponentInstance, 0).?;
                const l = inst[idx].instance_thread.?;

                if (inst[idx].tick_ref != std.math.minInt(i32)) {
                    _ = l.autoCallRef(?void, inst[idx].tick_ref, .{ world, ent, dt }) catch |err| {
                        switch (err) {
                            error.LuaRuntime => {
                                const err_msg = try l.toString(-1);
                                log.err("{s}", .{err_msg});
                            },
                            else => return err,
                        }
                    };
                }
            }
        }
    },
);

const gc_system_i = ecs.SystemI.implement(
    .{
        .name = "luau_component.gc",
        .multi_threaded = true,
        .phase = ecs.PostFrame,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(LuauScriptComponentInstance), .inout = .In },
            .{ .id = ecs.id(public.LuauScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            const ents = it.entities();
            for (ents, 0..) |_, idx| {
                const inst = it.field(LuauScriptComponentInstance, 0).?;
                if (inst[idx].instance) |l| {
                    l.gcStep(0);
                }
            }
        }
    },
);
// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        {
            _ = try cdb.addType(
                db,
                public.LuauScriptComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.LuauScriptComponentCdb.propIdx(.Script),
                        .name = "script",
                        .type = cdb.PropType.REFERENCE,
                        .type_hash = luauvm.LuauScriptCdb.type_hash,
                    },
                },
            );
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;

    // basic
    _allocator = allocator;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_instance_c, load);

    // Systems
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_logic_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &tick_logic_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &gc_system_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_luauvm_script_component(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
