pub const FooAPI = struct {
    const Self = @This();
    fff: f32 = 11,

    pub fn foo1(self: *Self, arg1: f32) f32 {
        return arg1 + self.fff;
    }
};
