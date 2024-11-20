const std = @import("std");
const profiler = @import("profiler.zig");

// ID for tasks
pub const TaskID = enum(u32) {
    none,
    _,

    pub fn format(
        id: TaskID,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const f = id.fields();
        return writer.print("{}:{}", .{ f.index, f.cycle });
    }

    pub inline fn cycle(id: TaskID) u16 {
        return id.fields().cycle;
    }

    pub inline fn index(id: TaskID) u16 {
        return id.fields().index;
    }

    pub inline fn fields(id: *const TaskID) Fields {
        return @as(*const Fields, @ptrCast(id)).*;
    }

    pub const Fields = packed struct {
        cycle: u16, // lo bits
        index: u16, // hi bits

        pub inline fn init(_index: u16, _cycle: u16) Fields {
            return .{ .index = _index, .cycle = _cycle };
        }

        pub inline fn id(_fields: *const Fields) TaskID {
            comptime std.debug.assert(@sizeOf(Fields) == @sizeOf(TaskID));
            return @as(*const TaskID, @ptrCast(_fields)).*;
        }
    };
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

pub const default_bacth_size = 64;

pub const BatchWorkloadArgs = struct {
    allocator: std.mem.Allocator,
    task_api: *const TaskAPI,
    profiler_api: *const profiler.ProfilerAPI,

    batch_size: usize = default_bacth_size,
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
    const items_count = args.count;

    if (items_count <= args.batch_size) {
        var a = args;
        a.batch_size = a.count;

        const t = CREATE_TASK_FCE.createTask(create_args, 0, a, args.count);
        return try args.task_api.schedule(.none, t);
    }

    const batch_count = items_count / args.batch_size;
    const batch_rest = items_count - (batch_count * args.batch_size);

    var tasks = try std.ArrayList(TaskID).initCapacity(args.allocator, batch_count);
    defer tasks.deinit();

    for (0..batch_count - 1) |batch_id| {
        const task = CREATE_TASK_FCE.createTask(create_args, batch_id, args, args.batch_size);
        const task_id = try args.task_api.schedule(TaskID.none, task);
        tasks.appendAssumeCapacity(task_id);
    }

    const last_batch_id = batch_count - 1;
    const task = CREATE_TASK_FCE.createTask(create_args, last_batch_id, args, args.batch_size + batch_rest);
    const task_id = try args.task_api.schedule(TaskID.none, task);
    tasks.appendAssumeCapacity(task_id);

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

    /// Wait for given task
    pub inline fn waitMany(self: Self, prereq: []const TaskID) void {
        self.waitManyFn(prereq);
    }

    /// Combine given TaskIds to one.
    pub inline fn combine(self: Self, prereq: []const TaskID) !TaskID {
        return self.combineFn(prereq);
    }

    /// Get worker thread count.
    pub inline fn getThreadNum(self: Self) u64 {
        return self.getThreadNumFn();
    }

    /// Get worker id 0..N.
    /// 0 == main thread.
    pub inline fn getWorkerId(self: Self) usize {
        return self.getWorkerIdFn();
    }

    //#region Pointers to implementation
    scheduleFn: *const fn (prereq: TaskID, task: TaskStub) anyerror!TaskID,
    waitManyFn: *const fn (prereq: []const TaskID) void,
    waitFn: *const fn (prereq: TaskID) void,
    combineFn: *const fn (prereq: []const TaskID) anyerror!TaskID,
    getThreadNumFn: *const fn () u64,
    getWorkerIdFn: *const fn () usize,
    //#endregions
};
