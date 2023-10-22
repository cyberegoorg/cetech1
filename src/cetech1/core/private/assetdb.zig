// I realy hate file, dirs and paths.
// Full of alloc shit and another braindump solution. Need cleanup but its works =).

const std = @import("std");
const apidb = @import("apidb.zig");
const task = @import("task.zig");
const cdb = @import("cdb.zig");
const cdb_test = @import("cdb_test.zig");
const log = @import("log.zig");
const uuid = @import("uuid.zig");
const tempalloc = @import("tempalloc.zig");

const c = @import("../c.zig");
const public = @import("../assetdb.zig");
const cetech1 = @import("../cetech1.zig");
const propIdx = cetech1.cdb.propIdx;

const Uuid2ObjId = std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.cdb.ObjId);
const ObjId2Uuid = std.AutoArrayHashMap(cetech1.cdb.ObjId, cetech1.uuid.Uuid);

// File info
// TODO: to struct
const Path2Folder = std.StringArrayHashMap(cetech1.cdb.ObjId);
const Uuid2AssetUuid = std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.uuid.Uuid);
const AssetUuid2Path = std.AutoArrayHashMap(cetech1.uuid.Uuid, []u8);
const AssetUuid2Depend = std.AutoArrayHashMap(cetech1.uuid.Uuid, UuidSet);
const AssetObjIdVersion = std.AutoArrayHashMap(cetech1.cdb.ObjId, u64);

const AssetIOSet = std.AutoArrayHashMap(*public.AssetIOI, void);

pub const MODULE_NAME = "assetdb";

// Keywords for json format
const JSON_ASSET_VERSION = "__version";
const JSON_ASSET_UUID_TOKEN = "__asset_uuid";
const JSON_TYPE_NAME_TOKEN = "__type_name";
const JSON_UUID_TOKEN = "__uuid";
const JSON_PROTOTYPE_UUID = "__prototype_uuid";
const JSON_REMOVED_POSTFIX = "__removed";
const JSON_INSTANTIATE_POSTFIX = "__instantiate";

const CT_ASSETS_FILE_PREFIX = ".ct_";
const BLOB_EXTENSION = "ct_blob";
pub const CT_TEMP_FOLDER = ".ct_temp";

const ASSET_CURRENT_VERSION_STR = "0.1.0";
const ASSET_CURRENT_VERSION = std.SemanticVersion.parse(ASSET_CURRENT_VERSION_STR) catch undefined;

// Type for root of all assets
pub const AssetRootType = cetech1.cdb.CdbTypeDecl(
    "ct_asset_root",
    enum(u32) {
        Assets = 0,
        Folders,
    },
);

const WriteBlobFn = *const fn (
    blob: []const u8,
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    tmp_allocator: std.mem.Allocator,
) anyerror!void;

const ReadBlobFn = *const fn (
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    tmp_allocator: std.mem.Allocator,
) anyerror![]u8;

pub var api = public.AssetDBAPI{
    .createAssetFn = createAsset,
    .openAssetRootFolderFn = openAssetRootFolder,
    .getRootFolderFn = getRootFolder,
    .getObjIdFn = getObjId,
    .getUuidFn = getUuid,
    .addAssetIOFn = addAssetIO,
    .removeAssetIOFn = removeAssetIO,
    .getTmpPathFn = getTmpPath,
    .isAssetModifiedFn = isObjModified,
    .isProjectModifiedFn = isProjectModified,
    .saveAllModifiedAssetsFn = saveAllModifiedAssets,
    .saveAllAssetsFn = saveAll,
    .saveAssetFn = saveAssetAndWait,
    .getAssetForObj = getAssetForObj,
    .isProjectOpened = isProjectOpened,
    .getFilePathForAsset = getFilePathForAsset,
    .createNewFolder = createNewFolder,
};

var asset_root_type: cetech1.strid.StrId32 = undefined;

var _allocator: std.mem.Allocator = undefined;
var _db: *cetech1.cdb.CdbDb = undefined;

var _asset_root: cetech1.cdb.ObjId = undefined;
var _asset_root_lock: std.Thread.Mutex = undefined;
var _asset_root_last_version: u64 = undefined;
var _asset_root_folder: cetech1.cdb.ObjId = undefined;
var _asset_root_path: ?[]const u8 = null;

var _uuid2objid: Uuid2ObjId = undefined;
var _objid2uuid: ObjId2Uuid = undefined;
var _uuid2objid_lock: std.Thread.Mutex = .{};

var _assetio_set: AssetIOSet = undefined;

// file info
var _file_info_lck = std.Thread.Mutex{};
var _path2folder: Path2Folder = undefined;
var _uuid2asset_uuid: Uuid2AssetUuid = undefined;
var _asset_uuid2path: AssetUuid2Path = undefined;
var _asset_uuid2depend: AssetUuid2Depend = undefined;
var _asset_bag: cetech1.bagraph.BAG(cetech1.uuid.Uuid) = undefined;

var _tmp_depend_array: std.ArrayList(cetech1.task.TaskID) = undefined;
var _tmp_taskid_map: std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.task.TaskID) = undefined;

var _asset_objid2version: AssetObjIdVersion = undefined;
var _asset_objid2version_lck = std.Thread.Mutex{};

//TODO:
//  without lock? (actualy problem when creating ref_placeholder and real ref).
//  ref_placeholder is needed because there is unsorderd order for load. ordered need analyze phase for UUID.
//var _get_or_create_lock = std.Thread.Mutex{};

var _cdb_asset_io_i = public.AssetIOI.implement(struct {
    pub fn canImport(extension: []const u8) bool {
        var type_name = extension[1..];
        const type_hash = cetech1.strid.strId32(type_name);
        return _db.getTypePropDef(type_hash) != null;
    }

    pub fn canExport(db: *cetech1.cdb.CdbDb, asset: cetech1.cdb.ObjId, extension: []const u8) bool {
        var type_name = extension[1..];
        const type_hash = cetech1.strid.strId32(type_name);

        var asset_obj = public.AssetType.readSubObj(db, db.readObj(asset).?, .Object) orelse return false;
        return asset_obj.type_hash.id == type_hash.id;
    }

    pub fn importAsset(
        db: *cetech1.cdb.CdbDb,
        prereq: cetech1.task.TaskID,
        dir: std.fs.Dir,
        folder: cetech1.cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cetech1.cdb.ObjId,
    ) !cetech1.task.TaskID {
        _ = reimport_to;
        const Task = struct {
            db: *cetech1.cdb.CdbDb,
            dir: std.fs.Dir,
            folder: cetech1.cdb.ObjId,
            filename: []const u8,
            pub fn exec(self: *@This()) void {
                var tmp_alloc = tempalloc.api.createTempArena() catch undefined;
                defer tempalloc.api.destroyTempArena(tmp_alloc);
                var allocator = tmp_alloc.allocator();

                var full_path_buf: [2048]u8 = undefined;
                const full_path = self.dir.realpath(self.filename, &full_path_buf) catch undefined;
                log.api.info(MODULE_NAME, "Importing cdb asset {s}", .{full_path});

                var asset_file = self.dir.openFile(self.filename, .{ .mode = .read_only }) catch |err| {
                    log.api.err(MODULE_NAME, "Could not import asset {}", .{err});
                    return;
                };

                defer asset_file.close();
                defer self.dir.close();

                var asset_reader = asset_file.reader();

                var asset = readAssetFromReader(
                    @TypeOf(asset_reader),
                    asset_reader,
                    std.fs.path.stem(self.filename),
                    self.folder,
                    ReadBlobFromFile,
                    allocator,
                ) catch |err| {
                    log.api.err(MODULE_NAME, "Could not import asset {}", .{err});
                    return;
                };

                addAssetToRoot(asset) catch |err| {
                    log.api.err(MODULE_NAME, "Could not add asset to root {}", .{err});
                    return;
                };

                // Save current version to assedb.
                markObjSaved(asset, self.db.getVersion(asset));
            }
        };

        return try task.api.schedule(
            prereq,
            Task{
                .db = db,
                .dir = dir,
                .folder = folder,
                .filename = filename,
            },
        );
    }

    pub fn exportAsset(
        db: *cetech1.cdb.CdbDb,
        sub_path: []const u8,
        asset: cetech1.cdb.ObjId,
    ) !cetech1.task.TaskID {
        const Task = struct {
            db: *cetech1.cdb.CdbDb,
            asset: cetech1.cdb.ObjId,
            sub_path: []const u8,
            pub fn exec(self: *@This()) void {
                var tmp_alloc = tempalloc.api.createTempArena() catch undefined;
                defer tempalloc.api.destroyTempArena(tmp_alloc);
                var allocator = tmp_alloc.allocator();

                const version = self.db.getVersion(self.asset);

                saveCdbObj(self.asset, self.sub_path, allocator) catch |err| {
                    log.api.err(MODULE_NAME, "Could not save asset {}", .{err});
                    return;
                };
                markObjSaved(self.asset, version);
            }
        };

        return try task.api.schedule(
            cetech1.task.TaskID.none,
            Task{
                .db = db,
                .sub_path = sub_path,
                .asset = asset,
            },
        );
    }
});

