const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;
const render_graph = cetech1.render_graph;
const ecs = cetech1.ecs;
const transform = cetech1.transform;
const renderer = cetech1.renderer;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const graphvm = @import("graphvm");

const public = @import("entity_logic_component.zig");

const module_name = .entity_logic_component;

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
var _gpu: *const gpu.GpuApi = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

const init_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "logic_component.init",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(public.EntityLogicComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.EntityLogicComponent), .inout = .In },
        },
    },
    struct {
        pub fn update(world: ecs.World, it: *ecs.Iter) !void {
            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            //const world = it.getWorld();
            const ents = it.entities();
            const logic_component = it.field(public.EntityLogicComponent, 1).?;

            const instances = try alloc.alloc(graphvm.GraphInstance, logic_component.len);
            defer alloc.free(instances);

            // TODO: SHIT
            if (logic_component[0].graph.isEmpty()) return;

            try _graphvm.createInstances(alloc, logic_component[0].graph, instances);

            try _graphvm.buildInstances(alloc, instances);

            for (0..it.count()) |idx| {
                _ = world.setId(public.EntityLogicComponentInstance, ents[idx], &public.EntityLogicComponentInstance{ .graph_container = instances[idx] });

                try _graphvm.setInstanceContext(instances[idx], ecs.ECS_WORLD_CONTEXT, world.ptr);
                try _graphvm.setInstanceContext(instances[idx], ecs.ECS_ENTITY_CONTEXT, @ptrFromInt(ents[idx]));
            }

            // world.deferSuspend();
            //_ = world.deferBegin();
            try _graphvm.executeNode(alloc, instances, graphvm.EVENT_INIT_NODE_TYPE, .{ .use_tasks = false });
            //_ = world.deferEnd();
            // world.deferResume();
        }
    },
);

pub fn toContanerSlice(from: anytype) []const graphvm.GraphInstance {
    var containers: []const graphvm.GraphInstance = undefined;
    containers.ptr = @alignCast(@ptrCast(from.ptr));
    containers.len = from.len;
    return containers;
}

const tick_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "logic_component.tick",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .query = &.{
            .{ .id = ecs.id(public.EntityLogicComponentInstance), .inout = .In },
            .{ .id = ecs.id(public.EntityLogicComponent), .inout = .In },
        },
    },
    struct {
        pub fn update(world: ecs.World, it: *ecs.Iter) !void {
            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            //const world = it.getWorld();
            const render_component = it.field(public.EntityLogicComponentInstance, 0).?;

            for (0..it.count()) |idx| {
                try _graphvm.setInstanceContext(toContanerSlice(render_component)[idx], ecs.ECS_WORLD_CONTEXT, world.ptr);
            }

            // world.deferSuspend();
            try _graphvm.executeNode(alloc, toContanerSlice(render_component), graphvm.EVENT_TICK_NODE_TYPE, .{ .use_tasks = false });
            // world.deferResume();
        }
    },
);

const logic_c = ecs.ComponentI.implement(
    public.EntityLogicComponent,
    public.EntityLogicComponentCdb.type_hash,
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
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.EntityLogicComponent, data);
            position.* = public.EntityLogicComponent{
                .graph = public.EntityLogicComponentCdb.readSubObj(_cdb, r, .graph) orelse .{},
            };
        }
    },
);

const logic_instance_c = ecs.ComponentI.implement(
    public.EntityLogicComponentInstance,
    null,
    struct {
        pub fn onDestroy(components: []public.EntityLogicComponentInstance) !void {
            for (components) |c| {
                if (c.graph_container.isValid()) {
                    _graphvm.destroyInstance(c.graph_container);
                }
            }
        }

        pub fn onMove(dsts: []public.EntityLogicComponentInstance, srcs: []public.EntityLogicComponentInstance) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.graph_container = .{};
            }
        }

        pub fn onRemove(iter: *ecs.IterO) !void {
            var it = _ecs.toIter(iter);
            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);
            const components = it.field(public.EntityLogicComponentInstance, 0).?;

            // TODO: real multi call
            try _graphvm.executeNode(alloc, toContanerSlice(components), graphvm.EVENT_SHUTDOWN_NODE_TYPE, .{ .use_tasks = false });
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
                public.EntityLogicComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.EntityLogicComponentCdb.propIdx(.graph),
                        .name = "graph",
                        .type = cdb.PropType.SUBOBJECT,
                        .type_hash = graphvm.GraphType.type_hash,
                    },
                },
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
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);

    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_c, true);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_instance_c, true);
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_logic_system_i, true);
    try apidb.implOrRemove(module_name, ecs.SystemI, &tick_logic_system_i, true);

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_entity_logic_component(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
