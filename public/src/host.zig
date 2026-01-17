const std = @import("std");

const input = @import("input.zig");
const math = @import("math.zig");

pub const CursorMode = enum(u32) {
    Normal = 0,
    Hidden,
    Disabled,
    Captured,
};

pub const Window = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn shouldClose(self: Window) bool {
        return self.vtable.shouldClose(self.ptr);
    }

    pub inline fn setShouldClose(self: Window, should_close: bool) void {
        return self.vtable.setShouldClose(self.ptr, should_close);
    }

    pub inline fn getInternal(self: Window, comptime T: type) *const T {
        return @ptrCast(self.vtable.getInternalHandler(self.ptr));
    }

    pub inline fn getFramebufferSize(self: Window) [2]i32 {
        return self.vtable.getFramebufferSize(self.ptr);
    }

    pub inline fn getContentScale(self: Window) math.Vec2f {
        return self.vtable.getContentScale(self.ptr);
    }

    pub inline fn getOsWindowHandler(self: Window) ?*anyopaque {
        return self.vtable.getOsWindowHandler(self.ptr);
    }

    pub inline fn getOsDisplayHandler(self: Window) ?*anyopaque {
        return self.vtable.getOsDisplayHandler(self.ptr);
    }

    pub inline fn getScroll(self: Window) [2]f64 {
        return self.vtable.getScroll(self.ptr);
    }

    pub inline fn getCursorPos(self: Window) [2]f64 {
        return self.vtable.getCursorPos(self.ptr);
    }

    pub inline fn setCursorMode(self: Window, mode: CursorMode) void {
        return self.vtable.setCursorMode(self.ptr, mode);
    }

    pub const VTable = struct {
        shouldClose: *const fn (window: *anyopaque) bool,
        getInternalHandler: *const fn (window: *anyopaque) *const anyopaque,
        getFramebufferSize: *const fn (window: *anyopaque) [2]i32,
        getContentScale: *const fn (window: *anyopaque) math.Vec2f,
        getOsWindowHandler: *const fn (window: *anyopaque) ?*anyopaque,
        getOsDisplayHandler: *const fn (window: *anyopaque) ?*anyopaque,
        getScroll: *const fn (window: *anyopaque) [2]f64,
        getCursorPos: *const fn (window: *anyopaque) [2]f64,
        setCursorMode: *const fn (window: *anyopaque, mode: CursorMode) void,
        setShouldClose: *const fn (window: *anyopaque, should_close: bool) void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "shouldClose")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setShouldClose")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getInternalHandler")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getFramebufferSize")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getContentScale")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getOsWindowHandler")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getOsDisplayHandler")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getCursorPos")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setCursorMode")) @compileError("implement me");
            if (!std.meta.hasFn(T, "getScroll")) @compileError("implement me");

            return VTable{
                .shouldClose = T.shouldClose,
                .setShouldClose = T.setShouldClose,
                .getInternalHandler = T.getInternalHandler,
                .getFramebufferSize = T.getFramebufferSize,
                .getContentScale = T.getContentScale,
                .getOsWindowHandler = T.getOsWindowHandler,
                .getOsDisplayHandler = T.getOsDisplayHandler,
                .getCursorPos = T.getCursorPos,
                .setCursorMode = T.setCursorMode,
                .getScroll = T.getScroll,
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
        return self.vtable.getMonitorVideoMode(self.ptr);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getMonitorVideoMode: *const fn (monitor: *anyopaque) anyerror!*VideoMode,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "getMonitorVideoMode")) @compileError("implement me");

            return VTable{
                .getMonitorVideoMode = T.getMonitorVideoMode,
            };
        }
    };
};

pub const PlatformApi = struct {
    update: *const fn (kernel_tick: u64, timeout: f64) anyerror!void,
};

pub const MonitorApi = struct {
    getPrimaryMonitor: *const fn () ?Monitor,
};

pub const WMType = enum {
    X11,
    Wayland,
    Native,
};

pub const WindowApi = struct {
    createWindow: *const fn (width: i32, height: i32, title: [:0]const u8, monitor: ?Monitor) anyerror!Window,
    destroyWindow: *const fn (window: Window) void,
    getWMType: *const fn () WMType,
};

pub const OpenInType = enum {
    Reveal,
    OpenURL,
    Edit,
};

pub const SystemApi = struct {
    openIn: *const fn (allocator: std.mem.Allocator, open_type: OpenInType, url: []const u8) anyerror!void,
};

pub const DialogsFilterItem = extern struct {
    name: [*:0]const u8,
    spec: [*:0]const u8,
};

pub const DialogsApi = struct {
    supportFileDialog: *const fn () bool,
    openFileDialog: *const fn (allocator: std.mem.Allocator, filter: ?[]const DialogsFilterItem, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
    saveFileDialog: *const fn (allocator: std.mem.Allocator, filter: ?[]const DialogsFilterItem, default_path: ?[:0]const u8, default_name: ?[:0]const u8) anyerror!?[:0]const u8,
    openFolderDialog: *const fn (allocator: std.mem.Allocator, default_path: ?[:0]const u8) anyerror!?[:0]const u8,
};
