// I realy hate file, dirs and paths.
// Full of alloc shit and another braindump solution. Need cleanup but its works =).

const std = @import("std");
const apidb = @import("apidb.zig");
const task = @import("task.zig");
const cdb_private = @import("cdb.zig");

const uuid_private = @import("uuid.zig");
const tempalloc = @import("tempalloc.zig");
const profiler = @import("profiler.zig");
const platform_private = @import("platform.zig");

const cetech1 = @import("cetech1");
const public = cetech1.assetdb;
const cdb = cetech1.cdb;
const uuid = cetech1.uuid;

const platform = cetech1.platform;
const cdb_types = cetech1.cdb_types;

var _cdb = &cdb_private.api;

const coreui = @import("coreui.zig");
const propIdx = cdb.propIdx;

test {
    _ = std.testing.refAllDecls(@import("assetdb_test.zig"));
}

const Uuid2ObjId = cetech1.AutoArrayHashMap(uuid.Uuid, cdb.ObjId);
const ObjId2Uuid = cetech1.AutoArrayHashMap(cdb.ObjId, uuid.Uuid);

const TaskList = cetech1.task.TaskIdList;

// File info
// TODO: to struct
const Path2Folder = std.StringArrayHashMapUnmanaged(cdb.ObjId);
const Folder2Path = cetech1.AutoArrayHashMap(cdb.ObjId, []u8);
const Uuid2AssetUuid = cetech1.AutoArrayHashMap(uuid.Uuid, uuid.Uuid);
const AssetUuid2Path = cetech1.AutoArrayHashMap(uuid.Uuid, []u8);
const AssetUuid2Depend = cetech1.AutoArrayHashMap(uuid.Uuid, UuidSet);
const AssetObjIdVersion = cetech1.AutoArrayHashMap(cdb.ObjId, u64);
const ToDeleteList = cetech1.ArraySet(cdb.ObjId);
const UuidSet = cetech1.ArraySet(uuid.Uuid);

const AssetIOSet = cetech1.ArraySet(*public.AssetIOI);

const module_name = .assetdb;

const log = std.log.scoped(module_name);

// Keywords for json format
const JSON_ASSET_VERSION = "__version";
const JSON_ASSET_UUID_TOKEN = "__asset_uuid";
const JSON_TAGS_TOKEN = "__tags";
const JSON_DESCRIPTION_TOKEN = "__description";
const JSON_TYPE_NAME_TOKEN = "__type_name";
const JSON_UUID_TOKEN = "__uuid";
const JSON_PROTOTYPE_UUID = "__prototype_uuid";
const JSON_REMOVED_POSTFIX = "__removed";
const JSON_INSTANTIATE_POSTFIX = "__instantiate";

const CT_ASSETS_FILE_PREFIX = ".json";
const BLOB_EXTENSION = "ct_blob";

const ASSET_CURRENT_VERSION_STR = "0.1.0";
const ASSET_CURRENT_VERSION = std.SemanticVersion.parse(ASSET_CURRENT_VERSION_STR) catch undefined;

const PROJECT_FILENAME = "project." ++ public.Project.name ++ ".json";
const FOLDER_FILENAME = "." ++ public.Folder.name ++ ".json";

// Type for root of all assets
pub const AssetRoot = public.AssetRoot;

const WriteBlobFn = *const fn (
    blob: []const u8,
    asset: cdb.ObjId,
    obj_uuid: uuid.Uuid,
    prop_hash: cetech1.StrId32,
    root_path: []const u8,
    allocator: std.mem.Allocator,
) anyerror!void;

const ReadBlobFn = *const fn (
    asset: cdb.ObjId,
    obj_uuid: uuid.Uuid,
    prop_hash: cetech1.StrId32,
    allocator: std.mem.Allocator,
) anyerror![]u8;

pub var api = public.AssetDBAPI{
    .createAssetFn = createAsset,
    .openAssetRootFolderFn = openAssetRootFolder,
    .getRootFolderFn = getRootFolder,
    .getObjIdFn = getObjId,
    .getUuidFn = getUuid,
    .getOrCreateUUIDFn = getOrCreateUuid,
    .addAssetIOFn = addAssetIO,
    .removeAssetIOFn = removeAssetIO,
    .getTmpPathFn = getTmpPath,
    .isAssetModifiedFn = isObjModified,
    .isProjectModifiedFn = isProjectModified,
    .saveAllModifiedAssetsFn = saveAllModifiedAssets,
    .saveAllAssetsFn = saveAll,
    .saveAssetFn = saveAssetAndWait,
    .getAssetForObj = getAssetForObj,
    .getObjForAsset = getObjForAsset,
    .isAssetFolder = isAssetFolder,
    .isProjectOpened = isProjectOpened,
    .getFilePathForAsset = getFilePathForAsset,
    .getPathForFolder = getPathForFolder,
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
};

var asset_root_type: cdb.TypeIdx = undefined;

var _allocator: std.mem.Allocator = undefined;
var _db: cdb.DbId = undefined;
var _assetio_set: AssetIOSet = undefined;
pub var _assetroot_fs: AssetRootFS = undefined; // TODO: remove pub
var _str_intern: cetech1.string.InternWithLock([]const u8) = undefined;

// file info

const AnalyzeInfo = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    file_info_lck: std.Thread.Mutex,

    path2folder: Path2Folder = .{},
    folder2path: Folder2Path = .{},
    uuid2asset_uuid: Uuid2AssetUuid = .{},
    asset_uuid2path: AssetUuid2Path = .{},
    asset_uuid2depend: AssetUuid2Depend = .{},

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .file_info_lck = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.asset_uuid2path.values()) |path| {
            _allocator.free(path);
        }

        for (self.path2folder.keys()) |path| {
            _allocator.free(path);
        }

        for (self.folder2path.values()) |path| {
            _allocator.free(path);
        }

        for (self.asset_uuid2depend.values()) |*depend| {
            depend.deinit(self.allocator);
        }

        self.path2folder.deinit(self.allocator);
        self.folder2path.deinit(self.allocator);
        self.uuid2asset_uuid.deinit(self.allocator);
        self.asset_uuid2path.deinit(self.allocator);
        self.asset_uuid2depend.deinit(self.allocator);
    }

    fn addAnalyzedFileInfo(self: *Self, path: []const u8, asset_uuid: uuid.Uuid, depend_on: *UuidSet, provide_uuids: *UuidSet) !void {
        // TODO
        self.file_info_lck.lock();
        defer self.file_info_lck.unlock();

        try self.asset_uuid2path.put(self.allocator, asset_uuid, try _allocator.dupe(u8, path));

        for (provide_uuids.unmanaged.keys()) |provide_uuid| {
            try self.uuid2asset_uuid.put(self.allocator, provide_uuid, asset_uuid);
        }

        if (self.asset_uuid2depend.getPtr(asset_uuid)) |depend| {
            depend.deinit(self.allocator);
        }

        try self.asset_uuid2depend.put(self.allocator, asset_uuid, try depend_on.clone(_allocator));
    }

    fn resetAnalyzedFileInfo(self: *Self) !void {
        // TODO
        self.file_info_lck.lock();
        defer self.file_info_lck.unlock();

        for (self.asset_uuid2path.values()) |path| {
            _allocator.free(path);
        }

        for (self.path2folder.keys()) |path| {
            _allocator.free(path);
        }

        for (self.folder2path.values()) |path| {
            _allocator.free(path);
        }

        for (self.asset_uuid2depend.values()) |*depend| {
            depend.deinit(self.allocator);
        }

        self.asset_uuid2path.clearRetainingCapacity();
        self.uuid2asset_uuid.clearRetainingCapacity();
        self.asset_uuid2depend.clearRetainingCapacity();
        self.path2folder.clearRetainingCapacity();
        self.folder2path.clearRetainingCapacity();
    }

    fn analyzeFile(self: *Self, allocator: std.mem.Allocator, path: []const u8) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        defer file.close();

        var buffer: [4096]u8 = undefined;
        var file_r = file.reader(&buffer);
        const reader = &file_r.interface;

        var json_reader = std.json.Reader.init(allocator, reader);
        defer json_reader.deinit();

        var parsed = try std.json.parseFromTokenSource(std.json.Value, allocator, &json_reader, .{ .parse_numbers = false });
        defer parsed.deinit();

        const version_str = parsed.value.object.get(JSON_ASSET_VERSION).?;

        try validateVersion(version_str.string);

        const asset_uuid_str = parsed.value.object.get(JSON_ASSET_UUID_TOKEN).?;
        const asset_uuid = uuid_private.api.fromStr(asset_uuid_str.string).?;

        var depend_on = UuidSet.init();
        defer depend_on.deinit(allocator);

        var provide_uuids = UuidSet.init();
        defer provide_uuids.deinit(allocator);

        try analyzFromJsonValue(parsed.value, allocator, &depend_on, &provide_uuids);
        try self.addAnalyzedFileInfo(path, asset_uuid, &depend_on, &provide_uuids);
    }

    fn analyzeFolder(self: *Self, root_dir: std.fs.Dir, parent_folder: cdb.ObjId, tasks: *TaskList, allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var iterator = root_dir.iterate();
        while (try iterator.next()) |entry| {
            // Skip . files
            if (std.mem.startsWith(u8, entry.name, ".")) continue;

            if (entry.kind == .file) {
                const extension = std.fs.path.extension(entry.name);
                if (!std.mem.startsWith(u8, extension, CT_ASSETS_FILE_PREFIX)) continue;
                if (std.mem.startsWith(u8, entry.name, ".")) continue;

                const Task = struct {
                    fi: *AnalyzeInfo,
                    root_dir: std.fs.Dir,
                    path: []const u8,
                    allocator: std.mem.Allocator,
                    pub fn exec(s: *@This()) !void {
                        defer s.allocator.free(s.path);

                        s.fi.analyzeFile(s.allocator, s.path) catch |err| {
                            log.err("Could not analyze asset {}", .{err});
                            return;
                        };
                    }
                };
                const task_id = try task.api.schedule(
                    cetech1.task.TaskID.none,
                    Task{
                        .fi = self,
                        .root_dir = root_dir,
                        .path = try root_dir.realpathAlloc(allocator, entry.name),
                        .allocator = allocator,
                    },
                    .{},
                );
                try tasks.append(allocator, task_id);
            } else if (entry.kind == .directory) {
                if (std.mem.endsWith(u8, entry.name, "." ++ BLOB_EXTENSION)) continue;
                var dir = try root_dir.openDir(entry.name, .{ .iterate = true });
                defer dir.close();

                const folder_asset = try getOrCreateFolder(allocator, root_dir, dir, entry.name, parent_folder);

                try self.path2folder.put(self.allocator, try dir.realpathAlloc(_allocator, "."), folder_asset);
                try self.folder2path.put(self.allocator, folder_asset, try dir.realpathAlloc(_allocator, "."));

                try self.analyzeFolder(dir, folder_asset, tasks, allocator);
                try _assetroot_fs.addAssetToRoot(folder_asset);
            }
        }
    }

    fn analyzFromJsonValue(parsed: std.json.Value, allocator: std.mem.Allocator, depend_on: *UuidSet, provide_uuids: *UuidSet) !void {
        const obj_uuid_str = parsed.object.get(JSON_UUID_TOKEN).?;
        const obj_uuid = uuid_private.api.fromStr(obj_uuid_str.string).?;
        const obj_type = parsed.object.get(JSON_TYPE_NAME_TOKEN).?;
        const obj_type_hash = cetech1.strId32(obj_type.string);
        const obj_type_idx = _cdb.getTypeIdx(_db, obj_type_hash).?;

        _ = try provide_uuids.add(allocator, obj_uuid);

        const prototype_uuid = parsed.object.get(JSON_PROTOTYPE_UUID);
        if (prototype_uuid) |proto_uuid| {
            _ = try depend_on.add(allocator, uuid_private.fromStr(proto_uuid.string).?);
        }

        const tags = parsed.object.get(JSON_TAGS_TOKEN);
        if (tags) |tags_array| {
            for (tags_array.array.items) |value| {
                var ref_link = std.mem.splitAny(u8, value.string, ":");
                const ref_type = cetech1.strId32(ref_link.first());
                const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;
                _ = ref_type;
                _ = try depend_on.add(allocator, ref_uuid);
            }
        }

        const prop_defs = _cdb.getTypePropDef(_db, obj_type_idx).?;

        const keys = parsed.object.keys();
        for (keys) |k| {
            // Skip private fields
            if (std.mem.startsWith(u8, k, "__")) continue;
            if (std.mem.endsWith(u8, k, JSON_REMOVED_POSTFIX)) continue;
            if (std.mem.endsWith(u8, k, JSON_INSTANTIATE_POSTFIX)) continue;

            const value = parsed.object.get(k).?;

            const prop_idx = _cdb.getTypePropDefIdx(_db, obj_type_idx, k) orelse continue;
            const prop_def = prop_defs[prop_idx];

            switch (prop_def.type) {
                cdb.PropType.SUBOBJECT => {
                    try analyzFromJsonValue(value, allocator, depend_on, provide_uuids);
                },
                cdb.PropType.REFERENCE => {
                    var ref_link = std.mem.splitAny(u8, value.string, ":");
                    const ref_type = cetech1.strId32(ref_link.first());
                    const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;
                    _ = ref_type;
                    _ = try depend_on.add(allocator, ref_uuid);
                },
                cdb.PropType.SUBOBJECT_SET => {
                    for (value.array.items) |subobj_item| {
                        try analyzFromJsonValue(subobj_item, allocator, depend_on, provide_uuids);
                    }
                },
                cdb.PropType.REFERENCE_SET => {
                    for (value.array.items) |ref| {
                        var ref_link = std.mem.splitAny(u8, ref.string, ":");
                        const ref_type = cetech1.strId32(ref_link.first());
                        const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;
                        _ = ref_type;
                        _ = try depend_on.add(allocator, ref_uuid);
                    }
                },
                else => continue,
            }
        }
    }
};

