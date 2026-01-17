const std = @import("std");
const Src = std.builtin.SourceLocation;

pub const ztracy = @import("ztracy");
pub const profiler_enabled = @import("cetech1_options").with_tracy;

const cetech1 = @import("cetech1");
const math = cetech1.math;
const apidb = @import("apidb.zig");
const public = cetech1.profiler;

const module_name = .profiler;
const log = std.log.scoped(module_name);

var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    _allocator = allocator;
}

pub fn deinit() void {}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.ProfilerAPI, &api);
}

fn msgWithColor(text: []const u8, color: math.SRGBA) void {
    ztracy.MessageC(text, color.toU32());
}

fn alloc(ptr: ?*const anyopaque, size: usize) void {
    ztracy.Alloc(ptr, size);
}

fn free(ptr: ?*const anyopaque) void {
    ztracy.Free(ptr);
}

fn allocNamed(name: [*:0]const u8, ptr: ?*const anyopaque, size: usize) void {
    ztracy.AllocN(ptr, size, name);
}

fn freeNamed(name: [*:0]const u8, ptr: ?*const anyopaque) void {
    ztracy.FreeN(ptr, name);
}

fn frameMark() void {
    ztracy.FrameMark();
}

fn plotU64(name: [*:0]const u8, val: u64) void {
    ztracy.PlotU(name, val);
}

fn plotF64(name: [*:0]const u8, val: f64) void {
    ztracy.PlotF(name, val);
}

fn emitZoneBegin(srcloc: *public._tracy_source_location_data, active: c_int) public._tracy_c_zone_context {
    return ___tracy_emit_zone_begin(srcloc, active);
}
pub extern fn ___tracy_emit_zone_begin(srcloc: [*c]const public._tracy_source_location_data, active: c_int) public._tracy_c_zone_context;

fn emitZoneEnd(zone: *public._tracy_c_zone_context) void {
    ___tracy_emit_zone_end(zone.*);
}
pub extern fn ___tracy_emit_zone_end(ctx: public._tracy_c_zone_context) void;

fn emitZoneName(zone: *public._tracy_c_zone_context, name: []const u8) void {
    ___tracy_emit_zone_name(zone.*, name.ptr, name.len);
}
pub extern fn ___tracy_emit_zone_name(ctx: public._tracy_c_zone_context, txt: [*c]const u8, size: usize) void;

pub var api = public.ProfilerAPI{
    .msgWithColorFn = msgWithColor,
    .allocFn = alloc,
    .freeFn = free,
    .allocNamedFn = allocNamed,
    .freeNamedFn = freeNamed,
    .frameMarkFn = frameMark,
    .plotU64Fn = plotU64,
    .plotF64Fn = plotF64,
    .emitZoneBegin = emitZoneBegin,
    .emitZoneEnd = emitZoneEnd,
    .emitZoneName = emitZoneName,
};
