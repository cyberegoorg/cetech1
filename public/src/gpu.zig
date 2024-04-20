const std = @import("std");
const system = @import("system.zig");
const strid = @import("strid.zig");
const cdb = @import("cdb.zig");
const gfx = @import("gfx.zig");
const gfxrg = @import("gfxrg.zig");
const gfxdd = @import("gfxdd.zig");

const log = std.log.scoped(.gpu);

pub const GpuContext = opaque {};

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

pub const GpuViewport = struct {
    pub fn setSize(self: GpuViewport, size: [2]f32) void {
        self.vtable.setSize(self.ptr, size);
    }
    pub fn getTexture(self: GpuViewport) ?gfx.TextureHandle {
        return self.vtable.getTexture(self.ptr);
    }
    pub fn getFb(self: GpuViewport) ?gfx.FrameBufferHandle {
        return self.vtable.getFb(self.ptr);
    }
    pub fn getSize(self: GpuViewport) [2]f32 {
        return self.vtable.getSize(self.ptr);
    }
    pub fn getDD(self: GpuViewport) gfxdd.Encoder {
        return self.vtable.getDD(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        setSize: *const fn (viewport: *anyopaque, size: [2]f32) void,
        getTexture: *const fn (viewport: *anyopaque) ?gfx.TextureHandle,
        getFb: *const fn (viewport: *anyopaque) ?gfx.FrameBufferHandle,
        getSize: *const fn (viewport: *anyopaque) [2]f32,
        getDD: *const fn (viewport: *anyopaque) gfxdd.Encoder,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "setSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getTexture")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getFb")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getDD")) @compileError("implement me");

            return VTable{
                .setSize = &T.setSize,
                .getTexture = &T.getTexture,
                .getFb = &T.getFb,
                .getSize = &T.getSize,
                .getDD = &T.getDD,
            };
        }
    };
};

pub const GpuApi = struct {
    createContext: *const fn (window: ?*system.Window, backend: ?Backend, vsync: bool, headles: bool) anyerror!*GpuContext,
    destroyContext: *const fn (ctx: *GpuContext) void,

    // Viewport
    createViewport: *const fn (rg: gfxrg.RenderGraph) anyerror!GpuViewport,
    destroyViewport: *const fn (viewport: GpuViewport) void,

    renderFrame: *const fn (ctx: *GpuContext, kernel_tick: u64, dt: f32, vsync: bool) void,

    // TODO: use system api
    getContentScale: *const fn (ctx: *GpuContext) [2]f32,
    getWindow: *const fn (ctx: *GpuContext) ?*system.Window,
};
