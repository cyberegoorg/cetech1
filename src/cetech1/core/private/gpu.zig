const std = @import("std");

const zgpu = @import("zgpu");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");

const public = @import("../gpu.zig");
const cetech1 = @import("../cetech1.zig");

pub var api = public.GpuApi{
    .createContext = createContext,
    .destroyContext = destroyContext,
    .shitTempRender = shitTempRender,
};

var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
}

pub fn deinit() void {}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.GpuApi, &api);
}

fn createContext(window: *cetech1.system.Window) !*public.GpuContext {
    const gctx = try zgpu.GraphicsContext.create(
        _allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),

            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    return @ptrCast(gctx);
}

fn destroyContext(ctx: *public.GpuContext) void {
    var gctx: *zgpu.GraphicsContext = @alignCast(@ptrCast(ctx));
    gctx.destroy(_allocator);
}

fn shitTempRender(ctx: *public.GpuContext) void {
    var zone_ctx = profiler.ztracy.ZoneN(@src(), "Render");
    defer zone_ctx.End();

    var gctx: *zgpu.GraphicsContext = @alignCast(@ptrCast(ctx));

    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        // GUI pass
        {
            const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
            defer zgpu.endReleasePass(pass);
            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
    _ = gctx.present();
    // profiler.ztracy.FrameImage( , width: u16, height: u16, offset: u8, flip: c_int);
}
