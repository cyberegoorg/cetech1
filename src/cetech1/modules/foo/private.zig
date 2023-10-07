const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const public = @import("module_foo.zig");

const MODULE_NAME = "foo";

const FOO_CDB_TYPE_NAME = "FooCDB";
const FOO_CDB_TYPE = cetech1.strid.strId32(FOO_CDB_TYPE_NAME);

var _allocator: Allocator = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;

var _db: cetech1.cdb.CdbDb = undefined;

var zig_api = public.FooAPI{};
var c_api = public.c.ct_foo_api_t{ .foo = &public.FooAPI.foo1_c };

const G = struct {
    var_1: u32 = 0,
};
var _g: *G = undefined;

var type_hash: cetech1.strid.StrId32 = undefined;
var type_hash2: cetech1.strid.StrId32 = undefined;
var ref_obj1: cetech1.cdb.ObjId = undefined;

fn cdb_create_types(db_: ?*cetech1.c.struct_ct_cdb_db_t) callconv(.C) void {
    var db = cetech1.cdb.CdbDb.fromDbT(@ptrCast(db_.?), _cdb);

    _ = db.addType(
        FOO_CDB_TYPE_NAME,
        &[_]cetech1.cdb.PropDef{
            .{ .name = "prop2", .type = cetech1.cdb.PropType.F32 },
            .{ .name = "kernel_tick", .type = cetech1.cdb.PropType.U64 },
            .{ .name = "prop3", .type = cetech1.cdb.PropType.REFERENCE_SET },
        },
    ) catch unreachable;

    type_hash = cetech1.cdb.addBigType(&db, "stress_foo_1") catch unreachable;
    type_hash2 = cetech1.cdb.addBigType(&db, "stress_foo_2") catch unreachable;
    ref_obj1 = db.createObject(type_hash2) catch undefined;
}
var create_types_i = cetech1.c.ct_cdb_create_types_i{ .create_types = cdb_create_types };

const KernelTask = struct {
    pub fn update(frame_allocator: std.mem.Allocator, main_db: ?*cetech1.c.ct_cdb_db_t, kernel_tick: u64, dt: f32) !void {
        _db = cetech1.cdb.CdbDb.fromDbT(@ptrCast(main_db.?), _cdb);
        _g.var_1 += 1;

        _log.info(MODULE_NAME, "kernel_tick:{}\tdt:{}\tg_var_1:{}", .{ kernel_tick, dt, _g.var_1 });

        // Alocator see in tracy
        var foo = try frame_allocator.create(public.FooAPI);
        _log.info(MODULE_NAME, "alloc {}", .{foo});
        defer frame_allocator.destroy(foo);

        // Cdb object create test
        try _db.stressIt(type_hash, type_hash2, ref_obj1);

        var obj1 = try _db.createObject(FOO_CDB_TYPE);
        _log.debug(MODULE_NAME, "obj1 id {d}", .{obj1.id});
        var writer = _db.writeObj(obj1);
        _db.setValue(f32, writer.?, 0, @floatFromInt(kernel_tick));
        _db.setValue(u64, writer.?, 1, kernel_tick);
        _db.writeCommit(writer.?);
        _db.destroyObject(obj1);

        std.time.sleep(1 * std.time.ns_per_ms);
    }

    pub fn init(main_db: ?*cetech1.c.ct_cdb_db_t) !void {
        _ = main_db;
        _log.info(MODULE_NAME, "TASK INIT", .{});
        var foo = _allocator.create(public.FooAPI) catch return;
        _log.info(MODULE_NAME, "alloc {}", .{foo});
        defer _allocator.destroy(foo);
    }

    pub fn shutdown() !void {
        _log.info(MODULE_NAME, "TASK SHUTDOWN", .{});
    }
};

var kernel_task = cetech1.kernel.KernelTaskInterface(
    "FooKernelTask",
    &[_]cetech1.strid.StrId64{},
    KernelTask.init,
    KernelTask.shutdown,
);

var update_task = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnUpdate,
    "FooUpdate",
    &[_]cetech1.strid.StrId64{},
    KernelTask.update,
);

var update_task2 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnUpdate,
    "FooUpdate2",
    &[_]cetech1.strid.StrId64{cetech1.strid.strId64("FooUpdate")},
    KernelTask.update,
);

var update_task3 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnUpdate,
    "FooUpdate3",
    &[_]cetech1.strid.StrId64{cetech1.strid.strId64("FooUpdate2")},
    KernelTask.update,
);

var update_task4 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnUpdate,
    "FooUpdate4",
    &[_]cetech1.strid.StrId64{
        cetech1.strid.strId64("FooUpdate2"),
        cetech1.strid.strId64("FooUpdate"),
    },
    KernelTask.update,
);

var update_task5 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnStore,
    "FooUpdate5",
    &[_]cetech1.strid.StrId64{
        //cetech1.strId64("FooUpdate4"),
    },
    KernelTask.update,
);
var update_task6 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnStore,
    "FooUpdate6",
    &[_]cetech1.strid.StrId64{
        //cetech1.strId64("FooUpdate4"),
    },
    KernelTask.update,
);
var update_task7 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnStore,
    "FooUpdate7",
    &[_]cetech1.strid.StrId64{
        //cetech1.strId64("FooUpdate4"),
    },
    KernelTask.update,
);
var update_task8 = cetech1.kernel.KernelTaskUpdateInterface(
    cetech1.kernel.OnStore,
    "FooUpdate8",
    &[_]cetech1.strid.StrId64{
        //cetech1.strId64("FooUpdate4"),
    },
    KernelTask.update,
);

pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    // basic
    _allocator = allocator;
    _log = log;
    _cdb = apidb.getZigApi(cetech1.cdb.CdbAPI).?;

    // set module api
    try apidb.setOrRemoveZigApi(public.FooAPI, &zig_api, load, reload);
    try apidb.setOrRemoveCApi(public.c.ct_foo_api_t, &c_api, load, reload);

    // simpl interface
    try apidb.implOrRemove(cetech1.c.ct_cdb_create_types_i, &create_types_i, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_i, &kernel_task, load);

    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task2, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task3, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task4, load);

    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task5, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task6, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task7, load);
    try apidb.implOrRemove(cetech1.c.ct_kernel_task_update_i, &update_task8, load);

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

pub export fn ct_load_module_foo(__apidb: ?*const cetech1.c.ct_apidb_api_t, __allocator: ?*const cetech1.c.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load == 1, __reload == 1);
}
