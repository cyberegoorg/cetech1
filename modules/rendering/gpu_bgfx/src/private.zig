const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const profiler = cetech1.profiler;
const task = cetech1.task;
const tempalloc = cetech1.tempalloc;

const public = cetech1.gpu;

const zm = cetech1.math.zmath;

const bgfx_shader = @embedFile("embed/bgfx_shader.sh");
const bgfx_compute = @embedFile("embed/bgfx_compute.sh");
const core_shader = bgfx_shader ++ "\n\n" ++ bgfx_compute;

const module_name = .gpu_bgfx;

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
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

var _metrics: *const cetech1.metrics.MetricsAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _coreui: *const cetech1.coreui.CoreUIApi = undefined;

// Global state
const G = struct {};

var _g: *G = undefined;

const ThreadId = std.Thread.Id;
const EncoderMap = cetech1.AutoArrayHashMap(ThreadId, *bgfx.Encoder);

const EncoderArray = cetech1.ArrayList(?*bgfx.Encoder);
const PalletColorMap = cetech1.AutoArrayHashMap(u32, u8);

pub const PrimitiveType = enum {
    pub fn toState(self: public.PrimitiveType) bgfx.StateFlags {
        return switch (self) {
            .triangles => 0,
            .triangles_strip => bgfx.StateFlags_PtTristrip,
            .lines => bgfx.StateFlags_PtLines,
            .lines_strip => bgfx.StateFlags_PtLinestrip,
            .points => bgfx.StateFlags_PtPoints,
        };
    }
};

pub const RasterState = struct {
    pub fn toState(self: public.RasterState) bgfx.StateFlags {
        var r: u64 = bgfx.StateFlags_None;

        if (self.cullmode) |cullmode| {
            switch (cullmode) {
                .front => {
                    if (self.front_face) |front_face| {
                        switch (front_face) {
                            .cw => {
                                r |= bgfx.StateFlags_CullCw;
                            },
                            .ccw => {
                                r |= bgfx.StateFlags_CullCcw;
                                r |= bgfx.StateFlags_FrontCcw;
                            },
                        }
                    } else {
                        r |= bgfx.StateFlags_CullCcw;
                        r |= bgfx.StateFlags_FrontCcw;
                    }
                },
                .back => {
                    if (self.front_face) |front_face| {
                        switch (front_face) {
                            .cw => {
                                r |= bgfx.StateFlags_CullCcw;
                            },
                            .ccw => {
                                r |= bgfx.StateFlags_CullCw;
                                r |= bgfx.StateFlags_FrontCcw;
                            },
                        }
                    } else {
                        r |= bgfx.StateFlags_CullCw;
                    }
                },
                .none => {},
            }
        }

        if (self.front_face) |front_face| {
            switch (front_face) {
                .cw => {},
                .ccw => {
                    r |= bgfx.StateFlags_FrontCcw;
                },
            }
        }

        return r;
    }
};

pub const DepthStencilState = struct {
    pub fn toState(self: public.DepthStencilState) bgfx.StateFlags {
        var r: u64 = bgfx.StateFlags_None;

        if (self.depth_test_enable) |depth_test_enable| {
            if (depth_test_enable) {
                if (self.depth_comapre_op) |depth_comapre_op| {
                    switch (depth_comapre_op) {
                        .never => r |= bgfx.StateFlags_DepthTestNever,
                        .less => r |= bgfx.StateFlags_DepthTestLess,
                        .equal => r |= bgfx.StateFlags_DepthTestEqual,
                        .less_equal => r |= bgfx.StateFlags_DepthTestLequal,
                        .greater => r |= bgfx.StateFlags_DepthTestGreater,
                        .not_equal => r |= bgfx.StateFlags_DepthTestNotequal,
                        .greater_equal => r |= bgfx.StateFlags_DepthTestGequal,
                    }
                }
            }
        }

        if (self.depth_write_enable) |depth_write_enable| {
            if (depth_write_enable) r |= bgfx.StateFlags_WriteZ;
        }

        return r;
    }
};

pub const ColorState = struct {
    pub fn toState(self: public.ColorState) bgfx.StateFlags {
        var r: u64 = bgfx.StateFlags_None;

        if (self.write_r) |write_r| {
            if (write_r) r |= bgfx.StateFlags_WriteR;
        }

        if (self.write_g) |write_g| {
            if (write_g) r |= bgfx.StateFlags_WriteG;
        }

        if (self.write_b) |write_b| {
            if (write_b) r |= bgfx.StateFlags_WriteB;
        }

        if (self.write_a) |write_a| {
            if (write_a) r |= bgfx.StateFlags_WriteA;
        }

        return r;
    }
};

fn blendColorEquationToBgfx(equation: public.BlendEquation) bgfx.StateFlags {
    return switch (equation) {
        .Add => bgfx.StateFlags_BlendEquationAdd,
        .Sub => bgfx.StateFlags_BlendEquationSub,
        .Revsub => bgfx.StateFlags_BlendEquationRevsub,
        .Min => bgfx.StateFlags_BlendEquationMin,
        .Max => bgfx.StateFlags_BlendEquationMax,
    };
}

fn blendColorFunctionToBgfx(factor: public.BlendFunction) bgfx.StateFlags {
    return switch (factor) {
        .Zero => bgfx.StateFlags_BlendZero,
        .One => bgfx.StateFlags_BlendOne,
        .Src_color => bgfx.StateFlags_BlendSrcColor,
        .Inv_src_color => bgfx.StateFlags_BlendInvSrcColor,
        .Src_alpha => bgfx.StateFlags_BlendSrcAlpha,
        .Inv_src_alpha => bgfx.StateFlags_BlendInvSrcAlpha,
        .Dst_alpha => bgfx.StateFlags_BlendDstAlpha,
        .Inv_dst_alpha => bgfx.StateFlags_BlendInvDstAlpha,
        .Dst_color => bgfx.StateFlags_BlendDstColor,
        .Inv_dst_color => bgfx.StateFlags_BlendInvDstColor,
        .Src_alpha_sat => bgfx.StateFlags_BlendSrcAlphaSat,
    };
}

fn BGFX_STATE_BLEND_FUNC_SEPARATE(srcRGB: u64, dstRGB: u64, srcA: u64, dstA: u64) bgfx.StateFlags {
    return 0 | (((srcRGB) | ((dstRGB) << 4))) | (((srcA) | ((dstA) << 4)) << 8);
}

fn BGFX_STATE_BLEND_EQUATION_SEPARATE(equationRGB: u64, equationA: u64) bgfx.StateFlags {
    return 0 | ((equationRGB) | ((equationA) << 3));
}

pub const BlendState = struct {
    pub fn toState(self: public.BlendState) bgfx.StateFlags {
        const color_equation: bgfx.StateFlags = if (self.color_equation) |c| blendColorEquationToBgfx(c) else 0;
        const source_color_factor: bgfx.StateFlags = if (self.source_color_factor) |c| blendColorFunctionToBgfx(c) else 0;
        const destination_color_factor: bgfx.StateFlags = if (self.destination_color_factor) |c| blendColorFunctionToBgfx(c) else 0;
        const alpha_equation: bgfx.StateFlags = if (self.alpha_equation) |c| blendColorEquationToBgfx(c) else 0;
        const source_alpha_factor: bgfx.StateFlags = if (self.source_alpha_factor) |c| blendColorFunctionToBgfx(c) else 0;
        const destination_alpha_factor: bgfx.StateFlags = if (self.destination_alpha_factor) |c| blendColorFunctionToBgfx(c) else 0;

        return 0 |
            BGFX_STATE_BLEND_FUNC_SEPARATE(source_color_factor, destination_color_factor, source_alpha_factor, destination_alpha_factor) |
            BGFX_STATE_BLEND_EQUATION_SEPARATE(color_equation, alpha_equation);
    }
};

pub const RenderState = struct {
    pub fn toState(self: public.RenderState) bgfx.StateFlags {
        var r: u64 = bgfx.StateFlags_None;
        r |= RasterState.toState(self.raster_state);
        r |= DepthStencilState.toState(self.depth_stencil_state);
        r |= ColorState.toState(self.color_state);
        r |= BlendState.toState(self.blend_state);
        r |= PrimitiveType.toState(self.primitive_type);
        return r;
    }
};

pub const SamplerFlags = struct {
    pub fn toState(self: public.SamplerFlags) bgfx.StateFlags {
        var r: u64 = bgfx.SamplerFlags_None;
        r |= 0;

        if (self.min_filter) |min_filter| {
            r |= switch (min_filter) {
                .point => bgfx.SamplerFlags_MinPoint,
                .linear => 0,
            };
        }

        if (self.max_filter) |max_filter| {
            r |= switch (max_filter) {
                .point => bgfx.SamplerFlags_MagPoint,
                .linear => 0,
            };
        }

        if (self.mip_mode) |mip_mode| {
            r |= switch (mip_mode) {
                .point => bgfx.SamplerFlags_MinPoint,
                .linear => 0,
            };
        }

        if (self.u) |adress_u| {
            r |= switch (adress_u) {
                .clamp => bgfx.SamplerFlags_UClamp,
                .border => bgfx.SamplerFlags_UBorder,
                .wrap => 0,
            };
        }
        if (self.v) |adress_v| {
            r |= switch (adress_v) {
                .clamp => bgfx.SamplerFlags_VClamp,
                .border => bgfx.SamplerFlags_VBorder,
                .wrap => 0,
            };
        }
        if (self.w) |adress_w| {
            r |= switch (adress_w) {
                .clamp => bgfx.SamplerFlags_WClamp,
                .border => bgfx.SamplerFlags_WBorder,
                .wrap => 0,
            };
        }

        return r;
    }
};

pub const TextureFlags = struct {
    pub fn toState(self: public.TextureFlags) bgfx.TextureFlags {
        var r = bgfx.TextureFlags_None;
        r |= 0;

        if (self.msaa_sample) r |= bgfx.TextureFlags_MsaaSample;
        if (self.compute_write) r |= bgfx.TextureFlags_ComputeWrite;
        if (self.srgb) r |= bgfx.TextureFlags_Srgb;
        if (self.blit_dst) r |= bgfx.TextureFlags_BlitDst;
        if (self.read_back) r |= bgfx.TextureFlags_ReadBack;
        if (self.rt_write_only) r |= bgfx.TextureFlags_RtWriteOnly;

        r |= switch (self.rt) {
            .no_rt => 0,
            .rt => bgfx.TextureFlags_RtWriteOnly,
            .mssaa_x2 => bgfx.TextureFlags_RtMsaaX2,
            .mssaa_x4 => bgfx.TextureFlags_RtMsaaX4,
            .mssaa_x8 => bgfx.TextureFlags_RtMsaaX8,
            .mssaa_x16 => bgfx.TextureFlags_RtMsaaX16,
        };

        return r;
    }
};

