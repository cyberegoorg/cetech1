const std = @import("std");

const strid = @import("stringid.zig");
const log = @import("log.zig");
const apidb = @import("apidb.zig");
const modules = @import("modules.zig");
const cetech1 = @import("../cetech1.zig");
const c = @import("../c.zig");

const UpdateArray = std.ArrayList(*cetech1.c.ct_kernel_task_update_i);
const KernelTaskArray = std.ArrayList(*cetech1.c.ct_kernel_task_i);
const PhaseMap = std.AutoArrayHashMap(cetech1.StrId64, Phase);

const LOG_SCOPE = "kernel";

const Phase = struct {
    const Self = @This();

    name: []const u8,
    update_bag: cetech1.BAG(cetech1.StrId64),
    update_chain: UpdateArray,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
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

var _main_allocator: std.mem.Allocator = undefined;
var _update_bag: cetech1.BAG(cetech1.StrId64) = undefined;
var _update_chain: UpdateArray = undefined;

var _task_bag: cetech1.BAG(cetech1.StrId64) = undefined;
var _task_chain: KernelTaskArray = undefined;

var _phase_map: PhaseMap = undefined;
var _phases_bag: cetech1.BAG(cetech1.StrId64) = undefined;

var _args: [][:0]u8 = undefined;
var _args_map: std.StringArrayHashMap([]const u8) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _main_allocator = allocator;

    _update_bag = cetech1.BAG(cetech1.StrId64).init(allocator);
    _update_chain = UpdateArray.init(allocator);

    _phases_bag = cetech1.BAG(cetech1.StrId64).init(allocator);
    _phase_map = PhaseMap.init(allocator);

    _task_bag = cetech1.BAG(cetech1.StrId64).init(allocator);
    _task_chain = KernelTaskArray.init(allocator);

    _args_map = std.StringArrayHashMap([]const u8).init(allocator);

    try apidb.init(allocator);
    try modules.init(allocator);

    try log.registerToApi();
    try strid.registerToApi();

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
    apidb.deinit();
    modules.deinit();

    _update_bag.deinit();
    _update_chain.deinit();
    _phases_bag.deinit();
    _phase_map.deinit();
    _task_bag.deinit();
    _task_chain.deinit();
    _args_map.deinit();

    deinitArgs();
}

fn initProgramArgs() !void {
    _args = try std.process.argsAlloc(_main_allocator);

    var args_idx: u32 = 1; // Skip program name
    while (args_idx < _args.len) {
        var name = _args[args_idx];

        if (args_idx + 1 >= _args.len) {
            log.api.err(LOG_SCOPE, "Invalid commandline args. Last is {s}", .{name});
            break;
        }

        var value = _args[args_idx + 1];
        try _args_map.put(name, value);

        args_idx += 2;
    }
}

fn deinitArgs() void {
    std.process.argsFree(_main_allocator, _args);
}

fn getIntArgs(arg_name: []const u8, default: u32) !u32 {
    var v = _args_map.get(arg_name);
    if (v == null) {
        return default;
    }
    return try std.fmt.parseInt(u32, v.?, 10);
}

pub fn bootInit(static_modules: ?[]const c.c.ct_module_desc_t, load_dynamic: bool) !void {
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
}

pub fn bootDeinit() !void {
    shutdownKernelTasks();

    try modules.unloadAll();
}

