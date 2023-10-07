const std = @import("std");

pub const TaskID = enum(u32) {
    none,
    _,
};

pub const TaskStub = struct {
    const Self = @This();
    const Data = [64 - 8]u8;
    const Main = *const fn (*Data) void;
    data: Data = undefined,
    task_fn: Main,
};

pub const TaskAPI = struct {
    const Self = @This();

    pub fn schedule(self: *Self, prereq: TaskID, task: anytype) !TaskID {
        const T = @TypeOf(task);

        const exec: *const fn (*T) void = &@field(T, "exec");
        const true_exec = @as(TaskStub.Main, @ptrCast(exec));
        var t = TaskStub{ .task_fn = true_exec };

        @memset(&t.data, 0);
        std.mem.copy(u8, &t.data, std.mem.asBytes(&task));

        return try self.scheduleFn.?(prereq, t);
    }

    pub fn wait(self: *Self, prereq: TaskID) void {
        self.waitFn.?(prereq);
    }

    pub fn combine(self: *Self, prereq: []const TaskID) !TaskID {
        return self.combineFn.?(prereq);
    }

    scheduleFn: ?*const fn (prereq: TaskID, task: TaskStub) anyerror!TaskID,
    waitFn: ?*const fn (prereq: TaskID) void,
    combineFn: ?*const fn (prereq: []const TaskID) anyerror!TaskID,
};
