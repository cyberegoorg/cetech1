const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

const public = @import("renderer_nodes.zig");

const graphvm = @import("graphvm");

const shader_system = @import("shader_system");

const render_viewport = @import("render_viewport");
const vertex_system = @import("vertex_system");
const visibility_flags = @import("visibility_flags");

const module_name = .renderer_nodes;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _ecs: *const ecs.EcsAPI = undefined;

var _dd: *const gpu.GpuDDApi = undefined;
var _metrics: *const cetech1.metrics.MetricsAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;

var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _viewport: *const render_viewport.RenderViewportApi = undefined;
var _vertex_system: *const vertex_system.VertexSystemApi = undefined;
var _visibility_flags: *const visibility_flags.VisibilityFlagsApi = undefined;

// Global state
const G = struct {
    cube_pos_vb: gpu.VertexBufferHandle = .{},
    cube_col_vb: gpu.VertexBufferHandle = .{},
    cube_ib: gpu.IndexBufferHandle = .{},
    cube_vb: vertex_system.VertexBuffer = .{},
    cube_geometry: vertex_system.GPUGeometry = undefined,

    bunny_pos_vb: gpu.VertexBufferHandle = .{},
    bunny_col_vb: gpu.VertexBufferHandle = .{},
    bunny_vb: vertex_system.VertexBuffer = .{},
    bunny_geometry: vertex_system.GPUGeometry = undefined,
    bunny_ib: gpu.IndexBufferHandle = .{},

    plane_pos_vb: gpu.VertexBufferHandle = .{},
    plane_ib: gpu.IndexBufferHandle = .{},
    plane_vb: vertex_system.VertexBuffer = .{},
    plane_geometry: vertex_system.GPUGeometry = undefined,

    current_frame: u32 = 0,
};

var _g: *G = undefined;

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "Renderer nodes",
    &[_]cetech1.StrId64{.fromStr("VertexSystem")},
    struct {
        pub fn init() !void {
            const gpu_backend = _kernel.getGpuBackend().?;

            _vertex_pos_layout = PosVertex.layoutInit(gpu_backend);
            _vertex_col_layout = ColorVertex.layoutInit(gpu_backend);
            _vertex_col_normal_layout = ColorNormalVertex.layoutInit(gpu_backend);

            //
            // Cube
            //
            _g.cube_pos_vb = gpu_backend.createVertexBuffer(
                gpu_backend.makeRef(&cube_positions, cube_positions.len * @sizeOf(PosVertex)),
                &_vertex_pos_layout,
                .{ .compute_access = .read },
            );
            _g.cube_col_vb = gpu_backend.createVertexBuffer(
                gpu_backend.makeRef(&cube_cololrs, cube_cololrs.len * @sizeOf(ColorNormalVertex)),
                &_vertex_col_normal_layout,
                .{ .compute_access = .read },
            );

            _g.cube_vb.num_vertices = cube_positions.len;
            _g.cube_vb.num_sets = 1;
            // _g.cube_vb.primitive_type = .triangles_strip;

            _g.cube_vb.active_channels.set(vertex_system.VertexChannelsNames.Position);
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Position].buffer = .{ .vb = _g.cube_pos_vb };
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Position].stride = @sizeOf(PosVertex);

            _g.cube_vb.active_channels.set(vertex_system.VertexChannelsNames.Color0);
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Color0].buffer = .{ .vb = _g.cube_col_vb };
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Color0].stride = @sizeOf(ColorNormalVertex);

            _g.cube_vb.active_channels.set(vertex_system.VertexChannelsNames.Normal0);
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Normal0].buffer = .{ .vb = _g.cube_col_vb };
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Normal0].offset = @offsetOf(ColorNormalVertex, "x");
            _g.cube_vb.channels[vertex_system.VertexChannelsNames.Normal0].stride = @sizeOf(ColorNormalVertex);

            _g.cube_geometry = try _vertex_system.createVertexSystemFromVertexBuffer(_allocator, _g.cube_vb);

            _g.cube_ib = gpu_backend.createIndexBuffer(
                // gpu_backend.makeRef(&cube_tri_strip, cube_tri_strip.len * @sizeOf(u16)),
                gpu_backend.makeRef(&cube_tri_list, cube_tri_list.len * @sizeOf(u16)),
                .{},
            );

            //
            // Bunny
            //
            _g.bunny_pos_vb = gpu_backend.createVertexBuffer(
                gpu_backend.makeRef(&bunny_position, bunny_position.len * @sizeOf(PosVertex)),
                &_vertex_pos_layout,
                .{ .compute_access = .read },
            );
            _g.bunny_col_vb = gpu_backend.createVertexBuffer(
                gpu_backend.makeRef(&bunny_colors, bunny_colors.len * @sizeOf(ColorVertex)),
                &_vertex_col_layout,
                .{ .compute_access = .read },
            );

            _g.bunny_vb.num_vertices = bunny_position.len;
            _g.bunny_vb.num_sets = 1;

            _g.bunny_vb.active_channels.set(vertex_system.VertexChannelsNames.Position);
            _g.bunny_vb.channels[vertex_system.VertexChannelsNames.Position].buffer = .{ .vb = _g.bunny_pos_vb };
            _g.bunny_vb.channels[vertex_system.VertexChannelsNames.Position].stride = @sizeOf(PosVertex);

            _g.bunny_vb.active_channels.set(vertex_system.VertexChannelsNames.Color0);
            _g.bunny_vb.channels[vertex_system.VertexChannelsNames.Color0].buffer = .{ .vb = _g.bunny_col_vb };
            _g.bunny_vb.channels[vertex_system.VertexChannelsNames.Color0].stride = @sizeOf(ColorVertex);

            _g.bunny_geometry = try _vertex_system.createVertexSystemFromVertexBuffer(_allocator, _g.bunny_vb);

            _g.bunny_ib = gpu_backend.createIndexBuffer(
                gpu_backend.makeRef(&bunny_tri_list, bunny_tri_list.len * @sizeOf(u16)),
                .{},
            );

            //
            // Bunny
            //
            _g.plane_pos_vb = gpu_backend.createVertexBuffer(
                gpu_backend.makeRef(&plan_positions, plan_positions.len * @sizeOf(PosVertex)),
                &_vertex_pos_layout,
                .{ .compute_access = .read },
            );

            _g.plane_vb.num_vertices = bunny_position.len;
            _g.plane_vb.num_sets = 1;

            _g.plane_vb.active_channels.set(vertex_system.VertexChannelsNames.Position);
            _g.plane_vb.channels[vertex_system.VertexChannelsNames.Position].buffer = .{ .vb = _g.plane_pos_vb };
            _g.plane_vb.channels[vertex_system.VertexChannelsNames.Position].stride = @sizeOf(PosVertex);

            _g.plane_geometry = try _vertex_system.createVertexSystemFromVertexBuffer(_allocator, _g.plane_vb);

            _g.plane_ib = gpu_backend.createIndexBuffer(
                gpu_backend.makeRef(&plane_tri_list, plane_tri_list.len * @sizeOf(u16)),
                .{},
            );
        }

        pub fn shutdown() !void {
            const gpu_backend = _kernel.getGpuBackend().?;

            gpu_backend.destroyIndexBuffer(_g.cube_ib);
            gpu_backend.destroyVertexBuffer(_g.cube_pos_vb);
            gpu_backend.destroyVertexBuffer(_g.cube_col_vb);

            const cube_io = _shader.getSystemIO(_g.cube_geometry.system);
            if (_g.cube_geometry.uniforms) |u| _shader.destroyUniformBuffer(cube_io, u);
            if (_g.cube_geometry.resources) |r| _shader.destroyResourceBuffer(cube_io, r);

            const bunny_io = _shader.getSystemIO(_g.bunny_geometry.system);
            if (_g.bunny_geometry.uniforms) |u| _shader.destroyUniformBuffer(bunny_io, u);
            if (_g.bunny_geometry.resources) |r| _shader.destroyResourceBuffer(bunny_io, r);

            gpu_backend.destroyVertexBuffer(_g.bunny_pos_vb);
            gpu_backend.destroyVertexBuffer(_g.bunny_col_vb);
            gpu_backend.destroyIndexBuffer(_g.bunny_ib);
        }
    },
);

