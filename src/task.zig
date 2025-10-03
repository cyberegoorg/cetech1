const std = @import("std");
const builtin = @import("builtin");

const zjobs = @import("zjobs");

const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const cetech1 = @import("cetech1");
const public = cetech1.task;

const module_name = .task;

const log = std.log.scoped(module_name);

pub const QueueConfig = struct {
    max_jobs: u16 = 256,
    max_job_size: u16 = 64,
    max_threads: u8 = 32,
    idle_sleep_ns: u32 = 50,
};
inline fn ignore(_: anytype) void {}

threadlocal var THREAD_IDX: u32 = 0;
pub const cache_line_size = std.atomic.cache_line;

inline fn isFreeCycle(cycle: u64) bool {
    return (cycle & 1) == 0;
}

inline fn isLiveCycle(cycle: u64) bool {
    return (cycle & 1) == 1;
}

pub fn JobSystem(comptime queue_config: QueueConfig) type {
    const Atomic = std.atomic.Value;
    const FreeQueue = cetech1.MPMCBoundedQueue(usize, queue_config.max_jobs);
    const TaskQueue = cetech1.MPMCBoundedQueue(public.TaskID, queue_config.max_jobs);
    const PrioTaskQueue = cetech1.MPMCBoundedQueue(public.TaskID, 1024);

    const TaskBuffer = cetech1.ArrayList(public.TaskID);

    const Worker = struct {
        const Self = @This();

        thread: ?std.Thread = null,
        prioqueue: PrioTaskQueue = undefined,
        queue: TaskQueue = undefined,

        buffer: TaskBuffer,

        pub fn pushJob(self: *Self, taks: public.TaskID) void {
            const b = self.queue.push(taks);
            std.debug.assert(b);
        }

        pub fn popJob(self: *Self) ?public.TaskID {
            return self.queue.pop();
        }

        pub fn stealJob(self: *Self) ?public.TaskID {
            return self.queue.pop();
        }

        pub fn pushPrioJob(self: *Self, taks: public.TaskID) void {
            const b = self.prioqueue.push(taks);
            std.debug.assert(b);
        }

        pub fn popPrioJob(self: *Self) ?public.TaskID {
            return self.prioqueue.pop();
        }
    };

    const Slot = struct {
        const Self = @This();

        pub const max_job_size = queue_config.max_job_size;

        const Data = [max_job_size]u8;
        const Main = *const fn (*Data) void;

        data: Data align(cache_line_size) = undefined,
        exec: Main align(cache_line_size) = undefined,

        id: public.TaskID = public.TaskID.none,
        prereq: public.TaskID = public.TaskID.none,
        cycle: Atomic(u16) = .{ .raw = 0 },

        combine: bool = false,

        fn storeJob(
            self: *Self,
            comptime Job: type,
            job: *const Job,
            index: usize,
            prereq: public.TaskID,
        ) public.TaskID {
            const old_cycle: u16 = self.cycle.load(.acquire);
            std.debug.assert(isFreeCycle(old_cycle));

            const new_cycle: u16 = old_cycle +% 1;
            std.debug.assert(isLiveCycle(new_cycle));

            {
                const acquired: bool = null == self.cycle.cmpxchgStrong(
                    old_cycle,
                    new_cycle,
                    .monotonic,
                    .monotonic,
                );
                std.debug.assert(acquired);
            }

            @memset(&self.data, 0);

            const job_bytes = std.mem.asBytes(job);
            @memcpy(self.data[0..job_bytes.len], job_bytes);

            const exec: *const fn (*Job) void = &@field(Job, "exec");
            const id = jobId(@truncate(index), new_cycle);

            self.exec = @as(Main, @ptrCast(exec));
            self.id = id;
            self.prereq = if (prereq != id) prereq else public.TaskID.none;
            return id;
        }

        fn executeJob(self: *Self, id: public.TaskID) bool {
            const old_id = @atomicLoad(public.TaskID, &self.id, .acquire);
            std.debug.assert(old_id == id);

            const old_cycle: u16 = old_id.cycle();
            std.debug.assert(isLiveCycle(old_cycle));

            const new_cycle: u16 = old_cycle +% 1;
            std.debug.assert(isFreeCycle(new_cycle));

            self.exec(&self.data);

            const old_id2 = @atomicLoad(public.TaskID, &self.id, .acquire);
            std.debug.assert(old_id2 == id);

            {
                const released: bool = null == self.cycle.cmpxchgStrong(
                    old_cycle,
                    new_cycle,
                    .monotonic,
                    .monotonic,
                );
                std.debug.assert(released);
            }
            return true;
        }

        fn jobId(index: u16, cycle: u16) public.TaskID {
            return public.TaskID.Fields.init(index, cycle).id();
        }
    };

    const Queue = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        num_threads: u32 = 0,
        running: std.atomic.Value(bool) = .{ .raw = false },

        workers: [queue_config.max_threads]Worker = undefined,

        tasks: [queue_config.max_jobs]Slot align(cache_line_size) = @splat(.{}),
        free_tasks: FreeQueue = undefined,

        job_signal: std.Thread.Semaphore = .{},

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{
                .allocator = allocator,
                .free_tasks = .init(),
            };

            for (0..queue_config.max_jobs) |value| {
                _ = self.free_tasks.push(value);
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            for (0..queue_config.max_threads) |wid| {
                self.workers[wid].buffer.deinit(self.allocator);
            }
        }

        pub fn isRunning(self: *const Self) bool {
            return self.running.load(.monotonic);
        }

        pub fn start(self: *Self, worker_count: ?u32) !void {
            const cpu_count = std.Thread.getCpuCount() catch 1;
            var cpu_core_count = @max(2, if (builtin.cpu.arch == .x86_64) cpu_count / 2 else cpu_count); // TODO: Is hyperthreding good or bad?

            // const cpu_core_count = cpu_count;
            if (worker_count) |count| {
                cpu_core_count = @max(2, count);
            }
            self.num_threads = @intCast(@min(queue_config.max_threads, cpu_core_count));
            // self.num_threads = 2;
            // self.num_threads = 1;
            log.info("Using {} threads for {} cores", .{ self.num_threads, cpu_core_count });

            const was_running = self.running.swap(true, .monotonic);
            std.debug.assert(was_running == false);

            const main_worker = &self.workers[0];
            main_worker.* = .{
                .buffer = try TaskBuffer.initCapacity(self.allocator, queue_config.max_jobs),
                .queue = .init(),
                .prioqueue = .init(),
            };

            for (self.workers[1..self.num_threads], 1..) |*worker, thread_index| {
                if (std.Thread.spawn(.{}, threadMain, .{ self, thread_index })) |spawned_thread| {
                    worker.* = .{
                        .thread = spawned_thread,
                        .buffer = try TaskBuffer.initCapacity(self.allocator, queue_config.max_jobs),
                        .queue = .init(),
                        .prioqueue = .init(),
                    };

                    nameThread(worker.thread.?, "Task Worker[{}]", .{thread_index});
                } else |err| {
                    log.err("thread[{}]: {}\n", .{ thread_index, err });
                    self.num_threads = @intCast(thread_index);
                    break;
                }
            }
        }

        pub fn stop(self: *Self) void {
            const was_running = self.running.swap(false, .monotonic);
            std.debug.assert(was_running == true);

            for (self.workers[1..self.num_threads]) |*worker| {
                worker.thread.?.join();
            }
        }

        pub fn getWokerId(self: *const Self) u32 {
            _ = self;
            return THREAD_IDX;
        }

        pub fn schedule(self: *Self, prereq: public.TaskID, job: anytype, combinee: bool, config: public.ScheduleConfig) !public.TaskID {
            const Job = @TypeOf(job);

            const index = self.getNewTaskIdx();

            const slot: *Slot = &self.tasks[index];
            slot.combine = combinee;

            const id = slot.storeJob(Job, &job, index, prereq);

            if (config.affinity) |affinity| {
                // _ = affinity;
                var w = &self.workers[affinity];
                w.pushPrioJob(id);
            } else {
                var w = self.getWorker();
                w.pushJob(id);
            }
            self.job_signal.post();
            return id;
        }

        fn getNewTaskIdx(self: *Self) usize {
            return self.free_tasks.pop().?;
        }

        fn freeTaskIdx(self: *Self, idx: usize) void {
            const b = self.free_tasks.push(idx);
            std.debug.assert(b);
        }

        fn threadMain(self: *Self, thread_index: usize) void {
            THREAD_IDX = @intCast(thread_index);

            log.debug("Worker thread {d} spawned", .{self.getWokerId()});

            var buf: [std.Thread.max_name_len]u8 = undefined;
            if (std.fmt.bufPrintZ(&buf, "Worker {}", .{THREAD_IDX})) |name| {
                profiler.ztracy.SetThreadName(name);
            } else |err| {
                ignore(err);
            }

            while (self.isRunning()) {
                if (self.getWorkToDo(false)) |task| {
                    const slot = &self.tasks[task.index()];

                    if (slot.executeJob(task)) {
                        self.freeTaskIdx(task.index());
                    }
                } else {
                    //self.job_signal.timedWait(queue_config.idle_sleep_ns) catch undefined;
                    // self.job_signal.wait();
                    //std.Thread.yield() catch undefined;
                    std.Thread.sleep(queue_config.idle_sleep_ns);
                }
            }
        }

        fn nameThread(t: std.Thread, comptime fmt: []const u8, args: anytype) void {
            var buf: [std.Thread.max_name_len]u8 = undefined;
            if (std.fmt.bufPrint(&buf, fmt, args)) |name| {
                t.setName(name) catch |err| ignore(err);
            } else |err| {
                ignore(err);
            }
        }

        fn getWorker(self: *Self) *Worker {
            const wid = self.getWokerId();
            return &self.workers[wid];
        }

        fn getWorkToDo(self: *Self, only_prio: bool) ?public.TaskID {

            // var zone_ctx = profiler.ztracy.Zone(@src());
            // defer zone_ctx.End();

            const wid = self.getWokerId();
            var self_w = self.getWorker();
            self_w.buffer.clearRetainingCapacity();

            {
                defer {
                    // var zone_ctx = profiler.ztracy.Zone(@src());

                    for (0..self_w.buffer.items.len) |idx| {
                        self_w.pushPrioJob(self_w.buffer.items[idx]);
                    }
                    self_w.buffer.clearRetainingCapacity();

                    // zone_ctx.End();
                }

                while (self_w.popPrioJob()) |task| {
                    std.debug.assert(task != .none);

                    var slot = &self.tasks[task.index()];

                    // TODO: SHIT
                    if (slot.combine) {
                        const d: *CombineTask = @ptrCast(@alignCast(&slot.data));
                        var done = true;
                        for (d.prereqs) |p| {
                            if (!self.isDone(p)) {
                                done = false;
                                break;
                            }
                        }

                        if (!done) {
                            self_w.buffer.appendAssumeCapacity(task);
                            continue;
                        }
                    }

                    // Depend on other task?
                    if (slot.prereq != .none) {
                        const prereq_id = slot.prereq.fields();
                        std.debug.assert(isLiveCycle(prereq_id.cycle));

                        if (!self.isDone(slot.prereq)) {
                            self_w.buffer.appendAssumeCapacity(task);
                            continue;
                        } else {
                            return task;
                        }
                    } else {
                        return task;
                    }
                }
            }

            if (only_prio) {
                return null;
            }

            for (0..self.num_threads) |value| {
                const worker_idx = (wid + value) % self.num_threads;

                var w = &self.workers[worker_idx];

                defer {
                    // var zone_ctx = profiler.ztracy.Zone(@src());
                    for (0..self_w.buffer.items.len) |idx| {
                        if (!self.isDone(self_w.buffer.items[idx])) {
                            self_w.pushJob(self_w.buffer.items[idx]);
                        }
                    }
                    self_w.buffer.clearRetainingCapacity();
                    // zone_ctx.End();
                }

                while (w.stealJob()) |task| {
                    std.debug.assert(task != .none);

                    var slot = &self.tasks[task.index()];

                    // TODO: SHIT
                    if (slot.combine) {
                        const d: *CombineTask = @ptrCast(@alignCast(&slot.data));
                        var done = true;
                        for (d.prereqs) |p| {
                            if (!self.isDone(p)) {
                                done = false;
                                break;
                            }
                        }

                        if (!done) {
                            self_w.buffer.appendAssumeCapacity(task);
                            continue;
                        }
                    }

                    // Depend on other task?
                    if (slot.prereq != .none) {
                        const prereq_id = slot.prereq.fields();
                        std.debug.assert(isLiveCycle(prereq_id.cycle));

                        if (!self.isDone(slot.prereq)) {
                            self_w.buffer.appendAssumeCapacity(task);
                            continue;
                        } else {
                            return task;
                        }
                    } else {
                        return task;
                    }
                }
            }

            return null;
        }

        pub fn waitForManyTask(self: *Self, tasks: []const public.TaskID) void {
            // var zone_ctx = profiler.ztracy.Zone(@src());
            // defer zone_ctx.End();
            for (tasks) |task| {
                if (task == .none) continue;
                const _id = task.fields();

                std.debug.assert(isLiveCycle(_id.cycle));

                while (!self.isDone(task)) {
                    if (self.getWorkToDo(false)) |t| {
                        var task_slot = &self.tasks[t.index()];
                        if (task_slot.executeJob(t)) {
                            self.freeTaskIdx(t.index());
                        }
                    } else {
                        // self.job_signal.timedWait(queue_config.idle_sleep_ns) catch undefined;
                        // self.job_signal.wait();
                    }
                    std.Thread.sleep(queue_config.idle_sleep_ns);
                }
            }
        }

        pub fn doOneTask(self: *Self, only_prio: bool) void {
            if (self.getWorkToDo(only_prio)) |t| {
                var task_slot = &self.tasks[t.index()];
                if (task_slot.executeJob(t)) {
                    self.freeTaskIdx(t.index());
                }
            }
            std.Thread.sleep(queue_config.idle_sleep_ns);
        }

        pub fn isDone(self: *Self, task: public.TaskID) bool {
            if (task == .none) return true;

            const _id = task.fields();
            const cycle = _id.cycle;
            var slot: *Slot = &self.tasks[_id.index];
            const slot_cycle = slot.cycle.load(.monotonic);
            return slot_cycle != cycle;
        }

        const CombineTask = struct {
            const jobs_size = @sizeOf(*Self);
            const prereq_size = @sizeOf(public.TaskID);
            const max_prereqs = (queue_config.max_job_size - jobs_size) / prereq_size;

            jobs: *Self,
            prereqs: [max_prereqs]public.TaskID = @splat(public.TaskID.none),

            pub fn exec(_: *@This()) void {}
        };
        pub fn combine(self: *Self, prereqs: []const public.TaskID) !public.TaskID {
            if (prereqs.len == 0) return public.TaskID.none;
            if (prereqs.len == 1) return prereqs[0];

            var id = public.TaskID.none;
            var in: []const public.TaskID = prereqs;
            while (in.len > 0) {
                var job = CombineTask{ .jobs = self };

                const out: []public.TaskID = &job.prereqs;

                const copy_len = @min(in.len, out.len);
                std.mem.copyForwards(public.TaskID, out, in[0..copy_len]);
                in = in[copy_len..];

                id = try self.schedule(
                    id,
                    job,
                    true,
                    .{},
                );
            }
            return id;
        }
    };

    return Queue;
}

