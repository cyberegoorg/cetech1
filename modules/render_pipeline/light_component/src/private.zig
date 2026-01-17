const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;

const public = @import("light_component.zig");
const editor_inspector = @import("editor_inspector");
const editor = @import("editor");
const transform = @import("transform");

const module_name = .light_component;

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
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _gpu: *const cetech1.gpu.GpuBackendApi = undefined;

var _inspector: *const editor_inspector.InspectorAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    light_type_properties_aspec: *editor_inspector.UiPropertyAspect = undefined,
    light_editor_component_aspect: *editor.EditorComponentAspect = undefined,
};
var _g: *G = undefined;

const light_c = ecs.ComponentI.implement(
    public.Light,
    .{
        .display_name = "Light",
        .cdb_type_hash = public.LightCdb.type_hash,
        .category = "Renderer",
        .on_instantiate = .inherit,
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const light = std.mem.bytesAsValue(public.Light, data);
            const type_str = public.LightCdb.readStr(_cdb, r, .Type) orelse "";
            const color_obj = public.LightCdb.readSubObj(_cdb, r, .Color);
            const radius = public.LightCdb.readValue(f32, _cdb, r, .Radius);
            const power = public.LightCdb.readValue(f32, _cdb, r, .Power);

            const angle_inner = public.LightCdb.readValue(f32, _cdb, r, .AngleInner);
            const angle_outer = public.LightCdb.readValue(f32, _cdb, r, .AngleOuter);

            const color: math.Color3f = if (color_obj) |c| cetech1.cdb_types.Color3fCdb.f.to(_cdb, c) else .white;
            light.* = public.Light{
                .type = std.meta.stringToEnum(public.LightType, type_str) orelse .Point,
                .color = color,
                .radius = radius,
                .power = power,
                .angle_inner = angle_inner,
                .angle_outer = angle_outer,
            };

            // log.debug("LIGHT: {any}", .{light.*});
        }

        pub fn debugdraw(gpu_backend: gpu.GpuBackend, dd: gpu.DDEncoder, world: ecs.World, entites: []const ecs.EntityId, data: []const u8, size: math.Vec2f) !void {
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
            _ = allocator; // autofix
            _ = obj; // autofix
            return std.fmt.bufPrintZ(buff, "{s}", .{coreui.Icons.Light});
        }
    },
);

var light_type_aspec = editor_inspector.UiPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = allocator; // autofix
        _ = args; // autofix
        const r = public.LightCdb.read(_cdb, obj).?;
        const type_str = public.LightCdb.readStr(_cdb, r, .Type) orelse "";
        var type_enum: public.LightType = std.meta.stringToEnum(public.LightType, type_str) orelse .Point;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        if (_coreui.comboFromEnum("", &type_enum)) {
            const w = public.LightCdb.write(_cdb, obj).?;
            try public.LightCdb.setStr(_cdb, w, .Type, @tagName(type_enum));
            try public.LightCdb.commit(_cdb, w);
        }
    }
});

// CDB
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // Light
        {
            const light_typeidx = try _cdb.addType(
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
                _cdb,
                db,
                _g.light_editor_component_aspect,
            );

            const light = public.Light{};

            const default_light = try _cdb.createObject(db, light_typeidx);
            const default_light_w = _cdb.writeObj(default_light).?;

            const default_color = try cetech1.cdb_types.Color3fCdb.createObject(_cdb, db);
            const default_color_w = _cdb.writeObj(default_color).?;

            try public.LightCdb.setStr(_cdb, default_light_w, .Type, "point");
            public.LightCdb.setValue(f32, _cdb, default_light_w, .Radius, light.radius);
            try public.LightCdb.setSubObj(_cdb, default_light_w, .Color, default_color_w);

            try _cdb.writeCommit(default_color_w);
            try _cdb.writeCommit(default_light_w);
            _cdb.setDefaultObject(default_light);

            try public.LightCdb.addPropertyAspect(
                editor_inspector.UiPropertyAspect,
                _cdb,
                db,
                .Type,
                _g.light_type_properties_aspec,
            );
        }
    }
});

const api = public.LightAPI{};

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _gpu = apidb.getZigApi(module_name, cetech1.gpu.GpuBackendApi).?;

    _inspector = apidb.getZigApi(module_name, editor_inspector.InspectorAPI).?;
    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;

    try apidb.setOrRemoveZigApi(module_name, public.LightAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &light_c, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.light_type_properties_aspec = try apidb.setGlobalVarValue(editor_inspector.UiPropertyAspect, module_name, "ct_light_component_type_embed_prop_aspect", light_type_aspec);
    _g.light_editor_component_aspect = try apidb.setGlobalVarValue(editor.EditorComponentAspect, module_name, "ct_light_editor_component_aspect", editor_light_component_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_light_component(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
