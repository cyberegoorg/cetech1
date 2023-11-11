// I realy hate file, dirs and paths.
// Full of alloc shit and another braindump solution. Need cleanup but its works =).

const std = @import("std");
const apidb = @import("apidb.zig");
const task = @import("task.zig");
const cdb = @import("cdb.zig");
const cdb_types = @import("../cdb_types.zig");
const log = @import("log.zig");
const uuid = @import("uuid.zig");
const tempalloc = @import("tempalloc.zig");

const public = @import("../assetdb.zig");
const cetech1 = @import("../cetech1.zig");
const editorui = @import("editorui.zig");
const propIdx = cetech1.cdb.propIdx;

const Uuid2ObjId = std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.cdb.ObjId);
const ObjId2Uuid = std.AutoArrayHashMap(cetech1.cdb.ObjId, cetech1.uuid.Uuid);

// File info
// TODO: to struct
const Path2Folder = std.StringArrayHashMap(cetech1.cdb.ObjId);
const Folder2Path = std.AutoArrayHashMap(cetech1.cdb.ObjId, []u8);
const Uuid2AssetUuid = std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.uuid.Uuid);
const AssetUuid2Path = std.AutoArrayHashMap(cetech1.uuid.Uuid, []u8);
const AssetUuid2Depend = std.AutoArrayHashMap(cetech1.uuid.Uuid, UuidSet);
const AssetObjIdVersion = std.AutoArrayHashMap(cetech1.cdb.ObjId, u64);

const ToDeleteList = std.AutoArrayHashMap(cetech1.cdb.ObjId, void);

const AssetIOSet = std.AutoArrayHashMap(*public.AssetIOI, void);

pub const MODULE_NAME = "assetdb";

// Keywords for json format
const JSON_ASSET_VERSION = "__version";
const JSON_ASSET_UUID_TOKEN = "__asset_uuid";
const JSON_TAGS_TOKEN = "__tags";
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
    root_path: []const u8,
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
    .getPathForFolder = getPathForFolder,
    .createNewFolder = createNewFolder,
    .filerAsset = filerAsset,
    .isAssetNameValid = isAssetNameValid,
    .saveAsAllAssets = saveAsAllAssets,
    .deleteAsset = deleteAsset,
    .deleteFolder = deleteFolder,
    .isToDeleted = isToDeleted,
    .reviveDeleted = reviveDeleted,
    .buffGetValidName = buffGetValidName,
    .getAssetColor = getAssetColor,
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
var _folder2path: Folder2Path = undefined;
var _uuid2asset_uuid: Uuid2AssetUuid = undefined;
var _asset_uuid2path: AssetUuid2Path = undefined;
var _asset_uuid2depend: AssetUuid2Depend = undefined;
var _asset_bag: cetech1.dagraph.DAG(cetech1.uuid.Uuid) = undefined;

var _tmp_depend_array: std.ArrayList(cetech1.task.TaskID) = undefined;
var _tmp_taskid_map: std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.task.TaskID) = undefined;

// Version check
var _asset_objid2version: AssetObjIdVersion = undefined;
var _asset_objid2version_lck = std.Thread.Mutex{};

// Delete list
var _assets_to_remove: ToDeleteList = undefined;
var _folders_to_remove: ToDeleteList = undefined;

//TODO:
//  without lock? (actualy problem when creating ref_placeholder and real ref).
//  ref_placeholder is needed because there is unsorderd order for load. ordered need analyze phase for UUID.
//var _get_or_create_lock = std.Thread.Mutex{};

var _cdb_asset_io_i = public.AssetIOI.implement(struct {
    pub fn canImport(extension: []const u8) bool {
        const type_name = extension[1..];
        const type_hash = cetech1.strid.strId32(type_name);
        return _db.getTypePropDef(type_hash) != null;
    }

    pub fn canExport(db: *cetech1.cdb.CdbDb, asset: cetech1.cdb.ObjId, extension: []const u8) bool {
        const type_name = extension[1..];
        const type_hash = cetech1.strid.strId32(type_name);

        const asset_obj = public.AssetType.readSubObj(db, db.readObj(asset).?, .Object) orelse return false;
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
                const allocator = tmp_alloc.allocator();

                var full_path_buf: [2048]u8 = undefined;
                const full_path = self.dir.realpath(self.filename, &full_path_buf) catch undefined;
                log.api.info(MODULE_NAME, "Importing cdb asset {s}", .{full_path});

                var asset_file = self.dir.openFile(self.filename, .{ .mode = .read_only }) catch |err| {
                    log.api.err(MODULE_NAME, "Could not import asset {}", .{err});
                    return;
                };

                defer asset_file.close();
                defer self.dir.close();

                const asset_reader = asset_file.reader();

                const asset = readAssetFromReader(
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
        root_path: []const u8,
        sub_path: []const u8,
        asset: cetech1.cdb.ObjId,
    ) !cetech1.task.TaskID {
        const Task = struct {
            db: *cetech1.cdb.CdbDb,
            asset: cetech1.cdb.ObjId,
            sub_path: []const u8,
            root_path: []const u8,
            pub fn exec(self: *@This()) void {
                var tmp_alloc = tempalloc.api.createTempArena() catch undefined;
                defer tempalloc.api.destroyTempArena(tmp_alloc);
                const allocator = tmp_alloc.allocator();

                const version = self.db.getVersion(self.asset);

                saveCdbObj(self.asset, self.root_path, self.sub_path, allocator) catch |err| {
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
                .root_path = root_path,
            },
        );
    }
});

fn getAssetColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) [4]f32 {
    const is_modified = isObjModified(obj);
    const is_deleted = isToDeleted(obj);

    if (is_modified) {
        return cetech1.editorui.Colors.Modified;
    } else if (is_deleted) {
        return cetech1.editorui.Colors.Deleted;
    }

    if (public.AssetType.isSameType(obj)) {
        const r = db.readObj(obj).?;
        if (public.AssetType.readSubObj(db, r, .Object)) |asset_obj| {
            return editorui.api.getObjColor(db, asset_obj, null, null);
        }
    }

    return .{ 1.0, 1.0, 1.0, 1.0 };
}

fn isAssetNameValid(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, folder: cetech1.cdb.ObjId, type_hash: cetech1.strid.StrId32, base_name: [:0]const u8) !bool {
    const set = try db.getReferencerSet(folder, allocator);
    defer allocator.free(set);

    var name_set = std.StringArrayHashMap(void).init(allocator);
    defer name_set.deinit();

    if (type_hash.id != cetech1.assetdb.FolderType.type_hash.id) {
        for (set) |obj| {
            if (obj.type_hash.id != cetech1.assetdb.AssetType.type_hash.id) continue;

            const asset_obj = cetech1.assetdb.AssetType.readSubObj(db, db.readObj(obj).?, .Object).?;
            if (asset_obj.type_hash.id != type_hash.id) continue;

            if (cetech1.assetdb.AssetType.readStr(db, db.readObj(obj).?, .Name)) |name| {
                try name_set.put(name, {});
            }
        }
    } else {
        for (set) |obj| {
            if (obj.type_hash.id != cetech1.assetdb.FolderType.type_hash.id) continue;

            if (cetech1.assetdb.AssetType.readStr(db, db.readObj(obj).?, .Name)) |name| {
                try name_set.put(name, {});
            }
        }
    }

    return !name_set.contains(base_name);
}
// Asset visual aspect
var asset_visual_aspect = cetech1.editorui.UiVisualAspect.implement(
    assetNameUIVisalAspect,
    assetIconUIVisalAspect,
    assetColorUIVisalAspect,
);

fn assetNameUIVisalAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![:0]const u8 {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, &cdb.api);
    const obj_r = db.readObj(obj).?;

    const asset_name = public.AssetType.readStr(&db, obj_r, .Name) orelse "No NAME =()";
    const asset_obj = public.AssetType.readSubObj(&db, obj_r, .Object).?;
    const type_name = db.getTypeName(asset_obj.type_hash).?;

    return try std.fmt.allocPrintZ(
        allocator,
        "{s}.{s}",
        .{
            asset_name,
            type_name,
        },
    );
}

