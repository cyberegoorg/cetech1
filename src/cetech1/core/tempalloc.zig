//! Kernel is entry point/runner for engine.

const std = @import("std");

pub const TempAllocApi = struct {
    createTempArena: *const fn () anyerror!*std.heap.ArenaAllocator,
    destroyTempArena: *const fn (arena: *std.heap.ArenaAllocator) void,
};
