const std = @import("std");
const profiler = @import("profiler.zig");

// ID for tasks
pub const TaskID = enum(u32) {
    none,
    _,
};

pub const TaskIDList = std.ArrayList(TaskID);

/// Structure for task wrap
pub const TaskStub = struct {
    const Self = @This();
    const Data = [128 - 8]u8;
    const Main = *const fn (*Data) anyerror!void;
    data: Data = undefined,
    task_fn: Main,
};

pub const BatchWorkloadArgs = struct {
    allocator: std.mem.Allocator,
    task_api: *const TaskAPI,
    profiler_api: *const profiler.ProfilerAPI,

    batch_size: usize = 32,
    count: usize,
};

pub fn batchWorkloadTask(
    args: BatchWorkloadArgs,
    create_args: anytype,
    comptime CREATE_TASK_FCE: type,
) !?TaskID {
    var zone_ctx = args.profiler_api.ZoneN(@src(), "batchWorkloadTask");
    defer zone_ctx.End();

    if (args.count == 0) return null;
    const worker_count = args.task_api.getThreadNum();
    const items_count = args.count;

    if (items_count <= args.batch_size) {
        var a = args;
        a.batch_size = a.count;

        const t = CREATE_TASK_FCE.createTask(create_args, 0, a, args.count);
        const task_id = try args.task_api.schedule(
            TaskID.none,
            t,
        );
        return task_id;
    }

    const batch_count = items_count / args.batch_size;
    const batch_rest = items_count - (batch_count * args.batch_size);

    var tasks = try std.ArrayList(TaskID).initCapacity(args.allocator, batch_count);
    defer tasks.deinit();

    var my_tasks = try std.ArrayList(@typeInfo(@TypeOf(CREATE_TASK_FCE.createTask)).@"fn".return_type.?).initCapacity(args.allocator, batch_count);
    defer my_tasks.deinit();

    for (0..batch_count - 1) |batch_id| {
        const task = CREATE_TASK_FCE.createTask(create_args, batch_id, args, args.batch_size);

        if (0 != batch_id % worker_count) {
            const task_id = try args.task_api.schedule(TaskID.none, task);
            tasks.appendAssumeCapacity(task_id);
        } else {
            my_tasks.appendAssumeCapacity(task);
        }
    }

    const last_batch_id = batch_count - 1;
    my_tasks.appendAssumeCapacity(CREATE_TASK_FCE.createTask(create_args, last_batch_id, args, args.batch_size + batch_rest));
    for (my_tasks.items) |*t| {
        try t.exec();
    }

    return if (tasks.items.len == 0) null else try args.task_api.combine(tasks.items);
}

/// Main task API
pub const TaskAPI = struct {
    const Self = @This();

    /// Schedule given work and return its TaskID.
    pub fn schedule(self: Self, prereq: TaskID, task: anytype) !TaskID {
        const T = @TypeOf(task);

        const exec: *const fn (*T) anyerror!void = &@field(T, "exec");
        const true_exec = @as(TaskStub.Main, @ptrCast(exec));
        var t = TaskStub{ .task_fn = true_exec };

        @memset(&t.data, 0);
        std.mem.copyForwards(u8, &t.data, std.mem.asBytes(&task));

        return try self.scheduleFn(prereq, t);
    }

    /// Wait for given task
    pub inline fn wait(self: Self, prereq: TaskID) void {
        self.waitFn(prereq);
    }

    /// Combine given TaskIds to one.
    pub inline fn combine(self: Self, prereq: []const TaskID) !TaskID {
        return self.combineFn(prereq);
    }

    /// Get worker thread count.
    pub inline fn getThreadNum(self: Self) u64 {
        return self.getThreadNumFn();
    }

    //#region Pointers to implementation
    scheduleFn: *const fn (prereq: TaskID, task: TaskStub) anyerror!TaskID,
    waitFn: *const fn (prereq: TaskID) void,
    combineFn: *const fn (prereq: []const TaskID) anyerror!TaskID,
    getThreadNumFn: *const fn () u64,
    //#endregions
};
