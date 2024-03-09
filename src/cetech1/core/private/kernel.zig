const std = @import("std");
const builtin = @import("builtin");

const profiler = @import("profiler.zig");

const strid = @import("strid.zig");
const log = @import("log.zig");
const apidb = @import("apidb.zig");
const modules = @import("modules.zig");
const task = @import("task.zig");
const cdb = @import("cdb.zig");
const cdb_types = @import("cdb_types.zig");
const tempalloc = @import("tempalloc.zig");
const uuid = @import("uuid.zig");
const assetdb = @import("assetdb.zig");
const system = @import("system.zig");
const gpu = @import("gpu.zig");
const editorui = @import("editorui.zig");

const public = @import("../kernel.zig");

const c = @import("c.zig").c;
const cetech1 = @import("../cetech1.zig");

const UpdateArray = std.ArrayList(*public.KernelTaskUpdateI);
const KernelTaskArray = std.ArrayList(*public.KernelTaskI);
const PhaseMap = std.AutoArrayHashMap(cetech1.strid.StrId64, Phase);

const MODULE_NAME = "kernel";

const Phase = struct {
    const Self = @This();

    name: [:0]const u8,
    update_dag: cetech1.dagraph.StrId64DAG,
    update_chain: UpdateArray,

    pub fn init(allocator: std.mem.Allocator, name: [:0]const u8) Self {
        return .{
            .name = name,
            .update_dag = cetech1.dagraph.StrId64DAG.init(allocator),
            .update_chain = UpdateArray.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.update_dag.deinit();
        self.update_chain.deinit();
    }

    pub fn reset(self: *Self) !void {
        try self.update_dag.reset();
        self.update_chain.clearRetainingCapacity();
    }
};

var _root_allocator: std.mem.Allocator = undefined;
var _kernel_allocator: std.mem.Allocator = undefined;

var _main_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _apidb_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _modules_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _task_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _profiler_profiler_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _cdb_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _assetdb_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _system_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _gpu_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _editorui_allocator: cetech1.profiler.AllocatorProfiler = undefined;
var _tmp_alocator_pool_allocator: cetech1.profiler.AllocatorProfiler = undefined;

var _update_dag: cetech1.dagraph.StrId64DAG = undefined;

var _task_dag: cetech1.dagraph.StrId64DAG = undefined;
var _task_chain: KernelTaskArray = undefined;

var _phase_map: PhaseMap = undefined;
var _phases_dag: cetech1.dagraph.StrId64DAG = undefined;

var _args: [][:0]u8 = undefined;
var _args_map: std.StringArrayHashMap([]const u8) = undefined;

var _tmp_depend_array: std.ArrayList(cetech1.task.TaskID) = undefined;
var _tmp_taskid_map: std.AutoArrayHashMap(cetech1.strid.StrId64, cetech1.task.TaskID) = undefined;

var _iface_map: std.AutoArrayHashMap(cetech1.strid.StrId64, *public.KernelTaskUpdateI) = undefined;

var _running: bool = false;
var _quit: bool = false;

var _main_db: cetech1.cdb.CdbDb = undefined;

var can_quit_handler: ?*const fn () bool = null;

var _max_tick_rate: u32 = 60;
var _restart = true;

var _next_asset_root_buff: [256]u8 = undefined;
var _next_asset_root: ?[]u8 = null;

pub var api = cetech1.kernel.KernelApi{
    .quit = quit,
    .setCanQuit = setCanQuit,
    .getKernelTickRate = getKernelTickRate,
    .setKernelTickRate = setKernelTickRate,
    .restart = restart,
};

fn restart(asset_root: ?[]const u8) void {
    _restart = true;
    if (asset_root != null) {
        _next_asset_root = std.fmt.bufPrint(&_next_asset_root_buff, "{s}", .{asset_root.?}) catch undefined;
    }
}

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

    _apidb_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "apidb");
    _modules_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "modules");
    _task_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "task");
    _cdb_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "cdb");
    _assetdb_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "assetdb");
    _system_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "system");
    _gpu_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "gpu");
    _editorui_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "editorui");
    _tmp_alocator_pool_allocator = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _kernel_allocator, "tmp_allocators");

    _update_dag = cetech1.dagraph.StrId64DAG.init(_kernel_allocator);

    _phases_dag = cetech1.dagraph.StrId64DAG.init(_kernel_allocator);
    _phase_map = PhaseMap.init(_kernel_allocator);

    _task_dag = cetech1.dagraph.StrId64DAG.init(_kernel_allocator);
    _task_chain = KernelTaskArray.init(_kernel_allocator);

    _args_map = std.StringArrayHashMap([]const u8).init(_kernel_allocator);

    _tmp_depend_array = std.ArrayList(cetech1.task.TaskID).init(_kernel_allocator);
    _tmp_taskid_map = std.AutoArrayHashMap(cetech1.strid.StrId64, cetech1.task.TaskID).init(_kernel_allocator);

    _iface_map = std.AutoArrayHashMap(cetech1.strid.StrId64, *public.KernelTaskUpdateI).init(_kernel_allocator);

    try tempalloc.init(_tmp_alocator_pool_allocator.allocator(), 256);
    try apidb.init(_apidb_allocator.allocator());
    try modules.init(_modules_allocator.allocator());
    try task.init(_task_allocator.allocator());
    try cdb.init(_cdb_allocator.allocator());
    try system.init(_system_allocator.allocator());
    try gpu.init(_gpu_allocator.allocator());
    try editorui.init(_editorui_allocator.allocator());

    try apidb.api.setZigApi(cetech1.kernel.KernelApi, &api);

    try log.registerToApi();
    try tempalloc.registerToApi();
    try strid.registerToApi();
    try task.registerToApi();
    try uuid.registerToApi();
    try cdb.registerToApi();
    try cdb_types.registerToApi();
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

