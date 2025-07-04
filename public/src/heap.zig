const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const cetech1 = @import("root.zig");
const QueueWithLock = @import("queue.zig").QueueWithLock;
const FreeIdQueue = QueueWithLock(u32);

pub const AtomicInt = std.atomic.Value(u32);

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

        pub fn initPreheated(allocator: std.mem.Allocator, initial_size: usize) !Self {
            return .{
                .pool = try std.heap.MemoryPool(T).initPreheated(allocator, initial_size),
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

        pub fn clear(self: *Self) void {
            self.lock.lock();
            defer self.lock.unlock();
            _ = self.pool.reset(.retain_capacity);
        }

        pub fn createMany(self: *Self, output: []*T, count: usize) !void {
            self.lock.lock();
            defer self.lock.unlock();
            for (0..count) |idx| output[idx] = try self.pool.create();
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
                return self.count.fetchAdd(1, .monotonic);
            }
        }

        pub fn destroy(self: *Self, id: T) !void {
            const new_node = try self.free_id_node_pool.create();
            new_node.* = FreeIdQueue.Node{ .data = id };
            self.free_id.put(new_node);
        }
    };
}

pub fn VirtualArray(comptime T: type) type {
    return struct {
        const Self = @This();

        reservation: []align(std.heap.page_size_min) u8 = &[_]u8{},

        max_items: usize,
        items: []T,

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

                new.items.ptr = @alignCast(@ptrCast(new.reservation.ptr));
                new.items.len = max_items;

                std.debug.assert(std.mem.isAligned(@intFromPtr(new.items.ptr), @alignOf(T)));
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

        const TagedIdx = packed struct(u64) {
            tag: u32,
            idx: u32,
        };

        const Item = struct {
            data: T,
            next_free_idx: std.atomic.Value(TagedIdx),
            free: bool,
        };

        max_size: usize,
        alocated_items: AtomicInt,

        mem: VirtualArray(Item),

        //lock: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator, max_items: usize) !Self {
            _ = allocator;
            var self = Self{
                .max_size = max_items,
                .alocated_items = AtomicInt.init(1),
                .mem = try VirtualArray(Item).init(max_items),
            };
            self.mem.items[0].next_free_idx.store(.{ .tag = 0, .idx = 0 }, .monotonic);
            self.mem.items[0].free = true;

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.mem.deinit();
        }

        pub inline fn index(self: *Self, id: *T) u32 {
            const item: *Item = @alignCast(@fieldParentPtr("data", id));
            std.debug.assert(((@intFromPtr(item) - @intFromPtr(self.mem.items.ptr)) % @sizeOf(Item)) == 0);
            const idx: u32 = @truncate((@intFromPtr(item) - @intFromPtr(self.mem.items.ptr)) / @sizeOf(Item));
            return idx;
        }

        pub inline fn get(self: *Self, idx: usize) *T {
            std.debug.assert(idx != 0);
            return &self.mem.items[idx].data;
        }

        pub fn allocatedItems(self: *Self) []Item {
            return self.mem.items[1..self.alocated_items.load(.monotonic)];
        }

        pub fn create(self: *Self, is_new: ?*bool) *T {
            // self.lock.lock();
            // defer self.lock.unlock();

            const head = &self.mem.items[0];

            while (true) {
                const next_free_idx = head.next_free_idx.load(.acquire);
                if (next_free_idx.idx != 0) {
                    if (is_new != null) is_new.?.* = false;

                    var free_item = &self.mem.items[next_free_idx.idx];
                    const free_next_item_idx = free_item.next_free_idx.load(.acquire);

                    const new_id = TagedIdx{ .tag = next_free_idx.tag +% 1, .idx = free_next_item_idx.idx };
                    if (null == head.next_free_idx.cmpxchgWeak(next_free_idx, new_id, .release, .monotonic)) {
                        free_item.free = false;
                        return &free_item.data;
                    }
                } else {
                    if (is_new != null) is_new.?.* = true;
                    const idx = self.alocated_items.fetchAdd(1, .monotonic);
                    self.mem.notifyAlloc(1) catch undefined;

                    var item = &self.mem.items[idx];
                    item.free = false;

                    return &item.data;
                }
            }
        }

        pub fn destroy(self: *Self, id: *T) void {
            // self.lock.lock();
            // defer self.lock.unlock();

            const head = &self.mem.items[0];

            const idx = self.index(id);
            const item: *Item = @alignCast(@fieldParentPtr("data", id));

            while (true) {
                const next_free_idx = head.next_free_idx.load(.acquire);
                item.next_free_idx.store(next_free_idx, .monotonic);

                const new_id = TagedIdx{ .tag = next_free_idx.tag +% 1, .idx = idx };
                if (null == head.next_free_idx.cmpxchgWeak(next_free_idx, new_id, .release, .monotonic)) {
                    break;
                }
            }
        }

        pub fn isFree(self: Self, item: *Item) bool {
            _ = self;
            return item.free;
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
        for (self.pool.allocatedItems()) |*obj| {
            obj.data.deinit();
        }
        self.pool.deinit();
    }

    pub fn create(self: *Self) std.mem.Allocator {
        var new: bool = false;
        const allocator = self.pool.create(&new);

        if (new) {
            allocator.* = InnerAllocator.init(self.allocator);
        }

        return allocator.allocator();
    }

    pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
        var true_alloc: *InnerAllocator = @alignCast(@ptrCast(alloc.ptr));
        _ = true_alloc.reset(.retain_capacity);
        self.pool.destroy(true_alloc);
    }
};
