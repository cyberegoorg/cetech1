const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const math = cetech1.math;

const gpu = cetech1.gpu;
const apidb = cetech1.apidb;
const coreui = cetech1.coreui;

const shader_system = cetech1.renderer.shader_system;

const public = cetech1.renderer_pipeline.vertex_system;

const module_name = .vertex_system;

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
const task = cetech1.task;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

pub const api = public.VertexSystemApi{
    .createVertexSystemFromVertexBuffer = createVertexSystemFromVertexBuffer,
};

const vertex_system_header_strid = cetech1.strId32("vertex_system_header");
const vertex_system_offsets_strid = cetech1.strId32("vertex_system_offsets");
const vertex_system_strides_strid = cetech1.strId32("vertex_system_strides");
const vertex_system_buffer_idx_strid = cetech1.strId32("vertex_system_buffer_idx");

const vertex_system_channel0_strid = cetech1.strId32("vertex_system_channel0");
const vertex_system_channel1_strid = cetech1.strId32("vertex_system_channel1");

fn createVertexSystemFromVertexBuffer(allocator: std.mem.Allocator, vertex_buffer: public.VertexBuffer) !public.GPUGeometry {
    const vertex_system = shader_system.findSystemByName(.fromStr("vertex_system")).?;
    const system_io = shader_system.getSystemIO(vertex_system);

    const vertex_system_uniforms = (try shader_system.createUniformBuffer(system_io)).?;
    const vertex_system_resources = (try shader_system.createResourceBuffer(system_io)).?;

    var it = vertex_buffer.active_channels.iterator(.{ .kind = .set });
    var channel_offset: [4][4]f32 = @splat(@splat(0));
    var channel_stride: [4][4]f32 = @splat(@splat(0));
    var channel_buffer_idx: [4][4]f32 = @splat(@splat(0));

    var buffer_idx_map: cetech1.AutoArrayHashMap(gpu.BufferHandle, void) = .{};
    defer buffer_idx_map.deinit(allocator);
    try buffer_idx_map.ensureTotalCapacity(allocator, public.MAX_BUFFERS);

    while (it.next()) |channel_id| {
        const buffer = vertex_buffer.channels[channel_id].buffer;
        const get_or_put = try buffer_idx_map.getOrPut(allocator, buffer);

        channel_offset[channel_id / 4][channel_id % 4] = @bitCast(vertex_buffer.channels[channel_id].offset / @sizeOf(f32));
        channel_stride[channel_id / 4][channel_id % 4] = @bitCast(vertex_buffer.channels[channel_id].stride / @sizeOf(f32));
        channel_buffer_idx[channel_id / 4][channel_id % 4] = @bitCast(@as(u32, @truncate(get_or_put.index)));
    }

    try shader_system.updateUniforms(system_io, vertex_system_uniforms, &.{
        .{
            .name = vertex_system_header_strid,
            .value = std.mem.asBytes(&[4]f32{
                @bitCast(vertex_buffer.active_channels.mask),
                @bitCast(vertex_buffer.num_vertices),
                @bitCast(vertex_buffer.num_sets),
                0,
            }),
        },
        .{
            .name = vertex_system_offsets_strid,
            .value = std.mem.asBytes(&channel_offset),
        },
        .{
            .name = vertex_system_strides_strid,
            .value = std.mem.asBytes(&channel_stride),
        },
        .{
            .name = vertex_system_buffer_idx_strid,
            .value = std.mem.asBytes(&channel_buffer_idx),
        },
    });

    for (buffer_idx_map.keys(), 0..) |vb, idx| {
        switch (idx) {
            0 => try shader_system.updateResources(system_io, vertex_system_resources, &.{.{ .name = vertex_system_channel0_strid, .value = .{ .buffer = vb } }}),
            1 => try shader_system.updateResources(system_io, vertex_system_resources, &.{.{ .name = vertex_system_channel1_strid, .value = .{ .buffer = vb } }}),
            else => {},
        }
    }

    return .{
        .primitive_type = vertex_buffer.primitive_type,
        .system = vertex_system,
        .uniforms = vertex_system_uniforms,
        .resources = vertex_system_resources,
    };
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "VertexSystem",
    &[_]cetech1.StrId64{.fromStr("ShaderSystem")},
    struct {
        pub fn init() !void {
            // Viewer system
            try shader_system.addSystemDefiniton(
                "vertex_system",
                .{
                    .imports = &.{
                        .{ .name = "vertex_system_header", .type = .vec4 },

                        .{ .name = "vertex_system_offsets", .type = .vec4, .count = public.MAX_CHANNELS / 4 },
                        .{ .name = "vertex_system_strides", .type = .vec4, .count = public.MAX_CHANNELS / 4 },
                        .{ .name = "vertex_system_buffer_idx", .type = .vec4, .count = public.MAX_CHANNELS / 4 },

                        .{ .name = "vertex_system_channel0", .type = .buffer, .buffer_type = .float, .buffer_acces = .read },
                        .{ .name = "vertex_system_channel1", .type = .buffer, .buffer_type = .float, .buffer_acces = .read },
                    },

                    .common_block = @embedFile("shaders/vertex_system/common_block.glsl"),

                    .vertex_block = .{
                        .import_semantic = &.{.vertex_id},
                        .common_block = @embedFile("shaders/vertex_system/vs_common_block.glsl"),
                        .code =
                        \\  ct_vertex_loader_ctx vertex_ctx;
                        \\  init_vertex_loader(vertex_ctx, inputs);
                        ,
                    },
                },
            );
        }

        pub fn shutdown() !void {}
    },
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;

    // basic
    _allocator = allocator;
    public.api = &api;

    try apidb.setOrRemoveZigApi(module_name, public.VertexSystemApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_vertex_system(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