fn assetIconUIVisalAspect(
    allocator: std.mem.Allocator,
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![:0]const u8 {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, &cdb.api);
    const obj_r = db.readObj(obj).?;
    const asset_obj = public.AssetType.readSubObj(&db, obj_r, .Object).?;
    const ui_visual_aspect = db.getAspect(cetech1.editorui.UiVisualAspect, asset_obj.type_hash);
    var ui_icon: ?[:0]const u8 = null;
    if (ui_visual_aspect) |aspect| {
        if (aspect.ui_icons) |icons| {
            ui_icon = std.mem.span(icons(&allocator, &db, asset_obj));
        }
    }
    defer {
        if (ui_icon) |i| {
            allocator.free(i);
        }
    }

    const is_modified = isObjModified(obj);
    const is_deleted = isToDeleted(obj);

    return try std.fmt.allocPrintZ(
        allocator,
        "{s} {s}{s}",
        .{
            if (ui_icon) |i| i else cetech1.editorui.Icons.Asset,
            if (is_modified) cetech1.editorui.CoreIcons.FA_STAR_OF_LIFE else "",
            if (is_deleted) " " ++ cetech1.editorui.Icons.Deleted else "",
        },
    );
}

fn assetColorUIVisalAspect(
    dbc: *cetech1.cdb.Db,
    obj: cetech1.cdb.ObjId,
) ![4]f32 {
    var db = cetech1.cdb.CdbDb.fromDbT(dbc, &cdb.api);
    return getAssetColor(&db, obj);
}

// Folder visual aspect
var folder_visual_aspect = cetech1.editorui.UiVisualAspect.implement(
    struct {
        fn ui_name(
            allocator: std.mem.Allocator,
            dbc: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) ![:0]const u8 {
            var db = cetech1.cdb.CdbDb.fromDbT(dbc, &cdb.api);
            const obj_r = db.readObj(obj).?;

            const is_root = public.FolderType.readRef(&db, obj_r, .Parent) == null;

            const asset_name = if (is_root) "ROOT" else public.FolderType.readStr(&db, obj_r, .Name) orelse "No NAME =()";
            return try std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{
                    asset_name,
                },
            );
        }
    }.ui_name,

    struct {
        fn ui_icons(
            allocator: std.mem.Allocator,
            dbc: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) ![:0]const u8 {
            _ = dbc;

            const is_modified = isObjModified(obj);
            const is_deleted = isToDeleted(obj);

            return try std.fmt.allocPrintZ(
                allocator,
                "{s} {s}{s}",
                .{
                    cetech1.editorui.Icons.Folder,
                    if (is_modified) cetech1.editorui.CoreIcons.FA_STAR_OF_LIFE else "",
                    if (is_deleted) " " ++ cetech1.editorui.Icons.Deleted else "",
                },
            );
        }
    }.ui_icons,
    struct {
        fn ui_color(
            dbc: *cetech1.cdb.Db,
            obj: cetech1.cdb.ObjId,
        ) ![4]f32 {
            var db = cetech1.cdb.CdbDb.fromDbT(dbc, &cdb.api);
            return getAssetColor(&db, obj);
        }
    }.ui_color,
);

pub fn createCdbTypes(db_: *cetech1.cdb.Db) !void {
    var db = cetech1.cdb.CdbDb.fromDbT(db_, &cdb.api);

    // Asset type is wrapper for asset object
    const asset_type_hash = db.addType(
        public.AssetType.name,
        &.{
            .{ .prop_idx = public.AssetType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.AssetType.propIdx(.Description), .name = "description", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.AssetType.propIdx(.Tags), .name = "tags", .type = cetech1.cdb.PropType.REFERENCE_SET, .type_hash = public.TagType.type_hash },
            .{ .prop_idx = public.AssetType.propIdx(.Object), .name = "object", .type = cetech1.cdb.PropType.SUBOBJECT },
            .{ .prop_idx = public.AssetType.propIdx(.Folder), .name = "folder", .type = cetech1.cdb.PropType.REFERENCE, .type_hash = public.FolderType.type_hash },
        },
    ) catch unreachable;
    std.debug.assert(asset_type_hash.id == public.AssetType.type_hash.id);
    try cetech1.assetdb.AssetType.addAspect(&db, cetech1.editorui.UiVisualAspect, &asset_visual_aspect);

    // Asset folder
    // TODO as regular asset
    const asset_folder_type = db.addType(
        public.FolderType.name,
        &.{
            .{ .prop_idx = public.FolderType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.FolderType.propIdx(.Description), .name = "description", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.FolderType.propIdx(.Tags), .name = "tags", .type = cetech1.cdb.PropType.REFERENCE_SET, .type_hash = public.TagType.type_hash },
            .{ .prop_idx = public.FolderType.propIdx(.Parent), .name = "parent", .type = cetech1.cdb.PropType.REFERENCE, .type_hash = public.FolderType.type_hash },
        },
    ) catch unreachable;
    std.debug.assert(asset_folder_type.id == public.FolderType.type_hash.id);
    try cetech1.assetdb.FolderType.addAspect(&db, cetech1.editorui.UiVisualAspect, &folder_visual_aspect);

    // All assets is parent of this
    asset_root_type = db.addType(
        AssetRootType.name,
        &.{
            .{ .prop_idx = AssetRootType.propIdx(.Assets), .name = "assets", .type = cetech1.cdb.PropType.SUBOBJECT_SET },
            .{ .prop_idx = AssetRootType.propIdx(.Folders), .name = "folders", .type = cetech1.cdb.PropType.SUBOBJECT_SET },
        },
    ) catch unreachable;

    // Project
    const project_type = db.addType(
        public.ProjectType.name,
        &.{
            .{ .prop_idx = public.ProjectType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.ProjectType.propIdx(.Description), .name = "description", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.ProjectType.propIdx(.Organization), .name = "organization", .type = cetech1.cdb.PropType.STR },
        },
    ) catch unreachable;
    std.debug.assert(project_type.id == public.ProjectType.type_hash.id);

    const ct_asset_tag_type = db.addType(
        public.TagType.name,
        &.{
            .{ .prop_idx = public.TagType.propIdx(.Name), .name = "name", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.TagType.propIdx(.Description), .name = "description", .type = cetech1.cdb.PropType.STR },
            .{ .prop_idx = public.TagType.propIdx(.Color), .name = "color", .type = cetech1.cdb.PropType.SUBOBJECT, .type_hash = cdb_types.Color4fType.type_hash },
        },
    ) catch unreachable;
    _ = ct_asset_tag_type;

    const ct_tags = db.addType(
        public.TagsType.name,
        &.{
            .{ .prop_idx = public.TagsType.propIdx(.Tags), .name = "tags", .type = cetech1.cdb.PropType.REFERENCE_SET, .type_hash = public.TagType.type_hash },
        },
    ) catch unreachable;
    _ = ct_tags;

    _ = cetech1.cdb_types.addBigType(&db, public.FooAsset.name) catch unreachable;
    _ = cetech1.cdb_types.addBigType(&db, public.BarAsset.name) catch unreachable;
    _ = cetech1.cdb_types.addBigType(&db, public.BazAsset.name) catch unreachable;
}

var create_cdb_types_i = cetech1.cdb.CreateTypesI.implement(createCdbTypes);

