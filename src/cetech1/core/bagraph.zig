const std = @import("std");
const strid = @import("strid.zig");
const Allocator = std.mem.Allocator;

pub const StrId64BAG = BAG(strid.StrId64);
pub const StrId32BAG = BAG(strid.StrId32);

// TODO: !!!!!! braindump SHIT !!!!!!
pub fn BAG(comptime T: type) type {
    const BAGArray = std.ArrayList(T);
    const BAGVisited = std.AutoArrayHashMap(T, bool);
    const BAGGraph = std.AutoArrayHashMap(T, BAGArray);
    const BAGDepends = std.AutoArrayHashMap(T, BAGArray);
    const BAGRoot = std.AutoArrayHashMap(T, bool);

    return struct {
        const Self = @This();
        allocator: Allocator,
        graph: BAGGraph,
        depends: BAGDepends,
        output: BAGArray,
        visited: BAGVisited,
        root: BAGRoot,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .graph = BAGGraph.init(allocator),
                .visited = BAGVisited.init(allocator),
                .root = BAGRoot.init(allocator),
                .depends = BAGDepends.init(allocator),
                .output = BAGArray.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.graph.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            for (self.depends.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            self.graph.deinit();
            self.output.deinit();
            self.visited.deinit();
            self.root.deinit();
            self.depends.deinit();
        }

        pub fn dependList(self: *Self, name: T) ?[]T {
            var dep_arr = self.depends.getPtr(name);
            if (dep_arr == null) {
                return null;
            }

            if (dep_arr.?.items.len == 0) {
                return null;
            }

            return dep_arr.?.items;
        }

        pub fn add(self: *Self, name: T, depends: []const T) !void {
            if (!self.graph.contains(name)) {
                var dep_arr = BAGArray.init(self.allocator);
                try self.graph.put(name, dep_arr);
            }

            if (!self.depends.contains(name)) {
                var dep_arr = BAGArray.init(self.allocator);
                try dep_arr.appendSlice(depends);
                try self.depends.put(name, dep_arr);
            }

            if (depends.len == 0) {
                try self.root.put(name, true);
            } else {
                for (depends) |dep_name| {
                    if (!self.graph.contains(dep_name)) {
                        var dep_arr = BAGArray.init(self.allocator);
                        try self.graph.put(dep_name, dep_arr);
                    }

                    var dep_arr = self.graph.getPtr(dep_name).?;
                    try dep_arr.append(name);
                }
            }
        }

        pub fn reset(self: *Self) !void {
            for (self.graph.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            for (self.depends.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            self.graph.clearRetainingCapacity();
            self.depends.clearRetainingCapacity();
            self.visited.clearRetainingCapacity();
            self.root.clearRetainingCapacity();
            self.output.clearRetainingCapacity();
        }

        pub fn build(self: *Self, name: T) !void {
            try self._build(name);
        }

        pub fn build_all(self: *Self) !void {
            for (self.root.keys()) |root| {
                try self.build(root);
            }
        }

        fn _build(self: *Self, name: T) !void {
            if (self.visited.contains(name)) return;
            try self.visited.put(name, true);
            try self.output.append(name);

            var dep_arr = self.graph.getPtr(name);
            if (dep_arr == null) {
                return;
            }

            for (dep_arr.?.items) |dep_name| {
                try self._build(dep_name);
            }
        }
    };
}

test "Can build and resolve graph" {
    var allocator = std.testing.allocator;
    var bag = BAG(u64).init(allocator);
    defer bag.deinit();

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{3});
    try bag.add(3, &[_]u64{4});
    try bag.add(4, &[_]u64{1});

    try bag.build(1);

    try std.testing.expectEqualSlices(u64, &[_]u64{ 1, 4, 3, 2 }, bag.output.items);
}

test "Can reuse graph" {
    var allocator = std.testing.allocator;
    var bag = BAG(u64).init(allocator);
    defer bag.deinit();

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{3});
    try bag.add(3, &[_]u64{4});
    try bag.add(4, &[_]u64{1});

    try bag.build(1);
    try bag.reset();

    try std.testing.expectEqualSlices(u64, &[_]u64{}, bag.output.items);

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{3});
    try bag.add(3, &[_]u64{4});
    try bag.add(4, &[_]u64{1});

    try bag.build(1);

    try std.testing.expectEqualSlices(u64, &[_]u64{ 1, 4, 3, 2 }, bag.output.items);
}
