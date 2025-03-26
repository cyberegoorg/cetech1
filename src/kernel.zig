const std = @import("std");
const builtin = @import("builtin");

const profiler_private = @import("profiler.zig");
const strid_private = @import("strid.zig");
const log_api = @import("log.zig");
const apidb = @import("apidb.zig");
const modules = @import("modules.zig");
const task = @import("task.zig");
const cdb_private = @import("cdb.zig");
const cdb_types = @import("cdb_types.zig");
const tempalloc = @import("tempalloc.zig");
const uuid = @import("uuid.zig");
const assetdb = @import("assetdb.zig");
const platform = @import("platform.zig");
const gpu = @import("gpu.zig");
const coreui = @import("coreui.zig");
const ecs = @import("ecs.zig");
const actions = @import("actions.zig");

const metrics = @import("metrics.zig");

const cetech1 = @import("cetech1");
const public = cetech1.kernel;
const profiler = cetech1.profiler;
const strid = cetech1.strid;
const cdb = cetech1.cdb;

const cetech1_options = @import("cetech1_options");

const externals_credits = @embedFile("externals_credit");
const authors = @embedFile("authors");

var _cdb = &cdb_private.api;

const module_name = .kernel;

const log = std.log.scoped(module_name);

const UpdateArray = cetech1.ArrayList(*const public.KernelTaskUpdateI);
const KernelTaskArray = cetech1.ArrayList(*const public.KernelTaskI);
const PhaseMap = cetech1.AutoArrayHashMap(cetech1.StrId64, Phase);

const BootArgs = struct {
    max_kernel_tick: u32 = 0,
    headless: bool = false,
    load_dynamic: bool = true,
};