pub fn registerToApi() !void {
    try apidb.api.setZigApi(public.AssetDBAPI, &api);
    try apidb.api.implOrRemove(cetech1.cdb.CreateTypesI, &create_cdb_types_i, true);
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
    _asset_bag = cetech1.dagraph.DAG(cetech1.uuid.Uuid).init(allocator);
    _path2folder = Path2Folder.init(allocator);
    _folder2path = Folder2Path.init(allocator);

    _tmp_depend_array = std.ArrayList(cetech1.task.TaskID).init(allocator);
    _tmp_taskid_map = std.AutoArrayHashMap(cetech1.uuid.Uuid, cetech1.task.TaskID).init(allocator);

    _assets_to_remove = ToDeleteList.init(allocator);
    _folders_to_remove = ToDeleteList.init(allocator);

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
    _folder2path.deinit();
    _tmp_depend_array.deinit();
    _tmp_taskid_map.deinit();
    _asset_objid2version.deinit();

    _assets_to_remove.deinit();
    _folders_to_remove.deinit();

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
    return cur_version != _asset_root_last_version or (_folders_to_remove.count() != 0 or _assets_to_remove.count() != 0);
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
    const obj = try _db.createObject(type_hash);
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
    const obj = try _db.createObject(type_hash);
    _ = try getOrCreateUuid(obj);
    return obj;
}

