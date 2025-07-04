const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const zm = cetech1.math.zmath;

const render_viewport = @import("render_viewport");
const render_pipeline = @import("render_pipeline");
const render_graph = @import("render_graph");
const shader_system = @import("shader_system");
const light_system = @import("light_system");

const module_name = .default_render_pipeline;

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
var _gpu: *const gpu.GpuApi = undefined;
var _dd: *const gpu.GpuDDApi = undefined;
var _render_viewport: *const render_viewport.RenderViewportApi = undefined;
var _render_graph: *const render_graph.RenderGraphApi = undefined;
var _shader: *const shader_system.ShaderSystemAPI = undefined;
var _light_system: *const light_system.LightSystemApi = undefined;

// Global state that can surive hot-reload
const G = struct {
    rg_vt: *render_pipeline.RenderPipelineI = undefined,
};
var _g: *G = undefined;

const depth_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "depth",
            .{
                .format = gpu.TextureFormat.D24,
                .flags = 0 |
                    gpu.TextureFlags_Rt |
                    gpu.SamplerFlags_MinPoint |
                    gpu.SamplerFlags_MagPoint |
                    gpu.SamplerFlags_MipPoint |
                    gpu.SamplerFlags_UClamp |
                    gpu.SamplerFlags_VClamp,
                .clear_depth = 1.0,
            },
        );
        try builder.setAttachment(pass, 0, "depth");

        try builder.setMaterialLayer(pass, "depth");
        try builder.enablePass(pass, "depth_pass");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = gpu_api;
        _ = viewid;
    }
});

const simple_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "foo",
            .{
                .format = gpu.TextureFormat.BGRA8,
                .flags = 0 |
                    gpu.TextureFlags_Rt |
                    gpu.SamplerFlags_MinPoint |
                    gpu.SamplerFlags_MagPoint |
                    gpu.SamplerFlags_MipPoint |
                    gpu.SamplerFlags_UClamp |
                    gpu.SamplerFlags_VClamp,

                .clear_color = 0x66CCFFff,
            },
        );
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "foo");
        try builder.setAttachment(pass, 1, "depth");

        try builder.setMaterialLayer(pass, "color");
        try builder.enablePass(pass, "simple_pass");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        gpu_api.touch(viewid);
    }
});

const dd_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.writeTexture(pass, "foo");
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "foo");
        try builder.setAttachment(pass, 1, "depth");

        try builder.setMaterialLayer(pass, "debugdraw");
        try builder.enablePass(pass, "dd_pass");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            const dd = _dd.encoderCreate();
            defer _dd.encoderDestroy(dd);
            {
                dd.begin(viewid, true, e);
                defer dd.end();

                dd.drawGridAxis(.Y, .{ 0, 0, 0 }, 128, 1);
                dd.drawAxis(.{ 0, 0, 0 }, 1.0, .Count, 0);
            }
        }
    }
});

const blit_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.readTexture(pass, "foo");
        try builder.writeTexture(pass, render_viewport.ColorResource);
        try builder.enablePass(pass, "blit");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        const fb_size = vp_size;

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            const out_tex = builder.getTexture(render_viewport.ColorResource).?;
            const foo_tex = builder.getTexture("foo").?;
            e.blit(
                viewid,
                out_tex,
                0,
                0,
                0,
                0,
                foo_tex,
                0,
                0,
                0,
                0,
                @intFromFloat(fb_size[0]),
                @intFromFloat(fb_size[1]),
                0,
            );
        }
    }
});

const DefaultPipelineInst = struct {
    allocator: std.mem.Allocator,

    time_system: shader_system.System = undefined,
    time_system_uniforms: shader_system.UniformBufferInstance = undefined,

    light_system: light_system.LightSystem = undefined,
};