pub fn create_cdb_types(db_: ?*c.c.struct_ct_cdb_db_t) callconv(.C) void {
    var db = cetech1.cdb.CdbDb.fromDbT(@ptrCast(db_), &cdb.api);

    // Asset type is wrapper for asset object
    const asset_type_hash = db.addType(
        public.AssetType.name,
        &.{
            .{ .prop_idx = public.AssetType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.AssetType.propIdx(.Object), .name = "object", .type = cetech1.cdb.PropType.SUBOBJECT },
            .{ .prop_idx = public.AssetType.propIdx(.Folder), .name = "folder", .type = cetech1.cdb.PropType.REFERENCE, .type_hash = public.FolderType.type_hash },
        },
    ) catch unreachable;
    std.debug.assert(asset_type_hash.id == public.AssetType.type_hash.id);

    // Asset folder
    const asset_folder_type = db.addType(
        public.FolderType.name,
        &.{
            .{ .prop_idx = public.FolderType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.FolderType.propIdx(.Parent), .name = "parent", .type = cetech1.cdb.PropType.REFERENCE, .type_hash = public.FolderType.type_hash },
        },
    ) catch unreachable;
    std.debug.assert(asset_folder_type.id == public.FolderType.type_hash.id);

    // All assets is parent of this
    asset_root_type = db.addType(
        AssetRootType.name,
        &.{
            .{ .prop_idx = AssetRootType.propIdx(.Assets), .name = "assets", .type = cetech1.cdb.PropType.SUBOBJECT_SET },
            .{ .prop_idx = AssetRootType.propIdx(.Folders), .name = "folders", .type = cetech1.cdb.PropType.SUBOBJECT_SET },
        },
    ) catch unreachable;

    // Project description
    const project_type = db.addType(
        public.ProjectType.name,
        &.{
            .{ .prop_idx = public.ProjectType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.ProjectType.propIdx(.Description), .name = "description", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.ProjectType.propIdx(.Organization), .name = "organization", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.ProjectType.propIdx(.Settings), .name = "settings", .type = cetech1.cdb.PropType.SUBOBJECT_SET },
        },
    ) catch unreachable;
    std.debug.assert(project_type.id == public.ProjectType.type_hash.id);

    _ = cetech1.cdb.addBigType(&db, public.FooAsset.name) catch unreachable;
    _ = cetech1.cdb.addBigType(&db, public.BarAsset.name) catch unreachable;
    _ = cetech1.cdb.addBigType(&db, public.BazAsset.name) catch unreachable;
}

var create_cdb_types_i = c.c.ct_cdb_create_types_i{
    .create_types = create_cdb_types,
};

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.AssetDBAPI, &api);
    try apidb.api.implOrRemove(c.c.ct_cdb_create_types_i, &create_cdb_types_i, true);
}

pub fn init(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb) !void {
    _allocator = allocator;
    _db = db;
    _asset_root = try db.createObject(asset_root_type);
    _asset_root_lock = std.Thread.Mutex{};

    _uuid2objid = Uuid2ObjId.init(allocator);
    _objid2uuid = ObjId2Uuid.init(allocator);

    _assetio_set = AssetIOSet.init(allocator);

    _uuid2asset_uuid = Uuid2AssetUuid.init(allocator);
    _asset_uuid2path = AssetUuid2Path.init(allocator);
    _asset_uuid2depend = AssetUuid2Depend.init(allocator);
    _asset_objid2version = AssetObjIdVersion.init(allocator);
    _asset_bag = cetech1.bagraph.BAG(cetech1.uuid.Uuid).init(allocator);
    _path2folder = Path2Folder.init(allocator);

    _tmp_depend_array = std.ArrayList(cetech1.task.TaskID).init(allocator);
    _tmp_taskid_map = std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.task.TaskID).init(allocator);

    _asset_root_folder = try public.FolderType.createObject(db);
    try addFolderToRoot(_asset_root_folder);
    markObjSaved(_asset_root_folder, db.getVersion(_asset_root_folder));

    _asset_root_last_version = db.getVersion(_asset_root);

    try db.addOnObjIdDestroyed(onObjidDestroyed);

    addAssetIO(&_cdb_asset_io_i);
}

pub fn deinit() void {
    removeAssetIO(&_cdb_asset_io_i);

    _db.destroyObject(_asset_root);
    _uuid2objid.deinit();
    _objid2uuid.deinit();
    _assetio_set.deinit();

    resetAnalyzedFileInfo() catch undefined;
    _asset_uuid2path.deinit();
    _asset_uuid2depend.deinit();
    _uuid2asset_uuid.deinit();
    _asset_bag.deinit();
    _path2folder.deinit();
    _tmp_depend_array.deinit();
    _tmp_taskid_map.deinit();
    _asset_objid2version.deinit();

    _db.removeOnObjIdDestroyed(onObjidDestroyed);
}

fn getAssetForObj(obj: cetech1.cdb.ObjId) ?cetech1.cdb.ObjId {
    var it: cetech1.cdb.ObjId = obj;

    var last_asset: ?cetech1.cdb.ObjId = null;

    while (!it.isEmpty()) {
        if (it.type_hash.id == public.AssetType.type_hash.id) {
            last_asset = it;
        }

        if (_db.readObj(it)) |r| {
            it = _db.getParent(r);
        } else {
            return null;
        }
    }
    return last_asset;
}

fn isProjectOpened() bool {
    return _asset_root_path != null;
}

pub fn markObjSaved(objdi: cetech1.cdb.ObjId, version: u64) void {
    _asset_objid2version_lck.lock();
    defer _asset_objid2version_lck.unlock();
    _asset_objid2version.put(objdi, version) catch undefined;
}

pub fn isObjModified(asset: cetech1.cdb.ObjId) bool {
    const cur_version = _db.getVersion(asset);

    // _asset_objid2version_lck.lock();
    // defer _asset_objid2version_lck.unlock();
    const saved_version = _asset_objid2version.get(asset) orelse return true;
    return cur_version != saved_version;
}

pub fn isProjectModified() bool {
    const cur_version = _db.getVersion(_asset_root);
    return cur_version != _asset_root_last_version;
}

pub fn getTmpPath(path_buf: []u8) !?[]u8 {
    const root_path = _asset_root_path orelse return null;

    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();
    return try root_dir.realpath(CT_TEMP_FOLDER, path_buf);
}

pub fn addAssetIO(asset_io: *public.AssetIOI) void {
    _assetio_set.put(asset_io, {}) catch |err| {
        log.api.err(MODULE_NAME, "Could not add AssetIO {}", .{err});
    };
}

pub fn removeAssetIO(asset_io: *public.AssetIOI) void {
    _ = _assetio_set.swapRemove(asset_io);
}

pub fn findFirstAssetIOForImport(extension: []const u8) ?*public.AssetIOI {
    for (_assetio_set.keys()) |asset_io| {
        if (asset_io.canImport != null and asset_io.canImport.?(extension)) return asset_io;
    }
    return null;
}

pub fn findFirstAssetIOForExport(db: *cetech1.cdb.CdbDb, asset: cetech1.cdb.ObjId, extension: []const u8) ?*public.AssetIOI {
    for (_assetio_set.keys()) |asset_io| {
        if (asset_io.canExport != null and asset_io.canExport.?(db, asset, extension)) return asset_io;
    }
    return null;
}

fn getRootFolder() cetech1.cdb.ObjId {
    return _asset_root_folder;
}

fn getObjId(obj_uuid: cetech1.uuid.Uuid) ?cetech1.cdb.ObjId {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();
    return _uuid2objid.get(obj_uuid);
}

fn getUuid(obj: cetech1.cdb.ObjId) ?cetech1.uuid.Uuid {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();
    return _objid2uuid.get(obj);
}

pub fn createObjectWithUuid(type_hash: cetech1.strid.StrId32, with_uuid: cetech1.uuid.Uuid) !cetech1.cdb.ObjId {
    log.api.debug(MODULE_NAME, "Creating new obj with UUID {}", .{with_uuid});
    var obj = try _db.createObject(type_hash);
    try mapUuidObjid(with_uuid, obj);
    return obj;
}