fn analyzFromJsonValue(parsed: std.json.Value, tmp_allocator: std.mem.Allocator, depend_on: *UuidSet, provide_uuids: *UuidSet) !void {
    const obj_uuid_str = parsed.object.get(JSON_UUID_TOKEN).?;
    const obj_uuid = uuid.api.fromStr(obj_uuid_str.string).?;
    const obj_type = parsed.object.get(JSON_TYPE_NAME_TOKEN).?;
    const obj_type_hash = cetech1.strid.strId32(obj_type.string);

    try provide_uuids.put(obj_uuid, {});

    const prototype_uuid = parsed.object.get(JSON_PROTOTYPE_UUID);
    if (prototype_uuid) |proto_uuid| {
        try depend_on.put(uuid.fromStr(proto_uuid.string).?, {});
    }

    const tags = parsed.object.get(JSON_TAGS_TOKEN);
    if (tags) |tags_array| {
        for (tags_array.array.items) |value| {
            var ref_link = std.mem.split(u8, value.string, ":");
            const ref_type = cetech1.strid.strId32(ref_link.first());
            const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;
            _ = ref_type;
            try depend_on.put(ref_uuid, {});
        }
    }

    const prop_defs = _db.getTypePropDef(obj_type_hash).?;

    const keys = parsed.object.keys();
    for (keys) |k| {
        // Skip private fields
        if (std.mem.startsWith(u8, k, "__")) continue;
        if (std.mem.endsWith(u8, k, JSON_REMOVED_POSTFIX)) continue;
        if (std.mem.endsWith(u8, k, JSON_INSTANTIATE_POSTFIX)) continue;

        const value = parsed.object.get(k).?;

        const prop_idx = _db.getTypePropDefIdx(obj_type_hash, k) orelse continue;
        const prop_def = prop_defs[prop_idx];

        switch (prop_def.type) {
            cetech1.cdb.PropType.SUBOBJECT => {
                try analyzFromJsonValue(value, tmp_allocator, depend_on, provide_uuids);
            },
            cetech1.cdb.PropType.REFERENCE => {
                var ref_link = std.mem.split(u8, value.string, ":");
                const ref_type = cetech1.strid.strId32(ref_link.first());
                const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;
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
                    const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;
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

    for (_folder2path.values()) |path| {
        _allocator.free(path);
    }

    for (_asset_uuid2depend.values()) |*depend| {
        depend.deinit();
    }

    _asset_uuid2path.clearRetainingCapacity();
    _uuid2asset_uuid.clearRetainingCapacity();
    _asset_uuid2depend.clearRetainingCapacity();
    _path2folder.clearRetainingCapacity();
    _folder2path.clearRetainingCapacity();
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
    const asset_uuid = uuid.api.fromStr(asset_uuid_str.string).?;

    var depend_on = UuidSet.init(tmp_allocator);
    defer depend_on.deinit();

    var provide_uuids = UuidSet.init(tmp_allocator);
    defer provide_uuids.deinit();

    try analyzFromJsonValue(parsed.value, tmp_allocator, &depend_on, &provide_uuids);
    try addAnalyzedFileInfo(path, asset_uuid, &depend_on, &provide_uuids);
}

fn analyzeFolder(root_dir: std.fs.Dir, parent_folder: cetech1.cdb.ObjId, tasks: *std.ArrayList(cetech1.task.TaskID), tmp_allocator: std.mem.Allocator) !void {
    var iterator = root_dir.iterate();
    while (try iterator.next()) |entry| {
        // Skip . files
        if (std.mem.startsWith(u8, entry.name, ".")) continue;

        if (entry.kind == .file) {
            const extension = std.fs.path.extension(entry.name);
            if (!std.mem.startsWith(u8, extension, CT_ASSETS_FILE_PREFIX)) continue;
            if (std.mem.startsWith(u8, entry.name, ".")) continue;

            const Task = struct {
                root_dir: std.fs.Dir,
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
                    .path = try root_dir.realpathAlloc(tmp_allocator, entry.name),
                    .tmp_allocator = tmp_allocator,
                },
            );
            try tasks.append(task_id);
        } else if (entry.kind == .directory) {
            if (std.mem.endsWith(u8, entry.name, "." ++ BLOB_EXTENSION)) continue;
            var dir = try root_dir.openDir(entry.name, .{ .iterate = true });
            defer dir.close();

            var rel_path: [2048]u8 = undefined;
            log.api.debug(MODULE_NAME, "Scaning folder {s}", .{try dir.realpath(".", &rel_path)});

            const folder_obj = try getOrCreateFolder(tmp_allocator, root_dir, dir, entry.name, parent_folder);

            try _path2folder.put(try dir.realpathAlloc(_allocator, "."), folder_obj);
            try _folder2path.put(folder_obj, try dir.realpathAlloc(_allocator, "."));

            try analyzeFolder(dir, folder_obj, tasks, tmp_allocator);
            try addFolderToRoot(folder_obj);
        }
    }
}

fn deleteAsset(db: *cetech1.cdb.CdbDb, asset: cetech1.cdb.ObjId) anyerror!void {
    _ = db;
    try _assets_to_remove.put(asset, {});
}

fn deleteFolder(db: *cetech1.cdb.CdbDb, folder: cetech1.cdb.ObjId) anyerror!void {
    _ = db;
    try _folders_to_remove.put(folder, {});
}

fn isToDeleted(asset_or_folder: cetech1.cdb.ObjId) bool {
    if (public.FolderType.isSameType(asset_or_folder)) {
        return _folders_to_remove.contains(asset_or_folder);
    } else {
        return _assets_to_remove.contains(asset_or_folder);
    }
}

fn reviveDeleted(asset_or_folder: cetech1.cdb.ObjId) void {
    if (public.FolderType.isSameType(asset_or_folder)) {
        _ = _folders_to_remove.swapRemove(asset_or_folder);
    } else {
        _ = _assets_to_remove.swapRemove(asset_or_folder);
    }
}

fn commitDeleteChanges(db: *cetech1.cdb.CdbDb, tmp_allocator: std.mem.Allocator) !void {
    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();
    for (_folders_to_remove.keys()) |folder| {
        const path = try getPathForFolder(folder, tmp_allocator);
        defer tmp_allocator.free(path);
        try root_dir.deleteTree(std.fs.path.dirname(path).?);
        db.destroyObject(folder);
    }
    _folders_to_remove.clearRetainingCapacity();

    for (_assets_to_remove.keys()) |asset| {
        const path = try getFilePathForAsset(asset, tmp_allocator);
        defer tmp_allocator.free(path);
        // Blob
        const blob_dir_path = try getPathForAsset(asset, BLOB_EXTENSION, tmp_allocator);
        defer tmp_allocator.free(blob_dir_path);
        try root_dir.deleteTree(blob_dir_path);

        // asset
        try root_dir.deleteTree(path);
        db.destroyObject(asset);
    }
    _assets_to_remove.clearRetainingCapacity();
}

// fn writeAssetDOTGraph() !void {
//     var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
//     defer root_dir.close();

//     var dot_file = try root_dir.createFile(CT_TEMP_FOLDER ++ "/" ++ "asset_graph.dot", .{});
//     defer dot_file.close();

//     // write header
//     var writer = dot_file.writer();
//     try writer.print("digraph asset_graph {{\n", .{});

//     // write nodes
//     try writer.print("    subgraph {{\n", .{});
//     try writer.print("        node [shape = box;];\n", .{});
//     for (_asset_uuid2path.keys(), _asset_uuid2path.values()) |asset_uuid, asset_path| {
//         var path = try std.fs.path.relative(_allocator, _asset_root_path.?, asset_path);
//         defer _allocator.free(path);

//         try writer.print("        \"{s}\" [label = \"{s}\";];\n", .{ asset_uuid, path });
//     }
//     try writer.print("    }}\n", .{});

//     // Edges
//     for (_asset_uuid2depend.keys(), _asset_uuid2depend.values()) |asset_uuid, depends| {
//         for (depends.keys()) |depend| {
//             try writer.print("    \"{s}\" -> \"{s}\";\n", .{ asset_uuid, _uuid2asset_uuid.get(depend).? });
//         }
//     }

//     // write footer
//     try writer.print("}}\n", .{});
// }

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
        const path = try std.fs.path.relative(_allocator, _asset_root_path.?, asset_path);
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

fn loadProject(tmp_allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, asset_root_path: []const u8, asset_root_folder: cetech1.cdb.ObjId) !void {
    var dir = try std.fs.cwd().openDir(asset_root_path, .{});

    var asset_file = dir.openFile("project.ct_project", .{ .mode = .read_only }) catch |err| {
        log.api.err(MODULE_NAME, "Could not load project.ct_project {}", .{err});
        return;
    };
    defer asset_file.close();

    const asset_reader = asset_file.reader();

    const asset = readAssetFromReader(
        @TypeOf(asset_reader),
        asset_reader,
        "project",
        asset_root_folder,
        ReadBlobFromFile,
        tmp_allocator,
    ) catch |err| {
        log.api.err(MODULE_NAME, "Could not import asset {}", .{err});
        return;
    };

    addAssetToRoot(asset) catch |err| {
        log.api.err(MODULE_NAME, "Could not add asset to root {}", .{err});
        return;
    };

    // Save current version to assedb.
    markObjSaved(asset, db.getVersion(asset));
}

fn getOrCreateFolder(
    tmp_allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    dir: std.fs.Dir,
    name: ?[]const u8,
    parent_folder: ?cetech1.cdb.ObjId,
) !cetech1.cdb.ObjId {
    var folder_obj: cetech1.cdb.ObjId = undefined;
    const root_folder = parent_folder == null;
    const exist_marker = if (root_folder) existRootFolderMarker(dir) else existFolderMarker(root_dir, name.?);

    if (exist_marker) {
        var asset_file = try dir.openFile("." ++ public.FolderType.name, .{ .mode = .read_only });
        defer asset_file.close();
        const asset_reader = asset_file.reader();
        folder_obj = try readObjFromJson(
            @TypeOf(asset_reader),
            asset_reader,
            ReadBlobFromFile,
            tmp_allocator,
        );
        markObjSaved(folder_obj, _db.getVersion(folder_obj));
    } else {
        folder_obj = try public.FolderType.createObject(_db);

        if (name != null or parent_folder != null) {
            const folder_obj_w = _db.writeObj(folder_obj).?;
            defer _db.writeCommit(folder_obj_w);

            if (name) |n| {
                var buffer: [128]u8 = undefined;
                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{n});
                try public.FolderType.setStr(_db, folder_obj_w, .Name, str);
            }

            if (parent_folder) |folder| {
                try public.FolderType.setRef(_db, folder_obj_w, .Parent, folder);
            }
        }

        try saveFolderObj(tmp_allocator, folder_obj, _asset_root_path.?);
    }

    return folder_obj;
}

fn openAssetRootFolder(asset_root_path: []const u8, tmp_allocator: std.mem.Allocator) !void {
    _asset_root_path = asset_root_path;
    var root_dir = try std.fs.cwd().openDir(asset_root_path, .{ .iterate = true });
    defer root_dir.close();

    try root_dir.makePath(CT_TEMP_FOLDER);

    if (!_asset_root.isEmpty()) {
        _db.destroyObject(_asset_root);
        _db.destroyObject(_asset_root_folder);
        _asset_root = try _db.createObject(asset_root_type);
    }

    try resetAnalyzedFileInfo();

    // asset root folder
    _asset_root_folder = try getOrCreateFolder(tmp_allocator, root_dir, root_dir, null, null);
    try addFolderToRoot(_asset_root_folder);
    const root_path = try root_dir.realpathAlloc(_allocator, ".");
    log.api.info(MODULE_NAME, "Asset root dir {s}", .{root_path});

    // project asset
    if (!existRootProjectAsset(root_dir)) {
        const project_obj = try public.ProjectType.createObject(_db);
        const project_asset = createAsset("project", _asset_root_folder, project_obj).?;
        const save_task = try saveAsset(tmp_allocator, _asset_root_path.?, project_asset);
        task.api.wait(save_task);
    } else {
        try loadProject(tmp_allocator, _db, asset_root_path, _asset_root_folder);
    }

    try _path2folder.put(root_path, _asset_root_folder);
    markObjSaved(_asset_root_folder, _db.getVersion(_asset_root_folder));

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

    try writeAssetGraphMD();

    for (_asset_bag.output.keys()) |output| {
        log.api.debug(MODULE_NAME, "Loader plan {s}", .{_asset_uuid2path.get(output).?});
        const depeds = _asset_bag.dependList(output);
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

        // skip
        if (std.mem.eql(u8, extension, "." ++ public.ProjectType.name)) continue;

        const asset_io = findFirstAssetIOForImport(extension) orelse continue;

        var prereq = cetech1.task.TaskID.none;
        const depeds = _asset_bag.dependList(asset_uuid);
        if (depeds != null) {
            _tmp_depend_array.clearRetainingCapacity();
            for (depeds.?) |d| {
                if (_tmp_taskid_map.get(d)) |task_id| {
                    try _tmp_depend_array.append(task_id);
                } else {
                    log.api.err(MODULE_NAME, "No task for UUID {s}", .{d});
                }
            }
            prereq = try task.api.combine(_tmp_depend_array.items);
        }

        const copy_dir = try std.fs.openDirAbsolute(dir, .{});
        if (asset_io.importAsset.?(_db, prereq, copy_dir, parent_folder, filename, null)) |import_task| {
            try _tmp_taskid_map.put(asset_uuid, import_task);
        } else |err| {
            log.api.err(MODULE_NAME, "Could not import asset {s} {}", .{ asset_path, err });
        }
    }

    //try writeAssetDOTGraph();

    const sync_job = try task.api.combine(_tmp_taskid_map.values());
    task.api.wait(sync_job);

    // Resave obj version
    const all_asset_copy = try tmp_allocator.dupe(cetech1.cdb.ObjId, _asset_objid2version.keys());
    defer tmp_allocator.free(all_asset_copy);
    for (all_asset_copy) |obj| {
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
    const objid = _uuid2objid.get(obj_uuid).?;
    _ = _uuid2objid.swapRemove(obj_uuid);
    _ = _objid2uuid.swapRemove(objid);
}

fn unmapByObjId(obj: cetech1.cdb.ObjId) !void {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();
    const obj_uuid = _objid2uuid.get(obj).?;
    _ = _uuid2objid.swapRemove(obj_uuid);
    _ = _objid2uuid.swapRemove(obj);
}

fn setAssetNameAndFolder(asset: cetech1.cdb.ObjId, name: []const u8, asset_folder: cetech1.cdb.ObjId) !void {
    const asset_w = _db.writeObj(asset).?;

    var buffer: [128]u8 = undefined;
    const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{name});

    try public.AssetType.setStr(_db, asset_w, .Name, str);
    try public.AssetType.setRef(_db, asset_w, .Folder, asset_folder);

    _db.writeCommit(asset_w);
}

fn addAssetToRoot(asset: cetech1.cdb.ObjId) !void {
    // TODO: make posible CAS write to CDB and remove lock.
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    const asset_root_w = _db.writeObj(_asset_root).?;
    const asset_w = _db.writeObj(asset).?;
    try AssetRootType.addSubObjToSet(_db, asset_root_w, .Assets, &.{asset_w});
    _db.writeCommit(asset_w);
    _db.writeCommit(asset_root_w);
}

fn addFolderToRoot(folder: cetech1.cdb.ObjId) !void {
    // TODO: make posible CAS write to CDB and remove lock.
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    const asset_root_w = _db.writeObj(_asset_root).?;
    const folder_w = _db.writeObj(folder).?;
    try AssetRootType.addSubObjToSet(_db, asset_root_w, .Folders, &.{folder_w});
    _db.writeCommit(folder_w);
    _db.writeCommit(asset_root_w);
}

fn createAsset(asset_name: []const u8, asset_folder: cetech1.cdb.ObjId, asset_obj: ?cetech1.cdb.ObjId) ?cetech1.cdb.ObjId {
    const asset = createObject(public.AssetType.type_hash) catch return null;

    if (asset_obj != null) {
        const asset_w = _db.writeObj(asset).?;
        const asset_obj_w = _db.writeObj(asset_obj.?).?;
        public.AssetType.setSubObj(_db, asset_w, .Object, asset_obj_w) catch return null;

        _db.writeCommit(asset_obj_w);
        _db.writeCommit(asset_w);
    }

    setAssetNameAndFolder(asset, asset_name, asset_folder) catch return null;
    addAssetToRoot(asset) catch return null;
    return asset;
}

pub fn saveAllTo(tmp_allocator: std.mem.Allocator, root_path: []const u8) !void {
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    const folders = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Folders, tmp_allocator)).?;
    defer tmp_allocator.free(folders);
    for (folders) |folder| {
        try saveFolderObj(tmp_allocator, folder, root_path);
    }

    const assets = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Assets, tmp_allocator)).?;
    defer tmp_allocator.free(assets);

    if (assets.len == 0) return;

    var tasks = try std.ArrayList(cetech1.task.TaskID).initCapacity(tmp_allocator, assets.len);
    defer tasks.deinit();

    for (assets) |asset| {
        const export_task = try saveAsset(tmp_allocator, root_path, asset);
        if (export_task == .none) continue;
        try tasks.append(export_task);
    }

    task.api.wait(try task.api.combine(tasks.items));

    _asset_root_last_version = _db.getVersion(_asset_root);
}

