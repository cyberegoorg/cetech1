const std = @import("std");
const zgui = @import("zgui");

const cetech1 = @import("cetech1");
const gpu = cetech1.gpu;
const zm = cetech1.math.zm;

pub var backend_init = false;

var _s_tex: gpu.UniformHandle = .{};
var _u_imageLodEnabled: gpu.UniformHandle = .{};
var _coreui_image_program: gpu.ProgramHandle = .{};
var _coreui_program: gpu.ProgramHandle = .{};

const ImguiVertexLayout = struct {
    fn layoutInit(gpu_backend: gpu.GpuBackend) gpu.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(gpu.VertexLayout);
        };
        _ = gpu_backend.layoutBegin(&L.posColorLayout);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Position, 2, gpu.AttribType.Float, false, false);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.TexCoord0, 2, gpu.AttribType.Float, false, false);
        _ = gpu_backend.layoutAdd(&L.posColorLayout, gpu.Attrib.Color0, 4, gpu.AttribType.Uint8, true, false);
        gpu_backend.layoutEnd(&L.posColorLayout);

        return L.posColorLayout;
    }
};
var _vertex_layout: gpu.VertexLayout = undefined;

pub fn init(window: ?*const anyopaque, gpu_backend: ?gpu.GpuBackend) !void {
    if (gpu_backend) |api| {
        _s_tex = api.createUniform("s_tex", .Sampler, 1);
        _u_imageLodEnabled = api.createUniform("u_imageLodEnabled", .Vec4, 1);

        var flags = zgui.io.getBackendFlags();
        flags.renderer_has_vtx_offset = true;
        flags.renderer_has_textures = true;
        zgui.io.setBackendFlags(flags);
    }

    if (window) |w| {
        zgui.backend.init(w);
        backend_init = true;
        if (gpu_backend) |api| {
            _vertex_layout = ImguiVertexLayout.layoutInit(api);

            _coreui_program = api.getCoreUIProgram();
            _coreui_image_program = api.getCoreUIImageProgram();
        }
    }
}

pub fn deinit(gpu_backend: ?gpu.GpuBackend) void {
    if (backend_init) zgui.backend.deinit();
    if (gpu_backend) |api| {
        if (_s_tex.isValid()) {
            api.destroyUniform(_s_tex);
        }

        if (_u_imageLodEnabled.isValid()) {
            api.destroyUniform(_u_imageLodEnabled);
        }
    }
}

pub fn newFrame() void {
    if (backend_init) zgui.backend.newFrame();
    zgui.newFrame();
    zgui.gizmo.beginFrame();
}

pub fn draw(gpu_backend: gpu.GpuBackend, viewid: gpu.ViewId) void {
    renderDrawData(gpu_backend, viewid) catch undefined;
}

fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32, homogenous_depth: bool) zm.Mat {
    return if (homogenous_depth) zm.orthographicOffCenterLh(
        left,
        right,
        top,
        bottom,
        near,
        far,
    ) else zm.orthographicOffCenterLhGl(
        left,
        right,
        top,
        bottom,
        near,
        far,
    );
}

const BgfxImage = extern struct {
    handle: gpu.TextureHandle,
    a: u8 = 0,
    b: u8 = 0,
    c: u32 = 0,

    pub fn toTextureIdent(self: *const BgfxImage) zgui.TextureIdent {
        return std.mem.bytesToValue(zgui.TextureIdent, std.mem.asBytes(self));
    }
    pub fn fromTextureIdent(self: zgui.TextureIdent) BgfxImage {
        const p: *const BgfxImage = @ptrCast(@alignCast(&self));
        return p.*;
    }
};

fn getTexId(dc: *zgui.DrawCmd) zgui.TextureIdent {
    return if (dc.texture_ref.tex_data) |td| td.tex_id else dc.texture_ref.tex_id;
}

