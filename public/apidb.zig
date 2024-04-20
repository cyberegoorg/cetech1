const std = @import("std");
const c = @import("c.zig").c;

const strid = @import("strid.zig");

pub const ImplIter = extern struct {
    interface: *const anyopaque,
    next: ?*ImplIter,
    prev: ?*ImplIter,
};

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

    /// Crete variable that can survive reload.
    pub fn globalVar(self: Self, comptime T: type, comptime module: @Type(.EnumLiteral), var_name: []const u8, default: T) !*T {
        const ptr: *T = @ptrFromInt(@intFromPtr(try self.globalVarFn(@tagName(module), var_name, @sizeOf(T), &std.mem.toBytes(default))));
        return ptr;
    }

    /// Register api for given language and api name.
    pub fn setApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *const T) !void {
        return try self.setApiOpaqueueFn(@tagName(module), language, api_name, api_ptr, @sizeOf(T));
    }

    /// Unregister api for given language and api name.
    pub fn removeApi(self: Self, comptime module: @Type(.EnumLiteral), language: []const u8, api_name: []const u8) void {
        return self.removeApiFn(@tagName(module), language, api_name);
    }

    /// Get api for given language.
    /// If api not exist create place holder with zeroed values and return it. (setApi fill the valid pointers)
    pub fn getApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, language: []const u8, api_name: []const u8) ?*const T {
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn(@tagName(module), language, api_name, @sizeOf(T))));
    }

    // Set or remove API for given language and api name
    pub fn setOrRemoveApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *const T, load: bool) !void {
        if (load) {
            return self.setApi(module, T, language, api_name, api_ptr);
        } else {
            return self.removeApi(module, language, api_name);
        }
    }

    // Set or remove Zig API
    pub fn setOrRemoveZigApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, api_ptr: *const T, load: bool) !void {
        if (load) {
            return self.setZigApi(module, T, api_ptr);
        } else {
            return self.removeZigApi(module, T);
        }
    }

    // Implement or remove interface
    pub fn implOrRemove(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, impl_ptr: *const T, load: bool) !void {
        if (load) {
            return self.implInterface(module, T, impl_ptr);
        } else {
            return self.removeImpl(module, T, impl_ptr);
        }
    }

    // Set zig api
    pub fn setZigApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, api_ptr: *const T) !void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return try self.setApiOpaqueueFn(@tagName(module), lang_zig, name_iter.first(), api_ptr, @sizeOf(T));
    }

    // Get zig api
    pub fn getZigApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type) ?*const T {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn(@tagName(module), lang_zig, name_iter.first(), @sizeOf(T))));
    }

    // Remove zig api
    pub fn removeZigApi(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type) void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        self.removeApiFn(@tagName(module), lang_zig, name_iter.first());
    }

    // Implement interface
    pub fn implInterface(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, impl_ptr: *const anyopaque) !void {
        return self.implInterfaceFn(@tagName(module), T.name_hash, impl_ptr);
    }

    // Cast generic interface to true type
    pub fn toInterface(comptime T: type, iter: *const ImplIter) *const T {
        return @ptrFromInt(@intFromPtr(iter.interface));
    }

    // Get first interface that implement given interface
    pub fn getFirstImpl(self: Self, comptime T: type) ?*const ImplIter {
        return self.getFirstImplFn(T.name_hash);
    }

    // Get last interface that implement given interface
    pub fn getLastImpl(self: Self, comptime T: type) ?*const ImplIter {
        return self.getLastImplFn(T.name_hash);
    }

    // Remove interface
    pub fn removeImpl(self: Self, comptime module: @Type(.EnumLiteral), comptime T: type, impl_ptr: *const anyopaque) void {
        self.removeImplFn(@tagName(module), T.name_hash, impl_ptr);
    }

    // Get version for given interface.
    // Version is number that is increment every time is interface implementation added or removed
    pub fn getInterafcesVersion(self: Self, comptime T: type) u64 {
        return self.getInterafcesVersionFn(T.name_hash);
    }

    //#region Pointers to implementation.
    globalVarFn: *const fn (module: []const u8, var_name: []const u8, size: usize, default: []const u8) anyerror!*anyopaque,
    setApiOpaqueueFn: *const fn (module: []const u8, language: []const u8, api_name: []const u8, api_ptr: *const anyopaque, api_size: usize) anyerror!void,
    getApiOpaaqueFn: *const fn (module: []const u8, language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque,
    removeApiFn: *const fn (module: []const u8, language: []const u8, api_name: []const u8) void,
    implInterfaceFn: *const fn (module: []const u8, interface_name: strid.StrId64, impl_ptr: *const anyopaque) anyerror!void,
    getFirstImplFn: *const fn (interface_name: strid.StrId64) ?*const ImplIter,
    getLastImplFn: *const fn (interface_name: strid.StrId64) ?*const ImplIter,
    removeImplFn: *const fn (module: []const u8, interface_name: strid.StrId64, impl_ptr: *const anyopaque) void,
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
