const std = @import("std");
const system = @import("system.zig");
const strid = @import("strid.zig");
const cdb = @import("cdb.zig");

const log = std.log.scoped(.gpu);

pub const GpuContext = opaque {};

// TODO: TEMP SHIT
pub const GpuPresentI = extern struct {
    pub const c_name = "ct_gpu_present_i";
    pub const name_hash = strid.strId64(@This().c_name);

    present: *const fn (db: *cdb.Db, kernel_tick: u64, dt: f32) callconv(.C) void,

    pub inline fn implement(
        comptime T: type,
    ) GpuPresentI {
        if (!std.meta.hasFn(T, "present")) @compileError("implement me");

        return GpuPresentI{
            .present = struct {
                pub fn f(db: *cdb.Db, kernel_tick: u64, dt: f32) callconv(.C) void {
                    T.present(db, kernel_tick, dt) catch |err| {
                        log.err("GpuPresentI.present() failed with error {}", .{err});
                    };
                }
            }.f,
        };
    }
};

pub const GpuApi = struct {
    createContext: *const fn (window: *system.Window, vsync: bool) anyerror!*GpuContext,
    destroyContext: *const fn (ctx: *GpuContext) void,

    // For now because ther is not HL rederer but....
    shitTempRender: *const fn (ctx: *GpuContext, db: *cdb.CdbDb, kernel_tick: u64, dt: f32) void,
};
