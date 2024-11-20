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

pub fn newFrame(fb_width: u32, fb_height: u32) void {
    var w = fb_width;
    var h = fb_height;

    // Headless mode
    // Set some default imgui screen size
    if (fb_width == 0 and fb_height == 0) {
        w = 1024;
        h = 768;
    }

    if (backend_init) zgui.backend.newFrame();

    zgui.io.setDisplaySize(@floatFromInt(w), @floatFromInt(h));
    zgui.io.setDisplayFramebufferScale(1.0, 1.0);

    ImGui_ImplBgfx_NewFrame(255);
    zgui.gizmo.beginFrame();
}

pub fn draw() void {
    ImGui_ImplBgfx_RenderDrawData();
}

extern fn ImGui_ImplBgfx_Init() void;
extern fn ImGui_ImplBgfx_Shutdown() void;
extern fn ImGui_ImplBgfx_NewFrame(_viewId: zbgfx.bgfx.ViewId) void;
extern fn ImGui_ImplBgfx_RenderDrawData() void;
