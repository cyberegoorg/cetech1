const std = @import("std");
const cetech1 = @import("cetech1.zig");
const math = cetech1.math;

const apidb = cetech1.apidb;
const Src = std.builtin.SourceLocation;
pub const profiler_enabled = @import("cetech1_options").with_tracy;

const M = @This();

/// Profiler alocator wraping struct
/// Wrap given alocator and trace alloc/free with profiler
pub const AllocatorProfiler = struct {
    const Self = @This();
    name: ?[:0]const u8,
    child_allocator: std.mem.Allocator,

    pub fn init(child_allocator: std.mem.Allocator, name: ?[:0]const u8) AllocatorProfiler {
        return AllocatorProfiler{ .child_allocator = child_allocator, .name = name };
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
                M.allocNamed(self.name.?, addr, len);
            } else {
                M.alloc(addr, len);
            }
        } else {
            var buffer: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, "alloc failed requesting {d}", .{len}) catch return result;
            M.msgWithColor(msg, .fromU32(0xFF0000));
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
                M.freeNamed(self.name.?, buf.ptr);
                M.allocNamed(self.name.?, buf.ptr, new_len);
            } else {
                M.free(buf.ptr);
                M.alloc(buf.ptr, new_len);
            }
        } else {
            var buffer: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, "resize failed requesting {d} -> {d}", .{ buf.len, new_len }) catch return result;
            M.msgWithColor(msg, .fromU32(0xFF0000));
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
            M.freeNamed(self.name.?, buf.ptr);
        } else {
            M.free(buf.ptr);
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
                freeNamed(self.name.?, buf.ptr);
                allocNamed(self.name.?, buf.ptr, new_len);
            } else {
                M.free(buf.ptr);
                M.alloc(buf.ptr, new_len);
            }
        } else {
            var buffer: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, "resize failed requesting {d} -> {d}", .{ buf.len, new_len }) catch return result;
            M.msgWithColor(msg, .fromU32(0xFF0000));
        }
        return result;
    }
};

pub const ZoneCtx = struct {
    _zone: _tracy_c_zone_context = .{},

    pub inline fn End(self: *ZoneCtx) void {
        api.emitZoneEnd(&self._zone);
    }

    pub inline fn Name(self: *ZoneCtx, name: []const u8) void {
        api.emitZoneName(&self._zone, name);
    }
};

pub inline fn Zone(comptime src: Src) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, null, .{}, 0);
}

pub inline fn ZoneN(comptime src: Src, name: [*:0]const u8) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, name, .{}, 0);
}
pub inline fn ZoneC(comptime src: Src, color: math.SRGBA) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, null, color, 0);
}
pub inline fn ZoneNC(comptime src: Src, name: [*:0]const u8, color: math.SRGBA) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, name, color, 0);
}
pub inline fn ZoneS(comptime src: Src, depth: i32) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, null, .{}, depth);
}
pub inline fn ZoneNS(comptime src: Src, name: [*:0]const u8, depth: i32) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, name, .{}, depth);
}
pub inline fn ZoneCS(comptime src: Src, color: math.SRGBA, depth: i32) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, null, color, depth);
}
pub inline fn ZoneNCS(comptime src: Src, name: [*:0]const u8, color: math.SRGBA, depth: i32) ZoneCtx {
    if (!profiler_enabled) return .{};
    return initZone(src, name, color, depth);
}

inline fn initZone(comptime src: Src, name: ?[*:0]const u8, color: math.SRGBA, depth: c_int) ZoneCtx {
    if (!profiler_enabled) return .{};

    _ = depth;
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

    const zone = api.emitZoneBegin(&static.loc, 1);
    return ZoneCtx{ ._zone = zone };
}

/// Trace this msg with color
pub inline fn msgWithColor(text: []const u8, color: math.SRGBA) void {
    if (!profiler_enabled) return;
    api.msgWithColor(text, color);
}

/// Trace allocation
pub inline fn alloc(ptr: ?*const anyopaque, size: usize) void {
    if (!profiler_enabled) return;
    api.alloc(ptr, size);
}

/// Trace free
pub inline fn free(ptr: ?*const anyopaque) void {
    if (!profiler_enabled) return;
    api.free(ptr);
}

/// Trace allocation with name
pub inline fn allocNamed(name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void {
    if (!profiler_enabled) return;
    api.allocNamed(name, ptr, size);
}

/// Trace free with name
pub inline fn freeNamed(name: [*:0]const u8, ptr: ?*const anyopaque) void {
    if (!profiler_enabled) return;
    api.freeNamed(name, ptr);
}

/// Mark frame begin
pub inline fn frameMark() void {
    if (!profiler_enabled) return;
    api.frameMark();
}

/// Plot u64 value with name
pub inline fn plotU64(name: [*:0]const u8, val: u64) void {
    if (!profiler_enabled) return;
    api.plotU64(name, val);
}

/// Plot f64 value with name
pub inline fn plotF64(name: [*:0]const u8, val: f64) void {
    if (!profiler_enabled) return;
    api.plotF64(name, val);
}

/// Main profiler API.
/// Using awesome Tracy profiler.
pub const ProfilerAPI = struct {
    msgWithColor: *const fn (text: []const u8, color: math.SRGBA) void,
    alloc: *const fn (ptr: ?*const anyopaque, size: usize) void,
    free: *const fn (ptr: ?*const anyopaque) void,
    allocNamed: *const fn (name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void,
    freeNamed: *const fn (name: [*:0]const u8, ptr: ?*const anyopaque) void,
    frameMark: *const fn () void,
    plotU64: *const fn (name: [*:0]const u8, val: u64) void,
    plotF64: *const fn (name: [*:0]const u8, val: f64) void,
    emitZoneBegin: *const fn (srcloc: *_tracy_source_location_data, active: c_int) _tracy_c_zone_context,
    emitZoneEnd: *const fn (zone: *_tracy_c_zone_context) void,
    emitZoneName: *const fn (zone: *_tracy_c_zone_context, name: []const u8) void,
};

pub var api: *const ProfilerAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, ProfilerAPI).?;
}

// Must be sync with original tracy
pub const _tracy_source_location_data = extern struct {
    name: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    function: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    file: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    line: u32 = @import("std").mem.zeroes(u32),
    color: math.SRGBA = @import("std").mem.zeroes(math.SRGBA),
};
pub const _tracy_c_zone_context = extern struct {
    id: u32 = @import("std").mem.zeroes(u32),
    active: c_int = @import("std").mem.zeroes(c_int),
};
