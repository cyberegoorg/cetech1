const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const zm = cetech1.math.zmath;
const light_system = @import("light_system");
const render_graph = @import("render_graph");
const render_pipeline = @import("render_pipeline");
const render_viewport = @import("render_viewport");
const shader_system = @import("shader_system");
const camera = @import("camera");

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
var _camera: *const camera.CameraAPI = undefined;

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
            "hdr",
            .{
                .format = gpu.TextureFormat.RGBA16F,
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

        try builder.setAttachment(pass, 0, "hdr");
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
        try builder.writeTexture(pass, "hdr");
        try builder.readTexture(pass, "depth");

        try builder.setAttachment(pass, 0, "hdr");
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

    fn layoutInit() gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = _gpu.layoutBegin(&L.posColorLayout, _gpu.getBackendType());
        _ = _gpu.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 3, gpu.AttribType.Float, false, false);
        _gpu.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};
var _vertex_pos_layout: gpu.VertexLayout = undefined;
fn screenSpaceQuad(e: gpu.Encoder, origin_mottom_left: bool, width: f32, height: f32) void {
    if (3 == _gpu.getAvailTransientVertexBuffer(3, &_vertex_pos_layout)) {
        var vb: gpu.TransientVertexBuffer = undefined;
        _gpu.allocTransientVertexBuffer(&vb, 3, &_vertex_pos_layout);
        var vertex: [*]PosVertex = @alignCast(@ptrCast(vb.data));

        const zz: f32 = 0.0;

        const minx = -width;
        const maxx = width;
        const miny = 0.0;
        const maxy = height * 2.0;

        var minv: f32 = 0.0;
        var maxv: f32 = 2.0;

        if (origin_mottom_left) {
            const temp = minv;
            minv = maxv;
            maxv = temp;

            minv -= 1.0;
            maxv -= 1.0;
        }

        vertex[0].x = minx;
        vertex[0].y = miny;
        vertex[0].z = zz;

        vertex[1].x = maxx;
        vertex[1].y = miny;
        vertex[1].z = zz;

        vertex[2].x = maxx;
        vertex[2].y = maxy;
        vertex[2].z = zz;

        e.setTransientVertexBuffer(0, &vb, 0, 3);
    }
}

const tonemap_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.readTexture(pass, "hdr");
        try builder.writeTexture(pass, render_viewport.ColorResource);

        try builder.setAttachment(pass, 0, render_viewport.ColorResource);

        try builder.enablePass(pass, "tonemap");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        _ = vp_size;

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            var shader_constext = try _shader.createSystemContext();
            defer _shader.destroySystemContext(shader_constext);

            // TODO:
            //e.setVertexCount(3);

            const hdr_texture = builder.getTexture("hdr").?;

            const shader = _shader.findShaderByName(.fromStr("tonemaping")).?;

            const shader_io = _shader.getShaderIO(shader);

            const rb = (try _shader.createResourceBuffer(shader_io)).?;
            defer _shader.destroyResourceBuffer(shader_io, rb);

            try _shader.updateResources(
                shader_io,
                rb,
                &.{.{ .name = .fromStr("hdr"), .value = .{ .texture = hdr_texture } }},
            );

            _shader.bindResource(shader_io, rb, e);

            const variants = try _shader.selectShaderVariant(
                _allocator,
                shader,
                &.{.fromStr("viewport")},
                &shader_constext,
            );
            defer _allocator.free(variants);
            const variant = variants[0];

            const projMtx = zm.matToArr(zm.orthographicOffCenterRh(0, 1, 1, 0, 0, 100));
            _gpu.setViewTransform(viewid, null, &projMtx);

            screenSpaceQuad(e, false, 1, 1);

            e.setState(variant.state, variant.rgba);
            e.submit(viewid, variant.prg.?, 0, gpu.DiscardFlags_None);
        }
    }
});

const blit_pass = render_graph.Pass.implement(struct {
    pub fn setup(pass: *render_graph.Pass, builder: render_graph.GraphBuilder) !void {
        try builder.readTexture(pass, "hdr");
        try builder.writeTexture(pass, render_viewport.ColorResource);
        try builder.enablePass(pass, "blit");
    }

    pub fn execute(builder: render_graph.GraphBuilder, gpu_api: *const gpu.GpuApi, vp_size: [2]f32, viewid: gpu.ViewId) !void {
        const fb_size = vp_size;

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            const out_tex = builder.getTexture(render_viewport.ColorResource).?;
            const foo_tex = builder.getTexture("hdr").?;
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

        try module.addPass(tonemap_pass);
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
            _vertex_pos_layout = PosVertex.layoutInit();

            // Time system
            try _shader.addSystemDefiniton("time_system", .{
                .imports = &.{
                    .{ .name = "time", .type = .vec4 },
                },
            });

            // Foo output node
            try _shader.addShaderDefiniton("node_pbr_lit", .{
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
                    .name = "node_pbr_lit",
                    .display_name = "PBR Lit",
                    .category = "PBR",

                    .inputs = &.{
                        // Vertexs
                        .{ .name = "position", .display_name = "Position", .type = .vec4, .stage = shader_system.TranspileStages.Vertex },

                        // Surface
                        .{ .name = "albedo", .display_name = "Albedo", .type = .vec4, .stage = shader_system.TranspileStages.Fragment, .contexts = &.{ "default", "color" } },
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
                    \\  const uint point_light_count = get_point_light_count();
                    \\  const vec3 wp = input.world_position;
                    \\  const vec3 V = normalize(load_camera_pos() - wp);
                    \\  const vec3 N = input.normal;
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
                    \\  output.color0 = vec4(out_rad, 1.0);
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

            // Foo output node
            try _shader.addShaderDefiniton("tonemaping", .{
                .color_state = .rgb,

                .depth_stencil_state = .{
                    .depth_write_enable = false,
                    .depth_test_enable = false,
                },
                .imports = &.{
                    .{ .name = "hdr", .type = .sampler2d },
                },
                .vertex_block = .{
                    .imports = &.{
                        .position,
                    },
                    .import_semantic = &.{.vertex_id},
                    .exports = &.{
                        .{ .name = "color0", .type = .vec4 },
                    },
                    .code =
                    \\  output.position = mul(u_modelViewProj, vec4(a_position, 1.0));
                    ,
                },
                .fragment_block = .{
                    .common_block =
                    \\vec3 tonemap_reinhard(vec3 color) {
                    \\    return color / (color + 1.0);
                    \\}
                    ,

                    .code =
                    \\  vec2 tex_coord = gl_FragCoord.xy * u_viewTexel.xy;
                    \\  vec3 color = texture2D(get_hdr_sampler(), tex_coord);
                    \\
                    \\  output.color0 = vec4(tonemap_reinhard(color), 1.0);
                    ,
                },

                .compile = .{
                    .includes = &.{"shaderlib"},
                    .configurations = &.{
                        .{
                            .name = "default",
                            .variations = &.{
                                .{ .systems = &.{} },
                            },
                        },
                    },
                    .contexts = &.{
                        .{
                            .name = "viewport",
                            .defs = &.{
                                .{ .config = "default" },
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
    _camera = apidb.getZigApi(module_name, camera.CameraAPI).?;

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
