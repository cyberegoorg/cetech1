const std = @import("std");

const api_registry = @import("api_registry.zig");
const modules = @import("modules.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const Kernel = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    api_reg_api: *api_registry.ApiRegistryAPI,
    modules_api: modules.ModulesAPI,

    pub fn init() !Self {
        var allocator = gpa.allocator();

        var api_reg_api = try allocator.create(api_registry.ApiRegistryAPI);
        api_reg_api.* = api_registry.ApiRegistryAPI.init(allocator);

        return Self{ .allocator = allocator, .api_reg_api = api_reg_api, .modules_api = modules.ModulesAPI.init(allocator, api_reg_api) };
    }

    pub fn powerOn(self: *Self, static_modules: ?[]const modules.ModulesAPI.ModulePair) !void {
        if (static_modules != null) {
            try self.modules_api.addStaticModule(static_modules.?);
        }
        try self.modules_api.loadAll();
    }

    pub fn powerOff(self: *Self) !void {
        try self.modules_api.unloadAll();
    }
};
