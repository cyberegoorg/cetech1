// I realy hate file, dirs and paths.
// Full of alloc shit and another braindump solution. Need cleanup but its works =).

const std = @import("std");
const apidb = cetech1.apidb;

const cetech1 = @import("cetech1");
const tempalloc = cetech1.tempalloc;
const cdb = cetech1.cdb;
const uuid = cetech1.uuid;
const host = cetech1.host;
const cdb_types = cetech1.cdb_types;
const coreui = cetech1.coreui;
const task = cetech1.task;
const profiler = cetech1.profiler;

const public = cetech1.assetdb;

const assetroot_fs = @import("assetdb_fs.zig");

const propIdx = cdb.propIdx;

test {
    _ = std.testing.refAllDecls(@import("assetdb_test.zig"));
}

const AssetIOSet = cetech1.ArraySet(*public.AssetIOI);

const module_name = .assetdb;

const log = std.log.scoped(module_name);

// Type for root of all assets
pub const AssetRootCdb = public.AssetRootCdb;
var assetroot_fs_provider_i: *const public.AssetRootProviderI = undefined;

//
const api = public.AssetDBAPI{
    .findFirstAssetIOForExport = findFirstAssetIOForExport,
    .findFirstAssetIOForImport = findFirstAssetIOForImport,
    .createAsset = createAsset,
    .createImportedAsset = createImportedAsset,
    .openAssetRootFolder = openAssetRootFolder,
    .getRootFolder = getRootFolder,
    .getTmpPath = getTmpPath,
    .isAssetModified = isObjModified,
    .isProjectModified = isProjectModified,
    .saveAllModifiedAssets = saveAllModifiedAssets,
    .saveAllAssets = saveAll,
    .saveAsset = saveAssetAndWait,
    .getAssetForObj = getAssetForObj,
    .getObjForAsset = getObjForAsset,
    .isAssetFolder = isAssetFolder,
    .isProjectOpened = isProjectOpened,
    .getFilePathForAsset = getFilePathForAsset,
    .getPathForAsset = getPathForAsset,
    .getPathForFolder = getPathForFolder,
    .getAssetByPath = getAssetByPath,
    .createNewFolder = createNewFolder,
    .isAssetNameValid = isAssetNameValid,
    .saveAsAllAssets = saveAsAllAssets,
    .deleteAsset = deleteAsset,
    .deleteFolder = deleteFolder,
    .isToDeleted = isToDeleted,
    .reviveDeleted = reviveDeleted,
    .buffGetValidName = buffGetValidName,
    .isRootFolder = isRootFolder,
    .isAssetObjTypeOf = isAssetObjTypeOf,
    .openInOs = openInOs,
    .createNewAssetFromPrototype = createNewAssetFromPrototype,
    .cloneNewAssetFrom = cloneNewAssetFrom,
    .isObjAssetObj = isObjAssetObj,
    .getDb = getDb,
    .getAssetRootPath = getAssetRootPath,
    .getAssetRootObj = getAssetRootObj,
    .filerAsset = filerAsset,
    .setAssetNameAndFolder = setAssetNameAndFolder,
};

var _allocator: std.mem.Allocator = undefined;
var _io: std.Io = undefined;
var _db: cdb.DbId = undefined;
var _assetroot: public.AssetRootI = undefined;

