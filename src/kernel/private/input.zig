const std = @import("std");
const builtin = @import("builtin");

const apidb = cetech1.apidb;

const cetech1 = @import("cetech1");
const public = cetech1.input;

const module_name = .input;

const log = std.log.scoped(module_name);

const api = public.InputApi{
    .getSourceByType = getSourceByType,
};

var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    public.api = &api;
    _allocator = allocator;
}

pub fn deinit() void {}

pub fn registerToApi() !void {
    try apidb.setZigApi(module_name, public.InputApi, &api);
}

pub fn dumpControlers(allocator: std.mem.Allocator) !void {
    log.info("Input sources:", .{});

    const impls = try apidb.getImpl(allocator, public.InputSourceI);
    defer allocator.free(impls);
    for (impls) |iface| {
        log.info("     - {s}", .{iface.name});

        log.info("         - controlers:", .{});
        for (try iface.getControllers(allocator)) |controler| {
            log.info("              - {d}", .{controler});
        }

        log.debug("         - items:", .{});
        for (iface.getItems()) |item| {
            log.debug("              - {s}:{d}", .{ item.name, item.id });
        }
    }
}

fn getSourceByType(allocator: std.mem.Allocator, input_type: cetech1.StrId32) ?*const public.InputSourceI {
    const impls = apidb.getImpl(allocator, public.InputSourceI) catch return null;
    defer allocator.free(impls);
    for (impls) |iface| {
        if (iface.input_type.eql(input_type)) return iface;
    }
    return null;
}
