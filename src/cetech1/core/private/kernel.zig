const std = @import("std");
const builtin = @import("builtin");

const profiler = @import("profiler.zig");

const strid = @import("strid.zig");
const log = @import("log.zig");
const apidb = @import("apidb.zig");
const modules = @import("modules.zig");
const task = @import("task.zig");
const cdb = @import("cdb.zig");
const tempalloc = @import("tempalloc.zig");
const uuid = @import("uuid.zig");
const assetdb = @import("assetdb.zig");
const system = @import("system.zig");
const gpu = @import("gpu.zig");
const editorui = @import("editorui.zig");

const c = @import("../c.zig").c;
const cetech1 = @import("../cetech1.zig");

const UpdateArray = std.ArrayList(*c.ct_kernel_task_update_i);
const KernelTaskArray = std.ArrayList(*c.ct_kernel_task_i);
const PhaseMap = std.AutoArrayHashMap(cetech1.strid.StrId64, Phase);

const MODULE_NAME = "kernel";

const Phase = struct {
    const Self = @This();

    name: [:0]const u8,
    update_bag: cetech1.bagraph.StrId64BAG,
    update_chain: UpdateArray,

    pub fn init(allocator: std.mem.Allocator, name: [:0]const u8) Self {
        return .{
            .name = name,
            .update_bag = cetech1.bagraph.StrId64BAG.init(allocator),
            .update_chain = UpdateArray.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.update_bag.deinit();
        self.update_chain.deinit();
    }

    pub fn reset(self: *Self) !void {
        try self.update_bag.reset();
        self.update_chain.clearRetainingCapacity();
    }
};

var _root_allocator: std.mem.Allocator = undefined;
var _kernel_allocator: std.mem.Allocator = undefined;

var _main_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _apidb_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _modules_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _task_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _profiler_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _cdb_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _asset_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _system_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _gpu_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _editorui_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _tmp_alocator_pool_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;

var _update_bag: cetech1.bagraph.StrId64BAG = undefined;

var _task_bag: cetech1.bagraph.StrId64BAG = undefined;
var _task_chain: KernelTaskArray = undefined;

var _phase_map: PhaseMap = undefined;
var _phases_bag: cetech1.bagraph.StrId64BAG = undefined;

var _args: [][:0]u8 = undefined;
var _args_map: std.StringArrayHashMap([]const u8) = undefined;

var _tmp_depend_array: std.ArrayList(cetech1.task.TaskID) = undefined;
var _tmp_taskid_map: std.AutoArrayHashMap(cetech1.strid.StrId64, cetech1.task.TaskID) = undefined;

var _iface_map: std.AutoArrayHashMap(cetech1.strid.StrId64, *c.ct_kernel_task_update_i) = undefined;

var _running: bool = false;
var _quit: bool = false;

var _main_db: cetech1.cdb.CdbDb = undefined;

var can_quit_handler: ?*const fn () bool = null;

var _max_tick_rate: u32 = 60;

pub var api = cetech1.kernel.KernelApi{
    .quit = quit,
    .setCanQuit = setCanQuit,
    .getKernelTickRate = getKernelTickRate,
    .setKernelTickRate = setKernelTickRate,
};

fn getKernelTickRate() u32 {
    return _max_tick_rate;
}

fn setKernelTickRate(rate: u32) void {
    _max_tick_rate = if (rate != 0) rate else 60;
}

fn setCanQuit(can_quit: *const fn () bool) void {
    can_quit_handler = can_quit;
}

pub fn init(allocator: std.mem.Allocator) !void {
    _root_allocator = allocator;
    _main_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, allocator, null);
    _kernel_allocator = _main_profiler_allocator.allocator();

    _profiler_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "profiler");
    profiler.init(_profiler_profiler_allocator.allocator());

    _apidb_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "apidb");
    _modules_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "modules");
    _task_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "task");
    _cdb_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "cdb");
    _asset_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "asset");
    _system_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "window");
    _gpu_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "gpu");
    _editorui_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "editorui");
    _tmp_alocator_pool_profiler_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "tmp_allocators");

    _update_bag = cetech1.bagraph.StrId64BAG.init(_kernel_allocator);

    _phases_bag = cetech1.bagraph.StrId64BAG.init(_kernel_allocator);
    _phase_map = PhaseMap.init(_kernel_allocator);

    _task_bag = cetech1.bagraph.StrId64BAG.init(_kernel_allocator);
    _task_chain = KernelTaskArray.init(_kernel_allocator);

    _args_map = std.StringArrayHashMap([]const u8).init(_kernel_allocator);

    _tmp_depend_array = std.ArrayList(cetech1.task.TaskID).init(_kernel_allocator);
    _tmp_taskid_map = std.AutoArrayHashMap(cetech1.strid.StrId64, cetech1.task.TaskID).init(_kernel_allocator);

    _iface_map = std.AutoArrayHashMap(cetech1.strid.StrId64, *c.ct_kernel_task_update_i).init(_kernel_allocator);

    try tempalloc.init(_tmp_alocator_pool_profiler_allocator.allocator(), 256);
    try apidb.init(_apidb_profiler_allocator.allocator());
    try modules.init(_modules_profiler_allocator.allocator());
    try task.init(_task_profiler_allocator.allocator());
    try cdb.init(_cdb_profiler_allocator.allocator());
    try system.init(_system_profiler_allocator.allocator());
    try gpu.init(_gpu_profiler_allocator.allocator());
    try editorui.init(_editorui_profiler_allocator.allocator());

    try apidb.api.setZigApi(cetech1.kernel.KernelApi, &api);

    try log.registerToApi();
    try tempalloc.registerToApi();
    try strid.registerToApi();
    try task.registerToApi();
    try uuid.registerToApi();
    try cdb.registerToApi();
    try assetdb.registerToApi();
    try system.registerToApi();
    try gpu.registerToApi();
    try editorui.registerToApi();

    try initProgramArgs();

    try addPhase(c.CT_KERNEL_PHASE_ONLOAD, &[_]cetech1.strid.StrId64{});
    try addPhase(c.CT_KERNEL_PHASE_POSTLOAD, &[_]cetech1.strid.StrId64{cetech1.kernel.OnLoad});
    try addPhase(c.CT_KERNEL_PHASE_PREUPDATE, &[_]cetech1.strid.StrId64{cetech1.kernel.PostLoad});
    try addPhase(c.CT_KERNEL_PHASE_ONUPDATE, &[_]cetech1.strid.StrId64{cetech1.kernel.PreUpdate});
    try addPhase(c.CT_KERNEL_PHASE_ONVALIDATE, &[_]cetech1.strid.StrId64{cetech1.kernel.OnUpdate});
    try addPhase(c.CT_KERNEL_PHASE_POSTUPDATE, &[_]cetech1.strid.StrId64{cetech1.kernel.OnValidate});
    try addPhase(c.CT_KERNEL_PHASE_PRESTORE, &[_]cetech1.strid.StrId64{cetech1.kernel.PostUpdate});
    try addPhase(c.CT_KERNEL_PHASE_ONSTORE, &[_]cetech1.strid.StrId64{cetech1.kernel.PreStore});
}