const Phase = struct {
    const Self = @This();

    name: [:0]const u8,
    update_dag: cetech1.dag.StrId64DAG,
    update_chain: UpdateArray = .{},

    pub fn init(allocator: std.mem.Allocator, name: [:0]const u8) Self {
        return .{
            .name = name,
            .update_dag = cetech1.dag.StrId64DAG.init(allocator),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.update_dag.deinit();
        self.update_chain.deinit(allocator);
    }

    pub fn reset(self: *Self) !void {
        try self.update_dag.reset();
        self.update_chain.clearRetainingCapacity();
    }
};

var _root_allocator: std.mem.Allocator = undefined;
var _kernel_allocator: std.mem.Allocator = undefined;

var _main_profiler_allocator: profiler.AllocatorProfiler = undefined;
var _apidb_allocator: profiler.AllocatorProfiler = undefined;
var _modules_allocator: profiler.AllocatorProfiler = undefined;
var _task_allocator: profiler.AllocatorProfiler = undefined;
var _profiler_profiler_allocator: profiler.AllocatorProfiler = undefined;
var _cdb_allocator: profiler.AllocatorProfiler = undefined;
var _assetdb_allocator: profiler.AllocatorProfiler = undefined;
var _platform_allocator: profiler.AllocatorProfiler = undefined;
var _gpu_allocator: profiler.AllocatorProfiler = undefined;
var _coreui_allocator: profiler.AllocatorProfiler = undefined;
var _tmp_alocator_pool_allocator: profiler.AllocatorProfiler = undefined;
var _ecs_allocator: profiler.AllocatorProfiler = undefined;
var _actions_allocator: profiler.AllocatorProfiler = undefined;
var _metrics_allocator: profiler.AllocatorProfiler = undefined;

var _update_dag: cetech1.dag.StrId64DAG = undefined;

var _task_dag: cetech1.dag.StrId64DAG = undefined;
var _task_chain: KernelTaskArray = undefined;

var _phase_map: PhaseMap = undefined;
var _phases_dag: cetech1.dag.StrId64DAG = undefined;

var _args: [][:0]u8 = undefined;
var _args_map: std.StringArrayHashMapUnmanaged([]const u8) = undefined;

var _tmp_depend_array: cetech1.task.TaskIdList = undefined;
var _tmp_taskid_map: cetech1.AutoArrayHashMap(cetech1.StrId64, cetech1.task.TaskID) = undefined;

var _iface_map: cetech1.AutoArrayHashMap(cetech1.StrId64, *const public.KernelTaskUpdateI) = undefined;

var _running: bool = false;
var _quit: bool = false;

var can_quit_handler: ?*const fn () bool = null;

var _max_tick_rate: u32 = 60;
var _restart = true;

var _next_asset_root_buff: [256]u8 = undefined;
var _next_asset_root: ?[]u8 = null;
var main_window: ?cetech1.platform.Window = null;
var gpu_context: ?*cetech1.gpu.GpuContext = null;

pub var api = cetech1.kernel.KernelApi{
    .quit = quit,
    .setCanQuit = setCanQuit,
    .getKernelTickRate = getKernelTickRate,
    .setKernelTickRate = setKernelTickRate,
    .openAssetRoot = openAssetRoot,
    .restart = restart,
    .getDb = getDb,
    .isTestigMode = isTestigMode,
    .isHeadlessMode = isHeadlessMode,
    .getMainWindow = getMainWindow,
    .getGpuCtx = getGpuCtx,
    .getExternalsCredit = getExternalsCredit,
    .getAuthors = getAuthors,
};

fn getExternalsCredit() [:0]const u8 {
    return externals_credits;
}

fn getAuthors() [:0]const u8 {
    return authors;
}

fn getMainWindow() ?cetech1.platform.Window {
    return main_window;
}
fn getGpuCtx() ?*cetech1.gpu.GpuContext {
    return gpu_context;
}

fn isTestigMode() bool {
    return 1 == getIntArgs("--test-ui") orelse 0;
}

fn isHeadlessMode() bool {
    return _headless;
}

fn restart() void {
    _restart = true;
}

fn getDb() cdb.DbId {
    return assetdb.getDb();
}

fn openAssetRoot(asset_root: ?[]const u8) void {
    //_restart = true;
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

pub fn init(allocator: std.mem.Allocator, headless: bool) !void {
    _root_allocator = allocator;
    _main_profiler_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, allocator, null);
    _kernel_allocator = _main_profiler_allocator.allocator();

    _profiler_profiler_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "profiler");
    profiler_private.init(_profiler_profiler_allocator.allocator());

    _apidb_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "apidb");
    _modules_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "modules");
    _task_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "task");
    _cdb_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "cdb");
    _assetdb_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "assetdb");
    _platform_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "platform");
    _gpu_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "gpu");
    _coreui_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "coreui");
    _tmp_alocator_pool_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "tmp_allocators");
    _ecs_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "ecs");
    _actions_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "actions");

    _metrics_allocator = profiler.AllocatorProfiler.init(&profiler_private.api, _kernel_allocator, "metrics");

    _update_dag = cetech1.dag.StrId64DAG.init(_kernel_allocator);

    _phases_dag = cetech1.dag.StrId64DAG.init(_kernel_allocator);
    _phase_map = .{};

    _task_dag = cetech1.dag.StrId64DAG.init(_kernel_allocator);
    _task_chain = .{};

    _tmp_depend_array = .{};
    _tmp_taskid_map = .{};

    _iface_map = .{};

    try tempalloc.init(_tmp_alocator_pool_allocator.allocator(), 256);

    try apidb.init(_apidb_allocator.allocator());
    try modules.init(_modules_allocator.allocator());
    try metrics.init(_metrics_allocator.allocator());
    try task.init(_task_allocator.allocator());
    try cdb_private.init(_cdb_allocator.allocator());
    try platform.init(_platform_allocator.allocator(), headless);
    try actions.init(_actions_allocator.allocator());
    try gpu.init(_gpu_allocator.allocator());
    try coreui.init(_coreui_allocator.allocator());

    try apidb.api.setZigApi(module_name, cetech1.kernel.KernelApi, &api);

    try log_api.registerToApi();
    try tempalloc.registerToApi();
    try strid_private.registerToApi();
    try profiler_private.registerToApi();
    try task.registerToApi();
    try uuid.registerToApi();
    try cdb_private.registerToApi();
    try cdb_types.registerToApi();
    try assetdb.registerToApi();
    try platform.registerToApi();
    try actions.registerToApi();
    try gpu.registerToApi();
    try coreui.registerToApi();
    try ecs.registerToApi();
    try metrics.registerToApi();

    try addPhase("OnLoad", &[_]cetech1.StrId64{});
    try addPhase("PostLoad", &[_]cetech1.StrId64{cetech1.kernel.OnLoad});
    try addPhase("PreUpdate", &[_]cetech1.StrId64{cetech1.kernel.PostLoad});
    try addPhase("OnUpdate", &[_]cetech1.StrId64{cetech1.kernel.PreUpdate});
    try addPhase("OnValidate", &[_]cetech1.StrId64{cetech1.kernel.OnUpdate});
    try addPhase("PostUpdate", &[_]cetech1.StrId64{cetech1.kernel.OnValidate});
    try addPhase("PreStore", &[_]cetech1.StrId64{cetech1.kernel.PostUpdate});
    try addPhase("OnStore", &[_]cetech1.StrId64{cetech1.kernel.PreStore});

    log.info("version: {}", .{cetech1_options.version});
}

