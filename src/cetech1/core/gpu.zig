const system = @import("system.zig");

pub const GpuContext = opaque {};

pub const GpuApi = struct {
    createContext: *const fn (window: *system.Window) anyerror!*GpuContext,
    destroyContext: *const fn (ctx: *GpuContext) void,

    // For now because ther is not HL rederer but....
    shitTempRender: *const fn (ctx: *GpuContext) void,
};