pub const BufferFlags = struct {
    pub fn toState(self: public.BufferFlags) bgfx.BufferFlags {
        var r = bgfx.BufferFlags_None;
        r |= 0;

        if (self.allow_resize) r |= bgfx.BufferFlags_AllowResize;
        if (self.draw_indirect) r |= bgfx.BufferFlags_DrawIndirect;
        if (self.index_32) r |= bgfx.BufferFlags_Index32;

        if (self.compute_access) |compute_access| {
            r |= switch (compute_access) {
                .read => bgfx.BufferFlags_ComputeRead,
                .write => bgfx.BufferFlags_ComputeWrite,
                .read_write => bgfx.BufferFlags_ComputeReadWrite,
            };
        }

        if (self.compute_type) |compute_type| {
            r |= switch (compute_type) {
                .int => bgfx.BufferFlags_ComputeTypeInt,
                .uint => bgfx.BufferFlags_ComputeTypeUint,
                .float => bgfx.BufferFlags_ComputeTypeFloat,
            };
        }
        if (self.compute_format) |compute_format| {
            r |= switch (compute_format) {
                .x8x1 => bgfx.BufferFlags_ComputeFormat8x1,
                .x8x2 => bgfx.BufferFlags_ComputeFormat8x2,
                .x8x4 => bgfx.BufferFlags_ComputeFormat8x4,
                .x16x1 => bgfx.BufferFlags_ComputeFormat16x1,
                .x16x2 => bgfx.BufferFlags_ComputeFormat16x2,
                .x16x4 => bgfx.BufferFlags_ComputeFormat16x4,
                .x32x1 => bgfx.BufferFlags_ComputeFormat32x1,
                .x32x2 => bgfx.BufferFlags_ComputeFormat32x2,
                .x32x4 => bgfx.BufferFlags_ComputeFormat32x4,
            };
        }
        return r;
    }
};

const DiscardFlags = struct {
    pub fn toState(self: public.DiscardFlags) u8 {
        var r: u8 = bgfx.DiscardFlags_None;

        if (self.Bindings) r |= bgfx.DiscardFlags_Bindings;
        if (self.IndexBuffer) r |= bgfx.DiscardFlags_IndexBuffer;
        if (self.State) r |= bgfx.DiscardFlags_State;
        if (self.Transform) r |= bgfx.DiscardFlags_Transform;
        if (self.VertexStreams) r |= bgfx.DiscardFlags_VertexStreams;

        return r;
    }
};

pub const ResetFlags = struct {
    pub fn toState(self: public.ResetFlags) bgfx.ResetFlags {
        var r = bgfx.ResetFlags_None;

        if (self.msaa) |msaa| {
            r |= switch (msaa) {
                .x2 => bgfx.ResetFlags_MsaaX2,
                .x4 => bgfx.ResetFlags_MsaaX4,
                .x8 => bgfx.ResetFlags_MsaaX8,
                .x16 => bgfx.ResetFlags_MsaaX16,
            };
        }

        if (self.Fullscreen) r |= bgfx.ResetFlags_Fullscreen;
        if (self.Vsync) r |= bgfx.ResetFlags_Vsync;
        if (self.Maxanisotropy) r |= bgfx.ResetFlags_Maxanisotropy;
        if (self.Capture) r |= bgfx.ResetFlags_Capture;
        if (self.FlushAfterRender) r |= bgfx.ResetFlags_FlushAfterRender;
        if (self.FlipAfterRender) r |= bgfx.ResetFlags_FlipAfterRender;
        if (self.SrgbBackbuffer) r |= bgfx.ResetFlags_SrgbBackbuffer;
        if (self.Hdr10) r |= bgfx.ResetFlags_Hdr10;
        if (self.Hidpi) r |= bgfx.ResetFlags_Hidpi;
        if (self.DepthClamp) r |= bgfx.ResetFlags_DepthClamp;
        if (self.Suspend) r |= bgfx.ResetFlags_Suspend;
        if (self.TransparentBackbuffer) r |= bgfx.ResetFlags_TransparentBackbuffer;

        return r;
    }
};

pub const ClearFlags = struct {
    pub fn toState(self: public.ClearFlags) bgfx.ClearFlags {
        var r = bgfx.ClearFlags_None;

        if (self.Color) r |= bgfx.ClearFlags_Color;
        if (self.Depth) r |= bgfx.ClearFlags_Depth;
        if (self.Stencil) r |= bgfx.ClearFlags_Stencil;
        if (self.DiscardColor0) r |= bgfx.ClearFlags_DiscardColor0;
        if (self.DiscardColor1) r |= bgfx.ClearFlags_DiscardColor1;
        if (self.DiscardColor2) r |= bgfx.ClearFlags_DiscardColor2;
        if (self.DiscardColor3) r |= bgfx.ClearFlags_DiscardColor3;
        if (self.DiscardColor4) r |= bgfx.ClearFlags_DiscardColor4;
        if (self.DiscardColor5) r |= bgfx.ClearFlags_DiscardColor5;
        if (self.DiscardColor6) r |= bgfx.ClearFlags_DiscardColor6;
        if (self.DiscardColor7) r |= bgfx.ClearFlags_DiscardColor7;
        if (self.DiscardDepth) r |= bgfx.ClearFlags_DiscardDepth;
        if (self.DiscardStencil) r |= bgfx.ClearFlags_DiscardStencil;

        return r;
    }
};

const NullVertex = struct {
    f: f32 = 0,

    fn layoutInit() public.VertexLayout {
        // static local
        const L = struct {
            var layout = std.mem.zeroes(public.VertexLayout);
        };
        _ = backend_api.layoutBegin(&L.layout);
        _ = backend_api.layoutAdd(&L.layout, public.Attrib.Position, 1, public.AttribType.Float, false, false);
        backend_api.layoutEnd(&L.layout);
        return L.layout;
    }
};

const FloatBufferVertex = struct {
    f: f32 = 0,

    fn layoutInit() public.VertexLayout {
        // static local
        const L = struct {
            var layout = std.mem.zeroes(public.VertexLayout);
        };
        _ = backend_api.layoutBegin(&L.layout);
        _ = backend_api.layoutAdd(&L.layout, public.Attrib.Position, 1, public.AttribType.Float, false, false);
        backend_api.layoutEnd(&L.layout);
        return L.layout;
    }
};

pub const Backend = enum(c_int) {
    /// No rendering.
    noop,

    /// AGC
    agc,

    /// Direct3D 11.0
    dx11,

    /// Direct3D 12.0
    dx12,

    /// GNM
    gnm,

    /// Metal
    metal,

    /// NVN
    nvn,

    /// OpenGL ES 2.0+
    opengl_es,

    /// OpenGL 2.1+
    opengl,

    /// Vulkan
    vulkan,

    /// Auto select best
    auto,

    pub fn fromString(str: []const u8) Backend {
        return std.meta.stringToEnum(Backend, str) orelse .auto;
    }
};

const embed_varying_def =
    \\vec4 v_color0    : COLOR0    = vec4(1.0, 0.0, 0.0, 1.0);
    \\vec2 v_texcoord0 : TEXCOORD0 = vec2(0.0, 0.0);
    \\
    \\vec2 a_position  : POSITION;
    \\vec4 a_color0    : COLOR0;
    \\vec2 a_texcoord0 : TEXCOORD0;
    \\
;
const fs_imgui_image_code = std.fmt.comptimePrint(
    \\$input v_texcoord0
    \\
    \\{[bgfx]s}
    \\
    \\uniform vec4 u_imageLodEnabled;
    \\SAMPLER2D(s_texColor, 0);
    \\#define u_imageLod     u_imageLodEnabled.x
    \\#define u_imageEnabled u_imageLodEnabled.y
    \\void main()
    \\{{
    \\vec3 color = texture2DLod(s_texColor, v_texcoord0, u_imageLod).xyz;
    \\float alpha = 0.2 + 0.8*u_imageEnabled;
    \\gl_FragColor = vec4(color, alpha);
    \\}}
    \\
, .{ .bgfx = core_shader });
const fs_ocornut_imgui_code = std.fmt.comptimePrint(
    \\$input v_color0, v_texcoord0
    \\
    \\{[bgfx]s}
    \\
    \\SAMPLER2D(s_tex, 0);
    \\
    \\void main()
    \\{{
    \\vec4 texel = texture2D(s_tex, v_texcoord0);
    \\gl_FragColor = texel * v_color0;
    \\}}
    \\
, .{ .bgfx = core_shader });
const vs_imgui_image_code = std.fmt.comptimePrint(
    \\$input a_position, a_texcoord0
    \\$output v_texcoord0
    \\
    \\{[bgfx]s}
    \\
    \\void main()
    \\{{
    \\gl_Position = mul(u_viewProj, vec4(a_position.xy, 0.0, 1.0) );
    \\v_texcoord0 = a_texcoord0;
    \\}}
    \\
, .{ .bgfx = core_shader });
const vs_ocornut_imgui_code = std.fmt.comptimePrint(
    \\$input a_position, a_texcoord0, a_color0
    \\$output v_color0, v_texcoord0
    \\
    \\{[bgfx]s}
    \\
    \\void main()
    \\{{
    \\vec4 pos = mul(u_viewProj, vec4(a_position.xy, 0.0, 1.0) );
    \\gl_Position = vec4(pos.x, pos.y, 0.0, 1.0);
    \\v_texcoord0 = a_texcoord0;
    \\v_color0    = a_color0;
    \\}}
    \\
, .{ .bgfx = core_shader });