pub fn deinit(
    allocator: std.mem.Allocator,
) !void {
    try shutdownKernelTasks();
    try modules.unloadAll();

    ecs.deinit();

    coreui.deinit();
    //renderer.deinit();
    if (gpu_context) |ctx| gpu.api.destroyContext(ctx);
    gpu.deinit();
    if (main_window) |window| platform.api.destroyWindow(window);

    actions.deinit();
    platform.deinit();

    assetdb.deinit();
    modules.deinit();

    task.stop();

    cdb_private.deinit();
    task.deinit();
    metrics.deinit();
    apidb.deinit();
    tempalloc.deinit();

    _iface_map.deinit(_kernel_allocator);
    _tmp_depend_array.deinit(_kernel_allocator);
    _tmp_taskid_map.deinit(_kernel_allocator);

    for (_phase_map.values()) |*value| {
        value.deinit(_kernel_allocator);
    }

    _update_dag.deinit();
    _phases_dag.deinit();
    _phase_map.deinit(_kernel_allocator);
    _task_dag.deinit();
    _task_chain.deinit(_kernel_allocator);

    deinitArgs(allocator);
    profiler_private.deinit();
}

fn initProgramArgs(allocator: std.mem.Allocator) !void {
    _args = try std.process.argsAlloc(allocator);
    _args_map = .{};

    var args_idx: u32 = 1; // Skip program name
    while (args_idx < _args.len) {
        const name = _args[args_idx];

        if (args_idx + 1 >= _args.len) {
            try _args_map.put(allocator, name, "1");
            break;
        }

        const value = _args[args_idx + 1];

        if (std.mem.startsWith(u8, value, "-")) {
            args_idx += 1;
            try _args_map.put(allocator, name, "1");
        } else {
            args_idx += 2;
            try _args_map.put(allocator, name, value);
        }
    }
}

fn deinitArgs(allocator: std.mem.Allocator) void {
    std.process.argsFree(allocator, _args);
    _args_map.deinit(allocator);
}

fn setArgs(arg_name: []const u8, arg_value: []const u8) !void {
    return _args_map.put(arg_name, arg_value);
}

pub fn getIntArgs(arg_name: []const u8) ?u32 {
    const v = _args_map.get(arg_name) orelse return null;
    return std.fmt.parseInt(u32, v, 10) catch return null;
}

pub fn getStrArgs(arg_name: []const u8) ?[]const u8 {
    const v = _args_map.get(arg_name) orelse return null;
    return v;
}

pub fn bigInit(static_modules: []const cetech1.modules.ModuleDesc, load_dynamic: bool) !void {
    if (static_modules.len != 0) {
        try modules.addModules(static_modules);
    }

    if (load_dynamic) {
        modules.loadDynModules() catch |err| {
            log.err("Could not load dynamic modules {}", .{err});
        };
    }

    try modules.loadAll();

    modules.dumpModules();

    try task.start();

    try ecs.init(_ecs_allocator.allocator());

    try assetdb.init(_assetdb_allocator.allocator());

    try generateKernelTaskChain(_kernel_allocator);

    apidb.dumpApi();
    apidb.dumpGlobalVar();
}

pub fn bigDeinit() !void {
    profiler_private.api.frameMark();
}

