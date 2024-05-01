const std = @import("std");

const builtin = @import("builtin");

const zbgfx = @import("zbgfx");

// TODO: fix some invalid type in original bgfx generator
//const bgfx = zbgfx.bgfx;

const bgfx = @import("bgfx.zig");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");

const gfx_rg_private = @import("gfx_render_graph.zig");
const gfx_rg_api = gfx_rg_private.api;

const cetech1 = @import("cetech1");
const public = cetech1.gpu;
const gfx = cetech1.gfx;
const gfx_dd = cetech1.gfx.dd;
const gfx_rg = cetech1.gfx.rg;
const zm = cetech1.zmath;

const log = std.log.scoped(.gpu);
const bgfx_log = std.log.scoped(.bgfx);
const module_name = .gpu;

const ThreadId = std.Thread.Id;
const EncoderMap = std.AutoArrayHashMap(ThreadId, *bgfx.Encoder);

var _allocator: std.mem.Allocator = undefined;

var _encoder_map: EncoderMap = undefined;
var _encoder_map_lock: std.Thread.Mutex = .{};

const GpuViewport = struct {
    fb: gfx.FrameBufferHandle = .{},
    size: [2]f32 = .{ 0, 0 },
    new_size: [2]f32 = .{ 0, 0 },
    dd: gfx_dd.Encoder,
    rg: gfx_rg.RenderGraph,
    view_mtx: [16]f32,
    world: ?cetech1.ecs.World,
};

const ViewportPool = cetech1.mem.PoolWithLock(GpuViewport);
const ViewportSet = std.AutoArrayHashMap(*GpuViewport, void);
const PalletColorMap = std.AutoArrayHashMap(u32, u8);

var _viewport_set: ViewportSet = undefined;
var _viewport_pool: ViewportPool = undefined;
var _pallet_map: PalletColorMap = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    bgfx_init = false;

    _encoder_map = EncoderMap.init(allocator);
    try _encoder_map.ensureTotalCapacity(std.Thread.getCpuCount() catch 1);

    _viewport_set = ViewportSet.init(allocator);
    _viewport_pool = ViewportPool.init(allocator);
    _encoder_map_lock = .{};

    _pallet_map = PalletColorMap.init(allocator);

    try gfx_rg_private.init(allocator);
}

pub fn deinit() void {
    gfx_rg_private.deinit();

    if (bgfx_init) {
        zbgfx.debugdraw.deinit();
        bgfx.shutdown();
    }
    _encoder_map.deinit();
    _viewport_set.deinit();
    _viewport_pool.deinit();
    _pallet_map.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.GpuApi, &api);
    try apidb.api.setZigApi(module_name, gfx.GfxApi, &gfx_api);
    try apidb.api.setZigApi(module_name, gfx_dd.GfxDDApi, &gfx_dd_api);

    try gfx_rg_private.registerToApi();
}

fn createViewport(render_graph: gfx_rg.RenderGraph, world: ?cetech1.ecs.World) !public.GpuViewport {
    const new_viewport = try _viewport_pool.create();
    new_viewport.* = .{
        .dd = gfx_dd_api.encoderCreate(),
        .rg = render_graph,
        .world = world,
        .view_mtx = zm.matToArr(zm.lookAtRh(
            zm.f32x4(0.0, 0.0, 0.0, 1.0),
            zm.f32x4(0.0, 0.0, 1.0, 1.0),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        )),
    };
    try _viewport_set.put(new_viewport, {});
    return public.GpuViewport{
        .ptr = new_viewport,
        .vtable = &viewport_vt,
    };
}
fn destroyViewport(viewport: public.GpuViewport) void {
    const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport.ptr));
    _ = _viewport_set.swapRemove(true_viewport);

    if (true_viewport.fb.isValid()) {
        gfx_api.destroyFrameBuffer(true_viewport.fb);
    }

    gfx_dd_api.encoderDestroy(true_viewport.dd);
    _viewport_pool.destroy(true_viewport);
}

pub var api = public.GpuApi{
    .createContext = createContext,
    .destroyContext = destroyContext,
    .renderFrame = renderAll,
    .getContentScale = getContentScale,
    .getWindow = getWindow,

    .createViewport = createViewport,
    .destroyViewport = destroyViewport,
};

