const gui = @import("gui.zig");
const backend_glfw = @import("backend_glfw.zig");
const backend_vulkan = @import("backend_vulkan.zig");

pub const VkHandle = backend_vulkan.VkHandle;
pub const VkPipelineRenderingCreateInfo = backend_vulkan.VkPipelineRenderingCreateInfo;
pub const ImGui_ImplVulkan_InitInfo = backend_vulkan.ImGui_ImplVulkan_InitInfo;

pub fn init(init_info: ImGui_ImplVulkan_InitInfo, window: *const anyopaque) void {
    backend_glfw.initVulkan(window);
    backend_vulkan.init(init_info);
}

pub fn loadFunctions(
    loader: fn (function_name: [*:0]const u8, user_data: ?*anyopaque) callconv(.C) ?*anyopaque,
    user_data: ?*anyopaque,
) bool {
    return backend_vulkan.loadFunctions(loader, user_data);
}

pub fn deinit() void {
    backend_vulkan.deinit();
    backend_glfw.deinit();
}

pub fn newFrame(
    fb_width: u32,
    fb_height: u32,
) void {
    backend_glfw.newFrame();
    backend_vulkan.newFrame();

    gui.io.setDisplaySize(@as(f32, @floatFromInt(fb_width)), @as(f32, @floatFromInt(fb_height)));
    gui.io.setDisplayFramebufferScale(1.0, 1.0);

    gui.newFrame();
}

pub fn render(
    command_buffer: VkHandle,
) void {
    gui.render();
    backend_vulkan.render(command_buffer);
}

pub fn set_min_image_count(min_image_count: u32) void {
    backend_vulkan.set_min_image_count(min_image_count);
}