pub fn boot(static_modules: ?[*]c.c.ct_module_desc_t, static_modules_n: u32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    try init(allocator);

    const max_kernel_tick = try getIntArgs("--max-kernel-tick", 0);
    const load_dynamic = try getIntArgs("--load-dynamic", 1) == 1;

    try bootInit(static_modules.?[0..static_modules_n], load_dynamic);
    defer bootDeinit() catch unreachable;

    var kernel_tick: u64 = 1;
    var last_call = std.time.milliTimestamp();

    try _phases_bag.build(cetech1.OnLoad);

    try generateTaskUpdateChain();
    var kernel_update_gen = apidb.api.getInterafceGen(c.c.ct_kernel_task_update_i);

    while (true) : (kernel_tick += 1) {
        log.api.debug(LOG_SCOPE, "FRAME BEGIN", .{});
        var now = std.time.milliTimestamp();
        var dt = now - last_call;
        last_call = now;

        const reloaded_modules = try modules.reloadAllIfNeeded();
        if (reloaded_modules) {
            apidb.dumpGlobalVar();
        }

        var new_kernel_update_gen = apidb.api.getInterafceGen(c.c.ct_kernel_task_update_i);
        if (new_kernel_update_gen != kernel_update_gen) {
            try generateTaskUpdateChain();
            kernel_update_gen = new_kernel_update_gen;
        }

        updateKernelTasks(kernel_tick, dt);

        log.api.debug(LOG_SCOPE, "FRAME END", .{});

        if (max_kernel_tick > 0) {
            if (kernel_tick >= max_kernel_tick) {
                break;
            }
        }
        std.time.sleep(std.time.ns_per_s * 1);
    }
}

fn addPhase(name: []const u8, depend: []const cetech1.StrId64) !void {
    const name_hash = cetech1.strId64(name);
    var phase = Phase.init(_main_allocator, name);
    try _phase_map.put(name_hash, phase);
    try _phases_bag.add(name_hash, depend);
}

fn generateKernelTaskChain() !void {
    try _task_bag.reset();
    try _task_chain.resize(0);

    var iface_map = std.AutoArrayHashMap(cetech1.StrId64, *c.c.ct_kernel_task_i).init(_main_allocator);
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
    try _update_bag.reset();
    try _update_chain.resize(0);

    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        try phase.reset();
    }

    var iface_map = std.AutoArrayHashMap(cetech1.StrId64, *c.c.ct_kernel_task_update_i).init(_main_allocator);
    defer iface_map.deinit();

    var it = apidb.api.getFirstImpl(c.c.ct_kernel_task_update_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.ApiDbAPI.toInterface(c.c.ct_kernel_task_update_i, node);
        var depends = if (iface.depends_n != 0) iface.depends[0..iface.depends_n] else &[_]cetech1.StrId64{};

        const name_hash = cetech1.strId64(iface.name[0..std.mem.len(iface.name)]);

        var phase = _phase_map.getPtr(iface.phase).?;
        try phase.update_bag.add(name_hash, depends);

        try iface_map.put(name_hash, iface);
    }

    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;

        try phase.update_bag.build_all();

        for (phase.update_bag.output.items) |module_name| {
            try phase.update_chain.append(iface_map.get(module_name).?);
        }
    }

    dumpKernelUpdatePhaseTree();
}

fn updateKernelTasks(kernel_tick: u64, dt: i64) void {
    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        for (phase.update_chain.items) |update_fce| {
            update_fce.update.?(kernel_tick, @floatFromInt(dt));
        }
    }
}

fn dumpKernelUpdatePhaseTree() void {
    log.api.debug(LOG_SCOPE, "UPDATE PHASE", .{});
    for (_phases_bag.output.items) |phase_hash| {
        var phase = _phase_map.getPtr(phase_hash).?;
        log.api.debug(LOG_SCOPE, " +- PHASE: {s}", .{phase.name});

        for (phase.update_chain.items) |update_fce| {
            log.api.debug(LOG_SCOPE, " |   +- TASK: {s}", .{update_fce.name});
        }
    }
}

fn initKernelTasks() void {
    for (_task_chain.items) |iface| {
        iface.init.?();
    }
}

fn dumpKernelTask() void {
    log.api.debug(LOG_SCOPE, "TASKS", .{});
    for (_task_chain.items) |task| {
        log.api.debug(LOG_SCOPE, " +- {s}", .{task.name});
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
        log.api.err(LOG_SCOPE, "Boot error: {}", .{err});
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
    try bootInit(&static_modules, false);
    try bootDeinit();

    try std.testing.expect(Module1.called);
}
