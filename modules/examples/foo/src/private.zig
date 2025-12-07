const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;

const public = @import("module_foo.zig");

const module_name = .sample_foo;

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

// Play with this constants to enable some features
const spam_log = false;
const do_tasks = false;
const do_cdb = false;

// Create zig api
const api = public.FooAPI{};

// Global state that can surive hot-reload
const G = struct {
    var_1: u32 = 0,
    type_hash: cdb.TypeIdx = undefined,
    type_hash2: cdb.TypeIdx = undefined,
    ref_obj1: cdb.ObjId = undefined,
};
var _g: *G = undefined;

// Foo cdb type decl
const FooCDB = cdb.CdbTypeDecl(
    "ct_foo_cdb",
    enum(u32) {
        PROP1 = 0,
        KERNEL_TICK,
        PROP2,
    },
    struct {},
);

// Register all cdb stuff in this method

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _ = try _cdb.addType(
            db,
            FooCDB.name,
            &[_]cdb.PropDef{
                .{ .prop_idx = FooCDB.propIdx(.PROP1), .name = "prop1", .type = cdb.PropType.F32 },
                .{ .prop_idx = FooCDB.propIdx(.KERNEL_TICK), .name = "kernel_tick", .type = cdb.PropType.U64 },
                .{ .prop_idx = FooCDB.propIdx(.PROP2), .name = "prop2", .type = cdb.PropType.REFERENCE_SET },
            },
        );

        _g.type_hash = cetech1.cdb_types.addBigType(_cdb, db, "stress_foo_1", null) catch unreachable;
        _g.type_hash2 = cetech1.cdb_types.addBigType(_cdb, db, "stress_foo_2", null) catch unreachable;

        _g.ref_obj1 = _cdb.createObject(db, _g.type_hash2) catch undefined;
    }
});

// Create simple update kernel task
const KernelTask = struct {
    pub fn update(kernel_tick: u64, dt: f32) !void {
        _cdb = _kernel.getDb();
        _g.var_1 += 1;

        const allocator = try _tmpalloc.create();
        defer _tmpalloc.destroy(allocator);

        if (spam_log) log.info("kernel_tick:{}\tdt:{}\tg_var_1:{}", .{ kernel_tick, dt, _g.var_1 });

        // Alocator see in tracy
        const foo = try allocator.create(public.FooAPI);
        if (spam_log) log.info("alloc {}", .{foo});

        defer allocator.destroy(foo);

        // Cdb object create test
        // if (do_cdb) {
        //     try _db.stressIt(_g.type_hash, _g.type_hash2, _g.ref_obj1);

        //     const obj1 = try FooCDB.createObject(_cdb);
        //     if (spam_log) log.debug("obj1 id {d}", .{obj1.id});

        //     if (_cdb.writeObj(obj1)) |writer| {
        //         defer _cdb.writeCommit(writer);

        //         FooCDB.setValue(_cdb, f32, writer, .PROP1, @floatFromInt(kernel_tick));
        //         FooCDB.setValue(_cdb, u64, writer, .KERNEL_TICK, kernel_tick);
        //     }

        //     const version = _cdb.getVersion(obj1);
        //     if (spam_log) log.debug("obj1 version {d}", .{version});
        //     _db.destroyObject(obj1);
        // }

        //std.Thread.sleep(1 * std.time.ns_per_ms);
    }
};

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "FooKernelTask",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            log.info("TASK INIT", .{});
            const foo = _allocator.create(public.FooAPI) catch return;
            log.info("alloc {}", .{foo});
            defer _allocator.destroy(foo);
        }

        pub fn shutdown() !void {
            log.info("TASK SHUTDOWN", .{});
        }
    },
);

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate",
    &[_]cetech1.StrId64{},
    null,
    KernelTask,
);

var update_task2 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate2",
    &[_]cetech1.StrId64{.fromStr("FooUpdate")},
    null,
    KernelTask,
);

var update_task3 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate3",
    &[_]cetech1.StrId64{.fromStr("FooUpdate2")},
    null,
    KernelTask,
);

var update_task4 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnUpdate,
    "FooUpdate4",
    &[_]cetech1.StrId64{
        .fromStr("FooUpdate2"),
        .fromStr("FooUpdate"),
    },
    null,
    KernelTask,
);

var update_task5 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate5",
    &[_]cetech1.StrId64{
        //.fromStr("FooUpdate4"),
    },
    null,
    KernelTask,
);
var update_task6 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate6",
    &[_]cetech1.StrId64{
        //.fromStr("FooUpdate5"),
    },
    null,
    KernelTask,
);
var update_task7 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate7",
    &[_]cetech1.StrId64{
        //.fromStr("FooUpdate5"),
    },
    null,
    KernelTask,
);
var update_task8 = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnStore,
    "FooUpdate8",
    &[_]cetech1.StrId64{
        //.fromStr("FooUpdate7"),
    },
    null,
    KernelTask,
);

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    // basic
    _allocator = allocator;
    _log = log_api;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;

    // set module api
    try apidb.setOrRemoveZigApi(module_name, public.FooAPI, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);

    // dont block test with sleeping shit
    if (!_kernel.isTestigMode() and do_tasks) {
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task2, load);
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task3, load);
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task4, load);

        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task5, load);
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task6, load);
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task7, load);
        try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task8, load);
    }

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    if (load) {
        log.info("LOAD", .{});
        return true;
    }

    if (!load) {
        log.info("UNLOAD", .{});
        return true;
    }

    if (reload) {
        log.info("WITH RELOAD", .{});
    }

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_foo(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
