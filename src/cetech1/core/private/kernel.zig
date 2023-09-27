const std = @import("std");
const builtin = @import("builtin");

const profiler = @import("profiler.zig");

const strid = @import("stringid.zig");
const log = @import("log.zig");
const apidb = @import("apidb.zig");
const modules = @import("modules.zig");
const task = @import("task.zig");
const cetech1 = @import("../cetech1.zig");
const c = @import("../c.zig");

const UpdateArray = std.ArrayList(*cetech1.c.ct_kernel_task_update_i);
const KernelTaskArray = std.ArrayList(*cetech1.c.ct_kernel_task_i);
const PhaseMap = std.AutoArrayHashMap(cetech1.StrId64, Phase);

const MODULE_NAME = "kernel";

const Phase = struct {
    const Self = @This();

    name: [:0]const u8,
    update_bag: cetech1.BAG(cetech1.StrId64),
    update_chain: UpdateArray,

    pub fn init(allocator: std.mem.Allocator, name: [:0]const u8) Self {
        return .{
            .name = name,
            .update_bag = cetech1.BAG(cetech1.StrId64).init(allocator),
            .update_chain = UpdateArray.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.update_bag.deinit();
        self.update_chain.deinit();
    }

    pub fn reset(self: *Self) !void {
        try self.update_bag.reset();
        try self.update_chain.resize(0);
    }
};

var _root_allocator: std.mem.Allocator = undefined;
var _kernel_allocator: std.mem.Allocator = undefined;
var _main_profiler_allocator: cetech1.AllocatorProfiler = undefined;
var _apidb_profiler_allocator: cetech1.AllocatorProfiler = undefined;
var _modules_profiler_allocator: cetech1.AllocatorProfiler = undefined;
var _task_profiler_allocator: cetech1.AllocatorProfiler = undefined;
var _profiler_profiler_allocator: cetech1.AllocatorProfiler = undefined;

var _update_bag: cetech1.BAG(cetech1.StrId64) = undefined;

var _task_bag: cetech1.BAG(cetech1.StrId64) = undefined;
var _task_chain: KernelTaskArray = undefined;

var _phase_map: PhaseMap = undefined;
var _phases_bag: cetech1.BAG(cetech1.StrId64) = undefined;

var _args: [][:0]u8 = undefined;
var _args_map: std.StringArrayHashMap([]const u8) = undefined;

var _tmp_depend_array: std.ArrayList(cetech1.TaskID) = undefined;
var _tmp_taskid_map: std.AutoArrayHashMap(cetech1.StrId64, cetech1.TaskID) = undefined;

var _iface_map: std.AutoArrayHashMap(cetech1.StrId64, *c.c.ct_kernel_task_update_i) = undefined;

var _running: bool = false;
var _quit: bool = false;

pub fn init(allocator: std.mem.Allocator) !void {
    _root_allocator = allocator;
    _main_profiler_allocator = cetech1.AllocatorProfiler.init(&profiler.api, allocator, null);
    _kernel_allocator = _main_profiler_allocator.allocator();

    _profiler_profiler_allocator = cetech1.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "profiler");
    profiler.init(_profiler_profiler_allocator.allocator());

    _apidb_profiler_allocator = cetech1.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "apidb");
    _modules_profiler_allocator = cetech1.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "modules");
    _task_profiler_allocator = cetech1.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "task");

    _update_bag = cetech1.BAG(cetech1.StrId64).init(_kernel_allocator);

    _phases_bag = cetech1.BAG(cetech1.StrId64).init(_kernel_allocator);
    _phase_map = PhaseMap.init(_kernel_allocator);

    _task_bag = cetech1.BAG(cetech1.StrId64).init(_kernel_allocator);
    _task_chain = KernelTaskArray.init(_kernel_allocator);

    _args_map = std.StringArrayHashMap([]const u8).init(_kernel_allocator);

    _tmp_depend_array = std.ArrayList(cetech1.TaskID).init(_kernel_allocator);
    _tmp_taskid_map = std.AutoArrayHashMap(cetech1.StrId64, cetech1.TaskID).init(_kernel_allocator);

    _iface_map = std.AutoArrayHashMap(cetech1.StrId64, *c.c.ct_kernel_task_update_i).init(_kernel_allocator);

    try apidb.init(_apidb_profiler_allocator.allocator());
    try modules.init(_modules_profiler_allocator.allocator());
    try task.init(_task_profiler_allocator.allocator());

    try log.registerToApi();
    try strid.registerToApi();
    try task.registerToApi();

    try initProgramArgs();

    try addPhase(cetech1.c.CT_KERNEL_PHASE_ONLOAD, &[_]cetech1.StrId64{});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_POSTLOAD, &[_]cetech1.StrId64{cetech1.OnLoad});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_PREUPDATE, &[_]cetech1.StrId64{cetech1.PostLoad});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_ONUPDATE, &[_]cetech1.StrId64{cetech1.PreUpdate});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_ONVALIDATE, &[_]cetech1.StrId64{cetech1.OnUpdate});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_POSTUPDATE, &[_]cetech1.StrId64{cetech1.OnValidate});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_PRESTORE, &[_]cetech1.StrId64{cetech1.PostUpdate});
    try addPhase(cetech1.c.CT_KERNEL_PHASE_ONSTORE, &[_]cetech1.StrId64{cetech1.PreStore});
}

