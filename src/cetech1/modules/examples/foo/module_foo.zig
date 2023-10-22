pub const c = @cImport({
    @cInclude("cetech1/modules/examples/foo/foo.h");
});

pub const FooAPI = struct {
    const Self = @This();
    fff: f32 = 11,

    pub fn foo1(self: *Self, arg1: f32) f32 {
        return arg1 + self.fff;
    }

    pub fn foo1_c(arg1: f32) callconv(.C) f32 {
        return arg1 + 1111;
    }
};
