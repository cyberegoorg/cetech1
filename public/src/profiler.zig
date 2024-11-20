const std = @import("std");
const Src = std.builtin.SourceLocation;
pub const profiler_enabled = @import("cetech1_options").enable_tracy;

/// Profiler alocator wraping struct
/// Wrap given alocator and trace alloc/free with profiler
pub const AllocatorProfiler = struct {
    const Self = @This();
    name: ?[:0]const u8,
    child_allocator: std.mem.Allocator,
    profiler_api: *ProfilerAPI,

    pub fn init(profiler_api: *ProfilerAPI, child_allocator: std.mem.Allocator, name: ?[:0]const u8) AllocatorProfiler {
        return AllocatorProfiler{ .child_allocator = child_allocator, .name = name, .profiler_api = profiler_api };
    }

    pub fn allocator(self: *AllocatorProfiler) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = Self.alloc, .resize = Self.resize, .free = Self.free, .remap = Self.remap } };
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_ptr_align: std.mem.Alignment,
        ra: usize,
    ) ?[*]u8 {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawAlloc(len, log2_ptr_align, ra);
        if (result) |addr| {
            if (self.name != null) {
                self.profiler_api.allocNamed(self.name.?, addr, len);
            } else {
                self.profiler_api.alloc(addr, len);
            }
        } else {
            var buffer: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, "alloc failed requesting {d}", .{len}) catch return result;
            self.profiler_api.msgWithColor(msg, 0xFF0000);
        }
        return result;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_ptr_align: std.mem.Alignment,
        new_len: usize,
        ra: usize,
    ) bool {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawResize(buf, log2_ptr_align, new_len, ra);
        if (result) {
            if (self.name != null) {
                self.profiler_api.freeNamed(self.name.?, buf.ptr);
                self.profiler_api.allocNamed(self.name.?, buf.ptr, new_len);
            } else {
                self.profiler_api.free(buf.ptr);
                self.profiler_api.alloc(buf.ptr, new_len);
            }
        } else {
            var buffer: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, "resize failed requesting {d} -> {d}", .{ buf.len, new_len }) catch return result;
            self.profiler_api.msgWithColor(msg, 0xFF0000);
        }
        return result;
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_ptr_align: std.mem.Alignment,
        ra: usize,
    ) void {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));
        self.child_allocator.rawFree(buf, log2_ptr_align, ra);
        if (self.name != null) {
            self.profiler_api.freeNamed(self.name.?, buf.ptr);
        } else {
            self.profiler_api.free(buf.ptr);
        }
    }

    fn remap(
        ctx: *anyopaque,
        buf: []u8,
        log2_ptr_align: std.mem.Alignment,
        new_len: usize,
        ra: usize,
    ) ?[*]u8 {
        const self: *AllocatorProfiler = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawRemap(buf, log2_ptr_align, new_len, ra);
        if (result != null) {
            if (self.name != null) {
                self.profiler_api.freeNamed(self.name.?, buf.ptr);
                self.profiler_api.allocNamed(self.name.?, buf.ptr, new_len);
            } else {
                self.profiler_api.free(buf.ptr);
                self.profiler_api.alloc(buf.ptr, new_len);
            }
        } else {
            var buffer: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, "resize failed requesting {d} -> {d}", .{ buf.len, new_len }) catch return result;
            self.profiler_api.msgWithColor(msg, 0xFF0000);
        }
        return result;
    }
};

pub const ZoneCtx = struct {
    _zone: _tracy_c_zone_context = undefined,
    profiler: *const ProfilerAPI = undefined,

    pub inline fn End(self: *ZoneCtx) void {
        self.profiler.emitZoneEnd(&self._zone);
    }

    pub inline fn Name(self: *ZoneCtx, name: []const u8) void {
        self.profiler.emitZoneName(&self._zone, name);
    }
};

