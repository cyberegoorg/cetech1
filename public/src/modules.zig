//! Module is main plugin like part of engine.

const std = @import("std");

const apidb = @import("apidb.zig");
const LogAPI = @import("log.zig").LogAPI;

pub const LoadModuleFn = fn (apidb: *const apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool;
pub const LoadModuleZigFn = fn (apidb: *const apidb.ApiDbAPI, allocator: std.mem.Allocator, _log: *const LogAPI, load: bool, reload: bool) anyerror!bool;

const module_name = .modules;
const log = std.log.scoped(module_name);

pub const ModuleDesc = struct {
    name: [:0]const u8,
    module_fce: *const LoadModuleFn,
};

/// Helper for using in Zig base modules.
pub fn loadModuleZigHelper(comptime load_module_zig: LoadModuleZigFn, comptime _module_name: @Type(.enum_literal), _apidb: *const apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) bool {
    const log_api = _apidb.getZigApi(_module_name, LogAPI).?;

    const r = load_module_zig(_apidb, _allocator.*, log_api, load, reload) catch |err| {
        log.err("Could not load module {}", .{err});
        return false;
    };

    return r;
}