pub fn quit() void {
    _quit = true;
}
var _can_quit_one = false;

fn sigQuitHandler(signum: c_int) callconv(.C) void {
    _ = signum;

    if (!_can_quit_one) {
        if (can_quit_handler) |can_quit| {
            _can_quit_one = true;
            _ = can_quit();
            return;
        }
    }

    quit();
}

fn registerSignals() !void {
    if (builtin.os.tag != .windows) {
        var sigaction = std.posix.Sigaction{
            .handler = .{ .handler = sigQuitHandler },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.TERM, &sigaction, null);
        std.posix.sigaction(std.posix.SIG.INT, &sigaction, null);
    }
}

var _headless = false;

pub fn boot(static_modules: []const cetech1.modules.ModuleDesc, boot_args: BootArgs) !void {
    while (_restart) {
        _restart = false;

        // Main Allocator
        var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
        const gpa_allocator, const is_debug = gpa: {
            if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
            break :gpa switch (builtin.mode) {
                .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true }, //TODO: FAIL on ReleaseSafe in 0.14.0
                .ReleaseFast, .ReleaseSmall => .{ debug_allocator.allocator(), true },
                // .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false }, //TODO: FAIL in 0.14.0
            };
        };
        defer if (is_debug) {
            _ = debug_allocator.deinit();
        };

        try initProgramArgs(gpa_allocator);

        // Boot ARGS aka. command line args
        const max_kernel_tick = getIntArgs("--max-kernel-tick") orelse boot_args.max_kernel_tick;
        _max_tick_rate = getIntArgs("--max-kernel-tick-rate") orelse 60;
        const load_dynamic = 1 == getIntArgs("--load-dynamic") orelse @intFromBool(boot_args.load_dynamic);
        const asset_root = getStrArgs("--asset-root") orelse "";
        _headless = 1 == getIntArgs("--headless") orelse @intFromBool(boot_args.headless);
        const fullscreen = 1 == getIntArgs("--fullscreen") orelse 0;
        const renderer_type = getStrArgs("--renderer");

        // Init Kernel
        try init(gpa_allocator, _headless);
        defer deinit(gpa_allocator) catch undefined;

        // Test args
        const test_ui = 1 == getIntArgs("--test-ui") orelse 0;
        const test_ui_speed_value = getStrArgs("--test-ui-speed") orelse "fast";
        const fast_mode = std.mem.eql(u8, test_ui_speed_value, "fast");

        // Init modules
        try bigInit(static_modules, load_dynamic);
        defer bigDeinit() catch unreachable;

        var kernel_tick: u64 = 1;
        var tick_last_call = std.time.milliTimestamp();

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
            _next_asset_root = null;
        }

        try _cdb.dump(assetdb.getDb());

        var buf: [256]u8 = undefined;
        if (try assetdb.getTmpPath(&buf)) |path| {
            const apidb_graph_md = try std.fs.path.join(_kernel_allocator, &.{ path, "apidb_graph.d2" });
            defer _kernel_allocator.free(apidb_graph_md);
            try apidb.writeApiGraphD2(apidb_graph_md);
        }

        // Create update graph.
        try generateTaskUpdateChain(_kernel_allocator);
        var kernel_task_update_gen = apidb.api.getInterafcesVersion(public.KernelTaskUpdateI);
        var kernel_task_gen: cetech1.apidb.InterfaceVersion = 0;

        // Main window
        if (!_headless) {
            var w: i32 = 1024;
            var h: i32 = 768;

            const monitor = platform.api.getPrimaryMonitor();

            if (fullscreen) {
                const vm = try monitor.?.getVideoMode();
                w = vm.width;
                h = vm.height;
            }

            log.info("Using video mode {d}x{d}", .{ w, h });

            main_window = try platform.api.createWindow(
                w,
                h,
                cetech1_options.app_name ++ " - powered by CETech1",
                if (fullscreen) monitor else null,
            );
        }

        gpu_context = try gpu.api.createContext(
            main_window,
            if (renderer_type) |r| cetech1.gpu.Backend.fromString(r) else null,
            !_headless,
            _headless,
        );

        try initKernelTasks();

        var checkfs_timer: i64 = 0;
        const dt_couter = try metrics.api.getCounter("kernel/dt");
        const tick_duration_counter = try metrics.api.getCounter("kernel/tick_duration");

        var last_game_tick_task: cetech1.task.TaskID = .none;
        var game_tick_last_call = std.time.milliTimestamp();

        var game_tick: usize = 0;

        profiler_private.api.frameMark();
        while (_running and !_quit and !_restart) : (kernel_tick +%= 1) {
            var update_zone_ctx = profiler_private.ztracy.ZoneN(@src(), "kernelUpdate");
            defer update_zone_ctx.End();

            //const tick_duration = cetech1.metrics.MetricScopedDuration.begin(tick_duration_counter);
            const tick_duration = cetech1.metrics.MetricScopedDuration.begin(tick_duration_counter);
            defer tick_duration.end();

            const now = std.time.milliTimestamp();
            const kernel_dt_ms = now - tick_last_call;
            tick_last_call = now;

            dt_couter.* = @floatFromInt(kernel_dt_ms);

            checkfs_timer += kernel_dt_ms;

            const tmp_frame_alloc = try tempalloc.api.create();
            defer tempalloc.api.destroy(tmp_frame_alloc);

            // Any dynamic modules changed?
            // TODO: Watch
            if (checkfs_timer >= (10 * std.time.ms_per_s)) {
                checkfs_timer = 0;

                const reloaded_modules = try modules.reloadAllIfNeeded(tmp_frame_alloc);
                if (reloaded_modules) {}
            }

            platform.api.poolEvents();

            // Any public.KernelTaskI iface changed? (add/remove)?
            const new_kernel_gen = apidb.api.getInterafcesVersion(public.KernelTaskI);
            if (new_kernel_gen != kernel_task_gen) {
                try generateKernelTaskChain(tmp_frame_alloc);
                kernel_task_gen = new_kernel_gen;
            }

            // Any public.KernelTaskUpdateI iface changed? (add/remove)?
            const new_kernel_update_gen = apidb.api.getInterafcesVersion(public.KernelTaskUpdateI);
            if (new_kernel_update_gen != kernel_task_update_gen) {
                try generateTaskUpdateChain(tmp_frame_alloc);
                kernel_task_update_gen = new_kernel_update_gen;
            }

            const GameTickTask = struct {
                kernel_tick: u64,
                dt_s: f32,
                fast_mode: bool,

                pub fn exec(self: *@This()) !void {
                    profiler_private.api.frameMark();

                    var task_zone_ctx = profiler_private.ztracy.ZoneN(@src(), "GameTick");
                    defer task_zone_ctx.End();

                    const noww = std.time.milliTimestamp();

                    const allocator = try tempalloc.api.create();
                    defer tempalloc.api.destroy(allocator);

                    // TODO: stange delta, unshit this shit
                    actions.checkInputs();

                    // Do hard work.
                    try doKernelUpdateTasks(self.kernel_tick, self.dt_s);

                    // clean main DB
                    try _cdb.gc(allocator, assetdb.getDb());

                    try metrics.pushFrames();

                    if (!(isTestigMode() and self.fast_mode)) {
                        const t = try sleepIfNeed(allocator, noww, _max_tick_rate, task.api.getThreadNum() - 1);
                        task.api.wait(t);
                    }
                }
            };

            if (task.api.isDone(last_game_tick_task)) {
                const noww = std.time.milliTimestamp();
                const game_dt_ms = noww - game_tick_last_call;
                const game_dt_s: f32 = @as(f32, @floatFromInt(game_dt_ms)) / std.time.ms_per_s;
                game_tick_last_call = noww;

                const t = try task.api.schedule(
                    .none,
                    GameTickTask{
                        .dt_s = game_dt_s,
                        .kernel_tick = kernel_tick,
                        .fast_mode = fast_mode,
                    },
                    .{},
                );
                last_game_tick_task = t;
                // task.api.wait(t);
                game_tick +%= 1;
            } else {
                task.api.doOneTask();
            }

            if (_next_asset_root != null) {
                try assetdb.api.openAssetRootFolder(
                    if (_next_asset_root) |root| root else asset_root,
                    _assetdb_allocator.allocator(),
                );
                _next_asset_root = null;
            }

            // Check window close request
            if (main_window) |window| {
                if (window.shouldClose()) {
                    if (can_quit_handler) |can_quit| {
                        _ = can_quit();
                    } else {
                        _quit = true;
                    }
                }
            }

            // If set max-kernel-tick and reach limit then quit
            if (max_kernel_tick > 0) _quit = kernel_tick >= max_kernel_tick;

            if (test_ui and game_tick > 1) {
                const impls = try apidb.api.getImpl(tmp_frame_alloc, public.KernelTestingI);
                defer tmp_frame_alloc.free(impls);

                for (impls) |iface| {
                    _quit = !try iface.isRunning();
                }
            }

            {
                var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "renderFrame");
                defer zone_ctx.End();
                _ = gpu.api.renderFrame(0);
            }
        }

        task.api.wait(last_game_tick_task);

        if (test_ui) {
            const impls = try apidb.api.getImpl(_kernel_allocator, public.KernelTestingI);
            defer _kernel_allocator.free(impls);

            for (impls) |iface| {
                iface.printResult();

                const result = iface.getResult();

                if (result.count_success != result.count_tested) {
                    @panic("Why are you break my app?");
                }
            }
        }

        profiler_private.api.frameMark();
        profiler_private.api.frameMark();

        if (!_restart) {
            log.info("Do quit", .{});
        } else {
            log.info("Do restart", .{});
        }
    }
}

