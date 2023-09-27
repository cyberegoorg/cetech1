//! ApiDbAPI is main api db and purpose is shared api/interafce across all part of enfine+language
//! API is struct with pointers to functions.
//! Interaface is similiar to API but Interaface can have multiple implementation and must be valid C struct because he is shared across langugage.

const std = @import("std");
const c = @import("c.zig").c;

pub const ApiDbAPI = struct {
    const Self = @This();

    pub const lang_zig = "zig";
    pub const lang_c = "c";

    pub inline fn globalVar(self: *Self, comptime T: type, module_name: []const u8, var_name: []const u8) !*T {
        return @ptrFromInt(@intFromPtr(try self.globalVarFn.?(module_name, var_name, @sizeOf(T))));
    }

    pub inline fn setApi(self: *Self, comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *T) !void {
        return try self.setApiOpaqueueFn.?(language, api_name, api_ptr, @sizeOf(T));
    }

    pub inline fn getApi(self: *Self, comptime T: type, language: []const u8, api_name: []const u8) ?*T {
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn.?(language, api_name, @sizeOf(T))));
    }

    pub inline fn setOrRemoveCApi(self: *Self, comptime T: type, api_ptr: *T, load: bool, reload: bool) !void {
        if (load) {
            return self.setApi(T, lang_c, _sanitizeApiName(T), api_ptr);
        } else if (!reload) {
            return self.removeApiFn.?(lang_c, _sanitizeApiName(T));
        }
    }

    pub inline fn setOrRemoveZigApi(self: *Self, comptime T: type, api_ptr: *T, load: bool, reload: bool) !void {
        if (load) {
            return self.setZigApi(T, api_ptr);
        } else if (!reload) {
            return self.removeZigApi(T);
        }
    }

    pub inline fn implOrRemove(self: *Self, comptime T: type, impl_ptr: *T, load: bool, reload: bool) !void {
        _ = reload;
        if (load) {
            return self.implInterface(T, impl_ptr);
        } else {
            return self.removeImpl(T, impl_ptr);
        }
    }

    pub inline fn setZigApi(self: *Self, comptime T: type, api_ptr: *T) !void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return try self.setApiOpaqueueFn.?(lang_zig, name_iter.first(), api_ptr, @sizeOf(T));
    }

    pub inline fn getZigApi(self: *Self, comptime T: type) ?*T {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn.?(lang_zig, name_iter.first(), @sizeOf(T))));
    }

    pub inline fn removeZigApi(self: *Self, comptime T: type) void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        self.removeApiFn.?(lang_zig, name_iter.first());
    }

    pub inline fn implInterface(self: *Self, comptime T: type, impl_ptr: *anyopaque) !void {
        return self.implInterfaceFn.?(_sanitizeApiName(T), impl_ptr);
    }

    pub inline fn toInterface(comptime T: type, iter: *const c.ct_apidb_impl_iter_t) *T {
        return @ptrFromInt(@intFromPtr(iter.interface));
    }

    pub inline fn getFirstImpl(self: *Self, comptime T: type) ?*const c.ct_apidb_impl_iter_t {
        return self.getFirstImplFn.?(_sanitizeApiName(T));
    }

    pub inline fn getLastImpl(self: *Self, comptime T: type) ?*const c.ct_apidb_impl_iter_t {
        return self.getLastImplFn.?(_sanitizeApiName(T));
    }

    pub inline fn removeImpl(self: *Self, comptime T: type, impl_ptr: *anyopaque) void {
        self.removeImplFn.?(_sanitizeApiName(T), impl_ptr);
    }

    pub inline fn getInterafceGen(self: *Self, comptime T: type) u64 {
        return self.getInterafceGenFn.?(_sanitizeApiName(T));
    }

    globalVarFn: ?*const fn (module: []const u8, var_name: []const u8, size: usize) anyerror!*anyopaque,
    setApiOpaqueueFn: ?*const fn (language: []const u8, api_name: []const u8, api_ptr: *anyopaque, api_size: usize) anyerror!void,
    getApiOpaaqueFn: ?*const fn (language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque,
    removeApiFn: ?*const fn (language: []const u8, api_name: []const u8) void,
    implInterfaceFn: ?*const fn (interface_name: []const u8, impl_ptr: *anyopaque) anyerror!void,
    getFirstImplFn: ?*const fn (interface_name: []const u8) ?*const c.ct_apidb_impl_iter_t,
    getLastImplFn: ?*const fn (interface_name: []const u8) ?*const c.ct_apidb_impl_iter_t,
    removeImplFn: ?*const fn (interface_name: []const u8, impl_ptr: *anyopaque) void,
    getInterafceGenFn: ?*const fn (interface_name: []const u8) u64,
};

inline fn _sanitizeApiName(comptime T: type) []const u8 {
    const struct_len = "struct_".len;
    const type_str = @typeName(T);
    var name_iter = std.mem.splitBackwardsAny(u8, type_str, ".");

    const first = name_iter.first();
    const is_struct = std.mem.startsWith(u8, first, "struct_");
    const api_name = if (is_struct) first[struct_len..] else first;
    return api_name;
}
