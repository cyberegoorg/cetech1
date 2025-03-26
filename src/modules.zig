// TODO: ubershit DETECTED => cleanup needed

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Allocator = mem.Allocator;

const apidb = @import("apidb.zig");
const profiler_private = @import("profiler.zig");

const cetech1 = @import("cetech1");
const public = cetech1.modules;

const module_name = .modules;

const MODULE_PREFIX = "ct_";

const log = std.log.scoped(module_name);

const AllocatorItem = struct {
    tracy: cetech1.profiler.AllocatorProfiler,
    allocator: std.mem.Allocator = undefined,
};
const ModuleAlocatorMap = std.StringArrayHashMapUnmanaged(*AllocatorItem);

const ModuleDesc = struct {
    desc: public.ModuleDesc,
    full_path: ?[:0]u8,
};

const DynLibInfo = struct {
    full_path: [:0]u8,
    name: [:0]u8,
    dyn_lib: std.DynLib,
    symbol: *public.LoadModuleFn,
    mtime: i128,

    pub fn close(self: *@This()) void {
        self.dyn_lib.close();
        //_allocator.free(self.full_path);
    }
};

const ModulesList = std.DoublyLinkedList(ModuleDesc);
const ModulesListNodePool = std.heap.MemoryPool(ModulesList.Node);
const DynModuleHashMap = std.StringArrayHashMapUnmanaged(DynLibInfo);
const ModuleHashMap = std.StringArrayHashMapUnmanaged(ModuleDesc);

var _allocator: Allocator = undefined;
var _modules_map: ModuleHashMap = undefined;
var _dyn_modules_map: DynModuleHashMap = undefined;
var _modules_allocator_map: ModuleAlocatorMap = undefined;

pub fn init(allocator: Allocator) !void {
    _allocator = allocator;
    _dyn_modules_map = .{};
    _modules_map = .{};
    _modules_allocator_map = .{};
}

pub fn deinit() void {
    for (_modules_allocator_map.values()) |value| {
        _allocator.destroy(value);
    }

    _modules_map.deinit(_allocator);
    _modules_allocator_map.deinit(_allocator);
    _dyn_modules_map.deinit(_allocator);
}

fn getDllExtension() []const u8 {
    return switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd => ".so",
        .windows => ".dll",
        .macos, .tvos, .watchos, .ios => ".dylib",
        else => return undefined,
    };
}

fn getDllPrefix() []const u8 {
    return switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd => "lib",
        .macos, .tvos, .watchos, .ios => "lib",
        .windows => "",
        else => return undefined,
    };
}

pub fn isDynamicModule(basename: []const u8) bool {
    if (std.mem.count(u8, basename, ".") != 1) return false;
    if (!std.mem.startsWith(u8, basename, comptime getDllPrefix() ++ MODULE_PREFIX)) return false;
    if (!std.mem.endsWith(u8, basename, getDllExtension())) return false;
    return true;
}

fn getModuleName(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    var name_with_ext = std.mem.splitBackwardsSequence(u8, basename, MODULE_PREFIX);
    return std.fs.path.stem(name_with_ext.first());
}

pub fn addModules(modules: []const public.ModuleDesc) !void {
    for (modules) |v| {
        try _modules_map.put(_allocator, v.name, .{ .desc = v, .full_path = null });
    }
}

pub fn addDynamicModule(desc: public.ModuleDesc, full_path: ?[:0]u8) !void {
    try _modules_map.put(_allocator, desc.name, .{ .desc = desc, .full_path = full_path });
}

