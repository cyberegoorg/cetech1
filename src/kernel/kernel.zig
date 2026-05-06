const std = @import("std");
const builtin = @import("builtin");

const profiler_private = @import("profiler.zig");
const strid_private = @import("strid.zig");
const log_private = @import("log.zig");
const apidb_private = @import("apidb.zig");
const modules_private = @import("modules.zig");
const task_private = @import("task.zig");
const cdb_private = @import("cdb.zig");
const cdb_types_private = @import("cdb_types.zig");
const tempalloc_private = @import("tempalloc.zig");
const uuid_private = @import("uuid.zig");
const assetdb_private = @import("assetdb.zig");
const host_private = @import("host.zig");
const input_private = @import("input.zig");
const gpu_privat = @import("gpu.zig");
const coreui_private = @import("coreui.zig");
const ecs_private = @import("ecs.zig");

const metrics = @import("metrics.zig");

const cetech1 = @import("cetech1");
const public = cetech1.kernel;
const profiler = cetech1.profiler;
const task = cetech1.task;
const tempalloc = cetech1.tempalloc;
const apidb = cetech1.apidb;

const cdb = cetech1.cdb;

const cetech1_options = @import("cetech1_options");

const externals_credits = @embedFile("externals_credit");
const authors = @embedFile("authors");

const module_name = .kernel;

const log = std.log.scoped(module_name);

const core_modules = [_]cetech1.modules.ModuleDesc{
    .{ .name = "actions", .module_fce = .{ .zig_fce = @import("actions.zig").load_module_zig } },
    .{ .name = "transform", .module_fce = .{ .zig_fce = @import("transform.zig").load_module_zig } },
    .{ .name = "graphvm", .module_fce = .{ .zig_fce = @import("scripting/graphvm/graphvm.zig").load_module_zig } },
    .{ .name = "graphvm_script_component", .module_fce = .{ .zig_fce = @import("scripting/graphvm/graphvm_script_component.zig").load_module_zig } },
    .{ .name = "native_script_component", .module_fce = .{ .zig_fce = @import("scripting/native_script_component.zig").load_module_zig } },
    .{ .name = "camera", .module_fce = .{ .zig_fce = @import("camera/camera.zig").load_module_zig } },
    .{ .name = "camera_controller", .module_fce = .{ .zig_fce = @import("camera/camera_controller.zig").load_module_zig } },
    .{ .name = "visibility_flags", .module_fce = .{ .zig_fce = @import("renderer/visibility_flags.zig").load_module_zig } },
    .{ .name = "render_graph", .module_fce = .{ .zig_fce = @import("renderer/render_graph.zig").load_module_zig } },
    .{ .name = "render_pipeline", .module_fce = .{ .zig_fce = @import("renderer/render_pipeline.zig").load_module_zig } },
    .{ .name = "render_viewport", .module_fce = .{ .zig_fce = @import("renderer/render_viewport.zig").load_module_zig } },
    .{ .name = "shader_system", .module_fce = .{ .zig_fce = @import("renderer/shader_system.zig").load_module_zig } },
    .{ .name = "renderer_nodes", .module_fce = .{ .zig_fce = @import("renderer/renderer_nodes.zig").load_module_zig } },
    .{ .name = "physics", .module_fce = .{ .zig_fce = @import("physics/physics.zig").load_module_zig } },
    .{ .name = "bloom", .module_fce = .{ .zig_fce = @import("renderer_pipeline/bloom.zig").load_module_zig } },
    .{ .name = "default_render_pipeline", .module_fce = .{ .zig_fce = @import("renderer_pipeline/default_render_pipeline.zig").load_module_zig } },
    .{ .name = "instance_system", .module_fce = .{ .zig_fce = @import("renderer_pipeline/instance_system.zig").load_module_zig } },
    .{ .name = "light_component", .module_fce = .{ .zig_fce = @import("renderer_pipeline/light_component.zig").load_module_zig } },
    .{ .name = "light_system", .module_fce = .{ .zig_fce = @import("renderer_pipeline/light_system.zig").load_module_zig } },
    .{ .name = "render_component", .module_fce = .{ .zig_fce = @import("renderer_pipeline/render_component.zig").load_module_zig } },
    .{ .name = "tonemap", .module_fce = .{ .zig_fce = @import("renderer_pipeline/tonemap.zig").load_module_zig } },
    .{ .name = "vertex_system", .module_fce = .{ .zig_fce = @import("renderer_pipeline/vertex_system.zig").load_module_zig } },
    .{ .name = "physics_jolt", .module_fce = .{ .zig_fce = @import("physics/physics_jolt.zig").load_module_zig } },
    .{ .name = "luauvm", .module_fce = .{ .zig_fce = @import("scripting/luauvm/luauvm.zig").load_module_zig } },
    .{ .name = "luauvm_script_component", .module_fce = .{ .zig_fce = @import("scripting/luauvm/luauvm_script_component.zig").load_module_zig } },
    .{ .name = "gpu_bgfx", .module_fce = .{ .zig_fce = @import("gpu_bgfx/gpu_bgfx.zig").load_module_zig } },
};

