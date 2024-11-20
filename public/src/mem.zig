const std = @import("std");
const builtin = @import("builtin");

pub const AtomicInt = std.atomic.Value(u32);
const FreeIdQueue = QueueWithLock(u32);

const strid = @import("strid.zig");

const ziglangSet = @import("ziglangSet");
pub const ArraySet = ziglangSet.ArraySetManaged;
pub const Set = ArraySet;

// Bassed on https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue
// Thx Dmitry Vyukov ;)
pub fn MPMCBoundedQueue(comptime T: type, comptime size: usize) type {
    comptime std.debug.assert(size >= 2);
    comptime std.debug.assert(size < std.math.maxInt(isize));
    comptime std.debug.assert(std.math.isPowerOfTwo(size));

    const Cell = struct {
        sequence: std.atomic.Value(isize) = .{ .raw = 0 },
        data: T,
    };

    const mask: isize = @intCast(size - 1);

    return struct {
        const Self = @This();

        buffer: [size]Cell = undefined,

        enqueue_pos: std.atomic.Value(isize) align(std.atomic.cache_line),
        dequeue_pos: std.atomic.Value(isize) align(std.atomic.cache_line),

        pub fn init() Self {
            var self = Self{
                .enqueue_pos = .{ .raw = 0 },
                .dequeue_pos = .{ .raw = 0 },
            };

            for (0..size) |idx| {
                self.buffer[idx].sequence.store(@intCast(idx), .monotonic);
            }

            return self;
        }

        pub fn push(self: *Self, value: T) bool {
            var cell: *Cell = undefined;
            var pos = self.enqueue_pos.load(.monotonic);

            while (true) {
                cell = &self.buffer[@intCast(pos & mask)];
                const seq = cell.sequence.load(.acquire);
                const diff = seq - pos;
                if (diff == 0) {
                    if (null == self.enqueue_pos.cmpxchgWeak(pos, pos +% 1, .monotonic, .monotonic)) {
                        break;
                    }
                } else if (diff < 0) {
                    return false;
                } else {
                    pos = self.enqueue_pos.load(.monotonic);
                }
            }
            cell.data = value;
            cell.sequence.store(pos +% 1, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            var cell: *Cell = undefined;
            var pos = self.dequeue_pos.load(.monotonic);

            while (true) {
                cell = &self.buffer[@intCast(pos & mask)];
                const seq = cell.sequence.load(.acquire);
                const diff = seq - (pos +% 1);
                if (diff == 0) {
                    if (null == self.dequeue_pos.cmpxchgWeak(pos, pos +% 1, .monotonic, .monotonic)) {
                        break;
                    }
                } else if (diff < 0) {
                    return null;
                } else {
                    pos = self.dequeue_pos.load(.monotonic);
                }
            }

            cell.sequence.store(pos +% mask +% 1, .release);
            return cell.data;
        }
    };
}

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

        reservation: []align(std.heap.page_size_min) u8 = &[_]u8{},

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

        pub inline fn index(self: *Self, id: *T) u32 {
            return @truncate((@intFromPtr(id) - @intFromPtr(self.mem.items)) / @sizeOf(T));
        }

        pub inline fn get(self: *Self, idx: u32) *T {
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

// TODO: unshit
pub fn StringInternWithLock(comptime T: type) type {
    return struct {
        const Self = @This();
        const Storage = std.AutoHashMap(InternId, T);
        const has_sentinel = std.meta.sentinel(T) != null;

        pub const InternId = strid.StrId64;

        allocator: std.mem.Allocator,
        storage: Storage,
        lck: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .storage = Storage.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.storage.valueIterator();
            while (it.next()) |v| {
                self.allocator.free(v.*);
            }
            self.storage.deinit();
        }

        pub fn intern(self: *Self, string: T) !T {
            self.lck.lock();
            defer self.lck.unlock();
            const hash = strid.strId64(string);

            const intern_str_result = try self.storage.getOrPut(hash);
            if (intern_str_result.found_existing) return intern_str_result.value_ptr.*;

            intern_str_result.value_ptr.* = try if (has_sentinel) self.allocator.dupeZ(u8, string) else self.allocator.dupe(u8, string);

            return intern_str_result.value_ptr.*;
        }

        pub fn internToHash(self: *Self, string: T) !InternId {
            const hash = strid.strId64(string);

            self.lck.lock();
            defer self.lck.unlock();
            const intern_str_result = try self.storage.getOrPut(hash);
            if (intern_str_result.found_existing) return hash;

            intern_str_result.value_ptr.* = try if (has_sentinel) self.allocator.dupeZ(u8, string) else self.allocator.dupe(u8, string);

            return hash;
        }

        pub fn findById(self: *Self, id: InternId) ?[:0]const u8 {
            self.lck.lock();
            defer self.lck.unlock();
            return self.storage.get(id);
        }
    };
}
