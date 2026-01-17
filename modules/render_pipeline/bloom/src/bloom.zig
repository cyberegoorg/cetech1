const std = @import("std");

const cetech1 = @import("cetech1");

pub const BloomComponent = struct {
    enabled: bool = true,
    bloom_intensity: f32 = 1.0,
};