const editor_modules = [_]cetech1.modules.ModuleDesc{
    .{ .name = "editor", .module_fce = .{ .zig_fce = @import("editor/editor.zig").load_module_zig } },
    .{ .name = "editor_asset_browser", .module_fce = .{ .zig_fce = @import("editor/asset_browser.zig").load_module_zig } },
    .{ .name = "editor_asset_preview", .module_fce = .{ .zig_fce = @import("editor/asset_preview.zig").load_module_zig } },
    .{ .name = "editor_assetdb", .module_fce = .{ .zig_fce = @import("editor/assetdb.zig").load_module_zig } },
    .{ .name = "editor_entity_asset", .module_fce = .{ .zig_fce = @import("editor/entity_asset.zig").load_module_zig } },
    .{ .name = "editor_entity_editor", .module_fce = .{ .zig_fce = @import("editor/entity_editor.zig").load_module_zig } },
    .{ .name = "editor_explorer", .module_fce = .{ .zig_fce = @import("editor/explorer.zig").load_module_zig } },
    .{ .name = "editor_fixtures", .module_fce = .{ .zig_fce = @import("editor/fixtures.zig").load_module_zig } },
    .{ .name = "editor_gizmo", .module_fce = .{ .zig_fce = @import("editor/gizmo.zig").load_module_zig } },
    .{ .name = "editor_graph", .module_fce = .{ .zig_fce = @import("editor/graph.zig").load_module_zig } },
    .{ .name = "editor_input", .module_fce = .{ .zig_fce = @import("editor/input.zig").load_module_zig } },
    .{ .name = "editor_inspector", .module_fce = .{ .zig_fce = @import("editor/inspector.zig").load_module_zig } },
    .{ .name = "editor_log", .module_fce = .{ .zig_fce = @import("editor/log.zig").load_module_zig } },
    .{ .name = "editor_metrics", .module_fce = .{ .zig_fce = @import("editor/metrics.zig").load_module_zig } },
    .{ .name = "editor_obj_buffer", .module_fce = .{ .zig_fce = @import("editor/obj_buffer.zig").load_module_zig } },
    .{ .name = "editor_renderer", .module_fce = .{ .zig_fce = @import("editor/renderer.zig").load_module_zig } },
    .{ .name = "editor_simulator", .module_fce = .{ .zig_fce = @import("editor/simulator.zig").load_module_zig } },
    .{ .name = "editor_tabs", .module_fce = .{ .zig_fce = @import("editor/tabs.zig").load_module_zig } },
    .{ .name = "editor_tree", .module_fce = .{ .zig_fce = @import("editor/tree.zig").load_module_zig } },
};

const runner_modules = [_]cetech1.modules.ModuleDesc{
    .{ .name = "runner", .module_fce = .{ .zig_fce = @import("runner.zig").load_module_zig } },
};

pub fn bootRunner(process_init: std.process.Init, comptime static_modules: []const cetech1.modules.ModuleDesc) !void {
    try boot(
        process_init,
        static_modules ++ runner_modules,
        .{
            .ignored_modules = &.{"editor"},
            .ignored_modules_prefix = &.{"editor_"},
        },
    );
}

pub fn bootStudio(process_init: std.process.Init, comptime static_modules: []const cetech1.modules.ModuleDesc) !void {
    try boot(
        process_init,
        static_modules ++ editor_modules,
        .{
            .ignored_modules = &.{"runner"},
            .ignored_modules_prefix = &.{"runner_"},
        },
    );
}

const UpdateArray = cetech1.ArrayList(*const public.KernelTaskUpdateI);
const KernelTaskArray = cetech1.ArrayList(*const public.KernelTaskI);
const PhaseMap = cetech1.AutoArrayHashMap(cetech1.StrId64, Phase);