pub fn saveAll(tmp_allocator: std.mem.Allocator) !void {
    try saveAllTo(tmp_allocator, _asset_root_path.?);
    try commitDeleteChanges(_db, tmp_allocator);
}

pub fn saveAssetAndWait(tmp_allocator: std.mem.Allocator, asset: cetech1.cdb.ObjId) !void {
    if (asset.type_hash.id == cetech1.assetdb.AssetType.type_hash.id) {
        const export_task = try saveAsset(tmp_allocator, _asset_root_path.?, asset);
        task.api.wait(export_task);
    } else if (asset.type_hash.id == cetech1.assetdb.FolderType.type_hash.id) {
        try saveFolderObj(tmp_allocator, asset, _asset_root_path.?);
    }
}

pub fn saveAllModifiedAssets(tmp_allocator: std.mem.Allocator) !void {
    _asset_root_lock.lock();
    defer _asset_root_lock.unlock();

    const folders = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Folders, tmp_allocator)).?;
    defer tmp_allocator.free(folders);
    for (folders) |folder| {
        if (!isObjModified(folder)) continue;
        try saveFolderObj(tmp_allocator, folder, _asset_root_path.?);
    }

    const assets = (try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Assets, tmp_allocator)).?;
    defer tmp_allocator.free(assets);

    var tasks = try std.ArrayList(cetech1.task.TaskID).initCapacity(tmp_allocator, assets.len);
    defer tasks.deinit();

    for (assets) |asset| {
        if (!isObjModified(asset)) continue;

        if (saveAsset(tmp_allocator, _asset_root_path.?, asset)) |export_task| {
            if (export_task == .none) continue;
            try tasks.append(export_task);
        } else |err| {
            log.api.err(MODULE_NAME, "Could not save asset {}", .{err});
        }
    }

    try commitDeleteChanges(_db, tmp_allocator);

    task.api.wait(try task.api.combine(tasks.items));

    _asset_root_last_version = _db.getVersion(_asset_root);
}

fn getPathForFolder(from_folder: cetech1.cdb.ObjId, tmp_allocator: std.mem.Allocator) ![]u8 {
    var path = std.ArrayList([:0]const u8).init(tmp_allocator);
    defer path.deinit();

    const from_folder_r = _db.readObj(from_folder).?;
    const root_folder_name = public.FolderType.readStr(_db, from_folder_r, .Name);

    if (root_folder_name != null) {
        var folder_it: ?cetech1.cdb.ObjId = from_folder;
        while (folder_it) |folder| : (folder_it = public.FolderType.readRef(_db, _db.readObj(folder).?, .Parent)) {
            const folder_name = public.FolderType.readStr(_db, _db.readObj(folder).?, .Name) orelse continue;
            try path.insert(0, folder_name);
        }

        const sub_path = try std.fs.path.join(tmp_allocator, path.items);
        defer tmp_allocator.free(sub_path);
        return std.fmt.allocPrint(tmp_allocator, "{s}/." ++ public.FolderType.name, .{sub_path});
    } else {
        return std.fmt.allocPrint(tmp_allocator, "." ++ public.FolderType.name, .{});
    }
}

pub fn getFilePathForAsset(asset: cetech1.cdb.ObjId, tmp_allocator: std.mem.Allocator) ![]u8 {
    const asset_r = _db.readObj(asset);
    const asset_obj = public.AssetType.readSubObj(_db, asset_r.?, .Object).?;

    // append asset type extension
    return getPathForAsset(asset, _db.getTypeName(asset_obj.type_hash).?, tmp_allocator);
}

fn getPathForAsset(asset: cetech1.cdb.ObjId, extension: []const u8, tmp_allocator: std.mem.Allocator) ![]u8 {
    const asset_r = _db.readObj(asset);
    var path = std.ArrayList([:0]const u8).init(tmp_allocator);
    defer path.deinit();

    // add asset name
    const asset_name = public.AssetType.readStr(_db, asset_r.?, .Name);
    try path.insert(0, asset_name.?);

    // make sub path
    var folder_it = public.AssetType.readRef(_db, asset_r.?, .Folder);
    while (folder_it) |folder| : (folder_it = public.FolderType.readRef(_db, _db.readObj(folder).?, .Parent)) {
        const folder_name = public.FolderType.readStr(_db, _db.readObj(folder).?, .Name) orelse continue;
        try path.insert(0, folder_name);
    }

    const sub_path = try std.fs.path.join(tmp_allocator, path.items);
    defer tmp_allocator.free(sub_path);

    return std.fmt.allocPrint(tmp_allocator, "{s}.{s}", .{ sub_path, extension });
}