const gpu_geometry_value_type_i = graphvm.GraphValueTypeI.implement(
    vertex_system.GPUGeometry,
    .{
        .name = "GPU geometry",
        .type_hash = public.PinTypes.GPU_GEOMETRY,
        .cdb_type_hash = public.GPUGeometryCdb.type_hash, // TODO: this is not needed. value only setable from nodes out
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            _ = obj; // autofix
            const v: vertex_system.GPUGeometry = .{};

            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            return cetech1.strId64(value).id;
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(vertex_system.GPUGeometry, value)}, 0);
        }
    },
);

const gpu_index_buffer_value_type_i = graphvm.GraphValueTypeI.implement(
    gpu.IndexBufferHandle,
    .{
        .name = "GPU index buffer",
        .type_hash = public.PinTypes.GPU_INDEX_BUFFER,
        .cdb_type_hash = public.GPUIndexBufferCdb.type_hash,
    },
    struct {
        pub fn valueFromCdb(allocator: std.mem.Allocator, obj: cdb.ObjId, value: []u8) !void {
            _ = allocator; // autofix
            const v = public.GPUIndexBufferCdb.readValue(u32, _cdb, _cdb.readObj(obj).?, .handle);
            @memcpy(value, std.mem.asBytes(&v));
        }

        pub fn calcValidityHash(value: []const u8) !graphvm.ValidityHash {
            const v = std.mem.bytesAsValue(u32, value);
            return @intCast(v.*);
        }

        pub fn valueToString(allocator: std.mem.Allocator, value: []const u8) ![:0]u8 {
            return std.fmt.allocPrintSentinel(allocator, "{any}", .{std.mem.bytesToValue(u32, value)}, 0);
        }
    },
);

// TODO: Move
const culling_volume_node_i = graphvm.NodeI.implement(
    .{
        .name = "Culling volume",
        .type_name = public.CULLING_VOLUME_NODE_TYPE_STR,
        .pivot = .pivot,
        .category = "Culling",
    },
    render_viewport.CullingVolume,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("Radius", graphvm.NodePin.pinHash("radius", false), graphvm.PinTypes.F32, null),
                    graphvm.NodePin.init("Min", graphvm.NodePin.pinHash("min", false), graphvm.PinTypes.VEC3F, null),
                    graphvm.NodePin.init("Max", graphvm.NodePin.pinHash("max", false), graphvm.PinTypes.VEC3F, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{}),
            };
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
            const real_state: *render_viewport.CullingVolume = @ptrCast(@alignCast(state));
            real_state.* = .{};
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self; // autofix
            _ = out_pins;
            var state = args.getState(render_viewport.CullingVolume).?;
            _, const radius = in_pins.read(f32, 0) orelse .{ 0, 0 };
            _, const min = in_pins.read([3]f32, 1) orelse .{ 0, .{ 0, 0, 0 } };
            _, const max = in_pins.read([3]f32, 2) orelse .{ 0, .{ 0, 0, 0 } };

            state.radius = radius;
            state.min = min;
            state.max = max;
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Bounding});
        }
    },
);

const draw_call_node_i = graphvm.NodeI.implement(
    .{
        .name = "Draw call",
        .type_name = public.DRAW_CALL_NODE_TYPE_STR,
        .pivot = .pivot,
        .category = "Renderer",
        .settings_type = public.DrawCallNodeSettings.type_hash,
    },
    public.DrawCall,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("GPU shader", graphvm.NodePin.pinHash("gpu_shader", false), shader_system.PinTypes.GPU_SHADER, null),
                    graphvm.NodePin.init("GPU geometry", graphvm.NodePin.pinHash("gpu_geometry", false), public.PinTypes.GPU_GEOMETRY, null),
                    graphvm.NodePin.init("GPU index buffer", graphvm.NodePin.pinHash("gpu_index_buffer", false), public.PinTypes.GPU_INDEX_BUFFER, null),
                    graphvm.NodePin.init("Vertex count", graphvm.NodePin.pinHash("vertex_count", false), graphvm.PinTypes.U32, null),
                    graphvm.NodePin.init("Index count", graphvm.NodePin.pinHash("index_count", false), graphvm.PinTypes.U32, null),
                }),
                .out = try allocator.dupe(graphvm.NodePin, &.{}),
            };
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool, transpile_state: ?[]u8) !void {
            _ = self; // autofix
            _ = transpile_state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
            const real_state: *public.DrawCall = @ptrCast(@alignCast(state));

            real_state.* = .{
                .shader = .{},
                .visibility_mask = _visibility_flags.createFlags(&.{}).?,
            };
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self; // autofix
            _ = out_pins;
            var state = args.getState(public.DrawCall).?;

            _, const shader = in_pins.read(shader_system.GpuShaderValue, 0) orelse .{ 0, shader_system.GpuShaderValue{} };
            _, const geometry = in_pins.read(vertex_system.GPUGeometry, 1) orelse .{ 0, vertex_system.GPUGeometry{} };
            _, const index_buffer = in_pins.read(gpu.IndexBufferHandle, 2) orelse .{ 0, gpu.IndexBufferHandle{} };
            _, const vertex_count = in_pins.read(u32, 3) orelse .{ 0, 0 };
            _, const index_count = in_pins.read(u32, 4) orelse .{ 0, 0 };

            const settings_r = public.DrawCallNodeSettings.read(_cdb, args.settings.?).?;
            const flags_obj = public.DrawCallNodeSettings.readSubObj(_cdb, settings_r, .visibility_flags).?;
            const flags_obj_r = visibility_flags.VisibilityFlagsCdb.read(_cdb, flags_obj).?;

            if (try visibility_flags.VisibilityFlagsCdb.readSubObjSet(_cdb, flags_obj_r, .flags, args.allocator)) |flags| {
                defer args.allocator.free(flags);

                var uuids = try cetech1.ArrayList(u32).initCapacity(args.allocator, visibility_flags.MAX_FLAGS);
                defer uuids.deinit(args.allocator);

                for (flags) |flag_obj| {
                    const flag_r = visibility_flags.VisibilityFlagCdb.read(_cdb, flag_obj).?;
                    const uuid = visibility_flags.VisibilityFlagCdb.readValue(u32, _cdb, flag_r, .uuid);
                    uuids.appendAssumeCapacity(uuid);
                }

                state.visibility_mask = _visibility_flags.createFlagsFromUuids(uuids.items).?;
            }

            state.shader = shader.shader;
            state.uniforms = shader.uniforms;
            state.resouces = shader.resouces;

            state.geometry = geometry;
            state.index_buffer = index_buffer;
            state.vertex_count = vertex_count;
            state.index_count = index_count;

            state.calcHash();
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.Icons.Draw});
        }
    },
);

