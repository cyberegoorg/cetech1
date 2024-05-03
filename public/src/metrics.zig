const std = @import("std");

pub const MetricScopedDuration = struct {
    start: std.time.Instant,
    counter: *f64,

    pub fn begin(counter: *f64) MetricScopedDuration {
        return .{
            .counter = counter,
            .start = std.time.Instant.now() catch undefined,
        };
    }

    pub fn end(self: MetricScopedDuration) void {
        const end_time = std.time.Instant.now() catch return;
        const duration: f64 = @floatFromInt(end_time.since(self.start));
        const duration_ms = duration / std.time.ns_per_ms;
        self.counter.* = duration_ms;
    }
};

pub const MetricsAPI = struct {
    const Self = @This();

    pub fn getCounter(self: Self, name: []const u8) !*f64 {
        return self.getCounterFn(name);
    }

    pub fn pushFrames(self: Self) !void {
        return self.pushFramesFn();
    }

    pub fn getMetricsName(self: Self, allocator: std.mem.Allocator) ![][]const u8 {
        return self.getMetricsNameFn(allocator);
    }

    pub fn getMetricValues(self: Self, allocator: std.mem.Allocator, name: []const u8) ?[]f64 {
        return self.getMetricValuesFn(allocator, name);
    }

    pub fn getMetricOffset(self: Self, name: []const u8) ?usize {
        return self.getMetricOffsetFn(name);
    }

    //#region Pointers to implementation
    getCounterFn: *const fn (name: []const u8) anyerror!*f64,
    pushFramesFn: *const fn () anyerror!void,
    getMetricsNameFn: *const fn (allocator: std.mem.Allocator) anyerror![][]const u8,
    getMetricValuesFn: *const fn (allocator: std.mem.Allocator, name: []const u8) ?[]f64,
    getMetricOffsetFn: *const fn (name: []const u8) ?usize,
    //#endregion
};
