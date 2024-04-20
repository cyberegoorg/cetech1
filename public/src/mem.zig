const std = @import("std");
const builtin = @import("builtin");

const AtomicInt = std.atomic.Value(u32);
const FreeIdQueue = QueueWithLock(u32);

pub fn QueueWithLock(comptime T: type) type {
    return struct {
        ll: std.DoublyLinkedList(T),
        mutex: std.Thread.Mutex,

        pub const Self = @This();
        pub const Node = std.DoublyLinkedList(T).Node;

        pub fn init() Self {
            return Self{
                .ll = .{},
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn pop(self: *Self) ?*Node {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.ll.pop();
        }

        pub fn put(self: *Self, new_node: *Node) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.ll.append(new_node);
        }
    };
}

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
            self.pool.destroy(@alignCast(item));
        }
    };
}

pub fn IdPool(comptime T: type) type {
    // TODO: gen count
    return struct {
        const Self = @This();

        count: AtomicInt,
        free_id: QueueWithLock(T),
        free_id_node_pool: PoolWithLock(QueueWithLock(T).Node),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .count = AtomicInt.init(1), // 0 is always empty
                .free_id = FreeIdQueue.init(),
                .free_id_node_pool = PoolWithLock(QueueWithLock(T).Node).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.free_id_node_pool.deinit();
        }

        pub fn create(self: *Self, is_new: ?*bool) T {
            if (self.free_id.pop()) |free_idx_node| {
                const new_obj_id = free_idx_node.data;
                self.free_id_node_pool.destroy(free_idx_node);

                if (is_new != null) is_new.?.* = false;
                return new_obj_id;
            } else {
                if (is_new != null) is_new.?.* = true;
                return self.count.fetchAdd(1, .release);
            }
        }

        pub fn destroy(self: *Self, id: T) !void {
            const new_node = try self.free_id_node_pool.create();
            new_node.* = FreeIdQueue.Node{ .data = id };
            self.free_id.put(new_node);
        }
    };
}

const windows = std.os.windows;

pub fn VirtualArray(comptime T: type) type {
    return struct {
        const Self = @This();

        reservation: []align(std.mem.page_size) u8 = &[_]u8{},

        max_items: usize,
        items: [*]T,

        pub fn init(max_items: usize) !Self {
            var new = Self{
                .max_items = max_items,
                .items = undefined,
            };

            const max_size = @sizeOf(T) * max_items;

            if (max_items != 0) {
                switch (builtin.os.tag) {
                    .windows => {
                        new.reservation.ptr = @alignCast(@ptrCast(try windows.VirtualAlloc(
                            null,
                            max_size,
                            windows.MEM_RESERVE | windows.MEM_COMMIT, // TODO: SHIT we need commit on page level
                            windows.PAGE_READWRITE,
                        )));
                        new.reservation.len = max_size;
                    },
                    else => {
                        const PROT = std.posix.PROT;
                        new.reservation = try std.posix.mmap(
                            null,
                            max_size,
                            PROT.READ | PROT.WRITE,
                            .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .NORESERVE = true },
                            -1,
                            0,
                        );
                    },
                }

                new.items = @ptrCast(new.reservation.ptr);
                std.debug.assert(std.mem.isAligned(@intFromPtr(new.items), @alignOf(T)));
            }

            return new;
        }

        pub fn deinit(self: *Self) void {
            if (self.reservation.len > 0) {
                switch (builtin.os.tag) {
                    .windows => {
                        std.os.windows.VirtualFree(self.reservation.ptr, 0, windows.MEM_RELEASE);
                    },
                    else => {
                        std.posix.munmap(self.reservation);
                    },
                }
            }
            self.reservation = &[_]u8{};
        }

        pub fn committed(self: *Self) usize {
            return self.reservation.len - self.uncommitted;
        }

        pub fn notifyAlloc(self: *Self, num_items: usize) !void {
            _ = self;
            _ = num_items;
        }
    };
}

pub fn VirtualPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const Queue = QueueWithLock(u32);

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

        pub fn get(self: *Self, idx: u32) *T {
            return &self.mem.items[idx];
        }

        pub fn create(self: *Self, is_new: ?*bool) *T {
            if (self.free_id.pop()) |free_idx_node| {
                const new_obj_idx = free_idx_node.data;
                self.free_id_node_pool.destroy(free_idx_node);

                if (is_new != null) is_new.?.* = false;

                return &self.mem.items[new_obj_idx];
            } else {
                if (is_new != null) is_new.?.* = true;
                const idx = self.alocated_items.fetchAdd(1, .release);
                self.mem.notifyAlloc(1) catch undefined;
                return &self.mem.items[idx];
            }
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
    const InnerAllocator = std.heap.ArenaAllocator;

    allocator: std.mem.Allocator,
    pool: VirtualPool(InnerAllocator),

    pub fn init(allocator: std.mem.Allocator, max_items: usize) !Self {
        return Self{
            .allocator = allocator,
            .pool = try VirtualPool(InnerAllocator).init(allocator, max_items),
        };
    }

    pub fn deinit(self: *Self) void {
        // idx 0 is null element
        for (self.pool.mem.items[1..self.pool.alocated_items.raw]) |*obj| {
            obj.deinit();
        }
        self.pool.deinit();
    }

    pub fn create(self: *Self) std.mem.Allocator {
        var new: bool = false;
        const tmp_alloc = self.pool.create(&new);

        if (new) {
            tmp_alloc.* = InnerAllocator.init(self.allocator);
        }

        return tmp_alloc.allocator();
    }

    pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
        var true_alloc: *InnerAllocator = @alignCast(@ptrCast(alloc.ptr));
        _ = true_alloc.reset(.retain_capacity);
        self.pool.destroy(true_alloc) catch undefined;
    }
};