pub const viewport_vt = public.GpuViewport.VTable.implement(struct {
    pub fn setSize(viewport: *anyopaque, size: [2]f32) void {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        true_viewport.new_size[0] = @max(size[0], 1);
        true_viewport.new_size[1] = @max(size[1], 1);
    }

    pub fn getTexture(viewport: *anyopaque) ?gfx.TextureHandle {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        if (!true_viewport.fb.isValid()) return null;

        const txt = gfx_api.getTexture(true_viewport.fb, 0);
        return if (txt.isValid()) txt else null;
    }

    pub fn getFb(viewport: *anyopaque) ?gfx.FrameBufferHandle {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        if (!true_viewport.fb.isValid()) return null;
        return true_viewport.fb;
    }

    pub fn getSize(viewport: *anyopaque) [2]f32 {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        return true_viewport.size;
    }

    pub fn getDD(viewport: *anyopaque) gfx_dd.Encoder {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        return true_viewport.dd;
    }

    pub fn setViewMtx(viewport: *anyopaque, mtx: [16]f32) void {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        true_viewport.view_mtx = mtx;
    }
    pub fn getViewMtx(viewport: *anyopaque) [16]f32 {
        const true_viewport: *GpuViewport = @alignCast(@ptrCast(viewport));
        return true_viewport.view_mtx;
    }
});

const AtomicViewId = std.atomic.Value(u16);
var view_id: AtomicViewId = AtomicViewId.init(1);
fn newViewId() bgfx.ViewId {
    return view_id.fetchAdd(1, .monotonic);
}

fn resetViewId() void {
    view_id.store(1, .monotonic);
}

var pallet_id_counter: AtomicViewId = AtomicViewId.init(1);
fn addPaletteColor(color: u32) u8 {
    const pallet_id = _pallet_map.get(color);
    if (pallet_id) |id| return id;

    const idx: u8 = @truncate(pallet_id_counter.fetchAdd(1, .monotonic));

    bgfx.setPaletteColorRgba8(idx, color);
    _pallet_map.put(color, idx) catch undefined;

    return idx;
}

const RenderViewportTask = struct {
    viewport: *GpuViewport,
    pub fn exec(s: *@This()) !void {
        var zone = profiler.ztracy.ZoneN(@src(), "RenderViewport");
        defer zone.End();

        const tmp_alloc = try tempalloc.api.create();
        defer tempalloc.api.destroy(tmp_alloc);

        const fb = s.viewport.fb;
        if (!fb.isValid()) return;

        const rg = s.viewport.rg;

        const vp = public.GpuViewport{ .ptr = s.viewport, .vtable = &viewport_vt };
        const builder = try rg.createBuilder(tmp_alloc, vp);
        defer rg.destroyBuilder(builder);

        {
            var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Render graph");
            defer z.End();

            const color_output = gfx_api.getTexture(fb, 0);
            try builder.importTexture(gfx_rg.ViewportColorResource, color_output);

            try rg.setupBuilder(builder);

            try builder.compile();
            try builder.execute(vp);
        }

        const Renderables = struct {
            iface: *const gfx_rg.ComponentRendererI,
            culling: ?gfx_rg.CullingResult = null,
        };

        if (s.viewport.world) |world| {
            var renderables = std.ArrayList(Renderables).init(tmp_alloc);
            defer renderables.deinit();

            const viewers = builder.getViewers();

            // Collect visible renderables
            // TODO: generic culling system
            {
                var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Culling phase");
                defer z.End();

                var it = apidb.api.getFirstImpl(gfx_rg.ComponentRendererI);
                while (it) |node| : (it = node.next) {
                    const iface = cetech1.apidb.ApiDbAPI.toInterface(gfx_rg.ComponentRendererI, node);

                    var renderable = Renderables{ .iface = iface };

                    if (iface.culling) |culling| {
                        renderable.culling = try culling(tmp_alloc, builder, world, viewers);
                    }

                    try renderables.append(renderable);
                }
            }

            // Render
            {
                var z = profiler.ztracy.ZoneN(@src(), "RenderViewport - Render phase");
                defer z.End();
                for (renderables.items) |renderable| {
                    try renderable.iface.render(builder, world, vp, renderable.culling);
                }
            }

            for (renderables.items) |*renderable| {
                if (renderable.culling) |*c| {
                    c.deinit();
                }
            }
        }
    }
};

fn renderAllViewports(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.ztracy.ZoneN(@src(), "renderAllViewports");
    defer zone_ctx.End();

    var tasks = std.ArrayList(cetech1.task.TaskID).init(allocator);
    defer tasks.deinit();

    for (_viewport_set.keys()) |viewport| {
        const recreate = viewport.new_size[0] != viewport.size[0] or viewport.new_size[1] != viewport.size[1];

        if (recreate) {
            if (viewport.fb.isValid()) {
                gfx_api.destroyFrameBuffer(viewport.fb);
            }

            const txFlags: u64 = 0 | gfx.TextureFlags_Rt | gfx.TextureFlags_BlitDst | gfx.SamplerFlags_MinPoint | gfx.SamplerFlags_MagPoint | gfx.SamplerFlags_MipMask | gfx.SamplerFlags_MagPoint | gfx.SamplerFlags_MipPoint | gfx.SamplerFlags_UClamp | gfx.SamplerFlags_VClamp | gfx.SamplerFlags_MipPoint;

            const fb = gfx_api.createFrameBuffer(
                @intFromFloat(viewport.new_size[0]),
                @intFromFloat(viewport.new_size[1]),
                gfx.TextureFormat.BGRA8,
                txFlags,
            );
            viewport.fb = fb;
            viewport.size = viewport.new_size;
        }

        const task_id = try task.api.schedule(
            cetech1.task.TaskID.none,
            RenderViewportTask{
                .viewport = viewport,
            },
        );
        try tasks.append(task_id);
    }

    if (tasks.items.len != 0) {
        task.api.wait(try task.api.combine(tasks.items));
    }
}