fn getOrCreateUuid(obj: cetech1.cdb.ObjId) !cetech1.uuid.Uuid {
    // _get_or_create_lock.lock();
    // defer _get_or_create_lock.unlock();

    var obj_uuid = getUuid(obj);
    if (obj_uuid != null) {
        return obj_uuid.?;
    }
    obj_uuid = uuid.newUUID7();
    try mapUuidObjid(obj_uuid.?, obj);
    return obj_uuid.?;
}

fn createObject(type_hash: cetech1.strid.StrId32) !cetech1.cdb.ObjId {
    var obj = try _db.createObject(type_hash);
    _ = try getOrCreateUuid(obj);
    return obj;
}

fn analyzFromJsonValue(parsed: std.json.Value, tmp_allocator: std.mem.Allocator, depend_on: *UuidSet, provide_uuids: *UuidSet) !void {
    const obj_uuid_str = parsed.object.get(JSON_UUID_TOKEN).?;
    const obj_uuid = try uuid.api.fromStr(obj_uuid_str.string);
    const obj_type = parsed.object.get(JSON_TYPE_NAME_TOKEN).?;
    const obj_type_hash = cetech1.strid.strId32(obj_type.string);

    try provide_uuids.put(obj_uuid, {});

    const prototype_uuid = parsed.object.get(JSON_PROTOTYPE_UUID);
    if (prototype_uuid) |proto_uuid| {
        try depend_on.put(try uuid.fromStr(proto_uuid.string), {});
    }

    var prop_defs = _db.getTypePropDef(obj_type_hash).?;

    var keys = parsed.object.keys();
    for (keys) |k| {
        // Skip private fields
        if (std.mem.startsWith(u8, k, "__")) continue;
        if (std.mem.endsWith(u8, k, JSON_REMOVED_POSTFIX)) continue;
        if (std.mem.endsWith(u8, k, JSON_INSTANTIATE_POSTFIX)) continue;

        var value = parsed.object.get(k).?;

        const prop_idx = _db.getTypePropDefIdx(obj_type_hash, k) orelse continue;
        const prop_def = prop_defs[prop_idx];

        switch (prop_def.type) {
            cetech1.cdb.PropType.SUBOBJECT => {
                try analyzFromJsonValue(value, tmp_allocator, depend_on, provide_uuids);
            },
            cetech1.cdb.PropType.REFERENCE => {
                var ref_link = std.mem.split(u8, value.string, ":");
                const ref_type = cetech1.strid.strId32(ref_link.first());
                const ref_uuid = try uuid.api.fromStr(ref_link.next().?);
                _ = ref_type;
                try depend_on.put(ref_uuid, {});
            },
            cetech1.cdb.PropType.SUBOBJECT_SET => {
                for (value.array.items) |subobj_item| {
                    try analyzFromJsonValue(subobj_item, tmp_allocator, depend_on, provide_uuids);
                }
            },
            cetech1.cdb.PropType.REFERENCE_SET => {
                for (value.array.items) |ref| {
                    var ref_link = std.mem.split(u8, ref.string, ":");
                    const ref_type = cetech1.strid.strId32(ref_link.first());
                    const ref_uuid = try uuid.api.fromStr(ref_link.next().?);
                    _ = ref_type;
                    try depend_on.put(ref_uuid, {});
                }
            },
            else => continue,
        }
    }
}

const UuidSet = std.AutoArrayHashMap(cetech1.uuid.Uuid, void);

fn addAnalyzedFileInfo(path: []const u8, asset_uuid: cetech1.uuid.Uuid, depend_on: *UuidSet, provide_uuids: *UuidSet) !void {
    // TODO
    _file_info_lck.lock();
    defer _file_info_lck.unlock();

    try _asset_uuid2path.put(asset_uuid, try _allocator.dupe(u8, path));

    for (provide_uuids.keys()) |provide_uuid| {
        try _uuid2asset_uuid.put(provide_uuid, asset_uuid);
    }

    if (_asset_uuid2depend.getPtr(asset_uuid)) |depend| {
        depend.deinit();
    }

    try _asset_uuid2depend.put(asset_uuid, try depend_on.cloneWithAllocator(_allocator));
}

fn resetAnalyzedFileInfo() !void {
    // TODO
    _file_info_lck.lock();
    defer _file_info_lck.unlock();

    _asset_objid2version_lck.lock();
    defer _asset_objid2version_lck.unlock();

    for (_asset_uuid2path.values()) |path| {
        _allocator.free(path);
    }

    for (_path2folder.keys()) |path| {
        _allocator.free(path);
    }

    for (_asset_uuid2depend.values()) |*depend| {
        depend.deinit();
    }

    _asset_uuid2path.clearRetainingCapacity();
    _uuid2asset_uuid.clearRetainingCapacity();
    _asset_uuid2depend.clearRetainingCapacity();
    _path2folder.clearRetainingCapacity();
    _asset_objid2version.clearRetainingCapacity();
    _tmp_depend_array.clearRetainingCapacity();
    _tmp_taskid_map.clearRetainingCapacity();
}

fn validateVersion(version: []const u8) !void {
    const v = try std.SemanticVersion.parse(version);
    if (v.order(ASSET_CURRENT_VERSION) == .lt) {
        return error.NOT_COMPATIBLE_VERSION;
    }
}

fn analyzeFile(tmp_allocator: std.mem.Allocator, path: []const u8) !void {
    log.api.debug(MODULE_NAME, "Analyze file {s}", .{path});

    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var json_reader = std.json.reader(tmp_allocator, file.reader());
    defer json_reader.deinit();
    var parsed = try std.json.parseFromTokenSource(std.json.Value, tmp_allocator, &json_reader, .{});
    defer parsed.deinit();

    const version_str = parsed.value.object.get(JSON_ASSET_VERSION).?;

    try validateVersion(version_str.string);

    const asset_uuid_str = parsed.value.object.get(JSON_ASSET_UUID_TOKEN).?;
    const asset_uuid = try uuid.api.fromStr(asset_uuid_str.string);

    var depend_on = UuidSet.init(tmp_allocator);
    defer depend_on.deinit();

    var provide_uuids = UuidSet.init(tmp_allocator);
    defer provide_uuids.deinit();

    try analyzFromJsonValue(parsed.value, tmp_allocator, &depend_on, &provide_uuids);
    try addAnalyzedFileInfo(path, asset_uuid, &depend_on, &provide_uuids);
}

fn analyzeFolder(root_dir: std.fs.IterableDir, parent_folder: cetech1.cdb.ObjId, tasks: *std.ArrayList(cetech1.task.TaskID), tmp_allocator: std.mem.Allocator) !void {
    var iterator = root_dir.iterate();
    while (try iterator.next()) |entry| {
        // Skip . files
        if (std.mem.startsWith(u8, entry.name, ".")) continue;

        if (entry.kind == .file) {
            const extension = std.fs.path.extension(entry.name);
            if (!std.mem.startsWith(u8, extension, CT_ASSETS_FILE_PREFIX)) continue;
            if (std.mem.startsWith(u8, entry.name, ".")) continue;

            const Task = struct {
                root_dir: std.fs.IterableDir,
                path: []const u8,
                tmp_allocator: std.mem.Allocator,
                pub fn exec(self: *@This()) void {
                    defer self.tmp_allocator.free(self.path);

                    analyzeFile(self.tmp_allocator, self.path) catch |err| {
                        log.api.err(MODULE_NAME, "Could not analyze asset {}", .{err});
                        return;
                    };
                }
            };
            const task_id = try task.api.schedule(
                cetech1.task.TaskID.none,
                Task{
                    .root_dir = root_dir,
                    .path = try root_dir.dir.realpathAlloc(tmp_allocator, entry.name),
                    .tmp_allocator = tmp_allocator,
                },
            );
            try tasks.append(task_id);
        } else if (entry.kind == .directory) {
            if (std.mem.endsWith(u8, entry.name, "." ++ BLOB_EXTENSION)) continue;
            var dir = try root_dir.dir.openIterableDir(entry.name, .{});
            defer dir.close();

            var rel_path: [2048]u8 = undefined;
            log.api.debug(MODULE_NAME, "Scaning folder {s}", .{try dir.dir.realpath(".", &rel_path)});

            var folder_obj: cetech1.cdb.ObjId = .{};

            if (existFolderMarker(root_dir.dir, entry.name)) {
                var buffer: [1024]u8 = undefined;
                var path = try std.fmt.bufPrintZ(&buffer, "." ++ public.FolderType.name, .{});

                var asset_file = try dir.dir.openFile(path, .{ .mode = .read_only });
                defer asset_file.close();
                var asset_reader = asset_file.reader();
                folder_obj = try readObjFromJson(
                    @TypeOf(asset_reader),
                    asset_reader,
                    ReadBlobFromFile,
                    tmp_allocator,
                );
                markObjSaved(folder_obj, _db.getVersion(folder_obj));
            } else {
                folder_obj = try createObject(public.FolderType.type_hash);

                var folder_obj_w = _db.writeObj(folder_obj).?;
                var buffer: [128]u8 = undefined;
                var str = try std.fmt.bufPrintZ(&buffer, "{s}", .{entry.name});

                try public.FolderType.setStr(_db, folder_obj_w, .Name, str);
                try public.FolderType.setRef(_db, folder_obj_w, .Parent, parent_folder);
                _db.writeCommit(folder_obj_w);

                try saveFolderObj(folder_obj, tmp_allocator);
            }

            try _path2folder.put(try dir.dir.realpathAlloc(_allocator, "."), folder_obj);

            try analyzeFolder(dir, folder_obj, tasks, tmp_allocator);
            try addFolderToRoot(folder_obj);
        }
    }
}

