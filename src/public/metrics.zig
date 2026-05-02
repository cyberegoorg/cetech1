const std = @import("std");
const cetech1 = @import("cetech1.zig");

const apidb = cetech1.apidb;
pub const MetricScopedDuration = struct {
    start: std.Io.Timestamp,
    counter: *f64,

    pub fn begin(io: std.Io, counter: *f64) MetricScopedDuration {
        return .{
            .counter = counter,
            .start = std.Io.Timestamp.now(io, .awake),
        };
    }

    pub fn end(self: MetricScopedDuration, io: std.Io) void {
        const end_time = self.start.durationTo(.now(io, .awake));
        const duration: f64 = @floatFromInt(end_time.toNanoseconds());
        const duration_ms = duration / std.time.ns_per_ms;
        self.counter.* = duration_ms;
    }
};

pub inline fn getCounter(name: []const u8) !*f64 {
    return api.getCounter(name);
}

pub inline fn pushFrames() !void {
    return api.pushFrames();
}

pub inline fn getMetricsName(allocator: std.mem.Allocator) ![][]const u8 {
    return api.getMetricsName(allocator);
}

pub inline fn getMetricValues(allocator: std.mem.Allocator, name: []const u8) ?[]f64 {
    return api.getMetricValues(allocator, name);
}

pub inline fn getMetricOffset(name: []const u8) ?usize {
    return api.getMetricOffset(name);
}

pub const MetricsAPI = struct {
    const Self = @This();

    //#region Pointers to implementation
    getCounter: *const fn (name: []const u8) anyerror!*f64,
    pushFrames: *const fn () anyerror!void,
    getMetricsName: *const fn (allocator: std.mem.Allocator) anyerror![][]const u8,
    getMetricValues: *const fn (allocator: std.mem.Allocator, name: []const u8) ?[]f64,
    getMetricOffset: *const fn (name: []const u8) ?usize,
    //#endregion
};

pub var api: *const MetricsAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, MetricsAPI).?;
}