// TODO: Move
const simple_mesh_node_i = graphvm.NodeI.implement(
    .{
        .name = "Simple mesh",
        .type_name = public.SIMPLE_MESH_NODE_TYPE_STR,
        .category = "Renderer",
        .settings_type = public.SimpleMeshNodeSettings.type_hash,
    },
    null,
    struct {
        const Self = @This();

        pub fn getPinsDef(self: *const graphvm.NodeI, allocator: std.mem.Allocator, graph_obj: cdb.ObjId, node_obj: cdb.ObjId) !graphvm.NodePinDef {
            _ = self; // autofix
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            return .{
                .in = try allocator.dupe(graphvm.NodePin, &.{}),
                .out = try allocator.dupe(graphvm.NodePin, &.{
                    graphvm.NodePin.init("GPU geometry", graphvm.NodePin.pinHash("gpu_geometry", true), public.PinTypes.GPU_GEOMETRY, null),
                    graphvm.NodePin.init("GPU index buffer", graphvm.NodePin.pinHash("gpu_index_buffer", true), public.PinTypes.GPU_INDEX_BUFFER, null),
                    graphvm.NodePin.init("Vertex count", graphvm.NodePin.pinHash("vertex_count", true), graphvm.PinTypes.U32, null),
                    graphvm.NodePin.init("Index count", graphvm.NodePin.pinHash("index_count", true), graphvm.PinTypes.U32, null),
                }),
            };
        }

        pub fn create(self: *const graphvm.NodeI, allocator: std.mem.Allocator, state: *anyopaque, node_obj: cdb.ObjId, reload: bool) !void {
            _ = self; // autofix
            _ = state; // autofix
            _ = reload; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix
        }

        pub fn execute(self: *const graphvm.NodeI, args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: *graphvm.OutPins) !void {
            _ = self; // autofix
            _ = in_pins; // autofix

            const settings_r = public.SimpleMeshNodeSettings.read(_cdb, args.settings.?).?;

            const type_str = public.SimpleMeshNodeSettings.readStr(_cdb, settings_r, .type) orelse "cube";
            const type_enum = std.meta.stringToEnum(public.SimpleMeshNodeType, type_str).?;

            switch (type_enum) {
                .cube => {
                    try out_pins.writeTyped(vertex_system.GPUGeometry, 0, try gpu_geometry_value_type_i.calcValidityHash(&std.mem.toBytes(_g.cube_geometry)), _g.cube_geometry);
                    try out_pins.writeTyped(gpu.IndexBufferHandle, 1, try gpu_index_buffer_value_type_i.calcValidityHash(&std.mem.toBytes(_g.cube_ib)), _g.cube_ib);
                    try out_pins.writeTyped(u32, 2, cube_positions.len, cube_positions.len);
                    try out_pins.writeTyped(u32, 3, cube_tri_list.len, cube_tri_list.len);
                },

                .plane => {
                    try out_pins.writeTyped(vertex_system.GPUGeometry, 0, try gpu_geometry_value_type_i.calcValidityHash(&std.mem.toBytes(_g.plane_geometry)), _g.plane_geometry);
                    try out_pins.writeTyped(gpu.IndexBufferHandle, 1, try gpu_index_buffer_value_type_i.calcValidityHash(&std.mem.toBytes(_g.plane_ib)), _g.plane_ib);
                    try out_pins.writeTyped(u32, 2, plan_positions.len, plan_positions.len);
                    try out_pins.writeTyped(u32, 3, plane_tri_list.len, plane_tri_list.len);
                },

                .bunny => {
                    try out_pins.writeTyped(vertex_system.GPUGeometry, 0, try gpu_geometry_value_type_i.calcValidityHash(&std.mem.toBytes(_g.bunny_geometry)), _g.bunny_geometry);
                    try out_pins.writeTyped(gpu.IndexBufferHandle, 1, try gpu_index_buffer_value_type_i.calcValidityHash(&std.mem.toBytes(_g.bunny_ib)), _g.bunny_ib);
                    try out_pins.writeTyped(u32, 2, bunny_position.len, bunny_position.len);
                    try out_pins.writeTyped(u32, 3, bunny_tri_list.len, bunny_tri_list.len);
                },
            }
        }

        pub fn icon(
            self: *const graphvm.NodeI,
            buff: [:0]u8,
            allocator: std.mem.Allocator,
            node_obj: cdb.ObjId,
        ) ![:0]u8 {
            _ = self; // autofix
            _ = allocator; // autofix
            _ = node_obj; // autofix

            return std.fmt.bufPrintZ(buff, "{s}", .{cetech1.coreui.CoreIcons.FA_POO});
        }
    },
);

// TMP SHIT
//
// Vertex layout definiton
//
const PosVertex = struct {
    x: f32,
    y: f32,
    z: f32,

    fn init(x: f32, y: f32, z: f32) PosVertex {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    fn layoutInit(gpu_backend: gpu.GpuBackend) gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = gpu_backend.layoutBegin(&L.posColorLayout);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 3, gpu.AttribType.Float, false, false);
        //_ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Color0, 4, gpu.AttribType.Uint8, true, false);
        gpu_backend.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};

const ColorVertex = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1,

    fn init(r: f32, g: f32, b: f32, a: f32) ColorVertex {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    fn layoutInit(gpu_backend: gpu.GpuBackend) gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = gpu_backend.layoutBegin(&L.posColorLayout);
        //_ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 3, gpu.AttribType.Float, false, false);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Color0, 4, gpu.AttribType.Float, true, false);
        gpu_backend.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};

const ColorNormalVertex = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1,
    x: f32,
    y: f32,
    z: f32,

    fn init(r: f32, g: f32, b: f32, a: f32, x: f32, y: f32, z: f32) ColorNormalVertex {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
            .x = x,
            .y = y,
            .z = z,
        };
    }

    fn layoutInit(gpu_backend: gpu.GpuBackend) gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = gpu_backend.layoutBegin(&L.posColorLayout);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Color0, 4, gpu.AttribType.Float, true, false);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Normal, 3, gpu.AttribType.Float, true, false);
        gpu_backend.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};

var _vertex_pos_layout: gpu.VertexLayout = undefined;
var _vertex_col_layout: gpu.VertexLayout = undefined;
var _vertex_col_normal_layout: gpu.VertexLayout = undefined;

