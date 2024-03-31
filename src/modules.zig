// TODO: ubershit DETECTED => cleanup needed

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const c = @import("c.zig").c;
const cetech1 = @import("cetech1");

const module_name = .modules;

const MODULE_PREFIX = "ct_";

const log = std.log.scoped(module_name);

const AllocatorItem = struct {
    tracy: cetech1.profiler.AllocatorProfiler,
    allocator: std.mem.Allocator = undefined,
};
const ModuleAlocatorMap = std.StringArrayHashMap(*AllocatorItem);

const ModuleDesc = struct {
    desc: c.ct_module_desc_t,
    full_path: ?[:0]u8,
};

const DynLibInfo = struct {
    full_path: [:0]u8,
    name: [:0]u8,
    dyn_lib: std.DynLib,
    symbol: *c.ct_module_fce_t,
    mtime: i128,

    pub fn close(self: *@This()) void {
        self.dyn_lib.close();
        //_allocator.free(self.full_path);
    }
};

const ModulesList = std.DoublyLinkedList(ModuleDesc);
const ModulesListNodePool = std.heap.MemoryPool(ModulesList.Node);
const DynModuleHashMap = std.StringArrayHashMap(DynLibInfo);
const ModuleHashMap = std.StringArrayHashMap(ModuleDesc);

var _allocator: Allocator = undefined;
var _modules_map: ModuleHashMap = undefined;
var _dyn_modules_map: DynModuleHashMap = undefined;
var _modules_allocator_map: ModuleAlocatorMap = undefined;

pub fn init(allocator: Allocator) !void {
    _allocator = allocator;
    _dyn_modules_map = DynModuleHashMap.init(allocator);
    _modules_map = ModuleHashMap.init(allocator);
    _modules_allocator_map = ModuleAlocatorMap.init(allocator);
}

pub fn deinit() void {
    for (_modules_allocator_map.values()) |value| {
        _allocator.destroy(value);
    }

    _modules_map.deinit();
    _modules_allocator_map.deinit();
    _dyn_modules_map.deinit();
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
    var name_with_ext = std.mem.splitBackwards(u8, basename, MODULE_PREFIX);
    return std.fs.path.stem(name_with_ext.first());
}

pub fn addModules(modules: []const c.ct_module_desc_t) !void {
    for (modules) |v| {
        try _modules_map.put(std.mem.span(v.name), .{ .desc = v, .full_path = null });
    }
}

pub fn addDynamicModule(desc: c.ct_module_desc_t, full_path: ?[:0]u8) !void {
    try _modules_map.put(std.mem.span(desc.name), .{ .desc = desc, .full_path = full_path });
}

pub fn loadAll() !void {
    for (_modules_map.values()) |*it| {
        var module_desc = it;

        if (module_desc.desc.module_fce == null) {
            log.err("Module {s} hash null load fce", .{module_desc.desc.name});
            continue;
        }

        var alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(module_desc.desc.name));
        if (alloc_item == null) {
            var item_ptr = try _allocator.create(AllocatorItem);
            item_ptr.* = AllocatorItem{
                .tracy = cetech1.profiler.AllocatorProfiler.init(
                    &profiler.api,
                    _allocator,
                    module_desc.desc.name[0..std.mem.len(module_desc.desc.name) :0],
                ),
            };
            item_ptr.*.allocator = item_ptr.tracy.allocator();

            try _modules_allocator_map.put(cetech1.fromCstr(module_desc.desc.name), item_ptr);
            alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(module_desc.desc.name));
        }

        if (0 == module_desc.desc.module_fce.?(&apidb.apidb_global_c, @ptrCast(@alignCast(&alloc_item.?.*.allocator)), 1, 0)) {
            log.err("Problem with load module {s}", .{module_desc.desc.name});
        }
    }
}

