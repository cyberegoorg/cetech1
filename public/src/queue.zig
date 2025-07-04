const std = @import("std");

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
        ll: std.SinglyLinkedList(T),
        mutex: std.Thread.Mutex,

        pub const Self = @This();
        pub const Node = std.SinglyLinkedList(T).Node;

        pub fn init() Self {
            return Self{
                .ll = .{},
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn pop(self: *Self) ?*Node {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.ll.popFirst();
        }

        pub fn put(self: *Self, new_node: *Node) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.ll.prepend(new_node);
        }
    };
}