// var AssetRootTypeIdx: cdb.TypeIdx = undefined;
var AssetTypeIdx: cdb.TypeIdx = undefined;
var FolderTypeIdx: cdb.TypeIdx = undefined;

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // Asset type is wrapper for asset object
        AssetTypeIdx = cdb.addType(
            db,
            public.AssetCdb.name,
            &.{
                .{ .prop_idx = public.AssetCdb.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                .{ .prop_idx = public.AssetCdb.propIdx(.Description), .name = "description", .type = cdb.PropType.STR },
                .{ .prop_idx = public.AssetCdb.propIdx(.Folder), .name = "folder", .type = cdb.PropType.REFERENCE, .type_hash = public.FolderCdb.type_hash },
                .{ .prop_idx = public.AssetCdb.propIdx(.Tags), .name = "tags", .type = cdb.PropType.REFERENCE_SET, .type_hash = public.TagCdb.type_hash },
                .{ .prop_idx = public.AssetCdb.propIdx(.Object), .name = "object", .type = cdb.PropType.SUBOBJECT },
            },
        ) catch unreachable;

        // Asset folder
        // TODO as regular asset
        FolderTypeIdx = cdb.addType(
            db,
            public.FolderCdb.name,
            &.{
                .{ .prop_idx = public.FolderCdb.propIdx(.Color), .name = "color", .type = cdb.PropType.SUBOBJECT, .type_hash = cdb_types.Color4fCdb.type_hash },
            },
        ) catch unreachable;

        // All assets is parent of this
        _ = cdb.addType(
            db,
            AssetRootCdb.name,
            &.{
                .{ .prop_idx = AssetRootCdb.propIdx(.Assets), .name = "assets", .type = cdb.PropType.SUBOBJECT_SET },
            },
        ) catch unreachable;

        // Project
        _ = cdb.addType(
            db,
            public.ProjectCdb.name,
            &.{
                .{ .prop_idx = public.ProjectCdb.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                .{ .prop_idx = public.ProjectCdb.propIdx(.Organization), .name = "organization", .type = cdb.PropType.STR },
            },
        ) catch unreachable;

        const ct_asset_tag_type = cdb.addType(
            db,
            public.TagCdb.name,
            &.{
                .{ .prop_idx = public.TagCdb.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                .{ .prop_idx = public.TagCdb.propIdx(.Color), .name = "color", .type = cdb.PropType.SUBOBJECT, .type_hash = cdb_types.Color4fCdb.type_hash },
            },
        ) catch unreachable;
        _ = ct_asset_tag_type;

        const ct_tags = cdb.addType(
            db,
            public.TagsCdb.name,
            &.{
                .{ .prop_idx = public.TagsCdb.propIdx(.Tags), .name = "tags", .type = cdb.PropType.REFERENCE_SET, .type_hash = public.TagCdb.type_hash },
            },
        ) catch unreachable;
        _ = ct_tags;

        _ = cetech1.cdb_types.addBigType(db, public.FooAsset.name, public.FooAsset.type_hash) catch unreachable;
        _ = cetech1.cdb_types.addBigType(db, public.BarAsset.name, null) catch unreachable;
        _ = cetech1.cdb_types.addBigType(db, public.BazAsset.name, null) catch unreachable;
    }
});

pub fn registerToApi() !void {
    try apidb.setZigApi(module_name, public.AssetDBAPI, &api);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, true);
}

pub fn getDb() cdb.DbId {
    return _db;
}

pub fn init(io: std.Io, allocator: std.mem.Allocator) !void {
    _allocator = allocator;
    _io = io;
    _db = try cdb.createDb("AssetDB");

    try assetroot_fs.init(allocator, io, _db);

    const providers = try apidb.getImpl(allocator, public.AssetRootProviderI);
    defer allocator.free(providers);

    assetroot_fs_provider_i = providers[0];

    _assetroot = try assetroot_fs_provider_i.create();

    public.api = &api;
}

pub fn deinit() void {
    assetroot_fs_provider_i.destroy(_assetroot);
    cdb.destroyDb(_db);
}