const rg_i = render_pipeline.RenderPipelineI.implement(struct {
    pub fn create(allocator: std.mem.Allocator) !*anyopaque {
        const inst = try allocator.create(DefaultPipelineInst);

        const time_system = _shader.findSystemByName(cetech1.strId32("time_system")).?;
        const time_system_io = _shader.getSystemIO(time_system);

        inst.* = .{
            .allocator = allocator,

            .time_system = time_system,
            .time_system_uniforms = (try _shader.createUniformBuffer(time_system_io)).?,

            .light_system = try _light_system.createLightSystem(),
        };
        return inst;
    }

    pub fn destroy(pipeline: *anyopaque) void {
        var inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));

        const time_system_io = _shader.getSystemIO(inst.time_system);
        _shader.destroyUniformBuffer(time_system_io, inst.time_system_uniforms);

        _light_system.destroyLightSystem(inst.light_system);

        inst.allocator.destroy(inst);
    }

    pub fn fillModule(pipeline: *anyopaque, module: render_graph.Module) !void {
        const inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));
        _ = inst;

        try module.addExtensionPoint(render_pipeline.extensions.init);
        try module.addExtensionPoint(render_pipeline.extensions.render);
        try module.addExtensionPoint(render_pipeline.extensions.dd);

        {
            const render_module = try _render_graph.createModule();
            try render_module.addPass(depth_pass);
            try render_module.addPass(simple_pass);
            try module.addToExtensionPoint(render_pipeline.extensions.render, render_module);
        }

        {
            const dd_module = try _render_graph.createModule();
            try dd_module.addPass(dd_pass);
            try module.addToExtensionPoint(render_pipeline.extensions.dd, dd_module);
        }

        try module.addPass(blit_pass);
    }

    pub fn begin(pipeline: *anyopaque, context: *shader_system.SystemContext, now_s: f32) !void {
        const inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));

        // Time system
        try context.addSystem(inst.time_system, inst.time_system_uniforms, null);
        const system_io = _shader.getSystemIO(inst.time_system);

        try _shader.updateUniforms(
            system_io,
            inst.time_system_uniforms,
            &.{.{ .name = cetech1.strId32("time"), .value = std.mem.asBytes(&[4]f32{ now_s, 0, 0, 0 }) }},
        );

        // Light system
        try context.addSystem(inst.light_system.system, inst.light_system.uniforms, inst.light_system.resources);
    }

    pub fn end(pipeline: *anyopaque, context: *shader_system.SystemContext) !void {
        _ = pipeline;
        _ = context;
    }

    pub fn getGlobalSystem(pipeline: *anyopaque, name: cetech1.StrId32) ?*anyopaque {
        const inst: *DefaultPipelineInst = @alignCast(@ptrCast(pipeline));

        if (name.eql(.fromStr("light_system"))) {
            return &inst.light_system;
        }

        return null;
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "DefaultRenderPipeline",
    &[_]cetech1.StrId64{ cetech1.strId64("ShaderSystem"), cetech1.strId64("InstanceSystem") },
    struct {
        pub fn init() !void {
            // Time system
            try _shader.addSystemDefiniton("time_system", .{
                .imports = &.{
                    .{ .name = "time", .type = .vec4 },
                },
            });

            // Foo output node
            try _shader.addShaderDefiniton("node_foo_output", .{
                .color_state = .rgb,
                .raster_state = .{
                    .cullmode = .back,
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = true,
                    .depth_comapre_op = .equal,
                },

                .graph_node = .{
                    .name = "node_foo_output",
                    .display_name = "Foo Output",
                    .category = "FOO",

                    .inputs = &.{
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = shader_system.TranspileStages.Vertex },
                        .{ .name = "color", .display_name = "Color", .type = .vec4, .stage = shader_system.TranspileStages.Fragment, .contexts = &.{ "default", "color" } },
                    },
                },

                .vertex_block = .{
                    .imports = &.{
                        // .position,
                        // .color0,
                    },
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                        .{ .name = "world_position", .type = .vec3 },
                        .{ .name = "normal", .type = .vec3 },
                    },
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph, vertex_ctx);
                    \\  ct_graph_eval(graph, input);
                    \\  
                    \\  mat4 model = load_model_transform(input, input.instance_id);
                    \\
                    \\  #if CT_PIN_CONNECTED(position)
                    \\      //output.position = graph.position;
                    \\      output.position = mul(model, load_vertex_position(vertex_ctx, input.vertex_id, 0));
                    \\  #else
                    \\      output.position = mul(model, load_vertex_position(vertex_ctx, input.vertex_id, 0));
                    \\  #endif
                    \\
                    \\  output.world_position = output.position;
                    \\  output.normal = load_vertex_normal0(vertex_ctx, input.vertex_id, 0);
                    \\
                    \\  output.position = mul(u_viewProj, output.position);
                    \\
                    \\  // output.color0 = vec4(float(input.vertex_id)/10, 0, 0, 1);
                    \\  output.color0 = load_vertex_color0(vertex_ctx, input.vertex_id, 0);
                    ,
                },
                .fragment_block = .{
                    .exports = &.{
                        .{ .name = "foo", .type = .vec4, .to_node = true },
                    },
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\
                    \\  graph.foo = abs(load_camera_pos())/10.0;
                    \\
                    \\  ct_graph_eval(graph, input);
                    \\
                    \\  #if CT_PIN_CONNECTED(color)
                    \\      output.color0 = graph.color;
                    \\  #else
                    \\      output.color0 = vec4(1, 0, 0, 1);
                    \\  #endif
                    \\  const vec3 normal = input.normal;
                    \\
                    \\  const uint point_light_count = get_point_light_count();
                    \\  const vec3 wp = input.world_position;
                    \\  vec3 out_rad = vec3_splat(0);
                    \\  for (int i = 0; i < point_light_count; i++) {
                    \\      const PointLight l = get_point_light(i);
                    \\      const float dist = length(wp - l.position);
                    \\
                    \\      if(dist > l.radius) continue;
                    \\
                    \\      const vec3 L = normalize(wp - l.position);
                    \\      const float NdL = saturate(dot(normal, -L));
                    \\      out_rad += NdL * l.color;
                    \\  }
                    \\  output.color0 *= vec4(out_rad, 1.0);
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system", "light_system" } },
                            },
                        },
                        .{
                            .name = "depth",
                            .variations = &.{
                                .{
                                    .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system", "light_system" },
                                    .depth_stencil_state = .{
                                        .depth_write_enable = true,
                                        .depth_test_enable = true,
                                        .depth_comapre_op = .less,
                                    },
                                },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .layer = "color", .config = "default" },
                                .{ .layer = "depth", .config = "depth" },
                            },
                        },
                    },
                },
            });
        }

        pub fn shutdown() !void {}
    },
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _apidb = apidb;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _ecs = apidb.getZigApi(module_name, ecs.EcsAPI).?;
    _gpu = apidb.getZigApi(module_name, gpu.GpuApi).?;
    _dd = apidb.getZigApi(module_name, gpu.GpuDDApi).?;
    _render_viewport = apidb.getZigApi(module_name, render_viewport.RenderViewportApi).?;
    _render_graph = apidb.getZigApi(module_name, render_graph.RenderGraphApi).?;
    _shader = apidb.getZigApi(module_name, shader_system.ShaderSystemAPI).?;
    _light_system = apidb.getZigApi(module_name, light_system.LightSystemApi).?;

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    _g.rg_vt = try apidb.setGlobalVarValue(render_pipeline.RenderPipelineI, module_name, "rg_vt", rg_i);
    try apidb.implOrRemove(module_name, render_pipeline.RenderPipelineI, _g.rg_vt, load);

    // impl interface

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_default_render_pipeline(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