//
var draw_call_setttings_type_idx: cdb.TypeIdx = undefined;
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // GPUGeometryCdb
        {
            const type_idx = try _cdb.addType(
                db,
                public.GPUGeometryCdb.name,
                &[_]cdb.PropDef{
                    // .{
                    //     .prop_idx = public.GPUGeometryCdb.propIdx(.handle0),
                    //     .name = "handle0",
                    //     .type = cdb.PropType.U32,
                    // },
                    // .{
                    //     .prop_idx = public.GPUGeometryCdb.propIdx(.handle1),
                    //     .name = "handle1",
                    //     .type = cdb.PropType.U32,
                    // },
                    // .{
                    //     .prop_idx = public.GPUGeometryCdb.propIdx(.handle2),
                    //     .name = "handle2",
                    //     .type = cdb.PropType.U32,
                    // },
                    // .{
                    //     .prop_idx = public.GPUGeometryCdb.propIdx(.handle3),
                    //     .name = "handle3",
                    //     .type = cdb.PropType.U32,
                    // },
                },
            );
            _ = type_idx; // autofix
        }

        // GPUIndexBufferCdb
        {
            const type_idx = try _cdb.addType(
                db,
                public.GPUIndexBufferCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.GPUIndexBufferCdb.propIdx(.handle),
                        .name = "handle",
                        .type = cdb.PropType.U32,
                    },
                },
            );
            _ = type_idx; // autofix
        }

        // ConstNodeSettings
        {
            const type_idx = try _cdb.addType(
                db,
                public.SimpleMeshNodeSettings.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.SimpleMeshNodeSettings.propIdx(.type),
                        .name = "type",
                        .type = .STR,
                    },
                },
            );
            _ = type_idx; // autofix
        }

        // DrawCallNodeSettings
        {
            draw_call_setttings_type_idx = try _cdb.addType(
                db,
                public.DrawCallNodeSettings.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.DrawCallNodeSettings.propIdx(.visibility_flags),
                        .name = "visibility_flags",
                        .type = .SUBOBJECT,
                        .type_hash = visibility_flags.VisibilityFlagsCdb.type_hash,
                    },
                },
            );
        }
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        // _ = db;
        const default_settings = try _cdb.createObject(db, draw_call_setttings_type_idx);
        const default_flags = try _cdb.createObject(db, _cdb.getTypeIdx(db, visibility_flags.VisibilityFlagsCdb.type_hash).?);

        const default_settings_w = _cdb.writeObj(default_settings).?;
        const default_flags_w = _cdb.writeObj(default_flags).?;

        try public.DrawCallNodeSettings.setSubObj(_cdb, default_settings_w, .visibility_flags, default_flags_w);

        try _cdb.writeCommit(default_flags_w);
        try _cdb.writeCommit(default_settings_w);

        _cdb.setDefaultObject(default_settings);
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;

    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _metrics = apidb.getZigApi(module_name, cetech1.metrics.MetricsAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;

    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _vertex_system = apidb.getZigApi(module_name, vertex_system.VertexSystemApi).?;
    _visibility_flags = apidb.getZigApi(module_name, visibility_flags.VisibilityFlagsApi).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &culling_volume_node_i, load);
    try apidb.implOrRemove(module_name, graphvm.NodeI, &draw_call_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.NodeI, &simple_mesh_node_i, load);

    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_geometry_value_type_i, load);
    try apidb.implOrRemove(module_name, graphvm.GraphValueTypeI, &gpu_index_buffer_value_type_i, load);

    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, true);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_renderer_nodes(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}

//
// CUBE
//
const cube_half_size: f32 = 0.5;
const cube_positions = [_]PosVertex{
    .init(-cube_half_size, cube_half_size, cube_half_size),
    .init(cube_half_size, cube_half_size, cube_half_size),
    .init(-cube_half_size, -cube_half_size, cube_half_size),
    .init(cube_half_size, -cube_half_size, cube_half_size),
    .init(-cube_half_size, cube_half_size, -cube_half_size),
    .init(cube_half_size, cube_half_size, -cube_half_size),
    .init(-cube_half_size, -cube_half_size, -cube_half_size),
    .init(cube_half_size, -cube_half_size, -cube_half_size),
    .init(-cube_half_size, cube_half_size, cube_half_size),
    .init(cube_half_size, cube_half_size, cube_half_size),
    .init(-cube_half_size, cube_half_size, -cube_half_size),
    .init(cube_half_size, cube_half_size, -cube_half_size),
    .init(-cube_half_size, -cube_half_size, cube_half_size),
    .init(cube_half_size, -cube_half_size, cube_half_size),
    .init(-cube_half_size, -cube_half_size, -cube_half_size),
    .init(cube_half_size, -cube_half_size, -cube_half_size),
    .init(cube_half_size, -cube_half_size, cube_half_size),
    .init(cube_half_size, cube_half_size, cube_half_size),
    .init(cube_half_size, -cube_half_size, -cube_half_size),
    .init(cube_half_size, cube_half_size, -cube_half_size),
    .init(-cube_half_size, -cube_half_size, cube_half_size),
    .init(-cube_half_size, cube_half_size, cube_half_size),
    .init(-cube_half_size, -cube_half_size, -cube_half_size),
    .init(-cube_half_size, cube_half_size, -cube_half_size),
};

const cube_cololrs = [_]ColorNormalVertex{
    .init(0, 0, 0, 1, 0.0, 0.0, 1.0), // 0
    .init(1, 0, 0, 1, 0.0, 0.0, 1.0), // 1
    .init(0, 1, 0, 1, 0.0, 0.0, 1.0), // 2
    .init(1, 1, 0, 1, 0.0, 0.0, 1.0), // 3
    .init(0, 0, 1, 1, 0.0, 0.0, -1.0), // 4
    .init(1, 0, 1, 1, 0.0, 0.0, -1.0), // 5
    .init(0, 0, 1, 1, 0.0, 0.0, -1.0), // 6
    .init(1, 0, 1, 1, 0.0, 0.0, -1.0), // 7
    .init(0, 0, 0, 1, 0.0, 1.0, 0.0), // 0
    .init(1, 0, 0, 1, 0.0, 1.0, 0.0), // 1
    .init(0, 1, 0, 1, 0.0, 1.0, 0.0), // 2
    .init(1, 1, 0, 1, 0.0, 1.0, 0.0), // 3
    .init(0, 0, 1, 1, 0.0, -1.0, 0.0), // 4
    .init(1, 0, 1, 1, 0.0, -1.0, 0.0), // 5
    .init(0, 0, 1, 1, 0.0, -1.0, 0.0), // 6
    .init(1, 0, 1, 1, 0.0, -1.0, 0.0), // 7
    .init(0, 0, 0, 1, 1.0, 0.0, 0.0), // 0
    .init(1, 0, 0, 1, 1.0, 0.0, 0.0), // 1
    .init(0, 1, 0, 1, 1.0, 0.0, 0.0), // 2
    .init(1, 1, 0, 1, 1.0, 0.0, 0.0), // 3
    .init(0, 0, 1, 1, -1.0, 0.0, 0.0), // 4
    .init(1, 0, 1, 1, -1.0, 0.0, 0.0), // 5
    .init(0, 0, 1, 1, -1.0, 0.0, 0.0), // 6
    .init(1, 0, 1, 1, -1.0, 0.0, 0.0), // 7
};

const cube_tri_list = [_]u16{
    0,  1,  2,
    1,  3,  2,
    4,  6,  5,
    5,  6,  7,

    8,  10, 9,
    9,  10, 11,
    12, 13, 14,
    13, 15, 14,

    16, 17, 18,
    17, 19, 18,
    20, 22, 21,
    21, 22, 23,
};