pub const backend_api = public.GpuBackendApi.implement(struct {
    pub fn destroyBackend(self: *anyopaque) void {
        const inst: *BgfxBackend = @ptrCast(@alignCast(self));

        if (inst.bgfx_init) {
            backend_api.destroyVertexBuffer(inst, inst.null_vb);

            if (inst.coreui_program.isValid()) {
                backend_api.destroyProgram(inst, inst.coreui_program);
            }

            if (inst.coreui_image_program.isValid()) {
                backend_api.destroyProgram(inst, inst.coreui_image_program);
            }

            const Task = struct {
                inst: *BgfxBackend,
                pub fn exec(selff: *@This()) !void {
                    zbgfx.debugdraw.deinit();
                    bgfx.shutdown();
                    selff.inst.encoders.deinit(_allocator);
                }
            };
            const task_id = _task.schedule(
                cetech1.task.TaskID.none,
                Task{ .inst = inst },
                .{ .affinity = 1 },
            ) catch undefined;
            while (!_task.isDone(task_id)) {
                std.Thread.sleep(1 * std.time.ns_per_ms);
                _ = bgfx.renderFrame(0);
            }
        }
        inst.pallet_map.deinit(_allocator);

        _allocator.destroy(inst);
    }

    pub fn getWindow(self: *anyopaque) ?cetech1.platform.Window {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));
        return context.window;
    }
    pub fn getResolution(self: *anyopaque) public.Resolution {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));

        const b = std.mem.toBytes(context.bgfxInit.resolution);
        return std.mem.bytesToValue(public.Resolution, &b);
    }
    pub fn addPaletteColor(self: *anyopaque, color: u32) u8 {
        const inst: *BgfxBackend = @ptrCast(@alignCast(self));

        const pallet_id = inst.pallet_map.get(color);
        if (pallet_id) |id| return id;

        const idx: u8 = @truncate(pallet_id_counter.fetchAdd(1, .monotonic));

        bgfx.setPaletteColorRgba8(idx, color);
        inst.pallet_map.put(_allocator, color, idx) catch undefined;

        return idx;
    }
    pub fn endAllUsedEncoders(self: *anyopaque) void {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));

        var zone_ctx = _profiler.ZoneN(@src(), "endAllUsedEncoders");
        defer zone_ctx.End();

        // log.debug("Begin end encoders", .{});
        for (context.encoders.items) |*value| {
            if (value.*) |e| {
                // log.debug("End encoder {} {}", .{ idx, e });
                bgfx.encoderEnd(@ptrCast(e));
            }
            value.* = null;
        }
        // log.debug("End end encoders", .{});
    }
    pub fn isNoop(self: *anyopaque) bool {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));
        return context.bgfx_backend == .Noop;
    }
    pub fn compileShader(self: *anyopaque, allocator: std.mem.Allocator, varying: []const u8, shader: []const u8, options: public.ShadercOptions) anyerror![]u8 {
        _ = self;
        log.debug("Compile {s} shader", .{@tagName(options.shaderType)});

        const exe = try zbgfx.shaderc.shadercFromExePath(allocator);
        defer allocator.free(exe);
        const opts: zbgfx.shaderc.ShadercOptions = std.mem.bytesToValue(zbgfx.shaderc.ShadercOptions, std.mem.asBytes(&options));
        return zbgfx.shaderc.compileShader(allocator, exe, varying, shader, opts);
    }
    pub fn createDefaultOptionsForRenderer(self: *anyopaque) public.ShadercOptions {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));
        if (context.bgfx_backend == .Noop) {
            return .{ .shaderType = .fragment, .platform = .linux, .profile = .spirv };
        }

        const res = zbgfx.shaderc.createDefaultOptionsForRenderer(zbgfx.bgfx.getRendererType());

        return .{
            .shaderType = @enumFromInt(@intFromEnum(res.shaderType)),
            .platform = @enumFromInt(@intFromEnum(res.platform)),
            .profile = @enumFromInt(@intFromEnum(res.profile)),
            .inputFilePath = res.inputFilePath,
            .outputFilePath = res.outputFilePath,
            .varyingFilePath = res.varyingFilePath,
            .includeDirs = res.includeDirs,
            .defines = res.defines,
            .optimizationLevel = @enumFromInt(@intFromEnum(res.optimizationLevel)),
        };
    }
    pub fn isHomogenousDepth(self: *anyopaque) bool {
        _ = self;
        const caps = bgfx.getCaps().*;
        return caps.homogeneousDepth;
    }
    pub fn getNullVb(self: *anyopaque) public.VertexBufferHandle {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));
        return context.null_vb;
    }
    pub fn getFloatBufferLayout(self: *anyopaque) *const public.VertexLayout {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));
        return &context.float_buffer_layout;
    }
    pub fn reset(self: *anyopaque, _width: u32, _height: u32, _flags: public.ResetFlags, _format: public.TextureFormat) void {
        _ = self;
        zbgfx.bgfx.reset(_width, _height, ResetFlags.toState(_flags), @enumFromInt(@intFromEnum(_format)));
    }
    pub fn frame(self: *anyopaque, _capture: bool) u32 {
        _ = self;
        return zbgfx.bgfx.frame(_capture);
    }
    pub fn alloc(self: *anyopaque, _size: u32) *const public.Memory {
        _ = self;
        return @ptrCast(zbgfx.bgfx.alloc(_size));
    }
    pub fn copy(self: *anyopaque, _data: ?*const anyopaque, _size: u32) *const public.Memory {
        _ = self;
        return @ptrCast(zbgfx.bgfx.copy(_data, _size));
    }
    pub fn makeRef(self: *anyopaque, _data: ?*const anyopaque, _size: u32) *const public.Memory {
        _ = self;
        return @ptrCast(zbgfx.bgfx.makeRef(_data, _size));
    }
    pub fn makeRefRelease(self: *anyopaque, _data: ?*const anyopaque, _size: u32, _releaseFn: ?*anyopaque, _userData: ?*anyopaque) *const public.Memory {
        _ = self;
        return @ptrCast(zbgfx.bgfx.makeRefRelease(_data, _size, _releaseFn, _userData));
    }
    pub fn setDebug(self: *anyopaque, _debug: public.DebugFlags) void {
        _ = self;
        bgfx.setDebug(DebugFlags.toState(_debug));
    }
    pub fn dbgTextClear(self: *anyopaque, _attr: u8, _small: bool) void {
        _ = self;
        return zbgfx.bgfx.dbgTextClear(_attr, _small);
    }
    pub fn dbgTextImage(self: *anyopaque, _x: u16, _y: u16, _width: u16, _height: u16, _data: ?*const anyopaque, _pitch: u16) void {
        _ = self;
        return zbgfx.bgfx.dbgTextImage(_x, _y, _width, _height, _data, _pitch);
    }
    pub fn getEncoder(self: *anyopaque) ?public.GpuEncoder {
        const context: *BgfxBackend = @ptrCast(@alignCast(self));

        var zone_ctx = _profiler.ZoneN(@src(), "getEncoder");
        defer zone_ctx.End();

        const wid = _task.getWorkerId();
        if (context.encoders.items[wid]) |encoder| {
            return .{ .ptr = @ptrCast(encoder), .vtable = &encoder_vt };
        } else {
            if (bgfx.encoderBegin(false)) |encoder| {
                context.encoders.items[wid] = encoder;
                return .{ .ptr = @ptrCast(encoder), .vtable = &encoder_vt };
            } else {
                log.warn("Empty encoder", .{});
                return null;
            }
        }
        log.warn("No encoder", .{});
        return null;
    }
    pub fn endEncoder(self: *anyopaque, encoder: public.GpuEncoder) void {
        _ = self;
        var zone_ctx = _profiler.ZoneN(@src(), "endEncoder");
        defer zone_ctx.End();

        encoder.discard(.all);

        // bgfx.encoderEnd(@ptrCast(encoder.ptr));
        // const wid = _task.getWorkerId();

        // _encoders.items[wid] = null;
        // bgfx.encoderEnd(@ptrCast(encoder.ptr));
        // for (_encoders.items) |*value| {
        //     if (value.*) |e| {
        //         bgfx.encoderEnd(@ptrCast(e));
        //     }
        //     value.* = null;
        // }
        //_encoders.clearRetainingCapacity();
    }
    pub fn requestScreenShot(self: *anyopaque, _handle: public.FrameBufferHandle, _filePath: [*c]const u8) void {
        _ = self;
        return zbgfx.bgfx.requestScreenShot(.{ .idx = _handle.idx }, _filePath);
    }
    pub fn renderFrame(self: *anyopaque, _msecs: i32) public.RenderFrame {
        _ = self;
        return @enumFromInt(@intFromEnum(zbgfx.bgfx.renderFrame(_msecs)));
    }
    pub fn createIndexBuffer(self: *anyopaque, _mem: ?*const public.Memory, _flags: public.BufferFlags) public.IndexBufferHandle {
        _ = self;
        return .{ .idx = bgfx.createIndexBuffer(@ptrCast(_mem), BufferFlags.toState(_flags)).idx };
    }
    pub fn setIndexBufferName(self: *anyopaque, _handle: public.IndexBufferHandle, _name: []const u8) void {
        _ = self;
        return zbgfx.bgfx.setIndexBufferName(.{ .idx = _handle.idx }, _name.ptr, @intCast(_name.len));
    }
    pub fn destroyIndexBuffer(self: *anyopaque, _handle: public.IndexBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyIndexBuffer(.{ .idx = _handle.idx });
    }
    pub fn createVertexLayout(self: *anyopaque, _layout: *const public.VertexLayout) public.VertexLayoutHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createVertexLayout(@ptrCast(_layout)).idx };
    }
    pub fn destroyVertexLayout(self: *anyopaque, _layoutHandle: public.VertexLayoutHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyVertexLayout(.{ .idx = _layoutHandle.idx });
    }
    pub fn createVertexBuffer(self: *anyopaque, _mem: ?*const public.Memory, _layout: *const public.VertexLayout, _flags: public.BufferFlags) public.VertexBufferHandle {
        _ = self;
        return .{ .idx = bgfx.createVertexBuffer(@ptrCast(_mem), @ptrCast(_layout), BufferFlags.toState(_flags)).idx };
    }
    pub fn setVertexBufferName(self: *anyopaque, _handle: public.VertexBufferHandle, _name: []const u8) void {
        _ = self;
        return zbgfx.bgfx.setVertexBufferName(.{ .idx = _handle.idx }, _name.ptr, @intCast(_name.len));
    }
    pub fn destroyVertexBuffer(self: *anyopaque, _handle: public.VertexBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyVertexBuffer(.{ .idx = _handle.idx });
    }
    pub fn createDynamicIndexBuffer(self: *anyopaque, _num: u32, _flags: u16) public.DynamicIndexBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createDynamicIndexBuffer(_num, _flags).idx };
    }
    pub fn createDynamicIndexBufferMem(self: *anyopaque, _mem: ?*const public.Memory, _flags: u16) public.DynamicIndexBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createDynamicIndexBufferMem(@ptrCast(_mem), _flags).idx };
    }
    pub fn updateDynamicIndexBuffer(self: *anyopaque, _handle: public.DynamicIndexBufferHandle, _startIndex: u32, _mem: ?*const public.Memory) void {
        _ = self;
        return zbgfx.bgfx.updateDynamicIndexBuffer(.{ .idx = _handle.idx }, _startIndex, @ptrCast(_mem));
    }
    pub fn destroyDynamicIndexBuffer(self: *anyopaque, _handle: public.DynamicIndexBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyDynamicIndexBuffer(.{ .idx = _handle.idx });
    }
    pub fn createDynamicVertexBuffer(self: *anyopaque, _num: u32, _layout: *const public.VertexLayout, _flags: public.BufferFlags) public.DynamicVertexBufferHandle {
        _ = self;
        return .{ .idx = bgfx.createDynamicVertexBuffer(_num, @ptrCast(_layout), BufferFlags.toState(_flags)).idx };
    }
    pub fn createDynamicVertexBufferMem(self: *anyopaque, _mem: ?*const public.Memory, _layout: *const public.VertexLayout, _flags: u16) public.DynamicVertexBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createDynamicVertexBufferMem(@ptrCast(_mem), @ptrCast(_layout), _flags).idx };
    }
    pub fn updateDynamicVertexBuffer(self: *anyopaque, _handle: public.DynamicVertexBufferHandle, _startVertex: u32, _mem: ?*const public.Memory) void {
        _ = self;
        return zbgfx.bgfx.updateDynamicVertexBuffer(.{ .idx = _handle.idx }, _startVertex, @ptrCast(_mem));
    }
    pub fn destroyDynamicVertexBuffer(self: *anyopaque, _handle: public.DynamicVertexBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyDynamicVertexBuffer(.{ .idx = _handle.idx });
    }
    pub fn getAvailTransientIndexBuffer(self: *anyopaque, _num: u32, _index32: bool) u32 {
        _ = self;
        return zbgfx.bgfx.getAvailTransientIndexBuffer(_num, _index32);
    }
    pub fn getAvailTransientVertexBuffer(self: *anyopaque, _num: u32, _layout: *const public.VertexLayout) u32 {
        _ = self;
        return zbgfx.bgfx.getAvailTransientVertexBuffer(_num, @ptrCast(_layout));
    }
    pub fn allocTransientIndexBuffer(self: *anyopaque, _tib: [*c]public.TransientIndexBuffer, _num: u32, _index32: bool) void {
        _ = self;
        return zbgfx.bgfx.allocTransientIndexBuffer(@ptrCast(_tib), _num, _index32);
    }
    pub fn allocTransientVertexBuffer(self: *anyopaque, _tvb: [*c]public.TransientVertexBuffer, _num: u32, _layout: *const public.VertexLayout) void {
        _ = self;
        return zbgfx.bgfx.allocTransientVertexBuffer(@ptrCast(_tvb), _num, @ptrCast(_layout));
    }
    pub fn allocTransientBuffers(self: *anyopaque, _tvb: [*c]public.TransientVertexBuffer, _layout: *const public.VertexLayout, _numVertices: u32, _tib: [*c]public.TransientIndexBuffer, _numIndices: u32, _index32: bool) bool {
        _ = self;
        return zbgfx.bgfx.allocTransientBuffers(@ptrCast(_tvb), @ptrCast(_layout), _numVertices, @ptrCast(_tib), _numIndices, _index32);
    }
    pub fn createIndirectBuffer(self: *anyopaque, _num: u32) public.IndirectBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createIndirectBuffer(_num).idx };
    }
    pub fn destroyIndirectBuffer(self: *anyopaque, _handle: public.IndirectBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyIndirectBuffer(.{ .idx = _handle.idx });
    }
    pub fn createShader(self: *anyopaque, _mem: ?*const public.Memory) public.ShaderHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createShader(@ptrCast(_mem)).idx };
    }
    pub fn getShaderUniforms(self: *anyopaque, _handle: public.ShaderHandle, _uniforms: [*c]public.UniformHandle, _max: u16) u16 {
        _ = self;
        return zbgfx.bgfx.getShaderUniforms(.{ .idx = _handle.idx }, @ptrCast(_uniforms), _max);
    }
    pub fn setShaderName(self: *anyopaque, _handle: public.ShaderHandle, _name: []const u8) void {
        _ = self;
        return zbgfx.bgfx.setShaderName(.{ .idx = _handle.idx }, _name.ptr, @intCast(_name.len));
    }
    pub fn destroyShader(self: *anyopaque, _handle: public.ShaderHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyShader(.{ .idx = _handle.idx });
    }
    pub fn createProgram(self: *anyopaque, _vsh: public.ShaderHandle, _fsh: public.ShaderHandle, _destroyShaders: bool) public.ProgramHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createProgram(.{ .idx = _vsh.idx }, .{ .idx = _fsh.idx }, _destroyShaders).idx };
    }
    pub fn createComputeProgram(self: *anyopaque, _handle: public.ShaderHandle, _destroyShaders: bool) public.ProgramHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createComputeProgram(.{ .idx = _handle.idx }, _destroyShaders).idx };
    }
    pub fn destroyProgram(self: *anyopaque, _handle: public.ProgramHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyProgram(.{ .idx = _handle.idx });
    }
    pub fn isTextureValid(self: *anyopaque, _depth: u16, _cubeMap: bool, _numLayers: u16, _format: public.TextureFormat, _flags: u64) bool {
        _ = self;
        return zbgfx.bgfx.isTextureValid(_depth, _cubeMap, _numLayers, @enumFromInt(@intFromEnum(_format)), _flags);
    }
    pub fn isFrameBufferValid(self: *anyopaque, _num: u8, _attachment: *const public.Attachment) bool {
        _ = self;
        return zbgfx.bgfx.isFrameBufferValid(_num, @ptrCast(_attachment));
    }
    pub fn calcTextureSize(self: *anyopaque, _info: [*c]public.TextureInfo, _width: u16, _height: u16, _depth: u16, _cubeMap: bool, _hasMips: bool, _numLayers: u16, _format: public.TextureFormat) void {
        _ = self;
        return zbgfx.bgfx.calcTextureSize(@ptrCast(_info), _width, _height, _depth, _cubeMap, _hasMips, _numLayers, @enumFromInt(@intFromEnum(_format)));
    }
    pub fn createTexture(self: *anyopaque, _mem: ?*const public.Memory, _flags: public.TextureFlags, _sampler_flags: ?public.SamplerFlags, _skip: u8, _info: ?*public.TextureInfo) public.TextureHandle {
        _ = self;
        return .{
            .idx = bgfx.createTexture(
                @ptrCast(_mem),
                TextureFlags.toState(_flags) | if (_sampler_flags) |f| SamplerFlags.toState(f) else 0,
                _skip,
                @ptrCast(_info),
            ).idx,
        };
    }
    pub fn createTexture2D(self: *anyopaque, _width: u16, _height: u16, _hasMips: bool, _numLayers: u16, _format: public.TextureFormat, _flags: public.TextureFlags, _sampler_flags: ?public.SamplerFlags, _mem: ?*const public.Memory) public.TextureHandle {
        _ = self;
        return .{
            .idx = bgfx.createTexture2D(
                _width,
                _height,
                _hasMips,
                _numLayers,
                @enumFromInt(@intFromEnum(_format)),
                TextureFlags.toState(_flags) | if (_sampler_flags) |f| SamplerFlags.toState(f) else 0,
                @ptrCast(_mem),
            ).idx,
        };
    }
    pub fn createTexture3D(self: *anyopaque, _width: u16, _height: u16, _depth: u16, _hasMips: bool, _format: public.TextureFormat, _flags: public.TextureFlags, _sampler_flags: ?public.SamplerFlags, _mem: ?*const public.Memory) public.TextureHandle {
        _ = self;
        return .{
            .idx = bgfx.createTexture3D(
                _width,
                _height,
                _depth,
                _hasMips,
                @enumFromInt(@intFromEnum(_format)),
                TextureFlags.toState(_flags) | if (_sampler_flags) |f| SamplerFlags.toState(f) else 0,
                @ptrCast(_mem),
            ).idx,
        };
    }
    pub fn createTextureCube(self: *anyopaque, _size: u16, _hasMips: bool, _numLayers: u16, _format: public.TextureFormat, _flags: public.TextureFlags, _sampler_flags: ?public.SamplerFlags, _mem: ?*const public.Memory) public.TextureHandle {
        _ = self;
        return .{
            .idx = bgfx.createTextureCube(
                _size,
                _hasMips,
                _numLayers,
                @enumFromInt(@intFromEnum(_format)),
                TextureFlags.toState(_flags) | if (_sampler_flags) |f| SamplerFlags.toState(f) else 0,
                @ptrCast(_mem),
            ).idx,
        };
    }
    pub fn updateTexture2D(self: *anyopaque, _handle: public.TextureHandle, _layer: u16, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: ?*const public.Memory, _pitch: u16) void {
        _ = self;
        return zbgfx.bgfx.updateTexture2D(.{ .idx = _handle.idx }, _layer, _mip, _x, _y, _width, _height, @ptrCast(_mem), _pitch);
    }
    pub fn updateTexture3D(self: *anyopaque, _handle: public.TextureHandle, _mip: u8, _x: u16, _y: u16, _z: u16, _width: u16, _height: u16, _depth: u16, _mem: ?*const public.Memory) void {
        _ = self;
        return zbgfx.bgfx.updateTexture3D(.{ .idx = _handle.idx }, _mip, _x, _y, _z, _width, _height, _depth, @ptrCast(_mem));
    }
    pub fn updateTextureCube(self: *anyopaque, _handle: public.TextureHandle, _layer: u16, _side: public.CubeMapSide, _mip: u8, _x: u16, _y: u16, _width: u16, _height: u16, _mem: ?*const public.Memory, _pitch: u16) void {
        _ = self;
        bgfx.updateTextureCube(.{ .idx = _handle.idx }, _layer, @intFromEnum(_side), _mip, _x, _y, _width, _height, @ptrCast(_mem), _pitch);
    }
    pub fn readTexture(self: *anyopaque, _handle: public.TextureHandle, _data: ?*anyopaque, _mip: u8) u32 {
        _ = self;
        return zbgfx.bgfx.readTexture(.{ .idx = _handle.idx }, _data, _mip);
    }
    pub fn setTextureName(self: *anyopaque, _handle: public.TextureHandle, _name: []const u8) void {
        _ = self;
        return zbgfx.bgfx.setTextureName(.{ .idx = _handle.idx }, _name.ptr, @intCast(_name.len));
    }
    pub fn getDirectAccessPtr(self: *anyopaque, _handle: public.TextureHandle) ?*anyopaque {
        _ = self;
        return zbgfx.bgfx.getDirectAccessPtr(.{ .idx = _handle.idx });
    }
    pub fn destroyTexture(self: *anyopaque, _handle: public.TextureHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyTexture(.{ .idx = _handle.idx });
    }
    pub fn createFrameBuffer(self: *anyopaque, _width: u16, _height: u16, _format: public.TextureFormat, _textureFlags: u64) public.FrameBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createFrameBuffer(_width, _height, @enumFromInt(@intFromEnum(_format)), _textureFlags).idx };
    }
    pub fn createFrameBufferScaled(self: *anyopaque, _ratio: public.BackbufferRatio, _format: public.TextureFormat, _textureFlags: u64) public.FrameBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createFrameBufferScaled(@enumFromInt(@intFromEnum(_ratio)), @enumFromInt(@intFromEnum(_format)), _textureFlags).idx };
    }
    pub fn createFrameBufferFromHandles(self: *anyopaque, _handles: []const public.TextureHandle, _destroyTexture: bool) public.FrameBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createFrameBufferFromHandles(@truncate(_handles.len), @ptrCast(_handles.ptr), _destroyTexture).idx };
    }
    pub fn createFrameBufferFromAttachment(self: *anyopaque, _attachment: []const public.Attachment, _destroyTexture: bool) public.FrameBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createFrameBufferFromAttachment(@truncate(_attachment.len), @ptrCast(_attachment.ptr), _destroyTexture).idx };
    }
    pub fn createFrameBufferFromNwh(self: *anyopaque, _nwh: ?*anyopaque, _width: u16, _height: u16, _format: public.TextureFormat, _depthFormat: public.TextureFormat) public.FrameBufferHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createFrameBufferFromNwh(_nwh, _width, _height, @enumFromInt(@intFromEnum(_format)), @enumFromInt(@intFromEnum(_depthFormat))).idx };
    }
    pub fn setFrameBufferName(self: *anyopaque, _handle: public.FrameBufferHandle, _name: []const u8) void {
        _ = self;
        return zbgfx.bgfx.setFrameBufferName(.{ .idx = _handle.idx }, _name.ptr, @intCast(_name.len));
    }
    pub fn getTexture(self: *anyopaque, _handle: public.FrameBufferHandle, _attachment: u8) public.TextureHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.getTexture(.{ .idx = _handle.idx }, _attachment).idx };
    }
    pub fn destroyFrameBuffer(self: *anyopaque, _handle: public.FrameBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyFrameBuffer(.{ .idx = _handle.idx });
    }
    pub fn createUniform(self: *anyopaque, _name: [:0]const u8, _type: public.UniformType, _num: u16) public.UniformHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createUniform(_name.ptr, @enumFromInt(@intFromEnum(_type)), _num).idx };
    }
    pub fn getUniformInfo(self: *anyopaque, _handle: public.UniformHandle, _info: [*c]public.UniformInfo) void {
        _ = self;
        return zbgfx.bgfx.getUniformInfo(.{ .idx = _handle.idx }, @ptrCast(_info));
    }
    pub fn destroyUniform(self: *anyopaque, _handle: public.UniformHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyUniform(.{ .idx = _handle.idx });
    }
    pub fn createOcclusionQuery(self: *anyopaque) public.OcclusionQueryHandle {
        _ = self;
        return .{ .idx = zbgfx.bgfx.createOcclusionQuery().idx };
    }
    pub fn getResult(self: *anyopaque, _handle: public.OcclusionQueryHandle, _result: [*c]i32) public.OcclusionQueryResult {
        _ = self;
        return @enumFromInt(@intFromEnum(zbgfx.bgfx.getResult(.{ .idx = _handle.idx }, _result)));
    }
    pub fn destroyOcclusionQuery(self: *anyopaque, _handle: public.OcclusionQueryHandle) void {
        _ = self;
        return zbgfx.bgfx.destroyOcclusionQuery(.{ .idx = _handle.idx });
    }
    pub fn setViewName(self: *anyopaque, _id: public.ViewId, _name: []const u8) void {
        _ = self;
        return zbgfx.bgfx.setViewName(_id, _name.ptr, @intCast(_name.len));
    }
    pub fn setViewRect(self: *anyopaque, _id: public.ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void {
        _ = self;
        return zbgfx.bgfx.setViewRect(_id, _x, _y, _width, _height);
    }
    pub fn setViewRectRatio(self: *anyopaque, _id: public.ViewId, _x: u16, _y: u16, _ratio: public.BackbufferRatio) void {
        _ = self;
        return zbgfx.bgfx.setViewRectRatio(_id, _x, _y, @enumFromInt(@intFromEnum(_ratio)));
    }
    pub fn setViewScissor(self: *anyopaque, _id: public.ViewId, _x: u16, _y: u16, _width: u16, _height: u16) void {
        _ = self;
        return zbgfx.bgfx.setViewScissor(_id, _x, _y, _width, _height);
    }
    pub fn setViewClear(self: *anyopaque, _id: public.ViewId, _flags: public.ClearFlags, _rgba: u32, _depth: f32, _stencil: u8) void {
        _ = self;
        bgfx.setViewClear(
            _id,
            ClearFlags.toState(_flags),
            _rgba,
            _depth,
            _stencil,
        );
    }
    pub fn setViewClearMrt(self: *anyopaque, _id: public.ViewId, _flags: public.ClearFlags, _depth: f32, _stencil: u8, _c0: u8, _c1: u8, _c2: u8, _c3: u8, _c4: u8, _c5: u8, _c6: u8, _c7: u8) void {
        _ = self;
        bgfx.setViewClearMrt(
            _id,
            ClearFlags.toState(_flags),
            _depth,
            _stencil,
            _c0,
            _c1,
            _c2,
            _c3,
            _c4,
            _c5,
            _c6,
            _c7,
        );
    }
    pub fn setViewMode(self: *anyopaque, _id: public.ViewId, _mode: public.ViewMode) void {
        _ = self;
        return zbgfx.bgfx.setViewMode(_id, @enumFromInt(@intFromEnum(_mode)));
    }
    pub fn setViewFrameBuffer(self: *anyopaque, _id: public.ViewId, _handle: public.FrameBufferHandle) void {
        _ = self;
        return zbgfx.bgfx.setViewFrameBuffer(_id, .{ .idx = _handle.idx });
    }
    pub fn setViewTransform(self: *anyopaque, _id: public.ViewId, _view: ?*const anyopaque, _proj: ?*const anyopaque) void {
        _ = self;
        return zbgfx.bgfx.setViewTransform(_id, _view, _proj);
    }
    pub fn setViewOrder(self: *anyopaque, _id: public.ViewId, _num: u16, _order: *const public.ViewId) void {
        _ = self;
        return zbgfx.bgfx.setViewOrder(_id, _num, _order);
    }
    pub fn resetView(self: *anyopaque, _id: public.ViewId) void {
        _ = self;
        return zbgfx.bgfx.resetView(_id);
    }

    pub fn layoutBegin(self: *public.VertexLayout) *public.VertexLayout {
        return @ptrCast(zbgfx.bgfx.VertexLayout.begin(@ptrCast(self), zbgfx.bgfx.getRendererType()));
    }
    pub fn layoutAdd(self: *public.VertexLayout, _attrib: public.Attrib, _num: u8, _type: public.AttribType, _normalized: bool, _asInt: bool) *public.VertexLayout {
        return @ptrCast(zbgfx.bgfx.VertexLayout.add(@ptrCast(self), @enumFromInt(@intFromEnum(_attrib)), _num, @enumFromInt(@intFromEnum(_type)), _normalized, _asInt));
    }
    pub fn layoutDecode(self: *const public.VertexLayout, _attrib: public.Attrib, _num: [*c]u8, _type: [*c]public.AttribType, _normalized: [*c]bool, _asInt: [*c]bool) void {
        return zbgfx.bgfx.VertexLayout.decode(@ptrCast(self), @enumFromInt(@intFromEnum(_attrib)), _num, @ptrCast(_type), _normalized, _asInt);
    }
    pub fn layoutSkip(self: *public.VertexLayout, _num: u8) *public.VertexLayout {
        return @ptrCast(zbgfx.bgfx.VertexLayout.skip(@ptrCast(self), _num));
    }
    pub fn layoutEnd(self: *public.VertexLayout) void {
        return zbgfx.bgfx.VertexLayout.end(@ptrCast(self));
    }

    pub fn getCoreUIImageProgram(self: *anyopaque) public.ProgramHandle {
        const inst: *BgfxBackend = @ptrCast(@alignCast(self));
        return inst.coreui_image_program;
    }

    pub fn getCoreUIProgram(self: *anyopaque) public.ProgramHandle {
        const inst: *BgfxBackend = @ptrCast(@alignCast(self));
        return inst.coreui_program;
    }

    pub fn getCoreShader(self: *anyopaque) []const u8 {
        _ = self;
        return core_shader;
    }

    // pub fn vertexPack(self: *anyopaque, _input: [4]f32, _inputNormalized: bool, _attr: public.Attrib, _layout: *const public.VertexLayout, _data: ?*anyopaque, _index: u32) void {
    //     _ = self;
    //     return bgfx.vertexPack(_input, _inputNormalized, @enumFromInt(@intFromEnum(_attr)), @ptrCast(_layout), _data, _index);
    // }
    // pub fn vertexUnpack(self: *anyopaque, _output: [4]f32, _attr: public.Attrib, _layout: *const public.VertexLayout, _data: ?*const anyopaque, _index: u32) void {
    //     _ = self;
    //     return bgfx.vertexUnpack(_output, @enumFromInt(@intFromEnum(_attr)), @ptrCast(_layout), _data, _index);
    // }
    // pub fn vertexConvert(self: *anyopaque, _dstLayout: *const public.VertexLayout, _dstData: ?*anyopaque, _srcLayout: *const public.VertexLayout, _srcData: ?*const anyopaque, _num: u32) void {
    //     _ = self;
    //     return bgfx.vertexConvert(@ptrCast(_dstLayout), _dstData, @ptrCast(_srcLayout), _srcData, _num);
    // }
    // pub fn weldVertices(self: *anyopaque, _output: ?*anyopaque, _layout: *const public.VertexLayout, _data: ?*const anyopaque, _num: u32, _index32: bool, _epsilon: f32) u32 {
    //     _ = self;
    //     return bgfx.weldVertices(_output, @ptrCast(_layout), _data, _num, _index32, _epsilon);
    // }
    // pub fn topologyConvert(self: *anyopaque, _conversion: public.TopologyConvert, _dst: ?*anyopaque, _dstSize: u32, _indices: ?*const anyopaque, _numIndices: u32, _index32: bool) u32 {
    //     _ = self;
    //     return bgfx.topologyConvert(@enumFromInt(@intFromEnum(_conversion)), _dst, _dstSize, _indices, _numIndices, _index32);
    // }
    // pub fn topologySortTriList(self: *anyopaque, _sort: public.TopologySort, _dst: ?*anyopaque, _dstSize: u32, _dir: [3]f32, _pos: [3]f32, _vertices: ?*const anyopaque, _stride: u32, _indices: ?*const anyopaque, _numIndices: u32, _index32: bool) void {
    //     _ = self;
    //     return bgfx.topologySortTriList(@enumFromInt(@intFromEnum(_sort)), _dst, _dstSize, _dir, _pos, _vertices, _stride, _indices, _numIndices, _index32);
    // }
});

