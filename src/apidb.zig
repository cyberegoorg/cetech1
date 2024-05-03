// TODO: Uber shit need rework...
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

const cetech1 = @import("cetech1");
const strid = cetech1.strid;

const public = cetech1.apidb;

test {
    _ = std.testing.refAllDecls(@import("apidb_test.zig"));
}

const module_name = .apidb;

const log = std.log.scoped(module_name);

const ApiItem = struct {
    api_ptr: []u8,
    api_size: usize,
};

const ApiHashMap = std.AutoArrayHashMap(strid.StrId64, ApiItem);
const ApiHashMapPool = std.heap.MemoryPool(ApiHashMap);
const LanguagesApiHashMap = std.AutoArrayHashMap(strid.StrId64, *ApiHashMap);

const InterfaceImplList = std.ArrayList(*const anyopaque);
const InterfaceHashMap = std.AutoArrayHashMap(strid.StrId64, InterfaceImplList);
const InterfaceGen = std.AutoArrayHashMap(strid.StrId64, u64);

const GlobalVarMap = std.AutoArrayHashMap(strid.StrId64, []u8);
const Api2Modules = std.AutoArrayHashMap(strid.StrId64, []const u8);

const ModuleInfo = struct {
    const Self = @This();
    module_name: []const u8,
    provided_api: std.StringArrayHashMap(void),
    need_api: std.StringArrayHashMap(void),

    fn init(allocator: std.mem.Allocator, module: []const u8) !Self {
        return .{
            .module_name = module,
            .provided_api = std.StringArrayHashMap(void).init(allocator),
            .need_api = std.StringArrayHashMap(void).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        for (self.provided_api.keys()) |keys| {
            _allocator.free(keys);
        }

        for (self.need_api.keys()) |keys| {
            _allocator.free(keys);
        }

        self.provided_api.deinit();
        self.need_api.deinit();
    }

    fn addProvidedApi(self: *Self, api_name: []const u8) !void {
        if (self.provided_api.contains(api_name)) return;
        try self.provided_api.put(try _allocator.dupe(u8, api_name), {});
    }

    fn addNeedApi(self: *Self, api_name: []const u8) !void {
        if (self.need_api.contains(api_name)) return;
        try self.need_api.put(try _allocator.dupe(u8, api_name), {});
    }
};
const ModuleInfoMap = std.AutoArrayHashMap(strid.StrId64, ModuleInfo);

pub var api = public.ApiDbAPI{
    .globalVarFn = globalVar,
    .setApiOpaqueueFn = setApiOpaqueue,
    .getApiOpaaqueFn = getApiOpaque,
    .removeApiFn = removeApi,
    .implInterfaceFn = implInterface,
    .getImplFn = getImpl,
    .removeImplFn = removeImpl,
    .getInterafcesVersionFn = getInterafcesVersion,
};

var _init = false;
var _allocator: Allocator = undefined;
var _language_api_map: LanguagesApiHashMap = undefined;
var _api_map_pool: ApiHashMapPool = undefined;

var _interafce_gen: InterfaceGen = undefined;
var _interafce_map: InterfaceHashMap = undefined;
var _global_var_map: GlobalVarMap = undefined;

var _module_info_map: ModuleInfoMap = undefined;
var _api2module: Api2Modules = undefined;

pub fn init(a: Allocator) !void {
    _init = true;
    _allocator = a;
    _language_api_map = LanguagesApiHashMap.init(a);
    _api_map_pool = ApiHashMapPool.init(a);

    _interafce_gen = InterfaceGen.init(a);
    _interafce_map = InterfaceHashMap.init(a);

    _module_info_map = ModuleInfoMap.init(a);

    _global_var_map = GlobalVarMap.init(a);

    _api2module = Api2Modules.init(a);

    try api.setZigApi(module_name, public.ApiDbAPI, &api);
}

pub fn deinit() void {
    for (_language_api_map.values()) |entry| {
        var api_map: *ApiHashMap = entry;

        for (api_map.values()) |api_entry| {
            _allocator.free(api_entry.api_ptr);
        }

        api_map.deinit();
    }

    var it = _global_var_map.iterator();
    while (it.next()) |entry| {
        _allocator.free(entry.value_ptr.*);
    }
    _global_var_map.deinit();

    _api_map_pool.deinit();
    _language_api_map.deinit();

    for (_interafce_map.values()) |*v| {
        v.deinit();
    }

    _interafce_map.deinit();
    _interafce_gen.deinit();
    _api2module.deinit();

    for (_module_info_map.values()) |*v| {
        v.deinit();
    }
    _module_info_map.deinit();

    _init = false;
}

fn _toBytes(ptr: *const anyopaque, ptr_size: usize) []u8 {
    var a: [*]u8 = @ptrFromInt(@intFromPtr(ptr));
    return a[0..ptr_size];
}

fn getOrCreateModuleInfo(module: []const u8) !*ModuleInfo {
    const module_hash = strid.strId64(module);
    if (_module_info_map.getPtr(module_hash)) |mi| return mi;
    const mi = try ModuleInfo.init(_allocator, module);
    try _module_info_map.put(module_hash, mi);
    return _module_info_map.getPtr(module_hash).?;
}

fn globalVar(module: []const u8, var_name: []const u8, size: usize, default: []const u8) !*anyopaque {
    var buff: [256]u8 = undefined;
    const combine_name = try std.fmt.bufPrint(&buff, "{s}:{s}", .{ module, var_name });
    const combine_hash = strid.strId64(combine_name);

    const v = _global_var_map.get(combine_hash);
    if (v == null) {
        const data = try _allocator.alloc(u8, size);
        if (default.len != 0) {
            @memcpy(data, default);
        }
        try _global_var_map.put(combine_hash, data);
        return data.ptr;
    }

    return v.?.ptr;
}

fn setApiOpaqueue(module: []const u8, language: []const u8, api_name: []const u8, api_ptr: *const anyopaque, api_size: usize) !void {
    const language_hash = strid.strId64(language);

    if (!_language_api_map.contains(language_hash)) {
        const api_map = try _api_map_pool.create();
        api_map.* = ApiHashMap.init(_allocator);
        try _language_api_map.put(language_hash, api_map);
    }

    log.debug("Register {s} api '{s}'", .{ language, api_name });

    const api_name_hash = strid.strId64(api_name);

    var mi = try getOrCreateModuleInfo(module);
    try mi.addProvidedApi(api_name);
    try _api2module.put(api_name_hash, mi.module_name);

    const api_ptr_intern = _getApiOpaque(language, api_name, api_size);

    if (api_ptr_intern == null) {
        return;
    }

    const api_map = _language_api_map.getPtr(language_hash).?;
    const old_api_ptr = api_map.*.getPtr(api_name_hash).?;
    @memcpy(old_api_ptr.api_ptr, _toBytes(api_ptr, api_size));
}

fn _getApiOpaque(language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque {
    const language_hash = strid.strId64(language);

    if (!_language_api_map.contains(language_hash)) {
        const api_map = _api_map_pool.create() catch return null;
        api_map.* = ApiHashMap.init(_allocator);
        _language_api_map.put(language_hash, api_map) catch return null;
    }
    const api_name_hash = strid.strId64(api_name);

    const api_map = _language_api_map.getPtr(language_hash).?;

    const api_ptr = api_map.*.get(api_name_hash);

    if (api_ptr == null) {
        const api_data = _allocator.alloc(u8, api_size) catch return null;
        @memset(api_data, 0);
        api_map.*.put(api_name_hash, ApiItem{ .api_ptr = api_data, .api_size = api_size }) catch return null;
        return api_data.ptr;
    }

    return api_ptr.?.api_ptr.ptr;
}

fn getApiOpaque(module: []const u8, language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque {
    const ret = _getApiOpaque(language, api_name, api_size);

    var mi = getOrCreateModuleInfo(module) catch return null;
    mi.addNeedApi(api_name) catch return null;

    return ret;
}

fn removeApi(module: []const u8, language: []const u8, api_name: []const u8) void {
    _ = module;
    const language_hash = strid.strId64(language);

    var api_map = _language_api_map.get(language_hash);
    if (api_map == null) {
        return;
    }

    const api_name_hash = strid.strId64(api_name);

    const api_ptr = api_map.?.get(api_name_hash);

    if (api_ptr == null) {
        return;
    }

    @memset(api_ptr.?.api_ptr, 0);
}

fn increaseIfaceGen(interface_name: strid.StrId64) void {
    const iface_gen = _interafce_gen.getPtr(interface_name).?;
    iface_gen.* += 1;
}

fn getInterafcesVersion(interface_name: strid.StrId64) u64 {
    const iface_gen = _interafce_gen.getPtr(interface_name);
    if (iface_gen == null) return 0;
    return iface_gen.?.*;
}

pub fn dumpGlobalVar() void {
    // log.info("GLOBAL APIDB VARIABLES", .{});

    // var it = _global_var_map.iterator();
    // while (it.next()) |entry| {
    //     log.info(" +- {s}", .{entry.key_ptr.*});
    // }
}

fn implInterface(module: []const u8, interface_name: strid.StrId64, impl_ptr: *const anyopaque) anyerror!void {
    _ = module; // autofix
    if (!_interafce_map.contains(interface_name)) {
        try _interafce_map.put(interface_name, InterfaceImplList.init(_allocator));
        try _interafce_gen.put(interface_name, 0);
    }

    var impl_list = _interafce_map.getPtr(interface_name).?;
    try impl_list.append(impl_ptr);

    increaseIfaceGen(interface_name);
}

fn getImpl(allocator: std.mem.Allocator, interface_name: strid.StrId64) ![]*const anyopaque {
    if (_interafce_map.getPtr(interface_name)) |impl_list| {
        return allocator.dupe(*const anyopaque, impl_list.items);
    }
    return allocator.dupe(*const anyopaque, &.{});
}

fn removeImpl(module: []const u8, interface_name: strid.StrId64, impl_ptr: *const anyopaque) void {
    _ = module;
    var impl_list = _interafce_map.getPtr(interface_name);

    if (impl_list == null) {
        return;
    }

    const idx = std.mem.indexOf(*const anyopaque, impl_list.?.items, &.{impl_ptr}) orelse return;
    _ = impl_list.?.swapRemove(idx);

    increaseIfaceGen(interface_name);
}

pub fn dumpApi() void {
    // log.debug("SUPPORTED API", .{});

    // var lang_iter = _language_api_map.iterator();
    // while (lang_iter.next()) |lang_entry| {
    //     log.debug(" +- LANG {s}", .{lang_entry.key_ptr.*});

    //     var api_iter = lang_entry.value_ptr.*.iterator();
    //     while (api_iter.next()) |api_entry| {
    //         log.debug("     +- {s}", .{api_entry.key_ptr.*});
    //     }
    // }
}

pub fn writeApiGraphD2(out_path: []const u8) !void {
    var dot_file = try std.fs.cwd().createFile(out_path, .{});
    defer dot_file.close();

    var bw = std.io.bufferedWriter(dot_file.writer());
    defer bw.flush() catch undefined;
    const writer = bw.writer();

    // write header
    _ = try writer.write("vars: {d2-config: {layout-engine: elk}}\n\n");

    for (_module_info_map.values()) |module_info| {
        const name = module_info.module_name;

        try writer.print("{s} : {{\n", .{name});

        for (module_info.provided_api.keys()) |api_str| {
            try writer.print("  {s}\n", .{api_str});
        }
        try writer.print("}}\n", .{});

        for (module_info.need_api.keys()) |api_str| {
            if (_api2module.get(strid.strId64(api_str))) |api_module_name| {
                try writer.print("{s}->{s}: {s}\n", .{ name, api_module_name, api_str });
            }
        }
    }
}
