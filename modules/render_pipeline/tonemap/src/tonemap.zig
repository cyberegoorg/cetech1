const std = @import("std");

const cetech1 = @import("cetech1");

pub const TonemapType = enum(u8) {
    aces = 0,
    uncharted,
    luma_debug,
};

pub const TonemapComponent = struct {
    type: TonemapType = .aces,
};