pub const DebugFlags = struct {
    pub fn toState(self: public.DebugFlags) bgfx.DebugFlags {
        var r = bgfx.DebugFlags_None;

        if (self.Wireframe) r |= bgfx.DebugFlags_Wireframe;
        if (self.Ifh) r |= bgfx.DebugFlags_Ifh;
        if (self.Stats) r |= bgfx.DebugFlags_Stats;
        if (self.Text) r |= bgfx.DebugFlags_Text;
        if (self.Profiler) r |= bgfx.DebugFlags_Profiler;

        return r;
    }
};

const AtomicViewId = std.atomic.Value(u16);

var pallet_id_counter: AtomicViewId = AtomicViewId.init(1);

fn initBgfx(context: *BgfxBackend, backend: bgfx.RendererType, vsync: bool, headless: bool, debug: bool, profile: bool) !void {
    bgfx.initCtor(&context.bgfxInit);

    context.bgfxInit.type = @enumFromInt(@intFromEnum(backend));

    const cpu_count: u16 = @intCast(_task.getThreadNum());

    context.bgfxInit.debug = debug;
    context.bgfxInit.profile = profile;
    context.bgfxInit.limits.maxEncoders = cpu_count;

    // TODO: read note in zbgfx.ZigAllocator
    // bgfx_alloc = zbgfx.callbacks.ZigAllocator.init(&_allocator);
    // bgfxInit.allocator = &bgfx_alloc;

    context.bgfxInit.callback = &context.bgfx_clbs;

    if (!headless) {
        const framebufferSize = context.window.?.getFramebufferSize();
        context.bgfxInit.resolution.width = @intCast(framebufferSize[0]);
        context.bgfxInit.resolution.height = @intCast(framebufferSize[1]);

        if (vsync) {
            context.bgfxInit.resolution.reset |= bgfx.ResetFlags_Vsync;
        }

        context.bgfxInit.platformData.nwh = context.window.?.getOsWindowHandler();
        context.bgfxInit.platformData.ndt = context.window.?.getOsDisplayHandler();

        // TODO: wayland
        context.bgfxInit.platformData.type = bgfx.NativeWindowHandleType.Default;
    }

    // // Do not create render thread.
    // _ = bgfx.renderFrame(-1);

    if (!bgfx.init(&context.bgfxInit)) {
        return error.BgfxInitFailed;
    }

    context.bgfx_init = true;
    zbgfx.debugdraw.init();

    context.encoders = try .initCapacity(_allocator, _task.getThreadNum());
    for (0.._task.getThreadNum()) |_| {
        context.encoders.appendAssumeCapacity(null);
    }

    log.info("Backend: {}", .{zbgfx.bgfx.getRendererType()});

    const caps = bgfx.getCaps().*;
    const limits = caps.limits;

    log.debug("Limits:", .{});
    log.debug("\t- maxDrawCalls: {d}", .{limits.maxDrawCalls});
    log.debug("\t- maxBlits: {d}", .{limits.maxBlits});
    log.debug("\t- maxTextureSize: {d}", .{limits.maxTextureSize});
    log.debug("\t- maxTextureLayers: {d}", .{limits.maxTextureLayers});
    log.debug("\t- maxViews: {d}", .{limits.maxViews});
    log.debug("\t- maxFrameBuffers: {d}", .{limits.maxFrameBuffers});
    log.debug("\t- maxFBAttachments: {d}", .{limits.maxFBAttachments});
    log.debug("\t- maxPrograms: {d}", .{limits.maxPrograms});
    log.debug("\t- maxShaders: {d}", .{limits.maxShaders});
    log.debug("\t- maxTextures: {d}", .{limits.maxTextures});
    log.debug("\t- maxTextureSamplers: {d}", .{limits.maxTextureSamplers});
    log.debug("\t- maxComputeBindings: {d}", .{limits.maxComputeBindings});
    log.debug("\t- maxVertexLayouts: {d}", .{limits.maxVertexLayouts});
    log.debug("\t- maxVertexStreams: {d}", .{limits.maxVertexStreams});
    log.debug("\t- maxIndexBuffers: {d}", .{limits.maxIndexBuffers});
    log.debug("\t- maxVertexBuffers: {d}", .{limits.maxVertexBuffers});
    log.debug("\t- maxDynamicIndexBuffers: {d}", .{limits.maxDynamicIndexBuffers});
    log.debug("\t- maxDynamicVertexBuffers: {d}", .{limits.maxDynamicVertexBuffers});
    log.debug("\t- maxUniforms: {d}", .{limits.maxUniforms});
    log.debug("\t- maxOcclusionQueries: {d}", .{limits.maxOcclusionQueries});
    log.debug("\t- maxEncoders: {d}", .{limits.maxEncoders});
    log.debug("\t- minResourceCbSize: {d}", .{limits.minResourceCbSize});
    log.debug("\t- transientVbSize: {d}", .{limits.maxTransientVbSize});
    log.debug("\t- transientIbSize: {d}", .{limits.maxTansientIbSize});

    context.null_layout = NullVertex.layoutInit();
    context.null_vb = backend_api.createVertexBuffer(
        context,
        backend_api.makeRef(context, &context.null_data, @sizeOf(NullVertex)),
        &context.null_layout,
        .{},
    );

    context.float_buffer_layout = FloatBufferVertex.layoutInit();
}
const BgfxBackend = struct {
    window: ?cetech1.platform.Window = null,
    headless: bool = false,
    bgfx_backend: bgfx.RendererType,

    bgfx_init: bool = false,
    bgfxInit: bgfx.Init = undefined,

    bgfx_clbs: zbgfx.callbacks.CCallbackInterfaceT = .{ .vtable = &zbgfx.callbacks.DefaultZigCallbackVTable.toVtbl() },
    bgfx_alloc: zbgfx.callbacks.ZigAllocator = undefined,

    null_layout: public.VertexLayout = undefined,
    null_vb: public.VertexBufferHandle = undefined,
    null_data: [1]NullVertex = .{NullVertex{}},

    float_buffer_layout: public.VertexLayout = undefined,

    encoders: EncoderArray = .{},
    pallet_map: PalletColorMap = .{},

    coreui_image_program: public.ProgramHandle = .{},
    coreui_program: public.ProgramHandle = .{},
};

