const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const coreui = cetech1.coreui;
const cdb = cetech1.cdb;
const assetdb = cetech1.assetdb;
const editor = @import("editor");
const editor_assetdb = @import("editor_assetdb");

const Icons = cetech1.coreui.CoreIcons;

const module_name = .editor_fixtures;

pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
const log = std.log.scoped(module_name);

var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;

// Global state
const G = struct {};
var _g: *G = undefined;

// Create foo asset
var create_foo_asset_i = editor_assetdb.CreateAssetI.implement(
    cetech1.assetdb.FooAsset.type_hash,
    struct {
        pub fn create(
            allocator: std.mem.Allocator,
            db: cdb.DbId,
            folder: cdb.ObjId,
        ) !void {
            var buff: [256:0]u8 = undefined;
            const name = try assetdb.buffGetValidName(
                allocator,
                &buff,
                folder,
                cdb.getTypeIdx(db, cetech1.assetdb.FooAsset.type_hash).?,
                "NewFooAsset",
            );
            const new_obj = try cetech1.assetdb.FooAsset.createObject(db);

            _ = assetdb.createAsset(name, folder, new_obj);
        }

        pub fn menuItem() ![:0]const u8 {
            return coreui.Icons.Smile ++ "  " ++ "Foo";
        }
    },
);

// Folder visual aspect
var foo_visual_aspect = editor.UiVisualAspect.implement(struct {
    pub fn uiIcons(
        buff: [:0]u8,
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
    ) ![:0]const u8 {
        _ = allocator;
        _ = obj;

        return try std.fmt.bufPrintZ(
            buff,
            "{s}",
            .{
                coreui.Icons.Smile,
            },
        );
    }
});

// Create cdb types
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        try cetech1.assetdb.FooAsset.addAspect(
            editor.UiVisualAspect,

            db,
            &foo_visual_aspect,
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    // basic
    _allocator = allocator;

    try cdb.loadAPI(module_name);

    try editor.loadAPI(module_name);
    try assetdb.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, editor_assetdb.CreateAssetI, &create_foo_asset_i, load);
    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor_fixtures(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