fn getContentScale(ctx: *public.GpuContext) [2]f32 {
    const context: *GpuContext = @alignCast(@ptrCast(ctx));

    if (context.window) |w| {
        return w.getContentScale();
    }

    return .{ 1, 1 };
}

fn getWindow(ctx: *public.GpuContext) ?cetech1.platform.Window {
    const context: *GpuContext = @alignCast(@ptrCast(ctx));
    return context.window;
}

var bgfx_init = false;
var bgfxInit: bgfx.Init = undefined;

var bgfx_clbs = zbgfx.callbacks.CCallbackInterfaceT{
    .vtable = &zbgfx.callbacks.DefaultZigCallbackVTable.toVtbl(),
};
var bgfx_alloc: zbgfx.callbacks.ZigAllocator = undefined;

fn initBgfx(context: *GpuContext, backend: public.Backend, vsync: bool, headless: bool) !void {
    bgfx.initCtor(&bgfxInit);

    bgfxInit.type = @enumFromInt(@intFromEnum(backend));

    const cpu_count: u16 = @intCast(std.Thread.getCpuCount() catch 1);

    bgfxInit.debug = true;
    bgfxInit.profile = true;
    bgfxInit.limits.maxEncoders = cpu_count;

    // TODO: read note in zbgfx.ZigAllocator
    //bgfx_alloc = zbgfx.callbacks.ZigAllocator.init(&_allocator);
    //bgfxInit.allocator = &bgfx_alloc;

    bgfxInit.callback = &bgfx_clbs;

    if (!headless) {
        const framebufferSize = context.window.?.getFramebufferSize();
        bgfxInit.resolution.width = @intCast(framebufferSize[0]);
        bgfxInit.resolution.height = @intCast(framebufferSize[1]);

        if (vsync) {
            bgfxInit.resolution.reset |= bgfx.ResetFlags_Vsync;
        }

        bgfxInit.platformData.nwh = context.window.?.getOsWindowHandler();
        bgfxInit.platformData.ndt = context.window.?.getOsDisplayHandler();

        // TODO: wayland
        bgfxInit.platformData.type = bgfx.NativeWindowHandleType.Default;
    }

    // Do not create render thread.
    _ = bgfx.renderFrame(-1);

    if (!bgfx.init(&bgfxInit)) {
        return error.BgfxInitFailed;
    }

    bgfx_init = true;
    zbgfx.debugdraw.init();
}

const GpuContext = struct {
    window: ?cetech1.platform.Window = null,
    headless: bool = false,
};

fn createContext(window: ?cetech1.platform.Window, backend: ?public.Backend, vsync: bool, headles: bool) !*public.GpuContext {
    var context = try _allocator.create(GpuContext);
    context.* = .{};

    if (window) |w| {
        context.window = w;
    }
    context.headless = headles;

    const default_backend = if (headles) public.Backend.noop else public.Backend.auto;
    try initBgfx(context, backend orelse default_backend, vsync, headles);
    return @ptrCast(context);
}

fn destroyContext(ctx: *public.GpuContext) void {
    _allocator.destroy(@as(*GpuContext, @alignCast(@ptrCast(ctx))));
}

fn renderAll(ctx: *public.GpuContext, kernel_tick: u64, dt: f32, vsync: bool) void {
    _renderAll(@alignCast(@ptrCast(ctx)), kernel_tick, dt, vsync) catch undefined;
}