pub fn deinit() void {
    task.deinit();
    modules.deinit();
    apidb.deinit();

    _iface_map.deinit();
    _tmp_depend_array.deinit();
    _tmp_taskid_map.deinit();

    _update_bag.deinit();
    _phases_bag.deinit();
    _phase_map.deinit();
    _task_bag.deinit();
    _task_chain.deinit();
    _args_map.deinit();

    deinitArgs();
    profiler.deinit();
}

fn initProgramArgs() !void {
    _args = try std.process.argsAlloc(_kernel_allocator);

    var args_idx: u32 = 1; // Skip program name
    while (args_idx < _args.len) {
        var name = _args[args_idx];

        if (args_idx + 1 >= _args.len) {
            log.api.err(MODULE_NAME, "Invalid commandline args. Last is {s}", .{name});
            break;
        }

        var value = _args[args_idx + 1];
        try _args_map.put(name, value);

        args_idx += 2;
    }
}

fn deinitArgs() void {
    std.process.argsFree(_kernel_allocator, _args);
}

fn getIntArgs(arg_name: []const u8, default: u32) !u32 {
    var v = _args_map.get(arg_name);
    if (v == null) {
        return default;
    }
    return try std.fmt.parseInt(u32, v.?, 10);
}

pub fn bigInit(static_modules: ?[]const c.c.ct_module_desc_t, load_dynamic: bool) !void {
    if (static_modules != null) {
        try modules.addModules(static_modules.?);
    }

    if (load_dynamic) {
        try modules.loadDynModules();
    }

    try modules.loadAll();

    modules.dumpModules();

    try generateKernelTaskChain();

    initKernelTasks();

    apidb.dumpApi();
    apidb.dumpInterfaces();
    apidb.dumpGlobalVar();

    try task.start();
}

pub fn bitDeinit() !void {
    task.stop();

    shutdownKernelTasks();

    try modules.unloadAll();
    profiler.api.frameMark();
}

pub fn quit() void {
    _quit = true;
}

fn sigQuitHandler(signum: c_int) align(1) callconv(.C) void {
    _ = signum;
    quit();
}

fn registerSignals() !void {
    if (builtin.os.tag != .windows) {
        var sigaction = std.os.Sigaction{
            .handler = .{ .handler = sigQuitHandler },
            .mask = std.os.empty_sigset,
            .flags = 0,
        };
        try std.os.sigaction(std.os.SIG.TERM, &sigaction, null);
        try std.os.sigaction(std.os.SIG.INT, &sigaction, null);
    }
}

