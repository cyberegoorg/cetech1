const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const graphvm = @import("graphvm");
const editor = @import("editor");

const public = @import("graphvm_script_component.zig");

const module_name = .graphvm_script_component;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;
var _graphvm: *const graphvm.GraphVMApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    editor_graphvm_component_aspect: *editor.EditorComponentAspect = undefined,
};
var _g: *G = undefined;

const logic_c = ecs.ComponentI.implement(
    public.GraphVMScriptComponent,
    .{
        .display_name = "GraphVM script",
        .cdb_type_hash = public.GraphVMScriptComponentCdb.type_hash,
        .category = "Scripting",
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.GraphVMScriptComponent, data);
            position.* = public.GraphVMScriptComponent{
                .graph = public.GraphVMScriptComponentCdb.readSubObj(_cdb, r, .Graph) orelse .{},
            };
        }
    },
);

const logic_instance_c = ecs.ComponentI.implement(
    public.GraphVMScriptComponentInstance,
    .{
        .display_name = "GraphVM logic instance ",
    },
    struct {
        pub fn onDestroy(components: []public.GraphVMScriptComponentInstance) !void {
            for (components) |c| {
                if (c.instance.isValid()) {
                    _graphvm.destroyInstance(c.instance);
                }
            }
        }

        pub fn onMove(dsts: []public.GraphVMScriptComponentInstance, srcs: []public.GraphVMScriptComponentInstance) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.instance = .{};
            }
        }

        pub fn onRemove(manager: ?*anyopaque, iter: *ecs.Iter) !void {
            _ = manager;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);
            const components = iter.field(public.GraphVMScriptComponentInstance, 0).?;

            // TODO: real multi call
            try _graphvm.executeNode(alloc, toContanerSlice(components), graphvm.EVENT_SHUTDOWN_NODE_TYPE, .{ .use_tasks = false });
        }
    },
);

const editor_graphvm_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.CoreIcons.FA_GEARS});
        }
    },
);

const init_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "logic_component.init",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(public.GraphVMScriptComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.GraphVMScriptComponent), .inout = .In },
        },
        .orderByComponent = ecs.id(public.GraphVMScriptComponent),
    },
    struct {
        pub fn orderByCallback(e1: ecs.EntityId, c1: *const anyopaque, e2: ecs.EntityId, c2: *const anyopaque) callconv(.c) i32 {
            const ci1: *const public.GraphVMScriptComponent = @ptrCast(@alignCast(c1));
            const ci2: *const public.GraphVMScriptComponent = @ptrCast(@alignCast(c2));
            _ = e1;
            _ = e2;

            return @truncate(ci1.*.graph.toI64() - ci2.*.graph.toI64());
        }

        pub fn tick(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            var all_instances = cetech1.ArrayList(graphvm.GraphInstance){};
            defer all_instances.deinit(alloc);

            var all_ents = cetech1.ArrayList(ecs.EntityId){};
            defer all_ents.deinit(alloc);

            while (it.next()) {
                const ents = it.entities();

                const render_components = it.field(public.GraphVMScriptComponent, 1).?;

                // TODO: SHIT
                if (render_components[0].graph.isEmpty()) return;

                const instances = try alloc.alloc(graphvm.GraphInstance, ents.len);
                defer alloc.free(instances);

                try _graphvm.createInstances(alloc, render_components[0].graph, instances);

                try all_instances.appendSlice(alloc, instances);
                try all_ents.appendSlice(alloc, ents);

                for (0..it.count()) |idx| {
                    _ = world.setComponent(public.GraphVMScriptComponentInstance, ents[idx], &.{ .instance = instances[idx] });
                }
            }

            if (all_instances.items.len > 0) {
                try _graphvm.buildInstances(alloc, all_instances.items);

                try _graphvm.setInstancesContext(all_instances.items, ecs.ECS_WORLD_CONTEXT, world.ptr);

                for (all_ents.items, 0..) |ent, idx| {
                    try _graphvm.setInstanceContext(all_instances.items[idx], ecs.ECS_ENTITY_CONTEXT, @ptrFromInt(ent));
                }

                try _graphvm.executeNode(alloc, all_instances.items, graphvm.EVENT_INIT_NODE_TYPE, .{
                    .use_tasks = false,
                    .sort = false,
                });
            }
        }
    },
);

pub fn toContanerSlice(from: anytype) []const graphvm.GraphInstance {
    var containers: []const graphvm.GraphInstance = undefined;
    containers.ptr = @ptrCast(@alignCast(from.ptr));
    containers.len = from.len;
    return containers;
}