fn sleepIfNeed(allocator: std.mem.Allocator, last_call: i64, max_rate: u32, worker_n: u64) !cetech1.task.TaskID {
    const frame_limit_time: f32 = (1.0 / @as(f32, @floatFromInt(max_rate)) * std.time.ms_per_s);

    const dt: f32 = @floatFromInt(std.time.milliTimestamp() - last_call);
    if (dt < frame_limit_time) {
        // var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "ShityFrameLimitSleeper");
        // defer zone_ctx.End();
        const sleep_time: u64 = @intFromFloat((frame_limit_time - dt) * 0.62 * std.time.ns_per_ms);

        const n = worker_n;
        var wait_tasks = try cetech1.task.TaskIdList.initCapacity(allocator, n);
        defer wait_tasks.deinit(allocator);

        for (0..n) |idx| {
            const SleepTask = struct {
                sleep_time: u64,
                pub fn exec(self: *@This()) !void {
                    var task_zone_ctx = profiler_private.ztracy.ZoneN(@src(), "ShityFrameLimitSleeper");
                    defer task_zone_ctx.End();
                    std.time.sleep(self.sleep_time);
                }
            };
            const t = try task.api.schedule(
                .none,
                SleepTask{ .sleep_time = sleep_time },
                .{ .affinity = @intCast(idx + 1) },
            );
            wait_tasks.appendAssumeCapacity(t);
        }

        // // Sleep but pool events and draw coreui
        // const sleep_begin = std.time.milliTimestamp();
        // while (true) {
        //     const sleep_time_s: f32 = @as(f32, @floatFromInt(sleep_time)) / std.time.ns_per_s;
        //     const sleep_delta_s: f32 = @as(f32, @floatFromInt(std.time.milliTimestamp() - sleep_begin)) / std.time.ms_per_s;
        //     if (sleep_delta_s > sleep_time_s) break;
        //     platform.api.poolEventsWithTimeout(std.math.clamp(sleep_time_s - sleep_delta_s, 0.0, sleep_time_s));

        //     if (main_window) |window| {
        //         if (window.shouldClose()) {
        //             if (can_quit_handler) |can_quit| {
        //                 _ = can_quit();
        //             } else {
        //                 _quit = true;
        //             }
        //         }
        //     }
        // }

        return task.api.combine(wait_tasks.items);
    }

    return .none;
}

