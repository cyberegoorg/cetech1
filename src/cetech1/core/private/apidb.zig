const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const StringArrayHashMap = std.StringArrayHashMap;

const cetech1 = @import("../cetech1.zig");
const strid = cetech1.strid;

const log = @import("log.zig");
const public = @import("../apidb.zig");
const c = @import("c.zig");

const MODULE_NAME = "apidb";

const ApiItem = struct {
    api_ptr: []u8,
    api_size: usize,
};

const ApiHashMap = StringHashMap(ApiItem);
const ApiHashMapPool = std.heap.MemoryPool(ApiHashMap);
const LanguagesApiHashMap = StringHashMap(*ApiHashMap);

const InterfaceImplList = std.DoublyLinkedList(c.c.ct_apidb_impl_iter_t);
const InterfaceImplNode = InterfaceImplList.Node;
const IterfaceImplNodePool = std.heap.MemoryPool(InterfaceImplList.Node);
const InterfaceHashMap = std.AutoArrayHashMap(strid.StrId64, InterfaceImplList);
const InterfaceGen = std.AutoArrayHashMap(strid.StrId64, u64);

const GlobalVarMap = StringArrayHashMap([]u8);

pub var api = public.ApiDbAPI{
    .globalVarFn = globalVar,
    .setApiOpaqueueFn = setApiOpaqueue,
    .getApiOpaaqueFn = getApiOpaque,
    .removeApiFn = removeApi,
    .implInterfaceFn = implInterface,
    .getFirstImplFn = getFirstImpl,
    .getLastImplFn = getLastImpl,
    .removeImplFn = removeImpl,
    .getInterafcesVersionFn = getInterafcesVersion,
};

var _allocator: Allocator = undefined;
var _language_api_map: LanguagesApiHashMap = undefined;
var _api_map_pool: ApiHashMapPool = undefined;

var _interafce_gen: InterfaceGen = undefined;
var _interafce_map: InterfaceHashMap = undefined;
var _interface_node_pool: IterfaceImplNodePool = undefined;
var _global_var_map: GlobalVarMap = undefined;

pub fn init(a: Allocator) !void {
    _allocator = a;
    _language_api_map = LanguagesApiHashMap.init(a);
    _api_map_pool = ApiHashMapPool.init(a);

    _interafce_gen = InterfaceGen.init(a);
    _interafce_map = InterfaceHashMap.init(a);
    _interface_node_pool = IterfaceImplNodePool.init(a);

    _global_var_map = GlobalVarMap.init(a);

    try api.setZigApi(public.ApiDbAPI, &api);
}

pub fn deinit() void {
    var iter = _language_api_map.valueIterator();
    while (iter.next()) |entry| {
        var api_map: *ApiHashMap = entry.*;

        var api_iter = api_map.valueIterator();
        while (api_iter.next()) |api_entry| {
            _allocator.free(api_entry.api_ptr);
        }

        api_map.deinit();
    }

    var it = _global_var_map.iterator();
    while (it.next()) |entry| {
        _allocator.free(entry.key_ptr.*);
        _allocator.free(entry.value_ptr.*);
    }

    _global_var_map.deinit();

    _api_map_pool.deinit();
    _language_api_map.deinit();

    _interafce_map.deinit();
    _interface_node_pool.deinit();
    _interafce_gen.deinit();
}

fn _toBytes(ptr: *anyopaque, ptr_size: usize) []u8 {
    var a: [*]u8 = @ptrFromInt(@intFromPtr(ptr));
    return a[0..ptr_size];
}

fn globalVar(module: []const u8, var_name: []const u8, size: usize, default: []const u8) !*anyopaque {
    const combine_name = try std.fmt.allocPrint(_allocator, "{s}:{s}", .{ module, var_name });
    const v = _global_var_map.get(combine_name);
    if (v == null) {
        const data = try _allocator.alloc(u8, size);
        @memcpy(data, default);
        try _global_var_map.put(combine_name, data);
        return data.ptr;
    }

    _allocator.free(combine_name);
    return v.?.ptr;
}

