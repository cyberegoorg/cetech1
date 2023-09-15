//!zig-autodoc-guide: ../../docs/intro.md

pub const api_registry = @import("core/api_registry.zig");
pub const modules = @import("core/modules.zig");
pub const kernel = @import("core/kernel.zig");

pub const ApiRegistryAPI = api_registry.ApiRegistryAPI;
pub const ModulesAPI = modules.ModulesAPI;
pub const Kernel = kernel.Kernel;

test {
    @import("std").testing.refAllDecls(@This());
}