pub fn unloadAll() !void {
    for (_modules_map.values()) |*it| {
        const alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(it.desc.name)).?;

        if (0 == it.desc.module_fce.?(&apidb.apidb_global_c, @ptrCast(&alloc_item.*.allocator), 0, 0)) {
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

    const symbol = dll.lookup(*c.ct_module_fce_t, load_fce_name);
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

pub fn loadDynModules() !void {
    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const tmp_allocator = fba.allocator();

    const tmp_allocator2 = _allocator;

    // TODO remove this fucking long alloc hell
    const exe_dir = try std.fs.selfExeDirPathAlloc(tmp_allocator2);
    defer tmp_allocator2.free(exe_dir);

    const module_dir = try std.fs.path.join(tmp_allocator2, &.{ exe_dir, "..", "lib" });
    defer tmp_allocator2.free(module_dir);

    const cwd_path = try std.fs.cwd().realpathAlloc(tmp_allocator2, ".");
    defer tmp_allocator2.free(cwd_path);

    const module_dir_relat = try std.fs.path.relative(tmp_allocator2, cwd_path, module_dir);
    defer tmp_allocator2.free(module_dir_relat);

    var dir = std.fs.cwd().openDir(module_dir, .{ .iterate = true }) catch |err| {
        log.err("Could not open dynamic modules dir {}", .{err});
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |path| {
        fba.reset();

        const basename = std.fs.path.basename(path.name);
        if (!isDynamicModule(basename)) continue;

        const full_path = try std.fs.path.joinZ(tmp_allocator, &[_][]const u8{ module_dir_relat, path.name });

        log.info("Loading module from {s}", .{full_path});

        const dyn_lib_info = _loadDynLib(full_path) catch continue;

        try _dyn_modules_map.put(dyn_lib_info.full_path, dyn_lib_info);
        try addDynamicModule(.{ .name = dyn_lib_info.name.ptr, .module_fce = dyn_lib_info.symbol }, dyn_lib_info.full_path);
    }
}

pub fn reloadAllIfNeeded(allocator: std.mem.Allocator) !bool {
    const keys = _dyn_modules_map.keys();
    const value = _dyn_modules_map.values();

    var to_reload = std.ArrayList([]const u8).init(allocator);
    defer to_reload.deinit();

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
            try to_reload.append(k);
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

            const alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(old_module_desc.desc.name)).?;

            if (0 == old_module_desc.desc.module_fce.?(&apidb.apidb_global_c, @ptrCast(&alloc_item.*.allocator), 0, 1)) {
                log.err("Problem with unload old module {s}", .{k});
                continue;
            }

            var v_ptr = _dyn_modules_map.getPtr(k).?;
            v_ptr.close();

            //load new
            var new_dyn_lib_info = _loadDynLib(k) catch continue;
            if (0 == new_dyn_lib_info.symbol(&apidb.apidb_global_c, @ptrCast(&alloc_item.*.allocator), 1, 1)) {
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
    log.info("LOADED MODULES", .{});

    for (_modules_map.values()) |*it| {
        if (it.full_path) |module_path| {
            log.info(" +- {s} [{s}]", .{ it.desc.name, module_path });
        } else {
            log.info(" +- {s} [static]", .{it.desc.name});
        }
    }
}

test "Can register module" {
    const allocator = std.testing.allocator;

    try init(allocator);
    defer deinit();

    const Module1 = struct {
        var called: bool = false;

        fn load_module(_apidb: ?*const c.ct_apidb_api_t, _a: ?*const c.ct_allocator_t, load: u8, reload: u8) callconv(.C) u8 {
            _ = _apidb;
            _ = _a;
            _ = reload;
            _ = load;
            _ = _a;
            called = true;
            return 1;
        }
    };

    var modules = [_]c.ct_module_desc_t{.{ .name = "module1", .module_fce = &Module1.load_module }};
    try addModules(&modules);
    try loadAll();

    try std.testing.expect(Module1.called);
}