pub fn deinit() void {
    shutdownKernelTasks();
    try modules.unloadAll();

    editorui.deinit();
    if (gpu_context) |ctx| gpu.api.destroyContext(ctx);
    if (main_window) |window| system.api.destroyWindow(window);
    gpu.deinit();
    system.deinit();

    assetdb.deinit();
    modules.deinit();

    cdb.api.destroyDb(_main_db);

    task.stop();

    cdb.deinit();
    task.deinit();
    apidb.deinit();
    tempalloc.deinit();

    _iface_map.deinit();
    _tmp_depend_array.deinit();
    _tmp_taskid_map.deinit();

    for (_phase_map.values()) |*value| {
        value.deinit();
    }

    _update_dag.deinit();
    _phases_dag.deinit();
    _phase_map.deinit();
    _task_dag.deinit();
    _task_chain.deinit();
    _args_map.deinit();

    deinitArgs();
    profiler.deinit();
}

fn initProgramArgs() !void {
    _args = try std.process.argsAlloc(_kernel_allocator);

    var args_idx: u32 = 1; // Skip program name
    while (args_idx < _args.len) {
        const name = _args[args_idx];

        if (args_idx + 1 >= _args.len) {
            try _args_map.put(name, "1");
            break;
        }

        const value = _args[args_idx + 1];

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

fn setArgs(arg_name: []const u8, arg_value: []const u8) !void {
    return _args_map.put(arg_name, arg_value);
}

fn getIntArgs(arg_name: []const u8) ?u32 {
    const v = _args_map.get(arg_name) orelse return null;
    return std.fmt.parseInt(u32, v, 10) catch return null;
}

fn getStrArgs(arg_name: []const u8) ?[]const u8 {
    const v = _args_map.get(arg_name) orelse return null;
    return v;
}

pub fn bigInit(static_modules: ?[]const c.ct_module_desc_t, load_dynamic: bool) !void {
    if (static_modules != null) {
        try modules.addModules(static_modules.?);
    }

    if (load_dynamic) {
        modules.loadDynModules() catch |err| {
            log.api.err(MODULE_NAME, "Could not load dynamic modules {}", .{err});
        };
    }

    try modules.loadAll();

    modules.dumpModules();

    try task.start();

    _main_db = try cdb.api.createDb("Main");
    try assetdb.init(_assetdb_allocator.allocator(), &_main_db);

    try generateKernelTaskChain();

    initKernelTasks();

    apidb.dumpApi();
    apidb.dumpInterfaces();
    apidb.dumpGlobalVar();
}

pub fn bigDeinit() !void {
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

pub fn boot(static_modules: ?[*]c.ct_module_desc_t, static_modules_n: u32) !void {
    while (_restart) {
        _restart = false;

        // Main Allocator
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const gpa_allocator = gpa.allocator();
        defer _ = gpa.deinit();

        // Init Kernel
        try init(gpa_allocator);
        defer deinit();

        // Boot ARGS aka. command line args
        const max_kernel_tick = getIntArgs("--max-kernel-tick") orelse 0;
        _max_tick_rate = getIntArgs("--max-kernel-tick-rate") orelse 60;
        const load_dynamic = 1 == getIntArgs("--load-dynamic") orelse 1;
        const asset_root = getStrArgs("--asset-root") orelse "";
        const headless = 1 == getIntArgs("--headless") orelse 0;
        const fullscreen = 1 == getIntArgs("--fullscreen") orelse 0;

        // Init modules
        try bigInit(static_modules.?[0..static_modules_n], load_dynamic);
        defer bigDeinit() catch unreachable;

        var kernel_tick: u64 = 1;
        var last_call = std.time.milliTimestamp();

        // Build phase graph
        try _phases_dag.build_all();

        _running = true;
        _quit = false;

        // Register OS signals
        try registerSignals();

        // If asset root is set open it.
        if (asset_root.len != 0 or _next_asset_root != null) {
            try assetdb.api.openAssetRootFolder(
                if (_next_asset_root) |root| root else asset_root,
                _assetdb_allocator.allocator(),
            );
            try cdb.api.dump(_main_db.db);
            _next_asset_root = null;
        }

        // Create update graph.
        try generateTaskUpdateChain();
        var kernel_task_update_gen = apidb.api.getInterafcesVersion(public.KernelTaskUpdateI);
        var kernel_task_gen = apidb.api.getInterafcesVersion(public.KernelTaskI);

        // Main window
        if (!headless) {
            var w: i32 = 1024;
            var h: i32 = 768;

            const monitor = system.api.getPrimaryMonitor();

            if (fullscreen) {
                const vm = try system.api.getMonitorVideoMode(monitor.?);
                w = vm.width;
                h = vm.height;
            }

            log.api.info(MODULE_NAME, "Using video mode {d}x{d}", .{ w, h });

            main_window = try system.api.createWindow(w, h, "cetech1", if (fullscreen) monitor else null);
            gpu_context = try gpu.api.createContext(main_window.?);
            editorui.api.enableWithWindow(main_window.?, gpu_context.?);
        } else {
            // TODO: True headless
        }

        var checkfs_timer: i64 = 0;

        while (_running and !_quit and !_restart) : (kernel_tick += 1) {
            profiler.api.frameMark();

            var update_zone_ctx = profiler.ztracy.ZoneN(@src(), "kernelUpdate");
            defer update_zone_ctx.End();

            const now = std.time.milliTimestamp();
            const dt = now - last_call;
            last_call = now;

            checkfs_timer += dt;

            // Any dynamic modules changed?
            // TODO: Watch
            if (checkfs_timer >= (5 * std.time.ms_per_s)) {
                checkfs_timer = 0;

                //log.api.debug(MODULE_NAME, "Module change check.", .{});

                const reloaded_modules = try modules.reloadAllIfNeeded();
                if (reloaded_modules) {
                    apidb.dumpGlobalVar();
                }
            }

            if (main_window != null) {
                editorui.api.newFrame();
            }

            system.api.poolEvents();

            // Any public.KernelTaskI iface changed? (add/remove)?
            const new_kernel_gen = apidb.api.getInterafcesVersion(public.KernelTaskI);
            if (new_kernel_gen != kernel_task_gen) {
                try generateKernelTaskChain();
                kernel_task_gen = new_kernel_gen;
            }

            // Any public.KernelTaskUpdateI iface changed? (add/remove)?
            const new_kernel_update_gen = apidb.api.getInterafcesVersion(public.KernelTaskUpdateI);
            if (new_kernel_update_gen != kernel_task_update_gen) {
                try generateTaskUpdateChain();
                kernel_task_update_gen = new_kernel_update_gen;
            }

            // Do hard work.
            try doKernelUpdateTasks(kernel_tick, dt);

            // TODO: Render graph
            if (gpu_context) |ctx| {
                var tmp = try tempalloc.api.createTempArena();
                defer tempalloc.api.destroyTempArena(tmp);

                try editorui.editorUI(tmp.allocator(), @ptrCast(_main_db.db), kernel_tick, @floatFromInt(dt));
                gpu.api.shitTempRender(ctx);
            }

            // Dont drill cpu if there is no hard work.
            try sleepIfNeed(last_call, _max_tick_rate, kernel_tick);

            // clean main DB
            var gc_tmp = try tempalloc.api.createTempArena();
            defer tempalloc.api.destroyTempArena(gc_tmp);
            try _main_db.gc(gc_tmp.allocator());

            // Check window close request
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
        }

        profiler.api.frameMark();
        profiler.api.frameMark();

        if (!_restart) {
            log.api.info(MODULE_NAME, "QUIT", .{});
        } else {
            log.api.info(MODULE_NAME, "RESTART", .{});
        }
    }
}

fn sleepIfNeed(last_call: i64, max_rate: u32, kernel_tick: u64) !void {
    const frame_limit_time: f32 = (1.0 / @as(f32, @floatFromInt(max_rate)) * std.time.ms_per_s);

    const dt: f32 = @floatFromInt(std.time.milliTimestamp() - last_call);
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
            const t = try task.api.schedule(.none, SleepTask{ .sleep_time = sleep_time });
            try wait_tasks.append(t);
        }

        // Sleep but pool events and draw editorui
        const sleep_begin = std.time.milliTimestamp();
        while (true) {
            const sleep_time_s: f32 = @as(f32, @floatFromInt(sleep_time)) / std.time.ns_per_s;
            const sleep_delta: f32 = @as(f32, @floatFromInt(std.time.milliTimestamp() - sleep_begin)) / std.time.ms_per_s;
            if (sleep_delta > sleep_time_s) break;
            system.api.poolEventsWithTimeout(std.math.clamp(sleep_time_s - sleep_delta, 0.0, sleep_time_s));

            if (main_window != null) {
                editorui.api.newFrame();
            }
            if (main_window) |window| {
                if (system.api.windowClosed(window)) {
                    if (can_quit_handler) |can_quit| {
                        _ = can_quit();
                    } else {
                        _quit = true;
                    }
                }
            }
            if (gpu_context) |ctx| {
                try editorui.editorUI(tmp.allocator(), @ptrCast(_main_db.db), kernel_tick, dt);
                gpu.api.shitTempRender(ctx);
            }
        }

        task.api.wait(try task.api.combine(wait_tasks.items));
    }
}

fn addPhase(name: [:0]const u8, depend: []const cetech1.strid.StrId64) !void {
    const name_hash = cetech1.strid.strId64(name);
    const phase = Phase.init(_kernel_allocator, name);
    try _phase_map.put(name_hash, phase);
    try _phases_dag.add(name_hash, depend);
}

fn generateKernelTaskChain() !void {
    try _task_dag.reset();
    _task_chain.clearRetainingCapacity();

    var iface_map = std.AutoArrayHashMap(cetech1.strid.StrId64, *public.KernelTaskI).init(_kernel_allocator);
    defer iface_map.deinit();

    var it = apidb.api.getFirstImpl(public.KernelTaskI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.KernelTaskI, node);

        const depends = if (iface.depends_n != 0) iface.depends[0..iface.depends_n] else &[_]cetech1.strid.StrId64{};

        const name_hash = cetech1.strid.strId64(iface.name[0..std.mem.len(iface.name)]);

        try _task_dag.add(name_hash, depends);
        try iface_map.put(name_hash, iface);
    }

    try _task_dag.build_all();
    for (_task_dag.output.keys()) |module_name| {
        try _task_chain.append(iface_map.get(module_name).?);
    }

    dumpKernelTask();
}

