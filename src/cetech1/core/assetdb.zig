const std = @import("std");
const cdb = @import("cdb.zig");
const task = @import("task.zig");
const strid = @import("strid.zig");
const uuid = @import("uuid.zig");

/// CDB type for asset wraper
pub const AssetType = cdb.CdbTypeDecl(
    "ct_asset",
    enum(u32) {
        Name = 0,
        Object,
        Folder,
    },
);

/// CDB type for folder
pub const FolderType = cdb.CdbTypeDecl(
    "ct_asset_folder",
    enum(u32) {
        Name = 0,
        Parent,
    },
);

/// CDB type for project
pub const ProjectType = cdb.CdbTypeDecl(
    "ct_project",
    enum(u32) {
        Name = 0,
        Description,
        Organization,
        Settings,
    },
);

/// Asset In/Out interface
/// Use this if you need define your non-cdb assets importer or exporter
pub const AssetIOI = struct {
    /// Can import asset that has this extension?
    canImport: ?*const fn (extension: []const u8) bool,

    /// Can reimport asset?
    canReimport: ?*const fn (db: *cdb.CdbDb, asset: cdb.ObjId) bool, //TODO

    /// Can export asset with this extension?
    canExport: ?*const fn (db: *cdb.CdbDb, asset: cdb.ObjId, extension: []const u8) bool,

    ///Crete import asset task.
    importAsset: ?*const fn (
        db: *cdb.CdbDb,
        prereq: task.TaskID,
        dir: std.fs.Dir,
        folder: cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cdb.ObjId,
    ) anyerror!task.TaskID,

    /// Crete export asset task.
    exportAsset: ?*const fn (
        db: *cdb.CdbDb,
        sub_path: []const u8,
        asset: cdb.ObjId,
    ) anyerror!task.TaskID,

    /// For implement this interface use this fce and construct your type as anonym struct as param;
    pub fn implement(comptime T: type) AssetIOI {
        const hasExport = std.meta.trait.hasFn("exportAsset");
        const hasImport = std.meta.trait.hasFn("importAsset");
        const hasCanImport = std.meta.trait.hasFn("canImport");
        const hasCanReimport = std.meta.trait.hasFn("canReimport");
        const hasCanExport = std.meta.trait.hasFn("canExport");

        if (!hasExport(T) and !hasImport(T)) {
            @compileError("AssetIOI must have least one of importAsset, exportAsset");
        }

        return AssetIOI{
            .canImport = if (hasCanImport(T)) T.canImport else null,
            .canReimport = if (hasCanReimport(T)) T.canReimport else null,
            .canExport = if (hasCanExport(T)) T.canExport else null,
            .importAsset = if (hasImport(T)) T.importAsset else null,
            .exportAsset = if (hasExport(T)) T.exportAsset else null,
        };
    }
};

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

    /// Get objid for UUID if exist.
    /// Only object that is loaded/saved has UUID
    pub fn getObjId(self: Self, obj_uuid: uuid.Uuid) ?cdb.ObjId {
        return self.getObjIdFn(obj_uuid);
    }

    /// Add AssetIO interface.
    pub fn addAssetIO(self: Self, asset_io: *AssetIOI) void {
        self.addAssetIOFn.?(asset_io);
    }

    /// Remove AssetIO interface.
    pub fn removeAssetIO(self: Self, asset_io: *AssetIOI) void {
        self.removeAssetIOFn.?(asset_io);
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
    pub fn saveAllModifiedAssets(self: *Self, tmp_allocator: std.mem.Allocator) !void {
        return self.saveAllModifiedAssetsFn(tmp_allocator);
    }

    /// Save asset.
    pub fn saveAsset(self: *Self, tmp_allocator: std.mem.Allocator, asset: cdb.ObjId) !void {
        return self.saveAssetFn(tmp_allocator, asset);
    }

    getAssetForObj: *const fn (obj: cdb.ObjId) ?cdb.ObjId,
    isProjectOpened: *const fn () bool,
    getFilePathForAsset: *const fn (asset: cdb.ObjId, tmp_allocator: std.mem.Allocator) anyerror![]u8,

    createNewFolder: *const fn (db: *cdb.CdbDb, parent_folder: cdb.ObjId, name: [:0]const u8) anyerror!void,

    //#region Pointers to implementation.
    createAssetFn: *const fn (asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId,
    openAssetRootFolderFn: *const fn (asset_root_path: []const u8, tmp_allocator: std.mem.Allocator) anyerror!void,
    getRootFolderFn: *const fn () cdb.ObjId,
    getObjIdFn: *const fn (obj_uuid: uuid.Uuid) ?cdb.ObjId,
    getUuidFn: *const fn (obj: cdb.ObjId) ?uuid.Uuid,
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
pub const FooAsset = cdb.BigTypeDecl("ct_foo_asset");
pub const BarAsset = cdb.BigTypeDecl("ct_bar_asset");
pub const BazAsset = cdb.BigTypeDecl("ct_baz_asset");
