const std = @import("std");

const zjobs = @import("zjobs");

const apidb = @import("apidb.zig");
const log = @import("log.zig");
const profiler = @import("profiler.zig");

const cetech1 = @import("../cetech1.zig");

const MODULE_NAME = "task";

pub var api = cetech1.task.TaskAPI{
    .scheduleFn = schedule,
    .waitFn = wait,
    .combineFn = combine,
};

const JobQueue = zjobs.JobQueue(.{ .idle_sleep_ns = 1 });

var _allocator: std.mem.Allocator = undefined;
var _job_queue: JobQueue = undefined;
var _thread_to_name: std.AutoArrayHashMap(std.Thread.Id, []const u8) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    _job_queue = JobQueue.init();
    _thread_to_name = std.AutoArrayHashMap(std.Thread.Id, []const u8).init(allocator);
}

pub fn deinit() void {
    _job_queue.stop();
    _job_queue.deinit();
    _thread_to_name.deinit();
}

pub fn getThreadName(id: std.Thread.Id) []const u8 {
    return _thread_to_name.get(id) orelse "";
}

pub fn start() !void {
    var num_threads = @max(2, (std.Thread.getCpuCount() catch 2) - 1);
    log.api.info(MODULE_NAME, "NUM_THREADS {}", .{num_threads});

    _job_queue.start(.{ .num_threads = @truncate(num_threads) });

    const main_thread_id = std.Thread.getCurrentId();
    try _thread_to_name.put(main_thread_id, "main");
}

pub fn stop() void {
    _job_queue.stop();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(cetech1.task.TaskAPI, &api);
    // try apidb.api.setOrRemoveCApi(public.c.ct_log_api_t, &api_c, true, false);
}

fn taskToJob(t: cetech1.task.TaskID) zjobs.JobId {
    return @enumFromInt(@intFromEnum(t));
}

fn jobToTask(j: zjobs.JobId) cetech1.task.TaskID {
    return @enumFromInt(@intFromEnum(j));
}

fn schedule(prereq: cetech1.task.TaskID, task: cetech1.task.TaskStub) !cetech1.task.TaskID {
    const Job = struct {
        t: cetech1.task.TaskStub,
        pub fn exec(self: *@This()) void {
            self.t.task_fn(&self.t.data);
        }
    };

    const job_id: zjobs.JobId = try _job_queue.schedule(
        taskToJob(prereq),
        Job{ .t = task },
    );

    return jobToTask(job_id);
}

fn wait(prereq: cetech1.task.TaskID) void {
    var update_zone_ctx = profiler.ztracy.Zone(@src());
    defer update_zone_ctx.End();
    _job_queue.wait(taskToJob(prereq));
}

fn combine(prereq: []const cetech1.task.TaskID) !cetech1.task.TaskID {
    var prereq_j: *[]zjobs.JobId = @ptrFromInt(@intFromPtr(&prereq));

    var ret = try _job_queue.combine(prereq_j.*);
    return jobToTask(ret);
}