fn filerAsset(allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cdb.ObjId) !public.FilteredAssets {
    var result = cetech1.ArrayList(public.FilteredAsset).empty;
    var buff: [256:0]u8 = undefined;
    var buff2: [256:0]u8 = undefined;
    var buff3: [256:0]u8 = undefined;

    var filter_set = cetech1.AutoArrayHashMap(cdb.ObjId, void).empty;
    defer filter_set.deinit(allocator);

    if (cdb.readObj(tags_filter)) |filter_r| {
        if (public.TagsCdb.readRefSet(filter_r, .Tags, allocator)) |tags| {
            defer allocator.free(tags);
            for (tags) |tag| {
                try filter_set.put(allocator, tag, {});
            }
        }
    }

    const set = try public.AssetRootCdb.readSubObjSet(cdb.readObj(getAssetRootObj()).?, .Assets, allocator);
    if (set) |s| {
        defer allocator.free(s);

        for (s) |obj| {
            if (obj.eql(getRootFolder())) continue;

            if (filter_set.count() != 0) {
                if (cdb.readObj(obj)) |asset_r| {
                    if (public.AssetCdb.readRefSet(asset_r, .Tags, allocator)) |asset_tags| {
                        defer allocator.free(asset_tags);

                        var pass_n: u32 = 0;
                        for (asset_tags) |tag| {
                            if (filter_set.contains(tag)) pass_n += 1;
                        }
                        if (pass_n != filter_set.count()) continue;
                    }
                }
            }

            const path = try getFilePathForAsset(&buff3, obj);

            const f = try std.fmt.bufPrintZ(&buff, "{s}", .{filter});
            const p = try std.fmt.bufPrintZ(&buff2, "{s}", .{path});

            const score = coreui.uiFilterPass(allocator, f, p, true) orelse continue;
            try result.append(allocator, .{ .score = score, .obj = obj });
        }
    }

    return result.toOwnedSlice(allocator);
}

fn isRootFolder(asset: cdb.ObjId) bool {
    const obj = getObjForAsset(asset) orelse return false;
    if (!obj.type_idx.eql(FolderTypeIdx)) return false;
    return public.AssetCdb.readRef(public.AssetCdb.read(asset).?, .Folder) == null;
}

fn isAssetObjTypeOf(asset: cdb.ObjId, type_idx: cdb.TypeIdx) bool {
    const obj = getObjForAsset(asset) orelse return false;
    return obj.type_idx.eql(type_idx);
}

fn isObjAssetObj(obj: cdb.ObjId) bool {
    const parent = cdb.getParent(obj);
    if (parent.isEmpty()) return false;
    return parent.type_idx.eql(AssetTypeIdx);
}

fn getAssetForObj(obj: cdb.ObjId) ?cdb.ObjId {
    var it: cdb.ObjId = obj;

    while (!it.isEmpty()) {
        if (it.type_idx.eql(AssetTypeIdx)) {
            return it;
        }
        it = cdb.getParent(it);
    }
    return null;
}

fn isAssetFolder(asset: cdb.ObjId) bool {
    if (!asset.type_idx.eql(AssetTypeIdx)) return false;

    if (getObjForAsset(asset)) |obj| {
        return obj.type_idx.eql(FolderTypeIdx);
    }
    return false;
}

fn getObjForAsset(obj: cdb.ObjId) ?cdb.ObjId {
    if (!obj.type_idx.eql(AssetTypeIdx)) return null;
    return public.AssetCdb.readSubObj(cdb.readObj(obj).?, .Object).?;
}

fn isProjectOpened() bool {
    return _assetroot.isProjectOpened();
}

pub fn isObjModified(asset: cdb.ObjId) bool {
    return _assetroot.isObjModified(asset);
}

pub fn isProjectModified() bool {
    return _assetroot.isModified();
}

pub fn getTmpPath(path_buf: []u8) !?[]u8 {
    return _assetroot.getTmpPath(_io, path_buf);
}

pub fn findFirstAssetIOForImport(filename: []const u8, extension: []const u8) ?*const public.AssetIOI {
    const impls = apidb.getImpl(_allocator, public.AssetIOI) catch return null;
    defer _allocator.free(impls);
    for (impls) |asset_io| {
        if (asset_io.can_import != null and asset_io.can_import.?(filename, extension)) return asset_io;
    }

    return null;
}

pub fn findFirstAssetIOForExport(db: cdb.DbId, asset: cdb.ObjId, filename: []const u8, extension: []const u8) ?*const public.AssetIOI {
    const impls = apidb.getImpl(_allocator, public.AssetIOI) catch return null;
    defer _allocator.free(impls);
    for (impls) |asset_io| {
        if (asset_io.can_export != null and asset_io.can_export.?(db, asset, filename, extension)) return asset_io;
    }
    return null;
}