pub fn deinit() !void {
    editorui.deinit();

    if (gpu_context) |ctx| gpu.api.destroyContext(ctx);
    if (main_window) |window| system.api.destroyWindow(window);
    gpu.deinit();
    system.deinit();
    assetdb.deinit();

    modules.deinit();

    cdb.api.destroyDb(_main_db);

    cdb.deinit();
    task.deinit();
    apidb.deinit();
    tempalloc.deinit();

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
    _ = gpa.deinit();
}

fn initProgramArgs() !void {
    _args = try std.process.argsAlloc(_kernel_allocator);

    var args_idx: u32 = 1; // Skip program name
    while (args_idx < _args.len) {
        var name = _args[args_idx];

        if (args_idx + 1 >= _args.len) {
            try _args_map.put(name, "1");
            // log.api.err(MODULE_NAME, "Invalid commandline args. Last is {s}", .{name});
            break;
        }

        var value = _args[args_idx + 1];

        if (std.mem.startsWith(u8, value, "-")) {
            args_idx += 1;
            try _args_map.put(name, "1");
        } else {
            args_idx += 2;
            try _args_map.put(name, value);
        }
    }
}

fn deinitArgs() void {
    std.process.argsFree(_kernel_allocator, _args);
}

fn getIntArgs(arg_name: []const u8) ?u32 {
    var v = _args_map.get(arg_name) orelse return null;
    return std.fmt.parseInt(u32, v, 10) catch return null;
}

