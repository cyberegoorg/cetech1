//! Module is main plugin like part of engine.

const std = @import("std");
const c = @import("c.zig");
const apidb = @import("apidb.zig");
const LogAPI = @import("log.zig").LogAPI;

pub const LoadModuleFn = fn (apidb: ?*const c.c.ct_apidb_api_t, _allocator: ?*const c.c.ct_allocator_t, load: u8, reload: u8) callconv(.C) u8;
pub const LoadModuleZigFn = fn (apidb: *apidb.ApiDbAPI, allocator: std.mem.Allocator, _log: *LogAPI, load: bool, reload: bool) anyerror!bool;

pub inline fn loadModuleZigHelper(comptime load_module_zig: LoadModuleZigFn, _apidb: ?*const c.c.ct_apidb_api_t, _allocator: ?*const c.c.ct_allocator_t, load: bool, reload: bool) u8 {
    const MODULE_NAME = "module";

    var apidb_api = _apiFromCApi(_apidb.?);
    var allocator = _allocFromCApi(_allocator.?);
    var log = apidb_api.getZigApi(LogAPI).?;

    var r = load_module_zig(apidb_api, allocator, log, load, reload) catch |err| {
        log.err(MODULE_NAME, "Could not load module {}\n", .{err});
        return 0;
    };

    return @intFromBool(r);
}

inline fn _allocFromCApi(allocator: *const c.c.ct_allocator_t) std.mem.Allocator {
    var _a: *std.mem.Allocator = @ptrFromInt(@intFromPtr(allocator));
    return _a.*;
}

inline fn _apiFromCApi(_apidb: *const c.c.ct_apidb_api_t) *apidb.ApiDbAPI {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(apidb.ApiDbAPI), ".");
    var _api = _apidb.get_api.?(apidb.ApiDbAPI.lang_zig, name_iter.first().ptr, @sizeOf(apidb.ApiDbAPI));
    return @ptrFromInt(@intFromPtr(_api));
}