const bgfx_metal = public.GpuBackendI{
    .name = "bgfx_metal",
    .createBackend = createBgfxBackend,
    .isDefault = isBgfxDefault,
};

const bgfx_vulkan = public.GpuBackendI{
    .name = "bgfx_vulkan",
    .createBackend = createBgfxBackend,
    .isDefault = isBgfxDefault,
};

const bgfx_dx12 = public.GpuBackendI{
    .name = "bgfx_dx12",
    .createBackend = createBgfxBackend,
    .isDefault = isBgfxDefault,
};

const bgfx_noop = public.GpuBackendI{
    .name = "bgfx_noop",
    .createBackend = createBgfxBackend,
    .isDefault = isBgfxDefault,
};

fn isBgfxDefault(backend: []const u8, headles: bool) bool {
    if (headles) return true;

    if (std.ascii.eqlIgnoreCase("bgfx_metal", backend) and builtin.target.os.tag.isDarwin()) return true;
    if (std.ascii.eqlIgnoreCase("bgfx_vulkan", backend) and !builtin.target.os.tag.isDarwin() or builtin.target.os.tag != .windows) return true;
    if (std.ascii.eqlIgnoreCase("bgfx_dx12", backend) and builtin.target.os.tag == .windows) return true;

    return false;
}

fn createBgfxBackend(
    window: ?cetech1.platform.Window,
    backend: []const u8,
    vsync: bool,
    headles: bool,
    debug: bool,
    profile: bool,
) !public.GpuBackend {
    const bgfx_backend: bgfx.RendererType = blk: {
        if (headles) break :blk .Noop;
        var split = std.mem.splitScalar(u8, backend, '_');
        _ = split.next().?;
        const next = split.next().?;
        break :blk @enumFromInt(@intFromEnum(Backend.fromString(next)));
    };

    var context = try _allocator.create(BgfxBackend);
    context.* = .{ .bgfx_backend = bgfx_backend };

    if (window) |w| {
        context.window = w;
    }
    context.headless = headles;

    // claim main thread as render thread.
    _ = bgfx.renderFrame(-1);

    const Task = struct {
        context: *BgfxBackend,
        backend: bgfx.RendererType,
        vsync: bool,
        headles: bool,
        debug: bool,
        profile: bool,

        pub fn exec(s: *@This()) !void {
            try initBgfx(
                s.context,
                s.backend,
                s.vsync,
                s.headles,
                s.debug,
                s.profile,
            );
        }
    };
    const task_id = try _task.schedule(
        cetech1.task.TaskID.none,
        Task{
            .context = context,
            .backend = bgfx_backend,
            .vsync = vsync,
            .headles = headles,
            .debug = debug,
            .profile = profile,
        },
        .{ .affinity = 1 },
    );
    while (!_task.isDone(task_id)) {
        std.Thread.sleep(1 * std.time.ns_per_ms);
        _ = bgfx.renderFrame(0);
    }

    const api = public.GpuBackend{ .inst = @ptrCast(context), .api = &backend_api };

    // Dont compile shader in headless.
    // TODO: need shaderc compiled but now in CI shderc is not compiled
    if (window != null) {
        var fs_options = api.createDefaultShadercOptions();
        fs_options.shaderType = .fragment;

        var vs_options = api.createDefaultShadercOptions();
        vs_options.shaderType = .vertex;

        const alloc = try _tmpalloc.create();
        defer _tmpalloc.destroy(alloc);

        const vs_imgui_image_data = try api.compileShader(alloc, embed_varying_def, vs_imgui_image_code, vs_options);
        const fs_imgui_image_data = try api.compileShader(alloc, embed_varying_def, fs_imgui_image_code, fs_options);

        const vs_ocornut_imgui_data = try api.compileShader(alloc, embed_varying_def, vs_ocornut_imgui_code, vs_options);
        const fs_ocornut_imgui_data = try api.compileShader(alloc, embed_varying_def, fs_ocornut_imgui_code, fs_options);

        const vs_imgui_image = api.createShader(api.copy(vs_imgui_image_data.ptr, @intCast(vs_imgui_image_data.len)));
        const fs_imgui_image = api.createShader(api.copy(fs_imgui_image_data.ptr, @intCast(fs_imgui_image_data.len)));

        const vs_ocornut_imgui = api.createShader(api.copy(vs_ocornut_imgui_data.ptr, @intCast(vs_ocornut_imgui_data.len)));
        const fs_ocornut_imgui = api.createShader(api.copy(fs_ocornut_imgui_data.ptr, @intCast(fs_ocornut_imgui_data.len)));

        context.coreui_image_program = api.createProgram(vs_imgui_image, fs_imgui_image, true);
        context.coreui_program = api.createProgram(vs_ocornut_imgui, fs_ocornut_imgui, true);
    }

    return api;
}