const tick_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "logic_component.tick",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(public.GraphVMScriptComponentInstance), .inout = .In },
            .{ .id = ecs.id(public.GraphVMScriptComponent), .inout = .In },
        },
        .orderByComponent = ecs.id(public.GraphVMScriptComponentInstance),
    },
    struct {
        pub fn orderByCallback(e1: ecs.EntityId, c1: *const anyopaque, e2: ecs.EntityId, c2: *const anyopaque) callconv(.c) i32 {
            const ci1: *const public.GraphVMScriptComponentInstance = @ptrCast(@alignCast(c1));
            const ci2: *const public.GraphVMScriptComponentInstance = @ptrCast(@alignCast(c2));
            _ = e1;
            _ = e2;

            return @truncate(ci1.*.instance.graph.toI64() - ci2.*.instance.graph.toI64());
        }

        pub fn tick(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            var all_instances = cetech1.ArrayList(graphvm.GraphInstance){};
            defer all_instances.deinit(alloc);

            while (it.next()) {
                // const ents = it.entities();

                const render_component = it.field(public.GraphVMScriptComponentInstance, 0).?;
                const instances = toContanerSlice(render_component);
                try all_instances.appendSlice(alloc, instances);
            }

            // world.deferSuspend();
            if (all_instances.items.len > 0) {
                // log.debug("Tick {any}", .{all_instances.items});
                try _graphvm.setInstancesContext(all_instances.items, ecs.ECS_WORLD_CONTEXT, world.ptr);
                try _graphvm.executeNode(alloc, all_instances.items, graphvm.EVENT_TICK_NODE_TYPE, .{
                    .use_tasks = false,
                    .sort = false,
                });
            }
            // world.deferResume();
        }
    },
);

const deleted_observer_i = ecs.ObserverI.implement(
    .{
        .name = "graphvm_logic.deleted_observer",
        .query = &.{
            .{ .id = ecs.id(public.GraphVMScriptComponent), .inout = .In },
            .{ .id = ecs.id(public.GraphVMScriptComponentInstance), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnRemove},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const ents = it.entities();

            for (0..it.count()) |idx| {
                world.removeComponent(public.GraphVMScriptComponentInstance, ents[idx]);
            }
        }
    },
);

const change_observer_i = ecs.ObserverI.implement(
    .{
        .name = "graphvm_logic.change_observer",
        .query = &.{
            .{ .id = ecs.id(public.GraphVMScriptComponent), .inout = .In },
            .{ .id = ecs.id(public.GraphVMScriptComponentInstance), .inout = .InOutFilter },
        },
        .events = &.{ecs.OnSet},
    },
    struct {
        pub fn iterate(world: ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            const logic_components = it.field(public.GraphVMScriptComponent, 0).?;
            const instance_components = it.field(public.GraphVMScriptComponentInstance, 1).?;

            const ents = it.entities();

            for (0..it.count()) |idx| {
                if (instance_components[idx].instance.graph.eql(logic_components[idx].graph)) continue;

                _graphvm.destroyInstance(instance_components[idx].instance);
                var instances: [1]graphvm.GraphInstance = undefined;

                try _graphvm.createInstances(alloc, logic_components[idx].graph, &instances);

                try _graphvm.buildInstances(alloc, &instances);

                _ = world.setComponent(public.GraphVMScriptComponentInstance, ents[idx], &public.GraphVMScriptComponentInstance{ .instance = instances[idx] });

                try _graphvm.setInstanceContext(instances[idx], ecs.ECS_WORLD_CONTEXT, world.ptr);
                try _graphvm.setInstanceContext(instances[idx], ecs.ECS_ENTITY_CONTEXT, @ptrFromInt(ents[idx]));

                // log.debug("changed logic: {d} {any} {any}", .{ idx, logic_components, instance_components });
            }
        }
    },
);

// Foo cdb type decl

// Register all cdb stuff in this method

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // EntityLogicComponentCdb
        {
            _ = try _cdb.addType(
                db,
                public.GraphVMScriptComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.GraphVMScriptComponentCdb.propIdx(.Graph),
                        .name = "graph",
                        .type = cdb.PropType.SUBOBJECT,
                        .type_hash = graphvm.GraphTypeCdb.type_hash,
                    },
                },
            );

            try public.GraphVMScriptComponentCdb.addAspect(
                editor.EditorComponentAspect,
                _cdb,
                db,
                _g.editor_graphvm_component_aspect,
            );
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _graphvm = apidb.getZigApi(module_name, graphvm.GraphVMApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_instance_c, load);

    // Systems
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_logic_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &tick_logic_system_i, load);

    // Observers
    try apidb.implOrRemove(module_name, ecs.ObserverI, &change_observer_i, load);
    try apidb.implOrRemove(module_name, ecs.ObserverI, &deleted_observer_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});
    _g.editor_graphvm_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_light_editor_component_aspect", editor_graphvm_component_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_graphvm_script_component(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
