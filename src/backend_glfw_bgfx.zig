const gui = @import("zgui");
const zbgfx = @import("zbgfx");

var glfw_init = false;

pub fn init(
    window: ?*const anyopaque, // zglfw.Window
) void {
    if (window) |w| {
        gui.backend.init(w);
        glfw_init = true;
    }

    ImGui_ImplBgfx_Init();
}

pub fn deinit() void {
    ImGui_ImplBgfx_Shutdown();
    if (glfw_init) gui.backend.deinit();
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

    if (glfw_init) gui.backend.newFrame();

    gui.io.setDisplaySize(@floatFromInt(w), @floatFromInt(h));
    gui.io.setDisplayFramebufferScale(1.0, 1.0);

    ImGui_ImplBgfx_NewFrame(255);
}

pub fn draw() void {
    ImGui_ImplBgfx_RenderDrawData();
}

extern fn ImGui_ImplBgfx_Init() void;
extern fn ImGui_ImplBgfx_Shutdown() void;
extern fn ImGui_ImplBgfx_NewFrame(_viewId: zbgfx.bgfx.ViewId) void;
extern fn ImGui_ImplBgfx_RenderDrawData() void;
