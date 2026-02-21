const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const math = cetech1.math;

const light_system = @import("light_system");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const shader_system = @import("shader_system");
const transform = @import("transform");
const bloom = @import("bloom");
const tonemap = @import("tonemap");

const module_name = .default_render_pipeline;

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
    rg_vt: *render_pipeline.RenderPipelineI = undefined,
};
var _g: *G = undefined;

const depth_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "depth",
            .{
                .format = gpu.TextureFormat.D24,
                .flags = .{
                    .rt = .RT,
                },
                .sampler_flags = .{
                    .min_filter = .Point,
                    .max_filter = .Point,
                    .mip_mode = .Point,
                    .u = .Clamp,
                    .v = .Clamp,
                },

                .clear_depth = 1.0,
            },
        );
        try builder.setAttachment(pass, 0, "depth");

        try builder.setMaterialLayer(pass, "depth");
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = pass;

        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);
            e.touch(viewid);
        }
    }
});

const material_pass = render_graph.PassApi.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.createTexture2D(
            pass,
            "hdr",
            .{
                .format = gpu.TextureFormat.RGBA16F,
                .flags = .{
                    .rt = .RT,
                },
                .sampler_flags = .{
                    .min_filter = .Point,
                    .max_filter = .Point,
                    .mip_mode = .Point,
                    .u = .Clamp,
                    .v = .Clamp,
                },
                .clear_color = .fromU32(0x000000FF),
            },
        );

        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "hdr");
        try builder.setAttachment(pass, 1, "depth");

        try builder.setMaterialLayer(pass, "color");
        try builder.enablePass(pass);
    }

    pub fn execute(pass: *const render_graph.Pass, builder: render_graph.GraphBuilder, gpu_backend: gpu.GpuBackend, vp_size: math.Vec2f, viewid: gpu.ViewId) !void {
        _ = builder;
        _ = vp_size;
        _ = pass;
        if (gpu_backend.getEncoder()) |e| {
            defer gpu_backend.endEncoder(e);
            e.touch(viewid);
        }
    }
});

const DefaultPipelineInst = struct {
    allocator: std.mem.Allocator,

    gpu: gpu.GpuBackend,

    time_system: shader_system.System = undefined,
    time_system_uniforms: shader_system.UniformBufferInstance = undefined,

    light_system: light_system.LightSystem = undefined,

    main_module: render_graph.Module = undefined,

    //
    render_module: render_graph.Module = undefined,

    //
    world: ecs.World = undefined,
    postprocess_ent: ecs.EntityId = 0,
};

pub fn fillMainModule(pipeline: *DefaultPipelineInst, module: render_graph.Module) !void {
    try module.addExtensionPoint(render_pipeline.extensions.init);
    try module.addExtensionPoint(render_pipeline.extensions.render);
    try module.addExtensionPoint(render_pipeline.extensions.postprocess);
    try module.addExtensionPoint(render_pipeline.extensions.dd);

    // Geometry passes
    {
        const render_module = try render_graph.createModule();
        try render_module.addPass(.{ .name = "depth_pass", .api = &depth_pass });
        try render_module.addPass(.{ .name = "material_pass", .api = &material_pass });
        try module.addToExtensionPoint(render_pipeline.extensions.render, render_module);

        pipeline.render_module = render_module;
    }

    //
    // DD output
    // TODO: move from tonemap
    {}
}