var old_fb_size = [2]i32{ -1, -1 };
var old_flags = bgfx.ResetFlags_None;
fn _renderAll(ctx: *GpuContext, kernel_tick: u64, dt: f32, vsync: bool) !void {
    _ = kernel_tick; // autofix
    _ = dt; // autofix
    var zone_ctx = profiler.ztracy.ZoneN(@src(), "Render");
    defer zone_ctx.End();

    var flags = bgfx.ResetFlags_None;

    var size = [2]i32{ 0, 0 };

    if (ctx.window) |w| {
        size = w.getFramebufferSize();
    }

    if (vsync) {
        flags |= bgfx.ResetFlags_Vsync;
    }

    resetViewId();

    if (old_flags != flags or old_fb_size[0] != size[0] or old_fb_size[1] != size[1]) {
        bgfx.reset(
            @intCast(size[0]),
            @intCast(size[1]),
            flags,
            bgfxInit.resolution.format,
        );
        old_fb_size = size;
        old_flags = flags;
    }

    gfx_api.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x303030ff, 1.0, 0);
    gfx_api.setViewRectRatio(0, 0, 0, .Equal);

    const encoder = gfx_api.getEncoder().?;
    encoder.touch(0);

    bgfx.dbgTextClear(0, false);

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);
    try renderAllViewports(allocator);

    endAllUsedEncoders();

    // TODO: save frameid for sync (sync across frames like read back frame + 2)
    {
        var frame_zone_ctx = profiler.ztracy.ZoneN(@src(), "frame");
        defer frame_zone_ctx.End();
        _ = bgfx.frame(false);
    }
    // TODO
    // profiler.ztracy.FrameImage( , width: u16, height: u16, offset: u8, flip: c_int);
}

