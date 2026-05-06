const std = @import("std");
const profiler = @import("profiler.zig");
const cetech1 = @import("../cetech1.zig");

const apidb = cetech1.apidb;
pub const TaskIdList = cetech1.ArrayList(TaskID);

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

/// Structure for task wrap
pub const TaskStub = struct {
    const Self = @This();
    const Data = [128 - 8]u8;
    const Main = *const fn (*Data) anyerror!void;
    data: Data = undefined,
    task: Main,
};

pub const default_batch_size = 32;

pub const BatchWorkloadArgs = struct {
    allocator: std.mem.Allocator,
    batch_size: usize = default_batch_size,
    count: usize,
};

pub fn batchWorkloadTask(
    args: BatchWorkloadArgs,
    create_args: anytype,
    comptime CREATE_TASK_FCE: type,
) !?TaskID {
    var zone_ctx = profiler.ZoneN(@src(), "batchWorkloadTask");
    defer zone_ctx.End();

    if (args.count == 0) return null;
    const items_count = args.count;
    const batch_size_by_workers = args.batch_size; //items_count / @max(1, args.task_api.getThreadNum() - 1);
    const batch_size = if (batch_size_by_workers == 0) items_count else batch_size_by_workers;
    // std.log.debug("dddd {d}", .{batch_size});

    if (items_count <= batch_size) {
        var a = args;
        a.batch_size = a.count;

        const t = CREATE_TASK_FCE.createTask(create_args, 0, a, args.count);
        return try schedule(
            .none,
            t,
            .{},
        );
    }

    const batch_count = items_count / batch_size;
    const batch_rest = items_count - (batch_count * batch_size);

    var tasks = try TaskIdList.initCapacity(args.allocator, if (batch_rest == 0) batch_count else batch_count + 1);
    defer tasks.deinit(args.allocator);

    const aargs = args;
    // aargs.batch_size = batch_size;

    for (0..batch_count) |batch_id| {
        if (batch_rest > 0 and (batch_id == batch_count - 1)) {
            const task = CREATE_TASK_FCE.createTask(create_args, batch_id, aargs, batch_size + batch_rest);
            const task_id = try schedule(
                TaskID.none,
                task,
                .{},
            );
            tasks.appendAssumeCapacity(task_id);
        } else {
            const task = CREATE_TASK_FCE.createTask(create_args, batch_id, aargs, batch_size);
            const task_id = try schedule(
                TaskID.none,
                task,
                .{},
            );
            tasks.appendAssumeCapacity(task_id);
        }
    }

    return if (tasks.items.len == 0) null else try combine(tasks.items);
}

pub const ScheduleConfig = struct {
    affinity: ?u32 = null,
};

/// Schedule given work and return its TaskID.
pub fn schedule(prereq: TaskID, task: anytype, config: ScheduleConfig) !TaskID {
    const T = @TypeOf(task);

    const exec: *const fn (*T) anyerror!void = &@field(T, "exec");
    const true_exec = @as(TaskStub.Main, @ptrCast(exec));
    var t = TaskStub{ .task = true_exec };

    @memset(&t.data, 0);
    std.mem.copyForwards(u8, &t.data, std.mem.asBytes(&task));

    return try api.schedule(prereq, t, config);
}

/// Wait for given task
pub inline fn wait(prereq: TaskID) void {
    api.wait(prereq);
}

/// Wait for given task
pub inline fn waitMany(prereq: []const TaskID) void {
    api.waitMany(prereq);
}

/// Combine given TaskIds to one.
pub inline fn combine(prereq: []const TaskID) !TaskID {
    return api.combine(prereq);
}

/// Get worker thread count.
pub inline fn getThreadNum() u64 {
    return api.getThreadNum();
}

/// Get worker id 0..N.
/// 0 == main thread.
pub inline fn getWorkerId() usize {
    return api.getWorkerId();
}

pub inline fn isDone(task: TaskID) bool {
    return api.isDone(task);
}

pub inline fn doOneTask(only_prio: bool) void {
    api.doOneTask(only_prio);
}

/// Main task API
pub const TaskAPI = struct {
    schedule: *const fn (prereq: TaskID, task: TaskStub, config: ScheduleConfig) anyerror!TaskID,
    waitMany: *const fn (task: []const TaskID) void,
    wait: *const fn (task: TaskID) void,
    isDone: *const fn (task: TaskID) bool,
    combine: *const fn (tasks: []const TaskID) anyerror!TaskID,
    getThreadNum: *const fn () u64,
    getWorkerId: *const fn () usize,
    doOneTask: *const fn (only_prio: bool) void,
};

pub var api: *const TaskAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, TaskAPI).?;
}
