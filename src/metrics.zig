const std = @import("std");

const apidb = @import("apidb.zig");
const profiler_private = @import("profiler.zig");

const cetech1 = @import("cetech1");
const public = cetech1.metrics;

const module = .metrics;

const MAX_FRAMES = 512;
const MAX_METRICS = 1024;

const Metric = struct {
    name: [:0]u8,
    values: cetech1.ArrayList(f64),
    current_value: f64 = 0,
    offset: usize = 0,
};

const MetricMap = std.StringArrayHashMapUnmanaged(usize);
const MetricIdxAtomic = std.atomic.Value(u32);

var _allocator: std.mem.Allocator = undefined;

var _metrics: [MAX_METRICS]Metric = undefined;
var _last_idx: MetricIdxAtomic = MetricIdxAtomic.init(0);
var _metric_map: MetricMap = undefined;

var _frame: usize = 0;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    _metric_map = .{};
    _frame = 0;
}

pub fn deinit() void {
    for (_metric_map.values()) |v| {
        _allocator.free(_metrics[v].name);
        _metrics[v].values.deinit(_allocator);
    }

    _metric_map.deinit(_allocator);
    _last_idx = MetricIdxAtomic.init(0);
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module, public.MetricsAPI, &api);
}

pub fn getCounter(name: []const u8) !*f64 {
    const counter_idx = _metric_map.get(name);

    if (counter_idx) |idx| {
        return &_metrics[idx].current_value;
    } else {
        const new_name = try _allocator.dupeZ(u8, name);
        const idx = _last_idx.fetchAdd(1, .monotonic);
        _metrics[idx] = Metric{
            .name = new_name,
            .values = try .initCapacity(_allocator, MAX_FRAMES),
        };

        try _metric_map.put(_allocator, new_name, idx);

        return &_metrics[idx].current_value;
    }
}

pub fn pushFrames() !void {
    const frame_idx = _frame % MAX_FRAMES;
    _frame += 1;

    for (_metric_map.values()) |idx| {
        var m = &_metrics[idx];

        if (m.values.items.len < MAX_FRAMES) {
            m.values.appendAssumeCapacity(m.current_value);
        } else {
            m.values.items[m.offset] = m.current_value;
            m.offset = frame_idx;
        }

        // TODO: dynamic on/off per metric, metric group?
        profiler_private.api.plotF64(m.name, m.current_value);

        m.current_value = 0;
    }
}

pub fn getMetricsName(allocator: std.mem.Allocator) ![][]const u8 {
    var names = try cetech1.ArrayList([]const u8).initCapacity(allocator, _metric_map.count());

    for (_metric_map.values()) |idx| {
        const m = &_metrics[idx];
        names.appendAssumeCapacity(m.name);
    }

    return try names.toOwnedSlice(allocator);
}

pub fn getMetricValues(allocator: std.mem.Allocator, name: []const u8) ?[]f64 {
    const counter_idx = _metric_map.get(name) orelse return null;

    const m = &_metrics[counter_idx];

    return allocator.dupe(f64, m.values.items.ptr[0..MAX_FRAMES]) catch null;
}

pub fn getMetricOffset(name: []const u8) ?usize {
    const counter_idx = _metric_map.get(name) orelse return null;

    const m = &_metrics[counter_idx];
    return m.offset;
}

pub var api = public.MetricsAPI{
    .getCounterFn = getCounter,
    .pushFramesFn = pushFrames,
    .getMetricsNameFn = getMetricsName,
    .getMetricValuesFn = getMetricValues,
    .getMetricOffsetFn = getMetricOffset,
};
