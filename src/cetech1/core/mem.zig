const std = @import("std");
const aqueue = @import("atomic_queue.zig");

const AtomicInt = std.atomic.Value(u32);
const FreeIdQueue = aqueue.Queue(u32);

pub fn PoolWithLock(comptime T: type) type {
    return struct {
        const Self = @This();

        pool: std.heap.MemoryPool(T),
        lock: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .pool = std.heap.MemoryPool(T).init(allocator),
                .lock = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.pool.deinit();
        }

        pub fn create(self: *Self) !*T {
            self.lock.lock();
            defer self.lock.unlock();
            return try self.pool.create();
        }

        pub fn destroy(self: *Self, item: *T) void {
            self.lock.lock();
            defer self.lock.unlock();
            self.pool.destroy(item);
        }
    };
}

pub fn IdPool(comptime T: type) type {
    // TODO: gen count
    return struct {
        const Self = @This();

        count: AtomicInt,
        free_id: aqueue.Queue(T),
        free_id_node_pool: PoolWithLock(aqueue.Queue(T).Node),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .count = AtomicInt.init(1), // 0 is always empty
                .free_id = FreeIdQueue.init(),
                .free_id_node_pool = PoolWithLock(aqueue.Queue(T).Node).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.free_id_node_pool.deinit();
        }

        pub fn create(self: *Self, is_new: ?*bool) T {
            if (self.free_id.isEmpty()) {
                if (is_new != null) is_new.?.* = true;
                return self.count.fetchAdd(1, .Release);
            }

            const free_idx_node = self.free_id.get().?;
            const new_obj_id = free_idx_node.data;
            self.free_id_node_pool.destroy(free_idx_node);

            if (is_new != null) is_new.?.* = false;
            return new_obj_id;
        }

        pub fn destroy(self: *Self, id: T) !void {
            const new_node = try self.free_id_node_pool.create();
            new_node.* = FreeIdQueue.Node{ .data = id };
            self.free_id.put(new_node);
        }
    };
}

pub fn VirtualArray(comptime T: type) type {
    // TODO better windows virtual alloc
    return struct {
        const Self = @This();

        max_items: usize,
        raw: [*]u8,
        items: [*]T,

        pub fn init(max_items: usize) !Self {
            const objs_raw = if (max_items != 0) std.heap.page_allocator.rawAlloc(@sizeOf(T) * max_items, 0, 0).? else undefined;
            return .{
                .max_items = max_items,
                .raw = objs_raw,
                .items = @alignCast(@ptrCast(objs_raw)),
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.max_items == 0) return;
            std.heap.page_allocator.rawFree(self.raw[0 .. @sizeOf(T) * self.max_items], 0, 0);
        }
    };
}

pub fn VirtualPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const Queue = aqueue.Queue(u32);

        max_size: usize,

        alocated_items: AtomicInt,
        mem: VirtualArray(T),

        free_id: Queue,
        free_id_node_pool: PoolWithLock(Queue.Node),

        pub fn init(allocator: std.mem.Allocator, max_items: usize) !Self {
            return .{
                .max_size = max_items,
                .alocated_items = AtomicInt.init(1),
                .mem = try VirtualArray(T).init(max_items),
                .free_id = Queue.init(),
                .free_id_node_pool = PoolWithLock(Queue.Node).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.free_id_node_pool.deinit();
        }

        pub fn index(self: *Self, id: *T) u32 {
            return @truncate((@intFromPtr(id) - @intFromPtr(self.mem.items)) / @sizeOf(T));
        }

        pub fn create(self: *Self, is_new: ?*bool) *T {
            if (self.free_id.isEmpty()) {
                if (is_new != null) is_new.?.* = true;
                const idx = self.alocated_items.fetchAdd(1, .Release);
                return &self.mem.items[idx];
            }

            const free_idx_node = self.free_id.get().?;
            const new_obj_idx = free_idx_node.data;
            self.free_id_node_pool.destroy(free_idx_node);

            if (is_new != null) is_new.?.* = false;

            return &self.mem.items[new_obj_idx];
        }

        pub fn destroy(self: *Self, id: *T) !void {
            const new_node = try self.free_id_node_pool.create();
            new_node.* = FreeIdQueue.Node{ .data = self.index(id) };
            self.free_id.put(new_node);
        }
    };
}

pub const TmpAllocatorPool = struct {
    const Self = @This();
    const TempAllocator = std.heap.ArenaAllocator;

    allocator: std.mem.Allocator,
    arena_pool: VirtualPool(TempAllocator),

    pub fn init(allocator: std.mem.Allocator, max_items: usize) !Self {
        return Self{
            .allocator = allocator,
            .arena_pool = try VirtualPool(TempAllocator).init(allocator, max_items),
        };
    }

    pub fn deinit(self: *Self) void {
        // idx 0 is null element
        for (self.arena_pool.mem.items[1..self.arena_pool.alocated_items.raw]) |*obj| {
            obj.deinit();
        }
        self.arena_pool.deinit();
    }

    pub fn create(self: *Self) *TempAllocator {
        var new: bool = false;
        const tmp_alloc = self.arena_pool.create(&new);

        if (new) {
            tmp_alloc.* = TempAllocator.init(self.allocator);
        }

        return tmp_alloc;
    }

    pub fn destroy(self: *Self, alloc: *TempAllocator) void {
        _ = alloc.reset(.retain_capacity);
        self.arena_pool.destroy(alloc) catch undefined;
    }
};
