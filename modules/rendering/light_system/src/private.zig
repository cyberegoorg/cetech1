const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const zm = cetech1.math.zmath;

const shader_system = @import("shader_system");
const transform = @import("transform");
const light_component = @import("light_component");
const visibility_flags = @import("visibility_flags");
const render_graph = @import("render_graph");
const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");

const public = @import("light_system.zig");

const module_name = .light_system;

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
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;

var _gpu: *const gpu.GpuApi = undefined;
var _dd: *const gpu.GpuDDApi = undefined;
var _shader_system: *const shader_system.ShaderSystemAPI = undefined;

const MAX_LIGHTS = 1_000; // TODO
const LIGHT_SIZE = 16; // 2xfloat4

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

pub const api = public.LightSystemApi{
    .createLightSystem = createLightSystem,
    .destroyLightSystem = destroyLightSystem,
};

const light_system_header_strid = cetech1.strId32("light_system_header");
const light_system_buffer_strid = cetech1.strId32("light_system_buffer");

fn createLightSystem() !public.LightSystem {
    const vertex_system = _shader_system.findSystemByName(.fromStr("light_system")).?;
    const system_io = _shader_system.getSystemIO(vertex_system);

    const light_system_uniforms = (try _shader_system.createUniformBuffer(system_io)).?;
    const light_system_resources = (try _shader_system.createResourceBuffer(system_io)).?;

    const light_buffer = _gpu.createDynamicVertexBuffer(MAX_LIGHTS * LIGHT_SIZE, _gpu.getFloatBufferLayout(), gpu.BufferFlags_ComputeRead);

    try _shader_system.updateResources(
        system_io,
        light_system_resources,
        &.{.{ .name = light_system_buffer_strid, .value = .{ .dvb = light_buffer } }},
    );

    try _shader_system.updateUniforms(system_io, light_system_uniforms, &.{
        .{
            .name = light_system_header_strid,
            .value = std.mem.asBytes(&[4]f32{
                0,
                0,
                0,
                0,
            }),
        },
    });

    return .{
        .system = vertex_system,
        .uniforms = light_system_uniforms,
        .resources = light_system_resources,
        .light_buffer = light_buffer,
    };
}

fn destroyLightSystem(inst_system: public.LightSystem) void {
    const system_io = _shader_system.getSystemIO(inst_system.system);
    _shader_system.destroyResourceBuffer(system_io, inst_system.resources.?);
    _shader_system.destroyUniformBuffer(system_io, inst_system.uniforms.?);
    _gpu.destroyDynamicVertexBuffer(inst_system.light_buffer);
}

const GPUPointLight = struct {
    position: [3]f32,
    radius: f32,
    color: [4]f32,
};