fn addPhase(name: [:0]const u8, depend: []const cetech1.StrId64) !void {
    const name_hash = cetech1.strId64(name);
    const phase = Phase.init(_kernel_allocator, name);
    try _phase_map.put(_kernel_allocator, name_hash, phase);
    try _phases_dag.add(name_hash, depend);
}

fn generateKernelTaskChain(alloctor: std.mem.Allocator) !void {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "generateKernelTaskChain");
    defer zone_ctx.End();

    try _task_dag.reset();
    _task_chain.clearRetainingCapacity();

    var iface_map = cetech1.AutoArrayHashMap(cetech1.StrId64, *const public.KernelTaskI){};
    defer iface_map.deinit(_kernel_allocator);

    const impls = try apidb.api.getImpl(alloctor, public.KernelTaskI);
    defer alloctor.free(impls);

    for (impls) |iface| {
        const depends = iface.depends;

        const name_hash = cetech1.strId64(iface.name);

        try _task_dag.add(name_hash, depends);
        try iface_map.put(_kernel_allocator, name_hash, iface);
    }

    try _task_dag.build_all();
    for (_task_dag.output.keys()) |name| {
        try _task_chain.append(_kernel_allocator, iface_map.get(name).?);
    }

    dumpKernelTask();
}

fn generateTaskUpdateChain(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler_private.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _update_dag.reset();

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        try phase.reset();
    }

    _iface_map.clearRetainingCapacity();

    const impls = try apidb.api.getImpl(allocator, public.KernelTaskUpdateI);
    defer allocator.free(impls);

    for (impls) |iface| {
        const depends = iface.depends;

        const name_hash = cetech1.strId64(iface.name);

        var phase = _phase_map.getPtr(iface.phase).?;
        try phase.update_dag.add(name_hash, depends);

        try _iface_map.put(_kernel_allocator, name_hash, iface);
    }

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        try phase.update_dag.build_all();

        for (phase.update_dag.output.keys()) |name| {
            try phase.update_chain.append(_kernel_allocator, _iface_map.get(name).?);
        }
    }

    try dumpKernelUpdatePhaseTree();
}

