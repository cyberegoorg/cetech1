const std = @import("std");
const Src = std.builtin.SourceLocation;

/// Priler alocator wraping struct
/// Wrap given alocator and trace alloc/free with profiler
pub const AllocatorProfiler = struct {
    const Self = @This();
    name: ?[:0]const u8,
    parent_allocator: std.mem.Allocator,
    profiler_api: *ProfilerAPI,

    pub fn init(profiler_api: *ProfilerAPI, parent_allocator: std.mem.Allocator, name: ?[:0]const u8) AllocatorProfiler {
        return AllocatorProfiler{ .parent_allocator = parent_allocator, .name = name, .profiler_api = profiler_api };
    }

    pub fn allocator(self: *AllocatorProfiler) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = Self.alloc, .resize = Self.resize, .free = Self.free } };
    }

    fn alloc(ctx: *anyopaque, n: usize, log2_ptr_align: u8, ra: usize) ?[*]u8 {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));
        var ptr = self.parent_allocator.rawAlloc(n, log2_ptr_align, ra);
        if (self.name != null) {
            self.profiler_api.allocNamed(self.name.?, ptr, n);
        } else {
            self.profiler_api.alloc(ptr, n);
        }
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_size: usize, return_address: usize) bool {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawResize(buf, log2_buf_align, new_size, return_address);
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, return_address: usize) void {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));

        if (self.name != null) {
            self.profiler_api.freeNamed(self.name.?, buf.ptr);
        } else {
            self.profiler_api.free(buf.ptr);
        }
        return self.parent_allocator.rawFree(buf, log2_buf_align, return_address);
    }
};

/// Main profiler API.
/// Using awesome Tracy profiler.
pub const ProfilerAPI = struct {
    const Self = @This();

    /// Trace this msg with color
    pub fn msgWithColor(self: Self, text: []const u8, color: u32) void {
        self.msgWithColorFn(text, color);
    }

    /// Trace allocation
    pub fn alloc(self: Self, ptr: ?*const anyopaque, size: usize) void {
        self.allocFn(ptr, size);
    }

    /// Trace free
    pub fn free(self: Self, ptr: ?*const anyopaque) void {
        self.freeFn(ptr);
    }

    /// Trace allocation with name
    pub fn allocNamed(self: Self, name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void {
        self.allocNamedFn(name, ptr, size);
    }

    /// Trace free with name
    pub fn freeNamed(self: Self, name: [*:0]const u8, ptr: ?*const anyopaque) void {
        self.freeNamedFn(name, ptr);
    }

    /// Mark frame begin
    pub fn frameMark(self: Self) void {
        self.frameMarkFn();
    }

    /// Plot u64 value with name
    pub fn plotU64(self: Self, name: [*:0]const u8, val: u64) void {
        self.plotU64Fn(name, val);
    }

    //#region Pointers to implementation
    msgWithColorFn: *const fn (text: []const u8, color: u32) void,
    allocFn: *const fn (ptr: ?*const anyopaque, size: usize) void,
    freeFn: *const fn (ptr: ?*const anyopaque) void,
    allocNamedFn: *const fn (name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void,
    freeNamedFn: *const fn (name: [*:0]const u8, ptr: ?*const anyopaque) void,
    frameMarkFn: *const fn () void,
    plotU64Fn: *const fn (name: [*:0]const u8, val: u64) void,
    //#endregion
};
