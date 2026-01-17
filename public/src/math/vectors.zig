pub const Vec2f = Vec2(f32);
pub const Vec3f = Vec3(f32);
pub const Vec4f = Vec4(f32);

pub const F32x4 = @Vector(4, f32);

pub fn Vec2(comptime T: type) type {
    return extern struct {
        x: T = 0,
        y: T = 0,

        const Self = @This();

        pub const up: Self = .{ .y = 1 };
        pub const down: Self = .{ .y = -1 };
        pub const right: Self = .{ .x = 1, .y = 0 };
        pub const left: Self = .{ .x = -1, .y = 0 };

        pub fn toF32x4(self: Self) F32x4 {
            return .{
                self.x,
                self.y,
                0,
                0,
            };
        }

        pub fn fromF32x4(value: F32x4) Self {
            return .{
                .x = value[0],
                .y = value[1],
            };
        }

        pub fn toArray(self: Self) [2]T {
            return @bitCast(self);
        }

        pub fn fromArray(v: [2]T) Self {
            return @bitCast(v);
        }

        pub fn splat(scalar: T) Self {
            return .{ .x = scalar, .y = scalar };
        }

        pub fn add(self: Self, b: Self) Self {
            return .{
                .x = self.x + b.x,
                .y = self.y + b.y,
            };
        }

        pub fn sub(self: Self, b: Self) Self {
            return .{
                .x = self.x - b.x,
                .y = self.y - b.y,
            };
        }

        pub fn mul(self: Self, b: Self) Self {
            return .{
                .x = self.x * b.x,
                .y = self.y * b.y,
            };
        }

        pub fn mulAdd(self: Self, b: Self, c: Self) Self {
            return .{
                .x = self.x * b.x + c.x,
                .y = self.y * b.y + c.y,
            };
        }

        pub fn div(self: Self, b: Self) Self {
            return .{
                .x = self.x / b.x,
                .y = self.y / b.y,
            };
        }

        pub fn increase(self: *Self, v: Self) void {
            self.x += v.x;
            self.y += v.y;
        }

        pub fn decrase(self: *Self, v: Self) void {
            self.x -= v.x;
            self.y -= v.y;
        }

        pub fn inverse(self: Self) Self {
            return .{
                .x = 1.0 / self.x,
                .y = 1.0 / self.y,
            };
        }

        pub fn negative(self: Self) Self {
            return .{
                .x = -self.x,
                .y = -self.y,
            };
        }

        pub fn dot(self: Self, b: Self) T {
            return self.x * b.x + self.y * b.y;
        }

        pub fn length(self: Self) T {
            return @sqrt(self.dot(self));
        }

        pub fn lengthSq(self: Self) T {
            return self.dot(self);
        }

        pub fn normalized(self: Self) Self {
            return .div(self, .splat(self.length()));
        }

        pub fn lerp(self: Self, b: Self, t: T) Self {
            return .{
                .x = self.x + (b.x - self.x) * t,
                .y = self.y + (b.y - self.y) * t,
            };
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return extern struct {
        x: T = 0,
        y: T = 0,
        z: T = 0,

        const Self = @This();

        pub const up: Self = .{ .y = 1 };
        pub const down: Self = .{ .y = -1 };
        pub const right: Self = .{ .x = 1 };
        pub const left: Self = .{ .x = -1 };
        pub const forward: Self = .{ .z = 1 };
        pub const backward: Self = .{ .z = -1 };

        pub fn toF32x4(self: Self) F32x4 {
            return .{
                self.x,
                self.y,
                self.z,
                0,
            };
        }

        pub fn fromF32x4(value: F32x4) Self {
            return .{
                .x = value[0],
                .y = value[1],
                .z = value[2],
            };
        }

        pub fn toArray(self: Self) [3]T {
            return @bitCast(self);
        }

        pub fn fromArray(v: [3]T) Self {
            return @bitCast(v);
        }

        pub fn splat(scalar: T) Self {
            return .{ .x = scalar, .y = scalar, .z = scalar };
        }

        pub fn add(self: Self, b: Self) Self {
            return .{
                .x = self.x + b.x,
                .y = self.y + b.y,
                .z = self.z + b.z,
            };
        }

        pub fn sub(self: Self, b: Self) Self {
            return .{
                .x = self.x - b.x,
                .y = self.y - b.y,
                .z = self.z - b.z,
            };
        }

        pub fn mul(self: Self, b: Self) Self {
            return .{
                .x = self.x * b.x,
                .y = self.y * b.y,
                .z = self.z * b.z,
            };
        }

        pub fn mulAdd(self: Self, b: Self, c: Self) Self {
            return .{
                .x = self.x * b.x + c.x,
                .y = self.y * b.y + c.y,
                .z = self.z * b.z + c.z,
            };
        }

        pub fn div(self: Self, b: Self) Self {
            return .{
                .x = self.x / b.x,
                .y = self.y / b.y,
                .z = self.z / b.z,
            };
        }

        pub fn increase(self: *Self, v: Self) void {
            self.x += v.x;
            self.y += v.y;
            self.z += v.z;
        }

        pub fn decrase(self: *Self, v: Self) void {
            self.x -= v.x;
            self.y -= v.y;
            self.z -= v.z;
        }

        pub fn inverse(self: Self) Self {
            return .{
                .x = 1.0 / self.x,
                .y = 1.0 / self.y,
                .z = 1.0 / self.z,
            };
        }

        pub fn negative(self: Self) Self {
            return .{
                .x = -self.x,
                .y = -self.y,
                .z = -self.z,
            };
        }

        pub fn dot(self: Self, b: Self) T {
            return (self.x * b.x) + (self.y * b.y) + (self.z * b.z);
        }

        pub fn cross(a: Self, b: Self) Self {
            return .{
                .x = a.y * b.z - a.z * b.y,
                .y = a.z * b.x - a.x * b.z,
                .z = a.x * b.y - a.y * b.x,
            };
        }

        pub fn length(self: Self) T {
            return @sqrt(self.dot(self));
        }

        pub fn lengthSq(self: Self) T {
            return self.dot(self);
        }

        pub fn normalized(self: Self) Self {
            return self.div(.splat(self.length()));
        }

        pub fn lerp(self: Self, b: Self, t: T) Self {
            return .{
                .x = self.x + (b.x - self.x) * t,
                .y = self.y + (b.y - self.y) * t,
                .z = self.z + (b.z - self.z) * t,
            };
        }
    };
}

pub fn Vec4(comptime T: type) type {
    return extern struct {
        x: T = 0,
        y: T = 0,
        z: T = 0,
        w: T = 0,

        const Self = @This();

        pub const up: Self = .{ .y = 1 };
        pub const down: Self = .{ .y = -1 };
        pub const right: Self = .{ .x = 1 };
        pub const left: Self = .{ .x = -1 };
        pub const forward: Self = .{ .z = 1 };
        pub const backward: Self = .{ .z = -1 };

        pub fn toF32x4(self: Self) F32x4 {
            return @bitCast(self);
        }

        pub fn fromF32x4(value: F32x4) Self {
            return @bitCast(value);
        }

        pub fn toArray(self: Self) [4]T {
            return @bitCast(self);
        }

        pub fn fromArray(v: [4]T) Self {
            return @bitCast(v);
        }

        pub fn splat(scalar: T) Self {
            return .{ .x = scalar, .y = scalar, .z = scalar, .w = scalar };
        }

        pub fn add(self: Self, b: Self) Self {
            return .{
                .x = self.x + b.x,
                .y = self.y + b.y,
                .z = self.z + b.z,
                .w = self.w + b.w,
            };
        }

        pub fn sub(self: Self, b: Self) Self {
            return .{
                .x = self.x - b.x,
                .y = self.y - b.y,
                .z = self.z - b.z,
                .w = self.w - b.w,
            };
        }

        pub fn mul(self: Self, b: Self) Self {
            return .{
                .x = self.x * b.x,
                .y = self.y * b.y,
                .z = self.z * b.z,
                .w = self.w * b.w,
            };
        }

        pub fn mulAdd(self: Self, b: Self, c: Self) Self {
            return .{
                .x = self.x * b.x + c.x,
                .y = self.y * b.y + c.y,
                .z = self.z * b.z + c.z,
                .w = self.w * b.w + c.w,
            };
        }

        pub fn div(self: Self, b: Self) Self {
            return .{
                .x = self.x / b.x,
                .y = self.y / b.y,
                .z = self.z / b.z,
                .w = self.w / b.w,
            };
        }

        pub fn increase(self: *Self, v: Self) void {
            self.x += v.x;
            self.y += v.y;
            self.z += v.z;
            self.w += v.w;
        }

        pub fn decrase(self: *Self, v: Self) void {
            self.x -= v.x;
            self.y -= v.y;
            self.z -= v.z;
            self.w -= v.w;
        }

        pub fn inverse(self: Self) Self {
            return .{
                .x = 1.0 / self.x,
                .y = 1.0 / self.y,
                .z = 1.0 / self.z,
                .w = 1.0 / self.w,
            };
        }

        pub fn negative(self: Self) Self {
            return .{
                .x = -self.x,
                .y = -self.y,
                .z = -self.z,
                .w = -self.w,
            };
        }

        pub fn dot(self: Self, b: Self) T {
            return (self.x * b.x) + (self.y * b.y) + (self.z * b.z) + (self.w * b.w);
        }

        pub fn length(self: Self) T {
            return @sqrt(self.dot(self));
        }

        pub fn lengthSq(self: Self) T {
            return self.dot(self);
        }

        pub fn normalized(self: Self) Self {
            return .div(self, .splat(self.length()));
        }

        pub fn lerp(self: Self, b: Self, t: T) Self {
            return .{
                .x = self.x + (b.x - self.x) * t,
                .y = self.y + (b.y - self.y) * t,
                .z = self.z + (b.z - self.z) * t,
                .w = self.w + (b.w - self.w) * t,
            };
        }
    };
}