fn WriteBlobToFile(
    blob: []const u8,
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    root_path: []const u8,
    tmp_allocator: std.mem.Allocator,
) anyerror!void {
    const blob_dir_path = try getPathForAsset(asset, BLOB_EXTENSION, tmp_allocator);
    defer tmp_allocator.free(blob_dir_path);

    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    //create blob dir
    try root_dir.makePath(blob_dir_path);

    var blob_file_name_buf: [1024]u8 = undefined;
    const blob_file_name = try std.fmt.bufPrint(&blob_file_name_buf, "{x}{x}", .{ cetech1.strid.strId32(&obj_uuid.bytes).id, prop_hash.id });

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
    const blob_dir_path = try getPathForAsset(asset, BLOB_EXTENSION, tmp_allocator);
    defer tmp_allocator.free(blob_dir_path);

    var root_dir = try std.fs.cwd().openDir(_asset_root_path.?, .{});
    defer root_dir.close();

    var blob_file_name_buf: [1024]u8 = undefined;
    const blob_file_name = try std.fmt.bufPrint(&blob_file_name_buf, "{x}{x}", .{ cetech1.strid.strId32(&obj_uuid.bytes).id, prop_hash.id });

    var blob_dir = try root_dir.openDir(blob_dir_path, .{});
    defer blob_dir.close();

    var blob_file = try blob_dir.openFile(blob_file_name, .{});
    defer blob_file.close();
    const size = try blob_file.getEndPos();

    const blob = try tmp_allocator.alloc(u8, size);
    _ = try blob_file.readAll(blob);
    return blob;
}

fn saveCdbObj(obj: cetech1.cdb.ObjId, root_path: []const u8, sub_path: []const u8, tmp_allocator: std.mem.Allocator) !void {
    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    const dir_path = std.fs.path.dirname(sub_path);
    if (dir_path != null) {
        try root_dir.makePath(dir_path.?);
    }

    var obj_file = try root_dir.createFile(sub_path, .{});
    defer obj_file.close();
    const writer = obj_file.writer();

    const folder = public.AssetType.readRef(_db, _db.readObj(obj).?, .Folder).?;
    try writeCdbObjJson(
        @TypeOf(writer),
        obj,
        writer,
        obj,
        folder,
        WriteBlobToFile,
        root_path,
        tmp_allocator,
    );
}

pub fn saveAsset(tmp_allocator: std.mem.Allocator, root_path: []const u8, asset: cetech1.cdb.ObjId) !cetech1.task.TaskID {
    const sub_path = try getFilePathForAsset(asset, tmp_allocator);

    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    const asset_uuid = getUuid(asset);

    if (asset_uuid) |a_uuid| {
        if (_asset_uuid2path.get(a_uuid)) |old_path| {
            const root_full_path = try root_dir.realpathAlloc(tmp_allocator, ".");
            defer tmp_allocator.free(root_full_path);

            const realtive_old = try std.fs.path.relative(tmp_allocator, root_full_path, old_path);
            defer tmp_allocator.free(realtive_old);

            // rename or move.
            if (!std.mem.eql(u8, realtive_old, sub_path)) {
                // This shit remove blobl dir if needed...
                const old_dirpath = std.fs.path.dirname(realtive_old) orelse "";
                const old_base_name = std.fs.path.basename(old_path);
                const old_name = std.fs.path.stem(old_base_name);
                const blob_dir_name = try std.fmt.allocPrint(tmp_allocator, "{s}.{s}", .{ old_name, BLOB_EXTENSION });
                defer tmp_allocator.free(blob_dir_name);
                const blob_path = try std.fs.path.join(tmp_allocator, &.{ old_dirpath, blob_dir_name });
                defer tmp_allocator.free(blob_path);
                try root_dir.deleteTree(blob_path);

                // Rename
                if (std.fs.path.dirname(sub_path)) |dir| {
                    try root_dir.makePath(dir);
                }

                try root_dir.rename(realtive_old, sub_path);
                try _asset_uuid2path.put(a_uuid, try root_dir.realpathAlloc(_allocator, sub_path));
                _allocator.free(old_path);
            }
        }
    }

    if (findFirstAssetIOForExport(_db, asset, std.fs.path.extension(sub_path))) |asset_io| {
        return asset_io.exportAsset.?(_db, root_path, sub_path, asset);
    }
    return .none;
}

fn saveFolderObj(tmp_allocator: std.mem.Allocator, folder: cetech1.cdb.ObjId, root_path: []const u8) !void {
    const sub_path = try getPathForFolder(folder, tmp_allocator);
    defer tmp_allocator.free(sub_path);

    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    if (_folder2path.get(folder)) |old_path| {
        const subdir = std.fs.path.dirname(sub_path).?;

        const root_full_path = try root_dir.realpathAlloc(tmp_allocator, ".");
        defer tmp_allocator.free(root_full_path);

        const realtive_old = try std.fs.path.relative(tmp_allocator, root_full_path, old_path);
        defer tmp_allocator.free(realtive_old);

        // rename or move.
        if (!std.mem.eql(u8, realtive_old, subdir)) {
            try root_dir.makePath(subdir);

            try root_dir.rename(realtive_old, subdir);
            try _folder2path.put(folder, try root_dir.realpathAlloc(_allocator, subdir));
            _allocator.free(old_path);
        }
    }

    if (std.fs.path.dirname(sub_path)) |dir| {
        try root_dir.makePath(dir);
    }

    var obj_file = try root_dir.createFile(sub_path, .{});
    defer obj_file.close();
    const writer = obj_file.writer();

    log.api.info(MODULE_NAME, "Creating folder asset in {s}.", .{sub_path});

    try writeCdbObjJson(
        @TypeOf(writer),
        folder,
        writer,
        folder,
        folder,
        WriteBlobToFile,
        root_path,
        tmp_allocator,
    );

    markObjSaved(folder, _db.getVersion(folder));
}

fn existRootFolderMarker(root_folder: std.fs.Dir) bool {
    var buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "." ++ public.FolderType.name, .{}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

fn existRootProjectAsset(root_folder: std.fs.Dir) bool {
    var buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "project." ++ public.ProjectType.name, .{}) catch return false;

    var obj_file = root_folder.openFile(path, .{}) catch return false;
    defer obj_file.close();
    return true;
}