pub const gfx_api = gfx.GfxApi{
    .newViewId = newViewId,
    .addPaletteColor = addPaletteColor,
    .vertexPack = @ptrCast(&bgfx.vertexPack),
    .vertexUnpack = @ptrCast(&bgfx.vertexUnpack),
    .vertexConvert = @ptrCast(&bgfx.vertexConvert),
    .weldVertices = @ptrCast(&bgfx.weldVertices),
    .topologyConvert = @ptrCast(&bgfx.topologyConvert),
    .topologySortTriList = @ptrCast(&bgfx.topologySortTriList),
    .reset = @ptrCast(&bgfx.reset),
    .frame = @ptrCast(&bgfx.frame),
    .alloc = @ptrCast(&bgfx.alloc),
    .copy = @ptrCast(&bgfx.copy),
    .makeRef = @ptrCast(&bgfx.makeRef),
    .makeRefRelease = @ptrCast(&bgfx.makeRefRelease),
    .setDebug = @ptrCast(&bgfx.setDebug),
    .dbgTextClear = @ptrCast(&bgfx.dbgTextClear),
    .dbgTextImage = @ptrCast(&bgfx.dbgTextImage),
    .createIndexBuffer = @ptrCast(&bgfx.createIndexBuffer),
    .setIndexBufferName = @ptrCast(&bgfx.setIndexBufferName),
    .destroyIndexBuffer = @ptrCast(&bgfx.destroyIndexBuffer),
    .createVertexLayout = @ptrCast(&bgfx.createVertexLayout),
    .destroyVertexLayout = @ptrCast(&bgfx.destroyVertexLayout),
    .createVertexBuffer = @ptrCast(&bgfx.createVertexBuffer),
    .setVertexBufferName = @ptrCast(&bgfx.setVertexBufferName),
    .destroyVertexBuffer = @ptrCast(&bgfx.destroyVertexBuffer),
    .createDynamicIndexBuffer = @ptrCast(&bgfx.createDynamicIndexBuffer),
    .createDynamicIndexBufferMem = @ptrCast(&bgfx.createDynamicIndexBufferMem),
    .updateDynamicIndexBuffer = @ptrCast(&bgfx.updateDynamicIndexBuffer),
    .destroyDynamicIndexBuffer = @ptrCast(&bgfx.destroyDynamicIndexBuffer),
    .createDynamicVertexBuffer = @ptrCast(&bgfx.createDynamicVertexBuffer),
    .createDynamicVertexBufferMem = @ptrCast(&bgfx.createDynamicVertexBufferMem),
    .updateDynamicVertexBuffer = @ptrCast(&bgfx.updateDynamicVertexBuffer),
    .destroyDynamicVertexBuffer = @ptrCast(&bgfx.destroyDynamicVertexBuffer),
    .getAvailTransientIndexBuffer = @ptrCast(&bgfx.getAvailTransientIndexBuffer),
    .getAvailTransientVertexBuffer = @ptrCast(&bgfx.getAvailTransientVertexBuffer),
    .getAvailInstanceDataBuffer = @ptrCast(&bgfx.getAvailInstanceDataBuffer),
    .allocTransientIndexBuffer = @ptrCast(&bgfx.allocTransientIndexBuffer),
    .allocTransientVertexBuffer = @ptrCast(&bgfx.allocTransientVertexBuffer),
    .allocTransientBuffers = @ptrCast(&bgfx.allocTransientBuffers),
    .allocInstanceDataBuffer = @ptrCast(&bgfx.allocInstanceDataBuffer),
    .createIndirectBuffer = @ptrCast(&bgfx.createIndirectBuffer),
    .destroyIndirectBuffer = @ptrCast(&bgfx.destroyIndirectBuffer),
    .createShader = @ptrCast(&bgfx.createShader),
    .getShaderUniforms = @ptrCast(&bgfx.getShaderUniforms),
    .setShaderName = @ptrCast(&bgfx.setShaderName),
    .destroyShader = @ptrCast(&bgfx.destroyShader),
    .createProgram = @ptrCast(&bgfx.createProgram),
    .createComputeProgram = @ptrCast(&bgfx.createComputeProgram),
    .destroyProgram = @ptrCast(&bgfx.destroyProgram),
    .isTextureValid = @ptrCast(&bgfx.isTextureValid),
    .isFrameBufferValid = @ptrCast(&bgfx.isFrameBufferValid),
    .calcTextureSize = @ptrCast(&bgfx.calcTextureSize),
    .createTexture = @ptrCast(&bgfx.createTexture),
    .createTexture2D = @ptrCast(&bgfx.createTexture2D),
    .createTexture2DScaled = @ptrCast(&bgfx.createTexture2DScaled),
    .createTexture3D = @ptrCast(&bgfx.createTexture3D),
    .createTextureCube = @ptrCast(&bgfx.createTextureCube),
    .updateTexture2D = @ptrCast(&bgfx.updateTexture2D),
    .updateTexture3D = @ptrCast(&bgfx.updateTexture3D),
    .updateTextureCube = @ptrCast(&bgfx.updateTextureCube),
    .readTexture = @ptrCast(&bgfx.readTexture),
    .setTextureName = @ptrCast(&bgfx.setTextureName),
    .getDirectAccessPtr = @ptrCast(&bgfx.getDirectAccessPtr),
    .destroyTexture = @ptrCast(&bgfx.destroyTexture),
    .createFrameBuffer = @ptrCast(&bgfx.createFrameBuffer),
    .createFrameBufferScaled = @ptrCast(&bgfx.createFrameBufferScaled),
    .createFrameBufferFromHandles = @ptrCast(&bgfx.createFrameBufferFromHandles),
    .createFrameBufferFromAttachment = @ptrCast(&bgfx.createFrameBufferFromAttachment),
    .createFrameBufferFromNwh = @ptrCast(&bgfx.createFrameBufferFromNwh),
    .setFrameBufferName = @ptrCast(&bgfx.setFrameBufferName),
    .getTexture = @ptrCast(&bgfx.getTexture),
    .destroyFrameBuffer = @ptrCast(&bgfx.destroyFrameBuffer),
    .createUniform = @ptrCast(&bgfx.createUniform),
    .getUniformInfo = @ptrCast(&bgfx.getUniformInfo),
    .destroyUniform = @ptrCast(&bgfx.destroyUniform),
    .createOcclusionQuery = @ptrCast(&bgfx.createOcclusionQuery),
    .getResult = @ptrCast(&bgfx.getResult),
    .destroyOcclusionQuery = @ptrCast(&bgfx.destroyOcclusionQuery),
    .setPaletteColor = @ptrCast(&bgfx.setPaletteColor),
    .setPaletteColorRgba8 = @ptrCast(&bgfx.setPaletteColorRgba8),
    .setViewName = @ptrCast(&bgfx.setViewName),
    .setViewRect = @ptrCast(&bgfx.setViewRect),
    .setViewRectRatio = @ptrCast(&bgfx.setViewRectRatio),
    .setViewScissor = @ptrCast(&bgfx.setViewScissor),
    .setViewClear = @ptrCast(&bgfx.setViewClear),
    .setViewClearMrt = @ptrCast(&bgfx.setViewClearMrt),
    .setViewMode = @ptrCast(&bgfx.setViewMode),
    .setViewFrameBuffer = @ptrCast(&bgfx.setViewFrameBuffer),
    .setViewTransform = @ptrCast(&bgfx.setViewTransform),
    .setViewOrder = @ptrCast(&bgfx.setViewOrder),
    .resetView = @ptrCast(&bgfx.resetView),
    .getEncoder = getEncoder,
    //.encoderEnd = @ptrCast(&bgfx.encoderEnd),
    .requestScreenShot = @ptrCast(&bgfx.requestScreenShot),
    .renderFrame = @ptrCast(&bgfx.renderFrame),
    .overrideInternalTexturePtr = @ptrCast(&bgfx.overrideInternalTexturePtr),
    .overrideInternalTexture = @ptrCast(&bgfx.overrideInternalTexture),
    .setMarker = @ptrCast(&bgfx.setMarker),
    .setState = @ptrCast(&bgfx.setState),
    .setCondition = @ptrCast(&bgfx.setCondition),
    .setStencil = @ptrCast(&bgfx.setStencil),
    .setScissor = @ptrCast(&bgfx.setScissor),
    .setScissorCached = @ptrCast(&bgfx.setScissorCached),
    .setTransform = @ptrCast(&bgfx.setTransform),
    .setTransformCached = @ptrCast(&bgfx.setTransformCached),
    .allocTransform = @ptrCast(&bgfx.allocTransform),
    .setUniform = @ptrCast(&bgfx.setUniform),
    .setIndexBuffer = @ptrCast(&bgfx.setIndexBuffer),
    .setDynamicIndexBuffer = @ptrCast(&bgfx.setDynamicIndexBuffer),
    .setTransientIndexBuffer = @ptrCast(&bgfx.setTransientIndexBuffer),
    .setVertexBuffer = @ptrCast(&bgfx.setVertexBuffer),
    .setVertexBufferWithLayout = @ptrCast(&bgfx.setVertexBufferWithLayout),
    .setDynamicVertexBuffer = @ptrCast(&bgfx.setDynamicVertexBuffer),
    .setDynamicVertexBufferWithLayout = @ptrCast(&bgfx.setDynamicVertexBufferWithLayout),
    .setTransientVertexBuffer = @ptrCast(&bgfx.setTransientVertexBuffer),
    .setTransientVertexBufferWithLayout = @ptrCast(&bgfx.setTransientVertexBufferWithLayout),
    .setVertexCount = @ptrCast(&bgfx.setVertexCount),
    .setInstanceDataBuffer = @ptrCast(&bgfx.setInstanceDataBuffer),
    .setInstanceDataFromVertexBuffer = @ptrCast(&bgfx.setInstanceDataFromVertexBuffer),
    .setInstanceDataFromDynamicVertexBuffer = @ptrCast(&bgfx.setInstanceDataFromDynamicVertexBuffer),
    .setInstanceCount = @ptrCast(&bgfx.setInstanceCount),
    .setTexture = @ptrCast(&bgfx.setTexture),
    .touch = @ptrCast(&bgfx.touch),
    .submit = @ptrCast(&bgfx.submit),
    .submitOcclusionQuery = @ptrCast(&bgfx.submitOcclusionQuery),
    .submitIndirect = @ptrCast(&bgfx.submitIndirect),
    .submitIndirectCount = @ptrCast(&bgfx.submitIndirectCount),
    .setComputeIndexBuffer = @ptrCast(&bgfx.setComputeIndexBuffer),
    .setComputeVertexBuffer = @ptrCast(&bgfx.setComputeVertexBuffer),
    .setComputeDynamicIndexBuffer = @ptrCast(&bgfx.setComputeDynamicIndexBuffer),
    .setComputeDynamicVertexBuffer = @ptrCast(&bgfx.setComputeDynamicVertexBuffer),
    .setComputeIndirectBuffer = @ptrCast(&bgfx.setComputeIndirectBuffer),
    .setImage = @ptrCast(&bgfx.setImage),
    .dispatch = @ptrCast(&bgfx.dispatch),
    .dispatchIndirect = @ptrCast(&bgfx.dispatchIndirect),
    .discard = @ptrCast(&bgfx.discard),
    .blit = @ptrCast(&bgfx.blit),

    // layout
    .layoutBegin = @ptrCast(&bgfx.VertexLayout.begin),
    .layoutAdd = @ptrCast(&bgfx.VertexLayout.add),
    .layoutDecode = @ptrCast(&bgfx.VertexLayout.decode),
    .layoutHas = @ptrCast(&bgfx.VertexLayout.has),
    .layoutSkip = @ptrCast(&bgfx.VertexLayout.skip),
    .layoutEnd = @ptrCast(&bgfx.VertexLayout.end),
};