/// Main profiler API.
/// Using awesome Tracy profiler.
pub const ProfilerAPI = struct {
    const Self = @This();

    pub inline fn Zone(self: *const Self, comptime src: Src) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, null, 0, 0);
    }

    pub inline fn ZoneN(self: *const Self, comptime src: Src, name: [*:0]const u8) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, name, 0, 0);
    }
    pub inline fn ZoneC(self: *const Self, comptime src: Src, color: u32) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, null, color, 0);
    }
    pub inline fn ZoneNC(self: *const Self, comptime src: Src, name: [*:0]const u8, color: u32) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, name, color, 0);
    }
    pub inline fn ZoneS(self: *const Self, comptime src: Src, depth: i32) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, null, 0, depth);
    }
    pub inline fn ZoneNS(self: *const Self, comptime src: Src, name: [*:0]const u8, depth: i32) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, name, 0, depth);
    }
    pub inline fn ZoneCS(self: *const Self, comptime src: Src, color: u32, depth: i32) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, null, color, depth);
    }
    pub inline fn ZoneNCS(self: *const Self, comptime src: Src, name: [*:0]const u8, color: u32, depth: i32) ZoneCtx {
        if (!profiler_enabled) return .{};
        return self.initZone(src, name, color, depth);
    }

    inline fn initZone(self: *const Self, comptime src: Src, name: ?[*:0]const u8, color: u32, depth: c_int) ZoneCtx {
        if (!profiler_enabled) return .{};

        _ = depth; // autofix
        // Tracy uses pointer identity to identify contexts.
        // The `src` parameter being comptime ensures that
        // each zone gets its own unique global location for this
        // struct.
        const static = struct {
            var loc: _tracy_source_location_data = undefined;

            // Ensure that a unique struct type is generated for each unique `src`. See
            // https://github.com/ziglang/zig/issues/18816
            comptime {
                // https://github.com/ziglang/zig/issues/19274
                _ = @sizeOf(@TypeOf(src));
            }
        };

        static.loc = .{
            .name = name,
            .function = src.fn_name.ptr,
            .file = src.file.ptr,
            .line = src.line,
            .color = color,
        };

        const zone = self.emitZoneBegin(&static.loc, 1);
        return ZoneCtx{ .profiler = self, ._zone = zone };
    }

    /// Trace this msg with color
    pub inline fn msgWithColor(self: Self, text: []const u8, color: u32) void {
        if (!profiler_enabled) return;
        self.msgWithColorFn(text, color);
    }

    /// Trace allocation
    pub inline fn alloc(self: Self, ptr: ?*const anyopaque, size: usize) void {
        if (!profiler_enabled) return;
        self.allocFn(ptr, size);
    }

    /// Trace free
    pub inline fn free(self: Self, ptr: ?*const anyopaque) void {
        if (!profiler_enabled) return;
        self.freeFn(ptr);
    }

    /// Trace allocation with name
    pub inline fn allocNamed(self: Self, name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void {
        if (!profiler_enabled) return;
        self.allocNamedFn(name, ptr, size);
    }

    /// Trace free with name
    pub inline fn freeNamed(self: Self, name: [*:0]const u8, ptr: ?*const anyopaque) void {
        if (!profiler_enabled) return;
        self.freeNamedFn(name, ptr);
    }

    /// Mark frame begin
    pub inline fn frameMark(self: Self) void {
        if (!profiler_enabled) return;
        self.frameMarkFn();
    }

    /// Plot u64 value with name
    pub inline fn plotU64(self: Self, name: [*:0]const u8, val: u64) void {
        if (!profiler_enabled) return;
        self.plotU64Fn(name, val);
    }

    /// Plot f64 value with name
    pub inline fn plotF64(self: Self, name: [*:0]const u8, val: f64) void {
        if (!profiler_enabled) return;
        self.plotF64Fn(name, val);
    }

    //#region Pointers to implementation
    msgWithColorFn: *const fn (text: []const u8, color: u32) void,
    allocFn: *const fn (ptr: ?*const anyopaque, size: usize) void,
    freeFn: *const fn (ptr: ?*const anyopaque) void,
    allocNamedFn: *const fn (name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void,
    freeNamedFn: *const fn (name: [*:0]const u8, ptr: ?*const anyopaque) void,
    frameMarkFn: *const fn () void,
    plotU64Fn: *const fn (name: [*:0]const u8, val: u64) void,
    plotF64Fn: *const fn (name: [*:0]const u8, val: f64) void,

    emitZoneBegin: *const fn (srcloc: *_tracy_source_location_data, active: c_int) _tracy_c_zone_context,
    emitZoneEnd: *const fn (zone: *_tracy_c_zone_context) void,
    emitZoneName: *const fn (zone: *_tracy_c_zone_context, name: []const u8) void,
    //#endregion
};

// Must be sync with original tracy
pub const _tracy_source_location_data = extern struct {
    name: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    function: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    file: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    line: u32 = @import("std").mem.zeroes(u32),
    color: u32 = @import("std").mem.zeroes(u32),
};
pub const _tracy_c_zone_context = extern struct {
    id: u32 = @import("std").mem.zeroes(u32),
    active: c_int = @import("std").mem.zeroes(c_int),
};
