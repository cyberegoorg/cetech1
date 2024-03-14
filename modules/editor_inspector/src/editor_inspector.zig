const std = @import("std");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const strid = cetech1.strid;
const coreui = cetech1.coreui;

const log = std.log.scoped(.editor_inspector);

const editor = @import("editor");

pub const UiPropertiesConfigAspect = extern struct {
    pub const c_name = "ct_properties_config_aspect";
    pub const name_hash = strid.strId32(@This().c_name);
    hide_prototype: bool = false,
};

pub const UiPropertyConfigAspect = extern struct {
    pub const c_name = "ct_ui_property_config_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    hide_prototype: bool = false,
};

pub const UiVisualPropertyConfigAspect = extern struct {
    pub const c_name = "ct_ui_visual_property_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    no_subtree: bool = false,
};

pub const cdbPropertiesViewArgs = extern struct {
    filter: ?[*:0]const u8 = null,
};

pub const UiEmbedPropertyAspect = extern struct {
    pub const c_name = "ct_ui_embed_property_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_properties: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiEmbedPropertyAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiEmbedPropertyAspect{
            .ui_properties = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                    prop_idx: u32,
                    args: cdbPropertiesViewArgs,
                ) callconv(.C) void {
                    T.ui(allocator.*, db, obj, prop_idx, args) catch |err| {
                        log.err("UiEmbedPropertyAspect.ui() failed with error {}", .{err});
                    };
                }
            }.f,
        };
    }
};

pub const UiEmbedPropertiesAspect = extern struct {
    pub const c_name = "ct_ui_embed_properties_aspect";
    pub const name_hash = strid.strId32(UiEmbedPropertiesAspect.c_name);

    ui_properties: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        obj: cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiEmbedPropertiesAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiEmbedPropertiesAspect{
            .ui_properties = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                    args: cdbPropertiesViewArgs,
                ) callconv(.C) void {
                    T.ui(allocator.*, db, obj, args) catch |err| {
                        log.err("UiEmbedPropertiesAspect.ui() failed with error {}", .{err});
                    };
                }
            }.f,
        };
    }
};

pub const hidePropertyAspect = UiPropertyAspect{};

pub const UiPropertyAspect = extern struct {
    pub const c_name = "ct_ui_property_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_property: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        cdb.ObjId,
        prop_idx: u32,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiPropertyAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiPropertyAspect{
            .ui_property = struct {
                pub fn f(
                    allocator: *const std.mem.Allocator,
                    db: *cdb.Db,
                    obj: cdb.ObjId,
                    prop_idx: u32,
                    args: cdbPropertiesViewArgs,
                ) callconv(.C) void {
                    T.ui(allocator.*, db, obj, prop_idx, args) catch |err| {
                        log.err("UiPropertyAspect.ui() failed with error {}", .{err});
                    };
                }
            }.f,
        };
    }
};

pub const UiPropertiesAspect = extern struct {
    pub const c_name = "ct_ui_properties_aspect";
    pub const name_hash = strid.strId32(@This().c_name);

    ui_properties: ?*const fn (
        allocator: *const std.mem.Allocator,
        db: *cdb.Db,
        tab: *editor.TabO,
        obj: cdb.ObjId,
        args: cdbPropertiesViewArgs,
    ) callconv(.C) void = null,

    pub inline fn implement(comptime T: type) UiPropertiesAspect {
        if (!std.meta.hasFn(T, "ui")) @compileError("implement me");

        return UiPropertiesAspect{ .ui_properties = struct {
            pub fn f(
                allocator: *const std.mem.Allocator,
                db: *cdb.Db,
                tab: *editor.TabO,
                obj: cdb.ObjId,
                args: cdbPropertiesViewArgs,
            ) callconv(.C) void {
                T.ui(allocator.*, db, tab, obj, args) catch |err| {
                    log.err("UiPropertiesAspect.ui() failed with error {}", .{err});
                };
            }
        }.f };
    }
};

pub const InspectorAPI = struct {
    uiPropLabel: *const fn (allocator: std.mem.Allocator, name: [:0]const u8, color: ?[4]f32, args: cdbPropertiesViewArgs) bool,
    uiPropInput: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputRaw: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputBegin: *const fn (db: *cdb.CdbDb, obj: cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputEnd: *const fn () void,
    uiAssetInput: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, tab: *editor.TabO, obj: cdb.ObjId, prop_idx: u32, read_only: bool, in_table: bool) anyerror!void,

    // Property utils
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,

    // Property view
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, tab: *editor.TabO, obj: cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, db: *cdb.CdbDb, tab: *editor.TabO, obj: cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,

    beginSection: *const fn (label: [:0]const u8, leaf: bool, default_open: bool) bool,
    endSection: *const fn (open: bool) void,

    beginPropTable: *const fn (name: [:0]const u8) bool,
    endPropTabel: *const fn () void,
};