fn writeAssetDOTGraph() !void {
    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    var dot_file = try root_dir.createFile(CT_TEMP_FOLDER ++ "/" ++ "asset_graph.dot", .{});
    defer dot_file.close();

    // write header
    var writer = dot_file.writer();
    try writer.print("digraph asset_graph {{\n", .{});

    // write nodes
    try writer.print("    subgraph {{\n", .{});
    try writer.print("        node [shape = box;];\n", .{});
    for (_asset_uuid2path.keys(), _asset_uuid2path.values()) |asset_uuid, asset_path| {
        var path = try std.fs.path.relative(_allocator, _asset_root_path.?, asset_path);
        defer _allocator.free(path);

        try writer.print("        \"{s}\" [label = \"{s}\";];\n", .{ asset_uuid, path });
    }
    try writer.print("    }}\n", .{});

    // Edges
    for (_asset_uuid2depend.keys(), _asset_uuid2depend.values()) |asset_uuid, depends| {
        for (depends.keys()) |depend| {
            try writer.print("    \"{s}\" -> \"{s}\";\n", .{ asset_uuid, _uuid2asset_uuid.get(depend).? });
        }
    }

    // write footer
    try writer.print("}}\n", .{});
}

fn writeAssetGraphMD() !void {
    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    var dot_file = try root_dir.createFile(CT_TEMP_FOLDER ++ "/" ++ "asset_graph.md", .{});
    defer dot_file.close();

    // write header
    var writer = dot_file.writer();
    try writer.print("# AssetDB asset dependencies\n\n", .{});

    try writer.print("```mermaid\n", .{});
    try writer.print("flowchart TB\n", .{});

    // write nodes
    for (_asset_uuid2path.keys(), _asset_uuid2path.values()) |asset_uuid, asset_path| {
        var path = try std.fs.path.relative(_allocator, _asset_root_path.?, asset_path);
        defer _allocator.free(path);

        try writer.print("    {s}[{s}]\n", .{ asset_uuid, path });
    }
    try writer.print("\n", .{});

    // Edges
    for (_asset_uuid2depend.keys(), _asset_uuid2depend.values()) |asset_uuid, depends| {
        for (depends.keys()) |depend| {
            try writer.print("    {s}-->{s}\n", .{ asset_uuid, _uuid2asset_uuid.get(depend).? });
        }
    }

    // write footer
    try writer.print("```\n", .{});
}

fn openAssetRootFolder(asset_root_path: []const u8, tmp_allocator: std.mem.Allocator) !void {
    _asset_root_path = asset_root_path;
    var root_dir = try std.fs.cwd().openIterableDir(asset_root_path, .{});
    defer root_dir.close();

    try root_dir.dir.makePath(CT_TEMP_FOLDER);

    if (!_asset_root.isEmpty()) {
        _db.destroyObject(_asset_root);
        _db.destroyObject(_asset_root_folder);
        _asset_root = try _db.createObject(asset_root_type);
    }

    // asset root folder
    if (existRootFolderMarker(root_dir.dir)) {
        var asset_file = try root_dir.dir.openFile("." ++ public.FolderType.name, .{ .mode = .read_only });
        defer asset_file.close();
        var asset_reader = asset_file.reader();
        _asset_root_folder = try readObjFromJson(
            @TypeOf(asset_reader),
            asset_reader,
            ReadBlobFromFile,
            tmp_allocator,
        );
        markObjSaved(_asset_root_folder, _db.getVersion(_asset_root_folder));
    } else {
        _asset_root_folder = try public.FolderType.createObject(_db);
        try saveFolderObj(_asset_root_folder, tmp_allocator);
    }
    try addFolderToRoot(_asset_root_folder);
    const root_path = try root_dir.dir.realpathAlloc(_allocator, ".");
    log.api.info(MODULE_NAME, "Asset root dir {s}", .{root_path});

    // project asset
    if (!existRootProjectAsset(root_dir.dir)) {
        const project_obj = try public.ProjectType.createObject(_db);
        const project_asset = createAsset("project", _asset_root_folder, project_obj).?;
        const save_task = try saveAsset(project_asset, tmp_allocator);
        task.api.wait(save_task);
    }

    try resetAnalyzedFileInfo();
    try _path2folder.put(root_path, _asset_root_folder);

    var tasks = std.ArrayList(cetech1.task.TaskID).init(tmp_allocator);
    defer tasks.deinit();
    try analyzeFolder(root_dir, _asset_root_folder, &tasks, tmp_allocator);
    task.api.wait(try task.api.combine(tasks.items));
    //tasks.clearRetainingCapacity();

    try _asset_bag.reset();
    for (_asset_uuid2depend.keys(), _asset_uuid2depend.values()) |asset_uuid, depends| {
        var depend_asset = UuidSet.init(tmp_allocator);
        defer depend_asset.deinit();

        for (depends.keys()) |depend_uuid| {
            try depend_asset.put(_uuid2asset_uuid.get(depend_uuid).?, {});
        }

        try _asset_bag.add(asset_uuid, depend_asset.keys());
    }
    try _asset_bag.build_all();

    for (_asset_bag.output.keys()) |output| {
        log.api.debug(MODULE_NAME, "Loader plan {s}", .{_asset_uuid2path.get(output).?});
        var depeds = _asset_bag.dependList(output);
        if (depeds != null) {
            for (depeds.?) |value| {
                log.api.debug(MODULE_NAME, "  | {s}", .{_asset_uuid2path.get(value).?});
            }
        }
    }

    for (_asset_bag.output.keys()) |asset_uuid| {
        const asset_path = _asset_uuid2path.getPtr(asset_uuid).?;
        const filename = std.fs.path.basename(asset_path.*);
        const extension = std.fs.path.extension(asset_path.*);
        const dir = std.fs.path.dirname(asset_path.*).?;
        const parent_folder = _path2folder.get(dir).?;

        var asset_io = findFirstAssetIOForImport(extension) orelse continue;

        var prereq = cetech1.task.TaskID.none;
        var depeds = _asset_bag.dependList(asset_uuid);
        if (depeds != null) {
            _tmp_depend_array.clearRetainingCapacity();
            for (depeds.?) |d| {
                try _tmp_depend_array.append(_tmp_taskid_map.get(d).?);
            }
            prereq = try task.api.combine(_tmp_depend_array.items);
        }

        var copy_dir = try std.fs.openDirAbsolute(dir, .{});
        if (asset_io.importAsset.?(_db, prereq, copy_dir, parent_folder, filename, null)) |import_task| {
            try _tmp_taskid_map.put(asset_uuid, import_task);
        } else |err| {
            log.api.err(MODULE_NAME, "Could not import asset {s} {}", .{ asset_path, err });
        }
    }

    try writeAssetDOTGraph();
    try writeAssetGraphMD();
    var sync_job = try task.api.combine(_tmp_taskid_map.values());
    task.api.wait(sync_job);

    // Resave obj version
    for (_asset_objid2version.keys()) |obj| {
        try _asset_objid2version.put(obj, _db.getVersion(obj));
    }

    _asset_root_last_version = _db.getVersion(_asset_root);
}

fn mapUuidObjid(obj_uuid: cetech1.uuid.Uuid, objid: cetech1.cdb.ObjId) !void {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();
    try _uuid2objid.put(obj_uuid, objid);
    try _objid2uuid.put(objid, obj_uuid);
}