const AssetRootFS = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    analyzer: AnalyzeInfo,

    // Delete list
    assets_to_remove: ToDeleteList = .init(),
    folders_to_remove: ToDeleteList = .init(),

    // Tmp
    tmp_depend_array: cetech1.task.TaskIdList = .{},
    tmp_taskid_map: cetech1.AutoArrayHashMap(uuid.Uuid, cetech1.task.TaskID) = .{},

    // Version check
    asset_objid2version: AssetObjIdVersion = .{},
    asset_objid2version_lck: std.Thread.Mutex,

    // DAG
    asset_dag: cetech1.dag.DAG(uuid.Uuid),

    // UUID maping
    uuid2objid: Uuid2ObjId = .{},
    objid2uuid: ObjId2Uuid = .{},
    uuid2objid_lock: std.Thread.Mutex,

    // Asset ROOT
    asset_root: cdb.ObjId,
    asset_root_lock: std.Thread.Mutex,
    asset_root_last_version: u64,
    asset_root_folder: cdb.ObjId,
    asset_root_path: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var self: Self = .{
            .allocator = allocator,
            .analyzer = try AnalyzeInfo.init(allocator),

            .asset_objid2version_lck = .{},

            .asset_dag = cetech1.dag.DAG(uuid.Uuid).init(allocator),

            .uuid2objid_lock = .{},

            .asset_root = try _cdb.createObject(_db, asset_root_type),
            .asset_root_lock = .{},
            .asset_root_last_version = 0,
            .asset_root_path = null,
            .asset_root_folder = .{},
        };

        //TODO: unshit
        const root_folder = try public.Folder.createObject(_cdb, _db);
        const folder_asset = try public.Asset.createObject(_cdb, _db);
        const asset_w = _cdb.writeObj(folder_asset).?;
        const folder_obj_w = _cdb.writeObj(root_folder).?;
        try public.Asset.setSubObj(_cdb, asset_w, .Object, folder_obj_w);
        try _cdb.writeCommit(asset_w);
        try _cdb.writeCommit(folder_obj_w);

        try self.addAssetToRoot(folder_asset);
        self.markObjSaved(folder_asset, _cdb.getVersion(folder_asset));
        self.asset_root_folder = folder_asset;
        self.asset_root_last_version = _cdb.getVersion(self.asset_root);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.analyzer.deinit();

        if (self.asset_root_path) |asset_root| {
            self.allocator.free(asset_root);
        }

        _cdb.destroyObject(self.asset_root);

        self.assets_to_remove.deinit(self.allocator);
        self.folders_to_remove.deinit(self.allocator);

        self.tmp_depend_array.deinit(self.allocator);
        self.tmp_taskid_map.deinit(self.allocator);

        self.asset_objid2version.deinit(self.allocator);
        self.asset_dag.deinit();

        self.uuid2objid.deinit(self.allocator);
        self.objid2uuid.deinit(self.allocator);
    }

    pub fn reset(self: *Self) void {
        self.assets_to_remove.clearRetainingCapacity();
        self.folders_to_remove.clearRetainingCapacity();

        self.asset_objid2version_lck.lock();
        defer self.asset_objid2version_lck.unlock();
        self.asset_objid2version.clearRetainingCapacity();
    }

    pub fn isModified(self: Self) bool {
        const cur_version = _cdb.getVersion(self.asset_root);
        return cur_version != self.asset_root_last_version or (self.folders_to_remove.cardinality() != 0 or self.assets_to_remove.cardinality() != 0);
    }

    pub fn isObjModified(self: Self, asset: cdb.ObjId) bool {
        const cur_version = _cdb.getVersion(asset);

        // asset_objid2version_lck.lock();
        // defer asset_objid2version_lck.unlock();
        const saved_version = self.asset_objid2version.get(asset) orelse return true;
        return cur_version != saved_version;
    }

    fn deleteAsset(self: *Self, asset: cdb.ObjId) anyerror!void {
        _ = try self.assets_to_remove.add(self.allocator, asset);
    }

    fn deleteFolder(self: *Self, folder: cdb.ObjId) anyerror!void {
        _ = try self.folders_to_remove.add(self.allocator, folder);
    }

    fn isToDeleted(self: Self, asset_or_folder: cdb.ObjId) bool {
        if (isAssetFolder(asset_or_folder)) {
            return self.folders_to_remove.contains(asset_or_folder);
        } else {
            return self.assets_to_remove.contains(asset_or_folder);
        }
    }

    fn reviveDeleted(self: *Self, asset_or_folder: cdb.ObjId) void {
        if (isAssetFolder(asset_or_folder)) {
            _ = self.folders_to_remove.remove(asset_or_folder);
        } else {
            _ = self.assets_to_remove.remove(asset_or_folder);
        }
    }

    fn commitDeleteChanges(self: *Self, allocator: std.mem.Allocator) !void {
        _ = allocator; // autofix
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (self.asset_root_path) |asset_root| {
            var root_dir = try std.fs.cwd().openDir(asset_root, .{});
            defer root_dir.close();
            for (self.folders_to_remove.unmanaged.keys()) |folder| {
                var buff: [128]u8 = undefined;
                const path = try getPathForFolder(&buff, folder);
                try root_dir.deleteTree(std.fs.path.dirname(path).?);
                _cdb.destroyObject(folder);
            }

            for (self.assets_to_remove.unmanaged.keys()) |asset| {
                var buff: [128]u8 = undefined;

                // Blob
                const blob_dir_path = try getPathForAsset(&buff, asset, BLOB_EXTENSION);
                try root_dir.deleteTree(blob_dir_path);

                // asset
                const path = try self.getFilenamePathForAsset(&buff, asset);
                try root_dir.deleteTree(path);
                _cdb.destroyObject(asset);
            }
        }

        self.folders_to_remove.clearRetainingCapacity();
        self.assets_to_remove.clearRetainingCapacity();
    }

    pub fn getFilenamePathForAsset(self: *Self, buff: []u8, asset: cdb.ObjId) ![]u8 {
        _ = self;

        const asset_r = _cdb.readObj(asset);
        const asset_obj = public.Asset.readSubObj(_cdb, asset_r.?, .Object).?;

        const asset_name = try getPathForAsset(buff, asset, _cdb.getTypeName(_db, asset_obj.type_idx).?);
        return std.fmt.bufPrint(buff, "{s}.json", .{asset_name});
    }

    pub fn saveAllTo(self: *Self, allocator: std.mem.Allocator, root_path: []const u8) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        self.asset_root_lock.lock();
        defer self.asset_root_lock.unlock();

        const assets = (try AssetRoot.readSubObjSet(_cdb, _cdb.readObj(self.asset_root).?, .Assets, allocator)).?;
        defer allocator.free(assets);

        if (assets.len == 0) return;

        var tasks = try TaskList.initCapacity(allocator, assets.len);
        defer tasks.deinit(allocator);

        for (assets) |asset| {
            if (self.isToDeleted(asset)) continue;

            const export_task = try self.saveAsset(allocator, root_path, asset);
            if (export_task == .none) continue;
            tasks.appendAssumeCapacity(export_task);
        }

        task.api.waitMany(tasks.items);

        self.asset_root_last_version = _cdb.getVersion(self.asset_root);
    }

    pub fn saveAll(self: *Self, allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        try self.saveAllTo(allocator, self.asset_root_path.?);
        try self.commitDeleteChanges(allocator);
    }

    pub fn saveAllModifiedAssets(self: *Self, allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        self.asset_root_lock.lock();
        defer self.asset_root_lock.unlock();

        const assets = (try AssetRoot.readSubObjSet(_cdb, _cdb.readObj(self.asset_root).?, .Assets, allocator)).?;
        defer allocator.free(assets);

        var tasks = try TaskList.initCapacity(allocator, assets.len);
        defer tasks.deinit(allocator);

        for (assets) |asset| {
            if (self.isToDeleted(asset)) continue;
            if (!self.isObjModified(asset)) continue;

            if (self.saveAsset(allocator, self.asset_root_path.?, asset)) |export_task| {
                if (export_task == .none) continue;
                tasks.appendAssumeCapacity(export_task);
            } else |err| {
                log.err("Could not save asset {}", .{err});
            }
        }

        try self.commitDeleteChanges(allocator);

        task.api.waitMany(tasks.items);

        self.asset_root_last_version = _cdb.getVersion(self.asset_root);
    }

    fn saveAsAllAssets(self: *Self, allocator: std.mem.Allocator, path: []const u8) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        try self.analyzer.resetAnalyzedFileInfo();
        self.assets_to_remove.clearRetainingCapacity();
        self.folders_to_remove.clearRetainingCapacity();
        {
            self.asset_objid2version_lck.lock();
            defer self.asset_objid2version_lck.unlock();
            self.asset_objid2version.clearRetainingCapacity();
        }

        self.tmp_depend_array.clearRetainingCapacity();
        self.tmp_taskid_map.clearRetainingCapacity();

        try self.saveAllTo(allocator, path);
    }

    pub fn markObjSaved(self: *Self, objdi: cdb.ObjId, version: u64) void {
        self.asset_objid2version_lck.lock();
        defer self.asset_objid2version_lck.unlock();
        self.asset_objid2version.put(self.allocator, objdi, version) catch undefined;
    }

    fn getObjId(self: *Self, obj_uuid: uuid.Uuid) ?cdb.ObjId {
        self.uuid2objid_lock.lock();
        defer self.uuid2objid_lock.unlock();
        return self.uuid2objid.get(obj_uuid);
    }

    fn getUuid(self: *Self, obj: cdb.ObjId) ?uuid.Uuid {
        self.uuid2objid_lock.lock();
        defer self.uuid2objid_lock.unlock();
        return self.objid2uuid.get(obj);
    }

    fn mapUuidObjid(self: *Self, obj_uuid: uuid.Uuid, objid: cdb.ObjId) !void {
        self.uuid2objid_lock.lock();
        defer self.uuid2objid_lock.unlock();
        try self.uuid2objid.put(self.allocator, obj_uuid, objid);
        try self.objid2uuid.put(self.allocator, objid, obj_uuid);
    }

    fn isProjectOpened(self: Self) bool {
        return self.asset_root_path != null;
    }

    pub fn getTmpPath(
        self: Self,
        path_buf: []u8,
    ) !?[]u8 {
        const root_path = self.asset_root_path orelse return null;

        var root_dir = try std.fs.cwd().openDir(root_path, .{});
        defer root_dir.close();
        return try root_dir.realpath(public.CT_TEMP_FOLDER, path_buf);
    }

    fn getRootFolder(self: Self) cdb.ObjId {
        return self.asset_root_folder;
    }

    fn addAssetToRoot(self: *Self, asset: cdb.ObjId) !void {
        // TODO: make posible CAS write to CDB and remove lock.
        self.asset_root_lock.lock();
        defer self.asset_root_lock.unlock();

        const asset_root_w = _cdb.writeObj(self.asset_root).?;
        const asset_w = _cdb.writeObj(asset).?;
        try AssetRoot.addSubObjToSet(_cdb, asset_root_w, .Assets, &.{asset_w});
        try _cdb.writeCommit(asset_w);
        try _cdb.writeCommit(asset_root_w);
    }

    fn openAssetRootFolder(self: *Self, asset_root_path: []const u8, allocator: std.mem.Allocator) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        if (self.asset_root_path) |asset_root| {
            self.allocator.free(asset_root);
        }
        if (std.fs.path.isAbsolute(asset_root_path)) {
            self.asset_root_path = try self.allocator.dupe(u8, asset_root_path);
        } else {
            self.asset_root_path = try std.fs.cwd().realpathAlloc(self.allocator, asset_root_path);
        }

        var root_dir = try std.fs.openDirAbsolute(self.asset_root_path.?, .{ .iterate = true });
        defer root_dir.close();

        try root_dir.makePath(public.CT_TEMP_FOLDER);

        if (!self.asset_root.isEmpty()) {
            _cdb.destroyObject(self.asset_root);

            // Force GC
            try _cdb.gc(allocator, _db);

            self.asset_root = try _cdb.createObject(_db, asset_root_type);
        }

        // asset root folder
        self.asset_root_folder = try getOrCreateFolder(allocator, root_dir, root_dir, null, null);
        try self.addAssetToRoot(self.asset_root_folder);
        const root_path = try root_dir.realpathAlloc(_allocator, ".");
        log.info("Asset root dir {s}", .{root_path});

        // project asset
        // TODO: SHIT
        var project_asset: ?cdb.ObjId = null;
        if (!existRootProjectAsset(root_dir)) {
            const project_obj = try public.Project.createObject(_cdb, _db);
            const pa = createAsset("project", self.asset_root_folder, project_obj).?;
            const save_task = try self.saveAsset(allocator, self.asset_root_path.?, pa);
            task.api.wait(save_task);
        } else {
            project_asset = try loadProject(allocator, _db, asset_root_path, self.asset_root_folder);
        }

        try self.analyzer.resetAnalyzedFileInfo();
        self.reset();

        // TODO: SHIT
        if (project_asset) |a| {
            self.markObjSaved(a, _cdb.getVersion(a));
        }

        try self.analyzer.path2folder.put(self.allocator, root_path, self.asset_root_folder);
        self.markObjSaved(self.asset_root_folder, _cdb.getVersion(self.asset_root_folder));

        var tasks = TaskList{};
        defer tasks.deinit(allocator);
        try self.analyzer.analyzeFolder(root_dir, self.asset_root_folder, &tasks, allocator);
        task.api.waitMany(tasks.items);
        //tasks.clearRetainingCapacity();

        try self.asset_dag.reset();
        for (self.analyzer.asset_uuid2depend.keys(), self.analyzer.asset_uuid2depend.values()) |asset_uuid, depends| {
            var depend_asset = UuidSet.init();
            defer depend_asset.deinit(allocator);

            for (depends.unmanaged.keys()) |depend_uuid| {
                const d = self.analyzer.uuid2asset_uuid.get(depend_uuid).?;
                if (std.mem.eql(u8, &d.bytes, &asset_uuid.bytes)) continue;
                _ = try depend_asset.add(allocator, d);
            }

            try self.asset_dag.add(asset_uuid, depend_asset.unmanaged.keys());
        }

        try self.asset_dag.build_all();

        try self.writeAssetGraphD2();

        if (false) {
            for (self.asset_dag.output.keys()) |output| {
                log.debug("Loader plan {s}", .{self.analyzer.asset_uuid2path.get(output).?});
                const depeds = self.asset_dag.dependList(output);
                if (depeds != null) {
                    for (depeds.?) |value| {
                        log.debug("  | {s}", .{self.analyzer.asset_uuid2path.get(value).?});
                    }
                }
            }
        }

        for (self.asset_dag.output.keys()) |asset_uuid| {
            const asset_path = self.analyzer.asset_uuid2path.get(asset_uuid).?;
            const filename = std.fs.path.basename(asset_path);
            const extension = std.fs.path.extension(asset_path);
            const dirname = std.fs.path.dirname(asset_path).?;
            const parent_folder = self.analyzer.path2folder.get(dirname).?;

            // skip
            if (std.mem.eql(u8, filename, PROJECT_FILENAME)) continue;

            const asset_io = findFirstAssetIOForImport(filename, extension) orelse continue;

            var prereq = cetech1.task.TaskID.none;
            const depeds = self.asset_dag.dependList(asset_uuid);
            if (depeds != null) {
                self.tmp_depend_array.clearRetainingCapacity();
                for (depeds.?) |d| {
                    if (self.tmp_taskid_map.get(d)) |task_id| {
                        try self.tmp_depend_array.append(self.allocator, task_id);
                    } else {
                        log.err("No task for UUID {f}", .{d});
                    }
                }
                prereq = try task.api.combine(self.tmp_depend_array.items);
            }

            const copy_dir = try std.fs.openDirAbsolute(dirname, .{});
            if (asset_io.importAsset.?(_db, prereq, copy_dir, parent_folder, filename, null)) |import_task| {
                try self.tmp_taskid_map.put(self.allocator, asset_uuid, import_task);
            } else |err| {
                log.err("Could not import asset {s} {}", .{ asset_path, err });
            }
        }

        //try writeAssetDOTGraph();

        // const sync_job = try task.api.combine(self.tmp_taskid_map.values());
        task.api.waitMany(self.tmp_taskid_map.values());

        // Resave obj version
        const all_asset_copy = try allocator.dupe(cdb.ObjId, self.asset_objid2version.keys());
        defer allocator.free(all_asset_copy);
        for (all_asset_copy) |obj| {
            try self.asset_objid2version.put(self.allocator, obj, _cdb.getVersion(obj));
        }

        self.asset_root_last_version = _cdb.getVersion(self.asset_root);

        const impls = try apidb.api.getImpl(allocator, public.AssetRootOpenedI);
        defer allocator.free(impls);
        for (impls) |iface| {
            if (iface.opened) |opened| {
                try opened();
            }
        }
    }

    fn writeAssetGraphD2(self: Self) !void {
        var root_dir = try std.fs.cwd().openDir(self.asset_root_path.?, .{});
        defer root_dir.close();

        var dot_file = try root_dir.createFile(public.CT_TEMP_FOLDER ++ "/" ++ "assetdb_graph.d2", .{});
        defer dot_file.close();

        var buffer: [4096]u8 = undefined;

        var bw = dot_file.writer(&buffer);
        defer bw.interface.flush() catch undefined;

        var writer = &bw.interface;

        // write header
        _ = try writer.write("vars: {d2-config: {layout-engine: elk}}\n\n");

        // write nodes
        for (self.analyzer.asset_uuid2path.keys(), self.analyzer.asset_uuid2path.values()) |asset_uuid, asset_path| {
            const path = try std.fs.path.relative(_allocator, _assetroot_fs.asset_root_path.?, asset_path);
            defer _allocator.free(path);

            try writer.print("{f}: {s}\n", .{ asset_uuid, path });
        }
        try writer.print("\n", .{});

        // Edges
        for (self.analyzer.asset_uuid2depend.keys(), self.analyzer.asset_uuid2depend.values()) |asset_uuid, depends| {
            for (depends.unmanaged.keys()) |depend| {
                try writer.print("{f}->{f}\n", .{ asset_uuid, self.analyzer.uuid2asset_uuid.get(depend).? });
            }
        }
    }

    pub fn saveAsset(self: *Self, allocator: std.mem.Allocator, root_path: []const u8, asset: cdb.ObjId) !cetech1.task.TaskID {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        var buff: [128]u8 = undefined;
        const sub_path = try self.getFilenamePathForAsset(&buff, asset);

        var root_dir = try std.fs.cwd().openDir(root_path, .{});
        defer root_dir.close();

        if (!isAssetFolder(asset)) {
            const asset_uuid = self.getUuid(asset);
            if (asset_uuid) |a_uuid| {
                if (self.analyzer.asset_uuid2path.get(a_uuid)) |old_path| {
                    const root_full_path = try root_dir.realpathAlloc(allocator, ".");
                    defer allocator.free(root_full_path);

                    const realtive_old = try std.fs.path.relative(allocator, root_full_path, old_path);
                    defer allocator.free(realtive_old);

                    // rename or move.
                    if (!std.mem.eql(u8, realtive_old, sub_path)) {
                        // This shit remove blobl dir if needed...
                        const old_dirpath = std.fs.path.dirname(realtive_old) orelse "";
                        const old_base_name = std.fs.path.basename(old_path);
                        const old_name = std.fs.path.stem(std.fs.path.stem(old_base_name));
                        const blob_dir_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ old_name, BLOB_EXTENSION });
                        defer allocator.free(blob_dir_name);
                        const blob_path = try std.fs.path.join(allocator, &.{ old_dirpath, blob_dir_name });
                        defer allocator.free(blob_path);
                        try root_dir.deleteTree(blob_path);

                        // Rename
                        if (std.fs.path.dirname(sub_path)) |dir| {
                            try root_dir.makePath(dir);
                        }

                        try root_dir.rename(realtive_old, sub_path);
                        try self.analyzer.asset_uuid2path.put(self.allocator, a_uuid, try root_dir.realpathAlloc(_allocator, sub_path));
                        _allocator.free(old_path);
                    }
                }
            }
        }

        var extension = std.fs.path.extension(sub_path);
        if (extension.len == 0) {
            extension = sub_path;
        }

        if (findFirstAssetIOForExport(_db, asset, sub_path, extension)) |asset_io| {
            const taskid = try asset_io.exportAsset.?(_db, root_path, sub_path, asset);
            return taskid;
        }

        return .none;
    }

    fn saveFolderObj(self: *Self, allocator: std.mem.Allocator, folder_asset: cdb.ObjId, root_path: []const u8) !void {
        var zone_ctx = profiler.ztracy.Zone(@src());
        defer zone_ctx.End();

        self.analyzer.file_info_lck.lock();
        defer self.analyzer.file_info_lck.unlock();

        var buff: [128]u8 = undefined;
        const sub_path = try getPathForFolder(&buff, folder_asset);

        var root_dir = try std.fs.cwd().openDir(root_path, .{});
        defer root_dir.close();

        const subdir = std.fs.path.dirname(sub_path) orelse ".";
        if (self.analyzer.folder2path.get(folder_asset)) |old_path| {
            const root_full_path = try root_dir.realpathAlloc(allocator, ".");
            defer allocator.free(root_full_path);

            const realtive_old = try std.fs.path.relative(allocator, root_full_path, old_path);
            defer allocator.free(realtive_old);

            // rename or move.
            if (!std.mem.eql(u8, realtive_old, subdir)) {
                try root_dir.makePath(subdir);

                try root_dir.rename(realtive_old, subdir);
                try self.analyzer.folder2path.put(self.allocator, folder_asset, try root_dir.realpathAlloc(_allocator, subdir));
                //try self.analyzer.path2folder.put(try root_dir.realpathAlloc(_allocator, subdir), folder_asset);
                _allocator.free(old_path);
            }
        }

        if (std.fs.path.dirname(sub_path)) |dir| {
            try root_dir.makePath(dir);
        }

        var obj_file = try root_dir.createFile(sub_path, .{});
        defer obj_file.close();

        var buffer: [4096]u8 = undefined;

        var bw = obj_file.writer(&buffer);
        const writer = &bw.interface;
        defer writer.flush() catch undefined;

        log.info("Creating folder asset in {s}.", .{sub_path});

        try writeCdbObjJson(
            folder_asset,
            writer,
            folder_asset,
            WriteBlobToFile,
            root_path,
            allocator,
        );

        _assetroot_fs.markObjSaved(folder_asset, _cdb.getVersion(folder_asset));

        if (!self.analyzer.folder2path.contains(folder_asset)) {
            try self.analyzer.folder2path.put(self.allocator, folder_asset, try root_dir.realpathAlloc(_allocator, subdir));
        }
    }
};