fn getRootFolder() cdb.ObjId {
    return _assetroot.getRootFolder();
}

fn deleteAsset(asset: cdb.ObjId) anyerror!void {
    try _assetroot.deleteAsset(asset);
}

fn deleteFolder(folder: cdb.ObjId) anyerror!void {
    try _assetroot.deleteFolder(folder);
}

fn isToDeleted(asset_or_folder: cdb.ObjId) bool {
    return _assetroot.isToDeleted(asset_or_folder);
}

fn reviveDeleted(asset_or_folder: cdb.ObjId) void {
    return _assetroot.reviveDeleted(asset_or_folder);
}

fn openAssetRootFolder(asset_root_path: []const u8, allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.Zone(@src());
    defer zone_ctx.End();
    return _assetroot.openAssetRootFolder(_io, asset_root_path, allocator);
}

fn setAssetNameAndFolder(asset_w: *cdb.Obj, name: []const u8, description: ?[]const u8, asset_folder: cdb.ObjId) !void {
    var buffer: [128]u8 = undefined;

    if (name.len != 0) {
        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{name});
        try public.AssetCdb.setStr(asset_w, .Name, str);
    }

    if (description) |desc| {
        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{desc});
        try public.AssetCdb.setStr(asset_w, .Description, str);
    }

    if (!asset_folder.isEmpty()) {
        try public.AssetCdb.setRef(asset_w, .Folder, getObjForAsset(asset_folder).?);
    }
}

