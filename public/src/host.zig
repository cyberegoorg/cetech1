const std = @import("std");

const input = @import("input.zig");
const math = @import("math.zig");
const cetech1 = @import("root.zig");

const apidb = cetech1.apidb;
pub const WMType = enum {
    X11,
    Wayland,
    Native,
};

pub const OpenInType = enum {
    Reveal,
    OpenURL,
    Edit,
};

pub const DialogsFilterItem = extern struct {
    name: [*:0]const u8,
    spec: [*:0]const u8,
};

pub const CursorMode = enum(u32) {
    Normal = 0,
    Hidden,
    Disabled,
    Captured,
};

pub const Window = struct {
    pub inline fn shouldClose(self: Window) bool {
        return self.vtable.should_close(self.ptr);
    }

    pub inline fn setShouldClose(self: Window, should_close: bool) void {
        return self.vtable.set_should_close(self.ptr, should_close);
    }

    pub inline fn getInternal(self: Window, comptime T: type) *const T {
        return @ptrCast(self.vtable.get_internal_handler(self.ptr));
    }

    pub inline fn getFramebufferSize(self: Window) [2]i32 {
        return self.vtable.get_framebuffer_size(self.ptr);
    }

    pub inline fn getContentScale(self: Window) math.Vec2f {
        return self.vtable.get_content_scale(self.ptr);
    }

    pub inline fn getOsWindowHandler(self: Window) ?*anyopaque {
        return self.vtable.get_os_window_handler(self.ptr);
    }

    pub inline fn getOsDisplayHandler(self: Window) ?*anyopaque {
        return self.vtable.get_os_display_handler(self.ptr);
    }

    pub inline fn getScroll(self: Window) [2]f64 {
        return self.vtable.get_scroll(self.ptr);
    }

    pub inline fn getCursorPos(self: Window) [2]f64 {
        return self.vtable.get_cursor_pos(self.ptr);
    }

    pub inline fn setCursorMode(self: Window, mode: CursorMode) void {
        return self.vtable.set_cursor_mode(self.ptr, mode);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        should_close: *const fn (window: *anyopaque) bool,
        get_internal_handler: *const fn (window: *anyopaque) *const anyopaque,
        get_framebuffer_size: *const fn (window: *anyopaque) [2]i32,
        get_content_scale: *const fn (window: *anyopaque) math.Vec2f,
        get_os_window_handler: *const fn (window: *anyopaque) ?*anyopaque,
        get_os_display_handler: *const fn (window: *anyopaque) ?*anyopaque,
        get_scroll: *const fn (window: *anyopaque) [2]f64,
        get_cursor_pos: *const fn (window: *anyopaque) [2]f64,
        set_cursor_mode: *const fn (window: *anyopaque, mode: CursorMode) void,
        set_should_close: *const fn (window: *anyopaque, should_close: bool) void,

        pub fn implement(comptime T: type) VTable {
            return VTable{
                .should_close = T.shouldClose,
                .set_should_close = T.setShouldClose,
                .get_internal_handler = T.getInternalHandler,
                .get_framebuffer_size = T.getFramebufferSize,
                .get_content_scale = T.getContentScale,
                .get_os_window_handler = T.getOsWindowHandler,
                .get_os_display_handler = T.getOsDisplayHandler,
                .get_cursor_pos = T.getCursorPos,
                .set_cursor_mode = T.setCursorMode,
                .get_scroll = T.getScroll,
            };
        }
    };
};

pub const Monitor = struct {
    pub const VideoMode = extern struct {
        width: c_int,
        height: c_int,
        red_bits: c_int,
        green_bits: c_int,
        blue_bits: c_int,
        refresh_rate: c_int,
    };

    pub inline fn getVideoMode(self: Monitor) !*VideoMode {
        return self.vtable.get_monitor_video_mode(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        get_monitor_video_mode: *const fn (monitor: *anyopaque) anyerror!*VideoMode,

        pub fn implement(comptime T: type) VTable {
            return VTable{
                .get_monitor_video_mode = T.getMonitorVideoMode,
            };
        }
    };
};

pub fn supportFileDialog() bool {
    return dialogs_api.supportFileDialog();
}
pub fn openFileDialog(allocator: std.mem.Allocator, filter: ?[]const DialogsFilterItem, default_path: ?[:0]const u8) anyerror!?[:0]const u8 {
    return dialogs_api.openFileDialog(allocator, filter, default_path);
}
pub fn saveFileDialog(allocator: std.mem.Allocator, filter: ?[]const DialogsFilterItem, default_path: ?[:0]const u8, default_name: ?[:0]const u8) anyerror!?[:0]const u8 {
    return dialogs_api.saveFileDialog(allocator, filter, default_path, default_name);
}
pub fn openFolderDialog(allocator: std.mem.Allocator, default_path: ?[:0]const u8) anyerror!?[:0]const u8 {
    return dialogs_api.openFolderDialog(allocator, default_path);
}
pub fn openIn(allocator: std.mem.Allocator, open_type: OpenInType, url: []const u8) anyerror!void {
    return system_api.openIn(allocator, open_type, url);
}
pub fn createWindow(width: i32, height: i32, title: [:0]const u8, monitor: ?Monitor) anyerror!Window {
    return window_api.createWindow(width, height, title, monitor);
}
pub fn destroyWindow(window: Window) void {
    return window_api.destroyWindow(window);
}
pub fn getWMType() WMType {
    return window_api.getWmType();
}
pub fn getPrimaryMonitor() ?Monitor {
    return monitor_api.get_primary_monitor();
}
pub fn update(kernel_tick: u64, timeout: f64) anyerror!void {
    return platform_api.update(kernel_tick, timeout);
}

pub const PlatformApi = struct {
    update: *const fn (kernel_tick: u64, timeout: f64) anyerror!void,
};

pub const MonitorApi = struct {
    get_primary_monitor: *const fn () ?Monitor,
};

pub const WindowApi = struct {
    createWindow: *const fn (width: i32, height: i32, title: [:0]const u8, monitor: ?Monitor) anyerror!Window,
    destroyWindow: *const fn (window: Window) void,
    getWmType: *const fn () WMType,
};

pub const SystemApi = struct {
    openIn: *const fn (allocator: std.mem.Allocator, open_type: OpenInType, url: []const u8) anyerror!void,
};

pub const DialogsApi = struct {
    supportFileDialog: *const fn () bool,
    openFileDialog: *const fn (allocator: std.mem.Allocator, filter: ?[]const DialogsFilterItem, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    saveFileDialog: *const fn (allocator: std.mem.Allocator, filter: ?[]const DialogsFilterItem, default_path: ?[:0]const u8, default_name: ?[:0]const u8) anyerror!?[:0]const u8,
    openFolderDialog: *const fn (allocator: std.mem.Allocator, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
};

pub var platform_api: *const PlatformApi = undefined;
pub var monitor_api: *const MonitorApi = undefined;
pub var window_api: *const WindowApi = undefined;
pub var system_api: *const SystemApi = undefined;
pub var dialogs_api: *const DialogsApi = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    platform_api = apidb.getZigApi(module, PlatformApi).?;
    monitor_api = apidb.getZigApi(module, MonitorApi).?;
    window_api = apidb.getZigApi(module, WindowApi).?;
    system_api = apidb.getZigApi(module, SystemApi).?;
    dialogs_api = apidb.getZigApi(module, DialogsApi).?;
}