pub fn boot(static_modules: ?[*]c.c.ct_module_desc_t, static_modules_n: u32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    try init(allocator);

    const max_kernel_tick = try getIntArgs("--max-kernel-tick", 0);
    const load_dynamic = try getIntArgs("--load-dynamic", 1) == 1;

    try bigInit(static_modules.?[0..static_modules_n], load_dynamic);
    defer bitDeinit() catch unreachable;

    var kernel_tick: u64 = 1;
    var last_call = std.time.milliTimestamp();

    try _phases_bag.build(cetech1.OnLoad);

    try generateTaskUpdateChain();
    var kernel_task_update_gen = apidb.api.getInterafceGen(c.c.ct_kernel_task_update_i);

    _running = true;
    _quit = false;

    try registerSignals();

    while (_running and !_quit) : (kernel_tick += 1) {
        profiler.api.frameMark();

        var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "kernelUpdate");
        defer update_zone_ctx.End();

        log.api.debug(MODULE_NAME, "", .{});
        log.api.debug(MODULE_NAME, "TICK BEGIN", .{});
        var now = std.time.milliTimestamp();
        var dt = now - last_call;
        last_call = now;

        // Any dynamic modules changed?
        const reloaded_modules = try modules.reloadAllIfNeeded();
        if (reloaded_modules) {
            apidb.dumpGlobalVar();
        }

        // Any ct_kernel_task_update_i iface changed? (add/remove)?
        var new_kernel_update_gen = apidb.api.getInterafceGen(c.c.ct_kernel_task_update_i);
        if (new_kernel_update_gen != kernel_task_update_gen) {
            try generateTaskUpdateChain();
            kernel_task_update_gen = new_kernel_update_gen;
        }

        // Do hard work.
        try updateKernelTasks(kernel_tick, dt);

        log.api.debug(MODULE_NAME, "TICK END", .{});
        log.api.debug(MODULE_NAME, "", .{});

        // If set max-kernel-tick and reach limit then quit
        if (max_kernel_tick > 0) _quit = kernel_tick >= max_kernel_tick;

        //std.time.sleep(std.time.ns_per_s * 1);
    }
    log.api.info(MODULE_NAME, "QUIT", .{});
}

fn addPhase(name: [:0]const u8, depend: []const cetech1.StrId64) !void {
    const name_hash = cetech1.strId64(name);
    var phase = Phase.init(_kernel_allocator, name);
    try _phase_map.put(name_hash, phase);
    try _phases_bag.add(name_hash, depend);
}

fn generateKernelTaskChain() !void {
    try _task_bag.reset();
    try _task_chain.resize(0);

    var iface_map = std.AutoArrayHashMap(cetech1.StrId64, *c.c.ct_kernel_task_i).init(_kernel_allocator);
    defer iface_map.deinit();

    var it = apidb.api.getFirstImpl(c.c.ct_kernel_task_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.ApiDbAPI.toInterface(c.c.ct_kernel_task_i, node);
        var depends = if (iface.depends_n != 0) iface.depends[0..iface.depends_n] else &[_]cetech1.StrId64{};

        const name_hash = cetech1.strId64(iface.name[0..std.mem.len(iface.name)]);

        try _task_bag.add(name_hash, depends);
        try iface_map.put(name_hash, iface);
    }

    try _task_bag.build_all();
    for (_task_bag.output.items) |module_name| {
        try _task_chain.append(iface_map.get(module_name).?);
    }

    dumpKernelTask();
}

fn generateTaskUpdateChain() !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _update_bag.reset();

    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        try phase.reset();
    }

    _iface_map.clearRetainingCapacity();

    var it = apidb.api.getFirstImpl(c.c.ct_kernel_task_update_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.ApiDbAPI.toInterface(c.c.ct_kernel_task_update_i, node);
        var depends = if (iface.depends_n != 0) iface.depends[0..iface.depends_n] else &[_]cetech1.StrId64{};

        const name_hash = cetech1.strId64(iface.name[0..std.mem.len(iface.name)]);

        var phase = _phase_map.getPtr(iface.phase).?;
        try phase.update_bag.add(name_hash, depends);

        try _iface_map.put(name_hash, iface);
    }

    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        try phase.update_bag.build_all();

        for (phase.update_bag.output.items) |module_name| {
            try phase.update_chain.append(_iface_map.get(module_name).?);
        }
    }

    try dumpKernelUpdatePhaseTree();
}

const UpdateFrameName = "UpdateFrame";

