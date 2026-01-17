const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const native_script_component = @import("native_script_component");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const module_name = .example_native_script;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

// Native script instance for one entity.
const NativeScriptInstance = struct {
    ent: ecs.EntityId,
};

const native_script_i = native_script_component.NativeScriptI.implement(.{
    .name = "example_native_script",
    .display_name = "Example native script",
}, struct {
    pub fn init(allocator: std.mem.Allocator, entity: ecs.EntityId) !?*anyopaque {
        log.debug("INIT for entity {d}", .{entity});
        const inst = try allocator.create(NativeScriptInstance);
        inst.* = .{ .ent = entity };
        return inst;
    }

    pub fn shutdown(allocator: std.mem.Allocator, inst: ?*anyopaque) !void {
        const instance: *NativeScriptInstance = @ptrCast(@alignCast(inst));

        log.debug("SHUTDOWN for entity {d}", .{instance.ent});

        allocator.destroy(instance);
    }

    pub fn update(inst: ?*anyopaque) !void {
        const instance: *NativeScriptInstance = @ptrCast(@alignCast(inst));
        log.debug("UPDATE for entity {d}", .{instance.ent});
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;

    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    // impl interface
    try apidb.implOrRemove(module_name, native_script_component.NativeScriptI, &native_script_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_example_native_script(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
