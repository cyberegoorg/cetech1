const std = @import("std");

const apidb = @import("apidb.zig");

const cetech1 = @import("cetech1");
const cetech1_options = @import("cetech1_options");
const public = cetech1.host;

const znfde = @import("znfde");

const module_name = .host_dialogs_znfde;

const log = std.log.scoped(module_name);

pub const dialogs_api = public.DialogsApi{
    .supportFileDialog = supportFileDialog,
    .openFileDialog = openFileDialog,
    .saveFileDialog = saveFileDialog,
    .openFolderDialog = openFolderDialog,
};

pub fn init() !void {
    if (cetech1_options.with_nfd) try znfde.init();
}

pub fn deinit() void {
    if (cetech1_options.with_nfd) znfde.deinit();
}

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.DialogsApi, &dialogs_api);
}

fn supportFileDialog() bool {
    return cetech1_options.with_nfd;
}

fn openFileDialog(allocator: std.mem.Allocator, filter: ?[]const public.DialogsFilterItem, default_path: ?[:0]const u8) !?[:0]const u8 {
    if (cetech1_options.with_nfd) {
        return znfde.openFileDialog(allocator, @ptrCast(filter), default_path);
    }
    return null;
}

fn saveFileDialog(allocator: std.mem.Allocator, filter: ?[]const public.DialogsFilterItem, default_path: ?[:0]const u8, default_name: ?[:0]const u8) !?[:0]const u8 {
    if (cetech1_options.with_nfd) {
        return znfde.saveFileDialog(allocator, @ptrCast(filter), default_path, default_name);
    }

    return null;
}

fn openFolderDialog(allocator: std.mem.Allocator, default_path: ?[:0]const u8) !?[:0]const u8 {
    if (cetech1_options.with_nfd) {
        return znfde.openFolderDialog(allocator, default_path);
    }
    return null;
}