const encoder_vt = gfx.Encoder.VTable{
    .encoderSetMarker = @ptrCast(&bgfx.Encoder.setMarker),
    .encoderSetState = @ptrCast(&bgfx.Encoder.setState),
    .encoderSetCondition = @ptrCast(&bgfx.Encoder.setCondition),
    .encoderSetStencil = @ptrCast(&bgfx.Encoder.setStencil),
    .encoderSetScissor = @ptrCast(&bgfx.Encoder.setScissor),
    .encoderSetScissorCached = @ptrCast(&bgfx.Encoder.setScissorCached),
    .encoderSetTransform = @ptrCast(&bgfx.Encoder.setTransform),
    .encoderSetTransformCached = @ptrCast(&bgfx.Encoder.setTransformCached),
    .encoderAllocTransform = @ptrCast(&bgfx.Encoder.allocTransform),
    .encoderSetUniform = @ptrCast(&bgfx.Encoder.setUniform),
    .encoderSetIndexBuffer = @ptrCast(&bgfx.Encoder.setIndexBuffer),
    .encoderSetDynamicIndexBuffer = @ptrCast(&bgfx.Encoder.setDynamicIndexBuffer),
    .encoderSetTransientIndexBuffer = @ptrCast(&bgfx.Encoder.setTransientIndexBuffer),
    .encoderSetVertexBuffer = @ptrCast(&bgfx.Encoder.setVertexBuffer),
    .encoderSetVertexBufferWithLayout = @ptrCast(&bgfx.Encoder.setVertexBufferWithLayout),
    .encoderSetDynamicVertexBuffer = @ptrCast(&bgfx.Encoder.setDynamicVertexBuffer),
    .encoderSetDynamicVertexBufferWithLayout = @ptrCast(&bgfx.Encoder.setDynamicVertexBufferWithLayout),
    .encoderSetTransientVertexBuffer = @ptrCast(&bgfx.Encoder.setTransientVertexBuffer),
    .encoderSetTransientVertexBufferWithLayout = @ptrCast(&bgfx.Encoder.setTransientVertexBufferWithLayout),
    .encoderSetVertexCount = @ptrCast(&bgfx.Encoder.setVertexCount),
    .encoderSetInstanceDataBuffer = @ptrCast(&bgfx.Encoder.setInstanceDataBuffer),
    .encoderSetInstanceDataFromVertexBuffer = @ptrCast(&bgfx.Encoder.setInstanceDataFromVertexBuffer),
    .encoderSetInstanceDataFromDynamicVertexBuffer = @ptrCast(&bgfx.Encoder.setInstanceDataFromDynamicVertexBuffer),
    .encoderSetInstanceCount = @ptrCast(&bgfx.Encoder.setInstanceCount),
    .encoderSetTexture = @ptrCast(&bgfx.Encoder.setTexture),
    .encoderTouch = @ptrCast(&bgfx.Encoder.touch),
    .encoderSubmit = @ptrCast(&bgfx.Encoder.submit),
    .encoderSubmitOcclusionQuery = @ptrCast(&bgfx.Encoder.submitOcclusionQuery),
    .encoderSubmitIndirect = @ptrCast(&bgfx.Encoder.submitIndirect),
    .encoderSubmitIndirectCount = @ptrCast(&bgfx.Encoder.submitIndirectCount),
    .encoderSetComputeIndexBuffer = @ptrCast(&bgfx.Encoder.setComputeIndexBuffer),
    .encoderSetComputeVertexBuffer = @ptrCast(&bgfx.Encoder.setComputeVertexBuffer),
    .encoderSetComputeDynamicIndexBuffer = @ptrCast(&bgfx.Encoder.setComputeDynamicIndexBuffer),
    .encoderSetComputeDynamicVertexBuffer = @ptrCast(&bgfx.Encoder.setComputeDynamicVertexBuffer),
    .encoderSetComputeIndirectBuffer = @ptrCast(&bgfx.Encoder.setComputeIndirectBuffer),
    .encoderSetImage = @ptrCast(&bgfx.Encoder.setImage),
    .encoderDispatch = @ptrCast(&bgfx.Encoder.dispatch),
    .encoderDispatchIndirect = @ptrCast(&bgfx.Encoder.dispatchIndirect),
    .encoderDiscard = @ptrCast(&bgfx.Encoder.discard),
    .encoderBlit = @ptrCast(&bgfx.Encoder.blit),
};