fn renderDrawData(gpu_api: gpu.GpuBackend, view_id: gpu.ViewId) !void {
    zgui.render();

    const draw_data = zgui.getDrawData();

    // Handle textures
    if (draw_data.textures.len != 0) {
        const textures = draw_data.textures.items[0..@intCast(draw_data.textures.len)];

        for (textures) |texture| {
            switch (texture.status) {
                .ok, .destroyed => continue,

                .want_create => {
                    const pixels = texture.pixels;
                    const new_tex = gpu_api.createTexture2D(
                        @intCast(texture.width),
                        @intCast(texture.height),
                        false,
                        1,
                        .BGRA8,
                        .{},
                        .{ .u = .border, .v = .border },
                        null,
                    );

                    gpu_api.updateTexture2D(
                        new_tex,
                        0,
                        0,
                        0,
                        0,
                        @intCast(texture.width),
                        @intCast(texture.height),
                        gpu_api.copy(pixels, @intCast(texture.width * texture.height * texture.bytes_per_pixel)),
                        std.math.maxInt(u16),
                    );

                    texture.tex_id = @enumFromInt(new_tex.idx);
                    texture.status = .ok;
                },

                .want_updates => {
                    const updates = texture.updates.items[0..@intCast(texture.updates.len)];
                    for (updates) |r| {
                        const src_pitch: u32 = @intCast(r.w * texture.bytes_per_pixel);
                        const buffer = gpu_api.alloc(@intCast(r.h * src_pitch));

                        const width: u32 = @intCast(texture.width);
                        const bpp: u32 = @intCast(texture.bytes_per_pixel);

                        var out_p = buffer.data;
                        for (0..r.h) |y| {
                            const pp = (r.x + (r.y + y) * width) * bpp;
                            @memcpy(out_p, texture.pixels[pp .. pp + src_pitch]);
                            out_p = out_p + src_pitch;
                        }

                        const texture_handle = gpu.TextureHandle{ .idx = @intCast(@intFromEnum(texture.tex_id)) };
                        gpu_api.updateTexture2D(
                            texture_handle,
                            0,
                            0,
                            r.x,
                            r.y,
                            r.w,
                            r.h,
                            buffer,
                            std.math.maxInt(u16),
                        );
                    }

                    texture.status = .ok;
                },

                .want_destroy => {
                    if (texture.unused_Frames == 0) continue;

                    const texture_handle = gpu.TextureHandle{ .idx = @intCast(@intFromEnum(texture.tex_id)) };
                    gpu_api.destroyTexture(texture_handle);

                    texture.tex_id = @enumFromInt(0);
                    texture.status = .destroyed;
                },
            }
        }
    }

    if (gpu_api.getWindow() == null) return;

    gpu_api.setViewName(view_id, "ImGui");
    gpu_api.setViewMode(view_id, .Sequential);

    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    const dispWidth = draw_data.display_size[0] * draw_data.framebuffer_scale[0];
    const dispHeight = draw_data.display_size[1] * draw_data.framebuffer_scale[1];
    if (dispWidth <= 0 or dispHeight <= 0) {
        return;
    }

    // Set projection transformation
    {
        const x = draw_data.display_pos[0];
        const y = draw_data.display_pos[1];
        const width = draw_data.display_size[0];
        const heigh = draw_data.display_size[1];

        const ortho = zm.matToArr(orthographic(x, x + width, y + heigh, y, 0.0, 1000.0, gpu_api.isHomogenousDepth()));
        gpu_api.setViewTransform(view_id, null, &ortho);
        gpu_api.setViewRect(view_id, 0, 0, @intFromFloat(dispWidth), @intFromFloat(dispHeight));
    }

    const clipPos = draw_data.display_pos; // (0,0) unless using multi-viewports
    const clipScale = draw_data.framebuffer_scale; // (1,1) unless using retina display which are often (2,2)

    for (0..@intCast(draw_data.cmd_lists_count)) |cmd_idx| {
        const cmd_list = draw_data.cmd_lists.items[cmd_idx];

        const numVertices: u32 = @intCast(cmd_list.getVertexBufferLength());
        const numIndices: u32 = @intCast(cmd_list.getIndexBufferLength());

        var tvb: gpu.TransientVertexBuffer = undefined;
        var tib: gpu.TransientIndexBuffer = undefined;

        gpu_api.allocTransientVertexBuffer(&tvb, numVertices, &_vertex_layout);
        gpu_api.allocTransientIndexBuffer(&tib, numIndices, false);

        @memcpy(tvb.data, std.mem.sliceAsBytes(cmd_list.getVertexBuffer()));
        @memcpy(tib.data, std.mem.sliceAsBytes(cmd_list.getIndexBuffer()));

        if (gpu_api.getEncoder()) |e| {
            defer gpu_api.endEncoder(e);

            for (cmd_list.getCmdBuffer()) |*cmd| {
                if (cmd.user_callback) |clb| {
                    clb(cmd_list, cmd);
                } else if (cmd.elem_count != 0) {
                    var state: gpu.RenderState = .{
                        .color_state = .rgba,
                    };

                    var th: gpu.TextureHandle = .{};
                    const program: gpu.ProgramHandle = _coreui_program;

                    if (getTexId(cmd) != @as(zgui.TextureIdent, @enumFromInt(0))) {
                        state.blend_state = .{
                            .source_color_factor = .Src_alpha,
                            .source_alpha_factor = .Src_alpha,

                            .destination_color_factor = .Inv_src_alpha,
                            .destination_alpha_factor = .Inv_src_alpha,
                        };

                        const image = BgfxImage.fromTextureIdent(getTexId(cmd));
                        th = image.handle;
                    } else {
                        state.blend_state = .{
                            .source_color_factor = .Src_alpha,
                            .source_alpha_factor = .Src_alpha,

                            .destination_color_factor = .Inv_src_alpha,
                            .destination_alpha_factor = .Inv_src_alpha,
                        };
                    }

                    // Project scissor/clipping rectangles into framebuffer space
                    const clipRect: [4]f32 = .{
                        (cmd.clip_rect[0] - clipPos[0]) * clipScale[0],
                        (cmd.clip_rect[1] - clipPos[1]) * clipScale[1],
                        (cmd.clip_rect[2] - clipPos[0]) * clipScale[0],
                        (cmd.clip_rect[3] - clipPos[1]) * clipScale[1],
                    };

                    if (clipRect[0] < dispWidth and clipRect[1] < dispHeight and clipRect[2] >= 0.0 and clipRect[3] >= 0.0) {
                        const xx = @max(clipRect[0], 0);
                        const yy = @max(clipRect[1], 0);

                        _ = e.setScissor(
                            @intFromFloat(xx),
                            @intFromFloat(yy),
                            @intFromFloat(@min(clipRect[2], 65535.0) - xx),
                            @intFromFloat(@min(clipRect[3], 65535.0) - yy),
                        );
                        e.setState(state, 0);
                        e.setTexture(0, _s_tex, th, null);
                        e.setTransientVertexBuffer(0, &tvb, cmd.vtx_offset, numVertices);
                        e.setTransientIndexBuffer(&tib, cmd.idx_offset, cmd.elem_count);
                        e.submit(view_id, program, 0, .all);
                    }
                }
            }
        }
    }
}
