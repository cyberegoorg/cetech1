const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const public = cetech1.scripting.native_script_component;
const editor_inspector = cetech1.editor.inspector;
const editor = cetech1.editor;

const module_name = .native_script_component;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;

// Global state that can surive hot-reload
const G = struct {
    camera_type_properties_aspec: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
    light_editor_component_aspect: *editor.EditorComponentAspect = undefined,
};
var _g: *G = undefined;

const logic_c = ecs.ComponentI.implement(
    public.NativeScriptComponent,
    .{
        .display_name = "Native logic",
        .cdb_type_hash = public.NativeScriptComponentCdb.type_hash,
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

            const position = std.mem.bytesAsValue(public.NativeScriptComponent, data);
            position.* = public.NativeScriptComponent{
                .native_script = if (public.NativeScriptComponentCdb.readStr(r, .NativeScript)) |s| cetech1.strId32(s) else .{},
            };
        }
    },
);

const logic_instance_c = ecs.ComponentI.implement(
    public.NativeScriptComponentInstance,
    .{
        .display_name = "Native logic instance",
    },
    struct {
        pub fn onDestroy(components: []public.NativeScriptComponentInstance) !void {
            for (components) |c| {
                _ = c;
            }
        }

        pub fn onMove(dsts: []public.NativeScriptComponentInstance, srcs: []public.NativeScriptComponentInstance) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.inst = null;
            }
        }

        pub fn onRemove(manager: ?*anyopaque, iter: *ecs.Iter) !void {
            _ = manager;

            // const alloc = try tempalloc.create();
            // defer tempalloc.destroy(alloc);
            const components = iter.field(public.NativeScriptComponentInstance, 0).?;

            for (components) |component| {
                try component.iface.shutdown(_allocator, component.inst);
            }
        }
    },
);

const init_native_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "native_script_component.init",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(public.NativeScriptComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.NativeScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);

            const ents = it.entities();
            const logic_components = it.field(public.NativeScriptComponent, 1).?;
            for (ents, logic_components) |ent, component| {
                if (!component.native_script.isEmpty()) {
                    if (findScriptById(alloc, component.native_script)) |iface| {
                        _ = world.setComponent(public.NativeScriptComponentInstance, ent, &public.NativeScriptComponentInstance{
                            .iface = iface,
                            .inst = try iface.init(_allocator, ent),
                        });
                    }
                }
            }
        }
    },
);

const tick_native_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "native_script_component.tick",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(public.NativeScriptComponentInstance), .inout = .In },
            .{ .id = ecs.id(public.NativeScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            // const alloc = try tempalloc.create();
            // defer tempalloc.destroy(alloc);

            const ents = it.entities();
            const components = it.field(public.NativeScriptComponentInstance, 0).?;

            _ = ents;

            for (components) |component| {
                try component.iface.update(component.inst);
            }
        }
    },
);

var native_script_type_aspec = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = prop_idx;
        _ = args;
        const r = public.NativeScriptComponentCdb.read(obj).?;
        const script_id_str = public.NativeScriptComponentCdb.readStr(r, .NativeScript) orelse "";

        var all_values = cetech1.ArrayList(u8).empty;
        defer all_values.deinit(allocator);

        try all_values.appendSlice(allocator, "None");
        try all_values.appendSlice(allocator, "\x00");

        var cur_idx: i32 = 0;

        const impls = apidb.getImpl(allocator, public.NativeScriptI) catch undefined;
        defer allocator.free(impls);
        for (impls, 0..) |iface, idx| {
            if (iface.id.eql(cetech1.strId32(script_id_str))) cur_idx = @intCast(idx + 1);

            try all_values.appendSlice(allocator, iface.display_name);
            try all_values.appendSlice(allocator, "\x00");
        }

        coreui.setNextItemWidth(-1.0);
        if (coreui.combo("", .{
            .current_item = &cur_idx,
            .items_separated_by_zeros = try all_values.toOwnedSliceSentinel(allocator, 0),
        })) {
            const w = public.NativeScriptComponentCdb.write(obj).?;
            if (cur_idx > 0) {
                try public.NativeScriptComponentCdb.setStr(w, .NativeScript, impls[@intCast(cur_idx - 1)].name);
            } else {
                try public.NativeScriptComponentCdb.setStr(w, .NativeScript, "");
            }
            try public.NativeScriptComponentCdb.commit(w);
        }
    }
});

fn findScriptById(allocator: std.mem.Allocator, id: cetech1.StrId32) ?*const public.NativeScriptI {
    const impls = apidb.getImpl(allocator, public.NativeScriptI) catch undefined;
    defer allocator.free(impls);
    for (impls) |iface| {
        if (iface.id.eql(id)) return iface;
    }
    return null;
}

// Register all cdb stuff in this method

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // EntityLogicComponentCdb
        {
            _ = try cdb.addType(
                db,
                public.NativeScriptComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.NativeScriptComponentCdb.propIdx(.NativeScript),
                        .name = "native_script",
                        .type = cdb.PropType.STR,
                    },
                },
            );

            try public.NativeScriptComponentCdb.addPropertyAspect(
                editor_inspector.UiInspectorPropertyValueAspect,

                db,
                .NativeScript,
                _g.camera_type_properties_aspec,
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

    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_instance_c, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_native_logic_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &tick_native_logic_system_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.camera_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_native_script_embed_prop_aspect", native_script_type_aspec);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_native_script_component(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
