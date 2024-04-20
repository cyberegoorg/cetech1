const std = @import("std");
const cdb = @import("cdb.zig");
const cdb_types = @import("cdb_types.zig");
const task = @import("task.zig");
const strid = @import("strid.zig");
const uuid = @import("uuid.zig");
const system = @import("system.zig");

const log = std.log.scoped(.assetdb);

/// CDB type for asset wraper
pub const Asset = cdb.CdbTypeDecl(
    "ct_asset",
    enum(u32) {
        Name = 0,
        Description,
        Folder,
        Tags,
        Object,
    },
    struct {},
);

/// CDB type for folder
pub const Folder = cdb.CdbTypeDecl(
    "ct_folder",
    enum(u32) {
        Color,
    },
    struct {},
);

/// CDB type for asset/folder tags
pub const Tag = cdb.CdbTypeDecl(
    "ct_tag",
    enum(u32) {
        Name = 0,
        Color,
    },
    struct {},
);

/// CDB type for tags filter or similiar stuff
pub const Tags = cdb.CdbTypeDecl(
    "ct_tags",
    enum(u32) {
        Tags = 0,
    },
    struct {},
);

/// CDB type for project
pub const Project = cdb.CdbTypeDecl(
    "ct_project",
    enum(u32) {
        Name = 0,
        Organization,
    },
    struct {},
);

pub const AssetRootOpenedI = extern struct {
    pub const c_name = "ct_cdb_assetroot_opened_i";
    pub const name_hash = strid.strId64(@This().c_name);

    opened: ?*const fn () anyerror!void,

    pub inline fn implement(comptime T: type) @This() {
        if (!std.meta.hasFn(T, "opened")) @compileError("implement me");

        return @This(){
            .opened = T.opened,
        };
    }
};

/// Asset In/Out interface
/// Use this if you need define your non-cdb assets importer or exporter
pub const AssetIOI = struct {
    /// Can import asset that has this extension?
    canImport: ?*const fn (extension: []const u8) bool,

    /// Can reimport asset?
    canReimport: ?*const fn (db: cdb.Db, asset: cdb.ObjId) bool, //TODO

    /// Can export asset with this extension?
    canExport: ?*const fn (db: cdb.Db, asset: cdb.ObjId, extension: []const u8) bool,

    ///Crete import asset task.
    importAsset: ?*const fn (
        db: cdb.Db,
        prereq: task.TaskID,
        dir: std.fs.Dir,
        folder: cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cdb.ObjId,
    ) anyerror!task.TaskID,

    /// Crete export asset task.
    exportAsset: ?*const fn (
        db: cdb.Db,
        root_path: []const u8,
        sub_path: []const u8,
        asset: cdb.ObjId,
    ) anyerror!task.TaskID,

    /// For implement this interface use this fce and construct your type as anonym struct as param;
    pub inline fn implement(comptime T: type) AssetIOI {
        const hasExport = std.meta.hasFn(T, "exportAsset");
        const hasImport = std.meta.hasFn(T, "importAsset");
        const hasCanImport = std.meta.hasFn(T, "canImport");
        const hasCanReimport = std.meta.hasFn(T, "canReimport");
        const hasCanExport = std.meta.hasFn(T, "canExport");

        if (!hasExport and !hasImport) {
            @compileError("AssetIOI must have least one of importAsset, exportAsset");
        }

        return AssetIOI{
            .canImport = if (hasCanImport) T.canImport else null,
            .canReimport = if (hasCanReimport) T.canReimport else null,
            .canExport = if (hasCanExport) T.canExport else null,
            .importAsset = if (hasImport) T.importAsset else null,
            .exportAsset = if (hasExport) T.exportAsset else null,
        };
    }
};

pub const FilteredAsset = extern struct {
    score: f64,
    obj: cdb.ObjId,

    pub fn lessThan(context: void, a: FilteredAsset, b: FilteredAsset) bool {
        _ = context;
        return a.score < b.score;
    }
};

pub const FilteredAssets = []FilteredAsset;

