const std = @import("std");
const c = @import("private/c.zig").c;

const strid = @import("strid.zig");

pub const ct_apidb_api_t = c.ct_apidb_api_t;
pub const ct_allocator_t = c.ct_allocator_t;

/// ApiDbAPI is main api db and purpose is shared api/interafce across all part of enfine+language
/// API is struct with pointers to functions.
/// Interaface is similiar to API but Interaface can have multiple implementation and must be valid C struct because he is shared across langugage.
/// You can create variable that can survive module reload.
/// You can register API for any language.
/// You can implement interface.
pub const ApiDbAPI = struct {
    const Self = @This();

    /// Zig api
    pub const lang_zig = "zig";

    /// C api
    pub const lang_c = "c";

    /// Crete variable that can survive reload.
    pub inline fn globalVar(self: Self, comptime T: type, module_name: []const u8, var_name: []const u8, default: T) !*T {
        const ptr: *T = @ptrFromInt(@intFromPtr(try self.globalVarFn(module_name, var_name, @sizeOf(T), &std.mem.toBytes(default))));
        return ptr;
    }

    /// Register api for given language and api name.
    pub inline fn setApi(self: Self, comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *T) !void {
        return try self.setApiOpaqueueFn(language, api_name, api_ptr, @sizeOf(T));
    }

    /// Unregister api for given language and api name.
    pub inline fn removeApi(self: Self, language: []const u8, api_name: []const u8) void {
        return self.removeApiFn(language, api_name);
    }

    /// Get api for given language.
    /// If api not exist create place holder with zeroed values and return it. (setApi fill the valid pointers)
    pub inline fn getApi(self: Self, comptime T: type, language: []const u8, api_name: []const u8) ?*T {
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn(language, api_name, @sizeOf(T))));
    }

    // Set or remove C API
    pub inline fn setOrRemoveCApi(self: Self, comptime T: type, api_ptr: *T, load: bool) !void {
        if (load) {
            return self.setApi(T, lang_c, _sanitizeApiName(T), api_ptr);
        } else {
            return self.removeApi(lang_c, _sanitizeApiName(T));
        }
    }

    // Set or remove API for given language and api name
    pub inline fn setOrRemoveApi(self: Self, comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *T, load: bool) !void {
        if (load) {
            return self.setApi(T, language, api_name, api_ptr);
        } else {
            return self.removeApi(language, api_name);
        }
    }

    // Set or remove Zig API
    pub inline fn setOrRemoveZigApi(self: Self, comptime T: type, api_ptr: *T, load: bool) !void {
        if (load) {
            return self.setZigApi(T, api_ptr);
        } else {
            return self.removeZigApi(T);
        }
    }

    // Implement or remove interface
    pub inline fn implOrRemove(self: Self, comptime T: type, impl_ptr: *T, load: bool) !void {
        if (load) {
            return self.implInterface(T, impl_ptr);
        } else {
            return self.removeImpl(T, impl_ptr);
        }
    }

    // Set zig api
    pub inline fn setZigApi(self: Self, comptime T: type, api_ptr: *T) !void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return try self.setApiOpaqueueFn(lang_zig, name_iter.first(), api_ptr, @sizeOf(T));
    }

    // Get zig api
    pub inline fn getZigApi(self: Self, comptime T: type) ?*T {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn(lang_zig, name_iter.first(), @sizeOf(T))));
    }

    // Remove zig api
    pub inline fn removeZigApi(self: Self, comptime T: type) void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        self.removeApiFn(lang_zig, name_iter.first());
    }

    // Implement interface
    pub inline fn implInterface(self: Self, comptime T: type, impl_ptr: *anyopaque) !void {
        return self.implInterfaceFn(T.name_hash, impl_ptr);
    }

    // Cast generic interface to true type
    pub inline fn toInterface(comptime T: type, iter: *const c.ct_apidb_impl_iter_t) *T {
        return @ptrFromInt(@intFromPtr(iter.interface));
    }

    // Get first interface that implement given interface
    pub inline fn getFirstImpl(self: Self, comptime T: type) ?*const c.ct_apidb_impl_iter_t {
        return self.getFirstImplFn(T.name_hash);
    }

    // Get last interface that implement given interface
    pub inline fn getLastImpl(self: Self, comptime T: type) ?*const c.ct_apidb_impl_iter_t {
        return self.getLastImplFn(T.name_hash);
    }

    // Remove interface
    pub inline fn removeImpl(self: Self, comptime T: type, impl_ptr: *anyopaque) void {
        self.removeImplFn(T.name_hash, impl_ptr);
    }

    // Get version for given interface.
    // Version is number that is increment every time is interface implementation added or removed
    pub inline fn getInterafcesVersion(self: Self, comptime T: type) u64 {
        return self.getInterafcesVersionFn(T.name_hash);
    }

    //#region Pointers to implementation.
    globalVarFn: *const fn (module: []const u8, var_name: []const u8, size: usize, default: []const u8) anyerror!*anyopaque,
    setApiOpaqueueFn: *const fn (language: []const u8, api_name: []const u8, api_ptr: *anyopaque, api_size: usize) anyerror!void,
    getApiOpaaqueFn: *const fn (language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque,
    removeApiFn: *const fn (language: []const u8, api_name: []const u8) void,
    implInterfaceFn: *const fn (interface_name: strid.StrId64, impl_ptr: *anyopaque) anyerror!void,
    getFirstImplFn: *const fn (interface_name: strid.StrId64) ?*const c.ct_apidb_impl_iter_t,
    getLastImplFn: *const fn (interface_name: strid.StrId64) ?*const c.ct_apidb_impl_iter_t,
    removeImplFn: *const fn (interface_name: strid.StrId64, impl_ptr: *anyopaque) void,
    getInterafcesVersionFn: *const fn (interface_name: strid.StrId64) u64,
    //#endregion
};

// get type name and return only last name withou struct_ prefix for c structs.
fn _sanitizeApiName(comptime T: type) []const u8 {
    const struct_len = "struct_".len;
    const type_str = @typeName(T);
    var name_iter = std.mem.splitBackwardsAny(u8, type_str, ".");
    const first = name_iter.first();
    const is_struct = std.mem.startsWith(u8, first, "struct_");
    const api_name = if (is_struct) first[struct_len..] else first;
    return api_name;
}