fn getStrArgs(arg_name: []const u8) ?[]const u8 {
    var v = _args_map.get(arg_name) orelse return null;
    return v;
}

pub fn bigInit(static_modules: ?[]const c.ct_module_desc_t, load_dynamic: bool) !void {
    if (static_modules != null) {
        try modules.addModules(static_modules.?);
    }

    if (load_dynamic) {
        try modules.loadDynModules();
    }

    try modules.loadAll();

    modules.dumpModules();

    try task.start();

    _main_db = try cdb.api.createDb("Main");

    try assetdb.init(_asset_profiler_allocator.allocator(), &_main_db);

    try generateKernelTaskChain();

    initKernelTasks();

    apidb.dumpApi();
    apidb.dumpInterfaces();
    apidb.dumpGlobalVar();
}

pub fn bigDeinit() !void {
    shutdownKernelTasks();

    try modules.unloadAll();
    task.stop();
    profiler.api.frameMark();
}

pub fn quit() void {
    _quit = true;
}

fn sigQuitHandler(signum: c_int) callconv(.C) void {
    _ = signum;
    if (can_quit_handler) |can_quit| {
        _ = can_quit();
        return;
    }

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

var main_window: ?*cetech1.system.Window = null;
var gpu_context: ?*cetech1.gpu.GpuContext = null;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gpa_allocator = gpa.allocator();

pub fn boot(static_modules: ?[*]c.ct_module_desc_t, static_modules_n: u32) !void {
    try init(gpa_allocator);

    // Boot ARGS aka. command line args
    const max_kernel_tick = getIntArgs("--max-kernel-tick") orelse 0;
    _max_tick_rate = getIntArgs("--max-kernel-tick-rate") orelse 60;
    const load_dynamic = 1 == getIntArgs("--load-dynamic") orelse 1;
    const asset_root = getStrArgs("--asset-root") orelse "";
    const headless = 1 == getIntArgs("--headless") orelse 0;

    try bigInit(static_modules.?[0..static_modules_n], load_dynamic);
    defer bigDeinit() catch unreachable;

    var kernel_tick: u64 = 1;
    var last_call = std.time.milliTimestamp();

    try _phases_bag.build_all();

    _running = true;
    _quit = false;

    try registerSignals();

    if (asset_root.len != 0) {
        try assetdb.api.openAssetRootFolder(asset_root, _asset_profiler_allocator.allocator());
    }

    try generateTaskUpdateChain();
    var kernel_task_update_gen = apidb.api.getInterafcesVersion(c.ct_kernel_task_update_i);

    // Main window
    if (!headless) {
        main_window = try system.api.createWindow(1024, 768, "cetech1", null);
        gpu_context = try gpu.api.createContext(main_window.?);
        editorui.api.enableWithWindow(main_window.?, gpu_context.?);
    } else {
        // TODO: True headless
    }

    while (_running and !_quit) : (kernel_tick += 1) {
        profiler.api.frameMark();

        var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "kernelUpdate");
        defer update_zone_ctx.End();

        // log.api.debug(MODULE_NAME, "TICK BEGIN", .{});

        var now = std.time.milliTimestamp();
        var dt = now - last_call;

        last_call = now;

        system.api.poolEvents();
        if (main_window != null) {
            editorui.api.newFrame();
        }

        // Do hard work.
        try updateKernelTasks(kernel_tick, dt);

        // Any dynamic modules changed?
        const reloaded_modules = try modules.reloadAllIfNeeded();
        if (reloaded_modules) {
            apidb.dumpGlobalVar();
        }

        // Any ct_kernel_task_update_i iface changed? (add/remove)?
        var new_kernel_update_gen = apidb.api.getInterafcesVersion(c.ct_kernel_task_update_i);
        if (new_kernel_update_gen != kernel_task_update_gen) {
            try generateTaskUpdateChain();
            kernel_task_update_gen = new_kernel_update_gen;
        }

        // TODO: Render graph
        if (gpu_context) |ctx| {
            var tmp = try tempalloc.api.createTempArena();
            defer tempalloc.api.destroyTempArena(tmp);

            try editorui.editorUI(tmp.allocator(), @ptrCast(_main_db.db), kernel_tick, @floatFromInt(dt));
            gpu.api.shitTempRender(ctx);
        }

        // clean main DB
        var gc_tmp = try tempalloc.api.createTempArena();
        defer tempalloc.api.destroyTempArena(gc_tmp);
        try _main_db.gc(gc_tmp.allocator());

        // log.api.debug(MODULE_NAME, "TICK END", .{});

        if (main_window) |window| {
            if (system.api.windowClosed(window)) {
                if (can_quit_handler) |can_quit| {
                    _ = can_quit();
                } else {
                    _quit = true;
                }
            }
        }

        // If set max-kernel-tick and reach limit then quit
        if (max_kernel_tick > 0) _quit = kernel_tick >= max_kernel_tick;

        // Dont drill cpu if there is no hard work.
        try sleepIfNeed(last_call, _max_tick_rate);
    }
    log.api.info(MODULE_NAME, "QUIT", .{});
}