const BootArgs = struct {
    max_kernel_tick: u32 = 0,
    headless: bool = false,
    load_dynamic: bool = true,
    ignored_modules: ?[]const []const u8 = null,
    ignored_modules_prefix: ?[]const []const u8 = null,
};

const Phase = struct {
    const Self = @This();

    name: [:0]const u8,
    update_dag: cetech1.dag.StrId64DAG,
    update_chain: UpdateArray = .empty,

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
var _profiler_allocator: profiler.AllocatorProfiler = undefined;
var _cdb_allocator: profiler.AllocatorProfiler = undefined;
var _assetdb_allocator: profiler.AllocatorProfiler = undefined;
var _host_allocator: profiler.AllocatorProfiler = undefined;
var _input_allocator: profiler.AllocatorProfiler = undefined;
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

var _args: []const [:0]const u8 = undefined;
var _args_map: std.StringArrayHashMapUnmanaged([]const u8) = undefined;

var _tmp_depend_array: cetech1.task.TaskIdList = undefined;
var _tmp_taskid_map: cetech1.AutoArrayHashMap(cetech1.StrId64, cetech1.task.TaskID) = undefined;

var _iface_map: cetech1.AutoArrayHashMap(cetech1.StrId64, *const public.KernelTaskUpdateI) = undefined;

var _running: bool = false;
var _quit: bool = false;

var _can_quit_handler: ?*const fn () bool = null;

var _max_tick_rate: u32 = 60;
var _restart = true;

var _next_asset_root_buff: [256]u8 = undefined;
var _next_asset_root: ?[]u8 = null;
var _main_window: ?*cetech1.host.Window = null;
var _gpu_backend: ?cetech1.gpu.GpuBackend = null;

const api = cetech1.kernel.KernelApi{
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
    .getGpuBackend = getGpuBackend,
    .getExternalsCredit = getExternalsCredit,
    .getAuthors = getAuthors,
    .getStrArgs = getStrArgs,
    .getIntArgs = getIntArgs,
    .getTmpPath = getTmpPath,
};

fn getExternalsCredit() [:0]const u8 {
    return externals_credits;
}

fn getAuthors() [:0]const u8 {
    return authors;
}

fn getMainWindow() ?*cetech1.host.Window {
    return _main_window;
}
fn getGpuBackend() ?cetech1.gpu.GpuBackend {
    return _gpu_backend;
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
    return cetech1.assetdb.getDb();
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
    _can_quit_handler = can_quit;
}

pub fn init(io: std.Io, allocator: std.mem.Allocator, headless: bool, boot_args: BootArgs) !void {
    public.api = &api;
    try log_private.init(io);
    _root_allocator = allocator;
    _main_profiler_allocator = profiler.AllocatorProfiler.init(allocator, null);
    _kernel_allocator = _main_profiler_allocator.allocator();

    _profiler_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "profiler");
    profiler_private.init(_profiler_allocator.allocator());

    _apidb_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "apidb");
    _modules_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "modules");
    _task_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "task");
    _cdb_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "cdb");
    _assetdb_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "assetdb");
    _host_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "host");
    _input_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "input");
    _gpu_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "gpu");
    _coreui_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "coreui");
    _tmp_alocator_pool_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "tmp_allocators");
    _ecs_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "ecs");
    _actions_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "actions");
    _metrics_allocator = profiler.AllocatorProfiler.init(_kernel_allocator, "metrics");

    _update_dag = cetech1.dag.StrId64DAG.init(_kernel_allocator);
    _phases_dag = cetech1.dag.StrId64DAG.init(_kernel_allocator);
    _phase_map = .{};

    _task_dag = cetech1.dag.StrId64DAG.init(_kernel_allocator);
    _task_chain = .empty;

    _tmp_depend_array = .empty;
    _tmp_taskid_map = .empty;

    _iface_map = .empty;

    try uuid_private.init(io);
    try task_private.init(io, _task_allocator.allocator());
    try tempalloc_private.init(_tmp_alocator_pool_allocator.allocator(), 256);

    try apidb_private.init(_apidb_allocator.allocator());
    try modules_private.init(_modules_allocator.allocator(), boot_args.ignored_modules, boot_args.ignored_modules_prefix);
    try metrics.init(_metrics_allocator.allocator());
    try cdb_private.init(io, _cdb_allocator.allocator());
    try host_private.init(io, _host_allocator.allocator(), headless);
    try input_private.init(_input_allocator.allocator());
    try gpu_privat.init(_gpu_allocator.allocator());
    try coreui_private.init(io, _coreui_allocator.allocator());

    try apidb.setZigApi(module_name, cetech1.kernel.KernelApi, &api);

    try log_private.registerToApi();
    try tempalloc_private.registerToApi();
    try strid_private.registerToApi();
    try profiler_private.registerToApi();
    try task_private.registerToApi();
    try uuid_private.registerToApi();
    try cdb_private.registerToApi();
    try cdb_types_private.registerToApi();
    try assetdb_private.registerToApi();
    try host_private.registerToApi();
    try input_private.registerToApi();
    try gpu_privat.registerToApi();
    try coreui_private.registerToApi();
    try ecs_private.registerToApi();
    try metrics.registerToApi();

    try addPhase("OnLoad", &[_]cetech1.StrId64{});
    try addPhase("PostLoad", &[_]cetech1.StrId64{cetech1.kernel.OnLoad});
    try addPhase("PreUpdate", &[_]cetech1.StrId64{cetech1.kernel.PostLoad});
    try addPhase("OnUpdate", &[_]cetech1.StrId64{cetech1.kernel.PreUpdate});
    try addPhase("OnValidate", &[_]cetech1.StrId64{cetech1.kernel.OnUpdate});
    try addPhase("PostUpdate", &[_]cetech1.StrId64{cetech1.kernel.OnValidate});
    try addPhase("PreStore", &[_]cetech1.StrId64{cetech1.kernel.PostUpdate});
    try addPhase("OnStore", &[_]cetech1.StrId64{cetech1.kernel.PreStore});

    log.info("version: {f}", .{cetech1_options.version});
}