fn setApiOpaqueue(language: []const u8, api_name: []const u8, api_ptr: *anyopaque, api_size: usize) !void {
    if (!_language_api_map.contains(language)) {
        const api_map = try _api_map_pool.create();
        api_map.* = ApiHashMap.init(_allocator);
        try _language_api_map.put(language, api_map);
    }

    log.api.debug(MODULE_NAME, "Register {s} api '{s}'", .{ language, api_name });

    const api_ptr_intern = getApiOpaque(language, api_name, api_size);

    if (api_ptr_intern == null) {
        return;
    }

    const api_map = _language_api_map.getPtr(language).?;
    const old_api_ptr = api_map.*.getPtr(api_name).?;
    @memcpy(old_api_ptr.api_ptr, _toBytes(api_ptr, api_size));
}

fn getApiOpaque(language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque {
    if (!_language_api_map.contains(language)) {
        const api_map = _api_map_pool.create() catch return null;
        api_map.* = ApiHashMap.init(_allocator);
        _language_api_map.put(language, api_map) catch return null;
    }

    const api_map = _language_api_map.getPtr(language).?;

    const api_ptr = api_map.*.get(api_name);

    if (api_ptr == null) {
        const api_data = _allocator.alloc(u8, api_size) catch return null;
        @memset(api_data, 0);
        api_map.*.put(api_name, ApiItem{ .api_ptr = api_data, .api_size = api_size }) catch return null;
        return api_data.ptr;
    }

    return api_ptr.?.api_ptr.ptr;
}

fn removeApi(language: []const u8, api_name: []const u8) void {
    var api_map = _language_api_map.get(language);
    if (api_map == null) {
        return;
    }

    const api_ptr = api_map.?.get(api_name);

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
    log.api.info(MODULE_NAME, "GLOBAL APIDB VARIABLES", .{});

    var it = _global_var_map.iterator();
    while (it.next()) |entry| {
        log.api.info(MODULE_NAME, " +- {s}", .{entry.key_ptr.*});
    }
}

/// !!! must be C compatible fce
fn implInterface(interface_name: strid.StrId64, impl_ptr: *anyopaque) anyerror!void {
    if (!_interafce_map.contains(interface_name)) {
        try _interafce_map.put(interface_name, InterfaceImplList{});
        try _interafce_gen.put(interface_name, 0);
    }

    var impl_list = _interafce_map.getPtr(interface_name).?;
    var last = impl_list.last;
    var prev: ?*c.c.ct_apidb_impl_iter_t = null;

    if (last != null) {
        prev = &last.?.data;
    }

    const c_iter = c.c.ct_apidb_impl_iter_t{ .interface = impl_ptr, .next = null, .prev = prev };

    var node = try _interface_node_pool.create();
    node.* = InterfaceImplNode{ .data = c_iter };

    if (last != null) {
        last.?.data.next = &node.data;
    }

    impl_list.append(node);

    //log.api.debug(MODULE_NAME, "Register interface '{s}'", .{interface_name});

    increaseIfaceGen(interface_name);
}

fn getImpl(comptime T: type, interface_name: []const u8) ?*T {
    const impl_list = _interafce_map.getPtr(interface_name);

    if (impl_list == null) {
        return null;
    }

    const first = impl_list.?.first;
    if (first == null) {
        return null;
    }
    return @ptrFromInt(@intFromPtr(first.?.data.interface));
}

fn getFirstImpl(interface_name: strid.StrId64) ?*const c.c.ct_apidb_impl_iter_t {
    var impl_list = _interafce_map.getPtr(interface_name);

    if (impl_list == null) {
        return null;
    }

    if (impl_list.?.first == null) {
        return null;
    }

    return &impl_list.?.first.?.data;
}

fn getLastImpl(interface_name: strid.StrId64) ?*const c.c.ct_apidb_impl_iter_t {
    var impl_list = _interafce_map.getPtr(interface_name);

    if (impl_list == null) {
        return null;
    }

    if (impl_list.?.last == null) {
        return null;
    }

    return &impl_list.?.last.?.data;
}

fn removeImpl(interface_name: strid.StrId64, impl_ptr: *anyopaque) void {
    var impl_list = _interafce_map.getPtr(interface_name);

    if (impl_list == null) {
        return;
    }

    var it = impl_list.?.first;
    while (it) |node| : (it = node.next) {
        if (node.data.interface != impl_ptr) {
            continue;
        }

        if (node.data.next != null) {
            node.data.next.*.prev = node.data.prev;
        }

        if (node.data.prev != null) {
            node.data.prev.*.next = node.data.next;
        }

        impl_list.?.remove(node);
        break;
    }

    increaseIfaceGen(interface_name);
}

pub fn dumpApi() void {
    log.api.debug(MODULE_NAME, "SUPPORTED API", .{});

    var lang_iter = _language_api_map.iterator();
    while (lang_iter.next()) |lang_entry| {
        log.api.debug(MODULE_NAME, " +- LANG {s}", .{lang_entry.key_ptr.*});

        var api_iter = lang_entry.value_ptr.*.iterator();
        while (api_iter.next()) |api_entry| {
            log.api.debug(MODULE_NAME, "     +- {s}", .{api_entry.key_ptr.*});
        }
    }
}

pub fn dumpInterfaces() void {
    // TODO
    // log.api.debug(MODULE_NAME, "IMPLEMENTED INTERAFCES", .{});

    // var iter = _interafce_map.iterator();
    // while (iter.next()) |entry| {
    //     log.api.debug(MODULE_NAME, " +- {s}", .{entry.key_ptr.*});
    // }
}

pub const apidb_global_c = blk: {
    const c_api = struct {
        const Self = @This();

        pub fn set_api(language: [*c]const u8, api_name: [*c]const u8, api_ptr: ?*anyopaque, api_size: u32) callconv(.C) void {
            setApiOpaqueue(cetech1.fromCstr(language), cetech1.fromCstr(api_name), api_ptr.?, api_size) catch return;
        }
        pub fn get_api(language: [*c]const u8, api_name: [*c]const u8, api_size: u32) callconv(.C) ?*anyopaque {
            return getApiOpaque(cetech1.fromCstr(language), cetech1.fromCstr(api_name), api_size);
        }
        pub fn remove_api(language: [*c]const u8, api_name: [*c]const u8) callconv(.C) void {
            removeApi(cetech1.fromCstr(language), cetech1.fromCstr(api_name));
        }

        pub fn set_or_remove(language: [*c]const u8, api_name: [*c]const u8, api_ptr: ?*anyopaque, api_size: u32, load: bool, reload: bool) callconv(.C) void {
            if (load) {
                Self.set_api(language, api_name, api_ptr, api_size);
            } else if (!reload) {
                Self.remove_api(language, api_name);
            }
        }

        pub fn impl_or_remove(interface_name: c.c.ct_strid64_t, api_ptr: ?*anyopaque, load: bool) callconv(.C) void {
            if (load) {
                Self.impl(interface_name, api_ptr);
            } else {
                Self.remove_impl(interface_name, api_ptr);
            }
        }

        pub fn global_var(module: [*c]const u8, var_name: [*c]const u8, size: u32, default: ?*const anyopaque) callconv(.C) ?*anyopaque {
            var def: []const u8 = undefined;
            def.ptr = @ptrCast(default.?);
            def.len = size;
            return globalVar(cetech1.fromCstr(module), cetech1.fromCstr(var_name), size, def) catch return null;
        }

        pub fn impl(interface_name: c.c.ct_strid64_t, api_ptr: ?*anyopaque) callconv(.C) void {
            return implInterface(strid.StrId64.from(c.c.ct_strid64_t, interface_name), api_ptr.?) catch return;
        }
        pub fn remove_impl(interface_name: c.c.ct_strid64_t, api_ptr: ?*anyopaque) callconv(.C) void {
            return removeImpl(strid.StrId64.from(c.c.ct_strid64_t, interface_name), api_ptr.?);
        }
        pub fn get_first_impl(interface_name: c.c.ct_strid64_t) callconv(.C) ?*const c.c.ct_apidb_impl_iter_t {
            return getFirstImpl(strid.StrId64.from(c.c.ct_strid64_t, interface_name));
        }
    };
    break :blk c.c.ct_apidb_api_t{
        .set_api = c_api.set_api,
        .get_api = c_api.get_api,
        .remove_api = c_api.remove_api,
        .set_or_remove = c_api.set_or_remove,
        .impl = c_api.impl,
        .remove_impl = c_api.remove_impl,
        .impl_or_remove = c_api.impl_or_remove,
        .get_first_impl = c_api.get_first_impl,
        .global_var = c_api.global_var,
    };
};