pub var api = public.TaskAPI{
    .scheduleFn = schedule,
    .waitFn = wait,
    .waitManyFn = waitMany,
    .combineFn = combine,
    .getThreadNumFn = getThreadNum,
    .getWorkerIdFn = getWorkerId,
    .isDoneFn = isDone,
    .doOneTaskFn = doOneTask,
};

fn getThreadNum() u64 {
    return _job_system.num_threads;
}

fn getWorkerId() usize {
    return _job_system.getWokerId();
}

fn doOneTask(only_prio: bool) void {
    _job_system.doOneTask(only_prio);
}

const JobSystemImpl = JobSystem(.{
    .idle_sleep_ns = 50,
    .max_job_size = 128,
    .max_jobs = 1024 * 4,
});

var _allocator: std.mem.Allocator = undefined;
var _job_system: JobSystemImpl = undefined;
pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    _job_system = try JobSystemImpl.init(allocator);
}

pub fn deinit() void {
    _job_system.deinit();
}

pub fn start(worker_count: ?u32) !void {
    try _job_system.start(worker_count);
}

pub fn stop() void {
    _job_system.stop();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.TaskAPI, &api);
}

fn schedule(prereq: public.TaskID, task: public.TaskStub, config: public.ScheduleConfig) !public.TaskID {
    const Job = struct {
        t: public.TaskStub,
        pub fn exec(self: *@This()) void {
            self.t.task_fn(&self.t.data) catch |err| {
                log.err("Task failed: {}", .{err});
            };
        }
    };

    const job_id = try _job_system.schedule(
        prereq,
        Job{ .t = task },
        false,
        config,
    );
    return job_id;
}