//
// Plane
//
const plane_half_size = 0.5;
const plan_positions = [_]PosVertex{
    .init(-plane_half_size, 0.0, plane_half_size), // 0
    .init(plane_half_size, 0.0, plane_half_size), // 1
    .init(-plane_half_size, 0.0, -plane_half_size), // 2
    .init(plane_half_size, 0.0, -plane_half_size), // 3
};

const plane_tri_list = [_]u16{
    2, 3, 1,
    2, 1, 0,
};

//
// Bunny
//
const bunny_scale = 0.02;
const bunny_position = [_]PosVertex{
    .{ .x = 25.0883 * bunny_scale, .y = -44.2788 * bunny_scale, .z = 31.0055 * bunny_scale },
    .{ .x = 0.945623 * bunny_scale, .y = 53.5504 * bunny_scale, .z = -24.6146 * bunny_scale },
    .{ .x = -0.94455 * bunny_scale, .y = -14.3443 * bunny_scale, .z = -16.8223 * bunny_scale },
    .{ .x = -20.1103 * bunny_scale, .y = -48.6664 * bunny_scale, .z = 12.6763 * bunny_scale },
    .{ .x = -1.60652 * bunny_scale, .y = -26.3165 * bunny_scale, .z = -24.5424 * bunny_scale },
    .{ .x = -30.6284 * bunny_scale, .y = -53.6299 * bunny_scale, .z = 14.7666 * bunny_scale },
    .{ .x = 1.69145 * bunny_scale, .y = -43.8075 * bunny_scale, .z = -15.2065 * bunny_scale },
    .{ .x = -20.5139 * bunny_scale, .y = 21.0521 * bunny_scale, .z = -5.40868 * bunny_scale },
    .{ .x = -13.9518 * bunny_scale, .y = 53.6299 * bunny_scale, .z = -39.1193 * bunny_scale },
    .{ .x = -21.7912 * bunny_scale, .y = 48.7801 * bunny_scale, .z = -42.0995 * bunny_scale },
    .{ .x = -26.8408 * bunny_scale, .y = 23.6537 * bunny_scale, .z = -17.7324 * bunny_scale },
    .{ .x = -23.1196 * bunny_scale, .y = 33.9692 * bunny_scale, .z = 4.91483 * bunny_scale },
    .{ .x = -12.3236 * bunny_scale, .y = -41.6303 * bunny_scale, .z = 31.8324 * bunny_scale },
    .{ .x = 27.6427 * bunny_scale, .y = -5.05034 * bunny_scale, .z = -11.3201 * bunny_scale },
    .{ .x = 32.2565 * bunny_scale, .y = 1.30521 * bunny_scale, .z = 30.2671 * bunny_scale },
    .{ .x = 47.2723 * bunny_scale, .y = -27.0974 * bunny_scale, .z = 11.1774 * bunny_scale },
    .{ .x = 33.598 * bunny_scale, .y = 10.5888 * bunny_scale, .z = 7.95916 * bunny_scale },
    .{ .x = -13.2898 * bunny_scale, .y = 12.6234 * bunny_scale, .z = 5.55953 * bunny_scale },
    .{ .x = -32.7364 * bunny_scale, .y = 19.0648 * bunny_scale, .z = -10.5736 * bunny_scale },
    .{ .x = -32.7536 * bunny_scale, .y = 31.4158 * bunny_scale, .z = -1.40712 * bunny_scale },
    .{ .x = -25.3672 * bunny_scale, .y = 30.2874 * bunny_scale, .z = -12.4682 * bunny_scale },
    .{ .x = 32.921 * bunny_scale, .y = -36.8408 * bunny_scale, .z = -12.0254 * bunny_scale },
    .{ .x = -37.7251 * bunny_scale, .y = -33.8989 * bunny_scale, .z = 0.378443 * bunny_scale },
    .{ .x = -35.6341 * bunny_scale, .y = -0.246891 * bunny_scale, .z = -9.25165 * bunny_scale },
    .{ .x = -16.7041 * bunny_scale, .y = -50.0254 * bunny_scale, .z = -15.6177 * bunny_scale },
    .{ .x = 24.6604 * bunny_scale, .y = -53.5319 * bunny_scale, .z = -11.1059 * bunny_scale },
    .{ .x = -7.77574 * bunny_scale, .y = -53.5719 * bunny_scale, .z = -16.6655 * bunny_scale },
    .{ .x = 20.6241 * bunny_scale, .y = 13.3489 * bunny_scale, .z = 0.376349 * bunny_scale },
    .{ .x = -44.2889 * bunny_scale, .y = 29.5222 * bunny_scale, .z = 18.7918 * bunny_scale },
    .{ .x = 18.5805 * bunny_scale, .y = 16.3651 * bunny_scale, .z = 12.6351 * bunny_scale },
    .{ .x = -23.7853 * bunny_scale, .y = 31.7598 * bunny_scale, .z = -6.54093 * bunny_scale },
    .{ .x = 24.7518 * bunny_scale, .y = -53.5075 * bunny_scale, .z = 2.14984 * bunny_scale },
    .{ .x = -45.7912 * bunny_scale, .y = -17.6301 * bunny_scale, .z = 21.1198 * bunny_scale },
    .{ .x = 51.8403 * bunny_scale, .y = -33.1847 * bunny_scale, .z = 24.3337 * bunny_scale },
    .{ .x = -47.5343 * bunny_scale, .y = -4.32792 * bunny_scale, .z = 4.06232 * bunny_scale },
    .{ .x = -50.6832 * bunny_scale, .y = -12.442 * bunny_scale, .z = 11.0994 * bunny_scale },
    .{ .x = -49.5132 * bunny_scale, .y = 19.2782 * bunny_scale, .z = 3.17559 * bunny_scale },
    .{ .x = -39.4881 * bunny_scale, .y = 29.0208 * bunny_scale, .z = -6.70431 * bunny_scale },
    .{ .x = -52.7286 * bunny_scale, .y = 1.23232 * bunny_scale, .z = 9.74872 * bunny_scale },
    .{ .x = 26.505 * bunny_scale, .y = -16.1297 * bunny_scale, .z = -17.0487 * bunny_scale },
    .{ .x = -25.367 * bunny_scale, .y = 20.0473 * bunny_scale, .z = -8.44282 * bunny_scale },
    .{ .x = -24.5797 * bunny_scale, .y = -10.3143 * bunny_scale, .z = -18.3154 * bunny_scale },
    .{ .x = -28.6707 * bunny_scale, .y = 6.12074 * bunny_scale, .z = 27.8025 * bunny_scale },
    .{ .x = -16.9868 * bunny_scale, .y = 22.6819 * bunny_scale, .z = 1.37408 * bunny_scale },
    .{ .x = -37.2678 * bunny_scale, .y = 23.9443 * bunny_scale, .z = -9.4945 * bunny_scale },
    .{ .x = -24.8562 * bunny_scale, .y = 21.3763 * bunny_scale, .z = 18.8847 * bunny_scale },
    .{ .x = -47.1879 * bunny_scale, .y = 3.8542 * bunny_scale, .z = -4.74621 * bunny_scale },
    .{ .x = 38.0706 * bunny_scale, .y = -7.33673 * bunny_scale, .z = -7.6099 * bunny_scale },
    .{ .x = -34.8833 * bunny_scale, .y = -3.57074 * bunny_scale, .z = 26.4838 * bunny_scale },
    .{ .x = 12.3797 * bunny_scale, .y = 5.46782 * bunny_scale, .z = 32.9762 * bunny_scale },
    .{ .x = -31.5974 * bunny_scale, .y = -22.956 * bunny_scale, .z = 30.5827 * bunny_scale },
    .{ .x = -6.80953 * bunny_scale, .y = 48.055 * bunny_scale, .z = -18.5116 * bunny_scale },
    .{ .x = 6.3474 * bunny_scale, .y = -15.1622 * bunny_scale, .z = -24.4726 * bunny_scale },
    .{ .x = -25.5733 * bunny_scale, .y = 25.2452 * bunny_scale, .z = -34.4736 * bunny_scale },
    .{ .x = -23.8955 * bunny_scale, .y = 31.8323 * bunny_scale, .z = -40.8696 * bunny_scale },
    .{ .x = -11.8622 * bunny_scale, .y = 38.2304 * bunny_scale, .z = -43.3125 * bunny_scale },
    .{ .x = -20.4918 * bunny_scale, .y = 41.2409 * bunny_scale, .z = -3.11271 * bunny_scale },
    .{ .x = 24.9806 * bunny_scale, .y = -8.53455 * bunny_scale, .z = 37.2862 * bunny_scale },
    .{ .x = -52.8935 * bunny_scale, .y = 5.3376 * bunny_scale, .z = 28.246 * bunny_scale },
    .{ .x = 34.106 * bunny_scale, .y = -41.7941 * bunny_scale, .z = 30.962 * bunny_scale },
    .{ .x = -1.26914 * bunny_scale, .y = 35.6664 * bunny_scale, .z = -18.7177 * bunny_scale },
    .{ .x = -0.13048 * bunny_scale, .y = 44.7288 * bunny_scale, .z = -28.7163 * bunny_scale },
    .{ .x = 2.47929 * bunny_scale, .y = 0.678165 * bunny_scale, .z = -14.6892 * bunny_scale },
    .{ .x = -31.8649 * bunny_scale, .y = -14.2299 * bunny_scale, .z = 32.2998 * bunny_scale },
    .{ .x = -19.774 * bunny_scale, .y = 30.8258 * bunny_scale, .z = 5.77293 * bunny_scale },
    .{ .x = 49.8059 * bunny_scale, .y = -37.125 * bunny_scale, .z = 4.97284 * bunny_scale },
    .{ .x = -28.0581 * bunny_scale, .y = -26.439 * bunny_scale, .z = -14.8316 * bunny_scale },
    .{ .x = -9.12066 * bunny_scale, .y = -27.3987 * bunny_scale, .z = -12.8592 * bunny_scale },
    .{ .x = -13.8752 * bunny_scale, .y = -29.9821 * bunny_scale, .z = 32.5962 * bunny_scale },
    .{ .x = -6.6222 * bunny_scale, .y = -10.9884 * bunny_scale, .z = 33.5007 * bunny_scale },
    .{ .x = -21.2664 * bunny_scale, .y = -53.6089 * bunny_scale, .z = -3.49195 * bunny_scale },
    .{ .x = -0.628672 * bunny_scale, .y = 52.8093 * bunny_scale, .z = -9.88088 * bunny_scale },
    .{ .x = 8.02417 * bunny_scale, .y = 51.8956 * bunny_scale, .z = -21.5834 * bunny_scale },
    .{ .x = -44.6547 * bunny_scale, .y = 11.9973 * bunny_scale, .z = 34.7897 * bunny_scale },
    .{ .x = -7.55466 * bunny_scale, .y = 37.9035 * bunny_scale, .z = -0.574101 * bunny_scale },
    .{ .x = 52.8252 * bunny_scale, .y = -27.1986 * bunny_scale, .z = 11.6429 * bunny_scale },
    .{ .x = -0.934591 * bunny_scale, .y = 9.81861 * bunny_scale, .z = 0.512566 * bunny_scale },
    .{ .x = -3.01043 * bunny_scale, .y = 5.70605 * bunny_scale, .z = 22.0954 * bunny_scale },
    .{ .x = -34.6337 * bunny_scale, .y = 44.5964 * bunny_scale, .z = -31.1713 * bunny_scale },
    .{ .x = -26.9017 * bunny_scale, .y = 35.1991 * bunny_scale, .z = -32.4307 * bunny_scale },
    .{ .x = 15.9884 * bunny_scale, .y = -8.92223 * bunny_scale, .z = -14.7411 * bunny_scale },
    .{ .x = -22.8337 * bunny_scale, .y = -43.458 * bunny_scale, .z = 26.7274 * bunny_scale },
    .{ .x = -31.9864 * bunny_scale, .y = -47.0243 * bunny_scale, .z = 9.36972 * bunny_scale },
    .{ .x = -36.9436 * bunny_scale, .y = 24.1866 * bunny_scale, .z = 29.2521 * bunny_scale },
    .{ .x = -26.5411 * bunny_scale, .y = 29.6549 * bunny_scale, .z = 21.2867 * bunny_scale },
    .{ .x = 33.7644 * bunny_scale, .y = -24.1886 * bunny_scale, .z = -13.8513 * bunny_scale },
    .{ .x = -2.44749 * bunny_scale, .y = -17.0148 * bunny_scale, .z = 41.6617 * bunny_scale },
    .{ .x = -38.364 * bunny_scale, .y = -13.9823 * bunny_scale, .z = -12.5705 * bunny_scale },
    .{ .x = -10.2972 * bunny_scale, .y = -51.6584 * bunny_scale, .z = 38.935 * bunny_scale },
    .{ .x = 1.28109 * bunny_scale, .y = -43.4943 * bunny_scale, .z = 36.6288 * bunny_scale },
    .{ .x = -19.7784 * bunny_scale, .y = -44.0413 * bunny_scale, .z = -4.23994 * bunny_scale },
    .{ .x = 37.0944 * bunny_scale, .y = -53.5479 * bunny_scale, .z = 27.6467 * bunny_scale },
    .{ .x = 24.9642 * bunny_scale, .y = -37.1722 * bunny_scale, .z = 35.7038 * bunny_scale },
    .{ .x = 37.5851 * bunny_scale, .y = 5.64874 * bunny_scale, .z = 21.6702 * bunny_scale },
    .{ .x = -17.4738 * bunny_scale, .y = -53.5734 * bunny_scale, .z = 30.0664 * bunny_scale },
    .{ .x = -8.93088 * bunny_scale, .y = 45.3429 * bunny_scale, .z = -34.4441 * bunny_scale },
    .{ .x = -17.7111 * bunny_scale, .y = -6.5723 * bunny_scale, .z = 29.5162 * bunny_scale },
    .{ .x = 44.0059 * bunny_scale, .y = -17.4408 * bunny_scale, .z = -5.08686 * bunny_scale },
    .{ .x = -46.2534 * bunny_scale, .y = -22.6115 * bunny_scale, .z = 0.702059 * bunny_scale },
    .{ .x = 43.9321 * bunny_scale, .y = -33.8575 * bunny_scale, .z = 4.31819 * bunny_scale },
    .{ .x = 41.6762 * bunny_scale, .y = -7.37115 * bunny_scale, .z = 27.6798 * bunny_scale },
    .{ .x = 8.20276 * bunny_scale, .y = -42.0948 * bunny_scale, .z = -18.0893 * bunny_scale },
    .{ .x = 26.2678 * bunny_scale, .y = -44.6777 * bunny_scale, .z = -10.6835 * bunny_scale },
    .{ .x = 17.709 * bunny_scale, .y = 13.1542 * bunny_scale, .z = 25.1769 * bunny_scale },
    .{ .x = -35.9897 * bunny_scale, .y = 3.92007 * bunny_scale, .z = 35.8198 * bunny_scale },
    .{ .x = -23.9323 * bunny_scale, .y = -37.3142 * bunny_scale, .z = -2.39396 * bunny_scale },
    .{ .x = 5.19169 * bunny_scale, .y = 46.8851 * bunny_scale, .z = -28.7587 * bunny_scale },
    .{ .x = -37.3072 * bunny_scale, .y = -35.0484 * bunny_scale, .z = 16.9719 * bunny_scale },
    .{ .x = 45.0639 * bunny_scale, .y = -28.5255 * bunny_scale, .z = 22.3465 * bunny_scale },
    .{ .x = -34.4175 * bunny_scale, .y = 35.5861 * bunny_scale, .z = -21.7562 * bunny_scale },
    .{ .x = 9.32684 * bunny_scale, .y = -12.6655 * bunny_scale, .z = 42.189 * bunny_scale },
    .{ .x = 1.00938 * bunny_scale, .y = -31.7694 * bunny_scale, .z = 43.1914 * bunny_scale },
    .{ .x = -45.4666 * bunny_scale, .y = -3.71104 * bunny_scale, .z = 19.2248 * bunny_scale },
    .{ .x = -28.7999 * bunny_scale, .y = -50.8481 * bunny_scale, .z = 31.5232 * bunny_scale },
    .{ .x = 35.2212 * bunny_scale, .y = -45.9047 * bunny_scale, .z = 0.199736 * bunny_scale },
    .{ .x = 40.3 * bunny_scale, .y = -53.5889 * bunny_scale, .z = 7.47622 * bunny_scale },
    .{ .x = 29.0515 * bunny_scale, .y = 5.1074 * bunny_scale, .z = -10.002 * bunny_scale },
    .{ .x = 13.4336 * bunny_scale, .y = 4.84341 * bunny_scale, .z = -9.72327 * bunny_scale },
    .{ .x = 11.0617 * bunny_scale, .y = -26.245 * bunny_scale, .z = -24.9471 * bunny_scale },
    .{ .x = -35.6056 * bunny_scale, .y = -51.2531 * bunny_scale, .z = 0.436527 * bunny_scale },
    .{ .x = -10.6863 * bunny_scale, .y = 34.7374 * bunny_scale, .z = -36.7452 * bunny_scale },
    .{ .x = -51.7652 * bunny_scale, .y = 27.4957 * bunny_scale, .z = 7.79363 * bunny_scale },
    .{ .x = -50.1898 * bunny_scale, .y = 18.379 * bunny_scale, .z = 26.3763 * bunny_scale },
    .{ .x = -49.6836 * bunny_scale, .y = -1.32722 * bunny_scale, .z = 26.2828 * bunny_scale },
    .{ .x = 19.0363 * bunny_scale, .y = -16.9114 * bunny_scale, .z = 41.8511 * bunny_scale },
    .{ .x = 32.7141 * bunny_scale, .y = -21.501 * bunny_scale, .z = 36.0025 * bunny_scale },
    .{ .x = 12.5418 * bunny_scale, .y = -28.4244 * bunny_scale, .z = 43.3125 * bunny_scale },
    .{ .x = -19.5634 * bunny_scale, .y = 42.6328 * bunny_scale, .z = -27.0687 * bunny_scale },
    .{ .x = -16.1942 * bunny_scale, .y = 6.55011 * bunny_scale, .z = 19.4066 * bunny_scale },
    .{ .x = 46.9886 * bunny_scale, .y = -18.8482 * bunny_scale, .z = 22.1332 * bunny_scale },
    .{ .x = 45.9697 * bunny_scale, .y = -3.76781 * bunny_scale, .z = 4.10111 * bunny_scale },
    .{ .x = -28.2912 * bunny_scale, .y = 51.3277 * bunny_scale, .z = -35.1815 * bunny_scale },
    .{ .x = -40.2796 * bunny_scale, .y = -27.7518 * bunny_scale, .z = 22.8684 * bunny_scale },
    .{ .x = -22.7984 * bunny_scale, .y = -38.9977 * bunny_scale, .z = 22.158 * bunny_scale },
    .{ .x = 54.0614 * bunny_scale, .y = -35.6096 * bunny_scale, .z = 12.694 * bunny_scale },
    .{ .x = 44.2064 * bunny_scale, .y = -53.6029 * bunny_scale, .z = 18.8679 * bunny_scale },
    .{ .x = 19.789 * bunny_scale, .y = -29.517 * bunny_scale, .z = -19.6094 * bunny_scale },
    .{ .x = -34.3769 * bunny_scale, .y = 34.8566 * bunny_scale, .z = 9.92517 * bunny_scale },
    .{ .x = -23.7518 * bunny_scale, .y = -45.0319 * bunny_scale, .z = 8.71282 * bunny_scale },
    .{ .x = -12.7978 * bunny_scale, .y = 3.55087 * bunny_scale, .z = -13.7108 * bunny_scale },
    .{ .x = -54.0614 * bunny_scale, .y = 8.83831 * bunny_scale, .z = 8.91353 * bunny_scale },
    .{ .x = 16.2986 * bunny_scale, .y = -53.5717 * bunny_scale, .z = 34.065 * bunny_scale },
    .{ .x = -36.6243 * bunny_scale, .y = -53.5079 * bunny_scale, .z = 24.6495 * bunny_scale },
    .{ .x = 16.5794 * bunny_scale, .y = -48.5747 * bunny_scale, .z = 35.5681 * bunny_scale },
    .{ .x = -32.3263 * bunny_scale, .y = 41.4526 * bunny_scale, .z = -18.7388 * bunny_scale },
    .{ .x = -18.8488 * bunny_scale, .y = 9.62627 * bunny_scale, .z = -8.81052 * bunny_scale },
    .{ .x = 5.35849 * bunny_scale, .y = 36.3616 * bunny_scale, .z = -12.9346 * bunny_scale },
    .{ .x = 6.19167 * bunny_scale, .y = 34.497 * bunny_scale, .z = -17.965 * bunny_scale },
};

