const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;
const gpu_dd = cetech1.gpu_dd;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;

const editor_inspector = cetech1.editor.inspector;
const editor = cetech1.editor;
const editor_tabs = cetech1.editor.tabs;
const transform = cetech1.transform;

const public = cetech1.renderer_pipeline.light_component;

const module_name = .light_component;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

const tempalloc = cetech1.tempalloc;
const profiler = cetech1.profiler;

// Global state that can surive hot-reload
const G = struct {
    light_type_properties_aspec: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
    light_obj_aspec: *editor_inspector.UiInspectorObjAspect = undefined,
    light_editor_component_aspect: *editor.EditorComponentAspect = undefined,
};
var _g: *G = undefined;

const light_c = ecs.ComponentI.implement(
    public.Light,
    .{
        .display_name = "Light",
        .cdb_type_hash = public.LightCdb.type_hash,
        .category = "Renderer",
        .on_instantiate = .Inherit,
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const light = std.mem.bytesAsValue(public.Light, data);
            const color_obj = public.LightCdb.readSubObj(r, .Color);
            const radius = public.LightCdb.readValue(f32, r, .Radius);
            const power = public.LightCdb.readValue(f32, r, .Power);

            const angle_inner = public.LightCdb.readValue(f32, r, .AngleInner);
            const angle_outer = public.LightCdb.readValue(f32, r, .AngleOuter);

            const color: math.Color3f = if (color_obj) |c| cetech1.cdb_types.Color3fCdb.f.to(c) else .white;
            light.* = public.Light{
                .type = public.LightCdb.readStrEnum(public.LightType, r, .Type, .Point),
                .color = color,
                .radius = radius,
                .power = power,
                .angle_inner = angle_inner,
                .angle_outer = angle_outer,
            };

            // log.debug("LIGHT: {any}", .{light.*});
        }

        pub fn debugdraw(gpu_backend: gpu.GpuBackend, dd: gpu_dd.Encoder, world: *ecs.World, entites: []const ecs.EntityId, data: []const u8, size: math.Vec2f) !void {
            _ = size;
            _ = gpu_backend;

            var lights: []const public.Light = undefined;
            lights.ptr = @ptrCast(@alignCast(data.ptr));
            lights.len = data.len / @sizeOf(public.Light);

            for (entites, lights) |ent, light| {
                const wt = world.getComponent(transform.WorldTransformComponent, ent) orelse continue;

                const position = wt.world.position;

                const dir = wt.world.getAxisZ();

                dd.setColor(.fromColor3f(light.color));

                switch (light.type) {
                    .Point => {
                        dd.drawCircleAxis(.X, position, light.radius, 0);
                        dd.drawCircleAxis(.Y, position, light.radius, 0);
                        dd.drawCircleAxis(.Z, position, light.radius, 0);
                    },
                    .Spot => {
                        const end = math.Vec3f.mulAdd(dir, .splat(light.radius), position);
                        {
                            dd.setWireframe(true);
                            defer dd.setWireframe(false);
                            dd.drawCone(end, position, std.math.tan(std.math.degreesToRadians(light.angle_outer)) * light.radius);
                            dd.drawCone(end, position, std.math.tan(std.math.degreesToRadians(light.angle_inner)) * light.radius);
                        }
                    },
                    .Direction => {
                        {
                            dd.pushTransform(wt.world.toMat());
                            defer dd.popTransform();

                            const r = 0.1;
                            dd.drawCylinder(.{}, .{ .z = light.radius }, r);
                            dd.drawCone(.{ .z = light.radius }, .{ .z = light.radius + 0.5 }, r);
                        }
                    },
                }
            }
        }
    },
);

const editor_light_component_aspect = editor.EditorComponentAspect.implement(
    .{},
    struct {
        pub fn uiIcons(
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
        ) ![:0]const u8 {
            _ = allocator;
            _ = obj;
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Light});
        }
    },
);