fn sleepIfNeed(last_call: i64, max_rate: u32) !void {
    const frame_limit_time: f32 = (1.0 / @as(f32, @floatFromInt(max_rate)) * std.time.ms_per_s);

    var dt: f32 = @floatFromInt(std.time.milliTimestamp() - last_call);
    if (dt < frame_limit_time) {
        var zone_ctx = profiler.ztracy.ZoneN(@src(), "ShityFrameLimitSleeper");
        defer zone_ctx.End();
        const sleep_time: u64 = @intFromFloat((frame_limit_time - dt) * 0.65 * std.time.ns_per_ms);

        var tmp = try tempalloc.api.createTempArena();
        defer tempalloc.api.destroyTempArena(tmp);

        const n = task.api.getThreadNum();
        var wait_tasks = std.ArrayList(cetech1.task.TaskID).init(tmp.allocator());
        defer wait_tasks.deinit();
        for (0..n) |_| {
            const SleepTask = struct {
                sleep_time: u64,
                pub fn exec(self: *@This()) void {
                    var task_zone_ctx = profiler.ztracy.ZoneN(@src(), "ShityFrameLimitSleeper");
                    defer task_zone_ctx.End();
                    std.time.sleep(self.sleep_time);
                }
            };
            var t = try task.api.schedule(.none, SleepTask{ .sleep_time = sleep_time });
            try wait_tasks.append(t);
        }
        std.time.sleep(sleep_time);
        task.api.wait(try task.api.combine(wait_tasks.items));
    }
}

fn addPhase(name: [:0]const u8, depend: []const cetech1.strid.StrId64) !void {
    const name_hash = cetech1.strid.strId64(name);
    var phase = Phase.init(_kernel_allocator, name);
    try _phase_map.put(name_hash, phase);
    try _phases_bag.add(name_hash, depend);
}

