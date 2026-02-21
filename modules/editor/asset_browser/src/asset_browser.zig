const std = @import("std");

const cetech1 = @import("cetech1");
const apidb = cetech1.apidb;

pub const AssetBrowserAPI = struct {};

pub var api: *const AssetBrowserAPI = undefined;

pub fn loadAPI(comptime module: @Type(.enum_literal)) !void {
    api = apidb.getZigApi(module, AssetBrowserAPI).?;
}