pub fn loadAll() !void {
    for (_modules_map.values()) |*it| {
        var module_desc = it;

        var alloc_item = _modules_allocator_map.getPtr(module_desc.desc.name);
        if (alloc_item == null) {
            var item_ptr = try _allocator.create(AllocatorItem);
            item_ptr.* = AllocatorItem{
                .tracy = cetech1.profiler.AllocatorProfiler.init(
                    &profiler_private.api,
                    _allocator,
                    module_desc.desc.name,
                ),
            };
            item_ptr.*.allocator = item_ptr.tracy.allocator();

            try _modules_allocator_map.put(_allocator, module_desc.desc.name, item_ptr);
            alloc_item = _modules_allocator_map.getPtr(module_desc.desc.name);
        }

        if (!module_desc.desc.module_fce(@ptrCast(&apidb.api), @ptrCast(@alignCast(&alloc_item.?.*.allocator)), true, false)) {
            log.err("Problem with load module {s}", .{module_desc.desc.name});
        }
    }
}

pub fn unloadAll() !void {
    for (_modules_map.values()) |*it| {
        const alloc_item = _modules_allocator_map.getPtr(it.desc.name).?;

        if (!it.desc.module_fce(@ptrCast(&apidb.api), @ptrCast(&alloc_item.*.allocator), false, false)) {
            log.err("Problem with unload module {s}", .{it.desc.name});
        }
    }

    var iter = _dyn_modules_map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.close();
        _allocator.free(entry.value_ptr.full_path);
        _allocator.free(entry.value_ptr.name);
    }

    // for (_modules_allocator_map.keys()) |k| {
    //     _allocator.free(k[0 .. k.len + 1]);
    // }
}

fn _getModule(name: []const u8) ?*ModuleDesc {
    return _modules_map.getPtr(name);
}

fn _loadDynLib(path: []const u8) !DynLibInfo {
    var dll = std.DynLib.open(path) catch |err| {
        log.err("Error load module from {s} with error {any}", .{ path, err });
        return err;
    };

    var load_fce_name_buff: [128:0]u8 = undefined;
    const name = getModuleName(path);
    const load_fce_name = try std.fmt.bufPrintZ(&load_fce_name_buff, "ct_load_module_{s}", .{name});

    const symbol = dll.lookup(*public.LoadModuleFn, load_fce_name);
    if (symbol == null) {
        log.err("Error find symbol {s} in {s}", .{ load_fce_name, path });
        return error.SymbolNotFound;
    }

    const f = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    errdefer f.close();
    const f_stat = try f.stat();
    const mtime = f_stat.mtime;
    f.close();

    return .{
        .name = try _allocator.dupeZ(u8, name),
        .full_path = try _allocator.dupeZ(u8, path),
        .dyn_lib = dll,
        .symbol = symbol.?,
        .mtime = mtime,
    };
}

fn lessThanStr(ctx: void, lhs: []const u8, rhs: []const u8) bool {
    _ = ctx; // autofix
    return std.ascii.lessThanIgnoreCase(lhs, rhs);
}

pub fn loadDynModules() !void {
    const allocator = _allocator;

    // TODO remove this fucking long alloc hell
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);

    const module_dir = try std.fs.path.join(allocator, if (builtin.os.tag == .windows) &.{exe_dir} else &.{ exe_dir, "..", "lib" });
    defer allocator.free(module_dir);

    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const module_dir_relat = try std.fs.path.relative(allocator, cwd_path, module_dir);
    defer allocator.free(module_dir_relat);

    var dir = std.fs.cwd().openDir(module_dir, .{ .iterate = true }) catch |err| {
        log.err("Could not open dynamic modules dir {}", .{err});
        return err;
    };
    defer dir.close();

    var modules = cetech1.ArrayList([:0]const u8){};
    defer modules.deinit(allocator);

    var iterator = dir.iterate();
    while (try iterator.next()) |path| {
        const basename = std.fs.path.basename(path.name);
        if (!isDynamicModule(basename)) continue;

        const full_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ module_dir_relat, path.name });

        try modules.append(allocator, full_path);
    }

    std.sort.insertion([:0]const u8, modules.items, {}, lessThanStr);
    for (modules.items) |full_path| {
        log.warn("Loading dynamic module from {s}", .{full_path});

        const dyn_lib_info = _loadDynLib(full_path) catch continue;

        try _dyn_modules_map.put(_allocator, dyn_lib_info.full_path, dyn_lib_info);
        try addDynamicModule(.{ .name = dyn_lib_info.name, .module_fce = dyn_lib_info.symbol }, dyn_lib_info.full_path);

        allocator.free(full_path);
    }
}