const UpdateFrameName = "UpdateFrame";

fn doKernelUpdateTasks(kernel_tick: u64, dt: f32) !void {
    var fce_zone_ctx = profiler_private.ztracy.Zone(@src());
    defer fce_zone_ctx.End();

    var all_phase_update_task_id = cetech1.task.TaskID.none;
    var last_phase_task_id = cetech1.task.TaskID.none;

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.get(phase_hash).?;

        if (phase.update_chain.items.len == 0) {
            continue;
        }

        for (phase.update_chain.items) |update_handler| {
            const KernelTask = struct {
                update_handler: *const public.KernelTaskUpdateI,
                kernel_tick: u64,
                dt: f32,
                pub fn exec(self: *@This()) !void {
                    var zone_ctx = profiler_private.ztracy.Zone(@src());
                    zone_ctx.Name(self.update_handler.name);
                    defer zone_ctx.End();

                    try self.update_handler.update(self.kernel_tick, self.dt);
                }
            };

            const task_strid = cetech1.strId64(update_handler.name);

            var prereq = cetech1.task.TaskID.none;

            const depeds = phase.update_dag.dependList(task_strid);
            if (depeds != null) {
                _tmp_depend_array.clearRetainingCapacity();

                for (depeds.?) |d| {
                    if (_tmp_taskid_map.get(d)) |task_id| {
                        try _tmp_depend_array.append(_kernel_allocator, task_id);
                    } else {
                        log.err("No task {d}", .{d.id});
                    }
                }

                prereq = try task.api.combine(_tmp_depend_array.items);
            } else {
                prereq = last_phase_task_id;
            }

            const job_id = try task.api.schedule(
                prereq,
                KernelTask{
                    .update_handler = update_handler,
                    .kernel_tick = kernel_tick,
                    .dt = dt,
                },
                .{ .affinity = update_handler.affinity },
            );
            try _tmp_taskid_map.put(_kernel_allocator, task_strid, job_id);
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

    _tmp_depend_array.clearRetainingCapacity();
    _tmp_taskid_map.clearRetainingCapacity();
}

fn dumpKernelUpdatePhaseTree() !void {
    try dumpKernelUpdatePhaseTreeD2();

    log.info("Kernel update phase:", .{});
    for (_phases_dag.output.keys(), 0..) |phase_hash, idx| {
        var phase = _phase_map.getPtr(phase_hash).?;
        log.info("\t- {s}", .{phase.name});

        const last_idx = if (_phases_dag.output.keys().len != 0) _phases_dag.output.keys().len else 0;
        const is_last = (last_idx - 1) == idx;
        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strId64(update_fce.name);
            const dep_arr = phase.update_dag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            const tags = if (is_root) "R" else " ";

            var depends_line: ?[]u8 = null;

            if (!is_root) {
                var depends_name = try cetech1.ArrayList([]const u8).initCapacity(_kernel_allocator, dep_arr.?.len);
                defer depends_name.deinit(_kernel_allocator);

                for (dep_arr.?) |dep_id| {
                    const dep_iface = _iface_map.getPtr(dep_id).?;
                    depends_name.appendAssumeCapacity(dep_iface.*.name);
                }

                depends_line = try std.mem.join(_kernel_allocator, ", ", depends_name.items);
            }

            const vert_line = if (!is_last) " " else " ";

            if (depends_line == null) {
                log.info("\t{s}\t- [{s}] {s}", .{ vert_line, tags, update_fce.name });
            } else {
                defer _kernel_allocator.free(depends_line.?);
                log.info("\t{s}\t- [{s}] {s} [{s}]", .{ vert_line, tags, update_fce.name, depends_line.? });
            }
        }
    }
}