fn unmapByUuid(obj_uuid: cetech1.uuid.Uuid) !void {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();
    var objid = _uuid2objid.get(obj_uuid).?;
    _ = _uuid2objid.swapRemove(obj_uuid);
    _ = _objid2uuid.swapRemove(objid);
}

fn unmapByObjId(obj: cetech1.cdb.ObjId) !void {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();
    var obj_uuid = _objid2uuid.get(obj).?;
    _ = _uuid2objid.swapRemove(obj_uuid);
    _ = _objid2uuid.swapRemove(obj);
}

fn setAssetNameAndFolder(asset: cetech1.cdb.ObjId, name: []const u8, asset_folder: cetech1.cdb.ObjId) !void {
    var asset_w = _db.writeObj(asset).?;

    var buffer: [128]u8 = undefined;
    var str = try std.fmt.bufPrintZ(&buffer, "{s}", .{name});

    try public.AssetType.setStr(_db, asset_w, .Name, str);
    try public.AssetType.setRef(_db, asset_w, .Folder, asset_folder);

    _db.writeCommit(asset_w);
}

fn addAssetToRoot(asset: cetech1.cdb.ObjId) !void {
    // TODO: make posible CAS write to CDB and remove lock.
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    var asset_root_w = _db.writeObj(_asset_root).?;
    var asset_w = _db.writeObj(asset).?;
    try AssetRootType.addSubObjToSet(_db, asset_root_w, .Assets, &.{asset_w});
    _db.writeCommit(asset_w);
    _db.writeCommit(asset_root_w);
}

fn addFolderToRoot(folder: cetech1.cdb.ObjId) !void {
    // TODO: make posible CAS write to CDB and remove lock.
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    var asset_root_w = _db.writeObj(_asset_root).?;
    var folder_w = _db.writeObj(folder).?;
    try AssetRootType.addSubObjToSet(_db, asset_root_w, .Folders, &.{folder_w});
    _db.writeCommit(folder_w);
    _db.writeCommit(asset_root_w);
}

fn createAsset(asset_name: []const u8, asset_folder: cetech1.cdb.ObjId, asset_obj: ?cetech1.cdb.ObjId) ?cetech1.cdb.ObjId {
    var asset = createObject(public.AssetType.type_hash) catch return null;

    if (asset_obj != null) {
        var asset_w = _db.writeObj(asset).?;
        var asset_obj_w = _db.writeObj(asset_obj.?).?;
        public.AssetType.setSubObj(_db, asset_w, .Object, asset_obj_w) catch return null;

        _db.writeCommit(asset_obj_w);
        _db.writeCommit(asset_w);
    }

    setAssetNameAndFolder(asset, asset_name, asset_folder) catch return null;
    addAssetToRoot(asset) catch return null;
    return asset;
}

pub fn saveAll(tmp_allocator: std.mem.Allocator) !void {
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    var assets = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Assets, tmp_allocator)).?;
    defer tmp_allocator.free(assets);

    if (assets.len == 0) return;

    var tasks = try std.ArrayList(cetech1.task.TaskID).initCapacity(tmp_allocator, assets.len);
    defer tasks.deinit();

    for (assets) |asset| {
        const export_task = try saveAsset(asset, tmp_allocator);
        if (export_task == .none) continue;
        try tasks.append(export_task);
    }

    task.api.wait(try task.api.combine(tasks.items));

    var folders = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Folders, tmp_allocator)).?;
    defer tmp_allocator.free(folders);
    for (folders) |folder| {
        try saveFolderObj(folder, tmp_allocator);
    }

    _asset_root_last_version = _db.getVersion(_asset_root);
}

pub fn saveAssetAndWait(tmp_allocator: std.mem.Allocator, asset: cetech1.cdb.ObjId) !void {
    if (asset.type_hash.id == cetech1.assetdb.AssetType.type_hash.id) {
        const export_task = try saveAsset(asset, tmp_allocator);
        task.api.wait(export_task);
    } else if (asset.type_hash.id == cetech1.assetdb.FolderType.type_hash.id) {
        try saveFolderObj(asset, tmp_allocator);
    }
}

pub fn saveAllModifiedAssets(tmp_allocator: std.mem.Allocator) !void {
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    var assets = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Assets, tmp_allocator)).?;
    defer tmp_allocator.free(assets);

    if (assets.len == 0) return;

    var tasks = try std.ArrayList(cetech1.task.TaskID).initCapacity(tmp_allocator, assets.len);
    defer tasks.deinit();

    for (assets) |asset| {
        if (!isObjModified(asset)) continue;

        if (saveAsset(asset, tmp_allocator)) |export_task| {
            if (export_task == .none) continue;
            try tasks.append(export_task);
        } else |err| {
            log.api.err(MODULE_NAME, "Could not save asset {}", .{err});
        }
    }

    task.api.wait(try task.api.combine(tasks.items));

    var folders = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Folders, tmp_allocator)).?;
    defer tmp_allocator.free(folders);
    for (folders) |folder| {
        if (!isObjModified(folder)) continue;
        try saveFolderObj(folder, tmp_allocator);
    }

    _asset_root_last_version = _db.getVersion(_asset_root);
}

fn getPathForFolder(from_folder: cetech1.cdb.ObjId, tmp_allocator: std.mem.Allocator) ![]u8 {
    var path = std.ArrayList([:0]const u8).init(tmp_allocator);
    defer path.deinit();

    var root_folder_name = public.FolderType.readStr(_db, _db.readObj(from_folder).?, .Name);

    if (root_folder_name != null) {
        var folder_it: ?cetech1.cdb.ObjId = from_folder;
        while (folder_it) |folder| : (folder_it = public.FolderType.readRef(_db, _db.readObj(folder).?, .Parent)) {
            var folder_name = public.FolderType.readStr(_db, _db.readObj(folder).?, .Name) orelse continue;
            try path.insert(0, folder_name);
        }

        var sub_path = try std.fs.path.join(tmp_allocator, path.items);
        defer tmp_allocator.free(sub_path);
        return std.fmt.allocPrint(tmp_allocator, "{s}/." ++ public.FolderType.name, .{sub_path});
    } else {
        return std.fmt.allocPrint(tmp_allocator, "." ++ public.FolderType.name, .{});
    }
}

pub fn getFilePathForAsset(asset: cetech1.cdb.ObjId, tmp_allocator: std.mem.Allocator) ![]u8 {
    var asset_r = _db.readObj(asset);
    var asset_obj = public.AssetType.readSubObj(_db, asset_r.?, .Object).?;

    // append asset type extension
    return getPathForAsset(asset, _db.getTypeName(asset_obj.type_hash).?, tmp_allocator);
}

fn getPathForAsset(asset: cetech1.cdb.ObjId, extension: []const u8, tmp_allocator: std.mem.Allocator) ![]u8 {
    var asset_r = _db.readObj(asset);
    var path = std.ArrayList([:0]const u8).init(tmp_allocator);
    defer path.deinit();

    // add asset name
    var asset_name = public.AssetType.readStr(_db, asset_r.?, .Name);
    try path.insert(0, asset_name.?);

    // make sub path
    var folder_it = public.AssetType.readRef(_db, asset_r.?, .Folder);
    while (folder_it) |folder| : (folder_it = public.FolderType.readRef(_db, _db.readObj(folder).?, .Parent)) {
        var folder_name = public.FolderType.readStr(_db, _db.readObj(folder).?, .Name) orelse continue;
        try path.insert(0, folder_name);
    }

    var sub_path = try std.fs.path.join(tmp_allocator, path.items);
    defer tmp_allocator.free(sub_path);

    return std.fmt.allocPrint(tmp_allocator, "{s}.{s}", .{ sub_path, extension });
}

fn WriteBlobToFile(
    blob: []const u8,
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    tmp_allocator: std.mem.Allocator,
) anyerror!void {
    var blob_dir_path = try getPathForAsset(asset, BLOB_EXTENSION, tmp_allocator);
    defer tmp_allocator.free(blob_dir_path);

    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    //create blob dir
    try root_dir.makePath(blob_dir_path);

    var blob_file_name_buf: [1024]u8 = undefined;
    var blob_file_name = try std.fmt.bufPrint(&blob_file_name_buf, "{x}{x}", .{ cetech1.strid.strId32(&obj_uuid.bytes).id, prop_hash.id });

    var blob_dir = try root_dir.openDir(blob_dir_path, .{});
    defer blob_dir.close();
    try blob_dir.writeFile(blob_file_name, blob);
}

