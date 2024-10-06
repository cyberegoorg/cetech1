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

const cetech1 = @import("cetech1");
const public = cetech1.gpu;

const render_graph = cetech1.render_graph;
const zm = cetech1.math;

const log = std.log.scoped(.gpu);
const bgfx_log = std.log.scoped(.bgfx);
const module_name = .gpu;

const ThreadId = std.Thread.Id;
const EncoderMap = std.AutoArrayHashMap(ThreadId, *bgfx.Encoder);

var _allocator: std.mem.Allocator = undefined;

var _encoder_map: EncoderMap = undefined;
var _encoder_map_lock: std.Thread.Mutex = .{};

const PalletColorMap = std.AutoArrayHashMap(u32, u8);

var _pallet_map: PalletColorMap = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    bgfx_init = false;

    _encoder_map = EncoderMap.init(allocator);
    try _encoder_map.ensureTotalCapacity(std.Thread.getCpuCount() catch 1);

    _encoder_map_lock = .{};

    _pallet_map = PalletColorMap.init(allocator);
}

pub fn deinit() void {
    if (bgfx_init) {
        zbgfx.debugdraw.deinit();
        bgfx.shutdown();
    }
    _encoder_map.deinit();
    _pallet_map.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.GpuApi, &api);
    try apidb.api.setZigApi(module_name, public.GpuDDApi, &dd_api);
}

pub const api = public.GpuApi{
    .createContext = createContext,
    .destroyContext = destroyContext,
    .getWindow = getWindow,

    .getResolution = getResolution,
    .addPaletteColor = addPaletteColor,
    .endAllUsedEncoders = endAllUsedEncoders,

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

const AtomicViewId = std.atomic.Value(u16);

var pallet_id_counter: AtomicViewId = AtomicViewId.init(1);
fn addPaletteColor(color: u32) u8 {
    const pallet_id = _pallet_map.get(color);
    if (pallet_id) |id| return id;

    const idx: u8 = @truncate(pallet_id_counter.fetchAdd(1, .monotonic));

    bgfx.setPaletteColorRgba8(idx, color);
    _pallet_map.put(color, idx) catch undefined;

    return idx;
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
    // bgfx_alloc = zbgfx.callbacks.ZigAllocator.init(&_allocator);
    // bgfxInit.allocator = &bgfx_alloc;

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

const encoder_vt = public.Encoder.VTable{
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

const dd_encoder_vt = public.DDEncoder.VTable{
    .encoderBegin = @ptrCast(&ddBegin),
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

pub const dd_api = public.GpuDDApi{
    .createSprite = @ptrCast(&zbgfx.debugdraw.createSprite),
    .destroySprite = @ptrCast(&zbgfx.debugdraw.destroySprite),
    .createGeometry = @ptrCast(&zbgfx.debugdraw.createGeometry),
    .destroyGeometry = @ptrCast(&zbgfx.debugdraw.destroyGeometry),

    .encoderCreate = createDDEncoder,
    .encoderDestroy = destroyDDEncoder,
};

pub fn ddBegin(dde: *anyopaque, _viewId: u16, _depthTestLess: bool, _encoder: ?*bgfx.Encoder) void {
    zbgfx.debugdraw.Encoder.begin(@alignCast(@ptrCast(dde)), _viewId, _depthTestLess, @alignCast(@ptrCast(_encoder)));

    // TODO: litle hack, cetech use opengl coordinates +x left, +y up, +z to screen
    zbgfx.debugdraw.Encoder.setState(@alignCast(@ptrCast(dde)), true, true, false);
}

pub fn getResolution() public.Resolution {
    const b = std.mem.toBytes(bgfxInit.resolution);
    return std.mem.bytesToValue(public.Resolution, &b);
}

pub fn createDDEncoder() public.DDEncoder {
    return public.DDEncoder{
        .ptr = zbgfx.debugdraw.Encoder.create(),
        .vtable = &dd_encoder_vt,
    };
}
pub fn destroyDDEncoder(encoder: public.DDEncoder) void {
    zbgfx.debugdraw.Encoder.destroy(@ptrCast(encoder.ptr));
}

fn getEncoder() ?public.Encoder {
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

pub fn endAllUsedEncoders() void {
    var zone_ctx = profiler.ztracy.ZoneN(@src(), "endAllUsedEncoders");
    defer zone_ctx.End();
    for (_encoder_map.values()) |encoder| {
        bgfx.encoderEnd(@ptrCast(encoder));
    }
    _encoder_map.clearRetainingCapacity();
}
