const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;
const cdb = cetech1.cdb;

const public = @import("module_foo.zig");

const MODULE_NAME = "foo";

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cdb.CdbAPI = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;

var _db: cdb.CdbDb = undefined;

const spam_log = false;
const do_cdb = false;

// Create c and zig api
var zig_api = public.FooAPI{};
var c_api = public.c.ct_foo_api_t{ .foo = &public.FooAPI.foo1_c };

// Global state that can surive hot-reload
const G = struct {
    var_1: u32 = 0,
    type_hash: strid.StrId32 = undefined,
    type_hash2: strid.StrId32 = undefined,
    ref_obj1: cdb.ObjId = undefined,
};
var _g: *G = undefined;

// Foo cdb type decl
const FooCDBType = cdb.CdbTypeDecl(
    "ct_foo_cdb",
    enum(u32) {
        PROP1 = 0,
        KERNEL_TICK,
        PROP2,
    },
);

// Register all cdb stuff in this method

var create_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db_: *cdb.Db) !void {
        var db = cdb.CdbDb.fromDbT(db_, _cdb);

        _ = try db.addType(
            FooCDBType.name,
            &[_]cdb.PropDef{
                .{ .prop_idx = FooCDBType.propIdx(.PROP1), .name = "prop1", .type = cdb.PropType.F32 },
                .{ .prop_idx = FooCDBType.propIdx(.KERNEL_TICK), .name = "kernel_tick", .type = cdb.PropType.U64 },
                .{ .prop_idx = FooCDBType.propIdx(.PROP2), .name = "prop2", .type = cdb.PropType.REFERENCE_SET },
            },
        );

        _g.type_hash = cetech1.cdb_types.addBigType(&db, "stress_foo_1") catch unreachable;
        _g.type_hash2 = cetech1.cdb_types.addBigType(&db, "stress_foo_2") catch unreachable;

        _g.ref_obj1 = db.createObject(_g.type_hash2) catch undefined;
    }
});

// Create simple update kernel task
const KernelTask = struct {
    pub fn update(frame_allocator: std.mem.Allocator, main_db: *cdb.Db, kernel_tick: u64, dt: f32) !void {
        _db = cdb.CdbDb.fromDbT(main_db, _cdb);
        _g.var_1 += 1;

        if (spam_log) _log.info(MODULE_NAME, "kernel_tick:{}\tdt:{}\tg_var_1:{}", .{ kernel_tick, dt, _g.var_1 });

        // Alocator see in tracy
        const foo = try frame_allocator.create(public.FooAPI);
        if (spam_log) _log.info(MODULE_NAME, "alloc {}", .{foo});

        defer frame_allocator.destroy(foo);

        // Cdb object create test
        if (do_cdb) {
            try _db.stressIt(_g.type_hash, _g.type_hash2, _g.ref_obj1);

            const obj1 = try FooCDBType.createObject(&_db);
            if (spam_log) _log.debug(MODULE_NAME, "obj1 id {d}", .{obj1.id});

            if (_db.writeObj(obj1)) |writer| {
                defer _db.writeCommit(writer);

                FooCDBType.setValue(&_db, f32, writer, .PROP1, @floatFromInt(kernel_tick));
                FooCDBType.setValue(&_db, u64, writer, .KERNEL_TICK, kernel_tick);
            }

            const version = _db.getVersion(obj1);
            if (spam_log) _log.debug(MODULE_NAME, "obj1 version {d}", .{version});
            _db.destroyObject(obj1);
        }

        std.time.sleep(1 * std.time.ns_per_ms);
    }
};

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "FooKernelTask",
    &[_]strid.StrId64{},
    struct {
        pub fn init(main_db: *cdb.Db) !void {
            _ = main_db;
            _log.info(MODULE_NAME, "TASK INIT", .{});
            const foo = _allocator.create(public.FooAPI) catch return;
            _log.info(MODULE_NAME, "alloc {}", .{foo});
            defer _allocator.destroy(foo);
        }

        pub fn shutdown() !void {
            _log.info(MODULE_NAME, "TASK SHUTDOWN", .{});
        }
    },
);

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate",
    &[_]strid.StrId64{},
    KernelTask.update,
);

var update_task2 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate2",
    &[_]strid.StrId64{strid.strId64("FooUpdate")},
    KernelTask.update,
);

var update_task3 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate3",
    &[_]strid.StrId64{strid.strId64("FooUpdate2")},
    KernelTask.update,
);

var update_task4 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate4",
    &[_]strid.StrId64{
        strid.strId64("FooUpdate2"),
        strid.strId64("FooUpdate"),
    },
    KernelTask.update,
);

var update_task5 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate5",
    &[_]strid.StrId64{
        //strid.strId64("FooUpdate4"),
    },
    KernelTask.update,
);
var update_task6 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate6",
    &[_]strid.StrId64{
        //strid.strId64("FooUpdate5"),
    },
    KernelTask.update,
);
var update_task7 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate7",
    &[_]strid.StrId64{
        //strid.strId64("FooUpdate5"),
    },
    KernelTask.update,
);
var update_task8 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate8",
    &[_]strid.StrId64{
        //strid.strId64("FooUpdate7"),
    },
    KernelTask.update,
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    // basic
    _allocator = allocator;
    _log = log;
    _cdb = apidb.getZigApi(cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;

    // set module api
    try apidb.setOrRemoveZigApi(public.FooAPI, &zig_api, load);
    try apidb.setOrRemoveCApi(public.c.ct_foo_api_t, &c_api, load);

    // impl interface
    try apidb.implOrRemove(cdb.CreateTypesI, &create_types_i, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskI, &kernel_task, load);

    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task2, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task3, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task4, load);

    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task5, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task6, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task7, load);
    try apidb.implOrRemove(cetech1.kernel.KernelTaskUpdateI, &update_task8, load);

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

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

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_foo(__apidb: ?*const cetech1.apidb.ct_apidb_api_t, __allocator: ?*const cetech1.apidb.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
