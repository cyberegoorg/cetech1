const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const api_registry = @import("api_registry.zig");

pub const ModulesAPI = struct {
    const Self = @This();
    pub const ModuleApiFn = fn (api_registry: *api_registry.ApiRegistryAPI, allocator: Allocator, load: bool, reload: bool) anyerror!void;
    pub const ModulePair = struct { name: []const u8, module_fce: *const ModuleApiFn };
    pub const ModulesList = std.DoublyLinkedList(ModulePair);

    allocator: Allocator,
    modules: ModulesList,
    api_reg: *api_registry.ApiRegistryAPI,

    pub fn init(allocator: Allocator, api_reg: *api_registry.ApiRegistryAPI) Self {
        return Self{ .modules = ModulesList{}, .allocator = allocator, .api_reg = api_reg };
    }

    pub fn addStaticModule(self: *Self, modules: []const ModulePair) !void {
        for (modules) |v| {
            var node = try self.allocator.create(ModulesList.Node);
            node.* = ModulesList.Node{ .data = v };
            self.modules.append(node);
        }
    }

    pub fn loadAll(self: *Self) !void {
        var it = self.modules.first;
        while (it) |node| : (it = node.next) {
            try node.data.module_fce(self.api_reg, self.allocator, true, false);
        }
    }

    pub fn unloadAll(self: *Self) !void {
        var it = self.modules.last;
        while (it) |node| : (it = node.prev) {
            try node.data.module_fce(self.api_reg, self.allocator, false, false);
        }
    }
};