pub fn reloadAllIfNeeded(allocator: std.mem.Allocator) !bool {
    var zone_ctx = profiler_private.ztracy.ZoneN(@src(), "reloadAllIfNeeded");
    defer zone_ctx.End();

    const keys = _dyn_modules_map.keys();
    const value = _dyn_modules_map.values();

    var to_reload = cetech1.ArrayList([]const u8){};
    defer to_reload.deinit(allocator);

    const dyn_modules_map_n = _dyn_modules_map.count();
    for (0..dyn_modules_map_n) |i| {
        const k = keys[dyn_modules_map_n - 1 - i];
        const v = value[dyn_modules_map_n - 1 - i];

        const f = std.fs.cwd().openFile(k, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => {
                continue;
            },
            else => |e| return e,
        };
        defer f.close();
        const f_stat = try f.stat();

        if (f_stat.mtime > v.mtime) {
            try to_reload.append(allocator, k);
        }
    }
    const modules_reloaded = to_reload.items.len != 0;

    if (modules_reloaded) {
        log.info("These dynamic modules need reload:", .{});
        for (to_reload.items) |k| {
            log.info(" +- {s}", .{k});
        }

        for (to_reload.items) |k| {
            log.info("Reloading module {s}", .{k});

            //unload old
            var old_module_desc = _getModule(getModuleName(k)).?;

            const alloc_item = _modules_allocator_map.getPtr(old_module_desc.desc.name).?;

            if (!old_module_desc.desc.module_fce(@ptrCast(&apidb.api), @ptrCast(&alloc_item.*.allocator), false, true)) {
                log.err("Problem with unload old module {s}", .{k});
                continue;
            }

            var v_ptr = _dyn_modules_map.getPtr(k).?;
            v_ptr.close();

            //load new
            var new_dyn_lib_info = _loadDynLib(k) catch continue;
            if (!new_dyn_lib_info.symbol(@ptrCast(&apidb.api), @ptrCast(&alloc_item.*.allocator), true, true)) {
                log.err("Problem with load new module {s}", .{k});
                continue;
            }
            const v = _dyn_modules_map.get(k).?;
            _allocator.free(new_dyn_lib_info.full_path);
            _allocator.free(new_dyn_lib_info.name);
            new_dyn_lib_info.full_path = v.full_path;
            new_dyn_lib_info.name = v.name;
            v_ptr.* = new_dyn_lib_info;

            old_module_desc.desc.module_fce = new_dyn_lib_info.symbol;
        }
    }

    return modules_reloaded;
}

pub fn dumpModules() void {
    log.info("Loaded modules:", .{});

    for (_modules_map.values()) |*it| {
        if (it.full_path) |module_path| {
            log.info("\t- {s} [{s}]", .{ it.desc.name, module_path });
        } else {
            log.info("\t- {s} [static]", .{it.desc.name});
        }
    }
}

test "Can register module" {
    const allocator = std.testing.allocator;

    try init(allocator);
    defer deinit();

    const Module1 = struct {
        var called: bool = false;

        fn load_module(_apidb: *const cetech1.apidb.ApiDbAPI, _a: *const std.mem.Allocator, load: bool, reload: bool) callconv(.C) bool {
            _ = _apidb;
            _ = _a;
            _ = reload;
            _ = load;
            _ = _a;
            called = true;
            return true;
        }
    };

    var modules = [_]public.ModuleDesc{.{ .name = "module1", .module_fce = @ptrCast(&Module1.load_module) }};
    try addModules(&modules);
    try loadAll();

    try std.testing.expect(Module1.called);
}
