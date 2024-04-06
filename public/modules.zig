//! Module is main plugin like part of engine.

const std = @import("std");
const c = @import("c.zig");
const apidb = @import("apidb.zig");
const LogAPI = @import("log.zig").LogAPI;

pub const ct_module_desc_t = c.c.ct_module_desc_t;

pub const LoadModuleFn = fn (apidb: *const c.c.ct_apidb_api_t, _allocator: *const c.c.ct_allocator_t, load: bool, reload: bool) callconv(.C) bool;
pub const LoadModuleZigFn = fn (apidb: *apidb.ApiDbAPI, allocator: std.mem.Allocator, _log: *LogAPI, load: bool, reload: bool) anyerror!bool;

const module_name = .modules;
const log = std.log.scoped(module_name);

/// Helper for using in Zig base modules.
pub fn loadModuleZigHelper(comptime load_module_zig: LoadModuleZigFn, comptime _module_name: @Type(.EnumLiteral), _apidb: *const c.c.ct_apidb_api_t, _allocator: *const c.c.ct_allocator_t, load: bool, reload: bool) bool {
    var apidb_api = apiFromCApi(_module_name, _apidb);
    const allocator = allocFromCApi(_allocator);
    const log_api = apidb_api.getZigApi(_module_name, LogAPI).?;

    const r = load_module_zig(apidb_api, allocator, log_api, load, reload) catch |err| {
        log.err("Could not load module {}", .{err});
        return false;
    };

    return r;
}

pub fn allocFromCApi(allocator: *const c.c.ct_allocator_t) std.mem.Allocator {
    const _a: *std.mem.Allocator = @ptrFromInt(@intFromPtr(allocator));
    return _a.*;
}

pub fn apiFromCApi(comptime _module_name: @Type(.EnumLiteral), _apidb: *const c.c.ct_apidb_api_t) *apidb.ApiDbAPI {
    var name_iter = std.mem.splitBackwardsAny(u8, @typeName(apidb.ApiDbAPI), ".");
    const _api = _apidb.get_api.?(@tagName(_module_name), apidb.ApiDbAPI.lang_zig, name_iter.first().ptr, @sizeOf(apidb.ApiDbAPI));
    return @ptrFromInt(@intFromPtr(_api));
}
