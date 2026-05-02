const std = @import("std");

const cetech1 = @import("../cetech1.zig");

pub const BloomComponent = extern struct {
    enabled: bool = true,
    bloom_intensity: f32 = 1.0,
};