const light_system_shaderable = render_viewport.ShaderableComponentI.implement(light_component.Light, struct {
    pub fn init(
        allocator: std.mem.Allocator,
        data: []*anyopaque,
    ) !void {
        _ = allocator;
        _ = data;
        var zz = _profiler.ZoneN(@src(), "Light system - Init callback");
        defer zz.End();
    }

    pub fn fill_bounding_volumes(
        allocator: std.mem.Allocator,
        entites_idx: ?[]const usize,
        transforms: []const transform.WorldTransform,
        data: []*anyopaque,
        volume_type: render_viewport.BoundingVolumeType,
        volumes: []u8,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "Light system - Culling callback");
        defer zz.End();

        var lights = try cetech1.ArrayList(*light_component.Light).initCapacity(allocator, transforms.len);
        defer lights.deinit(allocator);
        try lights.resize(allocator, if (entites_idx) |eidxs| eidxs.len else transforms.len);

        if (entites_idx) |idxs| {
            for (idxs, 0..) |ent_idx, idx| {
                const gi: *light_component.Light = @alignCast(@ptrCast(data[ent_idx]));
                lights.items[idx] = gi;
            }
        } else {
            for (data, 0..) |d, idx| {
                const gi: *light_component.Light = @alignCast(@ptrCast(d));
                lights.items[idx] = gi;
            }
        }

        switch (volume_type) {
            .sphere => {
                var sphere_out_volumes = std.mem.bytesAsSlice(render_viewport.SphereBoudingVolume, volumes);

                for (lights.items, 0..) |l, idx| {
                    var dc_visibility_flags = visibility_flags.VisibilityFlags.initEmpty();
                    dc_visibility_flags.set(0);

                    const tidx = if (entites_idx) |idxs| idxs[idx] else idx;
                    const mat = transforms[tidx].mtx;

                    const origin = zm.util.getTranslationVec(mat);
                    var center = [3]f32{ 0, 0, 0 };
                    zm.storeArr3(&center, origin);

                    sphere_out_volumes[idx] = .{
                        .center = center,
                        .radius = l.radius,
                        .visibility_mask = dc_visibility_flags,
                    };
                }
            },
            // TODO: skip box
            .box => {
                var box_out_volumes = std.mem.bytesAsSlice(render_viewport.BoxBoudingVolume, volumes);

                for (lights.items, 0..) |l, idx| {
                    var dc_visibility_flags = visibility_flags.VisibilityFlags.initEmpty();
                    dc_visibility_flags.set(0);

                    const tidx = if (entites_idx) |idxs| idxs[idx] else idx;
                    const t = transforms[tidx];

                    box_out_volumes[idx] = .{
                        .t = t,
                        .min = .{ -l.radius, -l.radius, -l.radius },
                        .max = .{ l.radius, l.radius, l.radius },
                        .visibility_mask = dc_visibility_flags,
                    };
                }
            },

            else => |v| {
                log.err("Invalid bounding volume {d}", .{v});
            },
        }
    }

    pub fn update(
        allocator: std.mem.Allocator,
        builder: render_graph.GraphBuilder,
        world: ecs.World,
        viewport: render_viewport.Viewport,
        pipeline: render_pipeline.RenderPipeline,
        viewers: []const render_graph.Viewer,
        system_context: *const shader_system.SystemContext,
        entites_idx: []const usize,
        transforms: []transform.WorldTransform,
        render_components: []*anyopaque,
        visibility: []const render_viewport.VisibilityBitField,
    ) !void {
        var zz = _profiler.ZoneN(@src(), "Light system - Render callback");
        defer zz.End();

        _ = world;
        _ = viewport;
        _ = builder;
        _ = viewers;

        _ = visibility;
        _ = system_context;

        var lights = try cetech1.ArrayList(*light_component.Light).initCapacity(allocator, transforms.len);
        defer lights.deinit(allocator);
        try lights.resize(allocator, entites_idx.len);

        for (entites_idx, 0..) |ent_idx, idx| {
            const gi: *light_component.Light = @alignCast(@ptrCast(render_components[ent_idx]));
            lights.items[idx] = gi;
        }

        var gpu_point_lights = try cetech1.ArrayList(GPUPointLight).initCapacity(allocator, entites_idx.len);
        defer gpu_point_lights.deinit(allocator);

        for (entites_idx) |lidx| {
            const l = lights.items[lidx];
            const t = transforms[entites_idx[lidx]];
            const pos = zm.util.getTranslationVec(t.mtx);
            switch (l.type) {
                .point => {
                    gpu_point_lights.appendAssumeCapacity(.{
                        .color = .{ l.color[0], l.color[1], l.color[2], 1.0 },
                        .position = .{ pos[0], pos[1], pos[2] },
                        .radius = l.radius,
                    });
                },
            }
        }

        const light_system_inst = pipeline.getGlobalSystem(public.LightSystem, .fromStr("light_system")).?;

        if (gpu_point_lights.items.len > 0) {
            // const curr_size = _g.light_buffer_offset.load(.monotonic);
            // if (curr_size + (gpu_point_lights.items.len * 4) >= MAX_LIGHTS * 4) {
            //     return error.LightBufferFull;
            // }

            _gpu.updateDynamicVertexBuffer(
                light_system_inst.light_buffer,
                0,
                _gpu.copy(gpu_point_lights.items.ptr, @truncate(@sizeOf(GPUPointLight) * gpu_point_lights.items.len)),
            );
        }

        const light_system_io = _shader_system.getSystemIO(light_system_inst.system);
        const lights_count: u32 = @truncate(gpu_point_lights.items.len);

        try _shader_system.updateUniforms(light_system_io, light_system_inst.uniforms.?, &.{
            .{
                .name = light_system_header_strid,
                .value = std.mem.asBytes(&[4]f32{
                    @bitCast(lights_count),
                    0,
                    0,
                    0,
                }),
            },
        });
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "LightSystem",
    &[_]cetech1.StrId64{.fromStr("ShaderSystem")},
    struct {
        pub fn init() !void {
            // _g.light_buffer = _gpu.createDynamicVertexBuffer(MAX_LIGHTS * 16, _gpu.getFloatBufferLayout(), gpu.BufferFlags_ComputeRead);

            // Viewer system
            try _shader_system.addSystemDefiniton(
                "light_system",
                .{
                    .imports = &.{
                        .{ .name = "light_system_header", .type = .vec4 },
                        .{ .name = "light_system_buffer", .type = .buffer, .buffer_type = .vec4, .buffer_acces = .read },
                    },

                    .common_block = @embedFile("shaders/common_block.glsl"),

                    .fragment_block = .{
                        .common_block = @embedFile("shaders/fs_common_block.glsl"),
                    },
                },
            );
        }

        pub fn shutdown() !void {
            // _gpu.destroyDynamicVertexBuffer(_g.light_buffer);
        }
    },
);

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "LightSystem",
    &[_]cetech1.StrId64{},
    null,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);
        }
    },
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;

    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _shader_system = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;

    try apidb.setOrRemoveZigApi(module_name, public.LightSystemApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);

    try apidb.implOrRemove(module_name, render_viewport.ShaderableComponentI, &light_system_shaderable, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_light_system(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