fn generateKernelTaskChain() !void {
    try _task_bag.reset();
    _task_chain.clearRetainingCapacity();

    var iface_map = std.AutoArrayHashMap(cetech1.strid.StrId64, *c.ct_kernel_task_i).init(_kernel_allocator);
    defer iface_map.deinit();

    var it = apidb.api.getFirstImpl(c.ct_kernel_task_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(c.ct_kernel_task_i, node);

        var depends = if (iface.depends_n != 0) cetech1.strid.StrId64.fromCArray(c.ct_strid64_t, iface.depends, iface.depends_n) else &[_]cetech1.strid.StrId64{};

        const name_hash = cetech1.strid.strId64(iface.name[0..std.mem.len(iface.name)]);

        try _task_bag.add(name_hash, depends);
        try iface_map.put(name_hash, iface);
    }

    try _task_bag.build_all();
    for (_task_bag.output.keys()) |module_name| {
        try _task_chain.append(iface_map.get(module_name).?);
    }

    dumpKernelTask();
}

fn generateTaskUpdateChain() !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _update_bag.reset();

    for (_phases_bag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        try phase.reset();
    }

    _iface_map.clearRetainingCapacity();

    var it = apidb.api.getFirstImpl(c.ct_kernel_task_update_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(c.ct_kernel_task_update_i, node);

        var depends = if (iface.depends_n != 0) cetech1.strid.StrId64.fromCArray(c.ct_strid64_t, iface.depends, iface.depends_n) else &[_]cetech1.strid.StrId64{};

        const name_hash = cetech1.strid.strId64(iface.name[0..std.mem.len(iface.name)]);

        var phase = _phase_map.getPtr(cetech1.strid.StrId64.from(c.ct_strid64_t, iface.phase)).?;
        try phase.update_bag.add(name_hash, depends);

        try _iface_map.put(name_hash, iface);
    }

    for (_phases_bag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        try phase.update_bag.build_all();

        for (phase.update_bag.output.keys()) |module_name| {
            try phase.update_chain.append(_iface_map.get(module_name).?);
        }
    }

    try dumpKernelUpdatePhaseTree();
}

const UpdateFrameName = "UpdateFrame";

fn updateKernelTasks(kernel_tick: u64, dt: i64) !void {
    var fce_zone_ctx = profiler.ztracy.Zone(@src());
    defer fce_zone_ctx.End();

    var all_phase_update_task_id = cetech1.task.TaskID.none;
    var last_phase_task_id = cetech1.task.TaskID.none;

    var tmp_alloc = try tempalloc.api.createTempArena();
    defer tempalloc.api.destroyTempArena(tmp_alloc);

    var tmp_allocators = std.ArrayList(*std.heap.ArenaAllocator).init(tmp_alloc.allocator());
    defer tmp_allocators.deinit();

    for (_phases_bag.output.keys()) |phase_hash| {
        var phase = _phase_map.get(phase_hash).?;

        if (phase.update_chain.items.len == 0) {
            continue;
        }

        // var phase_zone_ctx = profiler.ztracy.Zone(@src());
        // phase_zone_ctx.Name(phase.name);
        // defer phase_zone_ctx.End();

        for (phase.update_chain.items) |update_handler| {
            //update_handler.update.?(_main_db.db, kernel_tick, @floatFromInt(dt));

            const KernelTask = struct {
                update_handler: *c.ct_kernel_task_update_i,
                kernel_tick: u64,
                frame_allocator: std.mem.Allocator,
                dt: i64,
                pub fn exec(self: *@This()) void {
                    var zone_ctx = profiler.ztracy.Zone(@src());
                    zone_ctx.Name(self.update_handler.name[0..std.mem.len(self.update_handler.name)]);
                    defer zone_ctx.End();

                    // profiler.FiberEnter(self.update_handler.name);
                    // defer profiler.FiberLeave();
                    self.update_handler.update.?(@ptrCast(&self.frame_allocator), @ptrCast(_main_db.db), self.kernel_tick, @floatFromInt(self.dt));
                }
            };

            const task_strid = cetech1.strid.strId64(cetech1.fromCstr(update_handler.name));

            var prereq = cetech1.task.TaskID.none;

            var depeds = phase.update_bag.dependList(task_strid);
            if (depeds != null) {
                _tmp_depend_array.clearRetainingCapacity();

                for (depeds.?) |d| {
                    try _tmp_depend_array.append(_tmp_taskid_map.get(d).?);
                }

                prereq = try task.api.combine(_tmp_depend_array.items);
            } else {
                prereq = last_phase_task_id;
            }

            var task_alloc = try tempalloc.api.createTempArena();

            try tmp_allocators.append(task_alloc);

            const job_id = try task.api.schedule(
                prereq,
                KernelTask{
                    .update_handler = update_handler,
                    .kernel_tick = kernel_tick,
                    .frame_allocator = task_alloc.allocator(),
                    .dt = dt,
                },
            );
            try _tmp_taskid_map.put(task_strid, job_id);
        }

        var sync_job = try task.api.combine(_tmp_taskid_map.values());
        last_phase_task_id = sync_job;

        if (all_phase_update_task_id != cetech1.task.TaskID.none) {
            all_phase_update_task_id = sync_job;
        } else {
            all_phase_update_task_id = try task.api.combine(&[_]cetech1.task.TaskID{ all_phase_update_task_id, sync_job });
        }
    }

    task.api.wait(all_phase_update_task_id);

    for (tmp_allocators.items) |aloc| {
        tempalloc.api.destroyTempArena(aloc);
    }

    _tmp_depend_array.clearRetainingCapacity();
    _tmp_taskid_map.clearRetainingCapacity();
}