fn ReadBlobFromFile(
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    tmp_allocator: std.mem.Allocator,
) anyerror![]u8 {
    var blob_dir_path = try getPathForAsset(asset, BLOB_EXTENSION, tmp_allocator);
    defer tmp_allocator.free(blob_dir_path);

    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    var blob_file_name_buf: [1024]u8 = undefined;
    var blob_file_name = try std.fmt.bufPrint(&blob_file_name_buf, "{x}{x}", .{ cetech1.strid.strId32(&obj_uuid.bytes).id, prop_hash.id });

    var blob_dir = try root_dir.openDir(blob_dir_path, .{});
    defer blob_dir.close();

    var blob_file = try blob_dir.openFile(blob_file_name, .{});
    defer blob_file.close();
    const size = try blob_file.getEndPos();

    var blob = try tmp_allocator.alloc(u8, size);
    _ = try blob_file.readAll(blob);
    return blob;
}

fn saveCdbObj(obj: cetech1.cdb.ObjId, sub_path: []const u8, tmp_allocator: std.mem.Allocator) !void {
    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    var dir_path = std.fs.path.dirname(sub_path);
    if (dir_path != null) {
        try root_dir.makePath(dir_path.?);
    }

    var obj_file = try root_dir.createFile(sub_path, .{});
    defer obj_file.close();
    var writer = obj_file.writer();

    const folder = public.AssetType.readRef(_db, _db.readObj(obj).?, .Folder).?;
    try writeCdbObjJson(
        @TypeOf(writer),
        obj,
        writer,
        obj,
        folder,
        WriteBlobToFile,
        tmp_allocator,
    );
}

pub fn saveAsset(asset: cetech1.cdb.ObjId, tmp_allocator: std.mem.Allocator) !cetech1.task.TaskID {
    var sub_path = try getFilePathForAsset(asset, tmp_allocator);
    if (findFirstAssetIOForExport(_db, asset, std.fs.path.extension(sub_path))) |asset_io| {
        return asset_io.exportAsset.?(_db, sub_path, asset);
    }
    return .none;
}

fn saveFolderObj(folder: cetech1.cdb.ObjId, tmp_allocator: std.mem.Allocator) !void {
    var sub_path = try getPathForFolder(folder, tmp_allocator);
    defer tmp_allocator.free(sub_path);

    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    if (std.fs.path.dirname(sub_path)) |dir| {
        try root_dir.makePath(dir);
    }

    var obj_file = try root_dir.createFile(sub_path, .{});
    defer obj_file.close();
    var writer = obj_file.writer();

    log.api.info(MODULE_NAME, "Creating folder asset in {s}.", .{sub_path});

    try writeCdbObjJson(
        @TypeOf(writer),
        folder,
        writer,
        folder,
        folder,
        WriteBlobToFile,
        tmp_allocator,
    );

    markObjSaved(folder, _db.getVersion(folder));
}

