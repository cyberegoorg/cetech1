const std = @import("std");

const strid = @import("strid.zig");

pub const ImplIter = extern struct {
    interface: *const anyopaque,
    next: ?*ImplIter,
    prev: ?*ImplIter,
};

pub const InterfaceVersion = u64;

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
    pub inline fn globalVar(self: Self, comptime T: type, comptime module: @Type(.enum_literal), var_name: []const u8, default: T) !*T {
        const ptr: *T = @ptrFromInt(@intFromPtr(try self.globalVarFn(@tagName(module), var_name, @sizeOf(T), &std.mem.toBytes(default))));
        return ptr;
    }

    /// Crete variable that can survive reload + always set value
    pub inline fn globalVarValue(self: Self, comptime T: type, comptime module: @Type(.enum_literal), var_name: []const u8, value: T) !*T {
        const ptr: *T = @ptrFromInt(@intFromPtr(try self.globalVarFn(@tagName(module), var_name, @sizeOf(T), &.{})));
        ptr.* = value;
        return ptr;
    }

    /// Register api for given language and api name.
    pub inline fn setApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *const T) !void {
        return try self.setApiOpaqueueFn(@tagName(module), language, api_name, api_ptr, @sizeOf(T));
    }

    /// Unregister api for given language and api name.
    pub inline fn removeApi(self: Self, comptime module: @Type(.enum_literal), language: []const u8, api_name: []const u8) void {
        return self.removeApiFn(@tagName(module), language, api_name);
    }

    /// Get api for given language.
    /// If api not exist create place holder with zeroed values and return it. (setApi fill the valid pointers)
    pub inline fn getApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type, language: []const u8, api_name: []const u8) ?*const T {
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn(@tagName(module), language, api_name, @sizeOf(T))));
    }

    // Set or remove API for given language and api name
    pub inline fn setOrRemoveApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type, language: []const u8, api_name: []const u8, api_ptr: *const T, load: bool) !void {
        if (load) {
            return self.setApi(module, T, language, api_name, api_ptr);
        } else {
            return self.removeApi(module, language, api_name);
        }
    }

    // Set or remove Zig API
    pub inline fn setOrRemoveZigApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type, api_ptr: *const T, load: bool) !void {
        if (load) {
            return self.setZigApi(module, T, api_ptr);
        } else {
            return self.removeZigApi(module, T);
        }
    }

    // Implement or remove interface
    pub inline fn implOrRemove(self: Self, comptime module: @Type(.enum_literal), comptime T: type, impl_ptr: *const T, load: bool) !void {
        if (load) {
            return self.implInterface(module, T, impl_ptr);
        } else {
            return self.removeImpl(module, T, impl_ptr);
        }
    }

    // Set zig api
    pub inline fn setZigApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type, api_ptr: *const T) !void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return try self.setApiOpaqueueFn(@tagName(module), lang_zig, name_iter.first(), api_ptr, @sizeOf(T));
    }

    // Get zig api
    pub inline fn getZigApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type) ?*const T {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        return @ptrFromInt(@intFromPtr(self.getApiOpaaqueFn(@tagName(module), lang_zig, name_iter.first(), @sizeOf(T))));
    }

    // Remove zig api
    pub inline fn removeZigApi(self: Self, comptime module: @Type(.enum_literal), comptime T: type) void {
        var name_iter = std.mem.splitBackwardsAny(u8, @typeName(T), ".");
        self.removeApiFn(@tagName(module), lang_zig, name_iter.first());
    }

    // Implement interface
    pub inline fn implInterface(self: Self, comptime module: @Type(.enum_literal), comptime T: type, impl_ptr: *const T) !void {
        return self.implInterfaceFn(@tagName(module), T.name_hash, impl_ptr);
    }

    // Get all implementation for given interface
    pub inline fn getImpl(self: Self, allocator: std.mem.Allocator, comptime T: type) ![]*const T {
        const impls = try self.getImplFn(allocator, T.name_hash);
        var result: []*const T = undefined;
        result.ptr = @alignCast(@ptrCast(impls.ptr));
        result.len = impls.len;
        return result;
    }

    // Remove interface
    pub inline fn removeImpl(self: Self, comptime module: @Type(.enum_literal), comptime T: type, impl_ptr: *const T) void {
        self.removeImplFn(@tagName(module), T.name_hash, impl_ptr);
    }

    // Get version for given interface.
    // Version is number that is increment every time is interface implementation added or removed
    pub inline fn getInterafcesVersion(self: Self, comptime T: type) InterfaceVersion {
        return self.getInterafcesVersionFn(T.name_hash);
    }

    //#region Pointers to implementation.
    globalVarFn: *const fn (module: []const u8, var_name: []const u8, size: usize, default: []const u8) anyerror!*anyopaque,

    setApiOpaqueueFn: *const fn (module: []const u8, language: []const u8, api_name: []const u8, api_ptr: *const anyopaque, api_size: usize) anyerror!void,
    getApiOpaaqueFn: *const fn (module: []const u8, language: []const u8, api_name: []const u8, api_size: usize) ?*anyopaque,
    removeApiFn: *const fn (module: []const u8, language: []const u8, api_name: []const u8) void,

    implInterfaceFn: *const fn (module: []const u8, interface_name: strid.StrId64, impl_ptr: *const anyopaque) anyerror!void,
    getImplFn: *const fn (allocator: std.mem.Allocator, interface_name: strid.StrId64) anyerror![]*const anyopaque,
    removeImplFn: *const fn (module: []const u8, interface_name: strid.StrId64, impl_ptr: *const anyopaque) void,
    getInterafcesVersionFn: *const fn (interface_name: strid.StrId64) InterfaceVersion,
    //#endregion
};