pub fn deinit(io: std.Io, allocator: std.mem.Allocator) !void {
    try shutdownKernelTasks();

    // Before modules deinit because ImGUI test engine need test love for export result.xml
    coreui_private.deinit();
    try modules_private.unloadAll(io);

    ecs_private.deinit();
    if (_gpu_backend) |ctx| cetech1.gpu.destroyBackend(ctx);
    gpu_privat.deinit();
    if (_main_window) |window| cetech1.host.destroyWindow(window);

    input_private.deinit();
    host_private.deinit();

    assetdb_private.deinit();
    modules_private.deinit();

    task_private.stop();

    cdb_private.deinit();
    task_private.deinit();
    metrics.deinit();
    apidb_private.deinit();
    tempalloc_private.deinit();

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

var _tmp_path: []u8 = undefined;
pub fn getTmpPath() []const u8 {
    return _tmp_path;
}

fn initProgramArgs(ini: std.process.Init, allocator: std.mem.Allocator) !void {
    _args = try ini.minimal.args.toSlice(ini.arena.allocator());
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

pub fn bigInit(io: std.Io, static_modules: []const cetech1.modules.ModuleDesc, load_dynamic: bool) !void {
    try modules_private.addModules(&core_modules);

    if (static_modules.len != 0) {
        try modules_private.addModules(static_modules);
    }

    if (load_dynamic) {
        modules_private.loadDynModules(io) catch |err| {
            log.err("Could not load dynamic modules {}", .{err});
        };
    }

    try modules_private.loadAll(io);
    modules_private.dumpModules();

    const worker_count = getIntArgs("--worker-count");
    try task_private.start(worker_count);
    try ecs_private.init(io, _ecs_allocator.allocator());
    try assetdb_private.init(io, _assetdb_allocator.allocator());

    try generateKernelTaskChain(_kernel_allocator);

    apidb_private.dumpApi();
    apidb_private.dumpsetGlobalVar();
}

pub fn bigDeinit() !void {
    profiler.frameMark();
}

pub fn quit() void {
    _quit = true;
}
var _can_quit_one = false;

fn sigQuitHandler(signum: std.posix.SIG) callconv(.c) void {
    _ = signum;

    if (!_can_quit_one) {
        if (_can_quit_handler) |can_quit| {
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
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.TERM, &sigaction, null);
        std.posix.sigaction(std.posix.SIG.INT, &sigaction, null);
    }
}

var _headless = false;
// https://github.com/liyu1981/tmpfile.zig/blob/master/src/tmpfile.zig#L11
pub fn getSysTmpDir(a: std.mem.Allocator, env_map: *const std.process.Environ.Map) ![]u8 {
    const Impl = switch (builtin.os.tag) {
        .linux, .macos => struct {
            pub fn get(allocator: std.mem.Allocator, env_map_: *const std.process.Environ.Map) ![]u8 {
                // cpp17's temp_directory_path gives good reference
                // https://en.cppreference.com/w/cpp/filesystem/temp_directory_path
                // POSIX standard, https://en.wikipedia.org/wiki/TMPDIR
                return allocator.dupe(
                    u8,
                    env_map_.get("TMPDIR") orelse
                        env_map_.get("TMP") orelse
                        env_map_.get("TEMP") orelse
                        env_map_.get("TEMPDIR") orelse
                        "/tmp",
                );
            }
        },
        .windows => struct {
            const DWORD = std.os.windows.DWORD;
            const LPWSTR = std.os.windows.LPWSTR;
            const MAX_PATH = std.os.windows.MAX_PATH;
            const WCHAR = std.os.windows.WCHAR;

            pub extern "C" fn GetTempPath2W(BufferLength: DWORD, Buffer: LPWSTR) DWORD;

            pub fn get(allocator: std.mem.Allocator, env_map_: *const std.process.Environ.Map) ![]const u8 {
                _ = env_map_;

                // use GetTempPathW2, https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppathw
                var wchar_buf: [MAX_PATH + 2:0]WCHAR = undefined;
                wchar_buf[MAX_PATH + 1] = 0;
                const ret = GetTempPath2W(MAX_PATH + 1, &wchar_buf);
                if (ret != 0) {
                    const path = wchar_buf[0..ret];
                    return std.unicode.utf16LeToUtf8Alloc(allocator, path);
                } else {
                    return error.GetTempPath2WFailed;
                }
            }
        },
        else => {
            @panic(@tagName(std.builtin.os.tag) ++ " is not support");
        },
    };

    return Impl.get(a, env_map);
}

pub fn boot(process_init: std.process.Init, static_modules: []const cetech1.modules.ModuleDesc, boot_args: BootArgs) !void {
    while (_restart) {
        _restart = false;
        const is_debug = builtin.mode == .Debug;

        // Main Allocator
        const gpa_allocator = process_init.gpa;

        _tmp_path = try getSysTmpDir(gpa_allocator, process_init.environ_map);
        defer gpa_allocator.free(_tmp_path);

        try initProgramArgs(process_init, gpa_allocator);

        // Boot ARGS aka. command line args
        const max_kernel_tick = getIntArgs("--max-kernel-tick") orelse boot_args.max_kernel_tick;
        _max_tick_rate = getIntArgs("--max-kernel-tick-rate") orelse 60;

        const load_dynamic = 1 == getIntArgs("--load-dynamic") orelse @intFromBool(boot_args.load_dynamic);
        const asset_root = getStrArgs("--asset-root") orelse "";

        _headless = 1 == getIntArgs("--headless") orelse @intFromBool(boot_args.headless);
        const fullscreen = 1 == getIntArgs("--fullscreen") orelse 0;
        const vsync = 1 == getIntArgs("--vsync") orelse 1;

        const renderer_type = getStrArgs("--renderer");
        const renderer_debug = 1 == getIntArgs("--renderer-debug") orelse @intFromBool(is_debug);
        const renderer_profile = 1 == getIntArgs("--renderer-profile") orelse @intFromBool(is_debug);

        // Init Kernel
        try init(process_init.io, gpa_allocator, _headless, boot_args);
        defer deinit(process_init.io, gpa_allocator) catch undefined;

        // Test args
        const test_ui = 1 == getIntArgs("--test-ui") orelse 0;
        const test_ui_speed_value = getStrArgs("--test-ui-speed") orelse "fast";
        const fast_mode = std.mem.eql(u8, test_ui_speed_value, "fast");

        // Init modules
        try bigInit(process_init.io, static_modules, load_dynamic);
        defer bigDeinit() catch unreachable;

        var kernel_tick: u64 = 1;
        var tick_last_call = std.Io.Timestamp.now(process_init.io, .awake);

        // Build phase graph
        try _phases_dag.build_all();

        _running = true;
        _quit = false;

        // If asset root is set open it.
        if (asset_root.len != 0 or _next_asset_root != null) {
            try cetech1.assetdb.openAssetRootFolder(
                if (_next_asset_root) |root| root else asset_root,
                _assetdb_allocator.allocator(),
            );
            _next_asset_root = null;
        }

        try cdb.dump(assetdb_private.getDb());

        var buf: [256]u8 = undefined;
        if (try assetdb_private.getTmpPath(&buf)) |path| {
            const apidb_graph_md = try std.fs.path.join(_kernel_allocator, &.{ path, "apidb_graph.md" });
            defer _kernel_allocator.free(apidb_graph_md);
            try apidb_private.writeApiGraphMD(process_init.io, apidb_graph_md);
        }

        // Create update graph.
        try generateTaskUpdateChain(process_init.io, _kernel_allocator);
        var kernel_task_update_gen = apidb.getInterafcesVersion(public.KernelTaskUpdateI);
        var kernel_task_gen: cetech1.apidb.InterfaceVersion = 0;

        // Main window
        if (!_headless) {
            var w: i32 = 1024;
            var h: i32 = 768;

            const monitor = cetech1.host.getPrimaryMonitor();

            const vm = try monitor.?.getVideoMode();
            if (fullscreen) {
                w = vm.width;
                h = vm.height;
            } else {
                if (w * 2 <= vm.width and w * 2 <= vm.width) {
                    w *= 2;
                    h *= 2;
                }
            }

            log.info("Using video mode {d}x{d}", .{ w, h });

            _main_window = try cetech1.host.createWindow(
                w,
                h,
                cetech1_options.app_name ++ " - powered by CETech1",
                if (fullscreen) monitor else null,
            );
        }

        _gpu_backend = try cetech1.gpu.createBackend(
            _main_window,
            renderer_type,
            !_headless and vsync,
            _headless,
            renderer_debug,
            renderer_profile,
        );

        try initKernelTasks();

        // Register OS signals
        try registerSignals();

        var checkfs_timer: i64 = 0;
        const dt_couter = try metrics.getCounter("kernel/dt");
        const tick_duration_counter = try metrics.getCounter("kernel/tick_duration");

        var last_game_tick_task: cetech1.task.TaskID = .none;
        var game_tick_last_call = std.Io.Timestamp.now(process_init.io, .awake);

        var game_tick: usize = 0;

        var frame_arena = std.heap.ArenaAllocator.init(_main_profiler_allocator.allocator());
        defer frame_arena.deinit();

        try input_private.dumpControlers(frame_arena.allocator());

        // profiler.frameMark();
        while (_running and !_quit and !_restart) : (kernel_tick +%= 1) {
            // var update_zone_ctx = profiler.ZoneN(@src(), "kernelUpdate");
            // defer update_zone_ctx.End();

            const tick_duration = cetech1.metrics.MetricScopedDuration.begin(process_init.io, tick_duration_counter);
            defer tick_duration.end(process_init.io);

            const now = std.Io.Timestamp.now(process_init.io, .awake);
            const kernel_dt_ms = tick_last_call.durationTo(now).toMilliseconds();
            tick_last_call = now;

            dt_couter.* = @floatFromInt(kernel_dt_ms);

            checkfs_timer += kernel_dt_ms;

            _ = frame_arena.reset(.retain_capacity);
            const tmp_frame_alloc = frame_arena.allocator();

            // Any dynamic modules changed?
            // TODO: Watch
            if (checkfs_timer >= (10 * std.time.ms_per_s)) {
                checkfs_timer = 0;

                const reloaded_modules = try modules_private.reloadAllIfNeeded(process_init.io, tmp_frame_alloc);
                if (reloaded_modules) {}
            }

            // Any public.KernelTaskI iface changed? (add/remove)?
            const new_kernel_gen = apidb.getInterafcesVersion(public.KernelTaskI);
            if (new_kernel_gen != kernel_task_gen) {
                try generateKernelTaskChain(tmp_frame_alloc);
                kernel_task_gen = new_kernel_gen;
            }

            // Any public.KernelTaskUpdateI iface changed? (add/remove)?
            const new_kernel_update_gen = apidb.getInterafcesVersion(public.KernelTaskUpdateI);
            if (new_kernel_update_gen != kernel_task_update_gen) {
                try generateTaskUpdateChain(process_init.io, tmp_frame_alloc);
                kernel_task_update_gen = new_kernel_update_gen;
            }

            try cetech1.host.update(kernel_tick, 0);

            const GameTickTask = struct {
                kernel_tick: u64,
                dt_s: f32,
                fast_mode: bool,
                io: *const std.Io,

                pub fn exec(self: *@This()) !void {
                    profiler.frameMark();

                    const call_time: std.Io.Timestamp = .now(self.io.*, .awake);

                    var task_zone_ctx = profiler.ZoneN(@src(), "GameTick");
                    defer task_zone_ctx.End();

                    const allocator = try tempalloc.create();
                    defer tempalloc.destroy(allocator);

                    // Do hard work.
                    try doKernelUpdateTasks(self.kernel_tick, self.dt_s);

                    // clean main DB
                    try cdb.gc(allocator, assetdb_private.getDb());

                    try metrics.pushFrames();

                    if (!(isTestigMode() and self.fast_mode)) {
                        const t = try sleepIfNeed(self.io, allocator, call_time, _max_tick_rate, task.getThreadNum() - 1);
                        task.wait(t);
                    }
                }
            };

            if (task.isDone(last_game_tick_task)) {
                if (_next_asset_root != null) {
                    try cetech1.assetdb.openAssetRootFolder(
                        if (_next_asset_root) |root| root else asset_root,
                        _assetdb_allocator.allocator(),
                    );
                    _next_asset_root = null;
                } else {
                    const noww = std.Io.Timestamp.now(process_init.io, .awake);
                    const game_dt_ms = game_tick_last_call.durationTo(noww).toMilliseconds();
                    const game_dt_s: f32 = @as(f32, @floatFromInt(game_dt_ms)) / std.time.ms_per_s;
                    game_tick_last_call = noww;

                    const t = try task.schedule(
                        .none,
                        GameTickTask{
                            .dt_s = game_dt_s,
                            .kernel_tick = kernel_tick,
                            .fast_mode = fast_mode,
                            .io = &process_init.io,
                        },
                        .{},
                    );
                    last_game_tick_task = t;
                    // task.api.wait(t);
                    game_tick +%= 1;
                }
            } else {
                task.doOneTask(true);
            }

            // Check window close request
            if (_main_window) |window| {
                if (window.shouldClose()) {
                    if (_can_quit_handler) |can_quit| {
                        _ = can_quit();
                    } else {
                        _quit = true;
                    }
                }
            }

            // If set max-kernel-tick and reach limit then quit
            if (max_kernel_tick > 0) _quit = kernel_tick >= max_kernel_tick;

            if (test_ui and game_tick > 1) {
                const impls = try apidb.getImpl(tmp_frame_alloc, public.KernelTestingI);
                defer tmp_frame_alloc.free(impls);

                for (impls) |iface| {
                    _quit = !try iface.isRunning();
                }
            }

            {
                var zone_ctx = profiler.ZoneN(@src(), "renderFrame");
                defer zone_ctx.End();
                if (_gpu_backend) |ctx| {
                    _ = ctx.renderFrame(0);
                }
            }
        }

        // wait for last game tick
        // without this deadlock shit
        // TODO: quit loop only after last_game_tick_task
        while (!task.isDone(last_game_tick_task)) {
            if (_gpu_backend) |ctx| {
                _ = ctx.renderFrame(2);
            }
            task.doOneTask(false);
        }
        task.wait(last_game_tick_task);

        if (test_ui) {
            const impls = try apidb.getImpl(_kernel_allocator, public.KernelTestingI);
            defer _kernel_allocator.free(impls);

            for (impls) |iface| {
                iface.printResult();

                const result = iface.getResult();

                if (result.count_success != result.count_tested) {
                    return error.TestFailed;
                }
            }
        }

        profiler.frameMark();
        profiler.frameMark();

        if (!_restart) {
            log.info("Do quit", .{});
        } else {
            log.info("Do restart", .{});
        }
    }
}

fn sleepIfNeed(io: *const std.Io, allocator: std.mem.Allocator, last_call: std.Io.Timestamp, max_rate: u32, worker_n: u64) !cetech1.task.TaskID {
    const frame_limit_time: f32 = (1.0 / @as(f32, @floatFromInt(max_rate)) * std.time.ms_per_s);

    const dt: f32 = @floatFromInt(last_call.durationTo(.now(io.*, .awake)).toMilliseconds());
    if (dt < frame_limit_time) {
        const sleep_time: u64 = @intFromFloat((frame_limit_time - dt) * 0.62 * std.time.ns_per_ms);

        const n = worker_n;
        var wait_tasks = try cetech1.task.TaskIdList.initCapacity(allocator, n);
        defer wait_tasks.deinit(allocator);

        for (0..n) |idx| {
            const SleepTask = struct {
                sleep_time: u64,
                io: *const std.Io,
                pub fn exec(self: *@This()) !void {
                    var task_zone_ctx = profiler.ZoneN(@src(), "ShityFrameLimitSleeper");
                    defer task_zone_ctx.End();
                    try std.Io.sleep(self.io.*, .fromNanoseconds(self.sleep_time), .awake);
                }
            };
            const t = try task.schedule(
                .none,
                SleepTask{ .sleep_time = sleep_time, .io = io },
                .{ .affinity = @intCast(idx + 1) },
            );
            wait_tasks.appendAssumeCapacity(t);
        }

        return task.combine(wait_tasks.items);
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
    var zone_ctx = profiler.ZoneN(@src(), "generateKernelTaskChain");
    defer zone_ctx.End();

    try _task_dag.reset();
    _task_chain.clearRetainingCapacity();

    var iface_map = cetech1.AutoArrayHashMap(cetech1.StrId64, *const public.KernelTaskI).empty;
    defer iface_map.deinit(_kernel_allocator);

    const impls = try apidb.getImpl(alloctor, public.KernelTaskI);
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

fn generateTaskUpdateChain(io: std.Io, allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.Zone(@src());
    defer zone_ctx.End();

    try _update_dag.reset();

    for (_phases_dag.output.keys()) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        try phase.reset();
    }

    _iface_map.clearRetainingCapacity();

    const impls = try apidb.getImpl(allocator, public.KernelTaskUpdateI);
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

    try dumpKernelUpdatePhaseTree(io);
}

const UpdateFrameName = "UpdateFrame";

fn doKernelUpdateTasks(kernel_tick: u64, dt: f32) !void {
    var fce_zone_ctx = profiler.Zone(@src());
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
                    var zone_ctx = profiler.Zone(@src());
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

                prereq = try task.combine(_tmp_depend_array.items);
            } else {
                prereq = last_phase_task_id;
            }

            const job_id = try task.schedule(
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

        const sync_job = try task.combine(_tmp_taskid_map.values());
        last_phase_task_id = sync_job;

        if (all_phase_update_task_id != cetech1.task.TaskID.none) {
            all_phase_update_task_id = sync_job;
        } else {
            all_phase_update_task_id = try task.combine(&[_]cetech1.task.TaskID{ all_phase_update_task_id, sync_job });
        }
    }

    task.wait(all_phase_update_task_id);

    _tmp_depend_array.clearRetainingCapacity();
    _tmp_taskid_map.clearRetainingCapacity();
}

fn dumpKernelUpdatePhaseTree(io: std.Io) !void {
    try dumpKernelUpdatePhaseTreeMD(io);

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

fn dumpKernelUpdatePhaseTreeMD(io: std.Io) !void {
    var path_buff: [1024]u8 = undefined;
    var file_path_buff: [1024]u8 = undefined;
    // only if asset root is set.
    var path = try cetech1.assetdb.getTmpPath(&path_buff);
    if (path == null) return;
    path = try std.fmt.bufPrint(&file_path_buff, "{s}/" ++ "kernel_task_graph.md", .{path.?});

    var dot_file = try std.Io.Dir.createFileAbsolute(io, path.?, .{});
    defer dot_file.close(io);

    var buffer: [4096]u8 = undefined;
    var bw = dot_file.writer(io, &buffer);
    const writer = &bw.interface;
    defer writer.flush() catch undefined;

    try writer.print("# Kernel task graph\n\n", .{});

    // write header
    try writer.print("```d2\n", .{});
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
    try writer.print("```\n", .{});
}

var _kernel_task_initialised: bool = false;
fn initKernelTasks() !void {
    for (_task_chain.items) |iface| {
        try iface.init();
    }
    _kernel_task_initialised = true;
}

fn dumpKernelTask() void {
    log.info("Kernel tasks", .{});
    for (_task_chain.items) |t| {
        log.info("\t- {s}", .{t.name});
    }
}

fn shutdownKernelTasks() !void {
    if (_kernel_task_initialised) {
        for (0.._task_chain.items.len) |idx| {
            const iface = _task_chain.items[_task_chain.items.len - 1 - idx];
            try iface.shutdown();
        }
    }
    _kernel_task_initialised = false;
}

// test "Can boot kernel" {
//     if (builtin.os.tag == .linux) return error.SkipZigTest;
//     const Module1 = struct {
//         var called: bool = false;
//         fn load_module(_apidb: *const cetech1.apidb.ApiDbAPI, _allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
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