fn existRootFolderMarker(root_folder: std.fs.Dir) bool {
    var buf: [1024]u8 = undefined;
    var path = std.fmt.bufPrint(&buf, "." ++ public.FolderType.name, .{}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

fn existRootProjectAsset(root_folder: std.fs.Dir) bool {
    var buf: [1024]u8 = undefined;
    var path = std.fmt.bufPrint(&buf, "project." ++ public.ProjectType.name, .{}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

fn existFolderMarker(root_folder: std.fs.Dir, dir_name: []const u8) bool {
    var buf: [1024]u8 = undefined;
    var path = std.fmt.bufPrint(&buf, "{s}/." ++ public.FolderType.name, .{dir_name}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

pub fn writeCdbObjJson(
    comptime Writer: type,
    obj: cetech1.cdb.ObjId,
    writer: Writer,
    asset: cetech1.cdb.ObjId,
    folder: cetech1.cdb.ObjId,
    write_blob: WriteBlobFn,
    tmp_allocator: std.mem.Allocator,
) !void {
    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_2 });
    try ws.beginObject();

    var obj_r = _db.readObj(obj).?;
    var asset_obj: ?cetech1.cdb.ObjId = null;

    try ws.objectField(JSON_ASSET_VERSION);
    try ws.print("\"{s}\"", .{ASSET_CURRENT_VERSION_STR});

    if (obj.type_hash.id == public.AssetType.type_hash.id) {
        asset_obj = public.AssetType.readSubObj(_db, obj_r, .Object);

        try ws.objectField(JSON_ASSET_UUID_TOKEN);
        try ws.print("\"{s}\"", .{try getOrCreateUuid(obj)});
    } else {
        asset_obj = obj;
    }

    try writeCdbObjJsonBody(
        @TypeOf(ws),
        asset_obj.?,
        &ws,
        asset,
        folder,
        write_blob,
        tmp_allocator,
    );

    try ws.endObject();
}

fn writeCdbObjJsonBody(
    comptime Writer: type,
    obj: cetech1.cdb.ObjId,
    writer: *Writer,
    asset: cetech1.cdb.ObjId,
    folder: cetech1.cdb.ObjId,
    write_blob: WriteBlobFn,
    tmp_allocator: std.mem.Allocator,
) !void {
    var obj_r = _db.readObj(obj).?;
    const type_name = _db.getTypeName(obj.type_hash).?;

    // Type name
    try writer.objectField(JSON_TYPE_NAME_TOKEN);
    try writer.print("\"{s}\"", .{type_name});

    // UUID
    try writer.objectField(JSON_UUID_TOKEN);
    try writer.print("\"{s}\"", .{try getOrCreateUuid(obj)});

    const prototype_id = _db.getPrototype(obj_r);
    if (!prototype_id.isEmpty()) {
        try writer.objectField(JSON_PROTOTYPE_UUID);
        try writer.print("\"{s}\"", .{try getOrCreateUuid(prototype_id)});
    }

    var prop_defs = _db.getTypePropDef(obj.type_hash).?;
    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);
        const has_prototype = !_db.getPrototype(obj_r).isEmpty();
        const property_overided = _db.isPropertyOverrided(obj_r, prop_idx);
        switch (prop_def.type) {
            cetech1.cdb.PropType.BOOL => {
                var value = _db.readValue(bool, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == false) continue;

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.U64 => {
                var value = _db.readValue(u64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.I64 => {
                var value = _db.readValue(i64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.U32 => {
                var value = _db.readValue(u32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.I32 => {
                var value = _db.readValue(i32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.F64 => {
                var value = _db.readValue(f64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.F32 => {
                var value = _db.readValue(f32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and value == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.STR => {
                var str = _db.readStr(obj_r, prop_idx);
                if (str == null) continue;
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and str.?.len == 0) continue;
                try writer.objectField(prop_def.name);
                try writer.print("\"{s}\"", .{str.?});
            },
            cetech1.cdb.PropType.BLOB => {
                var blob = _db.readBlob(obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (blob.len == 0) continue;

                var obj_uuid = try getOrCreateUuid(obj);
                try write_blob(blob, asset, obj_uuid, cetech1.strid.strId32(prop_def.name), tmp_allocator);

                try writer.objectField(prop_def.name);
                try writer.print("\"{x}{x}\"", .{ cetech1.strid.strId32(&obj_uuid.bytes).id, cetech1.strid.strId32(prop_def.name).id });
            },
            cetech1.cdb.PropType.SUBOBJECT => {
                var subobj = _db.readSubObj(obj_r, prop_idx);
                if (has_prototype and !_db.isPropertyOverrided(obj_r, prop_idx)) continue;
                if (subobj != null) {
                    try writer.objectField(prop_def.name);

                    try writer.beginObject();
                    try writeCdbObjJsonBody(
                        Writer,
                        subobj.?,
                        writer,
                        asset,
                        folder,
                        write_blob,
                        tmp_allocator,
                    );
                    try writer.endObject();
                }
            },
            cetech1.cdb.PropType.REFERENCE => {
                const ref_obj = _db.readRef(obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (ref_obj != null) {
                    try writer.objectField(prop_def.name);
                    try writer.print("\"{s}:{s}\"", .{ type_name, try getOrCreateUuid(ref_obj.?) });
                }
            },
            cetech1.cdb.PropType.SUBOBJECT_SET => {
                var added = try _db.readSubObjSetAdded(
                    obj_r,
                    @truncate(prop_idx),
                    tmp_allocator,
                );
                defer tmp_allocator.free(added.?);

                if (prototype_id.isEmpty()) {
                    if (added.?.len == 0) continue;

                    try writer.objectField(prop_def.name);
                    try writer.beginArray();
                    for (added.?) |item| {
                        try writer.beginObject();
                        try writeCdbObjJsonBody(Writer, item, writer, asset, folder, write_blob, tmp_allocator);
                        try writer.endObject();
                    }
                    try writer.endArray();
                } else {
                    var deleted_items = _db.readSubObjSetRemoved(obj_r, prop_idx, tmp_allocator);
                    defer tmp_allocator.free(deleted_items.?);

                    var deleted_set = std.AutoArrayHashMap(cetech1.cdb.ObjId, void).init(tmp_allocator);
                    defer deleted_set.deinit();

                    for (deleted_items.?) |item| {
                        try deleted_set.put(item, {});
                    }

                    var added_set = std.AutoArrayHashMap(cetech1.cdb.ObjId, void).init(tmp_allocator);
                    var inisiate_set = std.AutoArrayHashMap(cetech1.cdb.ObjId, void).init(tmp_allocator);
                    defer added_set.deinit();
                    defer inisiate_set.deinit();

                    for (added.?) |item| {
                        const prototype_obj = _db.getPrototype(_db.readObj(item).?);

                        if (deleted_set.contains(prototype_obj)) {
                            try inisiate_set.put(item, {});
                            _ = deleted_set.swapRemove(prototype_obj);
                        } else {
                            try added_set.put(item, {});
                        }
                    }

                    // new added
                    if (added_set.count() != 0) {
                        try writer.objectField(prop_def.name);
                        try writer.beginArray();
                        for (added_set.keys()) |item| {
                            try writer.beginObject();
                            try writeCdbObjJsonBody(Writer, item, writer, asset, folder, write_blob, tmp_allocator);
                            try writer.endObject();
                        }
                        try writer.endArray();
                    }

                    // inisiated
                    if (inisiate_set.count() != 0) {
                        var buff: [128]u8 = undefined;
                        var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_INSTANTIATE_POSTFIX, .{prop_def.name});

                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (inisiate_set.keys()) |item| {
                            try writer.beginObject();
                            try writeCdbObjJsonBody(Writer, item, writer, asset, folder, write_blob, tmp_allocator);
                            try writer.endObject();
                        }
                        try writer.endArray();
                    }

                    // removed
                    if (deleted_set.count() != 0) {
                        var buff: [128]u8 = undefined;
                        var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (deleted_set.keys()) |item| {
                            try writer.print("\"{s}:{s}\"", .{ type_name, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }
                }
            },
            cetech1.cdb.PropType.REFERENCE_SET => {
                var added = _db.readRefSetAdded(obj_r, @truncate(prop_idx), tmp_allocator);
                defer tmp_allocator.free(added.?);
                if (prototype_id.isEmpty()) {
                    if (added == null or added.?.len == 0) continue;

                    try writer.objectField(prop_def.name);
                    try writer.beginArray();
                    for (added.?) |item| {
                        try writer.print("\"{s}:{s}\"", .{ type_name, try getOrCreateUuid(item) });
                    }
                    try writer.endArray();
                } else {
                    var deleted_items = _db.readSubObjSetRemoved(obj_r, prop_idx, tmp_allocator);
                    defer tmp_allocator.free(deleted_items.?);

                    var deleted_set = std.AutoArrayHashMap(cetech1.cdb.ObjId, void).init(tmp_allocator);
                    defer deleted_set.deinit();

                    for (deleted_items.?) |item| {
                        try deleted_set.put(item, {});
                    }

                    var added_set = std.AutoArrayHashMap(cetech1.cdb.ObjId, void).init(tmp_allocator);
                    defer added_set.deinit();

                    for (added.?) |item| {
                        const prototype_obj = _db.getPrototype(_db.readObj(item).?);

                        if (deleted_set.contains(prototype_obj)) {
                            _ = deleted_set.swapRemove(prototype_obj);
                        } else {
                            try added_set.put(item, {});
                        }
                    }

                    // new added
                    if (added_set.count() != 0) {
                        try writer.objectField(prop_def.name);
                        try writer.beginArray();
                        for (added_set.keys()) |item| {
                            try writer.print("\"{s}:{s}\"", .{ type_name, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }

                    // removed
                    if (deleted_set.count() != 0) {
                        var buff: [128]u8 = undefined;
                        var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (deleted_set.keys()) |item| {
                            try writer.print("\"{s}:{s}\"", .{ type_name, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }

                    // var deleted_items = _db.readRefSetRemoved(obj_r, prop_idx, tmp_allocator);
                    // defer tmp_allocator.free(deleted_items.?);

                    // if (deleted_items.?.len != 0) {
                    //     var buff: [128]u8 = undefined;
                    //     var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                    //     try writer.objectField(field_name);
                    //     try writer.beginArray();
                    //     for (deleted_items.?) |item| {
                    //         try writer.print("\"{s}:{s}\"", .{ type_name, try getOrCreateUuid(item) });
                    //     }
                    //     try writer.endArray();
                    // }
                }
            },
            else => unreachable,
        }
    }
}

pub fn readAssetFromReader(
    comptime Reader: type,
    reader: Reader,
    asset_name: []const u8,
    asset_folder: cetech1.cdb.ObjId,
    read_blob: ReadBlobFn,
    tmp_allocator: std.mem.Allocator,
) !cetech1.cdb.ObjId {
    var json_reader = std.json.reader(tmp_allocator, reader);
    defer json_reader.deinit();
    var parsed = try std.json.parseFromTokenSource(std.json.Value, tmp_allocator, &json_reader, .{});
    defer parsed.deinit();

    const version = parsed.value.object.get(JSON_ASSET_VERSION).?;
    try validateVersion(version.string);

    const asset_uuid_str = parsed.value.object.get(JSON_ASSET_UUID_TOKEN).?;
    const asset_uuid = try uuid.api.fromStr(asset_uuid_str.string);

    var asset = try getOrCreate(asset_uuid, public.AssetType.type_hash);

    try setAssetNameAndFolder(asset, asset_name, asset_folder);

    var asset_obj = try readCdbObjFromJsonValue(parsed.value, asset, read_blob, tmp_allocator);

    var asset_w = _db.writeObj(asset).?;
    var asset_obj_w = _db.writeObj(asset_obj).?;
    try public.AssetType.setSubObj(_db, asset_w, .Object, asset_obj_w);
    _db.writeCommit(asset_obj_w);
    _db.writeCommit(asset_w);

    return asset;
}

fn readObjFromJson(
    comptime Reader: type,
    reader: Reader,
    read_blob: ReadBlobFn,
    tmp_allocator: std.mem.Allocator,
) !cetech1.cdb.ObjId {
    var json_reader = std.json.reader(tmp_allocator, reader);
    defer json_reader.deinit();
    var parsed = try std.json.parseFromTokenSource(std.json.Value, tmp_allocator, &json_reader, .{});
    defer parsed.deinit();
    var obj = try readCdbObjFromJsonValue(parsed.value, .{}, read_blob, tmp_allocator);
    return obj;
}

fn getOrCreate(obj_uuid: cetech1.uuid.Uuid, type_hash: cetech1.strid.StrId32) !cetech1.cdb.ObjId {
    // _get_or_create_lock.lock();
    // defer _get_or_create_lock.unlock();

    var obj = getObjId(obj_uuid);
    if (obj == null) {
        obj = try createObjectWithUuid(type_hash, obj_uuid);
    }
    return obj.?;
}

fn createObjectFromPrototypeLocked(prototype_uuid: cetech1.uuid.Uuid, type_hash: cetech1.strid.StrId32) !cetech1.cdb.ObjId {
    const prototype_obj = try getOrCreate(prototype_uuid, type_hash);

    // _get_or_create_lock.lock();
    // defer _get_or_create_lock.unlock();
    return try _db.createObjectFromPrototype(prototype_obj);
}

fn readCdbObjFromJsonValue(parsed: std.json.Value, asset: cetech1.cdb.ObjId, read_blob: ReadBlobFn, tmp_allocator: std.mem.Allocator) !cetech1.cdb.ObjId {
    const obj_uuid_str = parsed.object.get(JSON_UUID_TOKEN).?;
    const obj_uuid = try uuid.api.fromStr(obj_uuid_str.string);
    const obj_type = parsed.object.get(JSON_TYPE_NAME_TOKEN).?;
    const obj_type_hash = cetech1.strid.strId32(obj_type.string);

    const prototype_uuid = parsed.object.get(JSON_PROTOTYPE_UUID);
    var obj: ?cetech1.cdb.ObjId = null;
    if (prototype_uuid == null) {
        obj = try createObject(obj_type_hash);
    } else {
        obj = try createObjectFromPrototypeLocked(try uuid.fromStr(prototype_uuid.?.string), obj_type_hash);
    }

    var obj_w = _db.writeObj(obj.?).?;

    var prop_defs = _db.getTypePropDef(obj_type_hash).?;

    var keys = parsed.object.keys();
    for (keys) |k| {
        // Skip private fields
        if (std.mem.startsWith(u8, k, "__")) continue;
        if (std.mem.endsWith(u8, k, JSON_REMOVED_POSTFIX)) continue;
        if (std.mem.endsWith(u8, k, JSON_INSTANTIATE_POSTFIX)) continue;

        var value = parsed.object.get(k).?;

        const prop_idx = _db.getTypePropDefIdx(obj_type_hash, k) orelse continue;
        const prop_def = prop_defs[prop_idx];

        switch (prop_def.type) {
            cetech1.cdb.PropType.BOOL => {
                _db.setValue(bool, obj_w, prop_idx, value.bool);
            },
            cetech1.cdb.PropType.U64 => {
                _db.setValue(u64, obj_w, prop_idx, @intCast(value.integer));
            },
            cetech1.cdb.PropType.I64 => {
                _db.setValue(i64, obj_w, prop_idx, @intCast(value.integer));
            },
            cetech1.cdb.PropType.U32 => {
                _db.setValue(u32, obj_w, prop_idx, @intCast(value.integer));
            },
            cetech1.cdb.PropType.I32 => {
                _db.setValue(i32, obj_w, prop_idx, @intCast(value.integer));
            },
            cetech1.cdb.PropType.F64 => {
                _db.setValue(f64, obj_w, prop_idx, @floatCast(value.float));
            },
            cetech1.cdb.PropType.F32 => {
                _db.setValue(f32, obj_w, prop_idx, @floatCast(value.float));
            },
            cetech1.cdb.PropType.STR => {
                var buffer: [128]u8 = undefined;
                var str = try std.fmt.bufPrintZ(&buffer, "{s}", .{value.string});
                try _db.setStr(obj_w, prop_idx, str);
            },
            cetech1.cdb.PropType.BLOB => {
                var blob = try read_blob(asset, obj_uuid, cetech1.strid.strId32(prop_def.name), tmp_allocator);
                defer tmp_allocator.free(blob);
                var true_blob = try _db.createBlob(obj_w, prop_idx, blob.len);
                @memcpy(true_blob.?, blob);
            },
            cetech1.cdb.PropType.SUBOBJECT => {
                var subobj = try readCdbObjFromJsonValue(value, asset, read_blob, tmp_allocator);

                var subobj_w = _db.writeObj(subobj).?;
                try _db.setSubObj(obj_w, prop_idx, subobj_w);
                _db.writeCommit(subobj_w);
            },
            cetech1.cdb.PropType.REFERENCE => {
                var ref_link = std.mem.split(u8, value.string, ":");
                const ref_type = cetech1.strid.strId32(ref_link.first());
                const ref_uuid = try uuid.api.fromStr(ref_link.next().?);

                var ref_obj = try getOrCreate(ref_uuid, ref_type);

                try _db.setRef(obj_w, prop_idx, ref_obj);
            },
            cetech1.cdb.PropType.SUBOBJECT_SET => {
                for (value.array.items) |subobj_item| {
                    var subobj = try readCdbObjFromJsonValue(subobj_item, asset, read_blob, tmp_allocator);

                    var subobj_w = _db.writeObj(subobj).?;
                    try _db.addSubObjToSet(obj_w, prop_idx, &.{subobj_w});
                    _db.writeCommit(subobj_w);
                }
            },
            cetech1.cdb.PropType.REFERENCE_SET => {
                for (value.array.items) |ref| {
                    var ref_link = std.mem.split(u8, ref.string, ":");
                    const ref_type = cetech1.strid.strId32(ref_link.first());
                    const ref_uuid = try uuid.api.fromStr(ref_link.next().?);

                    var ref_obj = try getOrCreate(ref_uuid, ref_type);
                    try _db.addRefToSet(obj_w, prop_idx, &.{ref_obj});
                }

                if (prototype_uuid != null) {
                    var buff: [128]u8 = undefined;
                    var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});

                    var removed_fiedl = parsed.object.get(field_name);
                    if (removed_fiedl != null) {
                        for (removed_fiedl.?.array.items) |ref| {
                            var ref_link = std.mem.split(u8, ref.string, ":");
                            const ref_type = cetech1.strid.strId32(ref_link.first());
                            const ref_uuid = try uuid.api.fromStr(ref_link.next().?);

                            var ref_obj = try getOrCreate(ref_uuid, ref_type);
                            try _db.removeFromRefSet(obj_w, prop_idx, ref_obj);
                        }
                    }
                }
            },
            else => continue,
        }
    }

    for (prop_defs, 0..) |prop_def, prop_idx| {
        switch (prop_def.type) {
            cetech1.cdb.PropType.REFERENCE_SET, cetech1.cdb.PropType.SUBOBJECT_SET => {
                if (prototype_uuid != null) {
                    var buff: [128]u8 = undefined;
                    var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_INSTANTIATE_POSTFIX, .{prop_def.name});

                    if (prop_def.type == .SUBOBJECT_SET) {
                        var inisiated = parsed.object.get(field_name);
                        if (inisiated != null) {
                            for (inisiated.?.array.items) |subobj_item| {
                                var subobj = try readCdbObjFromJsonValue(subobj_item, asset, read_blob, tmp_allocator);
                                var subobj_w = _db.writeObj(subobj).?;
                                try _db.addSubObjToSet(obj_w, @truncate(prop_idx), &.{subobj_w});

                                var proto_w = _db.writeObj(_db.getPrototype(subobj_w)).?;
                                try _db.removeFromSubObjSet(obj_w, @truncate(prop_idx), @ptrCast(proto_w));

                                _db.writeCommit(proto_w);
                                _db.writeCommit(subobj_w);
                            }
                        }
                    }

                    field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                    var removed = parsed.object.get(field_name);
                    if (removed != null) {
                        for (removed.?.array.items) |ref| {
                            var ref_link = std.mem.split(u8, ref.string, ":");
                            const ref_type = cetech1.strid.strId32(ref_link.first());
                            const ref_uuid = try uuid.api.fromStr(ref_link.next().?);

                            var ref_obj = try getOrCreate(ref_uuid, ref_type);

                            if (prop_def.type == .REFERENCE_SET) {
                                try _db.removeFromRefSet(obj_w, @truncate(prop_idx), ref_obj);
                            } else {
                                var ref_w = _db.writeObj(ref_obj).?;
                                try _db.removeFromSubObjSet(obj_w, @truncate(prop_idx), ref_w);
                                _db.writeCommit(ref_w);
                            }
                        }
                    }
                }
            },
            else => continue,
        }
    }

    var existed_object = getObjId(obj_uuid);

    if (existed_object == null) {
        _db.writeCommit(obj_w);
        try mapUuidObjid(obj_uuid, obj.?);
        log.api.debug(MODULE_NAME, "Creating new obj {s}:{s}.", .{ obj_type.string, obj_uuid_str.string });
    } else {
        try _db.retargetWrite(obj_w, existed_object.?);
        _db.writeCommit(obj_w);
        _db.destroyObject(obj.?);
        log.api.debug(MODULE_NAME, "Retargeting obj {s}:{s}.", .{ obj_type.string, obj_uuid_str.string });
    }

    return existed_object orelse obj.?;
}

fn createNewFolder(db: *cetech1.cdb.CdbDb, parent_folder: cetech1.cdb.ObjId, name: [:0]const u8) !void {
    var new_folder = try cetech1.assetdb.FolderType.createObject(db);
    var new_folder_w = db.writeObj(new_folder).?;

    try cetech1.assetdb.FolderType.setRef(db, new_folder_w, .Parent, parent_folder);
    try cetech1.assetdb.FolderType.setStr(db, new_folder_w, .Name, name);

    db.writeCommit(new_folder_w);

    try addFolderToRoot(new_folder);
}

fn onObjidDestroyed(db: *cetech1.cdb.Db, objects: []cetech1.cdb.ObjId) void {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();

    _ = db;

    for (objects) |obj| {
        var obj_uuid = _objid2uuid.get(obj) orelse continue;
        _ = _uuid2objid.swapRemove(obj_uuid);
        _ = _objid2uuid.swapRemove(obj);
        log.api.debug(MODULE_NAME, "Unmaping destroyed objid {any}:{s}", .{ obj, obj_uuid });
    }
}