const encoder_vt = public.GpuEncoder.implement(struct {
    pub fn setMarker(self: *anyopaque, _name: []const u8) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setMarker(_name.ptr, @intCast(_name.len));
    }
    pub fn setState(self: *anyopaque, state: public.RenderState, _rgba: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setState(RenderState.toState(state), _rgba);
    }
    pub fn setCondition(self: *anyopaque, _handle: public.OcclusionQueryHandle, _visible: bool) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setCondition(.{ .idx = _handle.idx }, _visible);
    }
    pub fn setStencil(self: *anyopaque, _fstencil: u32, _bstencil: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setStencil(_fstencil, _bstencil);
    }
    pub fn setScissor(self: *anyopaque, _x: u16, _y: u16, _width: u16, _height: u16) u16 {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setScissor(_x, _y, _width, _height);
    }
    pub fn setScissorCached(self: *anyopaque, _cache: u16) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setScissorCached(_cache);
    }
    pub fn setTransform(self: *anyopaque, _mtx: ?*const anyopaque, _num: u16) u32 {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setTransform(_mtx, _num);
    }
    pub fn setTransformCached(self: *anyopaque, _cache: u32, _num: u16) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setTransformCached(_cache, _num);
    }
    pub fn allocTransform(self: *anyopaque, _transform: [*c]public.Transform, _num: u16) u32 {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.allocTransform(@ptrCast(_transform), _num);
    }
    pub fn setUniform(self: *anyopaque, _handle: public.UniformHandle, _value: ?*const anyopaque, _num: u16) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setUniform(.{ .idx = _handle.idx }, _value, _num);
    }
    pub fn setIndexBuffer(self: *anyopaque, _handle: public.IndexBufferHandle, _firstIndex: u32, _numIndices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setIndexBuffer(.{ .idx = _handle.idx }, _firstIndex, _numIndices);
    }
    pub fn setDynamicIndexBuffer(self: *anyopaque, _handle: public.DynamicIndexBufferHandle, _firstIndex: u32, _numIndices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setDynamicIndexBuffer(.{ .idx = _handle.idx }, _firstIndex, _numIndices);
    }
    pub fn setTransientIndexBuffer(self: *anyopaque, _tib: *const public.TransientIndexBuffer, _firstIndex: u32, _numIndices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setTransientIndexBuffer(@ptrCast(_tib), _firstIndex, _numIndices);
    }
    pub fn setVertexBuffer(self: *anyopaque, _stream: u8, _handle: public.VertexBufferHandle, _startVertex: u32, _numVertices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setVertexBuffer(_stream, .{ .idx = _handle.idx }, _startVertex, _numVertices);
    }
    pub fn setVertexBufferWithLayout(self: *anyopaque, _stream: u8, _handle: public.VertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: public.VertexLayoutHandle) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setVertexBufferWithLayout(_stream, .{ .idx = _handle.idx }, _startVertex, _numVertices, .{ .idx = _layoutHandle.idx });
    }
    pub fn setDynamicVertexBuffer(self: *anyopaque, _stream: u8, _handle: public.DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setDynamicVertexBuffer(_stream, .{ .idx = _handle.idx }, _startVertex, _numVertices);
    }
    pub fn setDynamicVertexBufferWithLayout(self: *anyopaque, _stream: u8, _handle: public.DynamicVertexBufferHandle, _startVertex: u32, _numVertices: u32, _layoutHandle: public.VertexLayoutHandle) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setDynamicVertexBufferWithLayout(_stream, .{ .idx = _handle.idx }, _startVertex, _numVertices, .{ .idx = _layoutHandle.idx });
    }
    pub fn setTransientVertexBuffer(self: *anyopaque, _stream: u8, _tvb: *const public.TransientVertexBuffer, _startVertex: u32, _numVertices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setTransientVertexBuffer(_stream, @ptrCast(_tvb), _startVertex, _numVertices);
    }
    pub fn setTransientVertexBufferWithLayout(self: *anyopaque, _stream: u8, _tvb: *const public.TransientVertexBuffer, _startVertex: u32, _numVertices: u32, _layoutHandle: public.VertexLayoutHandle) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setTransientVertexBufferWithLayout(_stream, @ptrCast(_tvb), _startVertex, _numVertices, .{ .idx = _layoutHandle.idx });
    }
    pub fn setVertexCount(self: *anyopaque, _numVertices: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setVertexCount(_numVertices);
    }
    pub fn setInstanceCount(self: *anyopaque, _numInstances: u32) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setInstanceCount(_numInstances);
    }
    pub fn setTexture(self: *anyopaque, _stage: u8, _sampler: public.UniformHandle, _handle: public.TextureHandle, _flags: ?public.SamplerFlags) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        const f = if (_flags) |flags| SamplerFlags.toState(flags) else std.math.maxInt(u32);
        return enc.setTexture(_stage, .{ .idx = _sampler.idx }, .{ .idx = _handle.idx }, @truncate(f));
    }
    pub fn touch(self: *anyopaque, _id: public.ViewId) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.touch(_id);
    }
    pub fn submit(self: *anyopaque, _id: public.ViewId, _program: public.ProgramHandle, _depth: u32, _flags: public.DiscardFlags) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.submit(_id, .{ .idx = _program.idx }, _depth, DiscardFlags.toState(_flags));
    }
    pub fn submitOcclusionQuery(self: *anyopaque, _id: public.ViewId, _program: public.ProgramHandle, _occlusionQuery: public.OcclusionQueryHandle, _depth: u32, _flags: u8) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.submitOcclusionQuery(_id, .{ .idx = _program.idx }, .{ .idx = _occlusionQuery.idx }, _depth, _flags);
    }
    pub fn submitIndirect(self: *anyopaque, _id: public.ViewId, _program: public.ProgramHandle, _indirectHandle: public.IndirectBufferHandle, _start: u32, _num: u32, _depth: u32, _flags: u8) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.submitIndirect(_id, .{ .idx = _program.idx }, .{ .idx = _indirectHandle.idx }, _start, _num, _depth, _flags);
    }
    pub fn submitIndirectCount(self: *anyopaque, _id: public.ViewId, _program: public.ProgramHandle, _indirectHandle: public.IndirectBufferHandle, _start: u32, _numHandle: public.IndexBufferHandle, _numIndex: u32, _numMax: u32, _depth: u32, _flags: u8) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.submitIndirectCount(_id, .{ .idx = _program.idx }, .{ .idx = _indirectHandle.idx }, _start, .{ .idx = _numHandle.idx }, _numIndex, _numMax, _depth, _flags);
    }
    pub fn setComputeIndexBuffer(self: *anyopaque, _stage: u8, _handle: public.IndexBufferHandle, _access: public.Access) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setComputeIndexBuffer(_stage, .{ .idx = _handle.idx }, @enumFromInt(@intFromEnum(_access)));
    }
    pub fn setComputeVertexBuffer(self: *anyopaque, _stage: u8, _handle: public.VertexBufferHandle, _access: public.Access) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setComputeVertexBuffer(_stage, .{ .idx = _handle.idx }, @enumFromInt(@intFromEnum(_access)));
    }
    pub fn setComputeDynamicIndexBuffer(self: *anyopaque, _stage: u8, _handle: public.DynamicIndexBufferHandle, _access: public.Access) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setComputeDynamicIndexBuffer(_stage, .{ .idx = _handle.idx }, @enumFromInt(@intFromEnum(_access)));
    }
    pub fn setComputeDynamicVertexBuffer(self: *anyopaque, _stage: u8, _handle: public.DynamicVertexBufferHandle, _access: public.Access) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setComputeDynamicVertexBuffer(_stage, .{ .idx = _handle.idx }, @enumFromInt(@intFromEnum(_access)));
    }
    pub fn setComputeIndirectBuffer(self: *anyopaque, _stage: u8, _handle: public.IndirectBufferHandle, _access: public.Access) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setComputeIndirectBuffer(_stage, .{ .idx = _handle.idx }, @enumFromInt(@intFromEnum(_access)));
    }
    pub fn setImage(self: *anyopaque, _stage: u8, _handle: public.TextureHandle, _mip: u8, _access: public.Access, _format: public.TextureFormat) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.setImage(_stage, .{ .idx = _handle.idx }, _mip, @enumFromInt(@intFromEnum(_access)), @enumFromInt(@intFromEnum(_format)));
    }
    pub fn dispatch(self: *anyopaque, _id: public.ViewId, _program: public.ProgramHandle, _numX: u32, _numY: u32, _numZ: u32, _flags: u8) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.dispatch(_id, .{ .idx = _program.idx }, _numX, _numY, _numZ, _flags);
    }
    pub fn dispatchIndirect(self: *anyopaque, _id: public.ViewId, _program: public.ProgramHandle, _indirectHandle: public.IndirectBufferHandle, _start: u32, _num: u32, _flags: u8) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.dispatchIndirect(_id, .{ .idx = _program.idx }, .{ .idx = _indirectHandle.idx }, _start, _num, _flags);
    }
    pub fn discard(self: *anyopaque, _flags: public.DiscardFlags) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.discard(DiscardFlags.toState(_flags));
    }
    pub fn blit(self: *anyopaque, _id: public.ViewId, _dst: public.TextureHandle, _dstMip: u8, _dstX: u16, _dstY: u16, _dstZ: u16, _src: public.TextureHandle, _srcMip: u8, _srcX: u16, _srcY: u16, _srcZ: u16, _width: u16, _height: u16, _depth: u16) void {
        const enc: *bgfx.Encoder = @ptrCast(@alignCast(self));
        return enc.blit(_id, .{ .idx = _dst.idx }, _dstMip, _dstX, _dstY, _dstZ, .{ .idx = _src.idx }, _srcMip, _srcX, _srcY, _srcZ, _width, _height, _depth);
    }
});

