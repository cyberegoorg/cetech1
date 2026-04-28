const std = @import("std");

const cetech1 = @import("cetech1");
const apidb = cetech1.apidb;

pub const AssetBrowserAPI = struct {};

pub var api: *const AssetBrowserAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, AssetBrowserAPI).?;
}
