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

fn createLightSystem(gpu_backend: gpu.GpuBackend) !public.LightSystem {
    const vertex_system = _shader_system.findSystemByName(.fromStr("light_system")).?;
    const system_io = _shader_system.getSystemIO(vertex_system);

    const light_system_uniforms = (try _shader_system.createUniformBuffer(system_io)).?;
    const light_system_resources = (try _shader_system.createResourceBuffer(system_io)).?;

    const light_buffer = gpu_backend.createDynamicVertexBuffer(
        MAX_LIGHTS * LIGHT_SIZE,
        gpu_backend.getFloatBufferLayout(),
        .{ .compute_access = .read },
    );

    try _shader_system.updateResources(
        system_io,
        light_system_resources,
        &.{.{ .name = light_system_buffer_strid, .value = .{ .buffer = .{ .dvb = light_buffer } } }},
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

fn destroyLightSystem(inst_system: public.LightSystem, gpu_backend: gpu.GpuBackend) void {
    const system_io = _shader_system.getSystemIO(inst_system.system);
    _shader_system.destroyResourceBuffer(system_io, inst_system.resources.?);
    _shader_system.destroyUniformBuffer(system_io, inst_system.uniforms.?);
    gpu_backend.destroyDynamicVertexBuffer(inst_system.light_buffer);
}

// From: https://bartwronski.com/2017/04/13/cull-that-cone/
fn boundingSphere(origin: [3]f32, forward: [3]f32, size: f32, angle: f32) zm.Vec {
    var center: zm.Vec = .{ 0, 0, 0, 0 };
    var radius: f32 = 0;

    const cos_angle = std.math.cos(angle);

    if (angle > std.math.pi / 4.0) {
        radius = std.math.sin(angle) * size;
        center = zm.loadArr3(origin) + zm.loadArr3(forward) * zm.splat(zm.Vec, cos_angle * size);
    } else {
        radius = size / (2.0 * cos_angle);
        center = zm.loadArr3(origin) + zm.loadArr3(forward) * zm.splat(zm.Vec, radius);
    }

    return .{ center[0], center[1], center[2], radius };
}

const SortLightContext = struct {
    lights: []*light_component.Light,
    ent_idx: []usize,

    pub fn lessThan(ctx: *SortLightContext, lhs: usize, rhs: usize) bool {
        return @intFromEnum(ctx.lights[lhs].type) < @intFromEnum(ctx.lights[rhs].type);
    }

    pub fn swap(ctx: *SortLightContext, lhs: usize, rhs: usize) void {
        std.mem.swap(usize, &ctx.ent_idx[lhs], &ctx.ent_idx[rhs]);
        std.mem.swap(*light_component.Light, &ctx.lights[lhs], &ctx.lights[rhs]);
    }
};

const LightCusterDef = struct {
    first_idx: usize,
    lights: []const *light_component.Light,
};

fn clusterByLightsType(allocator: std.mem.Allocator, sorted_instances: []*light_component.Light, max_cluster: usize) ![]LightCusterDef {
    var zone2_ctx = _profiler.ZoneN(@src(), "clusterByLightsType");
    defer zone2_ctx.End();

    var clusters = try cetech1.ArrayList(LightCusterDef).initCapacity(allocator, max_cluster);
    defer clusters.deinit(allocator);

    var cluster_begin_idx: usize = 0;
    var current_obj = sorted_instances[0];
    for (0..sorted_instances.len) |idx| {
        if (sorted_instances[idx].type == current_obj.type) continue;

        clusters.appendAssumeCapacity(.{
            .first_idx = cluster_begin_idx,
            .lights = sorted_instances[cluster_begin_idx..idx],
        });
        current_obj = sorted_instances[idx];
        cluster_begin_idx = idx; //-1;
    }

    // Add rest
    clusters.appendAssumeCapacity(.{
        .first_idx = cluster_begin_idx,
        .lights = sorted_instances[cluster_begin_idx..sorted_instances.len],
    });

    return clusters.toOwnedSlice(allocator);
}

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
                const gi: *light_component.Light = @ptrCast(@alignCast(data[ent_idx]));
                lights.items[idx] = gi;
            }
        } else {
            for (data, 0..) |d, idx| {
                const gi: *light_component.Light = @ptrCast(@alignCast(d));
                lights.items[idx] = gi;
            }
        }

        switch (volume_type) {
            .sphere => {
                var sphere_out_volumes = std.mem.bytesAsSlice(render_viewport.SphereBoudingVolume, volumes);

                for (lights.items, 0..) |l, idx| {
                    var dc_visibility_flags = visibility_flags.VisibilityFlags.initEmpty();
                    dc_visibility_flags.set(0); // TODO:

                    const tidx = if (entites_idx) |idxs| idxs[idx] else idx;
                    const mat = transforms[tidx].mtx;

                    const origin = zm.util.getTranslationVec(mat);
                    var center = [3]f32{ 0, 0, 0 };
                    zm.storeArr3(&center, origin);

                    switch (l.type) {
                        .point => {
                            sphere_out_volumes[idx] = .{
                                .center = center,
                                .radius = l.radius,
                                .visibility_mask = dc_visibility_flags,
                            };
                        },
                        .spot => {
                            const forward = zm.normalize3(zm.util.getAxisZ(mat));
                            const sphere = boundingSphere(
                                center,
                                zm.vecToArr3(forward),
                                l.radius / std.math.cos(std.math.degreesToRadians(l.angle_outer)),
                                std.math.degreesToRadians(l.angle_outer),
                            );

                            sphere_out_volumes[idx] = .{
                                .center = .{ sphere[0], sphere[1], sphere[2] },
                                .radius = sphere[3],
                                .visibility_mask = dc_visibility_flags,
                            };
                        },
                        .direction => {
                            sphere_out_volumes[idx] = .{
                                .skip_culling = true,
                                .visibility_mask = dc_visibility_flags,
                            };
                        },
                    }
                }
            },

            .box => {
                var box_out_volumes = std.mem.bytesAsSlice(render_viewport.BoxBoudingVolume, volumes);

                for (lights.items, 0..) |l, idx| {
                    var dc_visibility_flags = visibility_flags.VisibilityFlags.initEmpty();
                    dc_visibility_flags.set(0); // TODO:

                    const tidx = if (entites_idx) |idxs| idxs[idx] else idx;
                    const t = transforms[tidx];

                    switch (l.type) {
                        .point => {
                            box_out_volumes[idx] = .{
                                .skip_culling = true,
                                .visibility_mask = dc_visibility_flags,
                            };
                        },
                        .spot => {
                            const r = l.radius * std.math.tan(std.math.degreesToRadians(l.angle_outer));
                            box_out_volumes[idx] = .{
                                .t = .{ .mtx = t.mtx },
                                .min = .{ -r, -r, 0 },
                                .max = .{ r, r, l.radius },
                                .visibility_mask = dc_visibility_flags,
                            };
                        },
                        .direction => {
                            box_out_volumes[idx] = .{
                                .skip_culling = true,
                                .visibility_mask = dc_visibility_flags,
                            };
                        },
                    }
                }
            },

            else => |v| {
                log.err("Invalid bounding volume {d}", .{v});
            },
        }
    }

    pub fn update(
        allocator: std.mem.Allocator,
        gpu_backend: gpu.GpuBackend,
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

        const light_system_inst = pipeline.getGlobalSystem(public.LightSystem, .fromStr("light_system")).?;
        const light_system_io = _shader_system.getSystemIO(light_system_inst.system);

        if (entites_idx.len == 0) {
            try _shader_system.updateUniforms(
                light_system_io,
                light_system_inst.uniforms.?,
                &.{
                    .{
                        .name = light_system_header_strid,
                        .value = std.mem.asBytes(&[4]f32{
                            0,
                            0,
                            0,
                            0,
                        }),
                    },
                },
            );
            return;
        }

        var lights = try cetech1.ArrayList(*light_component.Light).initCapacity(allocator, entites_idx.len);
        defer lights.deinit(allocator);
        try lights.resize(allocator, entites_idx.len);

        for (entites_idx, 0..) |ent_idx, idx| {
            const gi: *light_component.Light = @ptrCast(@alignCast(render_components[ent_idx]));
            lights.items[idx] = gi;
        }

        const dup_ent_idx = try allocator.dupe(usize, entites_idx);
        defer allocator.free(dup_ent_idx);

        var sort_context = SortLightContext{
            .lights = lights.items,
            .ent_idx = dup_ent_idx,
        };
        std.sort.insertionContext(0, lights.items.len, &sort_context);

        const clusters = try clusterByLightsType(allocator, lights.items, @intFromEnum(light_component.LightType.direction) + 1);
        defer allocator.free(clusters);

        var point_count: u32 = 0;
        var spot_count: u32 = 0;
        var direction_count: u32 = 0;
        for (clusters) |cluster| {
            const light_count: u32 = @truncate(cluster.lights.len);
            switch (cluster.lights[0].type) {
                .point => point_count += 1 * light_count,
                .spot => spot_count += 1 * light_count,
                .direction => direction_count += 1 * light_count,
            }
        }

        // Buffer is vec4
        const light_buffer_size = (point_count * 2) + (spot_count * 3) + (direction_count * 3);
        var gpu_point_lights = try cetech1.ArrayList([4]f32).initCapacity(allocator, light_buffer_size);
        defer gpu_point_lights.deinit(allocator);

        for (clusters) |cluster| {
            for (cluster.lights, 0..) |l, idx| {
                const t = transforms[dup_ent_idx[cluster.first_idx + idx]];
                const pos = zm.util.getTranslationVec(t.mtx);

                switch (l.type) {
                    .point => {
                        // l.power unit is lumen
                        const power = zm.loadArr3(l.color) * zm.splat(zm.F32x4, l.power / (4 * std.math.pi));
                        gpu_point_lights.appendSliceAssumeCapacity(&.{
                            .{ pos[0], pos[1], pos[2], l.radius },
                            .{ power[0], power[1], power[2], 0 },
                        });
                    },
                    .spot => {
                        // l.power unit is lumen
                        const power = zm.loadArr3(l.color) * zm.splat(zm.F32x4, l.power / (std.math.pi));

                        const dir = zm.normalize3(zm.util.getAxisZ(t.mtx));
                        const cos_inner = std.math.cos(std.math.degreesToRadians(l.angle_inner));
                        const cos_outer = std.math.cos(std.math.degreesToRadians(l.angle_outer));

                        const angle_scale = 1 / @max(0.001, cos_inner - cos_outer);
                        const angle_offset = -cos_outer * angle_scale;

                        gpu_point_lights.appendSliceAssumeCapacity(&.{
                            .{ pos[0], pos[1], pos[2], l.radius / std.math.cos(std.math.degreesToRadians(l.angle_outer)) },
                            .{ power[0], power[1], power[2], angle_scale },
                            .{ dir[0], dir[1], dir[2], angle_offset },
                        });
                    },
                    .direction => {
                        const power = zm.loadArr3(l.color) * zm.splat(zm.F32x4, l.power);

                        const dir = zm.normalize3(zm.util.getAxisZ(t.mtx));
                        gpu_point_lights.appendSliceAssumeCapacity(&.{
                            .{ pos[0], pos[1], pos[2], l.radius },
                            .{ power[0], power[1], power[2], 0 },
                            .{ dir[0], dir[1], dir[2], 0 },
                        });
                    },
                }
            }
        }

        if (gpu_point_lights.items.len > 0) {
            gpu_backend.updateDynamicVertexBuffer(
                light_system_inst.light_buffer,
                0,
                gpu_backend.copy(gpu_point_lights.items.ptr, @truncate(@sizeOf([4]f32) * gpu_point_lights.items.len)),
            );
        }

        try _shader_system.updateUniforms(
            light_system_io,
            light_system_inst.uniforms.?,
            &.{
                .{
                    .name = light_system_header_strid,
                    .value = std.mem.asBytes(&[4]f32{
                        @bitCast(point_count),
                        @bitCast(spot_count),
                        @bitCast(direction_count),
                        0,
                    }),
                },
            },
        );
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "LightSystem",
    &[_]cetech1.StrId64{.fromStr("ShaderSystem")},
    struct {
        pub fn init() !void {
            // Light system
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

        pub fn shutdown() !void {}
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
pub export fn ct_load_module_light_system(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
