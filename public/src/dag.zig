// TODO: !!!!!! braindump SHIT !!!!!!

const std = @import("std");
const strid = @import("strid.zig");
const Allocator = std.mem.Allocator;

pub const StrId64DAG = DAG(strid.StrId64);
pub const StrId32DAG = DAG(strid.StrId32);

// Can build nad resolve dependency graph
pub fn DAG(comptime T: type) type {
    const Set = std.AutoArrayHashMap(T, void);
    const Graph = std.AutoArrayHashMap(T, Set);
    const Depends = std.AutoArrayHashMap(T, Set);
    const Degrees = std.AutoArrayHashMap(T, usize);

    return struct {
        const Self = @This();
        allocator: Allocator,
        graph: Graph,
        depends_on: Depends,
        output: Set,
        build: Set,
        degrees: Degrees,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .graph = Graph.init(allocator),
                .depends_on = Depends.init(allocator),
                .output = Set.init(allocator),
                .build = Set.init(allocator),
                .degrees = Degrees.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.graph.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            for (self.depends_on.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            self.graph.deinit();
            self.output.deinit();
            self.depends_on.deinit();

            self.build.deinit();
            self.degrees.deinit();
        }

        // Return all node that depend on given node
        pub fn dependList(self: *Self, name: T) ?[]T {
            const dep_arr = self.depends_on.getPtr(name);
            if (dep_arr == null) {
                return null;
            }

            if (dep_arr.?.count() == 0) {
                return null;
            }

            return dep_arr.?.keys();
        }

        // Add node to graph
        pub fn add(self: *Self, name: T, depends: []const T) !void {
            if (!self.graph.contains(name)) {
                const dep_arr = Set.init(self.allocator);
                try self.graph.put(name, dep_arr);
            }

            if (!self.depends_on.contains(name)) {
                var dep_arr = Set.init(self.allocator);

                for (depends) |dep| {
                    try dep_arr.put(dep, {});
                }

                try self.depends_on.put(name, dep_arr);
            }

            for (depends) |dep_name| {
                if (!self.graph.contains(dep_name)) {
                    const dep_arr = Set.init(self.allocator);
                    try self.graph.put(dep_name, dep_arr);
                }

                var dep_arr = self.graph.getPtr(dep_name).?;
                try dep_arr.put(name, {});
            }
        }

        // Reset state but not dealocate memory.
        pub fn reset(self: *Self) !void {
            for (self.graph.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            for (self.depends_on.values()) |*dep_arr| {
                dep_arr.deinit();
            }

            self.graph.clearRetainingCapacity();
            self.depends_on.clearRetainingCapacity();
            self.output.clearRetainingCapacity();

            self.build.clearRetainingCapacity();
        }

        // Build for all root nodes
        pub fn build_all(self: *Self) !void {
            const nodes_n = self.graph.count();

            self.build.clearRetainingCapacity();
            self.degrees.clearRetainingCapacity();

            for (self.depends_on.keys()) |root| {
                const dep_arr = self.depends_on.getPtr(root);
                if (dep_arr) |arr| {
                    if (arr.count() != 0) {
                        try self.degrees.put(root, @intCast(arr.count()));
                    }
                }
            }

            for (self.depends_on.keys(), self.depends_on.values()) |k, v| {
                if (v.count() != 0) continue;
                try self.build.put(k, {});
            }

            var visited_n: usize = 0;
            while (self.build.count() != 0) {
                const value = self.build.pop().?;
                try self.output.put(value.key, {});

                const dep_arr = self.graph.getPtr(value.key);
                if (dep_arr) |arr| {
                    for (arr.keys()) |dep| {
                        if (self.degrees.getPtr(dep)) |deg_ptr| {
                            deg_ptr.* -= 1;
                            if (deg_ptr.* == 0) {
                                try self.build.put(dep, {});
                            }
                        }
                    }
                    visited_n += 1;
                }
            }
            std.debug.assert(visited_n == nodes_n);
        }
    };
}

//#region Test
test "Can build and resolve graph" {
    const allocator = std.testing.allocator;
    var bag = DAG(u64).init(allocator);
    defer bag.deinit();

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{3});
    try bag.add(3, &[_]u64{4});
    try bag.add(4, &[_]u64{1});

    try bag.build_all();

    try std.testing.expectEqualSlices(u64, &[_]u64{ 1, 4, 3, 2 }, bag.output.keys());
}

test "Can reuse graph" {
    const allocator = std.testing.allocator;
    var bag = DAG(u64).init(allocator);
    defer bag.deinit();

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{3});
    try bag.add(3, &[_]u64{4});
    try bag.add(4, &[_]u64{1});

    try bag.build_all();
    try bag.reset();

    try std.testing.expectEqualSlices(u64, &[_]u64{}, bag.output.keys());

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{3});
    try bag.add(3, &[_]u64{4});
    try bag.add(4, &[_]u64{1});

    try bag.build_all();

    try std.testing.expectEqualSlices(u64, &[_]u64{ 1, 4, 3, 2 }, bag.output.keys());
}

test "Can build and resolve graph2" {
    const allocator = std.testing.allocator;
    var bag = DAG(u64).init(allocator);
    defer bag.deinit();

    try bag.add(1, &[_]u64{});
    try bag.add(2, &[_]u64{ 1, 4 });
    try bag.add(3, &[_]u64{2});
    try bag.add(4, &[_]u64{});

    try bag.build_all();

    try std.testing.expectEqualSlices(u64, &[_]u64{ 4, 1, 2, 3 }, bag.output.keys());
}
//#endregion