fn updateKernelTasks(kernel_tick: u64, dt: i64) !void {
    var fce_zone_ctx = profiler.ztracy.Zone(@src());
    defer fce_zone_ctx.End();

    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.get(phase_hash).?;

        if (phase.update_chain.items.len == 0) {
            continue;
        }

        var phase_zone_ctx = profiler.ztracy.Zone(@src());
        phase_zone_ctx.Name(phase.name);
        defer phase_zone_ctx.End();

        for (phase.update_chain.items) |update_handler| {
            const KernelTask = struct {
                update_handler: cetech1.c.ct_kernel_task_update_i,
                kernel_tick: u64,
                dt: i64,
                pub fn exec(self: *@This()) void {
                    var zone_ctx = profiler.ztracy.Zone(@src());
                    zone_ctx.Name(self.update_handler.name[0..std.mem.len(self.update_handler.name)]);
                    defer zone_ctx.End();

                    // profiler.FiberEnter(self.update_handler.name);
                    // defer profiler.FiberLeave();
                    self.update_handler.update.?(self.kernel_tick, @floatFromInt(self.dt));
                }
            };

            const task_strid = cetech1.strId64(c.fromCstr(update_handler.name));

            var prereq = cetech1.TaskID.none;

            var depeds = phase.update_bag.dependList(task_strid);
            if (depeds != null) {
                try _tmp_depend_array.resize(0);

                for (depeds.?) |d| {
                    try _tmp_depend_array.append(_tmp_taskid_map.get(d).?);
                }

                prereq = try task.api.combine(_tmp_depend_array.items);
            } else {}

            const job_id = try task.api.schedule(
                prereq,
                KernelTask{
                    .update_handler = update_handler.*,
                    .kernel_tick = kernel_tick,
                    .dt = dt,
                },
            );
            try _tmp_taskid_map.put(task_strid, job_id);
        }

        var sync_job = try task.api.combine(_tmp_taskid_map.values());
        task.api.wait(sync_job);
    }

    try _tmp_depend_array.resize(0);
    _tmp_taskid_map.clearRetainingCapacity();
}

fn dumpKernelUpdatePhaseTree() !void {
    log.api.debug(MODULE_NAME, "UPDATE PHASE", .{});
    for (_phases_bag.output.items, 0..) |phase_hash, idx| {
        var phase = _phase_map.getPtr(phase_hash).?;
        log.api.debug(MODULE_NAME, " +- PHASE: {s}", .{phase.name});

        const last_idx = if (_phases_bag.output.items.len != 0) _phases_bag.output.items.len else 0;
        const is_last = (last_idx - 1) == idx;
        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strId64(c.fromCstr(update_fce.name));
            const dep_arr = phase.update_bag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            const tags = if (is_root) "R" else " ";

            var depends_line: ?[]u8 = null;

            if (!is_root) {
                var depends_name = std.ArrayList([]const u8).init(_kernel_allocator);
                defer depends_name.deinit();

                for (dep_arr.?) |dep_id| {
                    var dep_iface = _iface_map.getPtr(dep_id).?;
                    try depends_name.append(c.fromCstr(dep_iface.*.name));
                }

                depends_line = try std.mem.join(_kernel_allocator, ", ", depends_name.items);
            }

            const vert_line = if (!is_last) " " else " ";
            //const vert_line = if (!is_last) "|" else " ";

            if (depends_line == null) {
                log.api.debug(MODULE_NAME, " {s}   +- [{s}] TASK: {s}", .{ vert_line, tags, update_fce.name });
            } else {
                defer _kernel_allocator.free(depends_line.?);
                log.api.debug(MODULE_NAME, " {s}   +- [{s}] TASK: {s} [{s}]", .{ vert_line, tags, update_fce.name, depends_line.? });
            }
        }
    }
}

fn initKernelTasks() void {
    for (_task_chain.items) |iface| {
        iface.init.?();
    }
}

fn dumpKernelTask() void {
    log.api.debug(MODULE_NAME, "TASKS", .{});
    for (_task_chain.items) |t| {
        log.api.debug(MODULE_NAME, " +- {s}", .{t.name});
    }
}

fn shutdownKernelTasks() void {
    for (0.._task_chain.items.len) |idx| {
        var iface = _task_chain.items[_task_chain.items.len - 1 - idx];
        iface.shutdown.?();
    }
}

pub export fn cetech1_kernel_boot(static_modules: ?[*]c.c.ct_module_desc_t, static_modules_n: u32) u8 {
    boot(static_modules, static_modules_n) catch |err| {
        log.api.err(MODULE_NAME, "Boot error: {}", .{err});
        return 1;
    };
    return 0;
}

test "Can create kernel" {
    const allocator = std.testing.allocator;

    const Module1 = struct {
        var called: bool = false;
        fn load_module(_apidb: ?*const c.c.ct_apidb_api_t, _allocator: ?*const c.c.ct_allocator_t, load: u8, reload: u8) callconv(.C) u8 {
            _ = _apidb;
            _ = reload;
            _ = load;
            _ = _allocator;
            called = true;
            return 1;
        }
    };

    try init(allocator);
    defer deinit();

    var static_modules = [_]c.c.ct_module_desc_t{.{ .name = "module1", .module_fce = &Module1.load_module }};
    try bigInit(&static_modules, false);
    try bitDeinit();

    try std.testing.expect(Module1.called);
}