/// AssetDB main API
/// Asset is CDB object associated with name, folder and is load/save from fs, net etc.
/// Asset act like wraper for real asset object that is store inside "asset" property.
/// AssetDB map UUID to cdbobj if obj  thru it via save/load methods.
pub const AssetDBAPI = struct {
    const Self = @This();

    /// Create new asset with name, folder and probably asset object.
    pub fn createAsset(self: Self, asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId {
        return self.createAssetFn(asset_name, asset_folder, asset_obj);
    }

    /// Open asset root folder, crete basic struct if not exist and load assets.
    pub fn openAssetRootFolder(self: Self, asset_root_path: []const u8, tmp_allocator: std.mem.Allocator) !void {
        try self.openAssetRootFolderFn(asset_root_path, tmp_allocator);
    }

    /// Get root folder object.
    pub fn getRootFolder(self: Self) cdb.ObjId {
        return self.getRootFolderFn();
    }

    /// Get UUID for obj if exist.
    /// Only object that is loaded/saved has UUID
    pub fn getUuid(self: Self, obj: cdb.ObjId) ?uuid.Uuid {
        return self.getUuidFn(obj);
    }

    /// Get or create UUID for obj.
    pub fn getOrCreateUuid(self: Self, obj: cdb.ObjId) !uuid.Uuid {
        return self.getOrCreateUUIDFn(obj);
    }

    /// Get objid for UUID if exist.
    /// Only object that is loaded/saved has UUID
    pub fn getObjId(self: Self, obj_uuid: uuid.Uuid) ?cdb.ObjId {
        return self.getObjIdFn(obj_uuid);
    }

    /// Add AssetIO interface.
    pub fn addAssetIO(self: Self, asset_io: *AssetIOI) void {
        self.addAssetIOFn(asset_io);
    }

    /// Remove AssetIO interface.
    pub fn removeAssetIO(self: Self, asset_io: *AssetIOI) void {
        self.removeAssetIOFn(asset_io);
    }

    /// Add or remove AssetIO interface based on load param.
    pub fn addOrRemoveAssetIO(self: Self, asset_io: *AssetIOI, load: bool) void {
        if (load) self.addAssetIO(asset_io) else self.removeAssetIO(asset_io);
    }

    /// Get path to tmp directory within asset root dir
    pub fn getTmpPath(self: Self, path_buff: []u8) !?[]u8 {
        return try self.getTmpPathFn(path_buff);
    }

    /// Is asset modified?
    pub fn isAssetModified(self: Self, asset: cdb.ObjId) bool {
        return self.isAssetModifiedFn(asset);
    }

    /// Is any asset in project modified?
    pub fn isProjectModified(self: Self) bool {
        return self.isProjectModifiedFn();
    }

    /// Force save all assets.
    pub fn saveAllAssets(self: Self, tmp_allocator: std.mem.Allocator) !void {
        return self.saveAllAssetsFn(tmp_allocator);
    }

    /// Save only modified assets.
    pub fn saveAllModifiedAssets(self: Self, tmp_allocator: std.mem.Allocator) !void {
        return self.saveAllModifiedAssetsFn(tmp_allocator);
    }

    /// Save asset.
    pub fn saveAsset(self: Self, tmp_allocator: std.mem.Allocator, asset: cdb.ObjId) !void {
        return self.saveAssetFn(tmp_allocator, asset);
    }

    isAssetNameValid: *const fn (allocator: std.mem.Allocator, db: cdb.Db, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) anyerror!bool,

    getAssetForObj: *const fn (obj: cdb.ObjId) ?cdb.ObjId,
    getObjForAsset: *const fn (obj: cdb.ObjId) ?cdb.ObjId,
    isAssetFolder: *const fn (obj: cdb.ObjId) bool,
    getFilePathForAsset: *const fn (asset: cdb.ObjId, tmp_allocator: std.mem.Allocator) anyerror![]u8,
    getPathForFolder: *const fn (asset: cdb.ObjId, tmp_allocator: std.mem.Allocator) anyerror![]u8,

    createNewFolder: *const fn (db: cdb.Db, parent_folder: cdb.ObjId, name: [:0]const u8) anyerror!cdb.ObjId,
    filerAsset: *const fn (tmp_allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cdb.ObjId) anyerror!FilteredAssets,
    saveAsAllAssets: *const fn (tmp_allocator: std.mem.Allocator, path: []const u8) anyerror!void,
    deleteAsset: *const fn (db: cdb.Db, asset: cdb.ObjId) anyerror!void,
    deleteFolder: *const fn (db: cdb.Db, folder: cdb.ObjId) anyerror!void,
    isToDeleted: *const fn (asset_or_folder: cdb.ObjId) bool,
    reviveDeleted: *const fn (asset_or_folder: cdb.ObjId) void,
    isProjectOpened: *const fn () bool,

    createNewAssetFromPrototype: *const fn (asset: cdb.ObjId) anyerror!cdb.ObjId,
    cloneNewAssetFrom: *const fn (asset: cdb.ObjId) anyerror!cdb.ObjId,

    openInOs: *const fn (allocator: std.mem.Allocator, open_type: system.OpenInType, asset: cdb.ObjId) anyerror!void,

    isRootFolder: *const fn (db: cdb.Db, asset: cdb.ObjId) bool,
    isAssetObjTypeOf: *const fn (asset: cdb.ObjId, type_idx: cdb.TypeIdx) bool,

    buffGetValidName: *const fn (
        allocator: std.mem.Allocator,
        buf: [:0]u8,
        db: cdb.Db,
        folder: cdb.ObjId,
        type_idx: cdb.TypeIdx,
        base_name: [:0]const u8,
    ) anyerror![:0]const u8,

    //#region Pointers to implementation.
    createAssetFn: *const fn (asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId,
    openAssetRootFolderFn: *const fn (asset_root_path: []const u8, tmp_allocator: std.mem.Allocator) anyerror!void,
    getRootFolderFn: *const fn () cdb.ObjId,
    getObjIdFn: *const fn (obj_uuid: uuid.Uuid) ?cdb.ObjId,
    getUuidFn: *const fn (obj: cdb.ObjId) ?uuid.Uuid,
    getOrCreateUUIDFn: *const fn (obj: cdb.ObjId) anyerror!uuid.Uuid,
    isAssetModifiedFn: *const fn (asset: cdb.ObjId) bool,
    isProjectModifiedFn: *const fn () bool,
    saveAllAssetsFn: *const fn (tmp_allocator: std.mem.Allocator) anyerror!void,
    saveAllModifiedAssetsFn: *const fn (tmp_allocator: std.mem.Allocator) anyerror!void,
    saveAssetFn: *const fn (tmp_allocator: std.mem.Allocator, asset: cdb.ObjId) anyerror!void,
    getTmpPathFn: *const fn ([]u8) anyerror!?[]u8,
    addAssetIOFn: *const fn (asset_io: *AssetIOI) void,
    removeAssetIOFn: *const fn (asset_io: *AssetIOI) void,
    //#endregion
};

// For testing.
pub const FooAsset = cdb_types.BigTypeDecl("ct_foo_asset");
pub const BarAsset = cdb_types.BigTypeDecl("ct_bar_asset");
pub const BazAsset = cdb_types.BigTypeDecl("ct_baz_asset");