var light_type_aspec = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = prop_idx;
        _ = allocator;
        _ = args;
        const r = public.LightCdb.read(obj).?;

        var type_enum = public.LightCdb.readStrEnum(public.LightType, r, .Type, .Point);

        coreui.setNextItemWidth(-1.0);
        if (coreui.comboFromEnum("##select_light_type", &type_enum)) {
            const w = public.LightCdb.write(obj).?;
            try public.LightCdb.setStr(w, .Type, @tagName(type_enum));
            try public.LightCdb.commit(w);
        }
    }
});

var light_obj_aspec = editor_inspector.UiInspectorObjAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        tab: *editor_tabs.TabO,
        top_level_obj: cdb.ObjId,
        obj: cdb.ObjId,
        depth: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = depth; // autofix

        const r = public.LightCdb.read(obj).?;

        const type_enum = public.LightCdb.readStrEnum(public.LightType, r, .Type, .Point);

        if (editor_inspector.beginPropTable("Inspector")) {
            defer editor_inspector.endPropTabel();

            try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.Type), null, args);
            try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.Power), null, args);
            try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.Color), null, args);

            switch (type_enum) {
                .Point => {
                    try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.Radius), null, args);
                },
                .Spot => {
                    try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.Radius), "Lenght", args);
                    try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.AngleInner), null, args);
                    try editor_inspector.uiProperty(allocator, tab, top_level_obj, obj, public.LightCdb.propIdx(.AngleOuter), null, args);
                },
                .Direction => {},
            }
        }
    }
});
// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // Light
        {
            const light_typeidx = try cdb.addType(
                db,
                public.LightCdb.name,
                &[_]cdb.PropDef{
                    .{ .prop_idx = public.LightCdb.propIdx(.Type), .name = "type", .type = .STR },
                    .{ .prop_idx = public.LightCdb.propIdx(.Radius), .name = "radius", .type = .F32 },
                    .{ .prop_idx = public.LightCdb.propIdx(.Color), .name = "color", .type = .SUBOBJECT, .type_hash = cetech1.cdb_types.Color3fCdb.type_hash },
                    .{ .prop_idx = public.LightCdb.propIdx(.Power), .name = "power", .type = .F32 },
                    .{ .prop_idx = public.LightCdb.propIdx(.AngleInner), .name = "angle_inner", .type = .F32 },
                    .{ .prop_idx = public.LightCdb.propIdx(.AngleOuter), .name = "angle_outer", .type = .F32 },
                },
            );

            try public.LightCdb.addAspect(
                editor.EditorComponentAspect,

                db,
                _g.light_editor_component_aspect,
            );

            const light = public.Light{};

            const default_light = try cdb.createObject(db, light_typeidx);
            const default_light_w = cdb.writeObj(default_light).?;

            const default_color = try cetech1.cdb_types.Color3fCdb.createObject(db);
            const default_color_w = cdb.writeObj(default_color).?;

            try public.LightCdb.setStr(default_light_w, .Type, "point");
            public.LightCdb.setValue(f32, default_light_w, .Radius, light.radius);
            try public.LightCdb.setSubObj(default_light_w, .Color, default_color_w);

            try cdb.writeCommit(default_color_w);
            try cdb.writeCommit(default_light_w);
            cdb.setDefaultObject(default_light);

            try public.LightCdb.addPropertyAspect(
                editor_inspector.UiInspectorPropertyValueAspect,

                db,
                .Type,
                _g.light_type_properties_aspec,
            );

            try public.LightCdb.addAspect(
                editor_inspector.UiInspectorObjAspect,

                db,
                _g.light_obj_aspec,
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
    try apidb.implOrRemove(module_name, ecs.ComponentI, &light_c, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.light_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_light_component_type_embed_prop_aspect", light_type_aspec);
    _g.light_obj_aspec = try apidb.setGlobalVarValue(editor_inspector.UiInspectorObjAspect, module_name, "ct_light_component_obj_aspect", light_obj_aspec);
    _g.light_editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_light_editor_component_aspect", editor_light_component_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_light_component(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
