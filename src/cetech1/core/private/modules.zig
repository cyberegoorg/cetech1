const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const apidb = @import("apidb.zig");
const log = @import("log.zig");
const profiler = @import("profiler.zig");
const c = @import("c.zig").c;
const cetech1 = @import("../cetech1.zig");

const MODULE_NAME = "modules";

const ModulesList = std.DoublyLinkedList(c.ct_module_desc_t);
const ModulesListNodePool = std.heap.MemoryPool(ModulesList.Node);

const AllocatorItem = struct {
    tracy: cetech1.profiler.AllocatorProfiler,
    allocator: std.mem.Allocator = undefined,
};
const ModuleAlocatorMap = std.StringArrayHashMap(*AllocatorItem);

const DynLibInfo = struct {
    full_path: [:0]u8,
    dyn_lib: std.DynLib,
    symbol: *c.ct_module_fce_t,
    mtime: i128,

    pub fn close(self: *@This()) void {
        self.dyn_lib.close();
    }
};

const DynModuleHashMap = std.StringArrayHashMap(DynLibInfo);

fn getDllExtension() []const u8 {
    return switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd => ".so",
        .windows => ".dll",
        .macos, .tvos, .watchos, .ios => ".dylib",
        else => return undefined,
    };
}

var _allocator: Allocator = undefined;
var _modules: ModulesList = undefined;
var _modules_node_pool: ModulesListNodePool = undefined;
var _dyn_modules_map: DynModuleHashMap = undefined;
var _modules_allocator_map: ModuleAlocatorMap = undefined;

pub fn init(allocator: Allocator) !void {
    _allocator = allocator;
    _modules = ModulesList{};
    _modules_node_pool = ModulesListNodePool.init(allocator);
    _dyn_modules_map = DynModuleHashMap.init(allocator);
    _modules_allocator_map = ModuleAlocatorMap.init(allocator);
}

pub fn deinit() void {
    var iter = _dyn_modules_map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.dyn_lib.close();
    }

    for (_modules_allocator_map.values()) |value| {
        _allocator.destroy(value);
    }

    _modules_allocator_map.deinit();
    _dyn_modules_map.deinit();
    _modules_node_pool.deinit();
}

pub fn addModules(modules: []const c.ct_module_desc_t) !void {
    for (modules) |v| {
        var node = try _modules_node_pool.create();
        node.* = ModulesList.Node{ .data = v };
        _modules.append(node);
    }
}

pub fn loadAll() !void {
    var it = _modules.first;
    while (it) |node| : (it = node.next) {
        var module_desc = node.data;

        if (module_desc.module_fce == null) {
            log.api.err(MODULE_NAME, "Module {s} hash null load fce", .{module_desc.name});
            continue;
        }

        var alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(module_desc.name));
        if (alloc_item == null) {
            var item_ptr = try _allocator.create(AllocatorItem);
            item_ptr.* = AllocatorItem{ .tracy = cetech1.profiler.AllocatorProfiler.init(&profiler.api, _allocator, module_desc.name[0..std.mem.len(module_desc.name) :0]) };
            item_ptr.*.allocator = item_ptr.tracy.allocator();

            try _modules_allocator_map.put(cetech1.fromCstr(module_desc.name), item_ptr);
            alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(module_desc.name));
        }

        if (0 == module_desc.module_fce.?(&apidb.apidb_global_c, @ptrCast(@alignCast(&alloc_item.?.*.allocator)), 1, 0)) {
            log.api.err(MODULE_NAME, "Problem with load module {s}", .{module_desc.name});
        }
    }
}

pub fn unloadAll() !void {
    var it = _modules.last;
    while (it) |node| : (it = node.prev) {
        var alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(node.data.name)).?;

        if (0 == node.data.module_fce.?(&apidb.apidb_global_c, @ptrCast(&alloc_item.*.allocator), 0, 1)) {
            log.api.err(MODULE_NAME, "Problem with unload module {s}\n", .{node.data.name});
        }
    }

    var iter = _dyn_modules_map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.close();
    }
}

fn _getModule(name: []const u8) ?*c.ct_module_desc_t {
    var it = _modules.last;
    while (it) |node| : (it = node.prev) {
        if (!std.mem.eql(u8, node.data.name[0..std.mem.len(node.data.name)], name)) {
            continue;
        }

        return &node.data;
    }
    return null;
}