const render_pipeline_i = render_pipeline.RenderPipelineI.implement(struct {
    pub fn create(allocator: std.mem.Allocator, gpu_backend: gpu.GpuBackend, world: ecs.World) !*anyopaque {
        const inst = try allocator.create(DefaultPipelineInst);

        const time_system = shader_system.findSystemByName(.fromStr("time_system")).?;
        const time_system_io = shader_system.getSystemIO(time_system);

        const pp_ent = world.newEntity(.{ .name = "postprocess" });
        _ = world.setComponent(transform.LocalTransformComponent, pp_ent, &transform.LocalTransformComponent{}); // TODO: because of shaderable needs transform component in query
        _ = world.setComponent(bloom.BloomComponent, pp_ent, &bloom.BloomComponent{});
        _ = world.setComponent(tonemap.TonemapComponent, pp_ent, &tonemap.TonemapComponent{});

        inst.* = .{
            .allocator = allocator,
            .world = world,
            .time_system = time_system,
            .time_system_uniforms = (try shader_system.createUniformBuffer(time_system_io)).?,

            .light_system = try light_system.createLightSystem(gpu_backend),
            .main_module = try render_graph.createModule(),

            .postprocess_ent = pp_ent,
            .gpu = gpu_backend,
        };

        try fillMainModule(inst, inst.main_module);

        return inst;
    }

    pub fn destroy(pipeline: *anyopaque) void {
        var inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        inst.world.destroyEntities(&.{inst.postprocess_ent});

        const time_system_io = shader_system.getSystemIO(inst.time_system);
        shader_system.destroyUniformBuffer(time_system_io, inst.time_system_uniforms);

        light_system.destroyLightSystem(inst.light_system, inst.gpu);

        render_graph.destroyModule(inst.render_module);
        render_graph.destroyModule(inst.main_module);

        inst.allocator.destroy(inst);
    }

    pub fn getMainModule(pipeline: *anyopaque) render_graph.Module {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));
        return inst.main_module;
    }

    pub fn begin(pipeline: *anyopaque, context: *shader_system.SystemContext, now_s: f32) !void {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        // Time system
        try context.addSystem(inst.time_system, inst.time_system_uniforms, null);
        const system_io = shader_system.getSystemIO(inst.time_system);

        try shader_system.updateUniforms(
            system_io,
            inst.time_system_uniforms,
            &.{.{ .name = .fromStr("time"), .value = std.mem.asBytes(&[4]f32{ now_s, 0, 0, 0 }) }},
        );

        // Light system
        try context.addSystem(inst.light_system.system, inst.light_system.uniforms, inst.light_system.resources);
    }

    pub fn end(pipeline: *anyopaque, context: *shader_system.SystemContext) !void {
        _ = pipeline;
        _ = context;
    }

    pub fn uiDebugMenuItems(pipeline: *anyopaque, allocator: std.mem.Allocator) !void {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        try inst.main_module.editorMenuUi(allocator);
    }

    pub fn getGlobalSystem(pipeline: *anyopaque, name: cetech1.StrId32) ?*anyopaque {
        const inst: *DefaultPipelineInst = @ptrCast(@alignCast(pipeline));

        if (name.eql(.fromStr("light_system"))) {
            return &inst.light_system;
        }

        return null;
    }
});

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "DefaultRenderPipeline",
    &[_]cetech1.StrId64{ .fromStr("ShaderSystem"), .fromStr("InstanceSystem") },
    struct {
        pub fn init() !void {

            // Time system
            try shader_system.addSystemDefiniton("time_system", .{
                .imports = &.{
                    .{ .name = "time", .type = .vec4 },
                },
            });

            //
            // Lit shader node
            //
            try shader_system.addShaderDefiniton("node_pbr_lit", .{
                .color_state = .rgb,
                .raster_state = .{
                    .cullmode = .Back,
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = true,
                    .depth_comapre_op = .Equal,
                },

                .graph_node = .{
                    .name = "node_pbr_lit",
                    .display_name = "PBR Lit",
                    .category = "GPU/PBR",

                    .inputs = &.{
                        // Vertexs
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = shader_system.TranspileStages.Vertex },

                        // Surface
                        .{ .name = "albedo", .display_name = "Albedo", .type = .vec4, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "emissive", .display_name = "Emissive", .type = .vec3, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "roughness", .display_name = "Roughness", .type = .float, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "metallic", .display_name = "Metallic", .type = .float, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "occlusion", .display_name = "Occlusion", .type = .float, .stage = shader_system.TranspileStages.Fragment },
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
                    \\  ct_graph_eval(graph, inputs);
                    \\  
                    \\  mat4 model = load_model_transform(inputs, inputs.instance_id);
                    \\
                    \\  #if CT_PIN_CONNECTED(position)
                    \\      //outputs.position = graph.position;
                    \\      outputs.position = mul(model, load_vertex_position(vertex_ctx, inputs.vertex_id, 0));
                    \\  #else
                    \\      outputs.position = mul(model, load_vertex_position(vertex_ctx, inputs.vertex_id, 0));
                    \\  #endif
                    \\
                    \\  outputs.world_position = outputs.position.xyz;
                    \\
                    \\  const mat3 normal_matrix = cofactor(model);
                    \\  outputs.normal = normalize(mul(load_vertex_normal0(vertex_ctx, inputs.vertex_id, 0), normal_matrix));
                    \\
                    \\  outputs.position = mul(u_viewProj, outputs.position);
                    \\  outputs.color0 = load_vertex_color0(vertex_ctx, inputs.vertex_id, 0);
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\
                    \\  ct_graph_eval(graph, inputs);
                    \\
                    \\  const vec3 wp = inputs.world_position;
                    \\  const vec3 V = normalize(load_camera_pos().xyz - wp);
                    \\  const vec3 N = inputs.normal;
                    \\
                    \\  ct_pbr_material mat;
                    \\  #if CT_PIN_CONNECTED(albedo)
                    \\      mat.albedo = graph.albedo;
                    \\  #else
                    \\      mat.albedo = vec4(1, 0, 0, 1);
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(emissive)
                    \\      mat.emissive = graph.emissive;
                    \\  #else
                    \\      mat.emissive = vec3(0, 0, 0);
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(roughness)
                    \\      mat.roughness = graph.roughness;
                    \\  #else
                    \\      mat.roughness = 0.0;
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(metallic)
                    \\      mat.metallic = graph.metallic;
                    \\  #else
                    \\      mat.metallic = 0.0;
                    \\  #endif
                    \\  #if CT_PIN_CONNECTED(occlusion)
                    \\      mat.occlusion = graph.occlusion;
                    \\  #else
                    \\      mat.occlusion = 1.0;
                    \\  #endif
                    \\  const vec3 out_rad = pbr_calc_out_radiance(V, N, wp, mat);
                    \\
                    \\  outputs.color0 = vec4(out_rad, 1.0);
                    \\
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
                                    // TODO: Remove light system, need fragment (null fragmen?)?
                                    .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system", "light_system" },
                                    .depth_stencil_state = .{
                                        .depth_write_enable = true,
                                        .depth_test_enable = true,
                                        .depth_comapre_op = .Less,
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

            //
            // Unlit shader node
            //
            try shader_system.addShaderDefiniton("node_unlit", .{
                .color_state = .rgb,
                .raster_state = .{
                    .cullmode = .Back,
                },

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = true,
                    .depth_comapre_op = .Equal,
                },

                .graph_node = .{
                    .name = "node_unlit",
                    .display_name = "Unlit",
                    .category = "GPU/PBR",

                    .inputs = &.{
                        // Vertexs
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = shader_system.TranspileStages.Vertex },

                        // Surface
                        .{ .name = "color", .display_name = "Color", .type = .vec4, .stage = shader_system.TranspileStages.Fragment },
                        .{ .name = "emissive", .display_name = "Emissive", .type = .vec3, .stage = shader_system.TranspileStages.Fragment },
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
                    \\  ct_graph_eval(graph, inputs);
                    \\  
                    \\  mat4 model = load_model_transform(inputs, inputs.instance_id);
                    \\
                    \\  #if CT_PIN_CONNECTED(position)
                    \\      //outputs.position = graph.position;
                    \\      outputs.position = mul(model, load_vertex_position(vertex_ctx, inputs.vertex_id, 0));
                    \\  #else
                    \\      outputs.position = mul(model, load_vertex_position(vertex_ctx, inputs.vertex_id, 0));
                    \\  #endif
                    \\
                    \\  outputs.world_position = outputs.position.xyz;
                    \\
                    \\  const mat3 normal_matrix = cofactor(model);
                    \\  outputs.normal = normalize(mul(load_vertex_normal0(vertex_ctx, inputs.vertex_id, 0), normal_matrix));
                    \\
                    \\  outputs.position = mul(u_viewProj, outputs.position);
                    \\  outputs.color0 = load_vertex_color0(vertex_ctx, inputs.vertex_id, 0);
                    ,
                },
                .fragment_block = .{
                    .code =
                    \\  ct_graph graph;
                    \\  ct_graph_init(graph);
                    \\
                    \\  ct_graph_eval(graph, inputs);
                    \\  
                    \\  vec4 color = vec4_splat(0);
                    \\  #if CT_PIN_CONNECTED(color)
                    \\      color = graph.color;
                    \\  #endif
                    \\
                    \\  vec3 emissive = vec3_splat(0);
                    \\  #if CT_PIN_CONNECTED(emissive)
                    \\      emissive = graph.emissive;
                    \\  #endif
                    \\  
                    \\  outputs.color0 = color + vec4(emissive, 1);
                    \\
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system" } },
                            },
                        },
                        .{
                            .name = "depth",
                            .variations = &.{
                                .{
                                    .systems = &.{ "time_system", "viewer_system", "vertex_system", "instance_system" },
                                    .depth_stencil_state = .{
                                        .depth_write_enable = true,
                                        .depth_test_enable = true,
                                        .depth_comapre_op = .Less,
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
pub fn load_module_zig(allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;

    try cdb.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try coreui.loadAPI(module_name);
    try ecs.loadAPI(module_name);
    try render_graph.loadAPI(module_name);
    try shader_system.loadAPI(module_name);
    try light_system.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    _g.rg_vt = try apidb.setGlobalVarValue(render_pipeline.RenderPipelineI, module_name, "rg_vt", render_pipeline_i);
    try apidb.implOrRemove(module_name, render_pipeline.RenderPipelineI, _g.rg_vt, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_default_render_pipeline(apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb_, allocator, load, reload);
}