const bunny_colors = [_]ColorVertex{
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 1, 1),
    .init(1, 0, 1, 1),
    .init(0, 0, 0, 1),
    .init(1, 0, 0, 1),
    .init(0, 1, 0, 1),
    .init(1, 1, 0, 1),
};
const bunny_tri_list = [_]u16{
    80,  2,   52,
    0,   143, 92,
    51,  1,   71,
    96,  128, 77,
    67,  2,   41,
    85,  39,  52,
    58,  123, 38,
    99,  21,  114,
    55,  9,   54,
    136, 102, 21,
    3,   133, 81,
    101, 136, 4,
    5,   82,  3,
    6,   90,  24,
    7,   40,  145,
    33,  75,  134,
    55,  8,   9,
    10,  40,  20,
    46,  140, 38,
    74,  64,  11,
    89,  88,  12,
    147, 60,  7,
    47,  116, 13,
    59,  129, 108,
    147, 72,  106,
    33,  108, 75,
    100, 57,  14,
    129, 130, 15,
    32,  35,  112,
    16,  29,  27,
    107, 98,  132,
    130, 116, 47,
    17,  43,  7,
    54,  44,  53,
    46,  34,  23,
    87,  41,  23,
    40,  10,  18,
    8,   131, 9,
    11,  19,  56,
    11,  137, 19,
    19,  20,  30,
    28,  121, 137,
    122, 140, 36,
    15,  130, 97,
    28,  84,  83,
    114, 21,  102,
    87,  98,  22,
    41,  145, 23,
    133, 68,  12,
    90,  70,  24,
    31,  25,  26,
    98,  34,  35,
    16,  27,  116,
    28,  83,  122,
    29,  103, 77,
    40,  30,  20,
    14,  49,  103,
    31,  26,  142,
    78,  9,   131,
    80,  62,  2,
    6,   67,  105,
    32,  48,  63,
    60,  30,  7,
    33,  135, 91,
    116, 130, 16,
    47,  13,  39,
    70,  119, 5,
    24,  26,  6,
    102, 25,  31,
    103, 49,  77,
    16,  130, 93,
    125, 126, 124,
    111, 86,  110,
    4,   52,  2,
    87,  34,  98,
    4,   6,   101,
    29,  76,  27,
    112, 35,  34,
    6,   4,   67,
    72,  1,   106,
    26,  24,  70,
    36,  37,  121,
    81,  113, 142,
    44,  109, 37,
    122, 58,  38,
    96,  48,  128,
    71,  11,  56,
    73,  122, 83,
    52,  39,  80,
    40,  18,  145,
    82,  5,   119,
    10,  20,  120,
    139, 145, 41,
    3,   142, 5,
    76,  117, 27,
    95,  120, 20,
    104, 45,  42,
    128, 43,  17,
    44,  37,  36,
    128, 45,  64,
    143, 111, 126,
    34,  46,  38,
    97,  130, 47,
    142, 91,  115,
    114, 31,  115,
    125, 100, 129,
    48,  96,  63,
    62,  41,  2,
    69,  77,  49,
    133, 50,  68,
    60,  51,  30,
    4,   118, 52,
    53,  55,  54,
    95,  8,   55,
    121, 37,  19,
    65,  75,  99,
    51,  56,  30,
    14,  57,  110,
    58,  122, 73,
    59,  92,  125,
    42,  45,  128,
    49,  14,  110,
    60,  147, 61,
    76,  62,  117,
    69,  49,  86,
    26,  5,   142,
    46,  44,  36,
    63,  50,  132,
    128, 64,  43,
    75,  108, 15,
    134, 75,  65,
    68,  69,  86,
    62,  76,  145,
    142, 141, 91,
    67,  66,  105,
    69,  68,  96,
    119, 70,  90,
    33,  91,  108,
    136, 118, 4,
    56,  51,  71,
    1,   72,  71,
    23,  18,  44,
    104, 123, 73,
    106, 1,   61,
    86,  111, 68,
    83,  45,  104,
    30,  56,  19,
    15,  97,  99,
    71,  74,  11,
    15,  99,  75,
    25,  102, 6,
    12,  94,  81,
    135, 33,  134,
    138, 133, 3,
    76,  29,  77,
    94,  88,  141,
    115, 31,  142,
    36,  121, 122,
    4,   2,   67,
    9,   78,  79,
    137, 121, 19,
    69,  96,  77,
    13,  62,  80,
    8,   127, 131,
    143, 141, 89,
    133, 12,  81,
    82,  119, 138,
    45,  83,  84,
    21,  85,  136,
    126, 110, 124,
    86,  49,  110,
    13,  116, 117,
    22,  66,  87,
    141, 88,  89,
    64,  45,  84,
    79,  78,  109,
    26,  70,  5,
    14,  93,  100,
    68,  50,  63,
    90,  105, 138,
    141, 0,   91,
    105, 90,  6,
    0,   92,  59,
    17,  145, 76,
    29,  93,  103,
    113, 81,  94,
    39,  85,  47,
    132, 35,  32,
    128, 48,  42,
    93,  29,  16,
    145, 18,  23,
    108, 129, 15,
    32,  112, 48,
    66,  41,  87,
    120, 95,  55,
    96,  68,  63,
    85,  99,  97,
    18,  53,  44,
    22,  98,  107,
    98,  35,  132,
    95,  127, 8,
    137, 64,  84,
    18,  10,  53,
    21,  99,  85,
    54,  79,  44,
    100, 93,  130,
    142, 3,   81,
    102, 101, 6,
    93,  14,  103,
    42,  48,  104,
    87,  23,  34,
    66,  22,  105,
    106, 61,  147,
    72,  74,  71,
    109, 144, 37,
    115, 65,  99,
    107, 132, 133,
    94,  12,  88,
    108, 91,  59,
    43,  64,  74,
    109, 78,  144,
    43,  147, 7,
    91,  135, 115,
    111, 110, 126,
    38,  112, 34,
    142, 113, 94,
    54,  9,   79,
    120, 53,  10,
    138, 3,   82,
    114, 102, 31,
    134, 65,  115,
    105, 22,  107,
    125, 129, 59,
    37,  144, 19,
    17,  76,  77,
    89,  12,  111,
    41,  66,  67,
    13,  117, 62,
    116, 27,  117,
    136, 52,  118,
    51,  60,  61,
    138, 119, 90,
    53,  120, 55,
    68,  111, 12,
    122, 121, 28,
    123, 58,  73,
    110, 57,  124,
    47,  85,  97,
    44,  79,  109,
    126, 125, 92,
    43,  74,  146,
    20,  19,  127,
    128, 17,  77,
    72,  146, 74,
    115, 99,  114,
    140, 122, 38,
    133, 105, 107,
    129, 100, 130,
    131, 144, 78,
    95,  20,  127,
    123, 48,  112,
    102, 136, 101,
    89,  111, 143,
    28,  137, 84,
    133, 132, 50,
    125, 57,  100,
    38,  123, 112,
    124, 57,  125,
    135, 134, 115,
    23,  44,  46,
    136, 85,  52,
    41,  62,  139,
    137, 11,  64,
    104, 48,  123,
    133, 138, 105,
    145, 139, 62,
    25,  6,   26,
    7,   30,  40,
    46,  36,  140,
    141, 143, 0,
    132, 32,  63,
    83,  104, 73,
    19,  144, 127,
    142, 94,  141,
    39,  13,  80,
    92,  143, 126,
    127, 144, 131,
    51,  61,  1,
    91,  0,   59,
    17,  7,   145,
    43,  146, 147,
    146, 72,  147,
};
