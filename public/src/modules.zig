//! Module is main plugin like part of engine.

const std = @import("std");

const apidb = @import("apidb.zig");
const log_ = @import("log.zig");

pub const LoadModuleCABIFn = fn (apidb: *const apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool;
pub const LoadModuleZigFn = fn (allocator: std.mem.Allocator, load: bool, reload: bool) anyerror!bool;

const module_name = .modules;
const log = std.log.scoped(module_name);

pub const ModuleDesc = struct {
    name: [:0]const u8,
    module_fce: *const LoadModuleCABIFn,
};

/// Helper for using in Zig base modules.
pub fn loadModuleZigHelper(comptime load_module_zig: LoadModuleZigFn, comptime _module_name: @Type(.enum_literal), apidb_: *const apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) bool {
    apidb.loadAPI(apidb_) catch return false;
    log_.loadAPI(_module_name) catch return false;

    const r = load_module_zig(_allocator.*, load, reload) catch |err| {
        log.err("Could not load module {}", .{err});
        return false;
    };

    return r;
}
