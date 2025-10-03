const zgui = @import("zgui");
const zbgfx = @import("zbgfx");

var backend_init = false;

pub fn init(
    window: ?*const anyopaque, // zglfw.Window
) void {
    if (window) |w| {
        zgui.backend.init(w);
        backend_init = true;
    }

    ImGui_ImplBgfx_Init();
}

pub fn deinit() void {
    ImGui_ImplBgfx_Shutdown();
    if (backend_init) zgui.backend.deinit();
}

pub fn newFrame(viewid: zbgfx.bgfx.ViewId) void {
    if (backend_init) zgui.backend.newFrame();

    ImGui_ImplBgfx_NewFrame(viewid);
    zgui.gizmo.beginFrame();
}

pub fn draw() void {
    ImGui_ImplBgfx_RenderDrawData();
}

extern fn ImGui_ImplBgfx_Init() void;
extern fn ImGui_ImplBgfx_Shutdown() void;
extern fn ImGui_ImplBgfx_NewFrame(_viewId: zbgfx.bgfx.ViewId) void;
extern fn ImGui_ImplBgfx_RenderDrawData() void;
