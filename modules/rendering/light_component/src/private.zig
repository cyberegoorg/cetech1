const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const render_viewport = @import("render_viewport");
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const public = @import("light_component.zig");
const editor_inspector = @import("editor_inspector");
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
var _gpu: *const cetech1.gpu.GpuApi = undefined;

var _inspector: *const editor_inspector.InspectorAPI = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

// Global state that can surive hot-reload
const G = struct {
    light_type_properties_aspec: *editor_inspector.UiPropertyAspect = undefined,
};
var _g: *G = undefined;

const srgb = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn from3f(color: [3]f32) srgb {
        return .{
            .r = @intFromFloat(color[0] * 255),
            .g = @intFromFloat(color[1] * 255),
            .b = @intFromFloat(color[2] * 255),
            .a = 255,
        };
    }

    pub fn from4f(color: [4]f32) srgb {
        return .{
            .r = @intFromFloat(color[0] * 255),
            .g = @intFromFloat(color[1] * 255),
            .b = @intFromFloat(color[2] * 255),
            .a = @intFromFloat(color[3] * 255),
        };
    }
};

const light_c = ecs.ComponentI.implement(
    public.Light,
    .{
        .cdb_type_hash = public.LightCdb.type_hash,
        .category = "Renderer",
    },
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

        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator; // autofix

            const r = _cdb.readObj(obj) orelse return;

            const light = std.mem.bytesAsValue(public.Light, data);
            const type_str = public.LightCdb.readStr(_cdb, r, .Type) orelse "point";
            const color_obj = public.LightCdb.readSubObj(_cdb, r, .Color);
            const radius = public.LightCdb.readValue(f32, _cdb, r, .Radius);
            const power = public.LightCdb.readValue(f32, _cdb, r, .Power);

            const angle_inner = public.LightCdb.readValue(f32, _cdb, r, .AngleInner);
            const angle_outer = public.LightCdb.readValue(f32, _cdb, r, .AngleOuter);

            const color = if (color_obj) |c| cetech1.cdb_types.Color3f.f.toSlice(_cdb, c) else .{ 1.0, 1.0, 1.0 };
            light.* = public.Light{
                .type = std.meta.stringToEnum(public.LightType, type_str) orelse .point,
                .color = color,
                .radius = radius,
                .power = power,
                .angle_inner = angle_inner,
                .angle_outer = angle_outer,
            };

            // log.debug("LIGHT: {any}", .{light.*});
        }

        pub fn debugdraw(dd: gpu.DDEncoder, world: ecs.World, entites: []const ecs.EntityId, data: []const u8, size: [2]f32) !void {
            _ = size;
            var lights: []const public.Light = undefined;
            lights.ptr = @ptrCast(@alignCast(data.ptr));
            lights.len = data.len / @sizeOf(public.Light);

            for (entites, lights) |ent, light| {
                const wt = world.getComponent(transform.WorldTransform, ent) orelse continue;

                const position = zm.util.getTranslationVec(wt.mtx);
                const pos_array = zm.vecToArr3(position);

                const dir = zm.normalize3(zm.util.getAxisZ(wt.mtx));

                dd.setColor(@bitCast(srgb.from3f(light.color)));

                switch (light.type) {
                    .point => {
                        dd.drawCircleAxis(.X, pos_array, light.radius, 0);
                        dd.drawCircleAxis(.Y, pos_array, light.radius, 0);
                        dd.drawCircleAxis(.Z, pos_array, light.radius, 0);
                    },
                    .spot => {
                        const end = zm.mulAdd(dir, zm.splat(zm.Vec, light.radius), position);
                        const end_array = zm.vecToArr3(end);
                        {
                            dd.setWireframe(true);
                            defer dd.setWireframe(false);
                            dd.drawCone(end_array, pos_array, std.math.tan(std.math.degreesToRadians(light.angle_outer)) * light.radius);
                            dd.drawCone(end_array, pos_array, std.math.tan(std.math.degreesToRadians(light.angle_inner)) * light.radius);
                        }
                    },
                    .direction => {
                        {
                            dd.setTransform(&zm.matToArr(wt.mtx));
                            defer dd.popTransform();

                            const r = 0.1;
                            dd.drawCylinder(.{ 0, 0, 0 }, .{ 0, 0, light.radius }, r);
                            dd.drawCone(.{ 0, 0, light.radius }, .{ 0, 0, light.radius + 0.5 }, r);
                        }
                    },
                }
            }
        }
    },
);

// TODO: generic
const enum_str = "point\x00spot\x00direction\x00";
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
        const type_str = public.LightCdb.readStr(_cdb, r, .Type) orelse "point";
        const type_enum: public.LightType = std.meta.stringToEnum(public.LightType, type_str) orelse .point;

        try _inspector.uiPropInputBegin(obj, prop_idx, true);
        defer _inspector.uiPropInputEnd();

        var cur_idx: i32 = @intCast(@intFromEnum(type_enum));
        if (_coreui.combo("", .{
            .current_item = &cur_idx,
            .items_separated_by_zeros = enum_str,
        })) {
            const w = public.LightCdb.write(_cdb, obj).?;
            const enum_v: public.LightType = @enumFromInt(cur_idx);
            try public.LightCdb.setStr(_cdb, w, .Type, @tagName(enum_v));
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
                    .{ .prop_idx = public.LightCdb.propIdx(.Color), .name = "color", .type = .SUBOBJECT, .type_hash = cetech1.cdb_types.Color3f.type_hash },
                    .{ .prop_idx = public.LightCdb.propIdx(.Power), .name = "power", .type = .F32 },
                    .{ .prop_idx = public.LightCdb.propIdx(.AngleInner), .name = "angle_inner", .type = .F32 },
                    .{ .prop_idx = public.LightCdb.propIdx(.AngleOuter), .name = "angle_outer", .type = .F32 },
                },
            );

            const light = public.Light{};

            const default_light = try _cdb.createObject(db, light_typeidx);
            const default_light_w = _cdb.writeObj(default_light).?;

            const default_color = try cetech1.cdb_types.Color3f.createObject(_cdb, db);
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
    _gpu = apidb.getZigApi(module_name, cetech1.gpu.GpuApi).?;

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

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_light_component(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
