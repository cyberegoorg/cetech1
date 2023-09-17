const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const public = @import("module_foo.zig");

const MODULE_NAME = "FooModule";

var _allocator: Allocator = undefined;
var _log: *cetech1.LogAPI = undefined;

var zig_api = public.FooAPI{};
var c_api = public.c.ct_foo_api_t{ .foo = &public.FooAPI.foo1_c };

const G = struct {
    var_1: u32 = 0,
};
var _g: *G = undefined;

const KernelTask = struct {
    pub fn update(kernel_tick: u64, dt: f32) callconv(.C) void {
        _g.var_1 += 1;

        _log.info(MODULE_NAME, "kernel_tick:{}\tdt:{}\tg_var_1:{}", .{ kernel_tick, dt, _g.var_1 });
    }

    pub fn init() callconv(.C) void {
        _log.info(MODULE_NAME, "TASK INIT", .{});
        var foo = _allocator.create(public.FooAPI) catch return;
        _log.info(MODULE_NAME, "alloc {}", .{foo});
        defer _allocator.destroy(foo);
    }

    pub fn shutdown() callconv(.C) void {
        _log.info(MODULE_NAME, "TASK SHUTDOWN", .{});
    }
};

var kernel_task = cetech1.KernelTaskInterface(
    "FooKernelTask",
    &[_]cetech1.StrId64{},
    KernelTask.init,
    KernelTask.shutdown,
);

var update_task = cetech1.KernelTaskUpdateInterface(
    cetech1.OnUpdate,
    "FooUpdate",
    &[_]cetech1.StrId64{},
    KernelTask.update,
);

var update_task2 = cetech1.KernelTaskUpdateInterface(
    cetech1.OnUpdate,
    "FooUpdate2",
    &[_]cetech1.StrId64{cetech1.strId64("FooUpdate")},
    KernelTask.update,
);

var update_task3 = cetech1.KernelTaskUpdateInterface(
    cetech1.OnUpdate,
    "FooUpdate3",
    &[_]cetech1.StrId64{cetech1.strId64("FooUpdate2")},
    KernelTask.update,
);

var update_task4 = cetech1.KernelTaskUpdateInterface(
    cetech1.OnUpdate,
    "FooUpdate4",
    &[_]cetech1.StrId64{
        cetech1.strId64("FooUpdate2"),
        cetech1.strId64("FooUpdate"),
    },
    KernelTask.update,
);

pub fn load_module_zig(apidb: *cetech1.ApiDbAPI, allocator: Allocator, log: *cetech1.LogAPI, load: bool, reload: bool) anyerror!bool {
    // basic
    _allocator = allocator;
    _log = log;

    // set module api
    try apidb.setOrRemoveZigApi(public.FooAPI, &zig_api, load, reload);
    try apidb.setOrRemoveCApi(public.c.ct_foo_api_t, &c_api, load, reload);

    // simpl interface
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_i, &kernel_task, load, reload);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task, load, reload);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task2, load, reload);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task3, load, reload);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task4, load, reload);

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g");

    // Only set on first load.
    if (load and !reload) {
        _g.* = .{};
    }

    if (load) {
        _log.info(MODULE_NAME, "LOAD", .{});
        return true;
    }

    if (!load) {
        _log.info(MODULE_NAME, "UNLOAD", .{});
        return true;
    }

    if (reload) {
        _log.info(MODULE_NAME, "WITH RELOAD", .{});
    }

    return true;
}

pub export fn load_module(__apidb: ?*const cetech1.c.ct_apidb_api_t, __allocator: ?*const cetech1.c.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load == 1, __reload == 1);
}