fn wait(prereq: public.TaskID) void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    _job_system.waitForManyTask(&.{prereq});
}

fn isDone(task: public.TaskID) bool {
    return _job_system.isDone(task);
}

fn waitMany(prereq: []const public.TaskID) void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    _job_system.waitForManyTask(prereq);
}

fn combine(prereq: []const public.TaskID) !public.TaskID {
    return _job_system.combine(prereq);
}

test "MPMCBoundedQueue" {
    const Q = cetech1.MPMCBoundedQueue(u32, 128);
    var q = Q.init();

    try std.testing.expect(null == q.pop());

    try std.testing.expect(q.push(1));
    try std.testing.expect(q.push(2));
    try std.testing.expect(q.push(3));
    try std.testing.expect(q.push(4));
    try std.testing.expect(q.push(5));

    try std.testing.expectEqual(1, q.pop());
    try std.testing.expectEqual(2, q.pop());
    try std.testing.expectEqual(3, q.pop());
    try std.testing.expectEqual(4, q.pop());
    try std.testing.expectEqual(5, q.pop());
}

test "task: basic test" {
    const allocator = std.testing.allocator;
    const Queue = JobSystem(.{ .max_threads = 4 });

    var job_system = try Queue.init(allocator);
    defer job_system.deinit();

    try job_system.start(null);
    defer job_system.stop();

    const TaskA = struct {
        job: *Queue,
        pub fn exec(self: *@This()) void {
            log.debug("Task A {}", .{self.job.getWokerId()});
        }
    };

    const TaskB = struct {
        job: *Queue,
        pub fn exec(self: *@This()) void {
            log.debug("Task B {}", .{self.job.getWokerId()});
        }
    };

    const TaskC = struct {
        job: *Queue,
        pub fn exec(self: *@This()) void {
            log.debug("Task C {}", .{self.job.getWokerId()});
        }
    };

    const t1 = try job_system.schedule(.none, TaskA{ .job = &job_system }, false, .{});
    const t2 = try job_system.schedule(t1, TaskB{ .job = &job_system }, false, .{});
    const t3 = try job_system.schedule(t2, TaskC{ .job = &job_system }, false, .{});
    job_system.waitForManyTask(&.{t3});

    try std.testing.expect(job_system.isDone(t1));
    try std.testing.expect(job_system.isDone(t2));
    try std.testing.expect(job_system.isDone(t3));

    const batch = [_]public.TaskID{
        try job_system.schedule(.none, TaskA{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskB{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskC{ .job = &job_system }, false, .{}),

        try job_system.schedule(.none, TaskA{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskB{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskC{ .job = &job_system }, false, .{}),

        try job_system.schedule(.none, TaskA{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskB{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskC{ .job = &job_system }, false, .{}),

        try job_system.schedule(.none, TaskA{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskB{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskC{ .job = &job_system }, false, .{}),

        try job_system.schedule(.none, TaskA{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskB{ .job = &job_system }, false, .{}),
        try job_system.schedule(.none, TaskC{ .job = &job_system }, false, .{}),
    };

    const batch_task = try job_system.combine(&batch);
    job_system.waitForManyTask(&.{batch_task});

    for (batch) |value| {
        try std.testing.expect(job_system.isDone(value));
    }
}

test "task: spawn task from task" {
    const allocator = std.testing.allocator;
    const Queue = JobSystem(.{ .max_threads = 4 });

    var job_system = try Queue.init(allocator);
    defer job_system.deinit();

    try job_system.start(null);
    defer job_system.stop();

    // log.err("dasdasdasda", .{});

    const TaskDep1 = struct {
        pub fn exec(self: *@This()) void {
            _ = self;
            std.Thread.sleep(std.time.ns_per_ms * 5);
        }
    };

    const TaskDep2 = struct {
        job: *Queue,
        pub fn exec(self: *@This()) void {
            const td1 = try self.job.schedule(.none, TaskDep1{}, false, .{});
            const td2 = try self.job.schedule(.none, TaskDep1{}, false, .{});
            const td3 = try self.job.schedule(.none, TaskDep1{}, false, .{});

            self.job.waitForManyTask(
                &.{
                    try self.job.combine(
                        &.{
                            try self.job.schedule(td1, TaskDep1{}, false, .{}),
                            try self.job.schedule(td2, TaskDep1{}, false, .{}),
                            try self.job.schedule(td3, TaskDep1{}, false, .{}),
                        },
                    ),
                },
            );
        }
    };

    job_system.waitForManyTask(
        &.{
            try job_system.combine(
                &.{
                    try job_system.schedule(.none, TaskDep2{ .job = &job_system }, false, .{}),
                    try job_system.schedule(.none, TaskDep2{ .job = &job_system }, false, .{}),
                    try job_system.schedule(.none, TaskDep2{ .job = &job_system }, false, .{}),
                },
            ),
        },
    );
}