fn dumpKernelUpdatePhaseTree() !void {
    try dumpKernelUpdatePhaseTreeDOT();
    try dumpKernelUpdatePhaseTreeMD();

    log.api.info(MODULE_NAME, "UPDATE PHASE", .{});
    for (_phases_bag.output.keys(), 0..) |phase_hash, idx| {
        var phase = _phase_map.getPtr(phase_hash).?;
        log.api.info(MODULE_NAME, " +- PHASE: {s}", .{phase.name});

        const last_idx = if (_phases_bag.output.keys().len != 0) _phases_bag.output.keys().len else 0;
        const is_last = (last_idx - 1) == idx;
        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strid.strId64(cetech1.fromCstr(update_fce.name));
            const dep_arr = phase.update_bag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            const tags = if (is_root) "R" else " ";

            var depends_line: ?[]u8 = null;

            if (!is_root) {
                var depends_name = std.ArrayList([]const u8).init(_kernel_allocator);
                defer depends_name.deinit();

                for (dep_arr.?) |dep_id| {
                    var dep_iface = _iface_map.getPtr(dep_id).?;
                    try depends_name.append(cetech1.fromCstr(dep_iface.*.name));
                }

                depends_line = try std.mem.join(_kernel_allocator, ", ", depends_name.items);
            }

            const vert_line = if (!is_last) " " else " ";
            //const vert_line = if (!is_last) "|" else " ";

            if (depends_line == null) {
                log.api.info(MODULE_NAME, " {s}   +- [{s}] TASK: {s}", .{ vert_line, tags, update_fce.name });
            } else {
                defer _kernel_allocator.free(depends_line.?);
                log.api.info(MODULE_NAME, " {s}   +- [{s}] TASK: {s} [{s}]", .{ vert_line, tags, update_fce.name, depends_line.? });
            }
        }
    }
}

fn dumpKernelUpdatePhaseTreeDOT() !void {
    var path_buff: [1024]u8 = undefined;
    var file_path_buff: [1024]u8 = undefined;
    // only if asset root is set.
    var path = try assetdb.api.getTmpPath(&path_buff);
    if (path == null) return;
    path = try std.fmt.bufPrint(&file_path_buff, "{s}/" ++ "kernel_task_graph.dot", .{path.?});

    var dot_file = try std.fs.createFileAbsolute(path.?, .{});
    defer dot_file.close();

    // write header
    var writer = dot_file.writer();
    try writer.print("digraph kernel_task_graph {{\n", .{});

    // write nodes
    try writer.print("    node [shape = box;];\n", .{});

    var prev_phase: ?*Phase = null;

    for (_phases_bag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        try writer.print("    \"{s}\" [shape = diamond];\n", .{phase.name});

        if (prev_phase != null) {
            try writer.print("    \"{s}\" -> \"{s}\";\n", .{ prev_phase.?.name, phase.name });
        } else {
            try writer.print("    \"{s}\";\n", .{phase.name});
        }

        prev_phase = phase;

        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strid.strId64(cetech1.fromCstr(update_fce.name));
            const dep_arr = phase.update_bag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            var iface = _iface_map.getPtr(task_name_strid).?;
            if (!is_root) {
                for (dep_arr.?) |dep_id| {
                    var dep_iface = _iface_map.getPtr(dep_id).?;
                    try writer.print("    \"{s}\" -> \"{s}\";\n", .{ dep_iface.*.name, iface.*.name });
                }
            } else {
                try writer.print("    \"{s}\" -> \"{s}\";\n", .{ phase.name, iface.*.name });
            }
        }
    }

    // write footer
    try writer.print("}}\n", .{});
}