fn createAsset(asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId {
    const asset = public.AssetCdb.createObject(_db) catch return null;
    const asset_w = cdb.writeObj(asset).?;

    if (asset_obj != null) {
        const asset_obj_w = cdb.writeObj(asset_obj.?).?;
        public.AssetCdb.setSubObj(asset_w, .Object, asset_obj_w) catch return null;

        cdb.writeCommit(asset_obj_w) catch return null;
    }

    setAssetNameAndFolder(asset_w, asset_name, null, asset_folder) catch return null;

    cdb.writeCommit(asset_w) catch return null;

    _assetroot.addAssetToRoot(_io, asset) catch return null;
    return asset;
}

fn createImportedAsset(asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: cdb.ObjId, imported_from: []const u8) ?cdb.ObjId {
    return _assetroot.createImportedAsset(asset_name, asset_folder, asset_obj, imported_from);
}

pub fn saveAssetAndWait(allocator: std.mem.Allocator, asset: cdb.ObjId) !void {
    if (asset.type_idx.eql(AssetTypeIdx)) {
        const export_task = try _assetroot.saveAsset(_io, allocator, _assetroot.getAssetRootPath().?, asset);
        task.wait(export_task);
    } else if (asset.type_idx.eql(FolderTypeIdx)) {
        try _assetroot.saveFolderObj(_io, allocator, getAssetForObj(asset).?, _assetroot.getAssetRootPath().?);
    }
}

pub fn saveAll(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.Zone(@src());
    defer zone_ctx.End();

    try _assetroot.saveAll(_io, allocator);
}

pub fn saveAllModifiedAssets(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.Zone(@src());
    defer zone_ctx.End();

    try _assetroot.saveAllModifiedAssets(_io, allocator);
}

fn getPathForFolder(buff: []u8, from_folder: cdb.ObjId) ![]u8 {
    const root_folder_name = public.AssetCdb.readStr(cdb.readObj(getAssetForObj(from_folder).?).?, .Name);

    var pos = buff.len;
    if (root_folder_name != null) {
        var first = true;
        var folder_it: ?cdb.ObjId = from_folder;

        while (folder_it) |folder| {
            const folder_r = cdb.readObj(getAssetForObj(folder).?).?;

            const folder_name = public.AssetCdb.readStr(folder_r, .Name) orelse break;

            pos -= try writeLeft(pos, buff, &.{std.fs.path.sep});
            pos -= try writeLeft(pos, buff, folder_name);

            first = false;

            folder_it = public.AssetCdb.readRef(folder_r, .Folder);
        }
    }
    if (pos == buff.len) return buff[0..0];
    return buff[pos..];
}

pub fn getAssetByPath(path: []const u8) ?cdb.ObjId {
    const asset_uuid = _assetroot.getAssetUuid(_io, path) orelse return null;
    return cdb.getObjId(_db, asset_uuid);
}

pub fn getFilePathForAsset(buff: []u8, asset: cdb.ObjId) ![]u8 {
    const asset_r = cdb.readObj(asset);
    const asset_obj = public.AssetCdb.readSubObj(asset_r.?, .Object).?;

    // append asset type extension
    return getPathForAsset(buff, asset, cdb.getTypeName(_db, asset_obj.type_idx).?);
}

fn writeLeft(pos: usize, buff: []u8, data: []const u8) !usize {
    const new_pos = pos - data.len;
    @memcpy(buff[new_pos .. new_pos + data.len], data[0..data.len]);
    return data.len;
}

fn getPathForAsset(buff: []u8, asset: cdb.ObjId, extension: ?[]const u8) ![]u8 {
    var pos = buff.len;
    if (extension) |ex| {
        pos -= try writeLeft(pos, buff, ex);
        pos -= try writeLeft(pos, buff, ".");
    }

    // add asset name
    const asset_r = cdb.readObj(asset);
    if (public.AssetCdb.readStr(asset_r.?, .Name)) |asset_name| {
        pos -= try writeLeft(pos, buff, asset_name);
    }

    // make sub path
    var folder_it = public.AssetCdb.readRef(asset_r.?, .Folder);
    while (folder_it) |folder| {
        const folder_asset_r = cdb.readObj(getAssetForObj(folder).?).?;
        folder_it = public.AssetCdb.readRef(folder_asset_r, .Folder) orelse break;

        const folder_name = public.AssetCdb.readStr(folder_asset_r, .Name) orelse continue;

        pos -= try writeLeft(pos, buff, &.{std.fs.path.sep});
        pos -= try writeLeft(pos, buff, folder_name);
    }

    return buff[pos..];
}

fn createNewFolder(db: cdb.DbId, parent_folder: cdb.ObjId, name: [:0]const u8) !cdb.ObjId {
    std.debug.assert(parent_folder.type_idx.eql(AssetTypeIdx));

    const new_folder_asset = try public.AssetCdb.createObject(db);

    const new_folder = try public.FolderCdb.createObject(db);
    const new_folder_w = cdb.writeObj(new_folder).?;
    const new_folder_asset_w = cdb.writeObj(new_folder_asset).?;

    try public.AssetCdb.setSubObj(new_folder_asset_w, .Object, new_folder_w);
    try public.AssetCdb.setStr(new_folder_asset_w, .Name, name);
    try public.AssetCdb.setRef(new_folder_asset_w, .Folder, getObjForAsset(parent_folder).?);

    try cdb.writeCommit(new_folder_w);
    try cdb.writeCommit(new_folder_asset_w);

    try _assetroot.addAssetToRoot(_io, new_folder_asset);

    return new_folder;
}

fn saveAsAllAssets(allocator: std.mem.Allocator, path: []const u8) !void {
    var zone_ctx = profiler.Zone(@src());
    defer zone_ctx.End();

    try _assetroot.saveAsAllAssets(_io, allocator, path);
}

fn buffGetValidName(allocator: std.mem.Allocator, buf: [:0]u8, folder_: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) ![:0]const u8 {
    const folder = getObjForAsset(folder_).?;

    const db = cdb.getDbFromObjid(folder_);

    const set = try cdb.getReferencerSet(allocator, folder);
    defer allocator.free(set);

    var name_set = cetech1.ArraySet([]const u8).empty;
    defer name_set.deinit(allocator);

    if (!type_idx.eql(FolderTypeIdx)) {
        for (set) |obj| {
            if (!obj.type_idx.eql(cdb.getTypeIdx(db, public.AssetCdb.type_hash).?)) continue;

            const asset_obj = public.AssetCdb.readSubObj(cdb.readObj(obj).?, .Object).?;
            if (!asset_obj.type_idx.eql(type_idx)) continue;

            if (public.AssetCdb.readStr(cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    } else {
        for (set) |obj| {
            if (!isAssetFolder(obj)) continue;
            //if (obj.type_hash.id != public.Folder.type_hash.id) continue;

            if (public.AssetCdb.readStr(cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    }

    var number: u32 = 2;
    var name: [:0]const u8 = base_name;
    while (name_set.contains(name)) : (number += 1) {
        name = try std.fmt.bufPrintZ(buf, "{s}{d}", .{ base_name, number });
    }

    return name;
}

fn openInOs(allocator: std.mem.Allocator, open_type: host.OpenInType, asset: cdb.ObjId) !void {
    if (_assetroot.getAssetRootPath()) |asset_root_path| {
        var buff: [128:0]u8 = undefined;
        const path = try getFilePathForAsset(&buff, asset);

        const path_with_json = try std.fmt.allocPrint(allocator, "{s}.json", .{path});
        defer allocator.free(path_with_json);

        const full_path = try std.fs.path.join(allocator, &.{ asset_root_path, path_with_json });
        defer allocator.free(full_path);

        try host.openIn(allocator, open_type, full_path);
    }
}

fn createNewAssetFromPrototype(asset: cdb.ObjId) !cdb.ObjId {
    const assset_r = public.AssetCdb.read(asset).?;

    const asset_obj = getObjForAsset(asset).?;

    const folder = public.AssetCdb.readRef(assset_r, .Folder).?;
    const folder_asset = getAssetForObj(folder).?;
    const asset_name = public.AssetCdb.readStr(assset_r, .Name).?;

    var buff: [256:0]u8 = undefined;
    const name = try buffGetValidName(
        _allocator,
        &buff,
        folder_asset,
        asset_obj.type_idx,
        asset_name,
    );

    const new_asset_obj = try cdb.createObjectFromPrototype(asset_obj);
    return createAsset(name, folder_asset, new_asset_obj).?;
}

fn cloneNewAssetFrom(asset: cdb.ObjId) !cdb.ObjId {
    const assset_r = public.AssetCdb.read(asset).?;

    const asset_obj = getObjForAsset(asset).?;

    const folder = public.AssetCdb.readRef(assset_r, .Folder).?;
    const folder_asset = getAssetForObj(folder).?;
    const asset_name = public.AssetCdb.readStr(assset_r, .Name).?;

    var buff: [256:0]u8 = undefined;
    const name = try buffGetValidName(
        _allocator,
        &buff,
        folder_asset,
        asset_obj.type_idx,
        asset_name,
    );

    const new_asset_obj = try cdb.cloneObject(asset_obj);
    return createAsset(name, folder_asset, new_asset_obj).?;
}

fn getAssetRootPath() ?[]const u8 {
    return _assetroot.getAssetRootPath();
}

fn getAssetRootObj() cdb.ObjId {
    return _assetroot.getAssetRootObj();
}

fn isAssetNameValid(allocator: std.mem.Allocator, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) !bool {
    const set = try cdb.getReferencerSet(allocator, folder);
    defer allocator.free(set);

    var name_set = cetech1.ArraySet([]const u8).empty;
    defer name_set.deinit(allocator);

    if (!type_idx.eql(FolderTypeIdx)) {
        for (set) |obj| {
            if (!obj.type_idx.eql(AssetTypeIdx)) continue;

            const asset_obj = public.AssetCdb.readSubObj(cdb.readObj(obj).?, .Object).?;
            if (asset_obj.type_idx.idx != type_idx.idx) continue;

            if (public.AssetCdb.readStr(cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    } else {
        for (set) |obj| {
            if (!obj.type_idx.eql(AssetTypeIdx)) continue;

            if (public.AssetCdb.readStr(cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    }

    return !name_set.contains(base_name);
}