fn generateTaskUpdateChain() !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _update_dag.reset();

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        try phase.reset();
    }

    _iface_map.clearRetainingCapacity();

    var it = apidb.api.getFirstImpl(public.KernelTaskUpdateI);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.KernelTaskUpdateI, node);

        const depends = if (iface.depends_n != 0) iface.depends[0..iface.depends_n] else &[_]cetech1.strid.StrId64{};

        const name_hash = cetech1.strid.strId64(iface.name[0..std.mem.len(iface.name)]);

        var phase = _phase_map.getPtr(iface.phase).?;
        try phase.update_dag.add(name_hash, depends);

        try _iface_map.put(name_hash, iface);
    }

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        try phase.update_dag.build_all();

        for (phase.update_dag.output.keys()) |module_name| {
            try phase.update_chain.append(_iface_map.get(module_name).?);
        }
    }

    try dumpKernelUpdatePhaseTree();
}

const UpdateFrameName = "UpdateFrame";

fn doKernelUpdateTasks(kernel_tick: u64, dt: i64) !void {
    var fce_zone_ctx = profiler.ztracy.Zone(@src());
    defer fce_zone_ctx.End();

    var all_phase_update_task_id = cetech1.task.TaskID.none;
    var last_phase_task_id = cetech1.task.TaskID.none;

    var tmp_alloc = try tempalloc.api.createTempArena();
    defer tempalloc.api.destroyTempArena(tmp_alloc);

    var tmp_allocators = std.ArrayList(*std.heap.ArenaAllocator).init(tmp_alloc.allocator());
    defer tmp_allocators.deinit();

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.get(phase_hash).?;

        if (phase.update_chain.items.len == 0) {
            continue;
        }

        // var phase_zone_ctx = profiler.ztracy.Zone(@src());
        // phase_zone_ctx.Name(phase.name);
        // defer phase_zone_ctx.End();

        for (phase.update_chain.items) |update_handler| {
            const KernelTask = struct {
                update_handler: *public.KernelTaskUpdateI,
                kernel_tick: u64,
                frame_allocator: std.mem.Allocator,
                dt: i64,
                pub fn exec(self: *@This()) void {
                    var zone_ctx = profiler.ztracy.Zone(@src());
                    zone_ctx.Name(self.update_handler.name[0..std.mem.len(self.update_handler.name)]);
                    defer zone_ctx.End();

                    // profiler.FiberEnter(self.update_handler.name);
                    // defer profiler.FiberLeave();
                    self.update_handler.update(&self.frame_allocator, _main_db.db, self.kernel_tick, @floatFromInt(self.dt));
                }
            };

            const task_strid = cetech1.strid.strId64(cetech1.fromCstr(update_handler.name));

            var prereq = cetech1.task.TaskID.none;

            const depeds = phase.update_dag.dependList(task_strid);
            if (depeds != null) {
                _tmp_depend_array.clearRetainingCapacity();

                for (depeds.?) |d| {
                    if (_tmp_taskid_map.get(d)) |task_id| {
                        try _tmp_depend_array.append(task_id);
                    } else {
                        log.api.err(MODULE_NAME, "No task {d}", .{d.id});
                    }
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

        const sync_job = try task.api.combine(_tmp_taskid_map.values());
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
    try dumpKernelUpdatePhaseTreeMD();

    log.api.info(MODULE_NAME, "UPDATE PHASE", .{});
    for (_phases_dag.output.keys(), 0..) |phase_hash, idx| {
        var phase = _phase_map.getPtr(phase_hash).?;
        log.api.info(MODULE_NAME, " +- PHASE: {s}", .{phase.name});

        const last_idx = if (_phases_dag.output.keys().len != 0) _phases_dag.output.keys().len else 0;
        const is_last = (last_idx - 1) == idx;
        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strid.strId64(cetech1.fromCstr(update_fce.name));
            const dep_arr = phase.update_dag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            const tags = if (is_root) "R" else " ";

            var depends_line: ?[]u8 = null;

            if (!is_root) {
                var depends_name = std.ArrayList([]const u8).init(_kernel_allocator);
                defer depends_name.deinit();

                for (dep_arr.?) |dep_id| {
                    const dep_iface = _iface_map.getPtr(dep_id).?;
                    try depends_name.append(cetech1.fromCstr(dep_iface.*.name));
                }

                depends_line = try std.mem.join(_kernel_allocator, ", ", depends_name.items);
            }

            const vert_line = if (!is_last) " " else " ";

            if (depends_line == null) {
                log.api.info(MODULE_NAME, " {s}   +- [{s}] TASK: {s}", .{ vert_line, tags, update_fce.name });
            } else {
                defer _kernel_allocator.free(depends_line.?);
                log.api.info(MODULE_NAME, " {s}   +- [{s}] TASK: {s} [{s}]", .{ vert_line, tags, update_fce.name, depends_line.? });
            }
        }
    }
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
    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        if (prev_phase != null) {
            try writer.print("    {s}-->{s}{{{s}}}\n", .{ prev_phase.?.name, phase.name, phase.name });
        } else {
            try writer.print("    {s}{{{s}}}\n", .{ phase.name, phase.name });
        }

        prev_phase = phase;

        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strid.strId64(cetech1.fromCstr(update_fce.name));
            const dep_arr = phase.update_dag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            const iface = _iface_map.getPtr(task_name_strid).?;
            if (!is_root) {
                for (dep_arr.?) |dep_id| {
                    const dep_iface = _iface_map.getPtr(dep_id).?;
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
        const iface = _task_chain.items[_task_chain.items.len - 1 - idx];
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
    defer deinit();

    try setArgs("--headless", "1");

    var static_modules = [_]c.ct_module_desc_t{.{ .name = "module1", .module_fce = &Module1.load_module }};
    try bigInit(&static_modules, false);
    try bigDeinit();

    try std.testing.expect(Module1.called);
}

// Assert C api == C api in zig.
comptime {
    std.debug.assert(@sizeOf(c.ct_kernel_task_update_i) == @sizeOf(public.KernelTaskUpdateI));
    std.debug.assert(@sizeOf(c.ct_kernel_task_i) == @sizeOf(public.KernelTaskI));
}