fn dumpKernelUpdatePhaseTreeMD() !void {
    var path_buff: [1024]u8 = undefined;
    var file_path_buff: [1024]u8 = undefined;
    // only if asset root is set.
    var path = try assetdb.api.getTmpPath(&path_buff);
    if (path == null) return;
    path = try std.fmt.bufPrint(&file_path_buff, "{s}/" ++ "kernel_task_graph.md", .{path.?});

    var dot_file = try std.fs.createFileAbsolute(path.?, .{});
    defer dot_file.close();

    var writer = dot_file.writer();
    try writer.print("# Kernel task graph\n\n", .{});

    try writer.print("```mermaid\n", .{});
    try writer.print("flowchart TB\n", .{});

    // write nodes

    var prev_phase: ?*Phase = null;
    for (_phases_bag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        if (prev_phase != null) {
            try writer.print("    {s}-->{s}{{{s}}}\n", .{ prev_phase.?.name, phase.name, phase.name });
        } else {
            try writer.print("    {s}{{{s}}}\n", .{ phase.name, phase.name });
        }

        prev_phase = phase;

        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strid.strId64(cetech1.fromCstr(update_fce.name));
            const dep_arr = phase.update_bag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            var iface = _iface_map.getPtr(task_name_strid).?;
            if (!is_root) {
                for (dep_arr.?) |dep_id| {
                    var dep_iface = _iface_map.getPtr(dep_id).?;
                    try writer.print("    {s}-->{s}\n", .{ dep_iface.*.name, iface.*.name });
                }
            } else {
                try writer.print("    {s}-->{s}\n", .{ phase.name, iface.*.name });
            }
        }
    }

    // write footer
    try writer.print("```\n", .{});
}

fn initKernelTasks() void {
    for (_task_chain.items) |iface| {
        iface.init.?(@ptrCast(_main_db.db));
    }
}

fn dumpKernelTask() void {
    log.api.info(MODULE_NAME, "TASKS", .{});
    for (_task_chain.items) |t| {
        log.api.info(MODULE_NAME, " +- {s}", .{t.name});
    }
}

fn shutdownKernelTasks() void {
    for (0.._task_chain.items.len) |idx| {
        var iface = _task_chain.items[_task_chain.items.len - 1 - idx];
        if (iface.shutdown) |shutdown| {
            shutdown();
        } else {
            log.api.err(MODULE_NAME, "Kernel task {s} has empty shutdown.", .{iface.name});
        }
    }
}

pub export fn cetech1_kernel_boot(static_modules: ?[*]c.ct_module_desc_t, static_modules_n: u32) u8 {
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
        fn load_module(_apidb: ?*const c.ct_apidb_api_t, _allocator: ?*const c.ct_allocator_t, load: u8, reload: u8) callconv(.C) u8 {
            _ = _apidb;
            _ = reload;
            _ = load;
            _ = _allocator;
            called = true;
            return 1;
        }
    };

    try init(allocator);
    defer deinit() catch undefined;

    var static_modules = [_]c.ct_module_desc_t{.{ .name = "module1", .module_fce = &Module1.load_module }};
    try bigInit(&static_modules, false);
    try bigDeinit();

    try std.testing.expect(Module1.called);
}
