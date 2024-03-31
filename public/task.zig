const std = @import("std");

// ID for tasks
pub const TaskID = enum(u32) {
    none,
    _,
};

/// Structure for task wrap
pub const TaskStub = struct {
    const Self = @This();
    const Data = [64 - 8]u8;
    const Main = *const fn (*Data) anyerror!void;
    data: Data = undefined,
    task_fn: Main,
};

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
    pub fn wait(self: Self, prereq: TaskID) void {
        self.waitFn(prereq);
    }

    /// Combine given TaskIds to one.
    pub fn combine(self: Self, prereq: []const TaskID) !TaskID {
        return self.combineFn(prereq);
    }

    //#region Pointers to implementation
    scheduleFn: *const fn (prereq: TaskID, task: TaskStub) anyerror!TaskID,
    waitFn: *const fn (prereq: TaskID) void,
    combineFn: *const fn (prereq: []const TaskID) anyerror!TaskID,
    getThreadNum: *const fn () u64,
    //#endregions
};