fn dumpKernelUpdatePhaseTreeD2() !void {
    var path_buff: [1024]u8 = undefined;
    var file_path_buff: [1024]u8 = undefined;
    // only if asset root is set.
    var path = try assetdb.api.getTmpPath(&path_buff);
    if (path == null) return;
    path = try std.fmt.bufPrint(&file_path_buff, "{s}/" ++ "kernel_task_graph.d2", .{path.?});

    var dot_file = try std.fs.createFileAbsolute(path.?, .{});
    defer dot_file.close();

    var bw = std.io.bufferedWriter(dot_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    _ = try writer.write("vars: {d2-config: {layout-engine: elk}}\n\n");

    // write nodes

    var prev_phase: ?*Phase = null;
    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        if (prev_phase != null) {
            try writer.print("{s}->{s}\n", .{ prev_phase.?.name, phase.name });
        }
        prev_phase = phase;

        try writer.print("{s}: {{\n", .{phase.name});

        for (phase.update_chain.items) |update_fce| {
            const task_name_strid = cetech1.strId64(update_fce.name);
            const dep_arr = phase.update_dag.dependList(task_name_strid);
            const is_root = dep_arr == null;
            const iface = _iface_map.getPtr(task_name_strid).?;
            if (!is_root) {
                for (dep_arr.?) |dep_id| {
                    const dep_iface = _iface_map.getPtr(dep_id).?;
                    try writer.print("{s}->{s}\n", .{ dep_iface.*.name, iface.*.name });
                }
            } else {
                try writer.print("{s}\n", .{iface.*.name});
            }
        }

        try writer.print("}}\n", .{});
    }
}

fn initKernelTasks() !void {
    for (_task_chain.items) |iface| {
        try iface.init();
    }
}

fn dumpKernelTask() void {
    log.info("Kernel tasks", .{});
    for (_task_chain.items) |t| {
        log.info("\t- {s}", .{t.name});
    }
}

fn shutdownKernelTasks() !void {
    for (0.._task_chain.items.len) |idx| {
        const iface = _task_chain.items[_task_chain.items.len - 1 - idx];
        try iface.shutdown();
    }
}

// test "Can boot kernel" {
//     if (builtin.os.tag == .linux) return error.SkipZigTest;
//     const Module1 = struct {
//         var called: bool = false;
//         fn load_module(_apidb: *const cetech1.apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
//             _ = _apidb;
//             _ = reload;
//             _ = load;
//             _ = _allocator;
//             called = true;
//             return true;
//         }
//     };

//     const static_modules = [_]cetech1.modules.ModuleDesc{.{ .name = "module1", .module_fce = @ptrCast(&Module1.load_module) }};
//     try boot(&static_modules, .{ .headless = true, .load_dynamic = false, .max_kernel_tick = 2 });
//     try std.testing.expect(Module1.called);
// }

// Assert C api == C api in zig.
comptime {}
