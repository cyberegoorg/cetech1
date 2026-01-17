// TODO: !!!!!! braindump SHIT !!!!!!

const std = @import("std");

const cetech1 = @import("root.zig");
const Allocator = std.mem.Allocator;

pub const StrId64DAG = DAG(cetech1.StrId64);
pub const StrId32DAG = DAG(cetech1.StrId32);

// Can build nad resolve dependency graph
pub fn DAG(comptime T: type) type {
    const Set = cetech1.AutoArrayHashMap(T, void);
    const Graph = cetech1.AutoArrayHashMap(T, Set);
    const Depends = cetech1.AutoArrayHashMap(T, Set);
    const Degrees = cetech1.AutoArrayHashMap(T, usize);

    return struct {
        const Self = @This();
        arena: std.heap.ArenaAllocator,

        graph: Graph = .{},
        depends_on: Depends = .{},
        output: Set = .{},
        build: Set = .{},
        degrees: Degrees = .{},

        pub fn init(allocator: Allocator) Self {
            return .{
                .arena = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        // Reset state but not dealocate memory.
        pub fn reset(self: *Self) !void {
            _ = self.arena.reset(.retain_capacity);
            self.graph = .{};
            self.depends_on = .{};
            self.output = .{};
            self.build = .{};
            self.degrees = .{};
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
            const allocator = self.arena.allocator();

            if (!self.graph.contains(name)) {
                const dep_arr = Set{};
                try self.graph.put(allocator, name, dep_arr);
            }

            if (!self.depends_on.contains(name)) {
                var dep_arr = Set{};

                for (depends) |dep| {
                    try dep_arr.put(allocator, dep, {});
                }

                try self.depends_on.put(allocator, name, dep_arr);
            }

            for (depends) |dep_name| {
                if (!self.graph.contains(dep_name)) {
                    try self.graph.put(allocator, dep_name, .{});
                }

                var dep_arr = self.graph.getPtr(dep_name).?;
                try dep_arr.put(allocator, name, {});
            }
        }

        // Build for all root nodes
        pub fn build_all(self: *Self) !void {
            const allocator = self.arena.allocator();

            const nodes_n = self.graph.count();

            self.build.clearRetainingCapacity();
            self.degrees.clearRetainingCapacity();

            for (self.depends_on.keys()) |root| {
                if (self.depends_on.getPtr(root)) |arr| {
                    if (arr.count() != 0) {
                        try self.degrees.put(allocator, root, @intCast(arr.count()));
                    }
                }
            }

            for (self.depends_on.keys(), self.depends_on.values()) |k, v| {
                if (v.count() != 0) continue;
                try self.build.put(allocator, k, {});
            }

            var visited_n: usize = 0;
            while (self.build.count() != 0) {
                const value = self.build.pop().?;
                try self.output.put(allocator, value.key, {});

                if (self.graph.getPtr(value.key)) |arr| {
                    for (arr.keys()) |dep| {
                        if (self.degrees.getPtr(dep)) |deg_ptr| {
                            deg_ptr.* -= 1;
                            if (deg_ptr.* == 0) {
                                try self.build.put(allocator, dep, {});
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