fn getModuleName(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    var name_with_ext = std.mem.splitBackwards(u8, basename, "ct_");
    return std.fs.path.stem(name_with_ext.first());
}

fn _loadDynLib(path: []const u8) !DynLibInfo {
    var dll = std.DynLib.open(path) catch |err| {
        log.api.err(MODULE_NAME, "Error load module from {s} with error {any}\n", .{ path, err });
        return err;
    };

    var load_fce_name: [128:0]u8 = undefined;
    const module_name = getModuleName(path);
    _ = try std.fmt.bufPrintZ(&load_fce_name, "ct_load_module_{s}", .{module_name});

    var symbol = dll.lookup(*c.ct_module_fce_t, &load_fce_name);
    if (symbol == null) {
        log.api.err(MODULE_NAME, "Error find symbol {s} in {s}\n", .{ load_fce_name, path });
        return error.SymbolNotFound;
    }

    const f = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    errdefer f.close();
    const f_stat = try f.stat();
    const mtime = f_stat.mtime;
    f.close();

    const full_path_dup = try _allocator.dupeZ(u8, path);

    return .{
        .full_path = full_path_dup,
        .dyn_lib = dll,
        .symbol = symbol.?,
        .mtime = mtime,
    };
}

pub fn loadDynModules() !void {
    const module_dir = "./zig-out/lib";
    var dir = try std.fs.cwd().openIterableDir(module_dir, .{});
    defer dir.close();

    var iterator = dir.iterate();

    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const tmp_allocator = fba.allocator();

    while (try iterator.next()) |path| {
        fba.reset();

        const basename = std.fs.path.basename(path.name);
        if (!std.mem.startsWith(u8, basename, "ct_")) continue;
        if (!std.mem.endsWith(u8, basename, getDllExtension())) continue;

        var full_path = try std.fs.path.join(tmp_allocator, &[_][]const u8{ module_dir, path.name });

        log.api.debug(MODULE_NAME, "Loading module from {s}", .{full_path});

        var dyn_lib_info = _loadDynLib(full_path) catch continue;

        try _dyn_modules_map.put(dyn_lib_info.full_path, dyn_lib_info);
        try addModules(&[_]c.ct_module_desc_t{.{ .name = dyn_lib_info.full_path, .module_fce = dyn_lib_info.symbol }});
    }
}

pub fn reloadAllIfNeeded() !bool {
    var keys = _dyn_modules_map.keys();
    var value = _dyn_modules_map.values();

    var modules_reloaded = false;

    const dyn_modules_map_n = _dyn_modules_map.count();
    for (0..dyn_modules_map_n) |i| {
        var k = keys[dyn_modules_map_n - 1 - i];
        var v = value[dyn_modules_map_n - 1 - i];

        const f = try std.fs.cwd().openFile(k, .{ .mode = .read_only });
        defer f.close();
        const f_stat = try f.stat();

        if (f_stat.mtime > v.mtime) {
            log.api.debug(MODULE_NAME, "Dynamic module {s} need reload.", .{k});

            //unload old
            var old_module_desc = _getModule(k).?;

            var alloc_item = _modules_allocator_map.getPtr(cetech1.fromCstr(old_module_desc.name)).?;

            if (0 == old_module_desc.module_fce.?(&apidb.apidb_global_c, @ptrCast(&alloc_item.*.allocator), 0, 1)) {
                log.api.err(MODULE_NAME, "Problem with unload old module {s}\n", .{k});
                continue;
            }

            //load new
            var new_dyn_lib_info = _loadDynLib(k) catch continue;
            if (0 == new_dyn_lib_info.symbol(&apidb.apidb_global_c, @ptrCast(&alloc_item.*.allocator), 1, 1)) {
                log.api.err(MODULE_NAME, "Problem with load new module {s}\n", .{k});
                continue;
            }

            var v_ptr = _dyn_modules_map.getPtr(k).?;
            v_ptr.close();
            v_ptr.* = new_dyn_lib_info;

            old_module_desc.module_fce = new_dyn_lib_info.symbol;
            old_module_desc.name = new_dyn_lib_info.full_path;

            modules_reloaded = true;
        }
    }

    return modules_reloaded;
}

pub fn dumpModules() void {
    log.api.info(MODULE_NAME, "LOADED MODULES", .{});
    var it = _modules.first;
    while (it) |node| : (it = node.next) {
        log.api.info(MODULE_NAME, " +- {s}", .{node.data.name});
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