const dd_encoder_vt = public.DDEncoder.implement(struct {
    pub fn begin(dde: *anyopaque, _viewId: u16, _depthTestLess: bool, _encoder: *anyopaque) void {
        zbgfx.debugdraw.Encoder.begin(@ptrCast(@alignCast(dde)), _viewId, _depthTestLess, @ptrCast(@alignCast(_encoder)));
    }

    pub fn end(dde: *anyopaque) void {
        zbgfx.debugdraw.Encoder.end(@ptrCast(@alignCast(dde)));
    }

    pub fn push(dde: *anyopaque) void {
        zbgfx.debugdraw.Encoder.push(@ptrCast(@alignCast(dde)));
    }

    pub fn pop(dde: *anyopaque) void {
        zbgfx.debugdraw.Encoder.pop(@ptrCast(@alignCast(dde)));
    }

    pub fn setDepthTestLess(dde: *anyopaque, _depthTestLess: bool) void {
        zbgfx.debugdraw.Encoder.setDepthTestLess(@ptrCast(@alignCast(dde)), _depthTestLess);
    }

    pub fn setState(dde: *anyopaque, _depthTest: bool, _depthWrite: bool, _clockwise: bool) void {
        zbgfx.debugdraw.Encoder.setState(@ptrCast(@alignCast(dde)), _depthTest, _depthWrite, _clockwise);
    }

    pub fn setColor(dde: *anyopaque, _abgr: u32) void {
        zbgfx.debugdraw.Encoder.setColor(@ptrCast(@alignCast(dde)), _abgr);
    }

    pub fn setLod(dde: *anyopaque, _lod: u8) void {
        zbgfx.debugdraw.Encoder.setLod(@ptrCast(@alignCast(dde)), _lod);
    }

    pub fn setWireframe(dde: *anyopaque, _wireframe: bool) void {
        zbgfx.debugdraw.Encoder.setWireframe(@ptrCast(@alignCast(dde)), _wireframe);
    }

    pub fn setStipple(dde: *anyopaque, _stipple: bool, _scale: f32, _offset: f32) void {
        zbgfx.debugdraw.Encoder.setStipple(@ptrCast(@alignCast(dde)), _stipple, _scale, _offset);
    }

    pub fn setSpin(dde: *anyopaque, _spin: f32) void {
        zbgfx.debugdraw.Encoder.setSpin(@ptrCast(@alignCast(dde)), _spin);
    }

    pub fn setTransform(dde: *anyopaque, _mtx: ?*const anyopaque) void {
        zbgfx.debugdraw.Encoder.setTransform(@ptrCast(@alignCast(dde)), @constCast(_mtx));
    }

    pub fn setTranslate(dde: *anyopaque, _xyz: [3]f32) void {
        zbgfx.debugdraw.Encoder.setTranslate(@ptrCast(@alignCast(dde)), _xyz);
    }

    pub fn pushTransform(dde: *anyopaque, _mtx: *const anyopaque) void {
        zbgfx.debugdraw.Encoder.pushTransform(@ptrCast(@alignCast(dde)), @constCast(_mtx));
    }

    pub fn popTransform(dde: *anyopaque) void {
        zbgfx.debugdraw.Encoder.popTransform(@ptrCast(@alignCast(dde)));
    }

    pub fn moveTo(dde: *anyopaque, _xyz: [3]f32) void {
        zbgfx.debugdraw.Encoder.moveTo(@ptrCast(@alignCast(dde)), _xyz);
    }

    pub fn lineTo(dde: *anyopaque, _xyz: [3]f32) void {
        zbgfx.debugdraw.Encoder.lineTo(@ptrCast(@alignCast(dde)), _xyz);
    }

    pub fn close(dde: *anyopaque) void {
        zbgfx.debugdraw.Encoder.close(@ptrCast(@alignCast(dde)));
    }

    pub fn drawAABB(dde: *anyopaque, min: [3]f32, max: [3]f32) void {
        zbgfx.debugdraw.Encoder.drawAABB(@ptrCast(@alignCast(dde)), min, max);
    }

    pub fn drawCylinder(dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void {
        zbgfx.debugdraw.Encoder.drawCylinder(@ptrCast(@alignCast(dde)), pos, _end, radius);
    }

    pub fn drawCapsule(dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void {
        zbgfx.debugdraw.Encoder.drawCapsule(@ptrCast(@alignCast(dde)), pos, _end, radius);
    }

    pub fn drawDisk(dde: *anyopaque, center: [3]f32, normal: [3]f32, radius: f32) void {
        zbgfx.debugdraw.Encoder.drawDisk(@ptrCast(@alignCast(dde)), center, normal, radius);
    }

    pub fn drawObb(dde: *anyopaque, _obb: [3]f32) void {
        zbgfx.debugdraw.Encoder.drawObb(@ptrCast(@alignCast(dde)), _obb);
    }

    pub fn drawSphere(dde: *anyopaque, center: [3]f32, radius: f32) void {
        zbgfx.debugdraw.Encoder.drawSphere(@ptrCast(@alignCast(dde)), center, radius);
    }

    pub fn drawTriangle(dde: *anyopaque, v0: [3]f32, v1: [3]f32, v2: [3]f32) void {
        zbgfx.debugdraw.Encoder.drawTriangle(@ptrCast(@alignCast(dde)), v0, v1, v2);
    }

    pub fn drawCone(dde: *anyopaque, pos: [3]f32, _end: [3]f32, radius: f32) void {
        zbgfx.debugdraw.Encoder.drawCone(@ptrCast(@alignCast(dde)), pos, _end, radius);
    }

    pub fn drawGeometry(dde: *anyopaque, _handle: public.DDGeometryHandle) void {
        zbgfx.debugdraw.Encoder.drawGeometry(@ptrCast(@alignCast(dde)), .{ .idx = _handle.idx });
    }

    pub fn drawLineList(dde: *anyopaque, _numVertices: u32, _vertices: []const public.DDVertex, _numIndices: u32, _indices: ?[*]const u16) void {
        zbgfx.debugdraw.Encoder.drawLineList(@ptrCast(@alignCast(dde)), _numVertices, std.mem.bytesAsSlice(zbgfx.debugdraw.Vertex, std.mem.sliceAsBytes(_vertices)), _numIndices, _indices);
    }

    pub fn drawTriList(dde: *anyopaque, _numVertices: u32, _vertices: []const public.DDVertex, _numIndices: u32, _indices: ?[*]const u16) void {
        zbgfx.debugdraw.Encoder.drawTriList(@ptrCast(@alignCast(dde)), _numVertices, std.mem.bytesAsSlice(zbgfx.debugdraw.Vertex, std.mem.sliceAsBytes(_vertices)), _numIndices, _indices.?);
    }

    pub fn drawFrustum(dde: *anyopaque, _viewProj: [16]f32) void {
        zbgfx.debugdraw.Encoder.drawFrustum(@ptrCast(@alignCast(dde)), @constCast(&_viewProj));
    }

    pub fn drawArc(dde: *anyopaque, _axis: public.DDAxis, _xyz: [3]f32, _radius: f32, _degrees: f32) void {
        zbgfx.debugdraw.Encoder.drawArc(@ptrCast(@alignCast(dde)), @enumFromInt(@intFromEnum(_axis)), _xyz, _radius, _degrees);
    }

    pub fn drawCircle(dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _radius: f32, _weight: f32) void {
        zbgfx.debugdraw.Encoder.drawCircle(@ptrCast(@alignCast(dde)), _normal, _center, _radius, _weight);
    }

    pub fn drawCircleAxis(dde: *anyopaque, _axis: public.DDAxis, _xyz: [3]f32, _radius: f32, _weight: f32) void {
        zbgfx.debugdraw.Encoder.drawCircleAxis(@ptrCast(@alignCast(dde)), @enumFromInt(@intFromEnum(_axis)), _xyz, _radius, _weight);
    }

    pub fn drawQuad(dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        zbgfx.debugdraw.Encoder.drawQuad(@ptrCast(@alignCast(dde)), _normal, _center, _size);
    }

    pub fn drawQuadSprite(dde: *anyopaque, _handle: public.DDSpriteHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        zbgfx.debugdraw.Encoder.drawQuadSprite(@ptrCast(@alignCast(dde)), .{ .idx = _handle.idx }, _normal, _center, _size);
    }

    pub fn drawQuadTexture(dde: *anyopaque, _handle: public.TextureHandle, _normal: [3]f32, _center: [3]f32, _size: f32) void {
        zbgfx.debugdraw.Encoder.drawQuadTexture(@ptrCast(@alignCast(dde)), .{ .idx = _handle.idx }, _normal, _center, _size);
    }

    pub fn drawAxis(dde: *anyopaque, _xyz: [3]f32, _len: f32, _highlight: public.DDAxis, _thickness: f32) void {
        zbgfx.debugdraw.Encoder.drawAxis(@ptrCast(@alignCast(dde)), _xyz, _len, @enumFromInt(@intFromEnum(_highlight)), _thickness);
    }

    pub fn drawGrid(dde: *anyopaque, _normal: [3]f32, _center: [3]f32, _size: u32, _step: f32) void {
        zbgfx.debugdraw.Encoder.drawGrid(@ptrCast(@alignCast(dde)), _normal, _center, _size, _step);
    }

    pub fn drawGridAxis(dde: *anyopaque, _axis: public.DDAxis, _center: [3]f32, _size: u32, _step: f32) void {
        zbgfx.debugdraw.Encoder.drawGridAxis(@ptrCast(@alignCast(dde)), @enumFromInt(@intFromEnum(_axis)), _center, _size, _step);
    }

    pub fn drawOrb(dde: *anyopaque, _xyz: [3]f32, _radius: f32, _highlight: public.DDAxis) void {
        zbgfx.debugdraw.Encoder.drawOrb(@ptrCast(@alignCast(dde)), _xyz, _radius, @enumFromInt(@intFromEnum(_highlight)));
    }
});

pub const dd_api = public.GpuDDApi{
    .createSprite = @ptrCast(&zbgfx.debugdraw.createSprite),
    .destroySprite = @ptrCast(&zbgfx.debugdraw.destroySprite),
    .createGeometry = @ptrCast(&zbgfx.debugdraw.createGeometry),
    .destroyGeometry = @ptrCast(&zbgfx.debugdraw.destroyGeometry),

    .encoderCreate = createDDEncoder,
    .encoderDestroy = destroyDDEncoder,
};

pub fn createDDEncoder() public.DDEncoder {
    return public.DDEncoder{
        .ptr = zbgfx.debugdraw.Encoder.create(),
        .vtable = &dd_encoder_vt,
    };
}
pub fn destroyDDEncoder(encoder: public.DDEncoder) void {
    zbgfx.debugdraw.Encoder.destroy(@ptrCast(encoder.ptr));
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix

    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;

    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    _metrics = apidb.getZigApi(module_name, cetech1.metrics.MetricsAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _coreui = apidb.getZigApi(module_name, cetech1.coreui.CoreUIApi).?;

    // create global variable that can survive reload
    _g = try _apidb.setGlobalVar(G, module_name, "_g", .{});

    // impl interface
    try apidb.implOrRemove(module_name, public.GpuBackendI, &bgfx_metal, load);
    try apidb.implOrRemove(module_name, public.GpuBackendI, &bgfx_vulkan, load);
    try apidb.implOrRemove(module_name, public.GpuBackendI, &bgfx_dx12, load);
    try apidb.implOrRemove(module_name, public.GpuBackendI, &bgfx_noop, load);

    try apidb.setOrRemoveZigApi(module_name, public.GpuDDApi, &dd_api, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_gpu_bgfx(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