const dd_encoder_vt = gfx_dd.Encoder.VTable{
    .encoderBegin = @ptrCast(&zbgfx.debugdraw.Encoder.begin),
    .encoderEnd = @ptrCast(&zbgfx.debugdraw.Encoder.end),
    .encoderPush = @ptrCast(&zbgfx.debugdraw.Encoder.push),
    .encoderPop = @ptrCast(&zbgfx.debugdraw.Encoder.pop),
    .encoderSetDepthTestLess = @ptrCast(&zbgfx.debugdraw.Encoder.setDepthTestLess),
    .encoderSetState = @ptrCast(&zbgfx.debugdraw.Encoder.setState),
    .encoderSetColor = @ptrCast(&zbgfx.debugdraw.Encoder.setColor),
    .encoderSetLod = @ptrCast(&zbgfx.debugdraw.Encoder.setLod),
    .encoderSetWireframe = @ptrCast(&zbgfx.debugdraw.Encoder.setWireframe),
    .encoderSetStipple = @ptrCast(&zbgfx.debugdraw.Encoder.setStipple),
    .encoderSetSpin = @ptrCast(&zbgfx.debugdraw.Encoder.setSpin),
    .encoderSetTransform = @ptrCast(&zbgfx.debugdraw.Encoder.setTransform),
    .encoderSetTranslate = @ptrCast(&zbgfx.debugdraw.Encoder.setTranslate),
    .encoderPushTransform = @ptrCast(&zbgfx.debugdraw.Encoder.pushTransform),
    .encoderPopTransform = @ptrCast(&zbgfx.debugdraw.Encoder.popTransform),
    .encoderMoveTo = @ptrCast(&zbgfx.debugdraw.Encoder.moveTo),
    .encoderLineTo = @ptrCast(&zbgfx.debugdraw.Encoder.lineTo),
    .encoderClose = @ptrCast(&zbgfx.debugdraw.Encoder.close),
    .encoderDrawAABB = @ptrCast(&zbgfx.debugdraw.Encoder.drawAABB),
    .encoderDrawCylinder = @ptrCast(&zbgfx.debugdraw.Encoder.drawCylinder),
    .encoderDrawCapsule = @ptrCast(&zbgfx.debugdraw.Encoder.drawCapsule),
    .encoderDrawDisk = @ptrCast(&zbgfx.debugdraw.Encoder.drawDisk),
    .encoderDrawObb = @ptrCast(&zbgfx.debugdraw.Encoder.drawObb),
    .encoderDrawSphere = @ptrCast(&zbgfx.debugdraw.Encoder.drawSphere),
    .encoderDrawTriangle = @ptrCast(&zbgfx.debugdraw.Encoder.drawTriangle),
    .encoderDrawCone = @ptrCast(&zbgfx.debugdraw.Encoder.drawCone),
    .encoderDrawGeometry = @ptrCast(&zbgfx.debugdraw.Encoder.drawGeometry),
    .encoderDrawLineList = @ptrCast(&zbgfx.debugdraw.Encoder.drawLineList),
    .encoderDrawTriList = @ptrCast(&zbgfx.debugdraw.Encoder.drawTriList),
    .encoderDrawFrustum = @ptrCast(&zbgfx.debugdraw.Encoder.drawFrustum),
    .encoderDrawArc = @ptrCast(&zbgfx.debugdraw.Encoder.drawArc),
    .encoderDrawCircle = @ptrCast(&zbgfx.debugdraw.Encoder.drawCircle),
    .encoderDrawCircleAxis = @ptrCast(&zbgfx.debugdraw.Encoder.drawCircleAxis),
    .encoderDrawQuad = @ptrCast(&zbgfx.debugdraw.Encoder.drawQuad),
    .encoderDrawQuadSprite = @ptrCast(&zbgfx.debugdraw.Encoder.drawQuadSprite),
    .encoderDrawQuadTexture = @ptrCast(&zbgfx.debugdraw.Encoder.drawQuadTexture),
    .encoderDrawAxis = @ptrCast(&zbgfx.debugdraw.Encoder.drawAxis),
    .encoderDrawGrid = @ptrCast(&zbgfx.debugdraw.Encoder.drawGrid),
    .encoderDrawGridAxis = @ptrCast(&zbgfx.debugdraw.Encoder.drawGridAxis),
    .encoderDrawOrb = @ptrCast(&zbgfx.debugdraw.Encoder.drawOrb),
};