fn existFolderMarker(root_folder: std.fs.Dir, dir_name: []const u8) bool {
    var buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/." ++ public.FolderType.name, .{dir_name}) catch return false;

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
    root_path: []const u8,
    tmp_allocator: std.mem.Allocator,
) !void {
    var ws = std.json.writeStream(writer, .{ .whitespace = .indent_2 });
    try ws.beginObject();

    const obj_r = _db.readObj(obj).?;
    var asset_obj: ?cetech1.cdb.ObjId = null;

    try ws.objectField(JSON_ASSET_VERSION);
    try ws.print("\"{s}\"", .{ASSET_CURRENT_VERSION_STR});

    if (obj.type_hash.id == public.AssetType.type_hash.id) {
        asset_obj = public.AssetType.readSubObj(_db, obj_r, .Object);

        try ws.objectField(JSON_ASSET_UUID_TOKEN);
        try ws.print("\"{s}\"", .{try getOrCreateUuid(obj)});

        // TAGS
        const added = public.AssetType.readRefSetAdded(_db, obj_r, .Tags, tmp_allocator);
        defer tmp_allocator.free(added.?);
        if (added != null and added.?.len != 0) {
            try ws.objectField(JSON_TAGS_TOKEN);
            try ws.beginArray();
            for (added.?) |item| {
                try ws.print("\"{s}:{s}\"", .{ _db.getTypeName(item.type_hash).?, try getOrCreateUuid(item) });
            }
            try ws.endArray();
        }
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
        root_path,
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
    root_path: []const u8,
    tmp_allocator: std.mem.Allocator,
) !void {
    const obj_r = _db.readObj(obj).?;
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

    const prop_defs = _db.getTypePropDef(obj.type_hash).?;
    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);
        const has_prototype = !_db.getPrototype(obj_r).isEmpty();
        const property_overided = _db.isPropertyOverrided(obj_r, prop_idx);
        switch (prop_def.type) {
            cetech1.cdb.PropType.BOOL => {
                const value = _db.readValue(bool, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(bool, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == false) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.U64 => {
                const value = _db.readValue(u64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(u64, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.I64 => {
                const value = _db.readValue(i64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(i64, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.U32 => {
                const value = _db.readValue(u32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(u32, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.I32 => {
                const value = _db.readValue(i32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(i32, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.F64 => {
                const value = _db.readValue(f64, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(f64, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.F32 => {
                const value = _db.readValue(f32, obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    const default_value = _db.readValue(f32, _db.readObj(default).?, prop_idx);
                    if (value == default_value) continue;
                } else {
                    if (!has_prototype and value == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.write(value);
            },
            cetech1.cdb.PropType.STR => {
                const str = _db.readStr(obj_r, prop_idx);
                if (str == null) continue;
                if (has_prototype and !property_overided) continue;
                if (!has_prototype and str.?.len == 0) continue;

                if (_db.getDefaultObject(obj.type_hash)) |default| {
                    if (_db.readStr(_db.readObj(default).?, prop_idx)) |default_value| {
                        if (std.mem.eql(u8, str.?, default_value)) continue;
                    }
                } else {
                    if (!has_prototype and str.?.len == 0) continue;
                }

                try writer.objectField(prop_def.name);
                try writer.print("\"{s}\"", .{str.?});
            },
            cetech1.cdb.PropType.BLOB => {
                const blob = _db.readBlob(obj_r, prop_idx);
                if (has_prototype and !property_overided) continue;
                if (blob.len == 0) continue;

                var obj_uuid = try getOrCreateUuid(obj);
                try write_blob(blob, asset, obj_uuid, cetech1.strid.strId32(prop_def.name), root_path, tmp_allocator);

                try writer.objectField(prop_def.name);
                try writer.print("\"{x}{x}\"", .{ cetech1.strid.strId32(&obj_uuid.bytes).id, cetech1.strid.strId32(prop_def.name).id });
            },
            cetech1.cdb.PropType.SUBOBJECT => {
                const subobj = _db.readSubObj(obj_r, prop_idx);
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
                        root_path,
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
                    try writer.print("\"{s}:{s}\"", .{ _db.getTypeName(ref_obj.?.type_hash).?, try getOrCreateUuid(ref_obj.?) });
                }
            },
            cetech1.cdb.PropType.SUBOBJECT_SET => {
                const added = try _db.readSubObjSetAdded(
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
                        try writeCdbObjJsonBody(Writer, item, writer, asset, folder, write_blob, root_path, tmp_allocator);
                        try writer.endObject();
                    }
                    try writer.endArray();
                } else {
                    const deleted_items = _db.readSubObjSetRemoved(obj_r, prop_idx, tmp_allocator);
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
                            try writeCdbObjJsonBody(Writer, item, writer, asset, folder, write_blob, root_path, tmp_allocator);
                            try writer.endObject();
                        }
                        try writer.endArray();
                    }

                    // inisiated
                    if (inisiate_set.count() != 0) {
                        var buff: [128]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_INSTANTIATE_POSTFIX, .{prop_def.name});

                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (inisiate_set.keys()) |item| {
                            try writer.beginObject();
                            try writeCdbObjJsonBody(Writer, item, writer, asset, folder, write_blob, root_path, tmp_allocator);
                            try writer.endObject();
                        }
                        try writer.endArray();
                    }

                    // removed
                    if (deleted_set.count() != 0) {
                        var buff: [128]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
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
                const added = _db.readRefSetAdded(obj_r, @truncate(prop_idx), tmp_allocator);
                defer tmp_allocator.free(added.?);
                if (prototype_id.isEmpty()) {
                    if (added == null or added.?.len == 0) continue;

                    try writer.objectField(prop_def.name);
                    try writer.beginArray();
                    for (added.?) |item| {
                        try writer.print("\"{s}:{s}\"", .{ _db.getTypeName(item.type_hash).?, try getOrCreateUuid(item) });
                    }
                    try writer.endArray();
                } else {
                    const deleted_items = _db.readSubObjSetRemoved(obj_r, prop_idx, tmp_allocator);
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
                            try writer.print("\"{s}:{s}\"", .{ _db.getTypeName(item.type_hash).?, try getOrCreateUuid(item) });
                        }
                        try writer.endArray();
                    }

                    // removed
                    if (deleted_set.count() != 0) {
                        var buff: [128]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                        try writer.objectField(field_name);
                        try writer.beginArray();
                        for (deleted_set.keys()) |item| {
                            try writer.print("\"{s}:{s}\"", .{ _db.getTypeName(item.type_hash).?, try getOrCreateUuid(item) });
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
    const asset_uuid = uuid.api.fromStr(asset_uuid_str.string).?;

    const asset = try getOrCreate(asset_uuid, public.AssetType.type_hash);

    try setAssetNameAndFolder(asset, asset_name, asset_folder);

    const asset_w = _db.writeObj(asset).?;
    if (parsed.value.object.get(JSON_TAGS_TOKEN)) |tags| {
        for (tags.array.items) |tag| {
            var ref_link = std.mem.split(u8, tag.string, ":");
            const ref_type = cetech1.strid.strId32(ref_link.first());
            const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;

            const ref_obj = try getOrCreate(ref_uuid, ref_type);
            try public.AssetType.addRefToSet(_db, asset_w, .Tags, &.{ref_obj});
        }
    }

    const asset_obj = try readCdbObjFromJsonValue(parsed.value, asset, read_blob, tmp_allocator);

    const asset_obj_w = _db.writeObj(asset_obj).?;
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
    const obj = try readCdbObjFromJsonValue(parsed.value, .{}, read_blob, tmp_allocator);
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
    const obj_uuid = uuid.api.fromStr(obj_uuid_str.string).?;
    const obj_type = parsed.object.get(JSON_TYPE_NAME_TOKEN).?;
    const obj_type_hash = cetech1.strid.strId32(obj_type.string);

    const prototype_uuid = parsed.object.get(JSON_PROTOTYPE_UUID);
    var obj: ?cetech1.cdb.ObjId = null;
    if (prototype_uuid == null) {
        obj = try createObject(obj_type_hash);
    } else {
        obj = try createObjectFromPrototypeLocked(uuid.fromStr(prototype_uuid.?.string).?, obj_type_hash);
    }

    const obj_w = _db.writeObj(obj.?).?;

    const prop_defs = _db.getTypePropDef(obj_type_hash).?;

    const keys = parsed.object.keys();
    for (keys) |k| {
        // Skip private fields
        if (std.mem.startsWith(u8, k, "__")) continue;
        if (std.mem.endsWith(u8, k, JSON_REMOVED_POSTFIX)) continue;
        if (std.mem.endsWith(u8, k, JSON_INSTANTIATE_POSTFIX)) continue;

        const value = parsed.object.get(k).?;

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
                const str = try std.fmt.bufPrintZ(&buffer, "{s}", .{value.string});
                try _db.setStr(obj_w, prop_idx, str);
            },
            cetech1.cdb.PropType.BLOB => {
                const blob = try read_blob(asset, obj_uuid, cetech1.strid.strId32(prop_def.name), tmp_allocator);
                defer tmp_allocator.free(blob);
                const true_blob = try _db.createBlob(obj_w, prop_idx, blob.len);
                @memcpy(true_blob.?, blob);
            },
            cetech1.cdb.PropType.SUBOBJECT => {
                const subobj = try readCdbObjFromJsonValue(value, asset, read_blob, tmp_allocator);

                const subobj_w = _db.writeObj(subobj).?;
                try _db.setSubObj(obj_w, prop_idx, subobj_w);
                _db.writeCommit(subobj_w);
            },
            cetech1.cdb.PropType.REFERENCE => {
                var ref_link = std.mem.split(u8, value.string, ":");
                const ref_type = cetech1.strid.strId32(ref_link.first());
                const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;

                const ref_obj = try getOrCreate(ref_uuid, ref_type);

                try _db.setRef(obj_w, prop_idx, ref_obj);
            },
            cetech1.cdb.PropType.SUBOBJECT_SET => {
                for (value.array.items) |subobj_item| {
                    const subobj = try readCdbObjFromJsonValue(subobj_item, asset, read_blob, tmp_allocator);

                    const subobj_w = _db.writeObj(subobj).?;
                    defer _db.writeCommit(subobj_w);
                    try _db.addSubObjToSet(obj_w, prop_idx, &.{subobj_w});
                }
            },
            cetech1.cdb.PropType.REFERENCE_SET => {
                for (value.array.items) |ref| {
                    var ref_link = std.mem.split(u8, ref.string, ":");
                    const ref_type = cetech1.strid.strId32(ref_link.first());
                    const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;

                    const ref_obj = try getOrCreate(ref_uuid, ref_type);
                    try _db.addRefToSet(obj_w, prop_idx, &.{ref_obj});
                }

                if (prototype_uuid != null) {
                    var buff: [128]u8 = undefined;
                    const field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});

                    const removed_fiedl = parsed.object.get(field_name);
                    if (removed_fiedl != null) {
                        for (removed_fiedl.?.array.items) |ref| {
                            var ref_link = std.mem.split(u8, ref.string, ":");
                            const ref_type = cetech1.strid.strId32(ref_link.first());
                            const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;

                            const ref_obj = try getOrCreate(ref_uuid, ref_type);
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
                        const inisiated = parsed.object.get(field_name);
                        if (inisiated != null) {
                            for (inisiated.?.array.items) |subobj_item| {
                                const subobj = try readCdbObjFromJsonValue(subobj_item, asset, read_blob, tmp_allocator);
                                const subobj_w = _db.writeObj(subobj).?;
                                try _db.addSubObjToSet(obj_w, @truncate(prop_idx), &.{subobj_w});

                                const proto_w = _db.writeObj(_db.getPrototype(subobj_w)).?;
                                try _db.removeFromSubObjSet(obj_w, @truncate(prop_idx), @ptrCast(proto_w));

                                _db.writeCommit(proto_w);
                                _db.writeCommit(subobj_w);
                            }
                        }
                    }

                    field_name = try std.fmt.bufPrint(&buff, "{s}" ++ JSON_REMOVED_POSTFIX, .{prop_def.name});
                    const removed = parsed.object.get(field_name);
                    if (removed != null) {
                        for (removed.?.array.items) |ref| {
                            var ref_link = std.mem.split(u8, ref.string, ":");
                            const ref_type = cetech1.strid.strId32(ref_link.first());
                            const ref_uuid = uuid.api.fromStr(ref_link.next().?).?;

                            const ref_obj = try getOrCreate(ref_uuid, ref_type);

                            if (prop_def.type == .REFERENCE_SET) {
                                try _db.removeFromRefSet(obj_w, @truncate(prop_idx), ref_obj);
                            } else {
                                const ref_w = _db.writeObj(ref_obj).?;
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

    const existed_object = getObjId(obj_uuid);

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
    const new_folder = try cetech1.assetdb.FolderType.createObject(db);
    const new_folder_w = db.writeObj(new_folder).?;

    try cetech1.assetdb.FolderType.setRef(db, new_folder_w, .Parent, parent_folder);
    try cetech1.assetdb.FolderType.setStr(db, new_folder_w, .Name, name);

    db.writeCommit(new_folder_w);

    try addFolderToRoot(new_folder);
}

fn saveAsAllAssets(tmp_allocator: std.mem.Allocator, path: []const u8) !void {
    try resetAnalyzedFileInfo();
    try saveAllTo(tmp_allocator, path);
}

fn filerAsset(tmp_allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cetech1.cdb.ObjId) !public.FilteredAssets {
    var result = std.ArrayList(public.FilteredAsset).init(tmp_allocator);
    var buff: [256:0]u8 = undefined;
    var buff2: [256:0]u8 = undefined;

    var filter_set = std.AutoArrayHashMap(cetech1.cdb.ObjId, void).init(tmp_allocator);
    defer filter_set.deinit();

    if (_db.readObj(tags_filter)) |filter_r| {
        if (public.TagsType.readRefSet(_db, filter_r, .Tags, tmp_allocator)) |tags| {
            defer tmp_allocator.free(tags);
            for (tags) |tag| {
                try filter_set.put(tag, {});
            }
        }
    }

    const set = try AssetRootType.readSubObjSet(_db, _db.readObj(_asset_root).?, .Assets, tmp_allocator);
    if (set) |s| {
        defer tmp_allocator.free(s);

        for (s) |obj| {
            if (filter_set.count() != 0) {
                if (_db.readObj(obj)) |asset_r| {
                    if (public.AssetType.readRefSet(_db, asset_r, .Tags, tmp_allocator)) |asset_tags| {
                        defer tmp_allocator.free(asset_tags);

                        var pass_n: u32 = 0;
                        for (asset_tags) |tag| {
                            if (filter_set.contains(tag)) pass_n += 1;
                        }
                        if (pass_n != filter_set.count()) continue;
                    }
                }
            }

            const path = try api.getFilePathForAsset(obj, tmp_allocator);
            defer tmp_allocator.free(path);

            const f = try std.fmt.bufPrintZ(&buff, "{s}", .{filter});
            const p = try std.fmt.bufPrintZ(&buff2, "{s}", .{path});

            const score = editorui.api.uiFilterPass(tmp_allocator, f, p, true) orelse continue;
            try result.append(.{ .score = score, .obj = obj });
        }
    }

    return result.toOwnedSlice();
}

fn onObjidDestroyed(db: *cetech1.cdb.Db, objects: []cetech1.cdb.ObjId) void {
    _uuid2objid_lock.lock();
    defer _uuid2objid_lock.unlock();

    _ = db;

    for (objects) |obj| {
        const obj_uuid = _objid2uuid.get(obj) orelse continue;
        _ = _uuid2objid.swapRemove(obj_uuid);
        _ = _objid2uuid.swapRemove(obj);
        log.api.debug(MODULE_NAME, "Unmaping destroyed objid {any}:{s}", .{ obj, obj_uuid });
    }
}

fn buffGetValidName(allocator: std.mem.Allocator, buf: [:0]u8, db: *cetech1.cdb.CdbDb, folder: cetech1.cdb.ObjId, type_hash: cetech1.strid.StrId32, base_name: [:0]const u8) ![:0]const u8 {
    const set = try db.getReferencerSet(folder, allocator);
    defer allocator.free(set);

    var name_set = std.StringArrayHashMap(void).init(allocator);
    defer name_set.deinit();

    if (type_hash.id != public.FolderType.type_hash.id) {
        for (set) |obj| {
            if (obj.type_hash.id != public.AssetType.type_hash.id) continue;

            const asset_obj = public.AssetType.readSubObj(db, db.readObj(obj).?, .Object).?;
            if (asset_obj.type_hash.id != type_hash.id) continue;

            if (public.AssetType.readStr(db, db.readObj(obj).?, .Name)) |name| {
                try name_set.put(name, {});
            }
        }
    } else {
        for (set) |obj| {
            if (obj.type_hash.id != public.FolderType.type_hash.id) continue;

            if (public.AssetType.readStr(db, db.readObj(obj).?, .Name)) |name| {
                try name_set.put(name, {});
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