//TODO:
//  without lock? (actualy problem when creating ref_placeholder and real ref).
//  ref_placeholder is needed because there is unsorderd order for load. ordered need analyze phase for UUID.
//var _get_or_create_lock = std.Thread.Mutex{};

var _cdb_asset_io_i = public.AssetIOI.implement(struct {
    pub fn canImport(filename: []const u8, _: []const u8) bool {
        const extension = std.fs.path.extension(filename);
        if (!std.ascii.eqlIgnoreCase(extension, ".json")) return false;

        const f2 = std.fs.path.stem(filename);

        const type_name = std.fs.path.extension(f2)[1..];

        const type_hash = cetech1.strId32(type_name);
        return _cdb.getTypeIdx(_db, type_hash) != null;
    }

    pub fn canExport(db: cdb.DbId, asset: cdb.ObjId, filename: []const u8, _: []const u8) bool {
        _ = db; // autofix

        const extension = std.fs.path.extension(filename);
        if (!std.ascii.eqlIgnoreCase(extension, ".json")) return false;

        const type_name = blk: {
            if (filename[0] == '.') {
                break :blk std.fs.path.stem(filename);
            } else {
                const f2 = std.fs.path.stem(filename);
                break :blk std.fs.path.extension(f2)[1..];
            }
        };

        const type_hash = cetech1.strId32(type_name);
        const type_idx = _cdb.getTypeIdx(_db, type_hash) orelse return false;

        const asset_obj = public.Asset.readSubObj(_cdb, _cdb.readObj(asset).?, .Object) orelse return false;
        return type_idx.eql(asset_obj.type_idx);
    }

    pub fn importAsset(
        db: cdb.DbId,
        prereq: cetech1.task.TaskID,
        dir: std.fs.Dir,
        folder: cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cdb.ObjId,
    ) !cetech1.task.TaskID {
        _ = reimport_to;
        const Task = struct {
            db: cdb.DbId,
            dir: std.fs.Dir,
            folder: cdb.ObjId,
            filename: []const u8,
            pub fn exec(self: *@This()) !void {
                var zone_ctx = profiler.ztracy.Zone(@src());
                defer zone_ctx.End();

                const allocator = tempalloc.api.create() catch undefined;
                defer tempalloc.api.destroy(allocator);

                var full_path_buf: [2048]u8 = undefined;
                const full_path = self.dir.realpath(self.filename, &full_path_buf) catch undefined;
                log.info("Importing cdb asset {s}", .{full_path});

                var asset_file = self.dir.openFile(self.filename, .{ .mode = .read_only }) catch |err| {
                    log.err("Could not import asset {}", .{err});
                    return;
                };

                defer asset_file.close();
                defer self.dir.close();

                var buffer: [4096]u8 = undefined;

                var rb = asset_file.reader(&buffer);
                const asset_reader = &rb.interface;

                const asset = readAssetFromReader(
                    asset_reader,
                    std.fs.path.stem(std.fs.path.stem(self.filename)),
                    self.folder,
                    ReadBlobFromFile,
                    allocator,
                ) catch |err| {
                    log.err("Could not import asset {}", .{err});
                    return;
                };

                _assetroot_fs.addAssetToRoot(asset) catch |err| {
                    log.err("Could not add asset to root {}", .{err});
                    return;
                };

                // Save current version to assedb.
                _assetroot_fs.markObjSaved(asset, _cdb.getVersion(asset));
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
            .{},
        );
    }

    pub fn exportAsset(
        db: cdb.DbId,
        root_path: []const u8,
        sub_path: []const u8,
        asset: cdb.ObjId,
    ) !cetech1.task.TaskID {
        const Task = struct {
            db: cdb.DbId,
            asset: cdb.ObjId,
            sub_path: []const u8,
            root_path: []const u8,
            pub fn exec(self: *@This()) !void {
                var zone_ctx = profiler.ztracy.Zone(@src());
                defer zone_ctx.End();

                const allocator = try tempalloc.api.create();
                defer tempalloc.api.destroy(allocator);

                const version = _cdb.getVersion(self.asset);

                var dir = std.fs.openDirAbsolute(self.root_path, .{}) catch undefined;
                defer dir.close();

                if (isAssetFolder(self.asset)) {
                    _assetroot_fs.saveFolderObj(allocator, self.asset, self.root_path) catch |err| {
                        log.err("Could not save folder asset {}", .{err});
                        return err;
                    };
                } else {
                    saveCdbObj(self.asset, self.root_path, self.sub_path, allocator) catch |err| {
                        log.err("Could not save asset {}", .{err});
                        return err;
                    };
                }
                _assetroot_fs.markObjSaved(self.asset, version);

                // TODO: temp shit
                const asset_uuid = getUuid(self.asset).?;
                if (!_assetroot_fs.analyzer.asset_uuid2path.contains(asset_uuid)) {
                    const path = try std.fs.path.join(_assetroot_fs.analyzer.allocator, &.{ self.root_path, self.sub_path });
                    try _assetroot_fs.analyzer.asset_uuid2path.put(_assetroot_fs.analyzer.allocator, asset_uuid, path);
                }
            }
        };

        return try task.api.schedule(
            cetech1.task.TaskID.none,
            Task{
                .db = db,
                .sub_path = try _str_intern.intern(sub_path),
                .asset = asset,
                .root_path = root_path,
            },
            .{},
        );
    }
});

fn isAssetNameValid(allocator: std.mem.Allocator, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) !bool {
    const set = try _cdb.getReferencerSet(allocator, folder);
    defer allocator.free(set);

    var name_set = cetech1.ArraySet([]const u8).init();
    defer name_set.deinit(allocator);

    if (!type_idx.eql(FolderTypeIdx)) {
        for (set) |obj| {
            if (!obj.type_idx.eql(AssetTypeIdx)) continue;

            const asset_obj = cetech1.assetdb.Asset.readSubObj(_cdb, _cdb.readObj(obj).?, .Object).?;
            if (asset_obj.type_idx.idx != type_idx.idx) continue;

            if (cetech1.assetdb.Asset.readStr(_cdb, _cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    } else {
        for (set) |obj| {
            if (!obj.type_idx.eql(AssetTypeIdx)) continue;

            if (cetech1.assetdb.Asset.readStr(_cdb, _cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    }

    return !name_set.contains(base_name);
}

var AssetTypeIdx: cdb.TypeIdx = undefined;
var FolderTypeIdx: cdb.TypeIdx = undefined;

var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {

        // Asset type is wrapper for asset object
        AssetTypeIdx = _cdb.addType(
            db,
            public.Asset.name,
            &.{
                .{ .prop_idx = public.Asset.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                .{ .prop_idx = public.Asset.propIdx(.Description), .name = "description", .type = cdb.PropType.STR },
                .{ .prop_idx = public.Asset.propIdx(.Folder), .name = "folder", .type = cdb.PropType.REFERENCE, .type_hash = public.Folder.type_hash },
                .{ .prop_idx = public.Asset.propIdx(.Tags), .name = "tags", .type = cdb.PropType.REFERENCE_SET, .type_hash = public.Tag.type_hash },
                .{ .prop_idx = public.Asset.propIdx(.Object), .name = "object", .type = cdb.PropType.SUBOBJECT },
            },
        ) catch unreachable;

        // Asset folder
        // TODO as regular asset
        FolderTypeIdx = _cdb.addType(
            db,
            public.Folder.name,
            &.{
                .{ .prop_idx = public.Folder.propIdx(.Color), .name = "color", .type = cdb.PropType.SUBOBJECT, .type_hash = cdb_types.Color4f.type_hash },
            },
        ) catch unreachable;

        // All assets is parent of this
        asset_root_type = _cdb.addType(
            db,
            AssetRoot.name,
            &.{
                .{ .prop_idx = AssetRoot.propIdx(.Assets), .name = "assets", .type = cdb.PropType.SUBOBJECT_SET },
            },
        ) catch unreachable;

        // Project
        _ = _cdb.addType(
            db,
            public.Project.name,
            &.{
                .{ .prop_idx = public.Project.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                .{ .prop_idx = public.Project.propIdx(.Organization), .name = "organization", .type = cdb.PropType.STR },
            },
        ) catch unreachable;

        const ct_asset_tag_type = _cdb.addType(
            db,
            public.Tag.name,
            &.{
                .{ .prop_idx = public.Tag.propIdx(.Name), .name = "name", .type = cdb.PropType.STR },
                .{ .prop_idx = public.Tag.propIdx(.Color), .name = "color", .type = cdb.PropType.SUBOBJECT, .type_hash = cdb_types.Color4f.type_hash },
            },
        ) catch unreachable;
        _ = ct_asset_tag_type;

        const ct_tags = _cdb.addType(
            db,
            public.Tags.name,
            &.{
                .{ .prop_idx = public.Tags.propIdx(.Tags), .name = "tags", .type = cdb.PropType.REFERENCE_SET, .type_hash = public.Tag.type_hash },
            },
        ) catch unreachable;
        _ = ct_tags;

        _ = cetech1.cdb_types.addBigType(_cdb, db, public.FooAsset.name, public.FooAsset.type_hash) catch unreachable;
        _ = cetech1.cdb_types.addBigType(_cdb, db, public.BarAsset.name, null) catch unreachable;
        _ = cetech1.cdb_types.addBigType(_cdb, db, public.BazAsset.name, null) catch unreachable;
    }
});

pub fn registerToApi() !void {
    try apidb.api.setZigApi(module_name, public.AssetDBAPI, &api);
    try apidb.api.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, true);
}

pub fn getDb() cdb.DbId {
    return _db;
}

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    _db = try cdb_private.api.createDb("AssetDB");

    _assetroot_fs = try AssetRootFS.init(allocator);

    _assetio_set = .init();
    _str_intern = cetech1.string.InternWithLock([]const u8).init(allocator);
    try _cdb.addOnObjIdDestroyed(_db, onObjidDestroyed);

    addAssetIO(&_cdb_asset_io_i);
}

pub fn deinit() void {
    removeAssetIO(&_cdb_asset_io_i);
    _assetio_set.deinit(_allocator);
    _assetroot_fs.deinit();
    _str_intern.deinit();
    _cdb.removeOnObjIdDestroyed(_db, onObjidDestroyed);
    cdb_private.api.destroyDb(_db);
}

fn isRootFolder(asset: cdb.ObjId) bool {
    const obj = getObjForAsset(asset) orelse return false;
    if (!obj.type_idx.eql(FolderTypeIdx)) return false;
    return public.Asset.readRef(_cdb, public.Asset.read(_cdb, asset).?, .Folder) == null;
}

fn isAssetObjTypeOf(asset: cdb.ObjId, type_idx: cdb.TypeIdx) bool {
    const obj = getObjForAsset(asset) orelse return false;
    return obj.type_idx.eql(type_idx);
}

fn isObjAssetObj(obj: cdb.ObjId) bool {
    const parent = _cdb.getParent(obj);
    if (parent.isEmpty()) return false;
    return parent.type_idx.eql(AssetTypeIdx);
}

fn getAssetForObj(obj: cdb.ObjId) ?cdb.ObjId {
    var it: cdb.ObjId = obj;

    while (!it.isEmpty()) {
        if (it.type_idx.eql(AssetTypeIdx)) {
            return it;
        }
        it = _cdb.getParent(it);
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
    return public.Asset.readSubObj(_cdb, _cdb.readObj(obj).?, .Object).?;
}

fn isProjectOpened() bool {
    return _assetroot_fs.isProjectOpened();
}

pub fn isObjModified(asset: cdb.ObjId) bool {
    return _assetroot_fs.isObjModified(asset);
}

pub fn isProjectModified() bool {
    return _assetroot_fs.isModified();
}

pub fn getTmpPath(path_buf: []u8) !?[]u8 {
    return _assetroot_fs.getTmpPath(path_buf);
}

pub fn addAssetIO(asset_io: *public.AssetIOI) void {
    _ = _assetio_set.add(_allocator, asset_io) catch |err| {
        log.err("Could not add AssetIO {}", .{err});
    };
}

pub fn removeAssetIO(asset_io: *public.AssetIOI) void {
    _ = _assetio_set.remove(asset_io);
}

pub fn findFirstAssetIOForImport(filename: []const u8, extension: []const u8) ?*public.AssetIOI {
    for (_assetio_set.unmanaged.keys()) |asset_io| {
        if (asset_io.canImport != null and asset_io.canImport.?(filename, extension)) return asset_io;
    }
    return null;
}

pub fn findFirstAssetIOForExport(db: cdb.DbId, asset: cdb.ObjId, filename: []const u8, extension: []const u8) ?*public.AssetIOI {
    for (_assetio_set.unmanaged.keys()) |asset_io| {
        if (asset_io.canExport != null and asset_io.canExport.?(db, asset, filename, extension)) return asset_io;
    }
    return null;
}

fn getRootFolder() cdb.ObjId {
    return _assetroot_fs.asset_root_folder;
}

pub fn createObjectWithUuid(type_idx: cdb.TypeIdx, with_uuid: uuid.Uuid) !cdb.ObjId {
    //log.debug("Creating new obj with UUID {}", .{with_uuid});
    const obj = try _cdb.createObject(_db, type_idx);
    try _assetroot_fs.mapUuidObjid(with_uuid, obj);
    return obj;
}

pub fn createEmptyObjectWithUuid(type_idx: cdb.TypeIdx, with_uuid: uuid.Uuid) !cdb.ObjId {
    //log.debug("Creating new obj with UUID {}", .{with_uuid});
    const obj = try _cdb.createEmptyObject(_db, type_idx);
    try _assetroot_fs.mapUuidObjid(with_uuid, obj);
    return obj;
}

fn getOrCreateUuid(obj: cdb.ObjId) !uuid.Uuid {
    // _get_or_create_lock.lock();
    // defer _get_or_create_lock.unlock();

    var obj_uuid = getUuid(obj);
    if (obj_uuid != null) {
        return obj_uuid.?;
    }
    obj_uuid = uuid_private.newUUID7();
    try _assetroot_fs.mapUuidObjid(obj_uuid.?, obj);
    return obj_uuid.?;
}

fn createObject(type_idx: cdb.TypeIdx) !cdb.ObjId {
    const obj = try _cdb.createObject(_db, type_idx);
    _ = try getOrCreateUuid(obj);
    return obj;
}

fn createEmptyObject(type_idx: cdb.TypeIdx) !cdb.ObjId {
    const obj = try _cdb.createEmptyObject(_db, type_idx);
    _ = try getOrCreateUuid(obj);
    return obj;
}

fn validateVersion(version: []const u8) !void {
    const v = try std.SemanticVersion.parse(version);
    if (v.order(ASSET_CURRENT_VERSION) == .lt) {
        return error.NOT_COMPATIBLE_VERSION;
    }
}

fn deleteAsset(asset: cdb.ObjId) anyerror!void {
    try _assetroot_fs.deleteAsset(asset);
}

fn deleteFolder(folder: cdb.ObjId) anyerror!void {
    try _assetroot_fs.deleteFolder(folder);
}

fn isToDeleted(asset_or_folder: cdb.ObjId) bool {
    return _assetroot_fs.isToDeleted(asset_or_folder);
}

fn reviveDeleted(asset_or_folder: cdb.ObjId) void {
    return _assetroot_fs.reviveDeleted(asset_or_folder);
}

fn loadProject(allocator: std.mem.Allocator, db: cdb.DbId, asset_root_path: []const u8, asset_root_folder: cdb.ObjId) !cdb.ObjId {
    _ = db; // autofix
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var dir = try std.fs.cwd().openDir(asset_root_path, .{});

    var asset_file = dir.openFile(PROJECT_FILENAME, .{ .mode = .read_only }) catch |err| {
        log.err("Could not load {s} {}", .{ PROJECT_FILENAME, err });
        return err;
    };
    defer asset_file.close();

    var buffer: [4096]u8 = undefined;
    var asset_reader = asset_file.reader(&buffer);
    const asset_r = &asset_reader.interface;

    const asset = readAssetFromReader(
        asset_r,
        "project",
        asset_root_folder,
        ReadBlobFromFile,
        allocator,
    ) catch |err| {
        log.err("Could not import asset {}", .{err});
        return err;
    };

    _assetroot_fs.addAssetToRoot(asset) catch |err| {
        log.err("Could not add asset to root {}", .{err});
        return err;
    };

    // Save current version to assedb.
    _assetroot_fs.markObjSaved(asset, _cdb.getVersion(asset));

    return asset;
}

fn getOrCreateFolder(
    allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    dir: std.fs.Dir,
    name: ?[]const u8,
    parent_folder: ?cdb.ObjId,
) !cdb.ObjId {
    var folder_asset: cdb.ObjId = undefined;
    const root_folder = parent_folder == null;
    const exist_marker = if (root_folder) existRootFolderMarker(dir) else existFolderMarker(root_dir, name.?);

    if (exist_marker) {
        var asset_file = try dir.openFile(FOLDER_FILENAME, .{ .mode = .read_only });
        defer asset_file.close();

        var buffer: [128]u8 = undefined;
        var asset_reader = asset_file.reader(&buffer);
        const asset_r = &asset_reader.interface;

        folder_asset = try readAssetFromReader(
            asset_r,
            name orelse "",
            parent_folder orelse .{},
            ReadBlobFromFile,
            allocator,
        );

        _assetroot_fs.markObjSaved(folder_asset, _cdb.getVersion(folder_asset));
    } else {
        const folder_obj = try public.Folder.createObject(_cdb, _db);

        folder_asset = try public.Asset.createObject(_cdb, _db);
        const asset_w = _cdb.writeObj(folder_asset).?;
        const folder_obj_w = _cdb.writeObj(folder_obj).?;

        if (name) |n| {
            var buffer: [128]u8 = undefined;
            const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{n});
            try public.Asset.setStr(_cdb, asset_w, .Name, str);
        }

        if (parent_folder) |folder| {
            try public.Asset.setRef(_cdb, asset_w, .Folder, folder);
        }

        try public.Asset.setSubObj(_cdb, asset_w, .Object, folder_obj_w);

        try _cdb.writeCommit(folder_obj_w);
        try _cdb.writeCommit(asset_w);

        try _assetroot_fs.saveFolderObj(allocator, folder_asset, _assetroot_fs.asset_root_path.?);
    }

    return folder_asset;
}

fn openAssetRootFolder(asset_root_path: []const u8, allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();
    return _assetroot_fs.openAssetRootFolder(asset_root_path, allocator);
}

fn getObjId(obj_uuid: uuid.Uuid) ?cdb.ObjId {
    return _assetroot_fs.getObjId(obj_uuid);
}

fn getUuid(obj: cdb.ObjId) ?uuid.Uuid {
    return _assetroot_fs.getUuid(obj);
}

fn setAssetNameAndFolder(asset_w: *cdb.Obj, name: []const u8, description: ?[]const u8, asset_folder: cdb.ObjId) !void {
    var buffer: [128]u8 = undefined;

    if (name.len != 0) {
        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{name});
        try public.Asset.setStr(_cdb, asset_w, .Name, str);
    }

    if (description) |desc| {
        const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{desc});
        try public.Asset.setStr(_cdb, asset_w, .Description, str);
    }

    if (!asset_folder.isEmpty()) {
        try public.Asset.setRef(_cdb, asset_w, .Folder, getObjForAsset(asset_folder).?);
    }
}

fn createAsset(asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId {
    const asset = createObject(AssetTypeIdx) catch return null;
    const asset_w = _cdb.writeObj(asset).?;

    if (asset_obj != null) {
        const asset_obj_w = _cdb.writeObj(asset_obj.?).?;
        public.Asset.setSubObj(_cdb, asset_w, .Object, asset_obj_w) catch return null;

        _cdb.writeCommit(asset_obj_w) catch return null;
    }

    setAssetNameAndFolder(asset_w, asset_name, null, asset_folder) catch return null;

    _cdb.writeCommit(asset_w) catch return null;

    _assetroot_fs.addAssetToRoot(asset) catch return null;
    return asset;
}

pub fn saveAssetAndWait(allocator: std.mem.Allocator, asset: cdb.ObjId) !void {
    if (asset.type_idx.eql(AssetTypeIdx)) {
        const export_task = try _assetroot_fs.saveAsset(allocator, _assetroot_fs.asset_root_path.?, asset);
        task.api.wait(export_task);
    } else if (asset.type_idx.eql(FolderTypeIdx)) {
        try _assetroot_fs.saveFolderObj(allocator, getAssetForObj(asset).?, _assetroot_fs.asset_root_path.?);
    }
}

pub fn saveAll(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _assetroot_fs.saveAll(allocator);
}

pub fn saveAllModifiedAssets(allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _assetroot_fs.saveAllModifiedAssets(allocator);
}

const MAX_FOLDER_DEPTH = 16;
fn getPathForFolder(buff: []u8, from_folder: cdb.ObjId) ![]u8 {
    var fbs = std.io.fixedBufferStream(buff);
    try fbs.seekTo(try fbs.getEndPos());

    const root_folder_name = public.Asset.readStr(_cdb, _cdb.readObj(getAssetForObj(from_folder).?).?, .Name);

    if (root_folder_name != null) {
        var first = true;
        var folder_it: ?cdb.ObjId = from_folder;

        try writeLeft(&fbs, ".json");
        try writeLeft(&fbs, public.Folder.name);
        try writeLeft(&fbs, ".");

        while (folder_it) |folder| {
            const folder_r = _cdb.readObj(getAssetForObj(folder).?).?;

            folder_it = public.Asset.readRef(_cdb, folder_r, .Folder) orelse break;
            const folder_name = public.Asset.readStr(_cdb, folder_r, .Name) orelse continue;

            try writeLeft(&fbs, &.{std.fs.path.sep});
            try writeLeft(&fbs, folder_name);

            first = false;
        }
    } else {
        try writeLeft(&fbs, FOLDER_FILENAME);
    }

    const begin = try fbs.getPos();
    const end = try fbs.getEndPos();
    return buff[begin..end];
}

pub fn getFilePathForAsset(buff: []u8, asset: cdb.ObjId) ![]u8 {
    const asset_r = _cdb.readObj(asset);
    const asset_obj = public.Asset.readSubObj(_cdb, asset_r.?, .Object).?;

    // append asset type extension
    return getPathForAsset(buff, asset, _cdb.getTypeName(_db, asset_obj.type_idx).?);
}

fn writeLeft(fbs: *std.io.FixedBufferStream([]u8), data: []const u8) !void {
    try fbs.seekTo(try fbs.getPos() - data.len);
    const writen = try fbs.write(data);
    try fbs.seekTo(try fbs.getPos() - writen);
}

fn getPathForAsset(buff: []u8, asset: cdb.ObjId, extension: []const u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buff);
    try fbs.seekTo(try fbs.getEndPos());

    try writeLeft(&fbs, extension);
    try writeLeft(&fbs, ".");

    // add asset name
    const asset_r = _cdb.readObj(asset);
    if (public.Asset.readStr(_cdb, asset_r.?, .Name)) |asset_name| {
        try writeLeft(&fbs, asset_name);
    }

    // make sub path
    var folder_it = public.Asset.readRef(_cdb, asset_r.?, .Folder);
    while (folder_it) |folder| {
        const folder_asset_r = _cdb.readObj(getAssetForObj(folder).?).?;
        folder_it = public.Asset.readRef(_cdb, folder_asset_r, .Folder) orelse break;

        const folder_name = public.Asset.readStr(_cdb, folder_asset_r, .Name) orelse continue;

        try writeLeft(&fbs, &.{std.fs.path.sep});
        try writeLeft(&fbs, folder_name);
    }

    const begin = try fbs.getPos();
    const end = try fbs.getEndPos();
    return buff[begin..end];
}

fn WriteBlobToFile(
    blob: []const u8,
    asset: cdb.ObjId,
    obj_uuid: uuid.Uuid,
    prop_hash: cetech1.StrId32,
    root_path: []const u8,
    allocator: std.mem.Allocator,
) anyerror!void {
    _ = allocator; // autofix
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var buff: [128]u8 = undefined;
    const blob_dir_path = try getPathForAsset(&buff, asset, BLOB_EXTENSION);

    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    //create blob dir
    try root_dir.makePath(blob_dir_path);

    var blob_file_name_buf: [1024]u8 = undefined;
    const blob_file_name = try std.fmt.bufPrint(&blob_file_name_buf, "{x}{x}", .{ cetech1.strId32(&obj_uuid.bytes).id, prop_hash.id });

    var blob_dir = try root_dir.openDir(blob_dir_path, .{});
    defer blob_dir.close();
    try blob_dir.writeFile(.{ .sub_path = blob_file_name, .data = blob });
}

fn ReadBlobFromFile(
    asset: cdb.ObjId,
    obj_uuid: uuid.Uuid,
    prop_hash: cetech1.StrId32,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var buff: [128]u8 = undefined;
    const blob_dir_path = try getPathForAsset(&buff, asset, BLOB_EXTENSION);

    var root_dir = try std.fs.cwd().openDir(_assetroot_fs.asset_root_path.?, .{});
    defer root_dir.close();

    var blob_file_name_buf: [1024]u8 = undefined;
    const blob_file_name = try std.fmt.bufPrint(&blob_file_name_buf, "{x}{x}", .{ cetech1.strId32(&obj_uuid.bytes).id, prop_hash.id });

    var blob_dir = try root_dir.openDir(blob_dir_path, .{});
    defer blob_dir.close();

    var blob_file = try blob_dir.openFile(blob_file_name, .{});
    defer blob_file.close();
    const size = try blob_file.getEndPos();

    const blob = try allocator.alloc(u8, size);
    _ = try blob_file.readAll(blob);
    return blob;
}

fn saveCdbObj(obj: cdb.ObjId, root_path: []const u8, sub_path: []const u8, allocator: std.mem.Allocator) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    const dir_path = std.fs.path.dirname(sub_path);
    if (dir_path != null) {
        try root_dir.makePath(dir_path.?);
    }

    var obj_file = try root_dir.createFile(sub_path, .{});
    defer obj_file.close();

    var buffer: [4096]u8 = undefined;

    var bw = obj_file.writer(&buffer);
    const writer = &bw.interface;
    defer writer.flush() catch undefined;

    //const folder = public.Asset.readRef(_cdb, _db.readObj(obj).?, .Folder).?;
    try writeCdbObjJson(
        obj,
        writer,
        obj,
        WriteBlobToFile,
        root_path,
        allocator,
    );
}

fn existRootFolderMarker(root_folder: std.fs.Dir) bool {
    var buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, FOLDER_FILENAME, .{}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

fn existRootProjectAsset(root_folder: std.fs.Dir) bool {
    var buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, PROJECT_FILENAME, .{}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

fn existFolderMarker(root_folder: std.fs.Dir, dir_name: []const u8) bool {
    var buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/" ++ FOLDER_FILENAME, .{dir_name}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

pub fn writeCdbObjJson(
    obj: cdb.ObjId,
    writer: *std.io.Writer,
    asset: cdb.ObjId,
    write_blob: WriteBlobFn,
    root_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var ws = std.json.Stringify{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
    try ws.beginObject();

    const obj_r = _cdb.readObj(obj).?;
    var asset_obj: ?cdb.ObjId = null;

    try ws.objectField(JSON_ASSET_VERSION);
    try ws.print("\"{s}\"", .{ASSET_CURRENT_VERSION_STR});

    if (obj.type_idx.eql(AssetTypeIdx)) {
        asset_obj = public.Asset.readSubObj(_cdb, obj_r, .Object);

        try ws.objectField(JSON_ASSET_UUID_TOKEN);
        try ws.print("\"{f}\"", .{try getOrCreateUuid(obj)});

        if (public.Asset.readStr(_cdb, obj_r, .Description)) |desc| {
            try ws.objectField(JSON_DESCRIPTION_TOKEN);
            try ws.print("\"{s}\"", .{desc});
        }

        // TAGS
        const added = public.Asset.readRefSetAdded(_cdb, obj_r, .Tags);
        if (added.len != 0) {
            try ws.objectField(JSON_TAGS_TOKEN);
            try ws.beginArray();
            for (added) |item| {
                try ws.print("\"{s}:{f}\"", .{ _cdb.getTypeName(_db, item.type_idx).?, try getOrCreateUuid(item) });
            }
            try ws.endArray();
        }
    } else {
        asset_obj = obj;
    }

    try writeCdbObjJsonBody(
        asset_obj.?,
        &ws,
        asset,
        write_blob,
        root_path,
        allocator,
    );

    try ws.endObject();
}

fn writeCdbObjJsonBody(
    obj: cdb.ObjId,
    writer: *std.json.Stringify,
    asset: cdb.ObjId,
    write_blob: WriteBlobFn,
    root_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    const obj_r = _cdb.readObj(obj).?;
    const type_name = _cdb.getTypeName(_db, obj.type_idx).?;

    // Type name
    try writer.objectField(JSON_TYPE_NAME_TOKEN);
    try writer.print("\"{s}\"", .{type_name});

    // UUID
    try writer.objectField(JSON_UUID_TOKEN);
    try writer.print("\"{f}\"", .{try getOrCreateUuid(obj)});

    const prototype_id = _cdb.getPrototype(obj_r);
    if (!prototype_id.isEmpty()) {
        try writer.objectField(JSON_PROTOTYPE_UUID);
        try writer.print("\"{f}\"", .{try getOrCreateUuid(prototype_id)});
    }

    const prop_defs = _cdb.getTypePropDef(_db, obj.type_idx).?;
    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);
        const has_prototype = !_cdb.getPrototype(obj_r).isEmpty();
        const property_overided = _cdb.isPropertyOverrided(obj_r, prop_idx);
        switch (prop_def.type) {
            cdb.PropType.BOOL => {
                const value = _cdb.readValue(bool, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     const default_value = _cdb.readValue(bool, _cdb.readObj(default).?, prop_idx);
                //     if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == false) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.U64 => {
                const value = _cdb.readValue(u64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     const default_value = _cdb.readValue(u64, _cdb.readObj(default).?, prop_idx);
                //     if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.I64 => {
                const value = _cdb.readValue(i64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     const default_value = _cdb.readValue(i64, _cdb.readObj(default).?, prop_idx);
                //     if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.U32 => {
                const value = _cdb.readValue(u32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     const default_value = _cdb.readValue(u32, _cdb.readObj(default).?, prop_idx);
                //     if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.I32 => {
                const value = _cdb.readValue(i32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                // const default_value = _cdb.readValue(i32, _cdb.readObj(default).?, prop_idx);
                // if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.F64 => {
                const value = _cdb.readValue(f64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     const default_value = _cdb.readValue(f64, _cdb.readObj(default).?, prop_idx);
                //     if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.F32 => {
                const value = _cdb.readValue(f32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     const default_value = _cdb.readValue(f32, _cdb.readObj(default).?, prop_idx);
                //     if (value == default_value) continue;
                // } else {
                if (!has_prototype and value == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cdb.PropType.STR => {
                const str = _cdb.readStr(obj_r, prop_idx);
                if (str == null) continue;
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and str.?.len == 0) continue;

                // if (_cdb.getDefaultObject(_db, obj.type_idx)) |default| {
                //     if (_cdb.readStr(_cdb.readObj(default).?, prop_idx)) |default_value| {
                //         if (std.mem.eql(u8, str.?, default_value)) continue;
                //     }
                // } else {
                if (!has_prototype and str.?.len == 0) continue;
                // }

                try writer.objectField(prop_def.name);
                try writer.print("\"{s}\"", .{str.?});
            },
            cdb.PropType.BLOB => {
                const blob = _cdb.readBlob(obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (blob.len == 0) continue;

                var obj_uuid = try getOrCreateUuid(obj);
                try write_blob(blob, asset, obj_uuid, cetech1.strId32(prop_def.name), root_path, allocator);

                try writer.objectField(prop_def.name);
                try writer.print("\"{x}{x}\"", .{ cetech1.strId32(&obj_uuid.bytes).id, cetech1.strId32(prop_def.name).id });
            },
            cdb.PropType.SUBOBJECT => {
                const subobj = _cdb.readSubObj(obj_r, prop_idx);
                if (has_prototype and !_cdb.isPropertyOverrided(obj_r, prop_idx)) continue;
                if (subobj != null) {
                    try writer.objectField(prop_def.name);

                    try writer.beginObject();
                    try writeCdbObjJsonBody(
                        subobj.?,
                        writer,
                        asset,
                        write_blob,
                        root_path,
                        allocator,
                    );
                    try writer.endObject();
                }
            },
            cdb.PropType.REFERENCE => {
                const ref_obj = _cdb.readRef(obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (ref_obj != null) {
                    try writer.objectField(prop_def.name);
                    try writer.print("\"{s}:{f}\"", .{ _cdb.getTypeName(_db, ref_obj.?.type_idx).?, try getOrCreateUuid(ref_obj.?) });
                }
            },
            cdb.PropType.SUBOBJECT_SET => {
                const added = _cdb.readSubObjSetAdded(obj_r, @truncate(prop_idx));

                if (prototype_id.isEmpty()) {
                    if (added.len == 0) continue;

                    try writer.objectField(prop_def.name);
                    try writer.beginArray();
                    for (added) |item| {
                        try writer.beginObject();
                        try writeCdbObjJsonBody(item, writer, asset, write_blob, root_path, allocator);
                        try writer.endObject();
                    }
                    try writer.endArray();
                } else {
                    const deleted_items = _cdb.readSubObjSetRemoved(obj_r, prop_idx);

                    var deleted_set = cetech1.ArraySet(cdb.ObjId).init();
                    defer deleted_set.deinit(allocator);

                    for (deleted_items) |item| {
                        _ = try deleted_set.add(allocator, item);
                    }

                    var added_set = cetech1.ArraySet(cdb.ObjId).init();
                    var inisiate_set = cetech1.ArraySet(cdb.ObjId).init();
                    defer added_set.deinit(allocator);
                    defer inisiate_set.deinit(allocator);

                    for (added) |item| {
                        const prototype_obj = _cdb.getPrototype(_cdb.readObj(item).?);

                        if (deleted_set.contains(prototype_obj)) {
                            _ = try inisiate_set.add(allocator, item);
                            _ = deleted_set.remove(prototype_obj);
                        } else {
                            _ = try added_set.add(allocator, item);
                        }
                    }

                    // new added
                    if (added_set.cardinality() != 0) {
                        try writer.objectField(prop_def.name);
                        try writer.beginArray();
                        for (added_set.unmanaged.keys()) |item| {
                            try writer.beginObject();
                            try writeCdbObjJsonBody(item, writer, asset, write_blob, root_path, allocator);
                            try writer.endObject();
                        }
                        try writer.endArray();
                    }

                    // inisiated
                    if (inisiate_set.cardinality() != 0) {
                        var buff: [128]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_INSTANTIATE_POSTFIX, .{prop_def.name});

                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (inisiate_set.unmanaged.keys()) |item| {
                            try writer.beginObject();
                            try writeCdbObjJsonBody(item, writer, asset, write_blob, root_path, allocator);
                            try writer.endObject();
                        }
                        try writer.endArray();
                    }

                    // removed
                    if (deleted_set.cardinality() != 0) {
                        var buff: [128]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (deleted_set.unmanaged.keys()) |item| {
                            try writer.print("\"{s}:{f}\"", .{ type_name, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }
                }
            },
            cdb.PropType.REFERENCE_SET => {
                const added = _cdb.readRefSetAdded(obj_r, @truncate(prop_idx));
                if (prototype_id.isEmpty()) {
                    if (added.len == 0) continue;

                    try writer.objectField(prop_def.name);
                    try writer.beginArray();
                    for (added) |item| {
                        try writer.print("\"{s}:{f}\"", .{ _cdb.getTypeName(_db, item.type_idx).?, try getOrCreateUuid(item) });
                    }
                    try writer.endArray();
                } else {
                    const deleted_items = _cdb.readSubObjSetRemoved(obj_r, prop_idx);

                    var deleted_set = cetech1.ArraySet(cdb.ObjId).init();
                    defer deleted_set.deinit(allocator);

                    for (deleted_items) |item| {
                        _ = try deleted_set.add(allocator, item);
                    }

                    var added_set = cetech1.ArraySet(cdb.ObjId).init();
                    defer added_set.deinit(allocator);

                    for (added) |item| {
                        const prototype_obj = _cdb.getPrototype(_cdb.readObj(item).?);

                        if (deleted_set.contains(prototype_obj)) {
                            _ = deleted_set.remove(prototype_obj);
                        } else {
                            _ = try added_set.add(allocator, item);
                        }
                    }

                    // new added
                    if (added_set.cardinality() != 0) {
                        try writer.objectField(prop_def.name);
                        try writer.beginArray();
                        for (added_set.unmanaged.keys()) |item| {
                            try writer.print("\"{s}:{f}\"", .{ _cdb.getTypeName(_db, item.type_idx).?, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }

                    // removed
                    if (deleted_set.cardinality() != 0) {
                        var buff: [128]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (deleted_set.unmanaged.keys()) |item| {
                            try writer.print("\"{s}:{f}\"", .{ _cdb.getTypeName(_db, item.type_idx).?, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }

                    // var deleted_items = _cdb.readRefSetRemoved(obj_r, prop_idx, tmp_allocator);
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
    reader: *std.io.Reader,
    asset_name: []const u8,
    asset_folder: cdb.ObjId,
    read_blob: ReadBlobFn,
    allocator: std.mem.Allocator,
) !cdb.ObjId {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var json_reader = std.json.Reader.init(allocator, reader);
    defer json_reader.deinit();
    var parsed = try std.json.parseFromTokenSource(std.json.Value, allocator, &json_reader, .{ .parse_numbers = false });
    defer parsed.deinit();

    const version = parsed.value.object.get(JSON_ASSET_VERSION).?;
    try validateVersion(version.string);

    const asset_uuid_str = parsed.value.object.get(JSON_ASSET_UUID_TOKEN).?;
    const asset_uuid = uuid_private.api.fromStr(asset_uuid_str.string).?;

    const asset = try getOrCreate(asset_uuid, AssetTypeIdx);

    var desc: ?[]const u8 = null;
    const desc_value = parsed.value.object.get(JSON_DESCRIPTION_TOKEN);
    if (desc_value) |asset_desc| {
        desc = asset_desc.string;
    }

    {
        const asset_w = _cdb.writeObj(asset).?;
        try setAssetNameAndFolder(asset_w, asset_name, desc, asset_folder);
        try _cdb.writeCommit(asset_w);
    }

    const asset_w = _cdb.writeObj(asset).?;

    if (parsed.value.object.get(JSON_TAGS_TOKEN)) |tags| {
        for (tags.array.items) |tag| {
            var ref_link = std.mem.splitAny(u8, tag.string, ":");
            const ref_type = cetech1.strId32(ref_link.first());
            const ref_type_idx = _cdb.getTypeIdx(_db, ref_type).?;
            const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;

            const ref_obj = try getOrCreate(ref_uuid, ref_type_idx);
            try public.Asset.addRefToSet(_cdb, asset_w, .Tags, &.{ref_obj});
        }
    }

    const asset_obj = try readCdbObjFromJsonValue(parsed.value, asset, read_blob, allocator);

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    try public.Asset.setSubObj(_cdb, asset_w, .Object, asset_obj_w);
    try _cdb.writeCommit(asset_obj_w);
    try _cdb.writeCommit(asset_w);

    return asset;
}

fn readObjFromJson(
    comptime Reader: type,
    reader: Reader,
    read_blob: ReadBlobFn,
    allocator: std.mem.Allocator,
) !cdb.ObjId {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    var json_reader = std.json.reader(allocator, reader);
    defer json_reader.deinit();
    var parsed = try std.json.parseFromTokenSource(std.json.Value, allocator, &json_reader, .{ .parse_numbers = false });
    defer parsed.deinit();
    const obj = try readCdbObjFromJsonValue(parsed.value, .{}, read_blob, allocator);
    return obj;
}

fn getOrCreate(obj_uuid: uuid.Uuid, type_idx: cdb.TypeIdx) !cdb.ObjId {
    // _get_or_create_lock.lock();
    // defer _get_or_create_lock.unlock();

    var obj = getObjId(obj_uuid);
    if (obj == null) {
        obj = try createEmptyObjectWithUuid(type_idx, obj_uuid);
    }
    return obj.?;
}

fn createObjectFromPrototypeLocked(prototype_uuid: uuid.Uuid, type_idx: cdb.TypeIdx) !cdb.ObjId {
    const prototype_obj = try getOrCreate(prototype_uuid, type_idx);

    // _get_or_create_lock.lock();
    // defer _get_or_create_lock.unlock();
    return try _cdb.createObjectFromPrototype(prototype_obj);
}

fn readCdbObjFromJsonValue(parsed: std.json.Value, asset: cdb.ObjId, read_blob: ReadBlobFn, allocator: std.mem.Allocator) !cdb.ObjId {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    const obj_uuid_str = parsed.object.get(JSON_UUID_TOKEN).?;
    const obj_uuid = uuid_private.api.fromStr(obj_uuid_str.string).?;
    const obj_type = parsed.object.get(JSON_TYPE_NAME_TOKEN).?;
    const obj_type_hash = cetech1.strId32(obj_type.string);
    const obj_type_idx = _cdb.getTypeIdx(_db, obj_type_hash).?;

    const prototype_uuid = parsed.object.get(JSON_PROTOTYPE_UUID);
    var obj: ?cdb.ObjId = null;
    if (prototype_uuid == null) {
        obj = try createEmptyObject(obj_type_idx);
    } else {
        obj = try createObjectFromPrototypeLocked(uuid_private.fromStr(prototype_uuid.?.string).?, obj_type_idx);
    }

    const obj_w = _cdb.writeObj(obj.?).?;

    const prop_defs = _cdb.getTypePropDef(_db, obj_type_idx).?;

    const keys = parsed.object.keys();
    for (keys) |k| {
        // Skip private fields
        if (std.mem.startsWith(u8, k, "__")) continue;
        if (std.mem.endsWith(u8, k, JSON_REMOVED_POSTFIX)) continue;
        if (std.mem.endsWith(u8, k, JSON_INSTANTIATE_POSTFIX)) continue;

        const value = parsed.object.get(k).?;

        const prop_idx = _cdb.getTypePropDefIdx(_db, obj_type_idx, k) orelse continue;
        const prop_def = prop_defs[prop_idx];

        switch (prop_def.type) {
            cdb.PropType.BOOL => {
                _cdb.setValue(bool, obj_w, prop_idx, value.bool);
            },
            cdb.PropType.U64 => {
                _cdb.setValue(u64, obj_w, prop_idx, try std.fmt.parseInt(u64, value.number_string, 10));
            },
            cdb.PropType.I64 => {
                _cdb.setValue(i64, obj_w, prop_idx, try std.fmt.parseInt(i64, value.number_string, 10));
            },
            cdb.PropType.U32 => {
                _cdb.setValue(u32, obj_w, prop_idx, try std.fmt.parseInt(u32, value.number_string, 10));
            },
            cdb.PropType.I32 => {
                _cdb.setValue(i32, obj_w, prop_idx, try std.fmt.parseInt(i32, value.number_string, 10));
            },
            cdb.PropType.F64 => {
                _cdb.setValue(f64, obj_w, prop_idx, try std.fmt.parseFloat(f64, value.number_string));
            },
            cdb.PropType.F32 => {
                _cdb.setValue(f32, obj_w, prop_idx, try std.fmt.parseFloat(f32, value.number_string));
            },
            cdb.PropType.STR => {
                var buffer: [128]u8 = undefined;
                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{value.string});
                try _cdb.setStr(obj_w, prop_idx, str);
            },
            cdb.PropType.BLOB => {
                const blob = try read_blob(asset, obj_uuid, .fromStr(prop_def.name), allocator);
                defer allocator.free(blob);
                const true_blob = try _cdb.createBlob(obj_w, prop_idx, blob.len);
                @memcpy(true_blob.?, blob);
            },
            cdb.PropType.SUBOBJECT => {
                const subobj = try readCdbObjFromJsonValue(value, asset, read_blob, allocator);

                const subobj_w = _cdb.writeObj(subobj).?;
                try _cdb.setSubObj(obj_w, prop_idx, subobj_w);
                try _cdb.writeCommit(subobj_w);
            },
            cdb.PropType.REFERENCE => {
                var ref_link = std.mem.splitAny(u8, value.string, ":");
                const ref_type = cetech1.strId32(ref_link.first());
                const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;

                const ref_obj = try getOrCreate(ref_uuid, _cdb.getTypeIdx(_db, ref_type).?);

                try _cdb.setRef(obj_w, prop_idx, ref_obj);
            },
            cdb.PropType.SUBOBJECT_SET => {
                for (value.array.items) |subobj_item| {
                    const subobj = try readCdbObjFromJsonValue(subobj_item, asset, read_blob, allocator);

                    const subobj_w = _cdb.writeObj(subobj).?;
                    try _cdb.addSubObjToSet(obj_w, prop_idx, &.{subobj_w});
                    try _cdb.writeCommit(subobj_w);
                }
            },
            cdb.PropType.REFERENCE_SET => {
                for (value.array.items) |ref| {
                    var ref_link = std.mem.splitAny(u8, ref.string, ":");
                    const ref_type = cetech1.strId32(ref_link.first());
                    const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;

                    const ref_obj = try getOrCreate(ref_uuid, _cdb.getTypeIdx(_db, ref_type).?);
                    try _cdb.addRefToSet(obj_w, prop_idx, &.{ref_obj});
                }

                if (prototype_uuid != null) {
                    var buff: [128]u8 = undefined;
                    const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});

                    const removed_fiedl = parsed.object.get(field_name);
                    if (removed_fiedl != null) {
                        for (removed_fiedl.?.array.items) |ref| {
                            var ref_link = std.mem.splitAny(u8, ref.string, ":");
                            const ref_type = cetech1.strId32(ref_link.first());
                            const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;

                            const ref_obj = try getOrCreate(ref_uuid, _cdb.getTypeIdx(_db, ref_type).?);
                            try _cdb.removeFromRefSet(obj_w, prop_idx, ref_obj);
                        }
                    }
                }
            },
            else => continue,
        }
    }

    for (prop_defs, 0..) |prop_def, prop_idx| {
        switch (prop_def.type) {
            cdb.PropType.REFERENCE_SET, cdb.PropType.SUBOBJECT_SET => {
                if (prototype_uuid != null) {
                    var buff: [128]u8 = undefined;
                    var field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_INSTANTIATE_POSTFIX, .{prop_def.name});

                    if (prop_def.type == .SUBOBJECT_SET) {
                        const inisiated = parsed.object.get(field_name);
                        if (inisiated != null) {
                            for (inisiated.?.array.items) |subobj_item| {
                                const subobj = try readCdbObjFromJsonValue(subobj_item, asset, read_blob, allocator);
                                const subobj_w = _cdb.writeObj(subobj).?;
                                try _cdb.addSubObjToSet(obj_w, @truncate(prop_idx), &.{subobj_w});

                                const proto_w = _cdb.writeObj(_cdb.getPrototype(subobj_w)).?;
                                try _cdb.removeFromSubObjSet(obj_w, @truncate(prop_idx), @ptrCast(proto_w));

                                try _cdb.writeCommit(proto_w);
                                try _cdb.writeCommit(subobj_w);
                            }
                        }
                    }

                    field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                    const removed = parsed.object.get(field_name);
                    if (removed != null) {
                        for (removed.?.array.items) |ref| {
                            var ref_link = std.mem.splitAny(u8, ref.string, ":");
                            const ref_type = cetech1.strId32(ref_link.first());
                            const ref_uuid = uuid_private.api.fromStr(ref_link.next().?).?;

                            const ref_obj = try getOrCreate(ref_uuid, _cdb.getTypeIdx(_db, ref_type).?);

                            if (prop_def.type == .REFERENCE_SET) {
                                try _cdb.removeFromRefSet(obj_w, @truncate(prop_idx), ref_obj);
                            } else {
                                const ref_w = _cdb.writeObj(ref_obj).?;
                                try _cdb.removeFromSubObjSet(obj_w, @truncate(prop_idx), ref_w);
                                try _cdb.writeCommit(ref_w);
                            }
                        }
                    }
                }
            },
            else => continue,
        }
    }

    const existed_object = getObjId(obj_uuid);

    if (existed_object == null) {
        try _cdb.writeCommit(obj_w);
        try _assetroot_fs.mapUuidObjid(obj_uuid, obj.?);
        //log.debug("Creating new obj {s}:{s}.", .{ obj_type.string, obj_uuid_str.string });
    } else {
        try _cdb.retargetWrite(obj_w, existed_object.?);
        try _cdb.writeCommit(obj_w);
        _cdb.destroyObject(obj.?);
        log.debug("Retargeting obj {s}:{s}.", .{ obj_type.string, obj_uuid_str.string });
    }

    return existed_object orelse obj.?;
}

fn createNewFolder(db: cdb.DbId, parent_folder: cdb.ObjId, name: [:0]const u8) !cdb.ObjId {
    std.debug.assert(parent_folder.type_idx.eql(AssetTypeIdx));

    const new_folder_asset = try cetech1.assetdb.Asset.createObject(_cdb, db);

    const new_folder = try cetech1.assetdb.Folder.createObject(_cdb, db);
    const new_folder_w = _cdb.writeObj(new_folder).?;
    const new_folder_asset_w = _cdb.writeObj(new_folder_asset).?;

    try cetech1.assetdb.Asset.setSubObj(_cdb, new_folder_asset_w, .Object, new_folder_w);
    try cetech1.assetdb.Asset.setStr(_cdb, new_folder_asset_w, .Name, name);
    try cetech1.assetdb.Asset.setRef(_cdb, new_folder_asset_w, .Folder, getObjForAsset(parent_folder).?);

    try _cdb.writeCommit(new_folder_w);
    try _cdb.writeCommit(new_folder_asset_w);

    try _assetroot_fs.addAssetToRoot(new_folder_asset);

    return new_folder;
}

fn saveAsAllAssets(allocator: std.mem.Allocator, path: []const u8) !void {
    var zone_ctx = profiler.ztracy.Zone(@src());
    defer zone_ctx.End();

    try _assetroot_fs.saveAsAllAssets(allocator, path);
}

fn onObjidDestroyed(db: cdb.DbId, objects: []cdb.ObjId) void {
    _assetroot_fs.uuid2objid_lock.lock();
    defer _assetroot_fs.uuid2objid_lock.unlock();

    _ = db;

    for (objects) |obj| {
        const obj_uuid = _assetroot_fs.objid2uuid.get(obj) orelse continue;
        _ = _assetroot_fs.uuid2objid.swapRemove(obj_uuid);
        _ = _assetroot_fs.objid2uuid.swapRemove(obj);

        //TODO: Config verbosity
        if (false) {
            log.debug("Unmaping destroyed objid {any}:{s}", .{ obj, obj_uuid });
        }
    }
}

fn buffGetValidName(allocator: std.mem.Allocator, buf: [:0]u8, folder_: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) ![:0]const u8 {
    const folder = getObjForAsset(folder_).?;

    const db = _cdb.getDbFromObjid(folder_);

    const set = try _cdb.getReferencerSet(allocator, folder);
    defer allocator.free(set);

    var name_set = cetech1.ArraySet([]const u8).init();
    defer name_set.deinit(allocator);

    if (!type_idx.eql(FolderTypeIdx)) {
        for (set) |obj| {
            if (!obj.type_idx.eql(_cdb.getTypeIdx(db, public.Asset.type_hash).?)) continue;

            const asset_obj = public.Asset.readSubObj(_cdb, _cdb.readObj(obj).?, .Object).?;
            if (!asset_obj.type_idx.eql(type_idx)) continue;

            if (public.Asset.readStr(_cdb, _cdb.readObj(obj).?, .Name)) |name| {
                _ = try name_set.add(allocator, name);
            }
        }
    } else {
        for (set) |obj| {
            if (!isAssetFolder(obj)) continue;
            //if (obj.type_hash.id != public.Folder.type_hash.id) continue;

            if (public.Asset.readStr(_cdb, _cdb.readObj(obj).?, .Name)) |name| {
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

fn openInOs(allocator: std.mem.Allocator, open_type: platform.OpenInType, asset: cdb.ObjId) !void {
    if (_assetroot_fs.asset_root_path) |asset_root_path| {
        var buff: [128:0]u8 = undefined;
        const path = try getFilePathForAsset(&buff, asset);

        const full_path = try std.fs.path.join(allocator, &.{ asset_root_path, path });
        defer allocator.free(full_path);

        try platform_private.api.openIn(allocator, open_type, full_path);
    }
}

fn createNewAssetFromPrototype(asset: cdb.ObjId) !cdb.ObjId {
    const assset_r = public.Asset.read(_cdb, asset).?;

    const asset_obj = getObjForAsset(asset).?;

    const folder = public.Asset.readRef(_cdb, assset_r, .Folder).?;
    const folder_asset = getAssetForObj(folder).?;
    const asset_name = public.Asset.readStr(_cdb, assset_r, .Name).?;

    var buff: [256:0]u8 = undefined;
    const name = try buffGetValidName(
        _allocator,
        &buff,
        folder_asset,
        asset_obj.type_idx,
        asset_name,
    );

    const new_asset_obj = try _cdb.createObjectFromPrototype(asset_obj);
    return createAsset(name, folder_asset, new_asset_obj).?;
}

fn cloneNewAssetFrom(asset: cdb.ObjId) !cdb.ObjId {
    const assset_r = public.Asset.read(_cdb, asset).?;

    const asset_obj = getObjForAsset(asset).?;

    const folder = public.Asset.readRef(_cdb, assset_r, .Folder).?;
    const folder_asset = getAssetForObj(folder).?;
    const asset_name = public.Asset.readStr(_cdb, assset_r, .Name).?;

    var buff: [256:0]u8 = undefined;
    const name = try buffGetValidName(
        _allocator,
        &buff,
        folder_asset,
        asset_obj.type_idx,
        asset_name,
    );

    const new_asset_obj = try _cdb.cloneObject(asset_obj);
    return createAsset(name, folder_asset, new_asset_obj).?;
}

fn getAssetRootPath() ?[]const u8 {
    return _assetroot_fs.asset_root_path;
}

fn getAssetRootObj() cdb.ObjId {
    return _assetroot_fs.asset_root;
}
