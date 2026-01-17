const std = @import("std");
const vectors = @import("vectors.zig");

const Vec3f = vectors.Vec3f;
const Vec4f = vectors.Vec4f;

pub const Color3f = Color3(f32);
pub const Color4f = Color4(f32);

pub fn Color3(comptime T: type) type {
    return extern struct {
        r: T = 0,
        g: T = 0,
        b: T = 0,

        const Self = @This();

        pub const black: Self = .{};
        pub const white: Self = .{ .r = 1, .g = 1, .b = 1 };
        pub const red: Self = .{ .r = 1 };

        pub fn toVec3f(self: Self) Vec3f {
            return @bitCast(self);
        }
    };
}

pub fn Color4(comptime T: type) type {
    return extern struct {
        r: T = 0,
        g: T = 0,
        b: T = 0,
        a: T = 1,

        const Self = @This();

        pub const black: Self = .{};
        pub const white: Self = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
        pub const red: Self = .{ .r = 1, .a = 1 };
        pub const one_alpha: Self = .{ .a = 1 };

        pub fn toVec4f(self: Self) Vec4f {
            return @bitCast(self);
        }

        pub fn toColor3f(self: Self) Color3f {
            return .{ .r = self.r, .g = self.g, .b = self.b };
        }

        pub fn fromColor4f(v: Color3f, a: T) Self {
            return .{ .r = v.r, .g = v.g, .b = v.b, .a = a };
        }
    };
}

pub const SRGBA = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    const Self = @This();

    pub const white: Self = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };

    pub fn fromU32(v: u32) Self {
        return @bitCast(v);
    }

    pub fn toU32(self: Self) u32 {
        return @bitCast(self);
    }

    pub fn fromColor3f(color: Color3f) Self {
        return .{
            .r = @intFromFloat(color.r * 255),
            .g = @intFromFloat(color.g * 255),
            .b = @intFromFloat(color.b * 255),
            .a = 255,
        };
    }

    pub fn fromColor4f(color: Color4f) Self {
        return .{
            .r = @intFromFloat(color.r * 255),
            .g = @intFromFloat(color.g * 255),
            .b = @intFromFloat(color.b * 255),
            .a = @intFromFloat(color.a * 255),
        };
    }

    pub fn eql(self: Self, b: Self) bool {
        return std.meta.eql(self, b);
    }
};