pub const gfx_dd_api = gfx_dd.GfxDDApi{
    .createSprite = @ptrCast(&zbgfx.debugdraw.createSprite),
    .destroySprite = @ptrCast(&zbgfx.debugdraw.destroySprite),
    .createGeometry = @ptrCast(&zbgfx.debugdraw.createGeometry),
    .destroyGeometry = @ptrCast(&zbgfx.debugdraw.destroyGeometry),

    .encoderCreate = createDDEncoder,
    .encoderDestroy = destroyDDEncoder,
};

pub fn createDDEncoder() gfx_dd.Encoder {
    return gfx_dd.Encoder{
        .ptr = zbgfx.debugdraw.Encoder.create(),
        .vtable = &dd_encoder_vt,
    };
}
pub fn destroyDDEncoder(encoder: gfx_dd.Encoder) void {
    zbgfx.debugdraw.Encoder.destroy(@ptrCast(encoder.ptr));
}

fn getEncoder() ?gfx.Encoder {
    const thread_id = std.Thread.getCurrentId();

    {
        _encoder_map_lock.lock();
        defer _encoder_map_lock.unlock();
        if (_encoder_map.get(thread_id)) |encoder| {
            return .{ .ptr = @ptrCast(encoder), .vtable = &encoder_vt };
        }
    }

    if (bgfx.encoderBegin(false)) |encoder| {
        {
            _encoder_map_lock.lock();
            defer _encoder_map_lock.unlock();
            _encoder_map.put(thread_id, @ptrCast(encoder)) catch undefined;
            return .{ .ptr = @ptrCast(encoder), .vtable = &encoder_vt };
        }
    }

    return null;
}

fn endAllUsedEncoders() void {
    var zone_ctx = profiler.ztracy.ZoneN(@src(), "endAllUsedEncoders");
    defer zone_ctx.End();
    for (_encoder_map.values()) |encoder| {
        bgfx.encoderEnd(@ptrCast(encoder));
    }
    _encoder_map.clearRetainingCapacity();
}
